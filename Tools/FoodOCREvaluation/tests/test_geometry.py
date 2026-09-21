from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from geometry import bind


def observation(tokens: list[tuple[str, float]], y: float) -> dict:
    return {
        "tokens": [
            {"text": text, "boundingBox": {"x": x, "y": y, "width": 0.05, "height": 0.03}}
            for text, x in tokens
        ]
    }


class GeometryTests(unittest.TestCase):
    def test_binds_rows_to_explicit_headers_and_preserves_bounds(self) -> None:
        raw = {"observations": [
            observation([("Per", 0.40), ("100g", 0.46)], 0.90),
            observation([("Per", 0.70), ("serving", 0.76)], 0.90),
            observation([("Fat", 0.05), ("10g", 0.45), ("2g", 0.75)], 0.70),
            observation([("of", 0.05), ("which", 0.10), ("saturates", 0.18), ("<0.1g", 0.45), ("<0.1g", 0.75)], 0.60),
        ]}
        result = bind(raw)
        self.assertFalse(result["declined"])
        self.assertEqual(len(result["cells"]), 4)
        saturates = [cell for cell in result["cells"] if cell["row_id"] == "saturates"]
        self.assertEqual({cell["comparator"] for cell in saturates}, {"<"})
        self.assertEqual({cell["parent_row_id"] for cell in saturates}, {"fat"})
        self.assertTrue(all(not cell["persistence_authorized"] for cell in result["cells"]))

    def test_missing_header_declines(self) -> None:
        raw = {"observations": [observation([("Salt", 0.05), ("0.2g", 0.45)], 0.70)]}
        result = bind(raw)
        self.assertTrue(result["declined"])
        self.assertIn("no explicit basis header for salt", result["unresolved_reasons"])

    def test_unknown_row_declines_instead_of_guessing(self) -> None:
        raw = {"observations": [
            observation([("Per", 0.40), ("100g", 0.46)], 0.90),
            observation([("Mystery", 0.05), ("3g", 0.45)], 0.70),
        ]}
        result = bind(raw)
        self.assertTrue(result["declined"])
        self.assertEqual(result["cells"], [])

    def test_saturated_fat_is_nested_under_fat(self) -> None:
        raw = {"observations": [
            observation([("Per", 0.40), ("100g", 0.46)], 0.90),
            observation([("Saturated", 0.05), ("fat", 0.18), ("2g", 0.45)], 0.70),
        ]}
        result = bind(raw)
        self.assertEqual(result["cells"][0]["row_id"], "saturates")
        self.assertEqual(result["cells"][0]["parent_row_id"], "fat")


if __name__ == "__main__":
    unittest.main()
