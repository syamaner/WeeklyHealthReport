#!/usr/bin/env python3
"""Write the importable file defined by docs/personal-food-catalogue-import-v1.md (revision 5) and
its v2 delta, docs/personal-food-catalogue-import-v2.md (Open Food Facts projection v6).

Input: out/personal-food-catalogue.json (working form). Output:
out/personal-food-catalogue-v2.json, always schema personal-food-catalogue-v2 (owner decision,
13 November 2026). check_bytes also checks v1 files under the v1 rules, unchanged. The module keeps
its name; it is not a contract. The file carries no self-hash; the app derives the
release ID from the exact bytes (pfc:sha256:<hex>), and this script prints the same ID.
The export runs the importer's rejection rules (check_bytes) on its own output and refuses
to write a file the app would reject.

Usage: python3 -I export_v1.py <workspace> <repo_root>
"""
import datetime
import hashlib
import json
import math
import re
import sys
import time
import unicodedata
from collections import Counter
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from workspace_guard import check as guard_workspace  # noqa: E402

LIMIT_BYTES, LIMIT_ITEMS = 26_214_400, 20000  # 25 MiB exactly
# Deepest array or object nesting accepted. Explicit, so the Swift importer gives the same verdict;
# Python's own recursion limit depends on the call stack (real files nest about five deep).
MAX_DEPTH = 64
# Most JSON values (object keys not counted) a file may hold, as the Swift reader: it bounds the
# parsed tree's memory on the phone, and a real file holds far fewer values than its bytes allow.
MAX_VALUES = 4_000_000
CANON_UNITS = {
    "energy_consumed": "kcal", "protein": "g", "fat_total": "g", "fat_saturated": "g",
    "fat_monounsaturated": "g", "fat_polyunsaturated": "g", "fiber": "g", "sugar": "g",
    "carbohydrates": "g", "cholesterol": "mg", "vitamin_a": "mcg", "thiamin_b1": "mg",
    "riboflavin_b2": "mg", "niacin_b3": "mg", "pantothenic_acid_b5": "mg", "vitamin_b6": "mg",
    "biotin_b7": "mcg", "folate_b9": "mcg", "vitamin_b12": "mcg", "vitamin_c": "mg", "vitamin_d": "mcg",
    "vitamin_e": "mg", "vitamin_k": "mcg", "calcium": "mg", "chloride": "mg", "iron": "mg",
    "magnesium": "mg", "phosphorus": "mg", "potassium": "mg", "sodium": "mg", "zinc": "mg",
    "chromium": "mcg", "copper": "mg", "iodine": "mcg", "manganese": "mg", "molybdenum": "mcg",
    "selenium": "mcg", "water": "mL", "caffeine": "mg",
}
CATEGORIES = {"fruit", "vegetable", "herb_spice", "dairy", "egg", "meat", "fish", "grain_cereal", "bakery",
              "legume", "nut_seed", "oil_fat", "condiment_sauce", "snack", "confectionery", "beverage",
              "alcohol", "ready_meal", "other"}
PRODUCT_TYPES = {"fresh_whole", "packaged_single_ingredient", "packaged_composite", "unknown"}
STATES = {"raw", "cooked", "canned", "frozen", "dried", "smoked", "unknown"}
BASES = {"per_100_g", "per_100_ml_as_labelled"}
KIND_MATCH = {"manual_declaration": "owner", "exact_product_dataset": "probable"}
# The app's own transform pairs; each applies to one nutrient and is checked arithmetically.
TRANSFORMS = {  # (id, version): (nutrient, source unit, source_kind, function from source value to value)
    # the two pasted-label pairs are calculated (PastedLabelDomain.calculatedTransforms); owner values only
    ("salt_to_sodium_v1", "pasted-label-conversions-v1"): ("sodium", "g", "manual_declaration", lambda v: v / 2.5 * 1000),
    ("kj_to_kcal_v1", "pasted-label-conversions-v1"): ("energy_consumed", "kJ", "manual_declaration", lambda v: v / 4.184),
    # a unit conversion, not a calculation (calculated: false); Open Food Facts values only
    ("mass-g-to-mg", "v1"): ("sodium", "g", "exact_product_dataset", lambda v: v * 1000),
}
TOLERANCE = 0.005  # relative, for transform arithmetic
SCHEMA_V1, SCHEMA_V2 = "personal-food-catalogue-v1", "personal-food-catalogue-v2"
SCHEMA = SCHEMA_V2  # what build() writes
# Catalogue v2 (import v2 section 3): the app's per-serving scaling, off-product-projection-v6.
MASS_G_TO_MG = ("mass-g-to-mg", "v1")
SERVING_TO_100 = ("off-serving-to-100", "v1")  # not a calculation (calculated: false)
SERVING_NUTRIENTS = {"energy_consumed", "protein", "carbohydrates", "fat_total", "fat_saturated", "fiber", "sugar",
                     "sodium"}  # the eight Open Food Facts fields
