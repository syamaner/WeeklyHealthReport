"""Open Food Facts admission rules, ported from the app's OpenFoodFactsLookup.project
(Packages/FoodLedgerKit/Sources/FoodGenericSearch/OpenFoodFactsLookup.swift).

Keep this in step with that file (off-product-projection-v5 since #458). One deliberate difference: the app turns a "<" or ">"
value into a bound; the catalogue format has no bounded state in v1, so such a value is
left out (unknown). Everything else (fields, basis, legacy sodium, supplements, record
identity) follows the app.

The app has since moved to off-product-projection-v6 (#477), which only admits records v5 refuses
(a per-serving panel, or a lone per 100 panel that contradicts the pack). This port stays on v5
because the catalogue codec accepts v4 and v5 releases only; moving it needs a contract amendment.
"""
import hashlib
import json
import math
import re

# OpenFoodFactsLookup.project `fields`: the only eight nutrients the app admits.
FIELDS = {"energy_consumed": "energy-kcal", "protein": "proteins", "carbohydrates": "carbohydrates",
          "fat_total": "fat", "fat_saturated": "saturated-fat", "fiber": "fiber", "sugar": "sugars",
          "sodium": "sodium"}
CANON = {"energy_consumed": "kcal", "protein": "g", "carbohydrates": "g", "fat_total": "g",
         "fat_saturated": "g", "fiber": "g", "sugar": "g", "sodium": "mg"}
MODIFIERS = {"", "<", "<=", ">", ">="}
PROJECTION_VERSION = "off-product-projection-v5"  # #458: a panel may state its own basis


def _number(v):
    return v if isinstance(v, (int, float)) and not isinstance(v, bool) and math.isfinite(v) and v >= 0 else None


def _source_nutrients(product, pack_volume):
    """OpenFoodFactsLookup.sourceNutrients: one input set, never OFF's aggregate.

    pack_volume is the pack's basis (True volume, False mass) or None when the pack states neither;
    then exactly one eligible panel across both bases states its own basis (v5, #458).
    Returns (values, modern, volume)."""
    if "nutrition" in product:
        nutrition = product.get("nutrition")
        sets = nutrition.get("input_sets") if isinstance(nutrition, dict) else None
        if not isinstance(sets, list):
            return None
        pers = {"100ml" if pack_volume else "100g"} if pack_volume is not None else {"100g", "100ml"}
        if not all(isinstance(s, dict) for s in sets):
            return None  # the app's cast fails on a non-dictionary set
        eligible = [(i, s) for i, s in enumerate(sets) if s.get("source") == "packaging"
                    and isinstance(s.get("per"), str) and s["per"] in pers and s.get("preparation") == "as_sold"]
        if len(eligible) != 1 or not isinstance(eligible[0][1].get("nutrients"), dict):
            return None
        panel = eligible[0][1]
        volume = panel.get("per") == "100ml"
        if "per_quantity" in panel and _number(panel["per_quantity"]) != 100:
            return None
        if "per_unit" in panel and panel["per_unit"] != ("ml" if volume else "g"):
            return None
        out = {}
        for field, raw in panel["nutrients"].items():
            if isinstance(raw, dict):
                out[field + "_100g"] = raw.get("value")
                out[field + "_unit"] = raw.get("unit")
                out[field + "_modifier"] = raw.get("modifier")
        return out, True, volume
    if pack_volume is not False:  # legacy *_100g does not distinguish mass from volume: needs a mass pack
        return None
    if product.get("nutrition_data_per") != "100g" or not isinstance(product.get("nutriments"), dict):
        return None
    return product["nutriments"], False, False


