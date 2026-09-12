import importlib.util
import sys
import unittest
from pathlib import Path


SCRIPT_PATH = Path(__file__).parents[1] / "ci_policy.py"
SPEC = importlib.util.spec_from_file_location("ci_policy", SCRIPT_PATH)
assert SPEC is not None and SPEC.loader is not None
policy = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = policy
SPEC.loader.exec_module(policy)


BEFORE = "1" * 40
AFTER = "2" * 40
HEAD = "3" * 40


def change(path: str, status: str = "modified", **extra: str) -> dict:
    return {"filename": path, "status": status, **extra}


def push_event(**overrides: object) -> dict:
    event = {
        "before": BEFORE,
        "after": AFTER,
        "forced": False,
        "ref": "refs/heads/main",
    }
    event.update(overrides)
    return event


def exact_pull_request(**overrides: object) -> dict:
    pull_request = {
        "number": 44,
        "merged_at": "2026-09-12T12:00:00Z",
        "merge_commit_sha": AFTER,
        "base": {"ref": "main", "sha": BEFORE},
        "head": {"sha": HEAD},
    }
    pull_request.update(overrides)
    return pull_request


def successful_checks(**overrides: object) -> dict:
    check = {
        "name": "Build and test",
        "head_sha": HEAD,
        "status": "completed",
        "conclusion": "success",
        "app": {"slug": "github-actions"},
    }
    check.update(overrides)
    return {HEAD: {"check_runs": [check]}}


class PathClassificationTests(unittest.TestCase):
    def classify(self, *raw_changes: dict) -> tuple[str, str | None]:
        changes = policy.parse_changes(list(raw_changes))
        mode, _reason, focus = policy.classify_paths(changes)
        return (mode, focus)

    def test_documentation_only(self) -> None:
        self.assertEqual(
            self.classify(change("README.md"), change("docs/ci.md")),
            ("documentation", None),
        )

    def test_notes_ui_and_implementation_are_one_focused_subsystem(self) -> None:
        self.assertEqual(
            self.classify(
                change("WeeklyHealthReport/Views/DailyNotesView.swift"),
                change("WeeklyHealthReport/Notes/DailyNotesStore.swift"),
            ),
            ("focused", "notes"),
        )

    def test_drive_and_synthetic_harness_are_not_combined(self) -> None:
        self.assertEqual(
            self.classify(
                change("WeeklyHealthReport/GoogleDrive/DailyDriveTransport.swift"),
                change("Tools/SyntheticDriveExport/DriveAPI.swift"),
            ),
            ("full", None),
        )

    def test_report_model_and_healthkit_changes_are_full(self) -> None:
        for path in (
            "WeeklyHealthReport/Models/ReportPeriod.swift",
            "WeeklyHealthReport/HealthKit/HealthKitClient.swift",
            "WeeklyHealthReport/Views/WeeklyReportView.swift",
        ):
            with self.subTest(path=path):
                self.assertEqual(self.classify(change(path)), ("full", None))

    def test_test_infrastructure_project_workflow_and_policy_are_full(self) -> None:
        for path in (
            "WeeklyHealthReportTests/ReportPeriodTests.swift",
            "WeeklyHealthReport.xcodeproj/project.pbxproj",
            ".github/workflows/ios-ci.yml",
            ".github/scripts/ci_policy.py",
        ):
            with self.subTest(path=path):
                self.assertEqual(self.classify(change(path)), ("full", None))

    def test_unknown_path_is_full(self) -> None:
        self.assertEqual(self.classify(change("Unexpected/new.swift")), ("full", None))

    def test_rename_and_copy_metadata_are_full(self) -> None:
        for status, extra in (
            ("renamed", {"previous_filename": "docs/old.md"}),
            ("copied", {"previous_filename": "docs/source.md"}),
        ):
            with self.subTest(status=status):
                self.assertEqual(
                    self.classify(change("docs/new.md", status, **extra)),
                    ("full", None),
                )

    def test_empty_and_incomplete_file_lists_fail_closed(self) -> None:
        self.assertEqual(policy.classify_paths([])[0], "full")
        with self.assertRaisesRegex(policy.PolicyError, "incomplete"):
            policy.parse_changes([change("README.md")], expected_count=2)