PLAUSIBLE_MAXIMUM = {"g": 100.0, "mg": 100_000.0, "kcal": 900.0}  # per 100, as the app's v6 declines
SERVING_UNITS = {"per_100_g": "g", "per_100_ml_as_labelled": "ml"}
OFF_V6 = "off-product-projection-v6"
V2_RULE_CODES = ("serving-implausible", "serving-mismatch")  # emitted for v2 files only
GENERIC_SOURCES = {"cofid", "usda", "tfda"}
GENERIC_MATCHES = {"same_food_same_state", "close"}
SOURCE_IDS = {"open-food-facts", "owner"}
SOURCE_PINS = {  # every release field except the hashes and date is fixed per source_id (contract section 4)
    "open-food-facts": {"schema_version": "off-v3.6-product-record", "pipeline_version": "off-product-projection-v4",  # the first pinned form; OFF_PROJECTIONS governs the check
                        "licence": "ODbL 1.0 https://opendatacommons.org/licenses/odbl/1-0/; contents: https://opendatacommons.org/licenses/dbcl/1-0/",
                        "attribution": "Open Food Facts"},
    "owner": {"schema_version": "pfc-intake-label-v1", "pipeline_version": "personal-food-catalogue-skill-v1",
              "licence": "private", "attribution": "Label values typed or confirmed by the owner"},
}
# #458: v5 entries are built under the panel-stated basis rule; v4 entries built before it stay valid.
OFF_PROJECTIONS = {"off-product-projection-v4", "off-product-projection-v5"}
OFF_PROJECTIONS_V2 = OFF_PROJECTIONS | {OFF_V6}  # catalogue v2 only
RELEASE_PATTERNS = {
    "open-food-facts": re.compile(r"pfc-off:sha256:[0-9a-f]{64}:projection:off-product-projection-v[45]:retrieved:[0-9]{4}-[0-9]{2}-[0-9]{2}"),
    "owner": re.compile(r"owner:sha256:[0-9a-f]{64}"),
}
RELEASE_PATTERNS_V2 = {**RELEASE_PATTERNS, "open-food-facts": re.compile(
    r"pfc-off:sha256:[0-9a-f]{64}:projection:off-product-projection-v[456]:retrieved:[0-9]{4}-[0-9]{2}-[0-9]{2}")}
SWIFT_PINS = {
    "cofid": ("cofid-2021-generic-search-v1.json", "CoFIDGenericFoodSearch.swift", "corpusCanonicalSHA256"),
    "usda": ("usda-generic-v1.json", "USDAGenericFoodSearch.swift", "corpusSHA256"),
    "tfda": ("tfda-generic-v1.json", "TFDAGenericFoodSearch.swift", "corpusSHA256"),
}
TOP_KEYS = {"schema", "generated", "sources", "generic_corpora", "items"}
ITEM_KEYS = {"id", "brand", "title", "titles", "aliases", "concept", "variety", "fallback_chain", "category",
             "product_type", "state", "basis", "label_nutrients", "generic_reference"}
VALUE_KEYS = {"value", "unit", "source_kind", "source_release", "record_id", "match"}
VALUE_OPTIONAL = {"transforms", "source_value"}
REF_KEYS = {"source", "corpus_sha256", "record_id", "match", "role"}
SOURCE_KEYS = {"source_release_id", "source_id", "released_at", "artifact_sha256", "schema_version",
               "pipeline_version", "licence", "attribution", "manifest_sha256"}
HEX64 = re.compile(r"[0-9a-f]{64}")
REPLACED = Counter()


