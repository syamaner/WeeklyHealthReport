"""The estimate rules of `personal-food-catalogue-estimates-v2`
(docs/personal-food-catalogue-estimates-v2-proposal.md sections 2, 3.1 and 3.3; phase gate
docs/personal-food-catalogue-estimates-v2-phase.md section 3.1).

Pure. `export_v1._check` runs the v2 part first and then calls `check` here, so the order of codes is:
the v2 part, the inherited estimate checks (ported from the R2 tool,
Tools/PersonalFoodDatabaseEvaluation/r2/estimates_v1.py, with its code strings), then the codec table
of contract section 3.1. The Swift codec applies the same rules in the same order. The bundled-record
checks (corpus pin, record, value, contradiction) are the app importer's and are not repeated here.
"""
import re

import export_v1
import estimates_v3 as V3

SCHEMA = "personal-food-catalogue-estimates-v2"
EVIDENCE_ID = re.compile(r"pfe:[0-9a-f]{16}")
EVIDENCE_KEYS = {"id", "entry_id", "nutrient", "approved_as_estimate", "source_type", "composition_source",
                 "source_reference", "page_access", "source_digest", "retrieved_on", "source_state",
                 "target_state", "state_basis", "method", "assumption", "derivation", "quality"}
ESTIMATE_KEYS = {"value", "unit", "evidence_id"}
SOURCE_TYPES = {"national_composition", "manufacturer_page", "aggregator"}
PAGE_ACCESS = {"direct_read", "indexed_copy"}
STATE_BASES = {"source_states_it", "stated_assumption", "unknown"}
METHODS = {"direct", "derived", "carried_from_same_food", "carried_from_similar_food"}
QUALITY_RANK = {"low": 0, "medium": 1, "high": 2}  # closed list (contract section 3.3)
OWN_METHOD = {"same_food_same_state": "carried_from_same_food", "close": "carried_from_similar_food"}
HEX64 = re.compile(r"[0-9a-f]{64}")
CONTROL = re.compile(r"[\x00-\x1f\x7f-\x9f]")
URL_LIMIT = 2048
URL_PREFIX = "https://"
HOST_LABEL = re.compile(r"[A-Za-z0-9-]+")
PORT = re.compile(r"[0-9]{1,5}")
DIGITS = re.compile(r"[0-9]+")
# The codes only an estimates v2 file can get; the v1 and v2 manifests list their sets without them.
RULE_CODES = (
    "evidence-keys", "not-approved", "token", "date", "digest", "type-fields", "corpus-undeclared",
    "source-reference", "open-food-facts-host", "free-text", "derivation", "derivation-missing",
    "derivation-shape", "derivation-unexpected", "evidence-id", "evidence-duplicate", "evidence-order",
    "estimated-nutrients", "estimate-keys", "label-and-estimate", "evidence-dangling", "evidence-mismatch",
    "evidence-unused-or-shared",
    "estimate-own-method", "estimate-own-state", "estimate-own-held", "estimate-quality")
# `estimate-own-merge` is an importer code since own merge amendment G4
# (docs/personal-food-catalogue-own-merge-amendment-v1.md): only the record shows whether the app merges it.
# `estimate-basis` is an importer code since gap estimates amendment G2
# (docs/personal-food-catalogue-gap-estimates-v1-amendment.md): only the record shows the basis.
# Contract section 6 of estimates v1: the app's own pairs, each limited to its nutrient and source unit.
# Built from the v1 checker's table so the two cannot drift; its source-kind column does not apply.
TRANSFORMS = {key: (nutrient, unit, fn) for key, (nutrient, unit, _kind, fn) in export_v1.TRANSFORMS.items()}
TOLERANCE = 0.005


def page_host(ref):
    """The host of a page URL under the phase gate's grammar (section 3.1 item 7), lower-cased and
    without a trailing dot, or None when the text is not such a URL. Hand-written, not `urlsplit`, so
    the Swift codec gives the same verdict for every string."""
    if not isinstance(ref, str) or not ref.startswith(URL_PREFIX):
        return None
    try:
        raw = ref.encode("ascii")
    except UnicodeEncodeError:
        return None
    if len(raw) > URL_LIMIT or any(b < 0x21 or b > 0x7e for b in raw) or "?" in ref or "#" in ref:
        return None
    authority = ref[len(URL_PREFIX):].split("/", 1)[0]
    if "@" in authority:
        return None
    host, colon, port = authority.partition(":")
    if colon and not (PORT.fullmatch(port) and 1 <= int(port) <= 65535):
        return None
    if host.endswith("."):
        host = host[:-1]
    labels = host.split(".")
    if len(labels) < 2 or not all(HOST_LABEL.fullmatch(label) for label in labels):
        return None
    host = host.lower()
    last = labels[-1].lower()
    if host == "localhost" or host.endswith(".localhost") or DIGITS.fullmatch(last) or last.startswith("0x"):
        return None
    return host


def off_host(host) -> bool:
    return host == "openfoodfacts.org" or (host or "").endswith(".openfoodfacts.org")


