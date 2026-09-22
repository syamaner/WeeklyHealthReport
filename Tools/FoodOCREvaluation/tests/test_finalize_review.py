import json
import tempfile
import unittest
from pathlib import Path

from finalize_review import finalize


class FinalizeReviewTests(unittest.TestCase):
    def test_rejects_annotation_identity_mismatch(self):
        selection = {
            "counts": {"tuning": 60, "untouched_gate": 40},
            "panels": [{"panel_id": "expected", "split": "tuning", "image_sha256": "a" * 64}],
        }
        review_manifest = {
            "panels": [{
                "review_index": 1,
                "panel_id": "expected",
                "image_sha256": "a" * 64,
                "image_url": "https://example.test/image.jpg",
                "product_code": "1",
                "product_name": "Example",
            }]
        }
        annotation = {
            "schema_version": 1,
            "panel_id": "swapped",
            "image_sha256": "b" * 64,
            "reviewer": "Reviewer",
            "started_at": "2026-09-22T00:00:00+00:00",
            "verified_at": "2026-09-22T00:01:00+00:00",
            "correction_seconds": 60,
            "full_transcript": "Energy 1kJ",
            "cells": [],
            "families": [],
            "requires_decline": True,
            "decline_reason": "Table unreadable",
            "verification_assertion": True,
            "verification_status": "independently_verified",
        }
        with tempfile.TemporaryDirectory() as directory:
            annotations = Path(directory)
            (annotations / "001.json").write_text(json.dumps(annotation))
            with self.assertRaisesRegex(ValueError, "identity or image hash mismatch"):
                finalize(selection, review_manifest, annotations)


if __name__ == "__main__":
    unittest.main()