def norm(s):
    """Skill-side convention for entry IDs (the importer treats IDs as opaque): NFKC, Unicode
    case fold, then runs of letters, numbers, combining marks, & and % joined by single spaces."""
    s = unicodedata.normalize("NFKC", s or "").casefold()
    runs, cur = [], []
    for ch in s:
        if ch in "&%" or unicodedata.category(ch)[0] in "LNM":  # letters, numbers and combining marks
            cur.append(ch)
        elif cur:
            runs.append("".join(cur))
            cur = []
    if cur:
        runs.append("".join(cur))
    return " ".join(runs)


def entry_id(brand, title):
    return "pfc:" + hashlib.sha256(f"v1|{norm(brand)}|{norm(title)}".encode()).hexdigest()[:12]


def corpus_pins(repo: Path):
    res = repo / "Packages/FoodLedgerKit/Sources/FoodGenericSearch"
    pins, errs = {}, []
    for src, (resource, swift, const) in SWIFT_PINS.items():
        file_hash = hashlib.sha256((res / "Resources" / resource).read_bytes()).hexdigest()
        m = re.search(rf'static let {const} = "([0-9a-f]{{64}})"', (res / swift).read_text())
        if not m or m[1] != file_hash:
            errs.append(f"{src}: bundled file hash {file_hash[:12]} does not match the Swift pin")
        pins[src] = file_hash
    return pins, errs


def choose_reference(item, pins, basis):
    """One generic record per entry, by tier order: CoFID, then USDA, then TFDA (intake only)."""
    options = []
    gm, um = item.get("generic_match") or {}, item.get("usda_match") or {}
    if gm.get("cofid_record_id"):
        options.append(("cofid", gm["cofid_record_id"], gm.get("match")))
    if um.get("usda_record_id"):
        options.append(("usda", um["usda_record_id"], um.get("match")))
    if gm.get("source") in GENERIC_SOURCES and gm.get("record_id"):
        rid = str(gm["record_id"])
        if gm["source"] == "tfda" and not rid.startswith("tfda:"):
            rid = "tfda:" + rid  # the app's TFDA candidate record identity
        options.append((gm["source"], rid, gm.get("match")))
    for src, rid, match in options:
        if match in GENERIC_MATCHES:
            role = "merge" if (match == "same_food_same_state" and item["state"] in ("raw", "cooked")
                               and basis == "per_100_g") else "candidate"
            return {"source": src, "corpus_sha256": pins[src], "record_id": rid, "match": match, "role": role}
    return None


def owner_release(title, values, captured):
    """Opaque and deterministic: every field is a function of the hashed record, including its date."""
    blob = json.dumps({"title": title, "values": values, "captured": captured}, sort_keys=True,
                      ensure_ascii=False).encode()
    digest = hashlib.sha256(blob).hexdigest()
    return {"source_release_id": f"owner:sha256:{digest}", "source_id": "owner",
            "released_at": f"{captured}T00:00:00Z", "artifact_sha256": digest,
            "schema_version": "pfc-intake-label-v1", "pipeline_version": "personal-food-catalogue-skill-v1",
            "licence": "private", "attribution": "Label values typed or confirmed by the owner",
            "manifest_sha256": digest}


def value_out(v, kind, release, record_id, match):
    out = {"value": v["value"], "unit": v["unit"], "source_kind": kind, "source_release": release,
           "record_id": record_id, "match": match}
    if v.get("transforms"):
        out["transforms"] = v["transforms"]
        out["source_value"] = v["source_value"]
    return out


