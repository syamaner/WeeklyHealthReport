#!/usr/bin/env python3
"""Offline projection audit; lexical coverage evidence, not a search replay or identity verdict."""
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
RESOURCES = ROOT / "Packages/FoodLedgerKit/Sources/FoodGenericSearch/Resources"


def inspect(path):
    data = path.read_bytes()
    records = json.loads(data)["records"]
    cofid = path.name.startswith("cofid")

    def project(record):
        fat = record["nutrients"].get("fat_total", {})
        return {
            "id": record["record_id" if cofid else "id"],
            "name": record["name"],
            "description": record.get("description"),
            "basis": record["identity"]["serving_basis"] if cofid else "per_100_g",
            "fat": fat,
        }

    yoghurt = [r for r in records if "yog" in r["name"].lower()]
    greek = [r for r in yoghurt if "greek" in r["name"].lower()]
    milk = [r for r in records if "milk" in r["name"].lower()]
    numeric_ten = []
    for record in yoghurt:
        fat = record["nutrients"].get("fat_total", {})
        value = fat.get("value") if cofid and fat.get("state") == "numeric" else fat.get("amount") if not cofid else None
        if value is not None and abs(float(value) - 10) < 0.000001:
            numeric_ten.append(project(record))
    return {
        "file": path.name, "sha256": hashlib.sha256(data).hexdigest(),
        "records": len(records), "yoghurt_name_hits": len(yoghurt),
        "greek_yoghurt_name_hits": len(greek),
        "greek_yoghurt_records": [project(r) for r in greek],
        "yoghurt_numeric_10g_fat_hits": numeric_ten,
        "milk_name_hits": len(milk),
        "milk_volume_basis_records": [project(r) for r in milk if cofid and r["identity"]["serving_basis"] == "per_100_ml"],
        "selected_whole_milk": [project(r) for r in records if r["name"] == "Milk, whole, pasteurised, average"],
    }


if __name__ == "__main__":
    print(json.dumps({"audit_version": 1, "scope": "complete bundled projections, lexical name predicates; no network or ranking simulation",
                      "sources": [inspect(RESOURCES / name) for name in
                                  ("cofid-2021-generic-search-v1.json", "usda-generic-v1.json")]}, indent=2))
