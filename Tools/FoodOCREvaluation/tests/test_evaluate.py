from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from evaluate import score_panel


class EvaluationTests(unittest.TestCase):
    def setUp(self) -> None:
        self.cell = {
            "row_id": "salt",
            "header_id": "per100",
            "parent_row_id": None,
            "basis": "per_100g",
            "comparator": "<",
            "decimal_text": "0.1",
            "unit": "g",
            "serving_conversion": None,
        }
        self.panel = {
            "ground_truth": {
                "cells": [self.cell],
                "requires_decline": False,
            }
        }

    def test_exact_bounded_cell_scores_without_false_save(self) -> None:
        score = score_panel(self.panel, {
            "cells": [self.cell],
            "ready_for_confirmation": True,
            "unresolved_warning": False,
            "declined": False,
            "arithmetic_faults": [{"detected": True}],
            "correction_seconds": 2.5,
        })
        self.assertEqual(score["exact_cells"], 1)
        self.assertEqual(score["bound_exact"], 1)
        self.assertFalse(score["false_save"])

    def test_silent_wrong_value_is_a_false_save(self) -> None:
        wrong = dict(self.cell, decimal_text="1")
        score = score_panel(self.panel, {
            "cells": [wrong],
            "ready_for_confirmation": True,
            "unresolved_warning": False,
        })
        self.assertTrue(score["false_save"])

    def test_wrong_value_with_unresolved_warning_is_not_silent(self) -> None:
        wrong = dict(self.cell, decimal_text="1")
        score = score_panel(self.panel, {
            "cells": [wrong],
            "ready_for_confirmation": False,
            "unresolved_warning": True,
            "declined": True,
        })
        self.assertFalse(score["false_save"])


if __name__ == "__main__":
    unittest.main()
