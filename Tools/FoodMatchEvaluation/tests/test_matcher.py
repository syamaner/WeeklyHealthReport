from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from matcher import identity_contradictions, normalize_text, one_sided_wilson_lower, retrieve


CONTRACT = {
    "retrieval": {
        "candidate_limit": 10,
        "minimum_score": 0.25,
        "weights": {"exact_name": 0.55, "query_coverage": 0.2, "candidate_coverage": 0.15, "jaccard": 0.1},
    }
}


def identity(**changes: str) -> dict[str, str]:
    result = {
        "preparation": "unknown", "bone": "unknown", "skin": "unknown",
        "drained": "unknown", "packing_medium": "unknown", "fortification": "unknown",
        "salt_state": "unknown", "serving_basis": "unknown", "edible_quantity": "unknown",
        "formulation": "unknown",
    }
    result.update(changes)
    return result


class MatcherTests(unittest.TestCase):
    def test_normalisation_is_unicode_punctuation_and_alias_stable(self) -> None:
        self.assertEqual(normalize_text("Yogurt, AUBERGINES"), "yoghurt aubergine")

    def test_known_expected_value_blocks_unknown_and_conflict(self) -> None:
        expected = identity(drained="drained")
        self.assertEqual(identity_contradictions(expected, identity()), ["drained"])
        self.assertEqual(identity_contradictions(expected, identity(drained="undrained")), ["drained"])
        self.assertEqual(identity_contradictions(expected, identity(drained="drained")), [])

    def test_every_frozen_hard_rule_family_blocks_a_conflict(self) -> None:
        families = {
            "preparation": ("raw", "cooked"),
            "bone": ("boneless", "with_bone"),
            "skin": ("skinless", "skin_on"),
            "drained": ("drained", "undrained"),
            "packing_medium": ("brine", "oil"),
            "fortification": ("unfortified", "fortified"),
            "salt_state": ("unsalted", "salted"),
            "serving_basis": ("per_100_g", "per_serving"),
            "edible_quantity": ("100_g", "1_serving"),
            "formulation": ("v2", "v1"),
        }
        for field, (expected_value, conflict_value) in families.items():
            with self.subTest(field=field):
                self.assertEqual(
                    identity_contradictions(
                        identity(**{field: expected_value}),
                        identity(**{field: conflict_value}),
                    ),
                    [field],
                )

    def test_hard_rule_runs_before_a_lexically_exact_conflict(self) -> None:
        records = [
            {"record_id": "conflict", "name": "salmon fillet", "identity": identity(bone="with_bone")},
            {"record_id": "target", "name": "salmon fillet boneless", "identity": identity(bone="boneless")},
        ]
        result = retrieve("salmon fillet", identity(bone="boneless"), records, CONTRACT)
        self.assertEqual([item.record_id for item in result.candidates], ["target"])
        self.assertEqual(result.blocked, {"conflict": ["bone"]})
        self.assertEqual(result.action, "show_closest_for_explicit_selection")

    def test_record_order_does_not_change_ranking(self) -> None:
        records = [
            {"record_id": "b", "name": "apple raw", "identity": identity()},
            {"record_id": "a", "name": "apple raw", "identity": identity()},
        ]
        forward = retrieve("apple raw", identity(), records, CONTRACT)
        reverse = retrieve("apple raw", identity(), list(reversed(records)), CONTRACT)
        self.assertEqual([item.record_id for item in forward.candidates], ["a", "b"])
        self.assertEqual(forward, reverse)

    def test_no_result_declines_and_never_auto_accepts(self) -> None:
        result = retrieve("zzzxqv", identity(), [], CONTRACT)
        self.assertEqual(result.action, "decline")

    def test_one_sided_wilson_bound_is_deterministic(self) -> None:
        lower = one_sided_wilson_lower(1000, 1000, 1.6448536269514722)
        self.assertIsNotNone(lower)
        self.assertGreater(lower, 0.997)
        self.assertLess(lower, 1.0)


if __name__ == "__main__":
    unittest.main()
