#!/usr/bin/env python3
"""Extract deterministic CI timing evidence from Actions and an Xcode result."""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from dataclasses import asdict, dataclass
from datetime import datetime
from pathlib import Path
from typing import Any, Iterator


EXPECTED_STEPS = (
    "Check out repository",
    "Evaluate shadow CI policy",
    "Resolve Swift packages",
    "Select an available iPhone simulator",
    "Validate CI helpers",
    "Run Xcode static analysis",
    "Run unit tests with code coverage",
    "Summarise code coverage",
    "Upload app coverage to Codecov",
    "Upload test and coverage results",
)
TEST_TARGET_PATTERN = re.compile(r"^WeeklyHealthReport \(\d+\)$")


class TimingError(RuntimeError):
    """Raised when timing evidence is missing or structurally unsafe to use."""


@dataclass(frozen=True)
class NamedDuration:
    name: str
    seconds: float
    test_count: int | None = None


def _parse_timestamp(value: Any, context: str) -> datetime:
    if not isinstance(value, str):
        raise TimingError(f"{context} timestamp is missing")
    try:
        return datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError as error:
        raise TimingError(f"{context} timestamp is invalid: {value}") from error


def _duration(start: Any, end: Any, context: str) -> float:
    seconds = (
        _parse_timestamp(end, context) - _parse_timestamp(start, context)
    ).total_seconds()
    if seconds < 0:
        raise TimingError(f"{context} has a negative duration")
    return seconds


def action_step_durations(jobs_payload: dict[str, Any]) -> list[NamedDuration]:
    jobs = jobs_payload.get("jobs")
    if not isinstance(jobs, list):
        raise TimingError("Actions jobs payload has no jobs array")
    matches = [job for job in jobs if job.get("name") == "Build and test"]
    if len(matches) != 1:
        raise TimingError(f"expected one Build and test job, found {len(matches)}")
    steps = matches[0].get("steps")
    if not isinstance(steps, list):
        raise TimingError("Build and test job has no steps array")
    by_name = {step.get("name"): step for step in steps if isinstance(step, dict)}

    durations = []
    for name in EXPECTED_STEPS:
        step = by_name.get(name)
        if not isinstance(step, dict):
            raise TimingError(f"Actions timing is missing step: {name}")
        if step.get("conclusion") != "success":
            raise TimingError(f"Actions step did not complete successfully: {name}")
        durations.append(
            NamedDuration(
                name,
                _duration(step.get("started_at"), step.get("completed_at"), name),
            )
        )
    return durations


def _typed_value(value: Any) -> Any:
    if isinstance(value, dict) and "_value" in value:
        return value["_value"]
    return None


def _objects(value: Any) -> Iterator[dict[str, Any]]:
    if isinstance(value, dict):
        yield value
        for child in value.values():
            yield from _objects(child)
    elif isinstance(value, list):
        for child in value:
            yield from _objects(child)


def _title(entry: dict[str, Any]) -> str | None:
    value = _typed_value(entry.get("title"))
    return value if isinstance(value, str) else None


def _seconds(entry: dict[str, Any], context: str) -> float:
    value = _typed_value(entry.get("duration"))
    try:
        seconds = float(value)
    except (TypeError, ValueError) as error:
        raise TimingError(f"{context} duration is invalid") from error
    if seconds < 0:
        raise TimingError(f"{context} duration is negative")
    return seconds


def _start(entry: dict[str, Any], context: str) -> datetime:
    return _parse_timestamp(_typed_value(entry.get("startTime")), context)


def _reference_id(container: dict[str, Any], key: str) -> str:
    reference = container.get(key)
    if not isinstance(reference, dict):
        raise TimingError(f"xcresult has no {key}")
    value = _typed_value(reference.get("id"))
    if not isinstance(value, str) or not value:
        raise TimingError(f"xcresult {key} has no identifier")
    return value


def _run_xcresulttool(xcresult: Path, identifier: str | None = None) -> dict[str, Any]:
    command = [
        "xcrun",
        "xcresulttool",
        "get",
        "--legacy",
        "--path",
        str(xcresult),
        "--format",
        "json",
    ]
    if identifier is not None:
        command.extend(["--id", identifier])
    completed = subprocess.run(command, check=False, capture_output=True, text=True)
    if completed.returncode != 0:
        detail = completed.stderr.strip() or "xcresulttool returned no diagnostic"
        raise TimingError(f"xcresulttool failed: {detail}")
    try:
        payload = json.loads(completed.stdout)
    except json.JSONDecodeError as error:
        raise TimingError(f"xcresulttool returned invalid JSON: {error}") from error
    if not isinstance(payload, dict):
        raise TimingError("xcresulttool result root is not an object")
    return payload


