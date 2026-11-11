"""The file rules of `personal-food-catalogue-estimates-v1` (estimates contract sections 2.1 to 2.3
and section 6), as a builder-side mirror of what the app's importer will enforce. Section 6 limits
each transform to "its nutrient, source unit and the rules of import v1 section 4", so the transform
table is import v1's: `mass-g-to-mg` applies to sodium only.

Pure. `check_bytes` returns "code: detail" strings, empty when the file is accepted, and never
raises. The v1 part (the file without `estimate_evidence` and `estimated_nutrients`, under the v1
schema name) is checked with the unchanged v1 rules. The bundled-corpus value comparison (contract
section 4.3) is the importer's and is not repeated here.
"""
import ipaddress
import json
import re
from urllib.parse import urlsplit

import export_v1

SCHEMA = "personal-food-catalogue-estimates-v1"
EVIDENCE_ID = re.compile(r"pfe:[0-9a-f]{16}")
EVIDENCE_KEYS = {"id", "entry_id", "nutrient", "approved_as_estimate", "source_type", "composition_source",
                 "source_reference", "page_access", "source_digest", "retrieved_on", "source_state",
                 "target_state", "state_basis", "method", "assumption", "derivation"}
SOURCE_TYPES = {"national_composition", "manufacturer_page", "aggregator"}
PAGE_TYPES = {"manufacturer_page", "aggregator"}
PAGE_ACCESS = {"direct_read", "indexed_copy"}
STATE_BASES = {"source_states_it", "stated_assumption", "unknown"}
METHODS = {"direct", "derived", "carried_from_same_food", "carried_from_similar_food"}
HEX64 = re.compile(r"[0-9a-f]{64}")
CONTROL = re.compile(r"[\x00-\x1f\x7f-\x9f]")
URL_LIMIT = 2048
NUMERIC_LABEL = re.compile(r"[0-9]+|0x[0-9a-f]*")
# Contract section 6: the app's own pairs, each limited to its nutrient and source unit as in import v1
# section 4. Built from the v1 checker's table so the two cannot drift; the source-kind column of that
# table does not apply to estimates. (transform_id, version) -> (nutrient, source unit, function)
TRANSFORMS = {key: (nutrient, unit, fn) for key, (nutrient, unit, _kind, fn) in export_v1.TRANSFORMS.items()}
TOLERANCE = 0.005


def off_host(host: str) -> bool:
    host = (host or "").lower().rstrip(".")
    return host == "openfoodfacts.org" or host.endswith(".openfoodfacts.org")


def public_host(host) -> bool:
    """A named host with a dot; not an IP literal, localhost or a single-label name."""
    host = (host or "").lower().rstrip(".")
    if not host or "." not in host or host == "localhost" or host.endswith(".localhost"):
        return False
    # A real top-level label is never numeric, so this also refuses the IP spellings ipaddress does not
    # parse but resolvers do (127.0.0.01, 127.1, 0x7f.1, 2130706433.x.0).
    if ":" in host or NUMERIC_LABEL.fullmatch(host.rsplit(".", 1)[-1]):
        return False
    try:
        ipaddress.ip_address(host)
        return False
    except ValueError:
        return True


def page_url_ok(ref) -> bool:
    """A public HTTPS URL with no user information, query string or fragment, at most 2,048 bytes."""
    if not isinstance(ref, str) or not ref or len(ref.encode("utf-8")) > URL_LIMIT or CONTROL.search(ref) \
            or any(c.isspace() for c in ref):
        return False
    try:
        u = urlsplit(ref)
        port_ok = u.port is None or u.port > 0
    except ValueError:
        return False
    return (u.scheme == "https" and public_host(u.hostname) and u.username is None and u.password is None
            and "@" not in u.netloc and not u.query and not u.fragment and "?" not in ref and "#" not in ref
            and port_ok)


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
    if not isinstance(derivation, dict) or set(derivation) != {"transform_id", "version", "source_value"}:
        return None
    sv = derivation["source_value"]
    rule = TRANSFORMS.get((derivation["transform_id"], derivation["version"])) \
        if isinstance(derivation["transform_id"], str) and isinstance(derivation["version"], str) else None
    if rule is None or not isinstance(sv, dict) or set(sv) != {"value", "unit"} or not export_v1._num(sv["value"]):
        return None
    target, unit, fn = rule
    if sv["unit"] != unit or target != nutrient:
        return None
    return fn(sv["value"])


def transform_matches(derivation, nutrient, value) -> bool:
    expect = transform_value(derivation, nutrient)
    return expect is not None and export_v1._num(value) and abs(expect - value) <= TOLERANCE * abs(expect) + 1e-9


def _date_ok(s) -> bool:
    return isinstance(s, str) and bool(export_v1._date(s))


