from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from augment_review_with_off_ocr import extract_transcript, role_and_revision, sidecar_url


class PublicOCRAugmentationTests(unittest.TestCase):
    def test_extracts_google_full_text(self) -> None:
        payload = {"responses": [{"fullTextAnnotation": {"text": "Energy 100 kJ\n"}}]}
        self.assertEqual(extract_transcript(payload), "Energy 100 kJ")

    def test_selected_role_and_revision_are_frozen(self) -> None:
        self.assertEqual(role_and_revision("off:123:nutrition_en.10"), ("nutrition_en", 10))

    def test_sidecar_uses_original_image_id(self) -> None:
        selected = "https://images.openfoodfacts.org/images/products/505/754/580/8979/nutrition_en.10.full.jpg"
        self.assertEqual(
            sidecar_url(selected, "3"),
            "https://images.openfoodfacts.org/images/products/505/754/580/8979/3.json",
        )


if __name__ == "__main__":
    unittest.main()