def load_xcode_payloads(
    xcresult: Path,
) -> tuple[dict[str, Any], dict[str, Any], dict[str, Any]]:
    if not xcresult.exists():
        raise TimingError(f"xcresult does not exist: {xcresult}")
    invocation = _run_xcresulttool(xcresult)
    actions = invocation.get("actions", {}).get("_values")
    if not isinstance(actions, list) or len(actions) != 1:
        count = len(actions) if isinstance(actions, list) else 0
        raise TimingError(f"expected one xcresult action, found {count}")
    action = actions[0]
    if not isinstance(action, dict):
        raise TimingError("xcresult action is malformed")
    action_result = action.get("actionResult")
    build_result = action.get("buildResult")
    if not isinstance(action_result, dict) or not isinstance(build_result, dict):
        raise TimingError("xcresult action has no build or test result")
    if action_result.get("status", {}).get("_value") != "succeeded":
        raise TimingError("xcresult test action did not succeed")
    if build_result.get("status", {}).get("_value") != "succeeded":
        raise TimingError("xcresult build action did not succeed")
    build_log = _run_xcresulttool(xcresult, _reference_id(build_result, "logRef"))
    test_log = _run_xcresulttool(xcresult, _reference_id(action_result, "logRef"))
    return (invocation, build_log, test_log)


def _unique_activity_entries(
    payload: dict[str, Any], predicate: Any
) -> list[dict[str, Any]]:
    entries: list[dict[str, Any]] = []
    seen: set[tuple[str, str, str]] = set()
    for entry in _objects(payload):
        title = _title(entry)
        duration = _typed_value(entry.get("duration"))
        start = _typed_value(entry.get("startTime"))
        if title is None or duration is None or start is None or not predicate(title):
            continue
        identity = (title, str(duration), str(start))
        if identity not in seen:
            seen.add(identity)
            entries.append(entry)
    return entries


def xcode_timings(
    invocation: dict[str, Any],
    build_log: dict[str, Any],
    test_log: dict[str, Any],
) -> dict[str, Any]:
    build_entries = _unique_activity_entries(build_log, lambda _title: True)
    if not build_entries:
        raise TimingError("xcresult build log has no timed activity")
    build_activity = max(_seconds(entry, "build activity") for entry in build_entries)

    launch_entries = _unique_activity_entries(
        test_log, lambda title: title == "Launch actions"
    )
    if len(launch_entries) != 1:
        raise TimingError(
            f"expected one Launch actions activity, found {len(launch_entries)}"
        )
    launch = launch_entries[0]

    target_entries = _unique_activity_entries(
        test_log, lambda title: TEST_TARGET_PATTERN.fullmatch(title) is not None
    )
    if len(target_entries) != 1:
        raise TimingError(
            f"expected one WeeklyHealthReport test target activity, found {len(target_entries)}"
        )

    suite_entries = _unique_activity_entries(
        test_log, lambda title: title.startswith("Run test suite ")
    )
    test_entries = _unique_activity_entries(
        test_log, lambda title: title.startswith("Run test case ")
    )
    if not suite_entries or not test_entries:
        raise TimingError("xcresult has no timed test suites or test cases")

    suite_rows = []
    for suite in suite_entries:
        suite_title = _title(suite)
        assert suite_title is not None
        nested_tests = _unique_activity_entries(
            suite, lambda title: title.startswith("Run test case ")
        )
        suite_rows.append(
            NamedDuration(
                suite_title.removeprefix("Run test suite "),
                _seconds(suite, suite_title),
                len(nested_tests),
            )
        )
    suite_rows.sort(key=lambda row: (-row.seconds, row.name))

    slowest_tests = [
        NamedDuration(
            (_title(entry) or "").removeprefix("Run test case "),
            _seconds(entry, _title(entry) or "test case"),
        )
        for entry in test_entries
    ]
    slowest_tests.sort(key=lambda row: (-row.seconds, row.name))

    launch_start = _start(launch, "Launch actions")
    first_suite_start = min(
        _start(entry, _title(entry) or "test suite") for entry in suite_entries
    )
    preparation_seconds = (first_suite_start - launch_start).total_seconds()
    if preparation_seconds < 0:
        raise TimingError("first test suite starts before launch activity")

    test_count = _typed_value(invocation.get("metrics", {}).get("testsCount"))
    try:
        parsed_test_count = int(test_count)
    except (TypeError, ValueError) as error:
        raise TimingError("xcresult test count is invalid") from error
    if parsed_test_count != len(test_entries):
        raise TimingError(
            f"xcresult test count mismatch: expected {parsed_test_count}, "
            f"found {len(test_entries)} timed tests"
        )

    return {
        "build_activity_seconds": round(build_activity, 3),
        "launch_activity_seconds": round(_seconds(launch, "Launch actions"), 3),
        "preparation_to_first_suite_seconds": round(preparation_seconds, 3),
        "test_target_seconds": round(
            _seconds(target_entries[0], "WeeklyHealthReport test target"), 3
        ),
        "test_count": parsed_test_count,
        "suites": [asdict(row) for row in suite_rows],
        "slowest_tests": [asdict(row) for row in slowest_tests[:10]],
    }