def build(cat, pins, generated):
    sources, items, withheld = {}, [], 0
    for i in cat["items"]:
        if i["kind"] != "food":
            continue
        tiers = i.get("label_tiers") or {}
        values = {}
        for k, v in sorted((tiers.get("off") or {}).items()):
            rel = cat["off_releases"][v["release"]]
            sources[rel["source_release_id"]] = rel
            values[k] = value_out(v, "exact_product_dataset", rel["source_release_id"],
                                  v["source"].split(":", 2)[2], "probable")
        owner = {}
        for k, v in sorted((tiers.get("owner") or {}).items()):
            if v["source"].split(":")[1].endswith("unconfirmed"):
                withheld += 1  # agent-read values never leave until the owner confirms them
            else:
                owner[k] = v
        if owner:
            if not i.get("captured"):
                withheld += len(owner)  # no capture date, no deterministic release: never guess one
                owner = {}
            else:
                rel = owner_release(i["title"], {k: v["value"] for k, v in owner.items()}, i["captured"])
                sources[rel["source_release_id"]] = rel
            for k, v in owner.items():  # a printed label the owner typed or confirmed comes first (measured)
                values[k] = value_out(v, "manual_declaration", rel["source_release_id"], None, "owner")
        fixed = {}
        for f, allowed, fallback in (("category", CATEGORIES, "other"), ("product_type", PRODUCT_TYPES, "unknown"),
                                     ("state", STATES, "unknown")):
            v = i.get(f)
            ok = isinstance(v, str) and v in allowed  # a list or dict from a mapping is never hashed
            fixed[f] = v if ok else fallback
            if v is not None and not ok:
                REPLACED[f] += 1  # model output outside the closed list: never passed through
        basis = i.get("basis", "per_100_g")
        if not norm(i["title"]):
            REPLACED["empty_title"] += 1
            continue
        items.append({
            "id": entry_id(i.get("brand"), i["title"]), "brand": i.get("brand"), "title": i["title"],
            "titles": i.get("titles") or [i["title"]], "aliases": i.get("aliases") or [],
            "concept": i.get("concept"), "variety": i.get("variety"), "fallback_chain": i.get("fallback_chain") or [],
            "category": fixed["category"], "product_type": fixed["product_type"], "state": fixed["state"],
            "basis": basis, "label_nutrients": values,
            "generic_reference": choose_reference({**i, "state": fixed["state"]}, pins, basis),
        })
    items.sort(key=lambda x: x["id"])
    doc = {"schema": SCHEMA, "generated": generated,
           "sources": sorted(sources.values(), key=lambda s: s["source_release_id"]),
           "generic_corpora": [{"source": k, "corpus_sha256": h} for k, h in sorted(pins.items())],
           "items": items}
    return doc, withheld


DATE = re.compile(r"[0-9]{4}-[0-9]{2}-[0-9]{2}")


def _date(s):
    if not isinstance(s, str) or not DATE.fullmatch(s):
        return False  # strict YYYY-MM-DD; Python's fromisoformat would also take week and basic forms
    try:
        datetime.date.fromisoformat(s)
        return True
    except ValueError:
        return False


def _utc(s):
    return isinstance(s, str) and re.fullmatch(r"[0-9]{4}-[0-9]{2}-[0-9]{2}T00:00:00Z", s) is not None and _date(s[:10])


def _str_list(v):
    return isinstance(v, list) and all(isinstance(x, str) for x in v)


def _opt_str(v):
    return v is None or isinstance(v, str)


def _num(v):
    if isinstance(v, bool) or not isinstance(v, (int, float)):
        return False
    try:
        return math.isfinite(v) and v >= 0 and abs(float(v)) < 1e15  # huge numbers are invalid values
    except OverflowError:
        return False


class _Reject(Exception):
    pass


# Strings are skipped whole (escapes included), so a bracket inside a string never counts.
_STRUCTURE = re.compile(r'"(?:[^"\\]|\\.)*"?|[\[\]{}]', re.S)
_SURROGATE = re.compile("[\ud800-\udfff]")


def _depth_ok(text):
    depth = 0
    for m in _STRUCTURE.finditer(text):
        c = m.group()
        if c in "[{":
            depth += 1
            if depth > MAX_DEPTH:
                return False
        elif c in "]}":
            depth -= 1
    return True


def _value_count(v):
    if isinstance(v, list):
        return 1 + sum(_value_count(x) for x in v)
    if isinstance(v, dict):
        return 1 + sum(_value_count(x) for x in v.values())
    return 1


def _lone_surrogate(v):
    """Python decodes an unpaired \\ud800 escape into a string; Swift cannot hold one, so both refuse it."""
    if isinstance(v, str):
        return _SURROGATE.search(v) is not None
    if isinstance(v, list):
        return any(_lone_surrogate(x) for x in v)
    if isinstance(v, dict):
        return any(_lone_surrogate(k) or _lone_surrogate(x) for k, x in v.items())
    return False


def _no_duplicate_keys(pairs):
    keys = [k for k, _ in pairs]
    if len(keys) != len(set(keys)):
        raise _Reject("duplicate-key")
    return dict(pairs)