def text_ok(s, limit) -> bool:
    return isinstance(s, str) and bool(s.strip()) and len(s) <= limit and not CONTROL.search(s)


def derivation_shape_ok(d) -> bool:
    """Exactly {transform_id, version, source_value: {value, unit}}, with strings and a valid value."""
    return (isinstance(d, dict) and set(d) == {"transform_id", "version", "source_value"}
            and isinstance(d["transform_id"], str) and bool(d["transform_id"])
            and isinstance(d["version"], str) and bool(d["version"])
            and isinstance(d["source_value"], dict) and set(d["source_value"]) == {"value", "unit"}
            and export_v1._num(d["source_value"]["value"]) and isinstance(d["source_value"]["unit"], str)
            and bool(d["source_value"]["unit"]))


def transform_value(derivation, nutrient):
    """The recomputed value for a derivation, or None when it is outside the closed list or scope."""
    if not derivation_shape_ok(derivation):
        return None
    rule = TRANSFORMS.get((derivation["transform_id"], derivation["version"]))
    if rule is None:
        return None
    target, unit, fn = rule
    if derivation["source_value"]["unit"] != unit or target != nutrient:
        return None
    return fn(derivation["source_value"]["value"])


def transform_matches(derivation, nutrient, value) -> bool:
    expect = transform_value(derivation, nutrient)
    return expect is not None and export_v1._num(value) and abs(expect - value) <= TOLERANCE * abs(expect) + 1e-9


def source_types(schema) -> set:
    """The closed source-type list of one catalogue schema (label photo phase gate section 1)."""
    return SOURCE_TYPES | {V3.TOKEN} if schema == V3.SCHEMA else SOURCE_TYPES


def check_record(rec, corpora, err, where, schema=SCHEMA):
    """Estimates v1 section 2.2 for one evidence record, plus the required `quality` token; in a v3
    file, a photo record takes the photo rules in place of the page-type checks."""
    if not isinstance(rec, dict) or set(rec) != EVIDENCE_KEYS:
        return err("evidence-keys", where)
    if rec["approved_as_estimate"] is not True:
        err("not-approved", where)
    st = rec["source_type"]
    if not all(isinstance(rec[k], str) for k in ("source_type", "state_basis", "method", "quality")) \
            or st not in source_types(schema) or rec["state_basis"] not in STATE_BASES or rec["method"] not in METHODS \
            or rec["quality"] not in QUALITY_RANK:
        return err("token", where)
    if st == V3.TOKEN:
        V3.check_record(rec, err, where, export_v1._date)
    elif st == "national_composition":
        cs = rec["composition_source"]
        if not isinstance(cs, str) or cs not in export_v1.GENERIC_SOURCES or rec["page_access"] is not None:
            err("type-fields", where)
        elif cs not in corpora:
            err("corpus-undeclared", where)
        ref = rec["source_reference"]
        if not isinstance(ref, str) or not ref or CONTROL.search(ref) or (cs == "tfda") != ref.startswith("tfda:"):
            err("source-reference", where)
        if rec["retrieved_on"] is not None and not export_v1._date(rec["retrieved_on"]):
            err("date", where)
    else:
        access = rec["page_access"]
        if rec["composition_source"] is not None or not isinstance(access, str) or access not in PAGE_ACCESS:
            err("type-fields", where)
        host = page_host(rec["source_reference"])
        if host is None:
            err("source-reference", where)
        elif off_host(host):
            err("open-food-facts-host", where)
        if not export_v1._date(rec["retrieved_on"]):
            err("date", where)
    if rec["source_digest"] is not None and not (isinstance(rec["source_digest"], str)
                                                 and HEX64.fullmatch(rec["source_digest"])):
        err("digest", where)
    if not (text_ok(rec["source_state"], 200) and text_ok(rec["target_state"], 200)
            and text_ok(rec["assumption"], 500)):
        err("free-text", where)
    if rec["method"] == "derived":
        if rec["derivation"] is None:
            err("derivation-missing", where)
        elif not derivation_shape_ok(rec["derivation"]):
            err("derivation-shape", where)
    elif rec["derivation"] is not None:
        err("derivation-unexpected", where)


def is_own(rec, ref) -> bool:
    """A national composition record that names the entry's own generic reference, whatever its role."""
    return (rec["source_type"] == "national_composition" and isinstance(ref, dict)
            and ref.get("source") == rec["composition_source"] and ref.get("record_id") == rec["source_reference"])


def ceiling(rec, own: bool, composite: bool = False, own_merge: bool = False) -> str:
    """The highest tier the codec accepts for this record (contract section 3.3). A national estimate on
    a packaged composite dish is a generic recipe: at most `low` (amendment G1). An estimate from the
    entry's own `merge` record, which the app did not merge, is at most `medium` (amendment G4)."""
    if rec["state_basis"] == "unknown":
        return "low"
    if composite and rec["source_type"] == "national_composition":
        return "low"
    if rec["source_type"] == V3.TOKEN or own_merge:
        return "medium"
    if rec["method"] in ("carried_from_same_food", "direct") and rec["state_basis"] == "source_states_it" \
            and rec["page_access"] != "indexed_copy" and (rec["source_type"] != "national_composition" or own):
        return "high"
    return "medium"


