#!/usr/bin/env python3
"""Build and analyse the redacted Tesco Grocery 1.0 OFF legacy cohort."""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
from collections import Counter, defaultdict
from pathlib import Path
from statistics import median
from typing import Any


EXPECTED_SOURCE_SHA256 = "e79c86e1247408238d3062c7f78f18ca054d68d8d1e6def92ea70435347e3f15"
SOURCE_RELEASE_ID = f"tesco-grocery-1.0-food-categories-v2-{EXPECTED_SOURCE_SHA256}"
SAMPLE_PER_CATEGORY = 3

OFF_NUTRIENT_MAPPING = {
    "energy_consumed": "energy-kcal",
    "carbohydrates": "carbohydrates",
    "protein": "proteins",
    "fat_total": "fat",
    "fat_saturated": "saturated-fat",
    "fat_monounsaturated": "monounsaturated-fat",
    "fat_polyunsaturated": "polyunsaturated-fat",
    "fiber": "fiber",
    "sugar": "sugars",
    "cholesterol": "cholesterol",
    "vitamin_a": "vitamin-a",
    "thiamin_b1": "vitamin-b1",
    "riboflavin_b2": "vitamin-b2",
    "niacin_b3": "vitamin-pp",
    "pantothenic_acid_b5": "pantothenic-acid",
    "vitamin_b6": "vitamin-b6",
    "biotin_b7": "biotin",
    "folate_b9": "folates",
    "vitamin_b12": "vitamin-b12",
    "vitamin_c": "vitamin-c",
    "vitamin_d": "vitamin-d",
    "vitamin_e": "vitamin-e",
    "vitamin_k": "vitamin-k",
    "calcium": "calcium",
    "chloride": "chloride",
    "iron": "iron",
    "magnesium": "magnesium",
    "phosphorus": "phosphorus",
    "potassium": "potassium",
    "sodium": "sodium",
    "zinc": "zinc",
    "chromium": "chromium",
    "copper": "copper",
    "iodine": "iodine",
    "manganese": "manganese",
    "molybdenum": "molybdenum",
    "selenium": "selenium",
    "water": "water",
    "caffeine": "caffeine",
}

IDENTITY_FIELDS = [
    "product_name",
    "generic_name",
    "brands",
    "quantity",
    "packaging",
    "packaging_tags",
    "categories_tags",
    "countries_tags",
    "labels_tags",
    "serving_size",
    "nutrition_data_per",
    "ingredients_text",
    "last_modified_t",
]


def is_valid_gtin(value: str) -> bool:
    if not value.isdigit():
        return False
    digits = [int(character) for character in value.zfill(13)]
    weighted = sum((1 if index % 2 == 0 else 3) * digit for index, digit in enumerate(digits[:-1]))
    return (10 - weighted % 10) % 10 == digits[-1]


def build_sample(source: Path) -> dict[str, Any]:
    source_bytes = source.read_bytes()
    source_sha256 = hashlib.sha256(source_bytes).hexdigest()
    if source_sha256 != EXPECTED_SOURCE_SHA256:
        raise ValueError(
            f"unexpected Tesco source SHA-256: {source_sha256}; expected {EXPECTED_SOURCE_SHA256}"
        )
    rows = list(csv.DictReader(source_bytes.decode("utf-8-sig").splitlines()))
    by_category: dict[str, list[tuple[str, str]]] = defaultdict(list)
    scientific_notation = 0
    invalid_checksum = 0

    for row in rows:
        raw_gtin = row["gtin"]
        if not raw_gtin.isdigit():
            scientific_notation += 1
            continue
        if not is_valid_gtin(raw_gtin):
            invalid_checksum += 1
            continue
        gtin = raw_gtin.zfill(13)
        rank = hashlib.sha256(
            f"{SOURCE_RELEASE_ID}|{row['category']}|{gtin}".encode("utf-8")
        ).hexdigest()
        by_category[row["category"]].append((rank, gtin))

    sample = []
    for category in sorted(by_category):
        for ordinal, (rank, gtin) in enumerate(sorted(by_category[category])[:SAMPLE_PER_CATEGORY], 1):
            sample.append(
                {
                    "case_id": f"{category}-{ordinal:02d}",
                    "category": category,
                    "gtin": gtin,
                    "selection_rank": rank,
                }
            )

    canonical_private_sample = json.dumps(
        sample,
        sort_keys=True,
        separators=(",", ":"),
    ).encode("utf-8")

    return {
        "source": {
            "release_id": SOURCE_RELEASE_ID,
            "bytes": len(source_bytes),
            "sha256": source_sha256,
            "expected_sha256_match": source_sha256 == EXPECTED_SOURCE_SHA256,
            "rows": len(rows),
            "scientific_notation_rows_excluded": scientific_notation,
            "invalid_check_digit_rows_excluded": invalid_checksum,
            "eligible_exact_gtins": sum(map(len, by_category.values())),
            "eligible_by_category": {key: len(value) for key, value in sorted(by_category.items())},
        },
        "selection": {
            "algorithm": "sha256(source_release_id|category|zero_padded_gtin), ascending",
            "per_category": SAMPLE_PER_CATEGORY,
            "categories": len(by_category),
            "cases": len(sample),
            "canonical_private_sample_sha256": hashlib.sha256(
                canonical_private_sample
            ).hexdigest(),
        },
        "sample": sample,
    }