def _check_value(where, k, v, declared, err, v2=False, basis=None):
    """Returns (release, serving) for a product value under v2, for the serving-mismatch rule."""
    if k not in CANON_UNITS:
        return err("unknown-nutrient", f"{where}: {k}")
    if not isinstance(v, dict):
        return err("value-shape", f"{where}: {k} is not an object")
    keys = set(v)
    if not VALUE_KEYS <= keys or not keys <= VALUE_KEYS | VALUE_OPTIONAL or len(keys & VALUE_OPTIONAL) == 1:
        return err("value-keys", f"{where}: {k}")
    if v["unit"] != CANON_UNITS[k]:
        err("unit", f"{where}: {k} unit must be {CANON_UNITS[k]}")
    if not _num(v["value"]):
        err("value", f"{where}: {k}")
    kind = v["source_kind"]
    if not isinstance(kind, str) or kind not in KIND_MATCH or KIND_MATCH[kind] != v["match"]:
        return err("kind-match", f"{where}: {k}")
    if kind == "manual_declaration" and v["record_id"] is not None:
        err("record-id", f"{where}: {k} owner value must have record_id null")
    if kind == "exact_product_dataset" and not (isinstance(v["record_id"], str)
                                                and re.fullmatch(r"off:gtin:[0-9]{14}", v["record_id"])):
        err("record-id", f"{where}: {k} product record_id must be off:gtin:<14 digits>")
    src = declared.get(v["source_release"]) if isinstance(v["source_release"], str) else None
    if src is None:
        err("undeclared-release", f"{where}: {k}")
    elif {"manual_declaration": "owner", "exact_product_dataset": "open-food-facts"}[kind] != src["source_id"]:
        err("release-kind", f"{where}: {k}")
    if v2:
        return _check_value_v2(where, k, v, kind, src, basis, err)
    if "transforms" in v:
        tr, sv = v["transforms"], v["source_value"]
        if not isinstance(sv, dict) or set(sv) != {"value", "unit"} or not _num(sv.get("value")) \
                or not isinstance(sv.get("unit"), str):
            return err("source-value", f"{where}: {k}")
        if not isinstance(tr, list) or len(tr) != 1 or not isinstance(tr[0], dict) \
                or set(tr[0]) != {"transform_id", "version"} or not all(isinstance(x, str) for x in tr[0].values()):
            return err("transform-shape", f"{where}: {k}")
        rule = TRANSFORMS.get((tr[0]["transform_id"], tr[0]["version"]))
        if rule is None:
            err("transform-unknown", f"{where}: {k}")
        elif rule[0] != k or rule[1] != sv["unit"] or rule[2] != kind:
            err("transform-scope", f"{where}: {k} transform does not apply to this nutrient, unit or source")
        elif _num(v["value"]) and abs(rule[3](sv["value"]) - v["value"]) > TOLERANCE * abs(rule[3](sv["value"])) + 1e-9:
            err("transform-arithmetic", f"{where}: {k}")


def _serving_quantity_ok(q):
    if isinstance(q, bool) or not isinstance(q, (int, float)):
        return False
    try:
        return math.isfinite(q) and q > 0 and float(q) < 1e15
    except OverflowError:
        return False


