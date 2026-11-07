#!/usr/bin/env python3
"""Fetch the full Open Food Facts product record for every chosen label match.

Uses the app's own endpoint (API v3.6). Search results are used only to find a match: they carry no `_unit` or `_modifier`
fields, so they cannot show whether a value was "<0.5 g". Label values are taken
only from the product record, under the same rules as the app's OpenFoodFactsLookup.
Only barcodes are sent. All calls go through http_client.Client.

Usage: python3 -I fetch_off_products.py <work_dir> <catalogue_json>
"""
import json
import re
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from http_client import CircuitOpen, Client  # noqa: E402
from workspace_guard import check_output  # noqa: E402

FIELDS = "code,product_name,brands,quantity,nutriments,nutrition,nutrition_data_per,categories_tags,countries_tags"


def main(work: Path, catalogue: Path):
    cat = json.load(open(catalogue))
    codes = set()
    for i in cat["items"]:
        for key in ("label_candidate", "other_brand_label"):
            lab = i.get(key) or {}
            if lab.get("status") in ("probable", "other_brand_used") and re.fullmatch(r"[0-9]{8}|[0-9]{12,14}", str(lab.get("code") or "")):  # the lengths the app admits
                codes.add(lab["code"])
    out = work / "off-products-v3"  # API v3.6, as OpenFoodFactsLookup reads it
    out.mkdir(exist_ok=True)
    todo = sorted(c for c in codes if not (out / f"{c}.json").exists())
    print(f"chosen products: {len(codes)}, to fetch: {len(todo)}", flush=True)
    client = Client(log=lambda m: print(m, flush=True))
    done = errors = 0
    try:
        for code in todo:
            url = f"https://world.openfoodfacts.org/api/v3.6/product/{code}.json"  # the app's endpoint
            try:
                d = client.get_json(url)
                (out / f"{code}.json").write_text(json.dumps(
                    {"retrieved": time.strftime("%Y-%m-%d", time.gmtime()), "requested": code, "api": "v3.6",
                     "status": d.get("status"), "warnings": d.get("warnings"), "product": d.get("product")},
                    ensure_ascii=False))
                done += 1
            except CircuitOpen:
                raise
            except Exception as e:  # recorded; that product contributes no label values
                (out / f"{code}.error").write_text(f"{type(e).__name__}: {e}")
                errors += 1
            if (done + errors) % 25 == 0:
                print(f"progress done={done} errors={errors}", flush=True)
    except CircuitOpen as e:
        print(f"stopped: {e}", flush=True)
    print(f"finished done={done} errors={errors}", flush=True)


if __name__ == "__main__":
    main(check_output(sys.argv[1]), Path(sys.argv[2]))
