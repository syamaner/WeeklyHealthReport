#!/usr/bin/env python3
"""Decide whether a change needs the code CI jobs, failing closed to a full run.

Only an explicit, fully classified documentation-only change sets ``code=false``.
Any error, unknown path, missing revision or unexpected event sets ``code=true``.
"""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
from pathlib import Path

SHA_PATTERN = re.compile(r"^[0-9a-f]{40}$")
ZERO_SHA = "0" * 40

# Files that only people and agents read. Keep this list narrow: Markdown under
# Tools/ or Packages/ can be test data or checked inventory, so it is not here.
DOCUMENTATION_FILES = {
    "AGENTS.md",
    "CLAUDE.md",
    "DEVELOPMENT_NOTES.md",
    "LICENSE",
    "README.md",
}
DOCUMENTATION_PREFIXES = (
    ".agents/",
    ".claude/",
    "docs/",
)
# Paths under docs/ that code, tests or CI read. They always need a full run.
CODE_READ_DOCS = {
    "docs/food-healthkit-write-plan.md",
    "docs/privacy-policy.txt",
}
CODE_READ_DOC_PREFIXES = ("docs/fixtures/",)


def is_documentation(path: str) -> bool:
    if path in CODE_READ_DOCS or path.startswith(CODE_READ_DOC_PREFIXES):
        return False
    return path in DOCUMENTATION_FILES or path.startswith(DOCUMENTATION_PREFIXES)


def needs_code_ci(paths: list[str]) -> tuple[bool, str]:
    if not paths:
        return True, "no changed paths were found"
    code = sorted(p for p in paths if not is_documentation(p))
    if code:
        sample = ", ".join(code[:5]) + (" …" if len(code) > 5 else "")
        return True, f"{len(code)} non-documentation path(s): {sample}"
    return False, f"{len(paths)} documentation-only path(s)"


def changed_paths(base: str, head: str, three_dot: bool) -> list[str]:
    spec = f"{base}...{head}" if three_dot else f"{base}..{head}"
    output = subprocess.run(
        ["git", "diff", "--no-renames", "--name-only", spec],
        check=True,
        capture_output=True,
        text=True,
    ).stdout
    return [line for line in output.splitlines() if line]


def decide(event_name: str, base: str, head: str) -> tuple[bool, str]:
    if event_name not in {"pull_request", "push"}:
        return True, f"unsupported event {event_name!r}"
    if not SHA_PATTERN.match(base) or not SHA_PATTERN.match(head) or base == ZERO_SHA:
        return True, "missing or invalid comparison revisions"
    try:
        paths = changed_paths(base, head, three_dot=event_name == "pull_request")
    except (OSError, subprocess.CalledProcessError) as error:
        return True, f"git diff failed: {error}"
    return needs_code_ci(paths)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--event-name", required=True)
    parser.add_argument("--base", default="")
    parser.add_argument("--head", default="")
    parser.add_argument("--github-output", type=Path)
    args = parser.parse_args()
    try:
        code, reason = decide(args.event_name, args.base, args.head)
    except Exception as error:  # noqa: BLE001 - any failure must run full CI
        code, reason = True, f"classifier error: {error}"
    line = f"code={'true' if code else 'false'}"
    print(f"{line} ({reason})")
    if args.github_output:
        with args.github_output.open("a", encoding="utf-8") as handle:
            handle.write(line + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
