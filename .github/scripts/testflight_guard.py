#!/usr/bin/env python3
"""Credential-free source guard for the internal TestFlight release workflow.

It runs in a job that has no environment and no secrets, before the protected
`testflight` job can start. Every check fails closed. See
docs/testflight-ci-release-v1.md.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Any, Optional


EXPECTED_REPOSITORY = "syamaner/WeeklyHealthReport"
EXPECTED_REF = "refs/heads/main"
CI_WORKFLOW_FILE = "ios-ci.yml"
SHA_PATTERN = re.compile(r"^[0-9a-f]{40}$")
BUILD_NUMBER_PATTERN = re.compile(r"^[1-9][0-9]{0,5}$")
RELEASE_DOC_PATTERN = re.compile(r"^docs/releases/[A-Za-z0-9._-]+\.md$")
MARKETING_VERSION_PATTERN = re.compile(r"MARKETING_VERSION = ([0-9]+\.[0-9]+(?:\.[0-9]+)?);")
WHAT_TO_TEST_LIMIT = 4000


class GuardError(Exception):
    pass


def check_dispatch(event_name: str, ref: str, repository: str, run_attempt: str, sha: str) -> None:
    if event_name != "workflow_dispatch":
        raise GuardError("the release runs only from a manual workflow_dispatch")
    if repository != EXPECTED_REPOSITORY:
        raise GuardError("the release runs only in the upstream repository, never a fork")
    if ref != EXPECTED_REF:
        raise GuardError("the release runs only from main")
    if run_attempt != "1":
        raise GuardError("re-runs are refused; dispatch again with a fresh build number")
    if not SHA_PATTERN.fullmatch(sha):
        raise GuardError("the workflow SHA is not a full commit SHA")


def check_build_number(build_number: str) -> None:
    if not BUILD_NUMBER_PATTERN.fullmatch(build_number):
        raise GuardError("build number must be a positive integer of at most six digits")


def marketing_version(pbxproj: str) -> str:
    versions = set(MARKETING_VERSION_PATTERN.findall(pbxproj))
    if len(versions) != 1:
        raise GuardError(f"expected exactly one MARKETING_VERSION in the project, found {sorted(versions)}")
    return versions.pop()


def extract_what_to_test(markdown: str) -> str:
    """Return the first ```text block under a '## What to Test' heading."""
    lines = markdown.splitlines()
    in_section = False
    in_block = False
    block: list[str] = []
    for line in lines:
        if line.startswith("## "):
            if in_block:
                break
            in_section = line.lower().startswith("## what to test")
            continue
        if not in_section:
            continue
        if not in_block and line.strip() == "```text":
            in_block = True
            continue
        if in_block:
            if line.strip() == "```":
                text = "\n".join(block).strip()
                if not text:
                    break
                return text
            block.append(line)
    raise GuardError("no ```text block under a '## What to Test' heading in the release document")


def resolve_what_to_test(inline: str, release_doc: str, root: Path) -> str:
    inline = inline.strip()
    release_doc = release_doc.strip()
    if bool(inline) == bool(release_doc):
        raise GuardError("give exactly one of what_to_test or release_doc")
    if release_doc:
        if not RELEASE_DOC_PATTERN.fullmatch(release_doc):
            raise GuardError("release_doc must be a file directly under docs/releases/")
        path = root / release_doc
        if not path.is_file():
            raise GuardError("release_doc does not exist at this commit")
        text = extract_what_to_test(path.read_text(encoding="utf-8"))
    else:
        text = inline
    if len(text) > WHAT_TO_TEST_LIMIT:
        raise GuardError(f"What to Test is longer than {WHAT_TO_TEST_LIMIT} characters")
    return text


def ci_succeeded(runs_payload: Any, sha: str) -> bool:
    runs = runs_payload.get("workflow_runs") if isinstance(runs_payload, dict) else None
    if not isinstance(runs, list):
        raise GuardError("unexpected workflow runs payload")
    return any(
        run.get("head_sha") == sha
        and run.get("event") == "push"
        and run.get("head_branch") == "main"
        and run.get("status") == "completed"
        and run.get("conclusion") == "success"
        for run in runs
        if isinstance(run, dict)
    )


def fetch_ci_runs(repository: str, sha: str, token: str) -> Any:
    query = urllib.parse.urlencode({"head_sha": sha, "branch": "main", "event": "push", "per_page": "100"})
    url = f"https://api.github.com/repos/{repository}/actions/workflows/{CI_WORKFLOW_FILE}/runs?{query}"
    request = urllib.request.Request(url)
    request.add_header("Accept", "application/vnd.github+json")
    request.add_header("X-GitHub-Api-Version", "2022-11-28")
    if token:
        request.add_header("Authorization", "Bearer " + token)
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            return json.load(response)
    except (urllib.error.URLError, json.JSONDecodeError) as error:
        raise GuardError(f"could not read iOS CI runs: {error}") from error


def write_output(path: Optional[str], values: dict[str, str]) -> None:
    if not path:
        return
    with open(path, "a", encoding="utf-8") as handle:
        for key, value in values.items():
            if "\n" in value:
                raise GuardError("refusing a multi-line step output")
            handle.write(f"{key}={value}\n")


def main(argv: Optional[list[str]] = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    sub = parser.add_subparsers(dest="command", required=True)
    source = sub.add_parser("source", help="check the dispatch, inputs, project version and main CI")
    source.add_argument("--root", type=Path, default=Path("."))
    source.add_argument("--skip-ci-check", action="store_true", help="tests only")
    what = sub.add_parser("what-to-test", help="write the resolved What to Test text to a file")
    what.add_argument("--root", type=Path, default=Path("."))
    what.add_argument("--output", type=Path, required=True)
    args = parser.parse_args(argv)

    env = os.environ
    try:
        if args.command == "what-to-test":
            text = resolve_what_to_test(env.get("WHAT_TO_TEST", ""), env.get("RELEASE_DOC", ""), args.root)
            args.output.write_text(text + "\n", encoding="utf-8")
            return 0

        sha = env.get("GITHUB_SHA", "")
        check_dispatch(
            env.get("GITHUB_EVENT_NAME", ""),
            env.get("GITHUB_REF", ""),
            env.get("GITHUB_REPOSITORY", ""),
            env.get("GITHUB_RUN_ATTEMPT", ""),
            sha,
        )
        build_number = env.get("BUILD_NUMBER", "")
        check_build_number(build_number)
        resolve_what_to_test(env.get("WHAT_TO_TEST", ""), env.get("RELEASE_DOC", ""), args.root)
        pbxproj = (args.root / "WeeklyHealthReport.xcodeproj" / "project.pbxproj").read_text(encoding="utf-8")
        version = marketing_version(pbxproj)
        if not args.skip_ci_check:
            runs = fetch_ci_runs(env.get("GITHUB_REPOSITORY", ""), sha, env.get("GITHUB_TOKEN", ""))
            if not ci_succeeded(runs, sha):
                raise GuardError("iOS CI has not succeeded on main for this exact SHA")
        write_output(env.get("GITHUB_OUTPUT"), {"sha": sha, "version": version, "build_number": build_number})
        print(f"source guard passed: {sha} {version} ({build_number})")
        return 0
    except GuardError as error:
        print(f"::error::{error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
