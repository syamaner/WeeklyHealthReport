#!/usr/bin/env python3
"""Summarise Xcode line coverage by repository-owned architectural layer."""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Callable


APP_TARGET = "WeeklyHealthReport.app"


class CoverageError(RuntimeError):
    """Raised when an xcresult cannot provide the expected coverage contract."""


@dataclass(frozen=True)
class Layer:
    name: str
    includes: Callable[[str], bool]
    minimum_percent: float | None = None


@dataclass(frozen=True)
class LayerCoverage:
    name: str
    covered_lines: int
    executable_lines: int
    minimum_percent: float | None

    @property
    def percent(self) -> float:
        return 100.0 * self.covered_lines / self.executable_lines

    @property
    def passes(self) -> bool:
        return self.minimum_percent is None or self.percent >= self.minimum_percent


def load_report(xcresult: Path) -> dict:
    if not xcresult.exists():
        raise CoverageError(f"xcresult does not exist: {xcresult}")

    completed = subprocess.run(
        ["xcrun", "xccov", "view", "--report", "--json", str(xcresult)],
        check=False,
        capture_output=True,
        text=True,
    )
    if completed.returncode != 0:
        detail = completed.stderr.strip() or "xccov returned no diagnostic"
        raise CoverageError(f"xccov failed: {detail}")

    try:
        report = json.loads(completed.stdout)
    except json.JSONDecodeError as error:
        raise CoverageError(f"xccov returned invalid JSON: {error}") from error
    if not isinstance(report, dict):
        raise CoverageError("xccov report root is not an object")
    return report


def summarise(report: dict, minimum_domain_coverage: float) -> list[LayerCoverage]:
    targets = report.get("targets")
    if not isinstance(targets, list):
        raise CoverageError("xccov report has no targets")

    target = next(
        (candidate for candidate in targets if candidate.get("name") == APP_TARGET),
        None,
    )
    if target is None:
        raise CoverageError(f"xccov report has no {APP_TARGET} target")

    files = target.get("files")
    if not isinstance(files, list):
        raise CoverageError(f"{APP_TARGET} has no file coverage")

    layers = [
        Layer("App target", lambda _path: True),
        Layer(
            "Pure models and formatting",
            lambda path: "/WeeklyHealthReport/Models/" in path
            or "/WeeklyHealthReport/Utilities/" in path,
            minimum_domain_coverage,
        ),
        Layer(
            "Report orchestration",
            lambda path: path.endswith(
                "/WeeklyHealthReport/Views/WeeklyReportViewModel.swift"
            ),
        ),
        Layer(
            "HealthKit client",
            lambda path: path.endswith(
                "/WeeklyHealthReport/HealthKit/HealthKitClient.swift"
            ),
        ),
    ]

    summaries: list[LayerCoverage] = []
    for layer in layers:
        matching_files = [
            file
            for file in files
            if isinstance(file.get("path"), str)
            and layer.includes(file["path"].replace("\\", "/"))
        ]
        if not matching_files:
            raise CoverageError(f"coverage layer matched no files: {layer.name}")

        try:
            covered_lines = sum(int(file["coveredLines"]) for file in matching_files)
            executable_lines = sum(
                int(file["executableLines"]) for file in matching_files
            )
        except (KeyError, TypeError, ValueError) as error:
            raise CoverageError(
                f"coverage layer has invalid line counts: {layer.name}"
            ) from error
        if executable_lines <= 0:
            raise CoverageError(
                f"coverage layer has no executable lines: {layer.name}"
            )

        summaries.append(
            LayerCoverage(
                name=layer.name,
                covered_lines=covered_lines,
                executable_lines=executable_lines,
                minimum_percent=layer.minimum_percent,
            )
        )
    return summaries


def render_markdown(commit: str, summaries: list[LayerCoverage]) -> str:
    rows = []
    for summary in summaries:
        if summary.minimum_percent is None:
            gate = "Informational"
        else:
            result = "Pass" if summary.passes else "Fail"
            gate = f"{result} (minimum {summary.minimum_percent:.1f}%)"
        rows.append(
            f"| {summary.name} | {summary.covered_lines:,} / "
            f"{summary.executable_lines:,} | {summary.percent:.2f}% | {gate} |"
        )

    overall_result = "passed" if all(summary.passes for summary in summaries) else "failed"
    return "\n".join(
        [
            "## Code coverage",
            "",
            f"Reviewed commit: `{commit}`",
            "",
            "| Layer | Covered / executable lines | Line coverage | Gate |",
            "| --- | ---: | ---: | --- |",
            *rows,
            "",
            f"Coverage gate: **{overall_result}**.",
            "",
            "Only pure models and formatting are regression-gated. The app total and "
            "orchestration rows are visible context: SwiftUI-generated executable lines "
            "and framework-bound HealthKit code are not treated as equivalent to pure "
            "domain logic.",
            "",
            "This is unsigned simulator coverage. It does not exercise HealthKit "
            "permission, personal health data, or physical-device behaviour.",
            "",
        ]
    )


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--xcresult", required=True, type=Path)
    parser.add_argument("--commit", required=True)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--github-step-summary", type=Path)
    parser.add_argument("--minimum-domain-coverage", type=float, default=95.0)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if not 0.0 <= args.minimum_domain_coverage <= 100.0:
        print("minimum domain coverage must be between 0 and 100", file=sys.stderr)
        return 2

    try:
        summaries = summarise(
            load_report(args.xcresult), args.minimum_domain_coverage
        )
    except CoverageError as error:
        print(f"coverage summary failed: {error}", file=sys.stderr)
        return 2

    markdown = render_markdown(args.commit, summaries)
    args.output.write_text(markdown, encoding="utf-8")
    if args.github_step_summary is not None:
        with args.github_step_summary.open("a", encoding="utf-8") as summary_file:
            summary_file.write(markdown)
    print(markdown, end="")
    return 0 if all(summary.passes for summary in summaries) else 1


if __name__ == "__main__":
    raise SystemExit(main())
