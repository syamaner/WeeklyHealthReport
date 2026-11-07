#!/usr/bin/env python3
"""Assemble the private personal food catalogue.

Inputs: work/families.json, work/mapping-*.json (concept + CoFID proposals),
work/off-cache/*.json (Open Food Facts candidates), the bundled CoFID JSON.

Per-nutrient precedence (owner ruling 7 Nov 2026, "enhance as best as possible"):
  1. Product label (Open Food Facts candidate that passes the match bar).
  2. Generic CoFID record, only when the mapping is same_food_same_state or close.
  Every value carries its source, so a mixed record stays traceable. Fresh whole
  foods use CoFID first, because a retailer label for loose produce is rare and
  CoFID is the analysed edible portion. Unknown stays absent, never zero.

Usage: python3 -I assemble.py <work_dir> <cofid_json> <out_dir> <usda_json>
"""
import hashlib
import json
import re
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from workspace_guard import check_output  # noqa: E402

CANON = {  # Open Food Facts key -> (canonical key, canonical unit, factor from OFF grams)
    "energy-kcal": ("energy_consumed", "kcal", 1), "fat": ("fat_total", "g", 1),
    "saturated-fat": ("fat_saturated", "g", 1), "monounsaturated-fat": ("fat_monounsaturated", "g", 1),
    "polyunsaturated-fat": ("fat_polyunsaturated", "g", 1), "carbohydrates": ("carbohydrates", "g", 1),
    "sugars": ("sugar", "g", 1), "fiber": ("fiber", "g", 1), "proteins": ("protein", "g", 1),
    "sodium": ("sodium", "mg", 1e3), "cholesterol": ("cholesterol", "mg", 1e3),
    "vitamin-a": ("vitamin_a", "mcg", 1e6), "vitamin-d": ("vitamin_d", "mcg", 1e6),
    "vitamin-e": ("vitamin_e", "mg", 1e3), "vitamin-k": ("vitamin_k", "mcg", 1e6),
    "vitamin-c": ("vitamin_c", "mg", 1e3), "vitamin-b1": ("thiamin_b1", "mg", 1e3),
    "vitamin-b2": ("riboflavin_b2", "mg", 1e3), "vitamin-pp": ("niacin_b3", "mg", 1e3),
    "vitamin-b6": ("vitamin_b6", "mg", 1e3), "vitamin-b9": ("folate_b9", "mcg", 1e6),
    "folates": ("folate_b9", "mcg", 1e6), "vitamin-b12": ("vitamin_b12", "mcg", 1e6),
    "biotin": ("biotin_b7", "mcg", 1e6), "pantothenic-acid": ("pantothenic_acid_b5", "mg", 1e3),
    "calcium": ("calcium", "mg", 1e3), "iron": ("iron", "mg", 1e3), "magnesium": ("magnesium", "mg", 1e3),
    "zinc": ("zinc", "mg", 1e3), "potassium": ("potassium", "mg", 1e3), "phosphorus": ("phosphorus", "mg", 1e3),
    "iodine": ("iodine", "mcg", 1e6), "selenium": ("selenium", "mcg", 1e6), "copper": ("copper", "mg", 1e3),
    "manganese": ("manganese", "mg", 1e3), "chloride": ("chloride", "mg", 1e3),
    "chromium": ("chromium", "mcg", 1e6), "molybdenum": ("molybdenum", "mcg", 1e6),
    "caffeine": ("caffeine", "mg", 1e3),
}
LABEL_CORE = {"energy_consumed", "fat_total", "fat_saturated", "carbohydrates", "sugar", "fiber", "protein", "sodium"}
STOP = set("the and with of in a & organic british collection m&s ocado per pack x rainforest alliance "
           "perfectly ripe family large small medium free range".split())
BRAND_ALIASES = {"m&s": {"m&s", "marks & spencer", "marks and spencer", "marks & spencer food"}}


def toks(s):
    return {t for t in re.findall(r"[a-z0-9%]+", s.casefold().replace("&", " ")) if t not in STOP and len(t) > 1}


