"""R2, R1 plus owner-approved estimates (E3 disposition sections 4 and 5; plan decision 11).

Pure: parsed documents in, a document and counts out. The rules are in
docs/personal-food-database-r2-builder-v1.md section 3. R2 is R1 with `estimated_nutrients` on every
entry and `estimate_evidence` at the top; nothing else changes, which `check_additive` proves.
"""
import hashlib
import json
import re

from urllib.parse import urlsplit

import estimates_v1 as E
import export_v1

SCHEMA_COMPANION = "pfd-estimate-companion-v1"
ESTIMATE_KEYS = {"entry_id", "nutrient", "value", "unit", "basis", "evidence", "underlying_source", "origin"}
EVIDENCE_IN = E.EVIDENCE_KEYS - {"id", "entry_id", "nutrient"}
UNDERLYING = {"not_applicable", "stated_independent", "open_food_facts", "not_stated"}
ORIGINS = {"direct", "prior_release_resolved", "prior_release_unresolved", "recipe_estimate"}
ENTRY_ID = re.compile(r"pfc:[0-9a-f]{12}")
RELEASE_ID = re.compile(r"pfc:sha256:[0-9a-f]{64}")
WITHHELD = ("label_kept", "recipe_estimate", "prior_release_unresolved", "open_food_facts_source",
            "e3_withheld_value", "e3_withheld_source", "own_reference", "transform", "basis")


class R2Error(ValueError):
    """An input that cannot produce R2. Messages carry no title, entry ID or value."""


def release_id(data: bytes) -> str:
    return "pfc:sha256:" + hashlib.sha256(data).hexdigest()


def dumps(doc: dict) -> bytes:
    """The same serialisation as R1 (r1_export.dumps)."""
    return json.dumps(doc, indent=1, ensure_ascii=False).encode()


def evidence_id(entry_id: str, nutrient: str) -> str:
    return "pfe:" + hashlib.sha256(f"pfe-v1|{entry_id}|{nutrient}".encode()).hexdigest()[:16]


