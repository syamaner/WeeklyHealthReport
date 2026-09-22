from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from review_server import validate_annotation


class ReviewValidationTests(unittest.TestCase):
    def setUp(self) -> None:
        self.panel = {"panel_id": "panel-1", "image_sha256": "a" * 64}
        self.value = {
            "panel_id": "panel-1",
            "image_sha256": "a" * 64,
            "reviewer": "Sertan",
            "started_at": "2026-09-22T00:00:00Z",
            "correction_seconds": 30,
            "full_transcript": "Salt <0.1g",
            "cells": [{
                "row_id": "salt", "parent_row_id": None, "header_id": "header_1",
                "basis": "per_100g", "printed_text": "<0.1g", "comparator": "<",
                "decimal_text": "0.1", "unit": "g", "serving_conversion": None,
            }],
            "families": ["bound", "salt"],
            "requires_decline": False,
            "decline_reason": "",
            "verification_assertion": True,
        }

    def test_verified_annotation_is_normalized(self) -> None:
        result = validate_annotation(self.value, self.panel)
        self.assertEqual(result["verification_status"], "independently_verified")
        self.assertEqual(result["families"], ["bound", "salt"])

    def test_unchecked_annotation_fails(self) -> None:
        self.value["verification_assertion"] = False
        with self.assertRaisesRegex(ValueError, "verification assertion"):
            validate_annotation(self.value, self.panel)

    def test_empty_cells_require_decline(self) -> None:
        self.value["cells"] = []
        with self.assertRaisesRegex(ValueError, "record cells or mark"):
            validate_annotation(self.value, self.panel)


if __name__ == "__main__":
    unittest.main()