def norm_brand(b):
    b = re.sub(r"[^a-z0-9& ]", " ", b.casefold().replace(" and ", " & "))
    b = re.sub(r"\s+", " ", b).strip()
    if "m&s" in b or "m & s" in b or ("marks" in b and "spencer" in b):
        return "m&s"
    return b


def score_off(title, brand_guess, hit):
    """Forward/reverse overlap of product-name tokens; brand checked separately.

    Brand words are removed from both sides so a brand field (e.g. "Cucumber")
    can never stand in for the product name. brand_ok means the title starts
    with one of the hit's brands, after normalising punctuation and M&S names.
    """
    name = f"{hit.get('product_name') or ''}"
    brands = hit.get("brands") or []
    brands = brands if isinstance(brands, list) else [brands]
    nb = {norm_brand(b) for b in brands if b and b.strip()}
    nt = norm_brand(title) if norm_brand(title) == "m&s" and title.casefold().startswith(("m&s", "marks")) \
        else re.sub(r"\s+", " ", re.sub(r"[^a-z0-9& ]", " ", title.casefold())).strip()
    brand_ok = any(b and (nt == b or nt.startswith(b + " ")) for b in nb) or \
        ("m&s" in nb and title.casefold().startswith(("m&s", "marks")))
    if not nb and not brand_ok:
        # No brand field: accept the title's leading word appearing in the product name as the
        # brand, but only when nearly all of the name's words are in the title (Loch Fyne
        # salmon must not pass for Loch Fyne kippers).
        lead = title.split()[0].casefold() if title.split() else ""
        name_words = re.findall(r"[a-z0-9']+", name.casefold())
        rest = toks(name) - toks(lead)
        if len(lead) > 2 and lead in name_words and rest and name_coverage(title, hit) >= 0.75:
            brand_ok = True
    brand_toks = {t for b in nb for t in toks(b)} | {"m", "s", "spencer", "marks", "food"}
    tt = toks(re.sub(r"\d+(\.\d+)?\s*(kg|g|ml|cl|l)\b", "", title, flags=re.I)) - brand_toks
    ht = toks(name) - brand_toks
    if not tt or not ht:
        return 0.0, brand_ok
    if (ht ^ tt) & VARIANT_WORDS:  # either side names a variant the other lacks (flavour, frozen, light ...)
        return 0.0, brand_ok
    common = len(tt & ht)
    score = 0.7 * common / len(tt) + 0.3 * common / len(ht)
    return round(score, 3), brand_ok


def name_coverage(title, hit):
    """Share of the candidate's own name words that also appear in the title."""
    brands = hit.get("brands") or []
    brands = brands if isinstance(brands, list) else [brands]
    bt = {t for b in brands if b for t in toks(norm_brand(b))} | {"m", "s", "spencer", "marks", "food"}
    ht = toks(hit.get("product_name") or "") - bt
    tt = toks(title) - bt
    return len(ht & tt) / len(ht) if ht else 0.0


VARIANT_WORDS = set("""roast frozen vanilla chocolate strawberry raspberry blueberry cherry peach mango lemon lime
orange coconut honey toffee caramel salted unsalted smoked light lighter low reduced skimmed semi skimmed
sweetened unsweetened flavoured spicy chilli garlic herb cheese cheddar bacon oat soya almond lactose
decaf decaffeinated diet zero sugar free wholemeal white brown dried roasted cooked fried breaded
marinated crispy jalapeno pesto tomato onion pepper sea salt vinegar bbq barbecue sweet chilli
beef chicken pork lamb duck prawn seafood sesame miso teriyaki curry katsu mushroom vegetable
water brine oil olive sunflower spring""".split())


PRODUCT_DIR = None   # set by main(): <work>/off-products-v3
OFF_RELEASES = {}    # source_release_id -> release fields, collected for the export


