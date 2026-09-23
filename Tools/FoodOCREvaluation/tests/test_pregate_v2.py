from __future__ import annotations

import json
import sys
import unittest
from copy import deepcopy
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from pregate_v2 import audit_candidates


class PregateV2Tests(unittest.TestCase):
    def setUp(self) -> None:
        fixtures = ROOT / "fixtures"
        self.candidate = json.loads((fixtures / "candidate-manifest-v1.json").read_text())
        self.selection = json.loads((fixtures / "review-selection-v2.json").read_text())
        self.truth = json.loads((fixtures / "ground-truth-v1.json").read_text())

    def test_real_inventory_excludes_every_previously_selected_panel(self) -> None:
        result = audit_candidates(self.candidate, self.selection, self.truth)
        self.assertEqual(result["status"], "inventory_only_not_ground_truth_or_gate")
        self.assertEqual(result["remaining_count"], 40)
        self.assertEqual(result["old_split_counts"], {"tuning": 23, "untouched_gate": 17})
        prior_ids = {item["panel_id"] for item in self.selection["panels"]}
        prior_hashes = {item["image_sha256"] for item in self.truth["panels"]}
        self.assertFalse(prior_ids & {item["panel_id"] for item in result["panels"]})
        self.assertFalse(prior_hashes & {item["image_sha256"] for item in result["panels"]})

    def test_duplicate_image_fails_closed(self) -> None:
        candidate = deepcopy(self.candidate)
        candidate["panels"][1]["image_sha256"] = candidate["panels"][0]["image_sha256"]
        with self.assertRaisesRegex(ValueError, "repeats"):
            audit_candidates(candidate, self.selection, self.truth)

    def test_prior_selection_must_match_reviewed_image_identity(self) -> None:
        truth = deepcopy(self.truth)
        truth["panels"][0]["image_sha256"] = "0" * 64
        with self.assertRaisesRegex(ValueError, "conflicting image identities"):
            audit_candidates(self.candidate, self.selection, truth)

    def test_unpinned_or_nonpublic_image_fails_closed(self) -> None:
        remaining_id = audit_candidates(self.candidate, self.selection, self.truth)["panels"][0]["panel_id"]
        for field, value in (("image_sha256", "not-a-hash"), ("image_url", "https://example.org/panel.jpg")):
            with self.subTest(field=field):
                candidate = deepcopy(self.candidate)
                panel = next(item for item in candidate["panels"] if item["panel_id"] == remaining_id)
                if field == "image_url":
                    panel["source"][field] = value
                else:
                    panel[field] = value
                with self.assertRaises(ValueError):
                    audit_candidates(candidate, self.selection, self.truth)


if __name__ == "__main__":
    unittest.main()
