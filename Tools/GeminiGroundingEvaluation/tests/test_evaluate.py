import json
import sys
import tempfile
import unittest
from copy import deepcopy
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from evaluate import EvaluationError, evaluate, validate_cases, verify_frozen_contract  # noqa: E402


class GroundingEvaluationTests(unittest.TestCase):
    def setUp(self):
        self.cases = {"schema_version": "gemini-grounding-cases-v1", "cases": [
            {"id": "a", "split": "development", "family": "dairy", "food_terms": "Greek yoghurt 10%",
             "task": "Find source", "critical_distinctions": ["10% versus 0%"], "source_leads": []},
            {"id": "b", "split": "holdout", "family": "meat", "food_terms": "cooked ribeye",
             "task": "Find source", "critical_distinctions": ["cooked versus raw"], "source_leads": []}]}
        self.replay = {"schema_version": "gemini-grounding-replay-v1", "run_id": "synthetic-control",
                       "provider": "synthetic", "model": "control-v1", "captured_on": "2026-09-28", "results": [
                           {"case_id": "a", "response_text": "A manufacturer page is a lead.",
                            "leads": [{"title": "Manufacturer", "url": "https://example.org/yoghurt",
                                       "cited_text": "manufacturer page"}], "suggestions_present": True},
                           {"case_id": "b", "response_text": "Raw beef is cooked ribeye.",
                            "leads": [{"title": "Raw record", "url": "https://example.org/raw",
                                       "cited_text": "Raw beef"}], "suggestions_present": False}]}
        self.judgements = {"schema_version": "gemini-grounding-judgements-v1", "run_id": "synthetic-control",
                           "reviewer": "reviewer-1", "reviewed_on": "2026-09-28", "results": [
                               {"case_id": "a", "distinctions_preserved": True,
                                "promotes_unverified_nutrition": False, "answer_note": "Variant remains explicit",
                                "leads": [{"grade": "exact_primary", "supports_cited_text": "yes",
                                           "evidence_note": "Synthetic page supports title"}]},
                               {"case_id": "b", "distinctions_preserved": False,
                                "promotes_unverified_nutrition": True, "answer_note": "Raw labelled cooked",
                                "leads": [{"grade": "severe_mismatch", "supports_cited_text": "no",
                                           "evidence_note": "Synthetic page is raw"}]}]}

    def test_control_distinguishes_helpful_lead_from_unsafe_claim(self):
        report = evaluate(self.cases, self.replay, self.judgements)
        total = report["groups"]["all"]
        self.assertEqual(total["useful_at_3"], 1)
        self.assertEqual(total["primary_at_3"], 1)
        self.assertEqual(total["severe_mismatch_cases"], 1)
        self.assertEqual(total["nutrition_promotion_cases"], 1)
        self.assertEqual(total["unsupported_citations"], 1)
        self.assertEqual(report["groups"]["split:holdout"]["useful_at_3"], 0)

    def test_missing_case_or_independent_review_fails_closed(self):
        replay = deepcopy(self.replay)
        replay["results"].pop()
        with self.assertRaisesRegex(EvaluationError, "missing cases"):
            evaluate(self.cases, replay, self.judgements)
        review = deepcopy(self.judgements)
        review["results"][0]["leads"] = []
        with self.assertRaisesRegex(EvaluationError, "incomplete lead review"):
            evaluate(self.cases, self.replay, review)

    def test_honest_no_lead_response_keeps_precision_undefined(self):
        replay = deepcopy(self.replay)
        review = deepcopy(self.judgements)
        for result in replay["results"]:
            result["response_text"] = "No exact source established."
            result["leads"] = []
        for result in review["results"]:
            result["leads"] = []
            result["answer_note"] = "No cited source is available"
        total = evaluate(self.cases, replay, review)["groups"]["all"]
        self.assertEqual(total["useful_at_3"], 0)
        self.assertEqual(total["leads"], 0)
        self.assertIsNone(total["lead_precision_at_3"])

    def test_unsafe_url_and_unattached_citation_fail_closed(self):
        replay = deepcopy(self.replay)
        replay["results"][0]["leads"][0]["url"] = "https://secret@example.org/yoghurt"
        with self.assertRaisesRegex(EvaluationError, "unsafe URL"):
            evaluate(self.cases, replay, self.judgements)
        replay = deepcopy(self.replay)
        replay["results"][0]["leads"][0]["cited_text"] = "Unwritten claim"
        with self.assertRaisesRegex(EvaluationError, "not attached"):
            evaluate(self.cases, replay, self.judgements)

    def test_case_file_rejects_duplicate_ids_and_non_https_evidence(self):
        cases = deepcopy(self.cases)
        cases["cases"][1]["id"] = "a"
        with self.assertRaisesRegex(EvaluationError, "duplicate"):
            validate_cases(cases)
        cases = deepcopy(self.cases)
        cases["cases"][0]["source_leads"] = ["http://example.org"]
        with self.assertRaisesRegex(EvaluationError, "invalid source example"):
            validate_cases(cases)

    def test_frozen_contract_detects_case_mutation(self):
        root = Path(__file__).resolve().parents[1]
        contract = root / "frozen-contract-v1.json"
        original = root / "cases-v1.json"
        self.assertEqual(len(verify_frozen_contract(original, contract)), 16)
        with tempfile.TemporaryDirectory() as directory:
            altered = Path(directory) / "cases-v1.json"
            document = json.loads(original.read_text(encoding="utf-8"))
            document["cases"][0]["food_terms"] = "Greek yoghurt 0% fat"
            altered.write_text(json.dumps(document), encoding="utf-8")
            with self.assertRaisesRegex(EvaluationError, "hash changed"):
                verify_frozen_contract(altered, contract)


if __name__ == "__main__":
    unittest.main()