def off_label(code):
    """(basis, values) from the full product record under the app's rules (off_rules.py), or (None, {})."""
    import off_rules
    if PRODUCT_DIR is None:
        return None, {}
    p = PRODUCT_DIR / f"{code}.json"
    if not p.exists():
        return None, {}  # no product record: search results cannot show units or "<" modifiers
    product, record_bytes, retrieved = off_rules.load(p)
    if product is None:
        return None, {}
    got = off_rules.project(product, record_bytes, retrieved or "unknown")
    if got is None:
        return None, {}
    basis, record_id, release, values = got
    OFF_RELEASES[release["source_release_id"]] = release
    return basis, {k: {**v, "source": f"label:off:{record_id}", "release": release["source_release_id"]}
                   for k, v in values.items()}


def off_nutrients(hit, code):
    """Back-compatible wrapper: values only."""
    return off_label(code)[1]


def cofid_nutrients(rec):
    out = {}
    for k, v in rec["nutrients"].items():
        if v.get("state") == "numeric":
            out[k] = {"value": float(v["value"]), "unit": v["canonical_unit"],
                      "source": f"generic:cofid:{rec['record_id']}"}
        elif v.get("state") == "present_unquantified":  # CoFID "Tr" / "N": present, amount unknown
            out[k] = {"value": None, "state": "present_unquantified", "unit": v["canonical_unit"],
                      "source": f"generic:cofid:{rec['record_id']}"}
    return out


COOKED_WORDS = re.compile(r"\b(boiled|grilled|roasted|fried|stewed|braised|baked|microwaved|steamed|cooked|"
                          r"poached|toasted)\b", re.I)


def usda_nutrients(rec, prefix="usda"):
    """Same rule as the app's USDAGenericFoodSearch: a unit other than the canonical one
    is unknown (missing conversion), never converted (e.g. water in g is not mL)."""
    from export_v1 import CANON_UNITS
    return {k: {"value": float(v["amount"]), "unit": v["unit"], "source": f"generic:{prefix}:{rec['id']}"}
            for k, v in rec["nutrients"].items()
            if isinstance(v.get("amount"), (int, float)) and CANON_UNITS.get(k) == v["unit"]}


def fat_level_conflict(title, nutrients):
    """Title states a fat percentage the record's fat value does not carry (same rule as validate_mappings)."""
    t = re.search(r"(\d+(?:\.\d+)?)\s*%\s*fat", title, re.I)
    if not t:
        return None
    rf = (nutrients.get("fat_total") or {}).get("value")
    stated = float(t[1])
    less = re.search(r"less than", title, re.I)
    ok = rf is not None and (rf <= stated + 0.5 if less else abs(rf - stated) <= 2)
    return None if ok else f"title {t[0]}, record fat {rf} g/100 g"


def usda_state_ok(m, rec, title):
    """Same mechanical checks as validate_mappings.py, applied to USDA proposals."""
    name = rec["name"]
    st = m.get("state")
    if st in ("raw", "frozen") and COOKED_WORDS.search(name) and not re.search(r"\braw\b", name, re.I):
        return False, f"product {st}, record cooked"
    if st == "cooked" and re.search(r"\braw\b", name, re.I):
        return False, "product cooked, record raw"
    if bool(re.search(r"\bsmoked\b", title, re.I)) != bool(re.search(r"\bsmoked\b", name, re.I)) and \
            re.search(r"\b(fish|meat|bacon|salmon|haddock|mackerel|ham|sausage)\b", title + " " + name, re.I):
        return False, "smoked state differs"
    if re.search(r"\b(enriched|fortified)\b", name, re.I) and not re.search(r"\b(enriched|fortified)\b", title, re.I):
        return False, "US enriched/fortified record; UK product is not"
    return True, None


