from __future__ import annotations

import hashlib
import json
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from freeze_v2_development_review import build_snapshot


class FreezeV2DevelopmentReviewTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.workspace = Path(self.temporary.name)
        (self.workspace / "images").mkdir()
        (self.workspace / "annotations").mkdir()
        self.approval_path = self.workspace / "approval.json"
        panels = []
        for index in range(1, 41):
            image = f"public-image-{index}".encode()
            image_hash = hashlib.sha256(image).hexdigest()
            image_file = f"{index:03d}.jpg"
            (self.workspace / "images" / image_file).write_bytes(image)
            panel = {
                "review_index": index, "panel_id": f"panel-{index}",
                "image_sha256": image_hash, "image_file": image_file,
                "image_url": f"https://example.org/{index}.jpg",
                "product_code": str(index), "product_name": f"Product {index}",
            }
            panels.append(panel)
            decline = index == 1
            annotation = {
                "panel_id": panel["panel_id"], "image_sha256": image_hash,
                "reviewer": "Human", "started_at": "2026-09-23T00:00:00Z",
                "verified_at": "2026-09-23T00:01:00Z", "correction_seconds": 30,
                "verification_assertion": True, "verification_status": "independently_verified",
                "full_transcript": "Salt 0.1g", "families": ["salt", "per_100g"],
                "cells": [{
                    "row_id": "salt", "parent_row_id": None, "header_id": "header_1",
                    "basis": "per_100g", "printed_text": "0.1g", "comparator": None,
                    "decimal_text": "0.1", "unit": "g", "serving_conversion": None,
                }],
                "requires_decline": decline,
                "decline_reason": "Need confirmation" if decline else None,
            }
            (self.workspace / "annotations" / f"{index:03d}.json").write_text(json.dumps(annotation))
        (self.workspace / "review-manifest.json").write_text(json.dumps({
            "review_status": "development_review_not_gate", "panels": panels,
        }))
        self.approval = {
            "decision": "all_saved_declines_final", "source": "Explicit user approval",
            "approved_panel_indices": [1],
            "final_reason_overrides": {"1": "Final exclusion reason"},
        }
        self.save_approval()

    def save_approval(self) -> None:
        self.approval_path.write_text(json.dumps(self.approval))

    def test_freezes_without_gate_promotion_or_rewriting_annotation(self) -> None:
        snapshot = build_snapshot(self.workspace, self.approval_path)
        self.assertFalse(snapshot["acceptance_gate"])
        self.assertEqual(snapshot["counts"], {"panels": 40, "usable_tables": 39, "declines": 1})
        self.assertEqual(snapshot["panels"][0]["ground_truth"]["decline_reason"], "Final exclusion reason")
        self.assertEqual(snapshot["panels"][0]["original_decline_reason"], "Need confirmation")
        original = json.loads((self.workspace / "annotations" / "001.json").read_text())
        self.assertEqual(original["decline_reason"], "Need confirmation")

    def test_rejects_mismatched_approval(self) -> None:
        self.approval["approved_panel_indices"] = []
        self.save_approval()
        with self.assertRaisesRegex(ValueError, "approved decline indices"):
            build_snapshot(self.workspace, self.approval_path)

    def test_rejects_changed_image_bytes(self) -> None:
        (self.workspace / "images" / "001.jpg").write_bytes(b"changed")
        with self.assertRaisesRegex(ValueError, "image hash mismatch"):
            build_snapshot(self.workspace, self.approval_path)

    def test_rejects_unverified_annotation(self) -> None:
        path = self.workspace / "annotations" / "002.json"
        annotation = json.loads(path.read_text())
        annotation["verification_assertion"] = False
        path.write_text(json.dumps(annotation))
        with self.assertRaisesRegex(ValueError, "visual verification assertion"):
            build_snapshot(self.workspace, self.approval_path)


if __name__ == "__main__":
    unittest.main()