def _canonical(doc) -> bytes:
    return json.dumps(doc, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode() + b"\n"


# ---- pfd-estimate-companion-v1 -------------------------------------------------------------

def _validate_companion(doc, corpora=None):
    if not isinstance(doc, dict) or set(doc) != {"schema", "r1_release_id", "estimates"} \
            or doc["schema"] != SCHEMA_COMPANION:
        raise R2Error("companion: not a pfd-estimate-companion-v1 document")
    if not isinstance(doc["r1_release_id"], str) or not RELEASE_ID.fullmatch(doc["r1_release_id"]):
        raise R2Error("companion: invalid r1_release_id")
    if not isinstance(doc["estimates"], list):
        raise R2Error("companion: estimates must be a list")
    keys = []
    for n, est in enumerate(doc["estimates"]):
        where = f"companion: estimate {n}"
        if not isinstance(est, dict) or set(est) != ESTIMATE_KEYS:
            raise R2Error(f"{where}: fields must be exactly {sorted(ESTIMATE_KEYS)}")
        if not (isinstance(est["entry_id"], str) and ENTRY_ID.fullmatch(est["entry_id"])):
            raise R2Error(f"{where}: invalid entry_id")
        key = est["nutrient"]
        if not isinstance(key, str) or key not in export_v1.CANON_UNITS:
            raise R2Error(f"{where}: unknown nutrient")
        if not export_v1._num(est["value"]) or est["unit"] != export_v1.CANON_UNITS[key]:
            raise R2Error(f"{where}: value must be finite and non-negative, in the key's canonical unit")
        if est["basis"] not in export_v1.BASES:
            raise R2Error(f"{where}: invalid basis")
        if est["origin"] not in ORIGINS or est["underlying_source"] not in UNDERLYING:
            raise R2Error(f"{where}: origin or underlying_source outside its closed list")
        ev = est["evidence"]
        if not isinstance(ev, dict) or set(ev) != EVIDENCE_IN:
            raise R2Error(f"{where}: evidence fields must be the contract record without id, entry_id and nutrient")
        problems = []
        E.check_record({**ev, "id": "pfe:" + "0" * 16, "entry_id": est["entry_id"], "nutrient": key},
                       set(export_v1.GENERIC_SOURCES if corpora is None else corpora),
                       lambda code, _detail="": problems.append(code), where)
        # An Open Food Facts page is withheld by rule, not refused, so the count stays visible.
        problems = [p for p in problems if p != "open-food-facts-host"]
        if problems:
            raise R2Error(f"{where}: evidence fails {', '.join(sorted(set(problems)))}")
        if (ev["source_type"] == "aggregator") == (est["underlying_source"] == "not_applicable"):
            raise R2Error(f"{where}: underlying_source is not_applicable exactly when the source is not an aggregator")
        keys.append((est["entry_id"], key))
    if keys != sorted(set(keys)):
        raise R2Error("companion: estimates must be in ascending (entry_id, nutrient) order, each pair once")


def _no_constants(_token):
    raise R2Error("companion: NaN or Infinity")


def parse_companion(data: bytes, corpora=None) -> dict:
    """`corpora`, when given, is the set of generic corpora R1 declares; a national composition
    estimate naming another corpus refuses the companion."""
    if data[:3] == b"\xef\xbb\xbf":
        raise R2Error("companion: UTF-8 byte-order mark")
    try:
        doc = json.loads(data.decode("utf-8"), object_pairs_hook=export_v1._no_duplicate_keys,
                         parse_constant=_no_constants)
    except R2Error:
        raise
    except Exception:  # noqa: BLE001  (bad UTF-8, bad JSON or a repeated key)
        raise R2Error("companion: not valid UTF-8 JSON without repeated keys") from None
    _validate_companion(doc, corpora)
    if _canonical(doc) != data:
        raise R2Error("companion: not in canonical form")
    return doc


def build_companion(r1_id: str, estimates: list) -> bytes:
    doc = {"schema": SCHEMA_COMPANION, "r1_release_id": r1_id, "estimates": estimates}
    _validate_companion(doc)
    return _canonical(doc)


# ---- admission and assembly ----------------------------------------------------------------

def a1_dropped(item, pinned_item):
    """Keys whose pinned Open Food Facts label value R1 no longer has."""
    return {k for k, v in pinned_item["label_nutrients"].items()
            if v["source_kind"] == "exact_product_dataset" and k not in item["label_nutrients"]}


def _reason(est, item, pinned_item, listed_keys, entry_withheld):
    """The withheld reason for one estimate, or None to admit it (first rule wins)."""
    ev, key = est["evidence"], est["nutrient"]
    if key in item["label_nutrients"]:
        return "label_kept"
    if est["origin"] in ("recipe_estimate", "prior_release_unresolved"):
        return est["origin"]
    if open_food_facts(est):
        return "open_food_facts_source"
    # A value resolved from the prior (pinned) release on a key or entry E3 withheld may be the
    # withheld value itself, so it never comes back through this route (disposition section 4.1).
    if est["origin"] == "prior_release_resolved" and (
            entry_withheld or key in listed_keys
            or (key in pinned_item["label_nutrients"] and key not in item["label_nutrients"])):
        return "e3_withheld_value"
    if ev["source_type"] == "national_composition":
        named = (ev["composition_source"], ev["source_reference"])
        before, now = pinned_item["generic_reference"], item["generic_reference"]
        if before is not None and now is None and named == (before["source"], before["record_id"]):
            return "e3_withheld_source"
        if now is not None and named == (now["source"], now["record_id"]):
            return "own_reference"
    if ev["method"] == "derived" and not E.transform_matches(ev["derivation"], key, est["value"]):
        return "transform"
    if est["basis"] != item["basis"]:
        return "basis"
    return None


def open_food_facts(est) -> bool:
    ev = est["evidence"]
    return est["underlying_source"] == "open_food_facts" or (
        ev["source_type"] != "national_composition" and E.off_host(urlsplit(ev["source_reference"]).hostname))


def admitted(r1: dict, pinned: dict, companion: dict, listed: dict, withheld_entries) -> list:
    """The companion rows R2 admits, in companion order."""
    items = {it["id"]: it for it in r1["items"]}
    pinned_items = {it["id"]: it for it in pinned["items"]}
    withheld_entries = set(withheld_entries)
    return [est for est in companion["estimates"]
            if _reason(est, items[est["entry_id"]], pinned_items[est["entry_id"]],
                       listed.get(est["entry_id"], ()), est["entry_id"] in withheld_entries) is None]


def derive(r1: dict, pinned: dict, companion: dict, listed: dict, withheld_entries, groups: dict):
    """Returns (R2 document, counts). `listed` maps entry_id to the keys E3 withheld or left
    unresolved; `withheld_entries` are the entries E3 withheld; `groups` maps each inventory key to
    macro, micro or other. The caller checks every input's release ID."""
    items = {it["id"]: it for it in r1["items"]}
    pinned_items = {it["id"]: it for it in pinned["items"]}
    if list(items) != list(pinned_items):
        raise R2Error("R1 and the pinned release list different entries")
    if any(e["entry_id"] not in items for e in companion["estimates"]):
        raise R2Error("an estimate names an entry that is not in R1")
    withheld_entries = set(withheld_entries)

    counts = {"estimates_in_companion": len(companion["estimates"]), "companion_open_food_facts": 0,
              "estimates_admitted": 0}
    counts.update({f"withheld_{r}": 0 for r in WITHHELD})
    by = {"source_type": {}, "group": {}, "method": {}, "zero_by_source_type": {}}
    extra = {k: 0 for k in ("aggregator_underlying_not_stated", "indexed_copy_admitted",
                            "aggregator_or_indexed_copy_admitted", "admitted_on_withheld_entries",
                            "admitted_on_e3_listed_keys", "admitted_on_a1_dropped_keys")}
    added, evidence = {}, []
    for est in companion["estimates"]:
        eid, key, ev = est["entry_id"], est["nutrient"], est["evidence"]
        if open_food_facts(est):
            counts["companion_open_food_facts"] += 1
        why = _reason(est, items[eid], pinned_items[eid], listed.get(eid, ()), eid in withheld_entries)
        if why is not None:
            counts[f"withheld_{why}"] += 1
            continue
        rid = evidence_id(eid, key)
        added.setdefault(eid, {})[key] = {"value": est["value"], "unit": est["unit"], "evidence_id": rid}
        evidence.append({"id": rid, "entry_id": eid, "nutrient": key, **ev})
        counts["estimates_admitted"] += 1
        st = ev["source_type"]
        for name, val in (("source_type", st), ("group", groups.get(key, "other")), ("method", ev["method"])):
            by[name][val] = by[name].get(val, 0) + 1
        if est["value"] == 0:
            by["zero_by_source_type"][st] = by["zero_by_source_type"].get(st, 0) + 1
        extra["aggregator_underlying_not_stated"] += est["underlying_source"] == "not_stated"
        extra["indexed_copy_admitted"] += ev["page_access"] == "indexed_copy"
        extra["aggregator_or_indexed_copy_admitted"] += st == "aggregator" or ev["page_access"] == "indexed_copy"
        extra["admitted_on_withheld_entries"] += eid in withheld_entries
        extra["admitted_on_e3_listed_keys"] += key in listed.get(eid, ())
        extra["admitted_on_a1_dropped_keys"] += key in a1_dropped(items[eid], pinned_items[eid])

    out_items = []
    for it in r1["items"]:
        out_items.append({**it, "estimated_nutrients": dict(sorted(added.get(it["id"], {}).items()))})
    doc = {k: r1[k] for k in r1}
    doc["schema"] = E.SCHEMA
    doc["items"] = out_items
    doc["estimate_evidence"] = sorted(evidence, key=lambda r: r["id"])
    if len({r["id"] for r in evidence}) != len(evidence):
        raise R2Error("two estimates share an evidence ID")
    counts.update(extra)
    counts["entries"] = len(out_items)
    counts["entries_with_estimates"] = sum(bool(it["estimated_nutrients"]) for it in out_items)
    # R1's definition (no label value and no reference), so the two counts compare directly, and the
    # worklist: entries with no value shown, since a candidate reference is only offered, not merged.
    counts["entries_with_no_nutrition"] = sum(
        not it["label_nutrients"] and not it["estimated_nutrients"] and it["generic_reference"] is None
        for it in out_items)
    counts["entries_without_values"] = sum(
        not it["label_nutrients"] and not it["estimated_nutrients"]
        and (it["generic_reference"] is None or it["generic_reference"]["role"] != "merge") for it in out_items)
    for name, table in by.items():
        for val, n in sorted(table.items()):
            counts[f"admitted_by_{name}_{val}" if name != "zero_by_source_type" else f"zeros_{val}"] = n
    return doc, counts


def check_additive(r1: dict, r2: dict) -> list:
    """Proves R2 only adds estimates to R1. Returns rule codes, empty when it holds."""
    errs = []
    if list(r2) != list(r1) + ["estimate_evidence"]:
        return ["top-keys"]
    for k in r1:
        if k not in ("schema", "items") and _canonical(r1[k]) != _canonical(r2[k]):
            errs.append(f"top-changed: {k}")
    if r2["schema"] != E.SCHEMA:
        errs.append("schema")
    if [it["id"] for it in r1["items"]] != [it["id"] for it in r2["items"]]:
        return errs + ["entries-changed"]
    differ = 0
    for a, b in zip(r1["items"], r2["items"]):
        if list(b) != list(a) + ["estimated_nutrients"] or _canonical(a) != _canonical(
                {k: b[k] for k in b if k != "estimated_nutrients"}):
            differ += 1
    if differ:
        errs.append(f"entries-differ-outside-estimates: {differ}")
    with_estimates = {it["id"] for it in r2["items"] if it["estimated_nutrients"]}
    if any(r["entry_id"] not in with_estimates for r in r2["estimate_evidence"]):
        errs.append("evidence-outside-estimated-entries")
    return errs


def check_admitted(r2: dict, rows: list) -> list:
    """Proves R2's estimates are exactly the admitted companion rows: same values, units and
    evidence, nothing else. Returns rule codes, empty when it holds."""
    expected, records = {}, {}
    for est in rows:
        rid = evidence_id(est["entry_id"], est["nutrient"])
        expected[(est["entry_id"], est["nutrient"])] = {"value": est["value"], "unit": est["unit"], "evidence_id": rid}
        records[rid] = {"id": rid, "entry_id": est["entry_id"], "nutrient": est["nutrient"], **est["evidence"]}
    found = {(it["id"], k): v for it in r2["items"] for k, v in it["estimated_nutrients"].items()}
    errs = []
    if set(found) - set(expected):
        errs.append(f"estimate-not-admitted: {len(set(found) - set(expected))}")
    if set(expected) - set(found):
        errs.append(f"admitted-estimate-missing: {len(set(expected) - set(found))}")
    if any(_canonical(found[k]) != _canonical(expected[k]) for k in set(found) & set(expected)):
        errs.append("estimate-changed")
    got = {r.get("id"): r for r in r2["estimate_evidence"]}
    if set(got) != set(records) or any(_canonical(got[k]) != _canonical(records[k]) for k in records):
        errs.append("evidence-changed")
    return errs