def main(work: Path, cofid_path: Path, out: Path, usda_path: Path):
    global PRODUCT_DIR
    PRODUCT_DIR = work / "off-products-v3"
    cofid = json.load(open(cofid_path))
    usda = json.load(open(usda_path))
    by_row = {}
    for r in cofid["records"]:
        mm = re.search(r":row:(\d+):", r["record_id"])
        if mm:
            by_row[mm[1]] = r
    mapping = {m["n"]: m for m in json.load(open(work / "mapping-validated.json"))}
    usda_map = {}
    for p in sorted(work.glob("usda-mapping-[0-9].json")):
        for um in json.load(open(p)):
            usda_map[um["n"]] = um
    fams = json.load(open(work / "families.json"))
    items = []
    from collections import Counter
    tier_use, stats = Counter(), Counter()
    for f in fams:
        m = mapping.get(f["n"]) or {}
        brand_guess = f["title"].split()[0].casefold()
        best = best_other = None
        hit_files = [work / "off-cache" / f"{f['n']}.json", *sorted((work / "off-cache2").glob(f"{f['n']}-*.json"))]
        all_hits = [h for hf in hit_files if hf.exists() for h in json.load(open(hf))["hits"]]
        if all_hits:
            for hit in all_hits:
                if not isinstance((hit.get("nutriments") or {}).get("energy-kcal_100g"), (int, float)):
                    continue
                sc, b = score_off(f["title"], brand_guess, hit)
                uk = "en:united-kingdom" in (hit.get("countries_tags") or [])
                rank = sc + (0.15 if b else 0) + (0.05 if uk else 0)
                if best is None or rank > best[0]:
                    best = (rank, sc, b, uk, hit)
                if not b and (best_other is None or sc + (0.05 if uk else 0) > best_other[0]):
                    best_other = (sc + (0.05 if uk else 0), sc, b, uk, hit)
        pick = lambda t, status: {"status": status, **{k: t[4].get(k) for k in ("code", "product_name", "brands", "quantity")},
                                  "score": t[1], "brand_match": t[2], "uk": t[3]}
        label = other = None
        if best and best[1] >= 0.6 and best[2]:
            label = pick(best, "probable")
        elif best and best[1] >= 0.45:
            label = pick(best, "possible_not_used")
        single = m.get("product_type") in ("packaged_single_ingredient", "fresh_whole")
        if label is None or label["status"] != "probable":
            if single and best_other and best_other[1] >= 0.8 and name_coverage(f["title"], best_other[4]) >= 0.75:
                other = pick(best_other, "other_brand_used")
        # CoFID tier
        cofid_rec, cmatch = None, m.get("cofid_match", "none")
        if m.get("cofid_row") in by_row:
            cofid_rec = by_row[m["cofid_row"]]
        # USDA tier (gap families only), with the same mechanical state checks
        usda_rec, umatch, unote = None, None, None
        um = usda_map.get(f["n"])
        if um and isinstance(um.get("usda_index"), int) and 0 <= um["usda_index"] < len(usda["records"]):
            usda_rec = usda["records"][um["usda_index"]]
            umatch, unote = um.get("match"), um.get("note")
            import validate_mappings as VM
            ok, why = usda_state_ok({**m, "state": um.get("state") or m.get("state")}, usda_rec, f["title"])
            if ok and um.get("usda_name") != usda_rec["name"] and not VM.shares_food_word(m, usda_rec["name"]):
                ok, why = False, "record name differs from the proposed name and shares no food word"
            if ok:
                why = fat_level_conflict(f["title"], usda_nutrients(usda_rec))
                ok = why is None
            if not ok and umatch in ("same_food_same_state", "close"):
                umatch, unote = "concept_only", f"downgraded: {why}"
        tiers = {
            "label": {},
            "cofid": cofid_nutrients(cofid_rec) if cofid_rec and cmatch in ("same_food_same_state", "close") else {},
            "usda": usda_nutrients(usda_rec) if usda_rec and umatch in ("same_food_same_state", "close") else {},
            "other_brand": {},
        }
        label_basis = None
        if label and label["status"] == "probable":
            label_basis, tiers["label"] = off_label(label["code"])
        if other and not tiers["label"]:
            ob_basis, ob = off_label(other["code"])
            if ob_basis == "per_100_g":  # another brand's values never set the basis; only same-basis values fill
                tiers["other_brand"] = {k: {**v, "source": v["source"].replace("label:off:", "label-other-brand:off:")}
                                        for k, v in ob.items()}
        fresh = m.get("product_type") == "fresh_whole"
        order = ["cofid", "usda", "label", "other_brand"] if fresh else ["label", "cofid", "usda", "other_brand"]
        nutrients = {}
        liquid_label = label_basis == "per_100_ml_as_labelled"  # evidence, never the category
        if liquid_label:  # one basis per entry: per-100-g generic records never fill a per-100-ml label
            tiers["cofid"], tiers["usda"] = {}, {}
        for t in order:  # earlier tier wins per nutrient; later tiers fill only what is missing
            for k, v in tiers[t].items():
                held = nutrients.get(k)
                # a present-but-unquantified value is unknown in the app, so a numeric lower tier replaces it
                if held is None or (held.get("value") is None and v.get("value") is not None):
                    nutrients[k] = v
                    tier_use[t] += 1
        used = sorted({v["source"].split(":")[0] + ":" + v["source"].split(":")[1] for v in nutrients.values()})
        stats["none" if not used else "+".join(used)] += 1
        basis = "per_100_ml_as_labelled" if liquid_label else "per_100_g"
        items.append({
            "id": "pfc:" + hashlib.sha256(f["family_id"].encode()).hexdigest()[:12], "n": f["n"],
            "origin": "receipts",
            "title": f["title"], "titles": f["titles"], "kind": f["kind"],
            "concept": m.get("concept"), "variety": m.get("variety"),
            "aliases": m.get("aliases", []), "fallback_chain": m.get("fallback_chain", []),
            "category": m.get("category"), "product_type": m.get("product_type"),
            "state": m.get("state"), "packs": f["packs"], "retailers": f["retailers"],
            "purchase_lines": f["purchase_lines"], "basis": basis,
            "label_candidate": label, "other_brand_label": other,
            "generic_match": {"cofid_record_id": cofid_rec["record_id"], "name": cofid_rec["name"], "match": cmatch,
                              "note": m.get("note"), "validation": m.get("validation")}
                             if cofid_rec else {"match": cmatch, "note": m.get("note")},
            "usda_match": {"usda_record_id": usda_rec["id"], "name": usda_rec["name"], "match": umatch, "note": unote}
                          if usda_rec else None,
            "nutrient_sources": used, "nutrients": nutrients,
            "label_tiers": {"off": tiers["label"]},  # export picks label values from here, not from the winner
            "review": "unreviewed",
        })
    catalogue = {
        "schema": "personal-food-catalogue-v0-draft", "generated": time.strftime("%Y-%m-%d"),
        "private": True,
        "sources": {"off": {"title": "Open Food Facts", "licence": "ODbL 1.0 (database), DbCL (contents)",
                            "url": "https://world.openfoodfacts.org"},
                    "cofid": {"title": cofid["source"]["title"], "licence": cofid["source"]["licence"],
                              "release_id": cofid["source"]["release_id"]},
                    "usda": {"title": "USDA FoodData Central (Foundation, SR Legacy)", "licence": "public domain (CC0)",
                             "release": usda["sources"]}},
        "precedence": ("per nutrient, first tier wins: packaged = own label > CoFID > USDA > other-brand label "
                       "(single-ingredient only); fresh_whole = CoFID > USDA > own label > other-brand label. "
                       "Generic tiers only when the mapping is same_food_same_state or close after mechanical checks."),
        "items": items,
    }
    out.mkdir(parents=True, exist_ok=True)
    catalogue["off_releases"] = OFF_RELEASES
    (out / "personal-food-catalogue.json").write_text(json.dumps(catalogue, indent=1, ensure_ascii=False))
    print("families by sources used:", dict(stats.most_common()))
    print("nutrient values per tier:", dict(tier_use))


if __name__ == "__main__":
    main(check_output(sys.argv[1]), Path(sys.argv[2]), check_output(sys.argv[3]), Path(sys.argv[4]))
