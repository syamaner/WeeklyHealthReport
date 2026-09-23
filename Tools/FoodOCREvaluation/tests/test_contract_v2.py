from __future__ import annotations

import copy
import hashlib
import json
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from validate_contract_v2 import select_split, validate


class V2ContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.contract = json.loads((ROOT / "frozen-contract-v2.json").read_text())

    def test_pre_registered_contract_is_valid(self) -> None:
        validate(self.contract)
        self.assertEqual(self.contract["status"], "pre_registered_no_v2_gate_run")

    def test_safety_policy_cannot_authorize_automatic_save(self) -> None:
        altered = copy.deepcopy(self.contract)
        altered["safety_policy"]["automatic_save"] = True
        with self.assertRaisesRegex(ValueError, "unsafe v2 promotion policy"):
            validate(altered)
        altered = copy.deepcopy(self.contract)
        altered["candidate_schema"]["required_ready_for_confirmation"] = True
        with self.assertRaisesRegex(ValueError, "candidate acceptance boundary"):
            validate(altered)

    def test_corpus_and_critical_threshold_cannot_be_weakened(self) -> None:
        altered = copy.deepcopy(self.contract)
        altered["corpus"]["minimum_untouched_bounded_cells"] = 0
        with self.assertRaisesRegex(ValueError, "denominator minimum"):
            validate(altered)
        altered = copy.deepcopy(self.contract)
        altered["metrics"]["bound_preservation_minimum"] = 0.99
        with self.assertRaisesRegex(ValueError, "metric threshold weakened"):
            validate(altered)

    def test_selected_split_is_deterministic_and_exactly_sixty_forty(self) -> None:
        candidates = [
            {"panel_id": f"public-{index}", "image_sha256": hashlib.sha256(str(index).encode()).hexdigest()}
            for index in range(140)
        ]
        first = select_split(self.contract, candidates, excluded_panel_ids=set(), excluded_image_hashes=set())
        self.assertEqual(first, select_split(
            self.contract, list(reversed(candidates)), excluded_panel_ids=set(), excluded_image_hashes=set(),
        ))
        self.assertEqual(len(first), 100)
        self.assertEqual(list(first.values()).count("tuning"), 60)
        self.assertEqual(list(first.values()).count("untouched_gate"), 40)

    def test_split_rejects_duplicate_or_insufficient_candidates(self) -> None:
        candidates = [
            {"panel_id": f"public-{index}", "image_sha256": hashlib.sha256(str(index).encode()).hexdigest()}
            for index in range(140)
        ]
        with self.assertRaisesRegex(ValueError, "too few"):
            select_split(self.contract, candidates[:-1], excluded_panel_ids=set(), excluded_image_hashes=set())
        with self.assertRaisesRegex(ValueError, "reuses exposed"):
            select_split(self.contract, candidates, excluded_panel_ids={"public-1"}, excluded_image_hashes=set())
        candidates[-1] = candidates[0]
        with self.assertRaisesRegex(ValueError, "duplicate eligible"):
            select_split(self.contract, candidates, excluded_panel_ids=set(), excluded_image_hashes=set())


if __name__ == "__main__":
    unittest.main()