def _check_value_v2(where, k, v, kind, src, basis, err):
    """Catalogue v2 transforms (import v2 section 3); everything before them is the v1 rule."""
    product = kind == "exact_product_dataset" and isinstance(v["source_release"], str)
    if "transforms" not in v:
        return (v["source_release"], None) if product else None
    tr, sv = v["transforms"], v["source_value"]
    if not isinstance(sv, dict) or set(sv) not in ({"value", "unit"}, {"value", "unit", "serving"}) \
            or not _num(sv.get("value")) or not isinstance(sv.get("unit"), str):
        return err("source-value", f"{where}: {k}")
    serving = sv.get("serving")
    if "serving" in sv and not (isinstance(serving, dict) and set(serving) == {"quantity", "unit"}
                                and _serving_quantity_ok(serving["quantity"]) and serving["unit"] in ("g", "ml")):
        return err("source-value", f"{where}: {k} serving must be {{quantity above 0, unit g or ml}}")
    if not isinstance(tr, list) or len(tr) not in (1, 2) or not all(
            isinstance(t, dict) and set(t) == {"transform_id", "version"} and all(isinstance(x, str) for x in t.values())
            for t in tr):
        return err("transform-shape", f"{where}: {k}")
    pairs = [(t["transform_id"], t["version"]) for t in tr]
    if len(pairs) == 2 and pairs != [MASS_G_TO_MG, SERVING_TO_100]:
        return err("transform-shape", f"{where}: {k} the only chain is mass-g-to-mg then off-serving-to-100")
    if (SERVING_TO_100 in pairs) != ("serving" in sv):
        return err("source-value", f"{where}: {k} serving and off-serving-to-100 come together or not at all")
    if any(p not in TRANSFORMS and p != SERVING_TO_100 for p in pairs):
        return err("transform-unknown", f"{where}: {k}")
    unit, expected = sv["unit"], sv["value"]
    for p in pairs:
        if p == SERVING_TO_100:
            ok = k in SERVING_NUTRIENTS and kind == "exact_product_dataset" and unit == CANON_UNITS[k] \
                and src is not None and src["pipeline_version"] == OFF_V6 and serving["unit"] == SERVING_UNITS.get(basis)
            expected = expected * (100 / serving["quantity"])
        else:
            rule = TRANSFORMS[p]
            ok = rule[0] == k and rule[1] == unit and rule[2] == kind
            expected, unit = rule[3](expected), CANON_UNITS[k]
        if not ok:
            return err("transform-scope", f"{where}: {k} transform does not apply to this nutrient, unit, source or basis")
    if _num(v["value"]):
        # a tiny serving can overflow the expected value; inf > inf is false, so check it first
        if not math.isfinite(expected) or abs(expected - v["value"]) > TOLERANCE * abs(expected) + 1e-9:
            err("transform-arithmetic", f"{where}: {k}")
        elif "serving" in sv and v["value"] > PLAUSIBLE_MAXIMUM[CANON_UNITS[k]]:
            err("serving-implausible", f"{where}: {k} more than any food holds per 100")
    if product:
        return v["source_release"], (serving["quantity"], serving["unit"]) if "serving" in sv else None
    return None