def numeric_nutrient_count(product: dict[str, Any]) -> int:
    nutriments = product.get("nutriments") or {}
    return sum(
        isinstance(nutriments.get(f"{off_key}_100g"), (int, float))
        for off_key in OFF_NUTRIENT_MAPPING.values()
    )


def analyse_responses(sample: dict[str, Any], responses: Path) -> dict[str, Any]:
    hit_products = []
    response_hashes = []
    for case in sample["sample"]:
        path = responses / f"{case['case_id']}.json"
        response_bytes = path.read_bytes()
        response = json.loads(response_bytes)
        hit = (response.get("result") or {}).get("id") == "product_found"
        response_hashes.append(
            {
                "case_id": case["case_id"],
                "sha256": hashlib.sha256(response_bytes).hexdigest(),
                "hit": hit,
            }
        )
        if hit:
            hit_products.append(response.get("product") or {})

    field_counts = {
        field: sum(bool(product.get(field)) for product in hit_products)
        for field in IDENTITY_FIELDS
    }
    nutrient_counts = {
        catalogue_key: sum(
            isinstance((product.get("nutriments") or {}).get(f"{off_key}_100g"), (int, float))
            for product in hit_products
        )
        for catalogue_key, off_key in OFF_NUTRIENT_MAPPING.items()
    }
    per_hit_counts = [numeric_nutrient_count(product) for product in hit_products]

    return {
        "sample": sample["source"] | sample["selection"],
        "responses": {
            "cases": len(response_hashes),
            "hits": len(hit_products),
            "misses": len(response_hashes) - len(hit_products),
            "uk_country_tag_hits": sum(
                "en:united-kingdom" in (product.get("countries_tags") or [])
                for product in hit_products
            ),
            "response_manifest": response_hashes,
        },
        "identity_field_counts_among_hits": field_counts,
        "numeric_nutrient_counts_among_hits": nutrient_counts,
        "numeric_nutrient_summary_among_hits": {
            "available_cells": sum(per_hit_counts),
            "possible_cells": len(hit_products) * len(OFF_NUTRIENT_MAPPING),
            "median_per_hit": median(per_hit_counts) if per_hit_counts else None,
            "minimum_per_hit": min(per_hit_counts) if per_hit_counts else None,
            "maximum_per_hit": max(per_hit_counts) if per_hit_counts else None,
        },
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path)
    parser.add_argument("--responses", type=Path)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--redact", action="store_true")
    args = parser.parse_args()

    result = build_sample(args.source)
    if args.responses:
        result = analyse_responses(result, args.responses)
    elif args.redact:
        for case in result["sample"]:
            case.pop("gtin", None)
            case.pop("selection_rank", None)

    rendered = json.dumps(result, indent=2, ensure_ascii=False) + "\n"
    if args.output:
        args.output.write_text(rendered, encoding="utf-8")
    else:
        print(rendered, end="")


if __name__ == "__main__":
    main()
