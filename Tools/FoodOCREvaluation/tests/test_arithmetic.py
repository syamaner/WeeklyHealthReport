from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from arithmetic import serving_consistency


def cell(row: str, basis: str, value: str) -> dict:
    return {"row_id": row, "basis": basis, "decimal_text": value, "comparator": None}


class ArithmeticTests(unittest.TestCase):
    def test_consistent_serving_columns_pass(self) -> None:
        cells = []
        for row, per_100, serving in (
            ("fat", "10", "2.5"),
            ("carbohydrate", "20", "5"),
            ("protein", "8", "2"),
            ("salt", "1", "0.25"),
        ):
            cells += [cell(row, "per_100g", per_100), cell(row, "per_serving", serving)]
        result = serving_consistency(cells)
        self.assertEqual(result["status"], "consistent")
        self.assertFalse(result["detected"])

    def test_factor_ten_fault_is_detected(self) -> None:
        cells = []
        for row, per_100, serving in (
            ("fat", "10", "25"),
            ("carbohydrate", "20", "5"),
            ("protein", "8", "2"),
            ("salt", "1", "0.25"),
        ):
            cells += [cell(row, "per_100g", per_100), cell(row, "per_serving", serving)]
        result = serving_consistency(cells)
        self.assertTrue(result["detected"])
        self.assertEqual(result["outlier_rows"], ["fat"])

    def test_fewer_than_four_rows_declines_arithmetic_judgement(self) -> None:
        result = serving_consistency([
            cell("fat", "per_100g", "10"),
            cell("fat", "per_serving", "2.5"),
        ])
        self.assertEqual(result["status"], "insufficient_evidence")
        self.assertFalse(result["detected"])


if __name__ == "__main__":
    unittest.main()