def _check(doc, err):
    if not isinstance(doc, dict) or set(doc) != TOP_KEYS:
        return err("top-keys", f"top-level keys must be exactly {sorted(TOP_KEYS)}")
    v2 = doc["schema"] == SCHEMA_V2  # an unknown schema keeps the v1 rules for the rest
    if doc["schema"] != SCHEMA_V1 and not v2:
        err("schema", "unknown schema")
    patterns = RELEASE_PATTERNS_V2 if v2 else RELEASE_PATTERNS
    projections = OFF_PROJECTIONS_V2 if v2 else OFF_PROJECTIONS
    if not _date(doc["generated"]):
        err("generated", "generated must be a real YYYY-MM-DD date")
    declared = {}
    if not isinstance(doc["sources"], list):
        err("sources", "sources must be a list")
    for s in doc["sources"] if isinstance(doc["sources"], list) else []:
        if not isinstance(s, dict) or set(s) != SOURCE_KEYS or not all(isinstance(s[k], str) and s[k] for k in SOURCE_KEYS):
            err("source-fields", "a source is missing a release field")
            continue
        sid, kind = s["source_release_id"], s["source_id"]
        if kind not in SOURCE_IDS or not patterns[kind].fullmatch(sid):
            err("source-form", f"{sid[:40]}")
            continue
        id_hash = sid.split(":")[2]
        if s["artifact_sha256"] != id_hash or s["manifest_sha256"] != id_hash:
            err("source-hash", f"{sid[:40]}: artifact and manifest hashes must equal the hash in the ID")
        if not _utc(s["released_at"]) or (kind == "open-food-facts" and not sid.endswith(":retrieved:" + s["released_at"][:10])):
            err("source-date", f"{sid[:40]}")
        pins = SOURCE_PINS[kind]
        attribution_ok = (re.fullmatch(r"Open Food Facts · https://world\.openfoodfacts\.org/product/[0-9]{8,14}",
                                       s["attribution"]) is not None) if kind == "open-food-facts" \
            else s["attribution"] == pins["attribution"]
        pipeline_ok = (s["pipeline_version"] in projections and sid.split(":")[4] == s["pipeline_version"]) \
            if kind == "open-food-facts" else s["pipeline_version"] == pins["pipeline_version"]
        if any(s[f] != pins[f] for f in ("schema_version", "licence")) or not pipeline_ok or not attribution_ok:
            err("source-pins", f"{sid[:40]}: schema, pipeline, licence or attribution off-pin")
        if sid in declared:
            err("source-duplicate", f"{sid[:40]}")
        declared[sid] = s
    corpora = {}
    for c in doc["generic_corpora"] if isinstance(doc["generic_corpora"], list) else [None]:
        if not isinstance(c, dict) or set(c) != {"source", "corpus_sha256"} or not isinstance(c["source"], str) \
                or c["source"] not in GENERIC_SOURCES \
                or not isinstance(c["corpus_sha256"], str) or not HEX64.fullmatch(c["corpus_sha256"]) or c["source"] in corpora:
            err("corpus", "invalid or duplicate generic corpus entry")
            continue
        corpora[c["source"]] = c["corpus_sha256"]
    if not isinstance(doc["items"], list):
        return err("items", "items must be a list")
    if len(doc["items"]) > LIMIT_ITEMS:
        err("count", "too many items")
    ids, prev = set(), ""
    for n, it in enumerate(doc["items"]):
        where = f"item {n}"
        if not isinstance(it, dict) or set(it) != ITEM_KEYS:
            err("item-keys", where)
            continue
        if not isinstance(it["title"], str) or not it["title"].strip() or not _opt_str(it["brand"]):
            err("title", where)
            continue
        if not isinstance(it["id"], str) or not re.fullmatch(r"pfc:[0-9a-f]{12}", it["id"]):
            err("id-form", where)
            continue
        where = it["id"]
        if it["id"] in ids:
            err("id-duplicate", where)
        elif it["id"] <= prev:
            err("id-order", where)
        ids.add(it["id"])
        prev = max(prev, it["id"])
        if not (_str_list(it["titles"]) and _str_list(it["aliases"]) and _str_list(it["fallback_chain"])
                and _opt_str(it["concept"]) and _opt_str(it["variety"])):
            err("item-types", where)
        if not all(isinstance(it[f], str) for f in ("category", "product_type", "state", "basis")) \
                or it["category"] not in CATEGORIES or it["product_type"] not in PRODUCT_TYPES \
                or it["state"] not in STATES or it["basis"] not in BASES:
            err("vocabulary", where)
            continue
        ref = it["generic_reference"]
        if ref is not None:
            if not isinstance(ref, dict) or set(ref) != REF_KEYS or not all(isinstance(ref[x], str) for x in REF_KEYS) \
                    or ref["source"] not in GENERIC_SOURCES or ref["match"] not in GENERIC_MATCHES \
                    or ref["role"] not in ("merge", "candidate") or not ref["record_id"]:
                err("reference", where)
            else:
                if corpora.get(ref["source"]) != ref["corpus_sha256"]:
                    err("reference-corpus", where)
                if ref["role"] == "merge" and not (ref["match"] == "same_food_same_state"
                                                   and it["state"] in ("raw", "cooked") and it["basis"] == "per_100_g"):
                    err("merge-condition", where)
                if (ref["source"] == "tfda") != ref["record_id"].startswith("tfda:"):
                    err("tfda-record-id", where)
        if not isinstance(it["label_nutrients"], dict):
            err("label-nutrients", where)
            continue
        servings = {}
        for k, v in it["label_nutrients"].items():
            got = _check_value(where, k, v, declared, err, v2, it["basis"])
            if got is not None:
                servings.setdefault(got[0], set()).add(got[1])
        if any(len(s) > 1 for s in servings.values()):
            err("serving-mismatch", f"{where}: values from one release disagree on the serving size")


def check_bytes(data: bytes):
    """The importer's rejection rules (contract section 4.2). Returns a list of "code: detail"
    strings, empty when the file is accepted; never raises."""
    errs = []
    err = lambda code, detail="": errs.append(f"{code}: {detail}")
    if len(data) > LIMIT_BYTES:
        return ["size: file larger than 26,214,400 bytes"]
    if data[:3] == b"\xef\xbb\xbf":
        return ["bom: UTF-8 byte-order mark"]
    try:
        def _no_constants(token):
            raise _Reject("json")  # NaN, Infinity and -Infinity are not JSON (Swift rejects them too)
        text = data.decode("utf-8", errors="strict")
        if not _depth_ok(text):
            return [f"json: nesting deeper than {MAX_DEPTH}"]
        doc = json.loads(text, object_pairs_hook=_no_duplicate_keys, parse_constant=_no_constants)
    except UnicodeDecodeError:
        return ["encoding: not UTF-8"]
    except _Reject as r:
        return [f"{r}: a JSON object repeats a key" if str(r) == "duplicate-key" else f"{r}: NaN or Infinity token"]
    except Exception as e:  # ValueError (including integers over 4,300 digits), anything else
        return [f"json: {type(e).__name__}"]
    if _value_count(doc) > MAX_VALUES:
        return [f"count: more than {MAX_VALUES:,} JSON values"]
    if _lone_surrogate(doc):
        return ["json: unpaired surrogate escape"]
    try:
        _check(doc, err)
    except Exception as e:  # a type the rules did not anticipate is a rejection, never a crash
        return [f"malformed: {type(e).__name__}"]
    return errs


