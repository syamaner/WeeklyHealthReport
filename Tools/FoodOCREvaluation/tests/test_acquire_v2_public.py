from __future__ import annotations

import hashlib
import json
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from acquire_v2_public import acquire, legacy_exclusions, selected_raw_source
from freeze_v2_public import freeze
from prepare_v2_public_review import prepare
from validate_contract_v2 import select_split


class AcquireV2PublicTests(unittest.TestCase):
    def setUp(self) -> None:
        self.contract = json.loads((ROOT / "frozen-contract-v2.json").read_text())

    def test_selected_raw_source_requires_uk_nutrition_role_and_raw_id(self) -> None:
        product = {
            "code": "5060131761954", "countries_tags": ["en:united-kingdom"],
            "images": {"nutrition_en": {"imgid": "2", "rev": "5"}},
        }
        source = selected_raw_source(product, self.contract)
        self.assertEqual(source["panel_id"], "off:5060131761954:nutrition_en.5:raw-2")
        self.assertEqual(
            source["raw_image_url"],
            "https://openfoodfacts-images.s3.eu-west-3.amazonaws.com/data/506/013/176/1954/2.jpg",
        )
        product["images"]["nutrition_en"].pop("imgid")
        self.assertIsNone(selected_raw_source(product, self.contract))
        product["countries_tags"] = ["en:france"]
        self.assertIsNone(selected_raw_source(product, self.contract))

    def test_legacy_exclusions_include_products_from_panel_ids(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "legacy.json"
            path.write_text(json.dumps({"panels": [{
                "panel_id": "off:5060131761954:nutrition_en.5",
                "image_sha256": "a" * 64,
            }]}))
            ids, hashes, codes = legacy_exclusions([path])
        self.assertIn("off:5060131761954:nutrition_en.5", ids)
        self.assertIn("a" * 64, hashes)
        self.assertIn("5060131761954", codes)

    def test_acquisition_checkpoints_raw_hashes_without_opening_gate(self) -> None:
        products = [{
            "code": str(5000000000000 + index),
            "countries_tags": ["en:united-kingdom"],
            "images": {"nutrition_en": {"imgid": "2", "rev": "5"}},
        } for index in range(142)]
        images = {}
        for index, product in enumerate(products):
            source = selected_raw_source(product, self.contract)
            images[source["raw_image_url"]] = b"\xff\xd8\xff" + str(index).encode() + b"\xff\xd9"
        calls = []

        def fetch(url: str) -> bytes:
            calls.append(url)
            if "api/v2/search" in url:
                page = int(url.split("page=")[1].split("&")[0])
                subset = products[:100] if page == 1 else products[100:141] if page == 2 else products[141:]
                return json.dumps({"products": subset}).encode()
            return images[url]

        with tempfile.TemporaryDirectory() as folder:
            state = acquire(
                self.contract, Path(folder), excluded_ids=set(), excluded_hashes=set(),
                excluded_codes={products[0]["code"]}, target=140, maximum_pages=2,
                fetch=fetch, sleep=lambda _: None,
            )
            self.assertEqual(len(state["panels"]), 140)
            self.assertEqual(state["status"], "candidate_inventory_only_no_ground_truth_or_gate")
            self.assertEqual(len(state["search_responses"]), 2)
            self.assertEqual(state["panels"][0]["product_code"], products[1]["code"])
            first = state["panels"][0]
            self.assertEqual(
                hashlib.sha256((Path(folder) / first["local_image"]).read_bytes()).hexdigest(),
                first["image_sha256"],
            )
            split = select_split(
                self.contract, state["panels"], excluded_panel_ids=set(),
                excluded_image_hashes=set(), excluded_product_codes={products[0]["code"]},
            )
            self.assertEqual(list(split.values()).count("untouched_gate"), 40)
            replay = acquire(
                self.contract, Path(folder), excluded_ids=set(), excluded_hashes=set(),
                excluded_codes={products[0]["code"]}, target=140, maximum_pages=2,
                fetch=fetch, sleep=lambda _: None,
            )
            self.assertEqual(replay, state)
            self.assertEqual(len([url for url in calls if "api/v2/search" in url]), 2)
            resumed = acquire(
                self.contract, Path(folder), excluded_ids=set(), excluded_hashes=set(),
                excluded_codes={products[0]["code"]}, newly_exposed_codes={products[1]["code"]},
                target=140, maximum_pages=3, fetch=fetch, sleep=lambda _: None,
            )
            self.assertEqual(len(resumed["panels"]), 140)
            self.assertEqual(resumed["development_exposures"][0]["panel_id"], first["panel_id"])
            self.assertNotIn(first["panel_id"], {panel["panel_id"] for panel in resumed["panels"]})
            self.assertEqual(len(resumed["search_responses"]), 3)
            frozen = freeze(
                self.contract, resumed, Path(folder), excluded_ids=set(),
                excluded_hashes=set(), excluded_codes={products[0]["code"]},
            )
            self.assertEqual(len(frozen["panels"]), 100)
            self.assertEqual([panel["split"] for panel in frozen["panels"]].count("untouched_gate"), 40)
            self.assertNotIn(first["panel_id"], {panel["panel_id"] for panel in frozen["panels"]})
            self.assertEqual(frozen["status"], "identities_and_split_frozen_no_ground_truth_or_gate")
            review = prepare(frozen, Path(folder), Path(folder) / "review")
            self.assertEqual(len(review["panels"]), 100)
            self.assertEqual(review["panels"][0]["draft_transcript"], "")
            self.assertTrue(all("split" not in panel for panel in review["panels"]))


if __name__ == "__main__":
    unittest.main()
