import sys
import unittest
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from prepare import packets, validate_choice


class CandidateBoundaryTests(unittest.TestCase):
    def testOnlyAdmittedCandidatesCanBeChosenAndDeclineAlwaysWorks(self):
        packet = {"candidates": [{"record_id": "admitted"}]}
        validate_choice(packet, "admitted")
        validate_choice(packet, None)
        for value in ["blocked", "invented", True, 1]:
            with self.assertRaises(ValueError):
                validate_choice(packet, value)
        with self.assertRaises(ValueError):
            validate_choice({"candidates": []}, "admitted")

    def testHardRulesPrecedePacketsAndLabelsNeverEnterThem(self):
        identity = {"preparation": "raw"}
        records = [
            {"record_id": "raw", "name": "Fixture beef", "identity": identity},
            {"record_id": "cooked", "name": "Fixture beef", "identity": {"preparation": "cooked"}},
        ]
        contract = {"retrieval": {"minimum_score": 0.25, "candidate_limit": 10,
            "weights": {"exact_name": 0.55, "query_coverage": 0.2, "candidate_coverage": 0.15, "jaccard": 0.1}}}
        gold = {"synthetic_records": [], "cases": [{"case_id": "fixture", "split": "gate",
            "query": {"text": "Fixture beef", "identity": identity},
            "label": {"secret": "never export"}, "family": "not model input"}]}
        result = packets(contract, {"records": records}, gold)[0]
        self.assertEqual([record["record_id"] for record in result["candidates"]], ["raw"])
        self.assertEqual(set(result), {"case_id", "split", "query", "candidates"})
        with self.assertRaises(ValueError):
            validate_choice(result, "cooked")


if __name__ == "__main__":
    unittest.main()