def check_export_conventions(doc):
    """Skill-side checks the importer does not repeat: IDs derived from brand and title, and no
    two entries with the same normalised brand and title."""
    errs, seen = [], {}
    for it in doc["items"]:
        if it["id"] != entry_id(it["brand"], it["title"]):
            errs.append(f"id-derivation: {it['title'][:40]}")
        key = (norm(it["brand"]), norm(it["title"]))
        if key in seen:
            errs.append(f"duplicate-title: {it['title'][:40]} and {seen[key][:40]}")
        seen[key] = it["title"]
    return errs


def change_report(old, new):
    """Counts only (import v2 section 5): how a rebuild changes entries present in both files. The
    private workspace keeps it; nothing here names a food."""
    before = {it["id"]: it for it in (old or {}).get("items", []) if isinstance(it, dict) and "id" in it}
    counts = Counter()
    for it in new["items"]:
        was = before.get(it["id"])
        if was is None:
            counts["new entries"] += 1
            continue
        if len(it["label_nutrients"]) > len(was.get("label_nutrients") or {}):
            counts["entries gaining label values"] += 1
        if it["basis"] != was.get("basis"):
            counts["entries changing basis"] += 1
        old_role = (was.get("generic_reference") or {}).get("role")
        if old_role == "merge" and (it["generic_reference"] or {}).get("role") != "merge":
            counts["entries losing a merge"] += 1
    counts["entries with scaled values"] = sum(
        any("serving" in (v.get("source_value") or {}) for v in it["label_nutrients"].values()) for it in new["items"])
    return dict(sorted(counts.items()))


def main(ws: Path, repo: Path):
    out = ws / "out"
    cat = json.load(open(out / "personal-food-catalogue.json"))
    pins, pin_errs = corpus_pins(repo)
    if pin_errs:
        print("EXPORT REFUSED: " + "; ".join(pin_errs))
        sys.exit(2)
    generated = time.strftime("%Y-%m-%d")
    doc, withheld = build(cat, pins, generated)
    data = json.dumps(doc, indent=1, ensure_ascii=False).encode()
    errs = check_export_conventions(doc) + check_bytes(data)
    if errs:
        print("EXPORT REFUSED, the app would reject this file:")
        for e in errs[:30]:
            print("  -", e)
        sys.exit(2)
    from workspace_guard import check_output
    previous = next((out / n for n in ("personal-food-catalogue-v2.json", "personal-food-catalogue-v1.json")
                     if (out / n).exists()), None)
    try:
        prior = json.loads(previous.read_bytes()) if previous else None
        report = change_report(prior if isinstance(prior, dict) else None, doc)
    except (OSError, RecursionError, ValueError, TypeError, KeyError, AttributeError) as error:
        # The report only compares counts; a damaged earlier file must not stop the new
        # file, which has already passed every check, from being written.
        report = f"not compared, the previous file could not be read ({type(error).__name__})"
    p = check_output(out / "personal-food-catalogue-v2.json")
    p.write_bytes(data)
    p.chmod(0o600)
    refs = [it["generic_reference"] for it in doc["items"] if it["generic_reference"]]
    print(f"wrote {p} ({len(data) / 1e6:.2f} MB, {len(doc['items'])} entries, "
          f"{sum(r['role'] == 'merge' for r in refs)} merge and {sum(r['role'] == 'candidate' for r in refs)} candidate "
          f"references, {sum(bool(it['label_nutrients']) for it in doc['items'])} with label values, "
          f"{len(doc['sources'])} source releases)")
    print(f"release pfc:sha256:{hashlib.sha256(data).hexdigest()}")
    print(f"changes against {previous.name if previous else 'no previous file'}: {report}")
    if REPLACED:
        print(f"replaced values outside the closed vocabularies: {dict(REPLACED)}")
    if withheld:
        print(f"withheld {withheld} unconfirmed photo or page values; confirm them with the owner to include them")


if __name__ == "__main__":
    main(guard_workspace(Path(sys.argv[1])), Path(sys.argv[2]).expanduser())
