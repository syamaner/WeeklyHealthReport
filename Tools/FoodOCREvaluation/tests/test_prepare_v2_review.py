from __future__ import annotations

import hashlib
import json
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from prepare_v2_review import prepare


class PrepareV2ReviewTests(unittest.TestCase):
    def setUp(self) -> None:
        self.old_hash = hashlib.sha256(b"old").hexdigest()
        self.new_hash = hashlib.sha256(b"new public image").hexdigest()
        old = {"panel_id": "old", "image_sha256": self.old_hash,
               "ground_truth": {"verification_status": "pending"},
               "source": {"product_code": "1", "image_url": "https://images.openfoodfacts.org/images/products/1/old.full.jpg"},
               "local_image": "old.jpg", "split": "untouched_gate"}
        new = {"panel_id": "new", "image_sha256": self.new_hash,
               "ground_truth": {"verification_status": "pending"},
               "source": {"product_code": "2", "product_name": "Public sample",
                          "image_url": "https://images.openfoodfacts.org/images/products/2/new.full.jpg"},
               "local_image": "new.jpg", "split": "tuning"}
        self.candidate = {"schema_version": 1, "panels": [old, new]}
        self.selection = {"schema_version": 1, "panels": [old]}
        self.truth = {"schema_version": 1, "panels": [old]}

    def test_prepares_review_without_gate_or_vision_and_refuses_overwrite(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            workspace = Path(directory) / "review"
            manifest = prepare(self.candidate, self.selection, self.truth, workspace,
                               fetch=lambda _: b"new public image",
                               ocr=lambda _: [("tesseract-test", "Per 100g\nFat 2g")])
            self.assertEqual(manifest["review_status"], "development_review_not_gate")
            self.assertEqual(len(manifest["panels"]), 1)
            self.assertEqual(manifest["panels"][0]["panel_id"], "new")
            self.assertEqual(manifest["panels"][0]["draft_source"], "tesseract-test")
            self.assertTrue((workspace / "images" / manifest["panels"][0]["image_file"]).is_file())
            self.assertEqual(json.loads((workspace / "review-manifest.json").read_text()), manifest)
            with self.assertRaisesRegex(ValueError, "refusing to overwrite"):
                prepare(self.candidate, self.selection, self.truth, workspace,
                        fetch=lambda _: b"new public image", ocr=lambda _: [])

    def test_hash_mismatch_cannot_create_review_manifest(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            workspace = Path(directory) / "review"
            with self.assertRaisesRegex(ValueError, "hash mismatch"):
                prepare(self.candidate, self.selection, self.truth, workspace,
                        fetch=lambda _: b"changed", ocr=lambda _: [])
            self.assertFalse((workspace / "review-manifest.json").exists())


if __name__ == "__main__":
    unittest.main()