class ProvenanceTests(unittest.TestCase):
    def verified(self, **event_overrides: object) -> policy.Provenance:
        return policy.verify_merge_provenance(
            push_event(**event_overrides),
            [exact_pull_request()],
            successful_checks(),
        )

    def test_exact_merged_pr_and_exact_head_check_are_verified(self) -> None:
        provenance = self.verified()
        self.assertEqual(provenance.status, "verified")
        self.assertEqual(provenance.pull_request, 44)
        self.assertEqual(provenance.head_sha, HEAD)

    def test_force_push_missing_base_and_ambiguous_pr_fail_closed(self) -> None:
        self.assertEqual(self.verified(forced=True).status, "unverified")
        self.assertEqual(self.verified(before="0" * 40).status, "unverified")
        ambiguous = policy.verify_merge_provenance(
            push_event(),
            [exact_pull_request(), exact_pull_request(number=45)],
            successful_checks(),
        )
        self.assertEqual(ambiguous.status, "unverified")

    def test_wrong_base_or_merge_sha_fails_closed(self) -> None:
        for pull_request in (
            exact_pull_request(base={"ref": "other", "sha": BEFORE}),
            exact_pull_request(merge_commit_sha="4" * 40),
        ):
            with self.subTest(pull_request=pull_request):
                provenance = policy.verify_merge_provenance(
                    push_event(), [pull_request], successful_checks()
                )
                self.assertEqual(provenance.status, "unverified")

    def test_missing_failed_or_wrong_app_check_fails_closed(self) -> None:
        payloads = (
            {},
            successful_checks(conclusion="failure"),
            successful_checks(app={"slug": "other"}),
        )
        for checks in payloads:
            with self.subTest(checks=checks):
                provenance = policy.verify_merge_provenance(
                    push_event(), [exact_pull_request()], checks
                )
                self.assertEqual(provenance.status, "unverified")


class DecisionTests(unittest.TestCase):
    def test_executable_pr_is_full_even_when_path_is_focusable(self) -> None:
        decision = policy.decide(
            "pull_request",
            {"pull_request": {"base": {"ref": "main"}}},
            policy.parse_changes(
                [change("WeeklyHealthReport/Notes/DailyNotesStore.swift")]
            ),
        )
        self.assertEqual(decision.mode, "full")
        self.assertEqual(decision.actual_gate, "full")
        self.assertEqual(decision.activation, "shadow_only")

    def test_documentation_pr_is_candidate_documentation_but_actual_gate_is_full(
        self,
    ) -> None:
        decision = policy.decide(
            "pull_request",
            {"pull_request": {"base": {"ref": "main"}}},
            policy.parse_changes([change("README.md")]),
        )
        self.assertEqual(decision.mode, "documentation")
        self.assertEqual(decision.actual_gate, "full")

    def test_verified_main_merge_can_report_focused_candidate(self) -> None:
        decision = policy.decide(
            "push",
            push_event(),
            policy.parse_changes(
                [change("WeeklyHealthReport/Notes/DailyNotesStore.swift")]
            ),
            [exact_pull_request()],
            successful_checks(),
        )
        self.assertEqual((decision.mode, decision.focus), ("focused", "notes"))
        self.assertEqual(decision.actual_gate, "full")

    def test_direct_or_unverified_main_push_is_full(self) -> None:
        decision = policy.decide(
            "push",
            push_event(),
            policy.parse_changes([change("README.md")]),
            [],
            {},
        )
        self.assertEqual(decision.mode, "full")
        self.assertEqual(decision.provenance.status, "unverified")

    def test_unsupported_event_is_full(self) -> None:
        decision = policy.decide(
            "workflow_dispatch", {}, policy.parse_changes([change("README.md")])
        )
        self.assertEqual(decision.mode, "full")


if __name__ == "__main__":
    unittest.main()
