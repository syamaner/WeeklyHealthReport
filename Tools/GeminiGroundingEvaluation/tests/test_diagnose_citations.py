import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from diagnose_citations import diagnose_lead, diagnose_replay  # noqa: E402


class CitationDiagnosticTests(unittest.TestCase):
    def test_subdomain_matches_citation_hint(self):
        item = diagnose_lead({"title": "usda.gov", "url": "https://vertexaisearch.cloud.google.com/redirect",
                              "cited_text": "[Milk](https://fdc.nal.usda.gov/food-details/1)"})
        self.assertFalse(item["apparent_host_mismatch"])
        self.assertEqual(item["written_link_hosts"], ["fdc.nal.usda.gov"])

    def test_unrelated_citation_hint_flags_written_link(self):
        item = diagnose_lead({"title": "rawpawiq.com", "url": "https://vertexaisearch.cloud.google.com/redirect",
                              "cited_text": "[Egg](https://fdc.nal.usda.gov/food-details/1)"})
        self.assertTrue(item["apparent_host_mismatch"])

    def test_broad_span_and_unlinked_span_are_separate_diagnostics(self):
        broad = diagnose_lead({"title": "tesco.com", "url": "https://vertexaisearch.cloud.google.com/redirect",
                               "cited_text": "[Milk](https://www.tesco.com/milk) and [egg](https://fdc.nal.usda.gov/egg)"})
        self.assertTrue(broad["multiple_written_hosts"])
        self.assertFalse(broad["apparent_host_mismatch"])
        unlinked = diagnose_lead({"title": "tesco.com", "url": "https://vertexaisearch.cloud.google.com/redirect",
                                  "cited_text": "A claim with no written link"})
        self.assertTrue(unlinked["no_written_link_in_span"])
        self.assertFalse(unlinked["apparent_host_mismatch"])

    def test_opaque_grounding_redirect_does_not_claim_host_mismatch(self):
        item = diagnose_lead({"title": "tesco.com", "url": "https://vertexaisearch.cloud.google.com/redirect-a",
                              "cited_text": "[Milk](https://vertexaisearch.cloud.google.com/redirect-b)"})
        self.assertFalse(item["apparent_host_mismatch"])
        self.assertTrue(item["opaque_written_redirect"])

    def test_partial_replay_is_diagnosable_without_quality_score(self):
        replay = {"schema_version": "gemini-grounding-replay-v1", "results": [
            {"case_id": "g09", "leads": [
                {"title": "rawpawiq.com", "url": "https://vertexaisearch.cloud.google.com/redirect",
                 "cited_text": "[Egg](https://fdc.nal.usda.gov/food-details/1)"}]}]}
        result = diagnose_replay(replay)
        self.assertEqual(result["counts"]["apparent_host_mismatch"], 1)
        self.assertEqual(result["counts"]["cases"], 1)
        self.assertIn("not page verification", result["interpretation"])


if __name__ == "__main__":
    unittest.main()
