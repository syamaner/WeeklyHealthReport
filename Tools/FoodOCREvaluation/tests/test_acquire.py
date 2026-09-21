from __future__ import annotations

import sys
import gzip
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from acquire import candidate_codes_from_aws_index, full_image_url, panel_id, selected_nutrition


class AcquisitionTests(unittest.TestCase):
    def test_selected_display_url_maps_to_revision_pinned_full_image(self) -> None:
        product = {
            "selected_images": {
                "nutrition": {
                    "display": {
                        "en": "https://images.openfoodfacts.org/images/products/506/333/403/2197/nutrition_en.11.400.jpg"
                    }
                }
            }
        }
        self.assertEqual(
            selected_nutrition(product),
            ("en", "https://images.openfoodfacts.org/images/products/506/333/403/2197/nutrition_en.11.full.jpg"),
        )

    def test_panel_id_includes_product_role_language_and_revision(self) -> None:
        url = "https://images.openfoodfacts.org/images/products/506/333/403/2197/nutrition_en.11.full.jpg"
        self.assertEqual(panel_id("5063334032197", url), "off:5063334032197:nutrition_en.11")

    def test_unrecognised_image_host_fails_closed(self) -> None:
        with self.assertRaisesRegex(ValueError, "unsupported selected image URL"):
            full_image_url("https://example.com/nutrition_en.1.400.jpg")

    def test_aws_index_candidates_are_deterministic_and_only_product_codes(self) -> None:
        fixture = b"\n".join([
            b"data/506/333/403/2197/3.json.gz",
            b"data/506/333/403/2197/3.jpg",
            b"data/400/000/000/0000/1.json.gz",
            b"data/500/000/000/0012/7.json.gz",
            b"data/not-a-code/1.json.gz",
        ]) + b"\n"
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "keys.gz"
            path.write_bytes(gzip.compress(fixture, mtime=0))
            codes = candidate_codes_from_aws_index(path)
        self.assertEqual(set(codes), {"5063334032197", "5000000000012"})
        self.assertEqual(codes, candidate_codes_from_aws_index_from_bytes(fixture))


def candidate_codes_from_aws_index_from_bytes(value: bytes) -> list[str]:
    with tempfile.TemporaryDirectory() as directory:
        path = Path(directory) / "keys.gz"
        path.write_bytes(gzip.compress(value, mtime=0))
        return candidate_codes_from_aws_index(path)


if __name__ == "__main__":
    unittest.main()
