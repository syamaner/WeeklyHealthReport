"""The accepted-estimates input of the skill writer, `pfc-accepted-estimates-v1`
(docs/personal-food-catalogue-estimates-v2-phase.md section 3.2; contract
docs/personal-food-catalogue-estimates-v2-proposal.md sections 2, 3.1, 3.3 and 4).

Pure: bytes and parsed documents in, documents and counts out. No file is read here; the bundled
records arrive through a `read_record(source, record_id)` callable that returns None when the record
cannot be read, or its facts:

    {"nutrients": {key: value in the key's canonical unit},   # quantified values only
     "preparation": "raw" | "cooked" | "unknown" | ...,
     "fortification": "fortified" | "unfortified" | "unknown" | None,   # None: the source never states it
     "per_100_g": True | False}

A national composition value always comes from that reader, never from the input (phase gate
invariant 2.3.4). Refusal messages carry no title, brand or value. `apply_estimates.py` is the only
caller that touches a workspace. The format is documented in references/accepted-estimates-format.md.
"""
import hashlib
import json
import re

import estimates_v2 as E
import export_v1

SCHEMA = "pfc-accepted-estimates-v1"
TOP_KEYS = {"schema", "catalogue_release_id", "rows"}
ROW_BASE = {"entry_id", "scope", "evidence", "underlying_source", "relation", "accepted"}
SCOPES = ("entry", "nutrient")
EVIDENCE_IN = E.EVIDENCE_KEYS - {"id", "entry_id", "nutrient"}
UNDERLYING = ("not_applicable", "stated_independent", "open_food_facts", "not_stated")
RELATIONS = ("same_food", "similar_food")
ACCEPTED_KEYS = {"sheet", "row"}
ENTRY_ID = re.compile(r"pfc:[0-9a-f]{12}")
RELEASE_ID = re.compile(r"pfc:sha256:[0-9a-f]{64}")
# Admission, first reason wins (phase gate section 3.2 item 4), in exactly this order.
REASONS = ("label_kept", "merged_kept", "composite", "open_food_facts_source", "refused_source",
           "readmission_class", "unquantified", "basis", "fortified_record", "state_contradiction", "transform",
           "codec")
# What a refusal-status callable may answer (estimate_counts.Lists.status).
CLEAR, REFUSED, CLASS, READMITTED = "clear", "refused", "class", "readmitted"
BOM = b"\xef\xbb\xbf"


class EstimatesRefused(ValueError):
    """An input that cannot be used. Messages carry no title, brand or value."""


def release_id(data: bytes) -> str:
    return "pfc:sha256:" + hashlib.sha256(data).hexdigest()


def dumps(doc: dict) -> bytes:
    """The serialisation `export_v1.main` writes, so the plain v2 file round-trips byte for byte."""
    return json.dumps(doc, indent=1, ensure_ascii=False).encode()


