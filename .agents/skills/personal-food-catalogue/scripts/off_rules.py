"""Open Food Facts admission rules, ported from the app's OpenFoodFactsLookup.project
(Packages/FoodLedgerKit/Sources/FoodGenericSearch/OpenFoodFactsLookup.swift).

Keep this in step with that file (off-product-projection-v6 since #477, carried into the catalogue
by docs/personal-food-catalogue-import-v2.md). A record v5 admits keeps off-product-projection-v5
and identical values; v6 only adds records v5 refuses: a lone per 100 panel that contradicts the
pack ("the panel wins"), or a single per-serving panel scaled to per 100.

One deliberate difference: the app turns a "<" or ">" value into a bound; the catalogue format has
no bounded state, so such a value is left out (unknown). The plausibility check still covers it,
so the port refuses exactly the records the app declines. Everything else (fields, basis, legacy
sodium, supplements, record identity) follows the app.
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
PROJECTION_V5 = "off-product-projection-v5"  # #458: a panel may state its own basis
PROJECTION_V6 = "off-product-projection-v6"  # #477: the panel wins; per-serving panels scaled
SERVING_TRANSFORM = {"transform_id": "off-serving-to-100", "version": "v1"}
# OpenFoodFactsServingRule.plausibleMaximum: the most any food can hold per 100, by canonical unit.
PLAUSIBLE_MAXIMUM = {"g": 100.0, "mg": 100_000.0, "kcal": 900.0}
_SERVING_TEXT = re.compile(r"[0-9]{1,6}(\.[0-9]{1,3})?", re.ASCII)


def _number(v):
    try:
        return v if isinstance(v, (int, float)) and not isinstance(v, bool) and math.isfinite(v) and v >= 0 else None
    except OverflowError:
        return None  # an integer too large for a double: the app's NSNumber is not finite either


def _serving_quantity(raw):
    """OpenFoodFactsLookup.servingQuantity, then the caller's finite and above-zero checks."""
    if isinstance(raw, bool):
        return None
    if isinstance(raw, (int, float)):
        try:
            q = float(raw)
        except OverflowError:
            return None
    elif isinstance(raw, str) and _SERVING_TEXT.fullmatch(raw):
        q = float(raw)  # fullmatch, so "112\n" is refused (Swift: the regex allows it, Double("112\n") does not)
    else:
        return None
    return q if math.isfinite(q) and q > 0 else None


def _panel_values(panel):
    out = {}
    for field, raw in panel["nutrients"].items():
        if isinstance(raw, dict):
            out[field + "_100g"] = raw.get("value")
            out[field + "_unit"] = raw.get("unit")
            out[field + "_modifier"] = raw.get("modifier")
    return out


def _serving_nutrients(sets):
    """OpenFoodFactsLookup.servingNutrients: exactly one packaging, as_sold, per serving panel."""
    panels = [s for s in sets if s.get("source") == "packaging" and s.get("per") == "serving"
              and s.get("preparation") == "as_sold"]
    if len(panels) != 1 or not isinstance(panels[0].get("nutrients"), dict):
        return None
    serving = _serving_quantity(panels[0].get("per_quantity"))
    unit = panels[0].get("per_unit")
    if serving is None or unit not in ("g", "ml"):
        return None
    return _panel_values(panels[0]), True, unit == "ml", serving, False