def check_record(rec, corpora, err, where):
    """Contract section 2.2 for one evidence record (its value is checked by the caller)."""
    if not isinstance(rec, dict) or set(rec) != EVIDENCE_KEYS:
        return err("evidence-keys", where)
    if rec["approved_as_estimate"] is not True:
        err("not-approved", where)
    st = rec["source_type"]
    if not all(isinstance(rec[k], str) for k in ("source_type", "state_basis", "method")) \
            or st not in SOURCE_TYPES or rec["state_basis"] not in STATE_BASES or rec["method"] not in METHODS:
        return err("token", where)
    if st == "national_composition":
        cs = rec["composition_source"]
        if cs not in export_v1.GENERIC_SOURCES or rec["page_access"] is not None:
            err("type-fields", where)
        elif cs not in corpora:
            err("corpus-undeclared", where)
        ref = rec["source_reference"]
        if not isinstance(ref, str) or not ref or CONTROL.search(ref) or (cs == "tfda") != ref.startswith("tfda:"):
            err("source-reference", where)
        if rec["retrieved_on"] is not None and not _date_ok(rec["retrieved_on"]):
            err("date", where)
    else:
        if rec["composition_source"] is not None or rec["page_access"] not in PAGE_ACCESS:
            err("type-fields", where)
        if not page_url_ok(rec["source_reference"]):
            err("source-reference", where)
        elif off_host(urlsplit(rec["source_reference"]).hostname):
            err("open-food-facts-host", where)
        if not _date_ok(rec["retrieved_on"]):
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


def _v1_part(doc):
    v1 = {k: doc[k] for k in doc if k != "estimate_evidence"}
    v1["schema"] = "personal-food-catalogue-v1"
    v1["items"] = [{k: it[k] for k in it if k != "estimated_nutrients"} if isinstance(it, dict) else it
                   for it in doc["items"]] if isinstance(doc.get("items"), list) else doc.get("items")
    return v1


def _check(doc, err):
    if not isinstance(doc, dict) or set(doc) != export_v1.TOP_KEYS | {"estimate_evidence"}:
        return err("top-keys", "top-level keys must be v1's plus estimate_evidence")
    if doc["schema"] != SCHEMA:
        err("schema", "unknown schema")
    if not isinstance(doc["items"], list) or not isinstance(doc["estimate_evidence"], list):
        return err("items", "items and estimate_evidence must be lists")
    for e in export_v1.check_bytes(json.dumps(_v1_part(doc), ensure_ascii=False).encode()):
        err("v1", e)
    corpora = {c["source"] for c in doc["generic_corpora"] if isinstance(c, dict) and "source" in c} \
        if isinstance(doc["generic_corpora"], list) else set()
    records, prev = {}, ""
    for n, rec in enumerate(doc["estimate_evidence"]):
        rid = rec.get("id") if isinstance(rec, dict) else None
        if not isinstance(rid, str) or not EVIDENCE_ID.fullmatch(rid):
            err("evidence-id", f"record {n}")
            continue
        if rid in records:
            err("evidence-duplicate", f"record {n}")
        elif rid <= prev:
            err("evidence-order", f"record {n}")
        prev = max(prev, rid)
        records[rid] = rec
        check_record(rec, corpora, err, f"record {n}")
    used = {}
    for it in doc["items"]:
        if not isinstance(it, dict) or "estimated_nutrients" not in it:
            err("item-keys", "an entry has no estimated_nutrients")
            continue
        est, labels = it["estimated_nutrients"], it.get("label_nutrients")
        if not isinstance(est, dict):
            err("estimated-nutrients", "not an object")
            continue
        for key, v in est.items():
            where = f"{it.get('id')}: {key}"
            if key not in export_v1.CANON_UNITS:
                err("unknown-nutrient", where)
                continue
            if not isinstance(v, dict) or set(v) != {"value", "unit", "evidence_id"}:
                err("estimate-keys", where)
                continue
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
            if rec.get("entry_id") != it.get("id") or rec.get("nutrient") != key:
                err("evidence-mismatch", where)
            if rec.get("method") == "derived" and rec.get("derivation") is not None \
                    and not transform_matches(rec["derivation"], key, v["value"]):
                err("derivation", where)
            ref = it.get("generic_reference")
            if rec.get("source_type") == "national_composition" and isinstance(ref, dict) \
                    and ref.get("source") == rec.get("composition_source") \
                    and ref.get("record_id") == rec.get("source_reference"):
                err("own-reference", where)
    for rid in records:
        if used.get(rid, 0) != 1:
            err("evidence-unused-or-shared", rid)


def check_bytes(data: bytes):
    errs = []

    def err(code, detail=""):
        errs.append(f"{code}: {detail}")

    if len(data) > export_v1.LIMIT_BYTES:
        return ["size: file larger than 26,214,400 bytes"]
    if data[:3] == b"\xef\xbb\xbf":
        return ["bom: UTF-8 byte-order mark"]
    try:
        def _no_constants(token):
            raise export_v1._Reject("json")
        doc = json.loads(data.decode("utf-8", errors="strict"), object_pairs_hook=export_v1._no_duplicate_keys,
                         parse_constant=_no_constants)
    except UnicodeDecodeError:
        return ["encoding: not UTF-8"]
    except export_v1._Reject as r:
        return [f"{r}: rejected token or repeated key"]
    except Exception as e:  # noqa: BLE001  (any parse failure is a rejection, never a crash)
        return [f"json: {type(e).__name__}"]
    try:
        _check(doc, err)
    except Exception as e:  # noqa: BLE001
        return [f"malformed: {type(e).__name__}"]
    return errs
