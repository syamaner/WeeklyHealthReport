import importlib.util
import os
import re
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


SCRIPT_PATH = Path(__file__).parents[1] / "ci_changes.py"
REPO_ROOT = Path(__file__).parents[3]
SPEC = importlib.util.spec_from_file_location("ci_changes", SCRIPT_PATH)
assert SPEC is not None and SPEC.loader is not None
changes = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = changes
SPEC.loader.exec_module(changes)


class ClassificationTests(unittest.TestCase):
    def test_documentation_only_change_skips_code_ci(self) -> None:
        code, _ = changes.needs_code_ci(
            ["AGENTS.md", "docs/ux-revamp-v1.md", "docs/archive/old.md", ".claude/agents/validator.md"]
        )
        self.assertFalse(code)

    def test_any_code_path_runs_code_ci(self) -> None:
        code, reason = changes.needs_code_ci(["README.md", "WeeklyHealthReport/Views/WeeklyReportView.swift"])
        self.assertTrue(code)
        self.assertIn("WeeklyReportView.swift", reason)

    def test_docs_read_by_code_run_code_ci(self) -> None:
        for path in ("docs/privacy-policy.txt", "docs/food-healthkit-write-plan.md", "docs/fixtures/watch-health-v1.json"):
            with self.subTest(path=path):
                self.assertTrue(changes.needs_code_ci([path])[0])

    def test_markdown_outside_allowlist_runs_code_ci(self) -> None:
        for path in ("Packages/FoodLedgerKit/DEPENDENCIES.md", "Tools/GeminiGroundingEvaluation/holdout-evidence-v2.md", ".github/README.md"):
            with self.subTest(path=path):
                self.assertTrue(changes.needs_code_ci([path])[0])

    def test_empty_change_runs_code_ci(self) -> None:
        self.assertTrue(changes.needs_code_ci([])[0])


class DecisionTests(unittest.TestCase):
    def test_unsupported_event_runs_code_ci(self) -> None:
        self.assertTrue(changes.decide("workflow_dispatch", "a" * 40, "b" * 40)[0])

    def test_missing_or_zero_revisions_run_code_ci(self) -> None:
        self.assertTrue(changes.decide("push", "", "b" * 40)[0])
        self.assertTrue(changes.decide("push", changes.ZERO_SHA, "b" * 40)[0])

    def test_unknown_revisions_run_code_ci(self) -> None:
        self.assertTrue(changes.decide("pull_request", "a" * 40, "b" * 40)[0])

    def test_git_diff_classifies_real_commits(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            run = lambda *args: subprocess.run(["git", *args], cwd=directory, check=True, capture_output=True, text=True).stdout.strip()
            run("init", "-q")
            run("config", "user.email", "ci@example.invalid")
            run("config", "user.name", "CI")
            Path(directory, "README.md").write_text("a\n")
            run("add", ".")
            run("commit", "-q", "-m", "base")
            base = run("rev-parse", "HEAD")
            Path(directory, "docs").mkdir()
            Path(directory, "docs", "note.md").write_text("b\n")
            run("add", ".")
            run("commit", "-q", "-m", "docs")
            docs_head = run("rev-parse", "HEAD")
            Path(directory, "App.swift").write_text("c\n")
            run("add", ".")
            run("commit", "-q", "-m", "code")
            code_head = run("rev-parse", "HEAD")
            original = Path.cwd()
            try:
                os.chdir(directory)
                self.assertFalse(changes.decide("push", base, docs_head)[0])
                self.assertTrue(changes.decide("push", base, code_head)[0])
            finally:
                os.chdir(original)


class DriftGuardTests(unittest.TestCase):
    """Every docs/ path that code, tests or CI mention must force a full run."""

    def test_docs_referenced_outside_documentation_are_classified_as_code(self) -> None:
        tracked = subprocess.run(
            ["git", "ls-files"], cwd=REPO_ROOT, check=True, capture_output=True, text=True
        ).stdout.splitlines()
        existing = set(tracked)
        pattern = re.compile(r"docs/[A-Za-z0-9_./-]+")
        missed = set()
        scanned = (".swift", ".py", ".sh", ".yml", ".yaml", ".json", ".pbxproj", ".plist", ".txt")
        own_files = {"ci_changes.py", "test_ci_changes.py"}
        for path in tracked:
            if not path.endswith(scanned) or changes.is_documentation(path) or Path(path).name in own_files:
                continue
            try:
                text = (REPO_ROOT / path).read_text(encoding="utf-8")
            except (UnicodeDecodeError, OSError):
                continue
            for match in pattern.findall(text):
                reference = match.rstrip("./")
                hits = [p for p in existing if p == reference or p.startswith(reference + "/") or p.startswith(reference)]
                missed.update(p for p in hits if p.startswith("docs/") and changes.is_documentation(p))
        self.assertEqual(sorted(missed), [], "add these to CODE_READ_DOCS or CODE_READ_DOC_PREFIXES")


if __name__ == "__main__":
    unittest.main()
