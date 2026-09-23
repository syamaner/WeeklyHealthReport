from __future__ import annotations

import json
import sys
import unittest
from copy import deepcopy
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from geometry_v2 import candidate_review
from build_gate_outcomes import raw_filename


def observation(words: list[tuple[str, float]], y: float) -> dict:
    return {"tokens": [
        {"text": text, "boundingBox": {"x": x, "y": y, "width": 0.045, "height": 0.03}}
        for text, x in words
    ]}


class GeometryV2Tests(unittest.TestCase):
    def test_joins_split_bound_and_unit_but_never_authorizes_save(self) -> None:
        raw = {"observations": [
            observation([("Per", 0.38), ("100g", 0.43)], 0.90),
            observation([("Energy", 0.04), ("701", 0.40), ("kJ", 0.45)], 0.75),
            observation([("Fat", 0.04), ("<", 0.40), ("0.1", 0.45), ("g", 0.50)], 0.65),
        ]}
        before = deepcopy(raw)
        result = candidate_review(raw)
        self.assertEqual(raw, before)
        self.assertEqual([(c["row_id"], c["comparator"], c["unit"]) for c in result["candidates"]],
                         [("energy_kj", None, "kJ"), ("fat", "<", "g")])
        self.assertFalse(result["ready_for_confirmation"])
        self.assertFalse(result["automatic_save"])
        self.assertTrue(all(c["requires_user_selection"] and not c["persistence_authorized"]
                            for c in result["candidates"]))

    def test_missing_energy_unit_is_not_a_candidate(self) -> None:
        raw = {"observations": [
            observation([("Per", 0.38), ("100g", 0.43)], 0.90),
            observation([("Energy", 0.04), ("701", 0.40)], 0.75),
        ]}
        result = candidate_review(raw)
        self.assertEqual(result["candidates"], [])
        self.assertIn("energy unit is not explicit", result["unresolved_reasons"])

    def test_distant_unit_is_not_taken_from_another_column(self) -> None:
        raw = {"observations": [
            observation([("Per", 0.38), ("100g", 0.43)], 0.90),
            observation([("Energy", 0.04), ("701", 0.40), ("kJ", 0.70)], 0.75),
        ]}
        result = candidate_review(raw)
        self.assertEqual(result["candidates"], [])
        self.assertIn("energy unit is not explicit", result["unresolved_reasons"])

    def test_per_serving_candidate_keeps_conversion_unknown(self) -> None:
        raw = {"observations": [
            observation([("Per", 0.38), ("serving", 0.43)], 0.90),
            observation([("Fat", 0.04), ("2g", 0.40)], 0.75),
        ]}
        result = candidate_review(raw)
        self.assertIsNone(result["candidates"][0]["serving_conversion"])
        self.assertIn("serving conversion is not established", result["unresolved_reasons"])

    def test_energy_slash_pair_and_parenthesized_row(self) -> None:
        raw = {"observations": [
            observation([("Per", 0.58), ("100g", 0.63)], 0.90),
            observation([("Energy", 0.04), ("701", 0.55), ("kJ/167", 0.60), ("kcal", 0.66)], 0.75),
            observation([("saturates", 0.04), ("(0.9g)", 0.55)], 0.65),
        ]}
        result = candidate_review(raw)
        self.assertEqual({cell["row_id"] for cell in result["candidates"]},
                         {"energy_kj", "energy_kcal", "saturates"})
        self.assertFalse(result["ready_for_confirmation"])

    def test_unbound_printed_bound_is_reported(self) -> None:
        raw = {"observations": [
            observation([("Per", 0.38), ("100g", 0.43)], 0.90),
            observation([("Unknown", 0.04), ("<0.1g", 0.40)], 0.75),
        ]}
        result = candidate_review(raw)
        self.assertEqual(result["candidates"], [])
        self.assertIn("printed bound marker not bound to a candidate", result["unresolved_reasons"])

    def test_exposed_v1_false_ready_cases_are_selection_only_regressions(self) -> None:
        raw_dir = ROOT / "fixtures" / "untouched-vision-raw-v1"
        outcomes = json.loads((ROOT / "fixtures" / "untouched-outcomes-v1.json").read_text())
        formerly_ready = [panel["panel_id"] for panel in outcomes["panels"]
                          if panel["ready_for_confirmation"]]
        self.assertEqual(len(formerly_ready), 4)
        for panel_id in formerly_ready:
            with self.subTest(panel_id=panel_id):
                raw = json.loads((raw_dir / raw_filename(panel_id)).read_text())
                result = candidate_review(raw)
                self.assertEqual(result["image_sha256"], raw["imageSHA256"])
                self.assertFalse(result["ready_for_confirmation"])
                self.assertTrue(result["unresolved_warning"])
                self.assertFalse(result["automatic_save"])
                self.assertTrue(all(not cell["persistence_authorized"]
                                    for cell in result["candidates"]))


if __name__ == "__main__":
    unittest.main()
