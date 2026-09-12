#!/usr/bin/env python3
"""Report the fail-closed CI mode that a future selective policy would choose.

This script is deliberately advisory. The workflow does not consume its decision to
skip or narrow validation while issue #44 remains in the shadow-policy phase.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Any


API_VERSION = "2022-11-28"
AUTHORITATIVE_CHECK = "Build and test"
SHA_PATTERN = re.compile(r"^[0-9a-f]{40}$")
ZERO_SHA = "0" * 40
ALLOWED_CHANGE_STATUSES = {"added", "modified", "removed"}

DOCUMENTATION_FILES = {
    "AGENTS.md",
    "DEVELOPMENT_NOTES.md",
    "LICENSE",
    "README.md",
}
FULL_PREFIXES = (
    ".github/",
    "Config/",
    "WeeklyHealthReport/HealthKit/",
    "WeeklyHealthReport/Models/",
    "WeeklyHealthReport/Utilities/",
    "WeeklyHealthReport/Views/DeveloperDiagnostics",
    "WeeklyHealthReport/Views/WeeklyReport",
)
FULL_FILES = {
    "WeeklyHealthReport/Info.plist",
    "WeeklyHealthReport/WeeklyHealthReport.entitlements",
    "WeeklyHealthReport/WeeklyHealthReportApp.swift",
    "codecov.yml",
}
FOCUSED_PREFIXES = {
    "notes": ("WeeklyHealthReport/Notes/",),
    "drive": ("WeeklyHealthReport/GoogleDrive/",),
    "synthetic-drive": ("Tools/SyntheticDriveExport/",),
}
FOCUSED_FILES = {
    "WeeklyHealthReport/Views/DailyNotesView.swift": "notes",
    "WeeklyHealthReport/Views/DailyExportView.swift": "drive",
    "WeeklyHealthReportTests/DailyNoteSpeechCaptureTests.swift": "notes",
    "WeeklyHealthReportTests/DailyNotesStoreTests.swift": "notes",
    "WeeklyHealthReportTests/DailyNotesTests.swift": "notes",
    "WeeklyHealthReportTests/DailyDriveExportCoordinatorTests.swift": "drive",
}


class PolicyError(RuntimeError):
    """Raised when live context cannot be collected safely."""


@dataclass(frozen=True)
class Change:
    path: str
    status: str
    previous_path: str | None = None


@dataclass(frozen=True)
class Provenance:
    status: str
    pull_request: int | None = None
    head_sha: str | None = None
    detail: str | None = None


@dataclass(frozen=True)
class Decision:
    mode: str
    reason: str
    focus: str | None
    provenance: Provenance
    actual_gate: str = "full"
    activation: str = "shadow_only"


def _normalise_path(value: Any) -> str:
    if not isinstance(value, str) or not value or value.startswith("/"):
        raise PolicyError("changed path is missing or absolute")
    path = value.replace("\\", "/")
    if any(part in {"", ".", ".."} for part in path.split("/")):
        raise PolicyError(f"changed path is not normalised: {value!r}")
    return path


def parse_changes(raw_files: Any, expected_count: int | None = None) -> list[Change]:
    if not isinstance(raw_files, list):
        raise PolicyError("changed files payload is not an array")
    if expected_count is not None and expected_count != len(raw_files):
        raise PolicyError(
            f"changed files payload is incomplete: expected {expected_count}, "
            f"received {len(raw_files)}"
        )
    if len(raw_files) >= 300:
        raise PolicyError("changed files payload reached the fail-closed API limit")

    changes: list[Change] = []
    for raw in raw_files:
        if not isinstance(raw, dict):
            raise PolicyError("changed file entry is not an object")
        path = _normalise_path(raw.get("filename"))
        status = raw.get("status")
        if not isinstance(status, str):
            raise PolicyError(f"changed file has no status: {path}")
        previous = raw.get("previous_filename")
        changes.append(
            Change(
                path=path,
                status=status,
                previous_path=(
                    _normalise_path(previous) if previous is not None else None
                ),
            )
        )
    return changes


def _path_classification(path: str) -> tuple[str, str | None]:
    if (
        ".xcodeproj/" in path
        or path.endswith("Package.resolved")
        or path.endswith(".xcscheme")
        or path in FULL_FILES
        or path.startswith(FULL_PREFIXES)
    ):
        return ("full", None)
    if path in DOCUMENTATION_FILES or path.startswith("docs/"):
        return ("documentation", None)
    if path in FOCUSED_FILES:
        return ("focused", FOCUSED_FILES[path])
    for focus, prefixes in FOCUSED_PREFIXES.items():
        if path.startswith(prefixes):
            return ("focused", focus)
    if path.startswith("WeeklyHealthReportTests/"):
        return ("full", None)
    return ("full", None)


def classify_paths(changes: list[Change]) -> tuple[str, str, str | None]:
    if not changes:
        return ("full", "no changed paths were available", None)

    classifications: list[tuple[str, str | None]] = []
    for change in changes:
        if (
            change.status not in ALLOWED_CHANGE_STATUSES
            or change.previous_path is not None
        ):
            return (
                "full",
                f"{change.path} has rename, copy, or unknown change metadata",
                None,
            )
        classifications.append(_path_classification(change.path))

    if any(mode == "full" for mode, _focus in classifications):
        return ("full", "shared, infrastructure, or unclassified path changed", None)

    focuses = {
        focus
        for mode, focus in classifications
        if mode == "focused" and focus is not None
    }
    if len(focuses) > 1:
        return ("full", "more than one focused subsystem changed", None)
    if focuses:
        focus = next(iter(focuses))
        return ("focused", f"recognised {focus} subsystem change", focus)
    return ("documentation", "all changed paths are documentation", None)


def verify_merge_provenance(
    event: dict[str, Any],
    pull_requests: Any,
    check_runs_by_head: dict[str, Any],
) -> Provenance:
    before = event.get("before")
    after = event.get("after")
    if event.get("forced") is not False:
        return Provenance(
            "unverified", detail="push was forced or force state is missing"
        )
    if (
        not isinstance(before, str)
        or not SHA_PATTERN.fullmatch(before)
        or before == ZERO_SHA
        or not isinstance(after, str)
        or not SHA_PATTERN.fullmatch(after)
    ):
        return Provenance("unverified", detail="comparison base or head is missing")
    if not isinstance(pull_requests, list):
        return Provenance(
            "unverified", detail="associated pull requests are unavailable"
        )

    matches = [
        pull_request
        for pull_request in pull_requests
        if isinstance(pull_request, dict)
        and pull_request.get("merged_at") is not None
        and pull_request.get("merge_commit_sha") == after
        and pull_request.get("base", {}).get("ref") == "main"
        and pull_request.get("base", {}).get("sha") == before
    ]
    if len(matches) != 1:
        return Provenance(
            "unverified",
            detail=f"expected one exact merged pull request, found {len(matches)}",
        )

    pull_request = matches[0]
    number = pull_request.get("number")
    head_sha = pull_request.get("head", {}).get("sha")
    if not isinstance(number, int) or not isinstance(head_sha, str):
        return Provenance("unverified", detail="pull request identity is incomplete")
    check_payload = check_runs_by_head.get(head_sha)
    if not isinstance(check_payload, dict):
        return Provenance(
            "unverified",
            pull_request=number,
            head_sha=head_sha,
            detail="exact-head check runs are unavailable",
        )
    check_runs = check_payload.get("check_runs")
    if not isinstance(check_runs, list):
        return Provenance(
            "unverified",
            pull_request=number,
            head_sha=head_sha,
            detail="exact-head check runs are malformed",
        )
    authoritative = [
        check
        for check in check_runs
        if isinstance(check, dict)
        and check.get("name") == AUTHORITATIVE_CHECK
        and check.get("head_sha") == head_sha
        and check.get("status") == "completed"
        and check.get("conclusion") == "success"
        and check.get("app", {}).get("slug") == "github-actions"
    ]
    if len(authoritative) != 1:
        return Provenance(
            "unverified",
            pull_request=number,
            head_sha=head_sha,
            detail=(
                "expected one successful exact-head GitHub Actions check named "
                f"{AUTHORITATIVE_CHECK!r}, found {len(authoritative)}"
            ),
        )
    return Provenance("verified", pull_request=number, head_sha=head_sha)


def decide(
    event_name: str,
    event: dict[str, Any],
    changes: list[Change],
    pull_requests: Any = None,
    check_runs_by_head: dict[str, Any] | None = None,
) -> Decision:
    path_mode, path_reason, focus = classify_paths(changes)
    if event_name == "pull_request":
        pull_request = event.get("pull_request")
        if (
            not isinstance(pull_request, dict)
            or pull_request.get("base", {}).get("ref") != "main"
        ):
            return Decision(
                "full",
                "pull request target is missing or is not main",
                None,
                Provenance("pull_request"),
            )
        mode = "documentation" if path_mode == "documentation" else "full"
        reason = path_reason if mode == "documentation" else "executable pull request"
        return Decision(mode, reason, None, Provenance("pull_request"))

    if event_name == "push":
        if event.get("ref") != "refs/heads/main":
            return Decision(
                "full",
                "push target is missing or is not main",
                None,
                Provenance("unverified", detail="unexpected push ref"),
            )
        provenance = verify_merge_provenance(
            event, pull_requests, check_runs_by_head or {}
        )
        if provenance.status != "verified":
            return Decision(
                "full",
                provenance.detail or "merge provenance is unverified",
                None,
                provenance,
            )
        return Decision(path_mode, path_reason, focus, provenance)

    return Decision(
        "full",
        f"unsupported event: {event_name or '<missing>'}",
        None,
        Provenance("unverified", detail="unsupported event"),
    )


class GitHubClient:
    def __init__(self, repository: str, token: str) -> None:
        parts = repository.split("/")
        if len(parts) != 2 or not all(parts):
            raise PolicyError("repository must be OWNER/REPOSITORY")
        if not token:
            raise PolicyError("GitHub token is unavailable")
        self.repository = repository
        self.token = token

    def get(self, path: str) -> Any:
        request = urllib.request.Request(
            f"https://api.github.com/repos/{self.repository}/{path}",
            headers={
                "Accept": "application/vnd.github+json",
                "Authorization": f"Bearer {self.token}",
                "X-GitHub-Api-Version": API_VERSION,
                "User-Agent": "WeeklyHealthReport-shadow-ci-policy",
            },
        )
        try:
            with urllib.request.urlopen(request, timeout=30) as response:
                return json.load(response)
        except (OSError, urllib.error.HTTPError, json.JSONDecodeError) as error:
            raise PolicyError(
                f"GitHub API request failed for {path}: {error}"
            ) from error

    def pull_request_files(self, number: int) -> list[Any]:
        files: list[Any] = []
        for page in range(1, 31):
            payload = self.get(f"pulls/{number}/files?per_page=100&page={page}")
            if not isinstance(payload, list):
                raise PolicyError("pull request files payload is not an array")
            files.extend(payload)
            if len(payload) < 100:
                return files
        raise PolicyError("pull request files exceeded the fail-closed API limit")


def collect_live_context(
    event_name: str,
    event: dict[str, Any],
    client: GitHubClient,
) -> tuple[list[Change], Any, dict[str, Any]]:
    if event_name == "pull_request":
        pull_request = event.get("pull_request")
        if not isinstance(pull_request, dict):
            raise PolicyError("pull request payload is missing")
        number = pull_request.get("number")
        expected_count = pull_request.get("changed_files")
        if not isinstance(number, int) or not isinstance(expected_count, int):
            raise PolicyError("pull request file metadata is incomplete")
        files = client.pull_request_files(number)
        return (parse_changes(files, expected_count), [], {})

    if event_name == "push":
        before = event.get("before")
        after = event.get("after")
        if (
            not isinstance(before, str)
            or not SHA_PATTERN.fullmatch(before)
            or before == ZERO_SHA
            or not isinstance(after, str)
            or not SHA_PATTERN.fullmatch(after)
            or event.get("forced") is not False
        ):
            raise PolicyError("push comparison is missing, invalid, or forced")
        comparison = client.get(f"compare/{before}...{after}")
        if not isinstance(comparison, dict) or comparison.get("status") != "ahead":
            raise PolicyError("push comparison is not a simple forward update")
        if comparison.get("total_commits") != 1:
            raise PolicyError("push does not contain exactly one commit")
        changes = parse_changes(comparison.get("files"))
        pull_requests = client.get(f"commits/{after}/pulls")
        if not isinstance(pull_requests, list):
            raise PolicyError("associated pull requests payload is not an array")

        check_runs_by_head: dict[str, Any] = {}
        for pull_request in pull_requests:
            if not isinstance(pull_request, dict):
                continue
            head_sha = pull_request.get("head", {}).get("sha")
            if isinstance(head_sha, str) and SHA_PATTERN.fullmatch(head_sha):
                encoded_sha = urllib.parse.quote(head_sha, safe="")
                check_runs_by_head[head_sha] = client.get(
                    f"commits/{encoded_sha}/check-runs?per_page=100&filter=latest"
                )
        return (changes, pull_requests, check_runs_by_head)

    raise PolicyError(f"unsupported event: {event_name or '<missing>'}")


def render_markdown(decision: Decision, changes: list[Change]) -> str:
    focus = decision.focus or "None"
    provenance = decision.provenance.status
    if decision.provenance.pull_request is not None:
        provenance += f" (PR #{decision.provenance.pull_request})"
    return "\n".join(
        [
            "## Shadow CI policy",
            "",
            f"Candidate future mode: **{decision.mode}**",
            f"Candidate focus: **{focus}**",
            f"Provenance: **{provenance}**",
            f"Reason: {decision.reason}",
            f"Changed paths inspected: **{len(changes)}**",
            "",
            "Shadow phase: the actual gate remains the complete Xcode analysis, "
            "simulator suite, coverage processing and uploads for every event.",
            "",
        ]
    )


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--event-name", required=True)
    parser.add_argument("--event-json", required=True, type=Path)
    parser.add_argument("--repository", required=True)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--github-step-summary", type=Path)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    try:
        event = json.loads(args.event_json.read_text(encoding="utf-8"))
        if not isinstance(event, dict):
            raise PolicyError("event payload root is not an object")
        client = GitHubClient(args.repository, os.environ.get("GITHUB_TOKEN", ""))
        changes, pull_requests, check_runs = collect_live_context(
            args.event_name, event, client
        )
        decision = decide(args.event_name, event, changes, pull_requests, check_runs)
    except (OSError, json.JSONDecodeError, PolicyError) as error:
        changes = []
        decision = Decision(
            "full",
            f"live context failed closed: {error}",
            None,
            Provenance("unverified", detail=str(error)),
        )

    document = {
        "schema_version": 1,
        "decision": asdict(decision),
        "changes": [asdict(change) for change in changes],
    }
    args.output.write_text(
        json.dumps(document, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    markdown = render_markdown(decision, changes)
    if args.github_step_summary is not None:
        with args.github_step_summary.open("a", encoding="utf-8") as summary_file:
            summary_file.write(markdown)
    print(markdown, end="")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
