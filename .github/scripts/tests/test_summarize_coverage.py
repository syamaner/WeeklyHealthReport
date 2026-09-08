import importlib.util
import sys
import unittest
from pathlib import Path


SCRIPT_PATH = Path(__file__).parents[1] / "summarize_coverage.py"
SPEC = importlib.util.spec_from_file_location("summarize_coverage", SCRIPT_PATH)
assert SPEC is not None and SPEC.loader is not None
coverage = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = coverage
SPEC.loader.exec_module(coverage)


def file(path: str, covered: int, executable: int) -> dict:
    return {
        "path": f"/checkout/WeeklyHealthReport/{path}",
        "coveredLines": covered,
        "executableLines": executable,
    }


class CoverageSummaryTests(unittest.TestCase):
    def test_summarises_expected_layers_and_applies_only_domain_gate(self) -> None:
        report = {
            "targets": [
                {
                    "name": "WeeklyHealthReport.app",
                    "files": [
                        file("Models/ReportPeriod.swift", 95, 100),
                        file("Utilities/HealthReportFormatter.swift", 97, 100),
                        file("Views/WeeklyReportViewModel.swift", 20, 100),
                        file("HealthKit/HealthKitClient.swift", 1, 100),
                        file("Views/WeeklyReportView.swift", 0, 100),
                    ],
                }
            ]
        }

        summaries = coverage.summarise(report, minimum_domain_coverage=95.0)

        self.assertEqual(
            [
                (summary.name, summary.covered_lines, summary.executable_lines)
                for summary in summaries
            ],
            [
                ("App target", 213, 500),
                ("Pure models and formatting", 192, 200),
                ("Report orchestration", 20, 100),
                ("HealthKit client", 1, 100),
            ],
        )
        self.assertTrue(summaries[1].passes)
        self.assertIsNone(summaries[0].minimum_percent)
        self.assertIsNone(summaries[2].minimum_percent)
        self.assertIsNone(summaries[3].minimum_percent)

    def test_domain_regression_fails_the_gate(self) -> None:
        report = {
            "targets": [
                {
                    "name": "WeeklyHealthReport.app",
                    "files": [
                        file("Models/ReportPeriod.swift", 94, 100),
                        file("Utilities/HealthReportFormatter.swift", 95, 100),
                        file("Views/WeeklyReportViewModel.swift", 20, 100),
                        file("HealthKit/HealthKitClient.swift", 1, 100),
                    ],
                }
            ]
        }

        summaries = coverage.summarise(report, minimum_domain_coverage=95.0)

        self.assertFalse(summaries[1].passes)
        self.assertTrue(
            all(
                summary.passes
                for summary in summaries
                if summary is not summaries[1]
            )
        )

    def test_missing_key_layer_fails_closed(self) -> None:
        report = {
            "targets": [
                {
                    "name": "WeeklyHealthReport.app",
                    "files": [
                        file("Models/ReportPeriod.swift", 95, 100),
                        file("Utilities/HealthReportFormatter.swift", 97, 100),
                        file("Views/WeeklyReportViewModel.swift", 20, 100),
                    ],
                }
            ]
        }

        with self.assertRaisesRegex(coverage.CoverageError, "HealthKit client"):
            coverage.summarise(report, minimum_domain_coverage=95.0)


if __name__ == "__main__":
    unittest.main()
