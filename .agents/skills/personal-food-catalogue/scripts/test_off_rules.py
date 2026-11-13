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
pw = run(modern(per="100g", qty="1 l"))
check("panel per 100 g on a volume product: the panel wins under v6", pw and pw[0] == "per_100_g"
      and pw[2]["pipeline_version"] == "off-product-projection-v6" and ":off-product-projection-v6:" in pw[2]["source_release_id"]
      and pw[3]["sodium"]["transforms"] == [{"transform_id": "mass-g-to-mg", "version": "v1"}])
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
pm = run(modern(per="100ml", qty="500 g"))
check("mass pack with a lone per 100 ml panel: the panel wins under v6", pm and pm[0] == "per_100_ml_as_labelled"
      and pm[2]["pipeline_version"] == "off-product-projection-v6")
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

# off-product-projection-v6 (#477; catalogue v2): with no per 100 panel, one per-serving panel is
# scaled by 100 / serving. Each case is mirrored in OpenFoodFactsSkillParityTests.swift.
def serving(qty="500 g", per_quantity=28, per_unit="g", sodium=(0.4, "g"), extra=None, modifier=None, energy=100):
    n = {"energy-kcal": {"value": energy, "unit": "kcal"}, "sodium": {"value": sodium[0], "unit": sodium[1]}}
    if modifier:
        n["sugars"] = {"value": modifier[1], "unit": "g", "modifier": modifier[0]}
    panel = {"source": "packaging", "per": "serving", "preparation": "as_sold", "nutrients": n}
    if per_quantity is not None:
        panel["per_quantity"] = per_quantity
    if per_unit is not None:
        panel["per_unit"] = per_unit
    p = {"code": "00000017", "product_name": "Synthetic bar", "quantity": qty,
         "nutrition": {"input_sets": [panel] + (extra or [])}}
    return p


s28 = run(serving(sodium=(0.112, "mg")))
check("numeric 28 g serving scaled to per 100 g with off-serving-to-100", s28 and s28[0] == "per_100_g"
      and abs(s28[3]["energy_consumed"]["value"] - 100 * 100 / 28) < 1e-9
      and s28[3]["energy_consumed"]["transforms"] == [{"transform_id": "off-serving-to-100", "version": "v1"}]
      and s28[3]["energy_consumed"]["source_value"] == {"value": 100, "unit": "kcal", "serving": {"quantity": 28.0, "unit": "g"}}
      and s28[2]["pipeline_version"] == "off-product-projection-v6" and ":off-product-projection-v6:" in s28[2]["source_release_id"])
st = run(serving(per_quantity="12.5", sodium=(0.112, "mg")))
check("text serving '12.5' scaled", st and abs(st[3]["energy_consumed"]["value"] - 100 * 8) < 1e-9
      and st[3]["energy_consumed"]["source_value"]["serving"] == {"quantity": 12.5, "unit": "g"})
s100 = run(serving(per_quantity=100, sodium=(0.112, "mg")))
check("serving of exactly 100 still carries the transform", s100 and s100[3]["energy_consumed"]["value"] == 100
      and s100[3]["energy_consumed"]["transforms"] == [{"transform_id": "off-serving-to-100", "version": "v1"}])
sml = run(serving(per_unit="ml", per_quantity=250, sodium=(0.112, "mg")))
check("ml serving on a mass pack gives per 100 ml", sml and sml[0] == "per_100_ml_as_labelled"
      and sml[3]["energy_consumed"]["source_value"]["serving"] == {"quantity": 250.0, "unit": "ml"})
sg = run(serving(sodium=(0.112, "g")))
check("sodium in g gives the two-transform chain in order", sg
      and sg[3]["sodium"]["transforms"] == [{"transform_id": "mass-g-to-mg", "version": "v1"},
                                             {"transform_id": "off-serving-to-100", "version": "v1"}]
      and abs(sg[3]["sodium"]["value"] - 0.112 * 1000 * 100 / 28) < 1e-9
      and sg[3]["sodium"]["source_value"] == {"value": 0.112, "unit": "g", "serving": {"quantity": 28.0, "unit": "g"}})
two_serving = serving()
two_serving["nutrition"]["input_sets"].append(dict(two_serving["nutrition"]["input_sets"][0], per_quantity=30))
check("two serving panels refused", run(two_serving) is None)
beside = run(serving(extra=[{"source": "packaging", "per": "100g", "preparation": "as_sold",
                             "nutrients": {"energy-kcal": {"value": 400, "unit": "kcal"}}}]))
check("serving panel beside a per 100 panel is ignored (v5 result)", beside and beside[3]["energy_consumed"]["value"] == 400
      and "transforms" not in beside[3]["energy_consumed"] and beside[2]["pipeline_version"] == "off-product-projection-v5")
for bad in (0, -5, True, "1e2", "+5", "112\n", "1234567", "12.5000", None, "", [28]):
    check(f"per_quantity {bad!r} refused", run(serving(per_quantity=bad)) is None)
for bad in ("oz", None, "G", 1):
    check(f"per_unit {bad!r} refused", run(serving(per_unit=bad)) is None)
check("implausible scaled exact value refused", run(serving(per_quantity=1, energy=10)) is None)
check("implausible scaled bound end refused (a value the port leaves out)",
      run(serving(per_quantity=1, energy=5, modifier=("<", 101))) is None)
check("plausible bound left out, record admitted", (lambda x: x and "sugar" not in x[3])(
    run(serving(modifier=("<", 0.5), sodium=(0.112, "mg")))))
check("scale overflow refused", run(serving(per_quantity=1e-300, energy=1e300)) is None)
# Qodo (local review): large integers are handled as the app's doubles, never raised.
try:
    big_scaled = run(serving(per_quantity=1e-10, energy=10 ** 300))
    check("large integer that overflows only when scaled refuses the record", big_scaled is None)
except OverflowError:
    check("large integer that overflows only when scaled refuses the record", False)
try:
    big_sodium = run(modern(sodium=(10 ** 306, "g")))
    check("large integer sodium in g that overflows is left out, record admitted",
          big_sodium and "sodium" not in big_sodium[3] and big_sodium[3]["energy_consumed"]["value"] == 370)
    big_served = run(serving(sodium=(10 ** 306, "g")))
    check("serving record whose sodium overflows before scaling keeps the rest", big_served and "sodium" not in big_served[3])
except OverflowError:
    check("large integer sodium does not raise", False)
two100 = modern(per="100g", qty="1 l")
two100["nutrition"]["input_sets"].append(dict(two100["nutrition"]["input_sets"][0], per="100g"))
check("two per 100 panels contradicting the pack refused", run(two100) is None)
check("legacy record never scaled", run(legacy(nutrition_data_per="serving", serving_quantity=28)) is None)
v5 = run(modern())
iv5 = run(modern(sodium=(1, "g")))
check("v5 integer values keep their type (byte-identical output)", iv5
      and type(iv5[3]["energy_consumed"]["value"]) is int and iv5[3]["energy_consumed"]["value"] == 370
      and type(iv5[3]["sodium"]["value"]) is int and iv5[3]["sodium"]["value"] == 1000)
check("v5 admission keeps v5 and no serving", v5 and v5[2]["pipeline_version"] == "off-product-projection-v5"
      and "serving" not in v5[3]["sodium"]["source_value"])

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