def project(product, record_bytes, retrieved="unknown"):
    """Return (basis, record_id, release, values) or None, exactly as the app would admit them.

    values: {key: {"value", "unit", "transforms"?, "source_value"?}}
    """
    code = product.get("code")
    name = product.get("product_name") if isinstance(product.get("product_name"), str) else ""
    name = name.strip()
    if not isinstance(code, str) or not re.fullmatch(r"[0-9]{8}|[0-9]{12,14}", code) or not name:
        return None
    pack = product.get("quantity") if isinstance(product.get("quantity"), str) else ""
    mass = re.search(r"(?i)\d\s*(g|kg)\b", pack) is not None
    liquid = re.search(r"(?i)\d\s*(ml|cl|dl|l)\b", pack) is not None
    tags = product.get("categories_tags")
    tags = tags if isinstance(tags, list) and all(isinstance(t, str) for t in tags) else []
    if (mass and liquid) or "en:dietary-supplements" in tags:
        return None
    src = _source_nutrients(product, None if mass == liquid else liquid)
    if src is None:
        return None
    nutrients, modern, volume = src
    values = {}
    for key, field in FIELDS.items():
        if key == "sodium" and not modern:
            continue  # legacy sodium is normalised independently of the contributor unit
        v = _number(nutrients.get(field + "_100g"))
        unit = nutrients.get(field + "_unit")
        if v is None or not isinstance(unit, str):
            continue
        g_to_mg = key == "sodium" and unit == "g"
        if unit != CANON[key] and not g_to_mg:
            continue
        modifier = nutrients.get(field + "_modifier")
        if modifier is not None and not isinstance(modifier, str):
            continue
        if (modifier or "") not in MODIFIERS or (modifier or "") != "":
            continue  # bound in the app; not representable in catalogue v1, so unknown
        entry = {"value": v * 1000 if g_to_mg else v, "unit": CANON[key]}
        if g_to_mg:
            entry["transforms"] = [{"transform_id": "mass-g-to-mg", "version": "v1"}]
            entry["source_value"] = {"value": v, "unit": "g"}
        values[key] = entry
    if not values:
        return None
    digest = hashlib.sha256(record_bytes).hexdigest()
    gtin = "0" * (14 - len(code)) + code
    # A reduced form defined by the catalogue contract (not the app's own OFF release form, so the
    # two can never collide): every field is a pure function of the ID.
    release = {"source_release_id": f"pfc-off:sha256:{digest}:projection:{PROJECTION_VERSION}:retrieved:{retrieved}",
               "source_id": "open-food-facts", "artifact_sha256": digest, "manifest_sha256": digest,
               "released_at": f"{retrieved}T00:00:00Z",
               "schema_version": "off-v3.6-product-record", "pipeline_version": PROJECTION_VERSION,
               "licence": "ODbL 1.0 https://opendatacommons.org/licenses/odbl/1-0/; contents: https://opendatacommons.org/licenses/dbcl/1-0/",
               "attribution": f"Open Food Facts · https://world.openfoodfacts.org/product/{code}"}
    return ("per_100_ml_as_labelled" if volume else "per_100_g"), f"off:gtin:{gtin}", release, values


def load(path):
    """Read a cached v3.6 product record written by fetch_off_products.py.

    Mirrors the app: status must be "success" or "success_with_warnings", and the returned
    code, padded to GTIN-14, must equal the requested one. Returns (product, record_bytes,
    retrieved) or (None, None, None).
    """
    doc = json.loads(path.read_bytes())
    product = doc.get("product")
    status, warnings = doc.get("status"), doc.get("warnings")
    normalisation_only = status == "success_with_warnings" and isinstance(warnings, list) and bool(warnings) \
        and all(isinstance(w, dict) and (w.get("message") or {}).get("id") == "different_normalized_product_code"
                and (w.get("impact") or {}).get("id") == "none" for w in warnings)
    if doc.get("api") != "v3.6" or not (status == "success" or normalisation_only) or not isinstance(product, dict):
        return None, None, None  # other warnings, or warnings not recorded: refused, as the app does
    code, requested = product.get("code"), str(doc.get("requested") or "")
    if not isinstance(code, str) or ("0" * (14 - len(code)) + code) != ("0" * (14 - len(requested)) + requested):
        return None, None, None
    record = json.dumps(product, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode()
    return product, record, doc.get("retrieved")
