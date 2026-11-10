#!/usr/bin/env python3
"""Synthetic tests for off_rules.project (the port of the app's OpenFoodFactsLookup rules).

Usage: python3 -I test_off_rules.py <scripts_dir>
"""
import sys

sys.path.insert(0, sys.argv[1])
import off_rules as R  # noqa: E402


def legacy(**over):
    p = {"code": "0000000000017", "product_name": "Synthetic oats", "quantity": "500 g", "nutrition_data_per": "100g",
         "nutriments": {"energy-kcal_100g": 370, "energy-kcal_unit": "kcal", "fat_100g": 7, "fat_unit": "g",
                        "sodium_100g": 0.4, "sodium_unit": "mg", "calcium_100g": 0.05, "calcium_unit": "mg"}}
    p.update(over)
    return p


def modern(per="100g", qty="500 g", sodium=(0.4, "g"), modifier=None):
    n = {"energy-kcal": {"value": 370, "unit": "kcal"}, "sodium": {"value": sodium[0], "unit": sodium[1]}}
    if modifier:
        n["sugars"] = {"value": 0.5, "unit": "g", "modifier": modifier}
    return {"code": "00000017", "product_name": "Synthetic drink", "quantity": qty,
            "nutrition": {"input_sets": [{"source": "packaging", "per": per, "preparation": "as_sold", "nutrients": n}]}}


def run(p):
    return R.project(p, b"{}")


CHECKS = []


def check(name, cond):
    CHECKS.append((name, bool(cond)))


r = run(legacy())
check("legacy record admitted with energy and fat", r and r[3]["energy_consumed"]["value"] == 370 and "fat_total" in r[3])
check("legacy sodium is unknown (never 0.4 mg)", r and "sodium" not in r[3])
check("micronutrients are never taken", r and "calcium" not in r[3])
check("record identity is off:gtin:<GTIN-14>", r and r[1] == "off:gtin:00000000000017")
check("non-string quantity treated as missing, no crash", run(legacy(quantity=500)) is None)
check("non-dictionary input set refused like the app", run({**modern(), "nutrition": {"input_sets": [1]}}) is None)
rr = R.project(legacy(), b"{}", "2026-11-07")
check("release fields are a function of its ID (retrieved date in both)",
      rr and rr[2]["source_release_id"].endswith(":retrieved:2026-11-07") and rr[2]["released_at"] == "2026-11-07T00:00:00Z")
check("per-serving legacy record refused", run(legacy(nutrition_data_per="serving")) is None)
check("supplement refused", run(legacy(categories_tags=["en:dietary-supplements"])) is None)
check("categories_tags as a string is treated as empty, like the app", run(legacy(categories_tags="en:dietary-supplements")) is not None)
check("categories_tags as a number does not crash", run(legacy(categories_tags=7)) is not None)
check("pack with mass and volume refused", run(legacy(quantity="500 g / 500 ml")) is None)
check("legacy volume record refused", run(legacy(quantity="1 l")) is None)
m = run(modern())
check("modern sodium g -> mg with transform and source value",
      m and m[3]["sodium"]["value"] == 400 and m[3]["sodium"]["transforms"][0]["transform_id"] == "mass-g-to-mg"
      and m[3]["sodium"]["source_value"] == {"value": 0.4, "unit": "g"})
v = run(modern(per="100ml", qty="1 l"))
check("volume product uses per-100-ml basis", v and v[0] == "per_100_ml_as_labelled")
check("panel per 100 g on a volume product refused", run(modern(per="100g", qty="1 l")) is None)
check("'<' value left out, never exact", (lambda x: x and "sugar" not in x[3])(run(modern(modifier="<"))))
check("unknown modifier left out", (lambda x: x and "sugar" not in x[3])(run(modern(modifier="~"))))
check("non-canonical unit left out", (lambda x: x and "sodium" not in x[3])(run(modern(sodium=(400, "µg")))))
check("boolean value refused", (lambda x: x is None or "energy_consumed" not in x[3])(
    run(legacy(nutriments={"energy-kcal_100g": True, "energy-kcal_unit": "kcal"}))))

# off-product-projection-v5 (#458): with no recognised pack quantity, the single eligible panel
# states its own basis; every v4 refusal stays.
for qty in (None, "", "3 oz", "1 bar"):
    for per, basis in (("100g", "per_100_g"), ("100ml", "per_100_ml_as_labelled")):
        p = modern(per=per, qty=qty if qty is not None else "")
        if qty is None:
            p.pop("quantity")
        r5 = run(p)
        check(f"no recognised pack ({qty!r}) uses the panel's {per} basis", r5 and r5[0] == basis
              and r5[2]["pipeline_version"] == "off-product-projection-v5" and ":off-product-projection-v5:" in r5[2]["source_release_id"])
two = modern(qty="3 oz")
two["nutrition"]["input_sets"].append(dict(two["nutrition"]["input_sets"][0], per="100ml"))
check("two panels with no pack basis refused", run(two) is None)
check("legacy record with no pack refused", run(legacy(quantity="")) is None)
check("legacy record with an unrecognised pack refused", run(legacy(quantity="3 oz")) is None)
check("mass pack still refuses a lone per 100 ml panel", run(modern(per="100ml", qty="500 g")) is None)
for bad in ([], ["100g"], {}, {"per": "100g"}, 100):
    malformed = modern(qty="")
    malformed["nutrition"]["input_sets"][0]["per"] = bad
    try:
        refused = run(malformed) is None
    except TypeError:
        refused = False
    check(f"malformed panel per {bad!r} is declined, not raised", refused)
wrong_unit = modern(qty="")
wrong_unit["nutrition"]["input_sets"][0]["per_unit"] = "ml"
check("panel unit that contradicts its per refused", run(wrong_unit) is None)

import json as _json, os as _os, tempfile as _tempfile
from pathlib import Path as _Path
with _tempfile.TemporaryDirectory() as _d:
    def _cached(status, warnings):
        p = _Path(_d) / "x.json"
        p.write_text(_json.dumps({"api": "v3.6", "requested": "00000017", "status": status, "warnings": warnings,
                                  "product": {"code": "00000017", "product_name": "x"}}))
        return R.load(p)[0] is not None
    check("success record loads", _cached("success", None))
    check("normalisation-only warning loads, like the app",
          _cached("success_with_warnings", [{"message": {"id": "different_normalized_product_code"}, "impact": {"id": "none"}}]))
    check("any other warning is refused", not _cached("success_with_warnings", [{"message": {"id": "x"}, "impact": {"id": "warning"}}]))
    check("warnings not recorded are refused", not _cached("success_with_warnings", None))
failed = [n for n, ok in CHECKS if not ok]
print(f"{len(CHECKS) - len(failed)} of {len(CHECKS)} Open Food Facts rule checks pass")
if failed:
    print("FAILED:", failed)
    sys.exit(1)
