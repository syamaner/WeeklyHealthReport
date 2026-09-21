#!/usr/bin/env python3
"""Inspect reviewed Open Food Facts layout annotations without downloading images."""

from __future__ import annotations

import argparse
import json
import time
import urllib.parse
import urllib.request
from pathlib import Path

DATASET = "openfoodfacts/nutrient-detection-layout"
BASE = "https://datasets-server.huggingface.co/rows"
SPLIT_SIZES = {"train": 2884, "test": 199}
USER_AGENT = "WeeklyHealthReport-evaluation/1.0 (https://github.com/syamaner/WeeklyHealthReport)"


def fetch(split: str, offset: int) -> dict:
    query = urllib.parse.urlencode({
        "dataset": DATASET,
        "config": "default",
        "split": split,
        "offset": offset,
        "length": 100,
    })
    request = urllib.request.Request(f"{BASE}?{query}", headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(request, timeout=60) as response:
        return json.load(response)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    candidates = []
    for split, size in SPLIT_SIZES.items():
        for offset in range(0, size, 100):
            payload = fetch(split, offset)
            for wrapped in payload.get("rows", []):
                row = wrapped["row"]
                meta = row["meta"]
                barcode = meta["barcode"]
                if (
                    barcode.startswith("50")
                    and meta["checked"]
                    and not meta["no_nutrition_table"]
                ):
                    candidates.append({
                        "barcode": barcode,
                        "checked": True,
                        "image_id": meta["image_id"],
                        "image_url": meta["image_url"],
                        "layout_split": meta["split"],
                        "nutrition_text": meta["nutrition_text"],
                        "tokens": row["tokens"],
                        "ner_tags": row["ner_tags"],
                        "bboxes": row["bboxes"],
                    })
            print(f"split={split} offset={offset} candidates={len(candidates)}", flush=True)
            time.sleep(0.2)
    args.output.write_text(json.dumps({
        "schema_version": 1,
        "dataset": DATASET,
        "selection": "barcode starts 50, checked, contains nutrition table",
        "candidates": candidates,
    }, ensure_ascii=False, sort_keys=True, separators=(",", ":")) + "\n")


if __name__ == "__main__":
    main()
