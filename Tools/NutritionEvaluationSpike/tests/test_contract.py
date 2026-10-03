import copy
import importlib.util
import json
import sys
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(HERE))
from scoring import complete_roster, safeguard_rows
from assertions import get_assert


class Contracts(unittest.TestCase):
    def test_missing_duplicate_extra_predictions_cannot_pass(self):
        for rows in ([], [{"id": "a"}, {"id": "a"}], [{"id": "b"}]):
            with self.assertRaises(ValueError):
                complete_roster(rows, ["a"])

    def test_blocked_bad_proposal_retains_ai_failure(self):
        rows = safeguard_rows([
            dict(case_id="unsupported-count-conversion", validation="blocked", error="missingConversion", saved_count=0),
            dict(case_id="supported-grams-control", validation="saved", error="", saved_count=1)])
        self.assertTrue(rows[0]["expectation_met"])
        self.assertEqual(rows[0]["ai_status"], "fail_synthetic_unsupported_claim")
        self.assertEqual(rows[0]["outcome_status"], "unresolved_expected_block")

    def test_block_everything_fails_supported_control(self):
        rows = safeguard_rows([
            dict(case_id="unsupported-count-conversion", validation="blocked", error="missingConversion", saved_count=0),
            dict(case_id="supported-grams-control", validation="blocked", error="missingConversion", saved_count=0)])
        self.assertFalse(rows[1]["expectation_met"])

    def test_unexpected_save_fails_safeguard(self):
        rows = safeguard_rows([
            dict(case_id="unsupported-count-conversion", validation="saved", error="", saved_count=1),
            dict(case_id="supported-grams-control", validation="saved", error="", saved_count=1)])
        self.assertFalse(rows[0]["expectation_met"])

    def test_assertion_rejects_wrong_case_and_false_result(self):
        with self.assertRaises(ValueError):
            get_assert(json.dumps(dict(id="wrong")), dict(vars=dict(case_id="a")))
        result = get_assert(json.dumps(dict(id="a", expectation_met=False, reason="bad basis")),
                            dict(vars=dict(case_id="a")))
        self.assertFalse(result["pass"])
        self.assertEqual(result["score"], 0)

    def test_original_extraction_scorer_rejects_wrong_basis_and_invented_unknown(self):
        root = HERE.parent / "GeminiNutritionExtractionEvaluation"
        spec = importlib.util.spec_from_file_location("legacy_extraction", root / "evaluate.py")
        scorer = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(scorer)
        corpus = json.loads((root / "corpus-v1.json").read_text())
        replay = json.loads((root / "development-replay-v3.json").read_text())
        schema = json.loads((root / "response-schema-v2.json").read_text())
        by_id = {case["id"]: case for case in corpus["cases"] if case["split"] == "development"}
        row = next(row for row in replay["results"] if row["arm"] == "panel")
        case = by_id[row["case_id"]]
        changed = copy.deepcopy(row["bound"]["extraction"])
        changed["basis_amount"] = 1
        self.assertFalse(scorer.score(case, changed, schema)["passed"])
        unknown_row = next(row for row in replay["results"] if row["arm"] == "panel"
                           and any(field["state"] == "unknown" for field in row["bound"]["extraction"]["nutrients"]))
        changed = copy.deepcopy(unknown_row["bound"]["extraction"])
        field = next(field for field in changed["nutrients"] if field["state"] == "unknown")
        field["value"] = 0
        result = scorer.score(by_id[unknown_row["case_id"]], changed, schema)
        self.assertFalse(result["passed"])


if __name__ == "__main__":
    unittest.main()