def render_markdown(document: dict[str, Any]) -> str:
    steps = document["steps"]
    xcode = document["xcode"]
    lines = [
        "## CI timing",
        "",
        f"Measured commit: `{document['commit']}`",
        f"Workflow run: `{document['run_id']}`",
        "",
        "| GitHub Actions step | Seconds |",
        "| --- | ---: |",
    ]
    lines.extend(f"| {row['name']} | {row['seconds']:.1f} |" for row in steps)
    lines.extend(
        [
            "",
            "| Xcode result activity | Seconds |",
            "| --- | ---: |",
            f"| Build activity | {xcode['build_activity_seconds']:.1f} |",
            f"| Launch/test-host activity | {xcode['launch_activity_seconds']:.1f} |",
            "| Preparation from launch activity to first suite | "
            f"{xcode['preparation_to_first_suite_seconds']:.1f} |",
            f"| Named test bodies ({xcode['test_count']} tests) | "
            f"{xcode['test_target_seconds']:.1f} |",
            "",
            "### Slowest suites",
            "",
            "| Suite | Tests | Seconds |",
            "| --- | ---: | ---: |",
        ]
    )
    lines.extend(
        f"| {row['name']} | {row['test_count']} | {row['seconds']:.1f} |"
        for row in xcode["suites"][:10]
    )
    lines.extend(
        [
            "",
            "### Slowest tests",
            "",
            "| Test | Seconds |",
            "| --- | ---: |",
        ]
    )
    lines.extend(
        f"| {row['name']} | {row['seconds']:.1f} |" for row in xcode["slowest_tests"]
    )
    lines.extend(
        [
            "",
            "Build, launch and test activities can overlap inside Xcode; they must not "
            "be added together. Preparation-to-first-suite is an observable boundary, "
            "not proof that every second was simulator startup.",
            "",
        ]
    )
    return "\n".join(lines)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--jobs-json", required=True, type=Path)
    parser.add_argument("--xcresult", required=True, type=Path)
    parser.add_argument("--commit", required=True)
    parser.add_argument("--run-id", required=True)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--markdown-output", required=True, type=Path)
    parser.add_argument("--github-step-summary", type=Path)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    try:
        jobs_payload = json.loads(args.jobs_json.read_text(encoding="utf-8"))
        if not isinstance(jobs_payload, dict):
            raise TimingError("Actions jobs payload root is not an object")
        invocation, build_log, test_log = load_xcode_payloads(args.xcresult)
        document = {
            "schema_version": 1,
            "commit": args.commit,
            "run_id": args.run_id,
            "steps": [asdict(row) for row in action_step_durations(jobs_payload)],
            "xcode": xcode_timings(invocation, build_log, test_log),
        }
    except (OSError, json.JSONDecodeError, TimingError) as error:
        print(f"CI timing summary failed: {error}", file=sys.stderr)
        return 2

    args.output.write_text(
        json.dumps(document, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    markdown = render_markdown(document)
    args.markdown_output.write_text(markdown, encoding="utf-8")
    if args.github_step_summary is not None:
        with args.github_step_summary.open("a", encoding="utf-8") as summary_file:
            summary_file.write(markdown)
    print(markdown, end="")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
