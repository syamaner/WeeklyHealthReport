import importlib.util
import sys
import unittest
from pathlib import Path


SCRIPT_PATH = Path(__file__).parents[1] / "summarize_ci_timing.py"
SPEC = importlib.util.spec_from_file_location("summarize_ci_timing", SCRIPT_PATH)
assert SPEC is not None and SPEC.loader is not None
timing = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = timing
SPEC.loader.exec_module(timing)


def typed(value: object) -> dict:
    return {"_value": str(value)}


def activity(
    title: str, duration: float, start: str, children: list | None = None
) -> dict:
    entry = {
        "title": typed(title),
        "duration": typed(duration),
        "startTime": typed(start),
    }
    if children is not None:
        entry["subsections"] = {"_values": children}
    return entry


class ActionStepTimingTests(unittest.TestCase):
    def jobs(self) -> dict:
        steps = []
        for index, name in enumerate(timing.EXPECTED_STEPS):
            steps.append(
                {
                    "name": name,
                    "conclusion": "success",
                    "started_at": f"2026-09-12T12:{index:02d}:00Z",
                    "completed_at": f"2026-09-12T12:{index:02d}:05Z",
                }
            )
        return {"jobs": [{"name": "Build and test", "steps": steps}]}

    def test_extracts_expected_completed_steps_in_stable_order(self) -> None:
        durations = timing.action_step_durations(self.jobs())
        self.assertEqual([row.name for row in durations], list(timing.EXPECTED_STEPS))
        self.assertTrue(all(row.seconds == 5.0 for row in durations))

    def test_missing_or_failed_step_is_rejected(self) -> None:
        missing = self.jobs()
        missing["jobs"][0]["steps"].pop()
        with self.assertRaisesRegex(timing.TimingError, "missing step"):
            timing.action_step_durations(missing)

        failed = self.jobs()
        failed["jobs"][0]["steps"][0]["conclusion"] = "failure"
        with self.assertRaisesRegex(timing.TimingError, "did not complete"):
            timing.action_step_durations(failed)


class XcodeTimingTests(unittest.TestCase):
    def fixtures(self) -> tuple[dict, dict, dict]:
        first_test = activity("Run test case testSlow()", 3.0, "2026-09-12T12:00:13Z")
        first_suite = activity(
            "Run test suite FirstTests",
            3.0,
            "2026-09-12T12:00:13Z",
            [first_test],
        )
        second_test = activity("Run test case testFast()", 1.0, "2026-09-12T12:00:17Z")
        second_suite = activity(
            "Run test suite SecondTests",
            1.0,
            "2026-09-12T12:00:17Z",
            [second_test],
        )
        invocation = {"metrics": {"testsCount": typed(2)}}
        build_log = {
            "sections": [
                activity("Build root", 9.5, "2026-09-12T12:00:00Z"),
                activity("Compile file", 2.0, "2026-09-12T12:00:01Z"),
            ]
        }
        test_log = {
            "sections": [
                activity(
                    "Launch actions",
                    20.0,
                    "2026-09-12T12:00:10Z",
                    [first_suite, second_suite],
                ),
                activity(
                    "WeeklyHealthReport (1234)",
                    4.0,
                    "2026-09-12T12:00:12Z",
                ),
            ]
        }
        return (invocation, build_log, test_log)

    def test_separates_build_launch_preparation_suites_and_tests(self) -> None:
        result = timing.xcode_timings(*self.fixtures())

        self.assertEqual(result["build_activity_seconds"], 9.5)
        self.assertEqual(result["launch_activity_seconds"], 20.0)
        self.assertEqual(result["preparation_to_first_suite_seconds"], 3.0)
        self.assertEqual(result["test_target_seconds"], 4.0)
        self.assertEqual(result["test_count"], 2)
        self.assertEqual(
            [(row["name"], row["test_count"]) for row in result["suites"]],
            [("FirstTests", 1), ("SecondTests", 1)],
        )
        self.assertEqual(result["slowest_tests"][0]["name"], "testSlow()")

    def test_test_count_mismatch_is_rejected(self) -> None:
        invocation, build_log, test_log = self.fixtures()
        invocation["metrics"]["testsCount"] = typed(3)
        with self.assertRaisesRegex(timing.TimingError, "test count mismatch"):
            timing.xcode_timings(invocation, build_log, test_log)

    def test_missing_launch_activity_is_rejected(self) -> None:
        invocation, build_log, test_log = self.fixtures()
        test_log["sections"][0]["title"] = typed("Unknown launch")
        with self.assertRaisesRegex(timing.TimingError, "Launch actions"):
            timing.xcode_timings(invocation, build_log, test_log)

    def test_markdown_states_non_additive_boundary(self) -> None:
        document = {
            "commit": "a" * 40,
            "run_id": "123",
            "steps": [{"name": "Check out repository", "seconds": 2.0}],
            "xcode": timing.xcode_timings(*self.fixtures()),
        }
        markdown = timing.render_markdown(document)
        self.assertIn("must not be added together", markdown)
        self.assertIn("testSlow()", markdown)


if __name__ == "__main__":
    unittest.main()
