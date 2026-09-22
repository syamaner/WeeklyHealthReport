from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from review_server import review_queue, validate_annotation, validate_assistant_draft


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

    def test_assistant_draft_cannot_claim_human_verification(self) -> None:
        candidate = validate_assistant_draft(self.value, self.panel)
        self.assertEqual(candidate["review_status"], "assistant_candidate_pending_human")
        self.assertNotIn("reviewer", candidate)
        self.assertNotIn("verification_status", candidate)
        self.assertNotIn("verification_assertion", candidate)

    def test_assistant_draft_requires_matching_image(self) -> None:
        self.value["image_sha256"] = "b" * 64
        with self.assertRaisesRegex(ValueError, "image hash mismatch"):
            validate_assistant_draft(self.value, self.panel)

    def test_local_exclusion_preserves_frozen_manifest(self) -> None:
        manifest = {"panels": [{"panel_id": "panel-1"}, {"panel_id": "panel-2"}]}
        queue = review_queue(manifest, {"panels": [{"panel_id": "panel-1", "reason": "user skip"}]})
        self.assertEqual([panel["panel_id"] for panel in queue], ["panel-2"])
        self.assertEqual(len(manifest["panels"]), 2)

    def test_exclusion_requires_known_unique_id_and_reason(self) -> None:
        manifest = {"panels": [{"panel_id": "panel-1"}]}
        with self.assertRaisesRegex(ValueError, "unknown, duplicate or unexplained"):
            review_queue(manifest, {"panels": [{"panel_id": "panel-1", "reason": ""}]})


if __name__ == "__main__":
    unittest.main()
