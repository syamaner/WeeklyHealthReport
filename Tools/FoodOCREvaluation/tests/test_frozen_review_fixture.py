import json
import unittest
from pathlib import Path

from corpus import validate_manifest


FIXTURES = Path(__file__).resolve().parents[1] / "fixtures"
ROOT = FIXTURES.parent


class FrozenReviewFixtureTests(unittest.TestCase):
    def test_reviewed_fixture_preserves_sealed_identities_and_provenance(self):
        contract = json.loads((ROOT / "frozen-contract-v1.json").read_text())
        selection = json.loads((FIXTURES / "review-selection-v2.json").read_text())
        fixture = json.loads((FIXTURES / "ground-truth-v1.json").read_text())
        validate_manifest(fixture, contract)
        self.assertEqual(fixture["counts"], {"tuning": 60, "untouched_gate": 40})
        expected = {panel["panel_id"]: panel for panel in selection["panels"]}
        self.assertEqual({panel["panel_id"] for panel in fixture["panels"]}, set(expected))
        for panel in fixture["panels"]:
            sealed = expected[panel["panel_id"]]
            self.assertEqual(panel["image_sha256"], sealed["image_sha256"])
            self.assertEqual(panel["split"], sealed["split"])
            self.assertEqual(panel["image_url"], panel["source"]["image_url"])


if __name__ == "__main__":
    unittest.main()