def canonical(doc) -> bytes:
    """Canonical JSON: sorted keys, no spaces, UTF-8, one trailing newline."""
    return json.dumps(doc, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode() + b"\n"


def evidence_id(entry_id: str, nutrient: str) -> str:
    """The R2 builder's derivation (r2_export.evidence_id)."""
    return "pfe:" + hashlib.sha256(f"pfe-v1|{entry_id}|{nutrient}".encode()).hexdigest()[:16]


def _no_constants(_token):
    raise EstimatesRefused("NaN or Infinity")


def parse_canonical(data, what: str):
    """Strict JSON in canonical form, or EstimatesRefused. Used by every private input format."""
    if not isinstance(data, bytes):
        raise EstimatesRefused(f"{what}: not bytes")
    if data[:3] == BOM:
        raise EstimatesRefused(f"{what}: UTF-8 byte-order mark")
    try:
        doc = json.loads(data.decode("utf-8"), object_pairs_hook=export_v1._no_duplicate_keys,
                         parse_constant=_no_constants)
        same = canonical(doc) == data
    except Exception:  # noqa: BLE001  (bad UTF-8, bad JSON, a repeated key, NaN, a lone surrogate)
        raise EstimatesRefused(f"{what}: not valid UTF-8 JSON without repeated keys") from None
    if not same:
        raise EstimatesRefused(f"{what}: not in canonical form")
    return doc


def guarded(what: str, fn, *args):
    """Runs a field validator so that a value of an unexpected JSON type is a refusal, never a crash."""
    try:
        return fn(*args)
    except EstimatesRefused:
        raise
    except Exception:  # noqa: BLE001
        raise EstimatesRefused(f"{what}: a field has a value of the wrong type") from None


# ---- pfc-accepted-estimates-v1 -----------------------------------------------------------------

def _refuse(where, text):
    raise EstimatesRefused(f"accepted estimates: {where}: {text}")


def _validate_fields(doc):
    if not isinstance(doc, dict) or set(doc) != TOP_KEYS or doc["schema"] != SCHEMA:
        raise EstimatesRefused(f"accepted estimates: not a {SCHEMA} document")
    if not isinstance(doc["catalogue_release_id"], str) or not RELEASE_ID.fullmatch(doc["catalogue_release_id"]):
        raise EstimatesRefused("accepted estimates: invalid catalogue_release_id")
    if not isinstance(doc["rows"], list):
        raise EstimatesRefused("accepted estimates: rows must be a list")
    keys = []
    for n, row in enumerate(doc["rows"]):
        where = f"row {n}"
        if not isinstance(row, dict) or not ROW_BASE <= set(row):
            _refuse(where, "missing fields")
        scope, ev = row["scope"], row["evidence"]
        if not isinstance(scope, str) or scope not in SCOPES:
            _refuse(where, "scope must be entry or nutrient")
        if not isinstance(ev, dict) or set(ev) != EVIDENCE_IN:
            _refuse(where, "evidence fields must be the contract record without id, entry_id and nutrient")
        national = ev["source_type"] == "national_composition"
        if national and {"value", "unit"} & set(row):
            _refuse(where, "a national composition row never carries a typed value")
        if scope == "entry" and not national:
            _refuse(where, "whole-entry scope is national composition only")
        expected = ROW_BASE | ({"nutrient"} if scope == "nutrient" else set()) \
            | (set() if national else {"value", "unit"})
        if set(row) != expected:
            _refuse(where, f"fields must be exactly {sorted(expected)}")
        if not (isinstance(row["entry_id"], str) and ENTRY_ID.fullmatch(row["entry_id"])):
            _refuse(where, "invalid entry_id")
        key = row.get("nutrient", "")
        if scope == "nutrient" and (not isinstance(key, str) or key not in export_v1.CANON_UNITS):
            _refuse(where, "unknown nutrient")
        if not national and (not export_v1._num(row["value"]) or row["unit"] != export_v1.CANON_UNITS[key]):
            _refuse(where, "a page value must be finite and non-negative, in the key's canonical unit")
        if not isinstance(row["underlying_source"], str) or row["underlying_source"] not in UNDERLYING \
                or not isinstance(row["relation"], str) or row["relation"] not in RELATIONS:
            _refuse(where, "underlying_source or relation outside its closed list")
        acc = row["accepted"]
        if not isinstance(acc, dict) or set(acc) != ACCEPTED_KEYS or not E.text_ok(acc["sheet"], 200) \
                or isinstance(acc["row"], bool) or not isinstance(acc["row"], int) or acc["row"] < 1:
            _refuse(where, "accepted must be {sheet, row} naming one review sheet row")
        problems = []
        E.check_record({**ev, "id": "pfe:" + "0" * 16, "entry_id": row["entry_id"], "nutrient": key},
                       set(export_v1.GENERIC_SOURCES), lambda code, _detail="": problems.append(code), where)
        # An Open Food Facts page is withheld by rule at admission, not refused, so its count stays visible.
        problems = sorted(set(problems) - {"open-food-facts-host"})
        if problems:
            _refuse(where, f"evidence fails {', '.join(problems)}")
        if national and ev["method"] == "derived":
            _refuse(where, "a national composition row is never derived: its value is the bundled record's")
        if (ev["source_type"] == "aggregator") == (row["underlying_source"] == "not_applicable"):
            _refuse(where, "underlying_source is not_applicable exactly when the source is not an aggregator")
        if (row["relation"] == "similar_food") != (ev["method"] == "carried_from_similar_food"):
            _refuse(where, "relation and method disagree")
        keys.append((row["entry_id"], key))
    if keys != sorted(set(keys)):
        raise EstimatesRefused("accepted estimates: rows must be in ascending (entry_id, nutrient) order, "
                               "a whole-entry row first, each pair once")


def validate(doc):
    guarded("accepted estimates", _validate_fields, doc)
    return doc


def parse(data) -> dict:
    return validate(parse_canonical(data, "accepted estimates"))


def build(catalogue_release_id: str, rows: list) -> bytes:
    """The canonical bytes of an input document, validated."""
    return canonical(validate({"schema": SCHEMA, "catalogue_release_id": catalogue_release_id, "rows": rows}))


# ---- expansion, admission and assembly ---------------------------------------------------------

def _facts(read_record, source, record_id):
    facts = read_record(source, record_id)
    return facts if isinstance(facts, dict) and isinstance(facts.get("nutrients"), dict) else None


def _quantified(facts, key):
    """The record's value for the key in its canonical unit, or None: unknown is never zero."""
    value = facts["nutrients"].get(key) if facts else None
    return value if export_v1._num(value) else None


def _items(doc):
    return {it["id"]: it for it in doc["items"]}


def expand(doc: dict, accepted: dict, read_record):
    """One estimate for each (entry, nutrient) the rows cover (section 3.2 items 2 and 3). A
    whole-entry row gives one for each nutrient its record quantifies, never for a key the entry
    already has on its label and never for a key a nutrient-scope row of the same entry names. A
    national composition value is the record's, or None when the record does not quantify it.
    Returns (estimates in (entry_id, nutrient) order, counts)."""
    items = _items(doc)
    if any(row["entry_id"] not in items for row in accepted["rows"]):
        raise EstimatesRefused("accepted estimates: a row names an entry that is not in the catalogue file")
    named = {(row["entry_id"], row["nutrient"]) for row in accepted["rows"] if row["scope"] == "nutrient"}
    counts = {"rows": len(accepted["rows"]), "rows_entry_scope": 0, "rows_nutrient_scope": 0,
              "entry_rows_record_unreadable": 0, "expansion_skipped_label": 0, "expansion_skipped_nutrient_row": 0}
    out = []
    for n, row in enumerate(accepted["rows"]):
        ev, eid = row["evidence"], row["entry_id"]
        carried = {"entry_id": eid, "evidence": ev, "underlying_source": row["underlying_source"],
                   "relation": row["relation"], "accepted": row["accepted"], "scope": row["scope"], "row": n}
        counts[f"rows_{row['scope']}_scope"] += 1
        if ev["source_type"] != "national_composition":
            out.append({**carried, "nutrient": row["nutrient"], "value": row["value"], "unit": row["unit"]})
            continue
        facts = _facts(read_record, ev["composition_source"], ev["source_reference"])
        if row["scope"] == "nutrient":
            key = row["nutrient"]
            out.append({**carried, "nutrient": key, "value": _quantified(facts, key),
                        "unit": export_v1.CANON_UNITS[key]})
            continue
        if facts is None:
            counts["entry_rows_record_unreadable"] += 1
            continue
        for key in sorted(k for k in facts["nutrients"] if isinstance(k, str) and k in export_v1.CANON_UNITS):
            value = _quantified(facts, key)
            if value is None:
                continue
            if key in items[eid]["label_nutrients"]:
                counts["expansion_skipped_label"] += 1
            elif (eid, key) in named:
                counts["expansion_skipped_nutrient_row"] += 1
            else:
                out.append({**carried, "nutrient": key, "value": value, "unit": export_v1.CANON_UNITS[key]})
    out.sort(key=lambda est: (est["entry_id"], est["nutrient"]))
    counts["estimates"] = len(out)
    return out, counts


def open_food_facts(est) -> bool:
    ev = est["evidence"]
    return est["underlying_source"] == "open_food_facts" or (
        ev["source_type"] != "national_composition" and E.off_host(E.page_host(ev["source_reference"])))


def record_for(est) -> dict:
    """The evidence record the file would carry for one estimate."""
    return {"id": evidence_id(est["entry_id"], est["nutrient"]), "entry_id": est["entry_id"],
            "nutrient": est["nutrient"], **est["evidence"]}


def codec_codes(est, item, corpora) -> list:
    """The codec codes the row would raise against its entry: the inherited record checks with the
    file's own corpora, then the table of contract section 3.1."""
    rec, problems = record_for(est), []
    E.check_record(rec, set(corpora), lambda code, _detail="": problems.append(code), "")
    return sorted(set(problems)) if problems else E.table_codes(rec, item)


def merges(item, facts) -> bool:
    """Whether the app merges this entry's `merge` record, as `PersonalFoodDatabaseCandidateBuilder
    .mergeEligible` decides it: a raw or cooked entry per 100 g, and a record whose preparation is
    the entry's, per 100 g (every adapter then states a 100 g edible quantity) and not fortified.
    When the app would not merge, the key stays unknown there, so an accepted estimate may fill it."""
    return (facts is not None and item["state"] in ("raw", "cooked") and item["basis"] == "per_100_g"
            and facts.get("preparation") == item["state"] and facts.get("per_100_g") is True
            and facts.get("fortification") != "fortified")


def reason(est, item, corpora, read_record, refusal_status):
    """(the withheld reason or None to admit, the codec codes when the reason is `codec`)."""
    ev, key = est["evidence"], est["nutrient"]
    national = ev["source_type"] == "national_composition"
    if key in item["label_nutrients"]:
        return "label_kept", []
    ref = item["generic_reference"]
    if ref is not None and ref["role"] == "merge":
        merged = _facts(read_record, ref["source"], ref["record_id"])
        if merges(item, merged) and _quantified(merged, key) is not None:
            return "merged_kept", []
    if national and item["product_type"] == "packaged_composite":
        return "composite", []
    if open_food_facts(est):
        return "open_food_facts_source", []
    status = refusal_status(est["entry_id"], key, ev, corpora.get(ev["composition_source"]) if national else None)
    if status == CLASS:
        return "readmission_class", []
    if status not in (CLEAR, READMITTED):
        return "refused_source", []
    if national:
        facts = _facts(read_record, ev["composition_source"], ev["source_reference"])
        if est["value"] is None or _quantified(facts, key) is None:
            return "unquantified", []
        # No density is ever inferred: a record is per 100 g, so only a per 100 g entry takes it.
        if item["basis"] != "per_100_g" or facts.get("per_100_g") is False:
            return "basis", []
        # What the app's importer rejects with `estimate-contradiction` where the bundled data shows
        # it (contract section 3.1): a fortified record, and a raw or cooked entry against a record
        # whose stated preparation differs. Unknown never contradicts. Withheld here and counted, so
        # one such row never makes the phone refuse the whole file.
        if facts.get("fortification") == "fortified":
            return "fortified_record", []
        if item["state"] in ("raw", "cooked") and facts.get("preparation") not in (None, "unknown", item["state"]):
            return "state_contradiction", []
    if ev["method"] == "derived" and not E.transform_matches(ev["derivation"], key, est["value"]):
        return "transform", []
    codes = codec_codes(est, item, corpora)
    return ("codec", codes) if codes else (None, [])


def admit(doc: dict, estimates: list, read_record, refusal_status=None):
    """Returns (admitted estimates, counts). No reason is fatal; each is counted. `refusal_status`
    is `estimate_counts.Lists.status`; without it nothing is on a refusal list."""
    refusal_status = refusal_status or (lambda *_: CLEAR)
    items = _items(doc)
    corpora = {c["source"]: c["corpus_sha256"] for c in doc["generic_corpora"]}
    counts = {"admitted": 0, "admitted_readmitted": 0, **{f"withheld_{r}": 0 for r in REASONS}}
    admitted = []
    for est in estimates:
        why, codes = reason(est, items[est["entry_id"]], corpora, read_record, refusal_status)
        if why is None:
            admitted.append(est)
            counts["admitted"] += 1
            ev = est["evidence"]
            national = ev["source_type"] == "national_composition"
            counts["admitted_readmitted"] += refusal_status(
                est["entry_id"], est["nutrient"], ev,
                corpora.get(ev["composition_source"]) if national else None) == READMITTED
            continue
        counts[f"withheld_{why}"] += 1
        for code in codes:
            counts[f"codec_{code}"] = counts.get(f"codec_{code}", 0) + 1
    return admitted, counts


def assemble(doc: dict, admitted: list) -> dict:
    """The estimates v2 document (section 3.2 item 6): the plain v2 document with the schema
    string changed, `estimated_nutrients` (sorted by key, possibly empty) as every entry's last key
    and `estimate_evidence` (sorted by id) as the last top-level key."""
    added, evidence = {}, []
    for est in admitted:
        rec = record_for(est)
        added.setdefault(est["entry_id"], {})[est["nutrient"]] = {
            "value": est["value"], "unit": est["unit"], "evidence_id": rec["id"]}
        evidence.append(rec)
    if len({r["id"] for r in evidence}) != len(evidence):
        raise EstimatesRefused("two estimates share an evidence ID")
    out = {k: doc[k] for k in doc}
    out["schema"] = export_v1.SCHEMA_ESTIMATES_V2
    out["items"] = [{**it, "estimated_nutrients": dict(sorted(added.get(it["id"], {}).items()))}
                    for it in doc["items"]]
    out["estimate_evidence"] = sorted(evidence, key=lambda r: r["id"])
    return out


def output_bytes(plain: bytes, doc: dict, admitted: list) -> bytes:
    """What the catalogue is after admission: the plain v2 bytes themselves, untouched, when no
    estimate is admitted (invariant 2.3.3), otherwise the estimates v2 file."""
    return dumps(assemble(doc, admitted)) if admitted else plain


def check_additive(plain: dict, out: dict) -> list:
    """Proves the estimates document only adds estimates to the plain v2 document. Returns rule
    codes, empty when it holds; never raises."""
    try:
        return _check_additive(plain, out)
    except Exception as e:  # noqa: BLE001
        return [f"malformed: {type(e).__name__}"]


def _check_additive(plain, out):
    errs = []
    if list(out) != list(plain) + ["estimate_evidence"]:
        return ["top-keys"]
    for k in plain:
        if k not in ("schema", "items") and canonical(plain[k]) != canonical(out[k]):
            errs.append(f"top-changed: {k}")
    if plain["schema"] != export_v1.SCHEMA_V2 or out["schema"] != export_v1.SCHEMA_ESTIMATES_V2:
        errs.append("schema")
    if [it["id"] for it in plain["items"]] != [it["id"] for it in out["items"]]:
        return errs + ["entries-changed"]
    differ = sum(list(b) != list(a) + ["estimated_nutrients"]
                 or canonical(a) != canonical({k: b[k] for k in b if k != "estimated_nutrients"})
                 for a, b in zip(plain["items"], out["items"]))
    if differ:
        errs.append(f"entries-differ-outside-estimates: {differ}")
    with_estimates = {it["id"] for it in out["items"] if it["estimated_nutrients"]}
    if any(r["entry_id"] not in with_estimates for r in out["estimate_evidence"]):
        errs.append("evidence-outside-estimated-entries")
    return errs


def check_admitted(out: dict, admitted: list) -> list:
    """Proves the document's estimates are exactly the admitted ones: same values, units and
    evidence, nothing else. Returns rule codes, empty when it holds; never raises."""
    try:
        expected, records = {}, {}
        for est in admitted:
            rec = record_for(est)
            expected[(est["entry_id"], est["nutrient"])] = {"value": est["value"], "unit": est["unit"],
                                                            "evidence_id": rec["id"]}
            records[rec["id"]] = rec
        found = {(it["id"], k): v for it in out["items"] for k, v in it["estimated_nutrients"].items()}
        errs = []
        if set(found) - set(expected):
            errs.append(f"estimate-not-admitted: {len(set(found) - set(expected))}")
        if set(expected) - set(found):
            errs.append(f"admitted-estimate-missing: {len(set(expected) - set(found))}")
        if any(canonical(found[k]) != canonical(expected[k]) for k in set(found) & set(expected)):
            errs.append("estimate-changed")
        got = {r.get("id"): r for r in out["estimate_evidence"]}
        if set(got) != set(records) or any(canonical(got[k]) != canonical(records[k]) for k in records):
            errs.append("evidence-changed")
        return errs
    except Exception as e:  # noqa: BLE001
        return [f"malformed: {type(e).__name__}"]


REPORT_KEYS = ("checked_against_bundled_record", "record_preparation_unknown", "source_never_states_fortification",
               "cites_fortified_record", "raw_record_on_non_raw_entry", "aggregator_underlying_not_stated",
               "indexed_copy", "entries_with_estimates")


def change_report(doc: dict, admitted: list, read_record) -> dict:
    """Counts only (contract section 3.1; phase gate section 3.2 item 7). Nothing here names a food.

    `checked_against_bundled_record` is how many estimates the app importer will look up in its
    bundled corpus (the four value codes and `estimate-contradiction`, which Python does not mirror).
    `record_preparation_unknown`, `source_never_states_fortification` and `raw_record_on_non_raw_entry`
    are the limits the contract asks to keep visible; `cites_fortified_record` counts estimates the
    importer would reject as a contradiction."""
    items = _items(doc)
    counts = {k: 0 for k in REPORT_KEYS}

    def add(name):
        counts[name] = counts.get(name, 0) + 1

    for est in admitted:
        ev = est["evidence"]
        st = ev["source_type"]
        add(f"admitted_by_source_type_{st}")
        add(f"admitted_by_method_{ev['method']}")
        add(f"admitted_by_quality_{ev['quality']}")
        if est["value"] == 0:
            add(f"zeros_{st}")
        if st != "national_composition":
            counts["aggregator_underlying_not_stated"] += est["underlying_source"] == "not_stated"
            counts["indexed_copy"] += ev["page_access"] == "indexed_copy"
            continue
        add("checked_against_bundled_record")
        add(f"national_by_composition_source_{ev['composition_source']}")
        facts = _facts(read_record, ev["composition_source"], ev["source_reference"]) or {}
        preparation = facts.get("preparation")
        counts["record_preparation_unknown"] += preparation in (None, "unknown")
        counts["source_never_states_fortification"] += facts.get("fortification") is None
        counts["cites_fortified_record"] += facts.get("fortification") == "fortified"
        counts["raw_record_on_non_raw_entry"] += preparation == "raw" and items[est["entry_id"]]["state"] != "raw"
    counts["entries_with_estimates"] = len({est["entry_id"] for est in admitted})
    return dict(sorted(counts.items()))
