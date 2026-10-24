#!/usr/bin/env python3
"""Project the count portion guide manifest (count-portion-estimate-v1, #307) from a local,
hash-pinned USDA SR Legacy April 2018 archive. Offline only: it never downloads.

Usage:
  python3 -I Tools/FoodSourceEvaluation/project_usda_count_portions.py ARCHIVE.zip \
      Packages/FoodLedgerKit/Sources/FoodGenericSearch/Resources/count-portion-guides-v1.json
"""
import hashlib
import json
import sys
import zipfile
from pathlib import Path

ARCHIVE_SHA256 = "0fe8ae486a2c8eb42cb96413f058deb51863a46c8fb8eeb4b1fb45006dd338ef"
ARCHIVE_NAME = "FoodData_Central_sr_legacy_food_json_2018-04.zip"
RELEASE_DATE = "2018-04-01"
RAW_FDC, BOILED_FDC = 171287, 173424
# (size, portion ID, source descriptor, expected grams); the expected values are the reviewed
# table in docs/count-portion-estimate-v1.md section 3. Any difference stops the projection.
RAW_PORTIONS = [("small", 88379, "small", 38.0), ("medium", 88378, "medium", 44.0),
                ("large", 88374, "large", 50.0), ("extra_large", 88375, "extra large", 56.0)]
BOILED_LARGE = ("large", 92500, "large", 50.0)
# The app's USDA candidates carry the bundled projection's release ID (USDAGenericFoodSearch:
# "<release>:projection:<corpus SHA-256>") and the record ID "<release>:fdc:<id>".
USDA_RECORD_PREFIX = "usda-legacy:2018-04-01:sha256:" + ARCHIVE_SHA256
USDA_CORPUS_SHA256 = "6759b10f419ecdfd5395d469b0ff51d58e59e29d40f31e2087ae9455da6a4bd4"
USDA_RELEASE = USDA_RECORD_PREFIX + ":projection:" + USDA_CORPUS_SHA256
COFID_RELEASE = "cofid:2021:sha256:436e9445ef2adb2a75f3d7edd51302de3adad25385f9795fc94ba58bd030e97d"
RAW_RECORDS = [[USDA_RELEASE, USDA_RECORD_PREFIX + ":fdc:171287"],
               [COFID_RELEASE, COFID_RELEASE + ":row:1096:a72b3e44d2dadad3"]]
BOILED_RECORDS = [[USDA_RELEASE, USDA_RECORD_PREFIX + ":fdc:173424"],
                  [COFID_RELEASE, COFID_RELEASE + ":row:1091:0fe190b81c244ccf"]]


def portions(foods, fdc_id):
    food = next((f for f in foods if isinstance(f, dict) and f.get("fdcId") == fdc_id), None)
    if food is None:
        raise SystemExit(f"FDC record {fdc_id} not found")
    return {p["id"]: p for p in food.get("foodPortions", [])}


def check(found, portion_id, descriptor, grams):
    portion = found.get(portion_id)
    if portion is None:
        raise SystemExit(f"portion {portion_id} missing")
    if portion.get("modifier") != descriptor or portion.get("amount") != 1.0 or portion.get("gramWeight") != grams:
        raise SystemExit(f"portion {portion_id} differs from the reviewed table: {portion}")


def entry(code, size, grams, preparation, derived, fdc, portion, descriptor, applies_to, default):
    return {"guide_id": "count_portion_guide_v1:" + code, "size": size, "grams": grams,
            "part": "whole_without_shell", "preparation": preparation,
            "source_fdc_id": fdc, "source_portion_id": portion, "source_descriptor": descriptor,
            "derivation": "raw_size_weight_for_boiled" if derived else "none",
            "default": default, "applies_to": applies_to}


def main(archive, output):
    raw = Path(archive).read_bytes()
    digest = hashlib.sha256(raw).hexdigest()
    if digest != ARCHIVE_SHA256:
        raise SystemExit("archive hash mismatch: " + digest)
    with zipfile.ZipFile(archive) as z:
        member = next(n for n in z.namelist() if n.endswith(".json"))
        foods = next(iter(json.loads(z.read(member)).values()))
    raw_found, boiled_found = portions(foods, RAW_FDC), portions(foods, BOILED_FDC)
    for _, portion, descriptor, grams in RAW_PORTIONS:
        check(raw_found, portion, descriptor, grams)
    check(boiled_found, BOILED_LARGE[1], BOILED_LARGE[2], BOILED_LARGE[3])
    guides = []
    for size, portion, descriptor, grams in RAW_PORTIONS:
        guides.append(entry(f"usda_sr_legacy_{RAW_FDC}_{portion}", size, grams, "raw", False, RAW_FDC, portion,
                            descriptor, RAW_RECORDS, size == "large"))
    for size, portion, descriptor, grams in RAW_PORTIONS:
        if size == "large":
            _, bportion, bdescriptor, bgrams = BOILED_LARGE
            guides.append(entry(f"usda_sr_legacy_{BOILED_FDC}_{bportion}", size, bgrams, "boiled", False, BOILED_FDC,
                                bportion, bdescriptor, BOILED_RECORDS, True))
        else:
            guides.append(entry(f"usda_sr_legacy_boiled_from_{RAW_FDC}_{portion}", size, grams, "boiled", True, RAW_FDC,
                                portion, descriptor, BOILED_RECORDS, False))
    manifest = {
        "guide_set_id": "count-portion-guides-v1",
        "source": {
            "title": "USDA FoodData Central, SR Legacy, April 2018",
            "archive_file": ARCHIVE_NAME,
            "archive_sha256": ARCHIVE_SHA256,
            "release_date": RELEASE_DATE,
            "licence": "CC0 1.0",
            "attribution": "USDA FoodData Central, SR Legacy, April 2018 (public domain, CC0 1.0). Typical edible weights of one egg without shell.",
            "documentation_url": "https://fdc.nal.usda.gov/data-documentation/",
        },
        "guides": guides,
    }
    text = json.dumps(manifest, indent=1, sort_keys=True, ensure_ascii=False) + "\n"
    Path(output).write_text(text, encoding="utf-8")
    print("archive sha256", digest)
    print("manifest sha256", hashlib.sha256(text.encode("utf-8")).hexdigest())


if __name__ == "__main__":
    if len(sys.argv) != 3:
        raise SystemExit(__doc__)
    main(sys.argv[1], sys.argv[2])