def _source_nutrients(product, pack_volume):
    """OpenFoodFactsLookup.sourceNutrients: one input set, never OFF's aggregate.

    pack_volume is the pack's basis (True volume, False mass) or None when the pack states neither;
    then exactly one eligible panel across both bases states its own basis (v5, #458). With no
    eligible panel, v6: a lone per 100 panel wins over the pack, else one per-serving panel.
    Returns (values, modern, volume, serving, panel_overrides_pack)."""
    if "nutrition" in product:
        nutrition = product.get("nutrition")
        sets = nutrition.get("input_sets") if isinstance(nutrition, dict) else None
        if not isinstance(sets, list):
            return None
        pers = {"100ml" if pack_volume else "100g"} if pack_volume is not None else {"100g", "100ml"}
        if not all(isinstance(s, dict) for s in sets):
            return None  # the app's cast fails on a non-dictionary set
        eligible = [s for s in sets if s.get("source") == "packaging"
                    and isinstance(s.get("per"), str) and s["per"] in pers and s.get("preparation") == "as_sold"]
        overrides = False
        if not eligible:
            per100 = [s for s in sets if s.get("source") == "packaging" and s.get("preparation") == "as_sold"
                      and isinstance(s.get("per"), str) and s["per"] in ("100g", "100ml")]
            if not per100:
                return _serving_nutrients(sets)
            if len(per100) != 1:
                return None
            eligible, overrides = per100, True
        if len(eligible) != 1 or not isinstance(eligible[0].get("nutrients"), dict):
            return None
        panel = eligible[0]
        volume = panel.get("per") == "100ml"
        if "per_quantity" in panel and _number(panel["per_quantity"]) != 100:
            return None
        if "per_unit" in panel and panel["per_unit"] != ("ml" if volume else "g"):
            return None
        return _panel_values(panel), True, volume, None, overrides
    if pack_volume is not False:  # legacy *_100g does not distinguish mass from volume: needs a mass pack
        return None
    if product.get("nutrition_data_per") != "100g" or not isinstance(product.get("nutriments"), dict):
        return None
    return product["nutriments"], False, False, None, False


def project(product, record_bytes, retrieved="unknown"):
    """Return (basis, record_id, release, values) or None, exactly as the app would admit them.

    values: {key: {"value", "unit", "transforms"?, "source_value"?}}; a scaled value's source_value
    also carries "serving": {"quantity", "unit"} (catalogue v2).
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
    nutrients, modern, volume, serving, overrides = src
    scale = 100 / serving if serving is not None else 1
    serving_unit = "ml" if volume else "g"
    values, implausible, scaled_overflow = {}, False, False
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
        if (modifier or "") not in MODIFIERS:
            continue
        unscaled = v * 1000 if g_to_mg else v  # the stored type is kept, so v5 output keeps its bytes
        amount = unscaled * scale if serving is not None else unscaled
        if not math.isfinite(amount):
            if serving is not None and math.isfinite(unscaled):
                scaled_overflow = True  # only the scale overflowed: a wrong serving size
            continue
        if serving is not None and amount > PLAUSIBLE_MAXIMUM[CANON[key]]:
            implausible = True  # checked on bounds too, which the port then leaves out
        if modifier:
            continue  # bound in the app; not representable in the catalogue, so unknown
        entry = {"value": amount, "unit": CANON[key]}
        transforms = [{"transform_id": "mass-g-to-mg", "version": "v1"}] if g_to_mg else []
        if serving is not None:
            transforms.append(dict(SERVING_TRANSFORM))
        if transforms:
            entry["transforms"] = transforms
            entry["source_value"] = {"value": v, "unit": unit}
            if serving is not None:
                entry["source_value"]["serving"] = {"quantity": serving, "unit": serving_unit}
        values[key] = entry
    if serving is not None and (implausible or scaled_overflow):
        return None  # the app declines the whole record (v6 plausibility)
    if not values:
        return None
    projection = PROJECTION_V6 if serving is not None or overrides else PROJECTION_V5
    digest = hashlib.sha256(record_bytes).hexdigest()
    gtin = "0" * (14 - len(code)) + code
    # A reduced form defined by the catalogue contract (not the app's own OFF release form, so the
    # two can never collide): every field is a pure function of the ID.
    release = {"source_release_id": f"pfc-off:sha256:{digest}:projection:{projection}:retrieved:{retrieved}",
               "source_id": "open-food-facts", "artifact_sha256": digest, "manifest_sha256": digest,
               "released_at": f"{retrieved}T00:00:00Z",
               "schema_version": "off-v3.6-product-record", "pipeline_version": projection,
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
