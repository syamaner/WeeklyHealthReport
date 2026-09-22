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

    def test_equivalent_semantic_header_with_different_local_id_matches(self) -> None:
        recognized = dict(self.cell, header_id="header_7")
        score = score_panel(self.panel, {
            "cells": [recognized], "ready_for_confirmation": True,
            "unresolved_warning": False,
        })
        self.assertEqual(score["correct_bindings"], 1)
        self.assertEqual(score["exact_cells"], 1)
        self.assertTrue(score["table_exact"])
        self.assertFalse(score["false_save"])

    def test_wrong_parent_or_basis_cannot_be_ready_without_false_save(self) -> None:
        for wrong in (dict(self.cell, parent_row_id="fat"), dict(self.cell, basis="per_serving")):
            with self.subTest(wrong=wrong):
                score = score_panel(self.panel, {
                    "cells": [wrong], "ready_for_confirmation": True,
                    "unresolved_warning": False,
                })
                self.assertEqual(score["correct_bindings"], 0)
                self.assertFalse(score["table_exact"])
                self.assertTrue(score["false_save"])

    def test_repeated_same_basis_columns_fail_closed(self) -> None:
        repeated = dict(self.cell, header_id="another_header")
        panel = {"ground_truth": {"cells": [self.cell, repeated], "requires_decline": False}}
        score = score_panel(panel, {
            "cells": [self.cell, repeated], "ready_for_confirmation": True,
            "unresolved_warning": False,
        })
        self.assertEqual(score["expected_cells"], 2)
        self.assertEqual(score["exact_cells"], 0)
        self.assertFalse(score["table_exact"])
        self.assertTrue(score["false_save"])


if __name__ == "__main__":
    unittest.main()