def table_codes(rec, item) -> list:
    """The rows of contract section 3.1 that one bound, valid record matches, in table order."""
    ref = item["generic_reference"]
    own = is_own(rec, ref)
    candidate = own and ref["role"] == "candidate"
    # Amendment G4: an own `merge` record is judged as an own same-food record, never held; whether
    # the app merges it is the importer's `estimate-own-merge`.
    own_merge = own and ref["role"] == "merge"
    codes = []
    if (candidate or own_merge) and rec["method"] != OWN_METHOD[ref["match"]]:
        codes.append("estimate-own-method")
    if (candidate or own_merge) and rec["state_basis"] == "unknown":
        codes.append("estimate-own-state")
    if candidate and ref["match"] == "same_food_same_state" and item["state"] in ("raw", "cooked"):
        codes.append("estimate-own-held")
    if QUALITY_RANK[rec["quality"]] > QUALITY_RANK[ceiling(rec, own, item["product_type"] == "packaged_composite",
                                                            own_merge)]:
        codes.append("estimate-quality")
    if rec["source_type"] == V3.TOKEN:
        codes += V3.relation_codes(rec, item)
    return codes


def check(doc, report, failed_items, duplicate_ids):
    """`failed_items` are the indexes of entries that raised a code in the v2 part and
    `duplicate_ids` the entry IDs that occur more than once: their records get no table row."""
    raised = [0]

    def err(code, detail=""):
        raised[0] += 1
        report(code, detail)

    schema = doc.get("schema")
    item_keys = export_v1.ITEM_KEYS | {"estimated_nutrients"}
    corpora = {c["source"] for c in doc["generic_corpora"]
               if isinstance(c, dict) and isinstance(c.get("source"), str)} \
        if isinstance(doc["generic_corpora"], list) else set()
    records, faulty, prev = {}, set(), ""
    for n, rec in enumerate(doc["estimate_evidence"]):
        rid = rec.get("id") if isinstance(rec, dict) else None
        if not isinstance(rid, str) or not EVIDENCE_ID.fullmatch(rid):
            err("evidence-id", f"record {n}")
            continue
        before = raised[0]
        if rid in records:
            err("evidence-duplicate", f"record {n}")
        elif rid <= prev:
            err("evidence-order", f"record {n}")
        prev = max(prev, rid)
        records[rid] = rec
        check_record(rec, corpora, err, f"record {n}", schema)
        if raised[0] > before:
            faulty.add(rid)
    used, cited_by = {}, {}
    for n, it in enumerate(doc["items"]):
        if not isinstance(it, dict) or set(it) != item_keys:
            continue  # item-keys was raised once, in the v2 part
        est, labels = it["estimated_nutrients"], it["label_nutrients"]
        if not isinstance(est, dict):
            err("estimated-nutrients", f"item {n}")
            continue
        for key, v in est.items():
            where = f"item {n}: {key}"
            if key not in export_v1.CANON_UNITS:
                err("unknown-nutrient", where)
                continue
            if not isinstance(v, dict) or set(v) != ESTIMATE_KEYS:
                err("estimate-keys", where)
                continue
            before = raised[0]
            if v["unit"] != export_v1.CANON_UNITS[key]:
                err("unit", where)
            if not export_v1._num(v["value"]):
                err("value", where)
            if isinstance(labels, dict) and key in labels:
                err("label-and-estimate", where)
            rid = v["evidence_id"]
            rec = records.get(rid) if isinstance(rid, str) else None
            if rec is None:
                err("evidence-dangling", where)
                continue
            used[rid] = used.get(rid, 0) + 1
            cited_by[rid] = n
            # Only two strings can agree, so the Swift codec needs no Python value equality.
            if not isinstance(it["id"], str) or rec.get("entry_id") != it["id"] or rec.get("nutrient") != key:
                err("evidence-mismatch", where)
            if rec.get("method") == "derived" and rec.get("derivation") is not None \
                    and not transform_matches(rec["derivation"], key, v["value"]):
                err("derivation", where)
            if raised[0] > before:
                faulty.add(rid)
    for rid in records:
        if used.get(rid, 0) != 1:
            err("evidence-unused-or-shared", rid)
            faulty.add(rid)
    seen = set()
    for rec in doc["estimate_evidence"]:
        rid = rec.get("id") if isinstance(rec, dict) else None
        if not isinstance(rid, str) or rid not in records or rid in faulty or rid in seen:
            continue
        seen.add(rid)
        n = cited_by[rid]
        item = doc["items"][n]
        if n in failed_items or item["id"] in duplicate_ids:
            continue
        for code in table_codes(rec, item):
            report(code, rid)
    if schema == V3.SCHEMA:
        V3.check_missing(doc, err)
