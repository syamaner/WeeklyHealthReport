"""Versioned v2 file formats for the Part A best-estimate review. Pure: bytes in, data out.

Design: docs/personal-food-database-review-v2-design.md (revision 2), sections 2.1 to 2.3.

- pfd-nutrient-inventory-v1: the declared inventory, three closed groups (macro 8, micro 26, other 5).
- pfd-review-sheet-v2: one row per initial sample entry; every cell holds a closed token; a blank
  cell is refused, never read as unresolved; the per-stratum combination table is enforced here.
- pfd-nutrient-evidence-v2: JSON Lines, one record per row and inventory key, strings only, no
  values, titles, URLs or record identifiers.

`check_bundle` applies the rules that need both files (coverage, stated assumptions, A4 match
records). Error messages name the line, row, column or field only, never a value, so a private
title or ID never reaches a console.
"""
import csv
import io
import json
import re

from formats import ENTRY_ID, STRATA, FormatError, dumps

# pfd-nutrient-inventory-v1

INVENTORY_SCHEMA = "pfd-nutrient-inventory-v1"
GROUPS = ("macro", "micro", "other")
GROUP_SIZES = {"macro": 8, "micro": 26, "other": 5}
KEY = re.compile(r"[a-z][a-z0-9_]*")


def parse_inventory(data: bytes) -> dict:
    """{"groups": {group: tuple of keys}, "keys": tuple of all keys, "group_of": {key: group}}."""
    try:
        doc = json.loads(data.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError):
        raise FormatError("inventory: not valid UTF-8 JSON") from None
    if not isinstance(doc, dict) or set(doc) != {"schema", "groups"} or doc["schema"] != INVENTORY_SCHEMA:
        raise FormatError("inventory: not a pfd-nutrient-inventory-v1 file")
    groups = doc["groups"]
    if not isinstance(groups, dict) or set(groups) != set(GROUPS):
        raise FormatError("inventory: groups must be exactly macro, micro and other")
    group_of = {}
    for g in GROUPS:
        keys = groups[g]
        if not isinstance(keys, list) or len(keys) != GROUP_SIZES[g]:
            raise FormatError(f"inventory: group {g} must list {GROUP_SIZES[g]} keys")
        for n, k in enumerate(keys):
            if not isinstance(k, str) or not KEY.fullmatch(k):
                raise FormatError(f"inventory: group {g}: key {n}: invalid key")
            if k in group_of:
                raise FormatError(f"inventory: group {g}: key {n}: listed twice")
            group_of[k] = g
    return {"groups": {g: tuple(groups[g]) for g in GROUPS},
            "keys": tuple(k for g in GROUPS for k in groups[g]), "group_of": group_of}


def write_inventory(inventory: dict) -> bytes:
    return dumps({"schema": INVENTORY_SCHEMA, "groups": {g: list(inventory["groups"][g]) for g in GROUPS}})


# pfd-review-sheet-v2 (CSV, UTF-8, one header row)

SHEET_SCHEMA = "pfd-review-sheet-v2"
SHEET_COLUMNS = ("schema", "row", "stratum", "reason", "entry_id", "identity", "state", "variety", "outcome")
CHECKS = ("identity", "state", "variety")
REASONS = {"census", "top30", "draw"}
CHECK_TOKENS = {
    "identity": {"same_food", "different_food", "unresolved"},
    "state": {"same_state", "compatible_with_stated_assumption", "different_state", "unresolved"},
    "variety": {"same_or_immaterial", "material_difference", "unresolved"},
}
PASS = {"identity": {"same_food"}, "state": {"same_state", "compatible_with_stated_assumption"},
        "variety": {"same_or_immaterial"}}
FAIL = {"identity": {"different_food"}, "state": {"different_state"}, "variety": {"material_difference"}}
OUTCOMES = {
    "A1": {"not_applicable"}, "A5": {"not_applicable"},
    "A2": {"merge_ok", "merge_failed", "unresolved"},
    "A3": {"sensible", "misleading_other_state", "misleading_close", "unresolved"},
    "A4": {"match_missed", "nothing_suitable", "unresolved"},
}
ROW = re.compile(r"[1-9][0-9]*")


def check_status(row: dict, check: str) -> str:
    """"pass", "fail" or "unresolved" for one check of a parsed row."""
    v = row[check]
    return "pass" if v in PASS[check] else "fail" if v in FAIL[check] else "unresolved"


def entry_status(row: dict) -> str:
    """Fail beats unresolved, unresolved beats pass."""
    got = {check_status(row, c) for c in CHECKS}
    return "fail" if "fail" in got else "unresolved" if "unresolved" in got else "pass"


def sheet_template(sample: dict):
    """The empty sheet rows: exactly sample["entries"], in sample order. Token cells are blank, so the
    template is refused by parse_sheet until the owner fills every cell."""
    return [{"schema": SHEET_SCHEMA, "row": str(n), "stratum": e["stratum"], "reason": e["reason"],
             "entry_id": e["entry_id"]} for n, e in enumerate(sample["entries"], start=1)]


def write_sheet(rows) -> bytes:
    buf = io.StringIO()
    w = csv.writer(buf, lineterminator="\n")
    w.writerow(SHEET_COLUMNS)
    for r in rows:
        w.writerow([r.get(c, "") for c in SHEET_COLUMNS])
    return buf.getvalue().encode("utf-8")


class _DuplicateKey(json.JSONDecodeError):
    pass


def _no_duplicate_keys(pairs):
    keys = [k for k, _ in pairs]
    if len(set(keys)) != len(keys):
        raise _DuplicateKey("duplicate key", "", 0)  # caught as invalid JSON; the value is never shown
    return dict(pairs)


def _combination(r: dict, where: str):
    """The section 2.2 table. Checks that need the sidecar are in check_bundle."""
    s, outcome = r["stratum"], r["outcome"]
    st = {c: check_status(r, c) for c in CHECKS}
    failing = "fail" in st.values()
    unresolved = "unresolved" in st.values()
    if outcome not in OUTCOMES[s]:
        raise FormatError(f"{where}: column outcome: not allowed for {s}")
    if s == "A2":
        if outcome == "merge_ok" and (failing or unresolved):
            raise FormatError(f"{where}: merge_ok needs all three checks to pass")
        if outcome == "merge_failed" and not failing:
            raise FormatError(f"{where}: merge_failed needs at least one failing check")
        if outcome == "unresolved" and (failing or not unresolved):
            raise FormatError(f"{where}: unresolved needs no failing check and at least one unresolved check")
    elif s == "A3":
        if outcome == "sensible" and r["identity"] == "different_food":
            raise FormatError(f"{where}: sensible is refused with identity different_food")
        if outcome == "misleading_other_state" and r["state"] != "different_state":
            raise FormatError(f"{where}: misleading_other_state needs state different_state")
        if outcome == "sensible" and unresolved:
            raise FormatError(f"{where}: sensible is refused while a check is unresolved")
        if outcome == "unresolved" and not unresolved:
            raise FormatError(f"{where}: unresolved needs at least one unresolved check")
        if outcome == "misleading_close" and r["identity"] != "different_food" and r["variety"] != "material_difference":
            raise FormatError(f"{where}: misleading_close needs identity different_food or variety material_difference")
        if outcome == "unresolved" and r["identity"] == "different_food":
            # a candidate for a different food is misleading whatever else is open
            raise FormatError(f"{where}: unresolved is refused with identity different_food")
    elif s == "A4":
        if outcome == "match_missed" and st != {c: "pass" for c in CHECKS}:
            raise FormatError(f"{where}: match_missed needs all three checks to pass for the named record")
        if outcome == "nothing_suitable" and any(r[c] != "unresolved" for c in CHECKS):
            raise FormatError(f"{where}: nothing_suitable needs all three checks unresolved")


def parse_sheet(data: bytes):
    try:
        text = data.decode("utf-8-sig")
    except UnicodeDecodeError:
        raise FormatError("review sheet v2: not valid UTF-8") from None
    reader = csv.reader(io.StringIO(text))
    try:
        header = next(reader, None)
        if tuple(header or ()) != SHEET_COLUMNS:
            raise FormatError("review sheet v2: header does not match pfd-review-sheet-v2")
        rows = []
        for n, raw in enumerate(reader, start=2):
            if not any(cell.strip() for cell in raw):
                continue
            where = f"review sheet v2: line {n}"
            if len(raw) != len(SHEET_COLUMNS):
                raise FormatError(f"{where}: wrong number of columns")
            r = dict(zip(SHEET_COLUMNS, (c.strip() for c in raw)))
            for c in SHEET_COLUMNS:
                if not r[c]:
                    raise FormatError(f"{where}: column {c}: blank cell")
            if r["schema"] != SHEET_SCHEMA:
                raise FormatError(f"{where}: column schema: unknown schema")
            if not ROW.fullmatch(r["row"]) or int(r["row"]) != len(rows) + 1:
                raise FormatError(f"{where}: column row: rows must be numbered 1, 2, 3 in order")
            if r["stratum"] not in STRATA:
                raise FormatError(f"{where}: column stratum: unknown stratum")
            if r["reason"] == "replacement":
                raise FormatError(f"{where}: column reason: replacement rows are not part of the v2 sheet")
            if r["reason"] not in REASONS:
                raise FormatError(f"{where}: column reason: unknown token")
            if not ENTRY_ID.fullmatch(r["entry_id"]):
                raise FormatError(f"{where}: column entry_id: invalid entry ID")
            for c in CHECKS:
                if r[c] not in CHECK_TOKENS[c]:
                    raise FormatError(f"{where}: column {c}: unknown token")
            _combination(r, where)
            rows.append(r)
    except csv.Error:
        raise FormatError("review sheet v2: malformed CSV") from None
    return rows


# pfd-nutrient-evidence-v2 (JSON Lines)

EVIDENCE_SCHEMA = "pfd-nutrient-evidence-v2"
EVIDENCE_FIELDS = ("schema", "row", "nutrient", "assessment", "source_kind", "state_basis", "method")
ERRORS = ("error_basis", "error_state", "error_transcription", "error_derivation", "error_source")
NOT_ASSESSED = ("unresolved", "missing", "missing_source_available", "present_unquantified", "candidate_only")
ASSESSMENTS = ("correct", *ERRORS, *NOT_ASSESSED, "match_available")
SOURCE_FIELDS = {
    "source_kind": {"pinned_release", "national_composition", "manufacturer_page", "aggregator", "owner_declaration"},
    "state_basis": {"source_states_it", "stated_assumption", "unknown"},
    "method": {"direct", "derived", "carried_from_same_food", "carried_from_similar_food"},
}
A4_KEY = "energy_consumed"
FULL_COVERAGE = ("A1", "A2", "A5")


def write_evidence(records) -> bytes:
    """Canonical JSON Lines: fields in declared order, no spaces, UTF-8, one newline per record."""
    return "".join(json.dumps({f: r[f] for f in EVIDENCE_FIELDS}, ensure_ascii=False, separators=(",", ":")) + "\n"
                   for r in records).encode("utf-8")


def parse_evidence(data: bytes, inventory: dict):
    try:
        text = data.decode("utf-8")
    except UnicodeDecodeError:
        raise FormatError("evidence: not valid UTF-8") from None
    lines = text.split("\n")
    if lines and lines[-1] == "":
        lines.pop()
    records, seen = [], set()
    for n, line in enumerate(lines, start=1):
        where = f"evidence: line {n}"
        if not line.strip():
            raise FormatError(f"{where}: blank line")
        try:
            rec = json.loads(line, object_pairs_hook=_no_duplicate_keys)
        except json.JSONDecodeError:
            raise FormatError(f"{where}: not valid JSON") from None
        if not isinstance(rec, dict):
            raise FormatError(f"{where}: must be an object")
        if set(rec) - set(EVIDENCE_FIELDS):
            raise FormatError(f"{where}: unknown field")
        for f in EVIDENCE_FIELDS:
            if f not in rec:
                raise FormatError(f"{where}: missing field {f}")
            if not isinstance(rec[f], str):
                raise FormatError(f"{where}: field {f}: must be a string")
        if rec["schema"] != EVIDENCE_SCHEMA:
            raise FormatError(f"{where}: field schema: unknown schema")
        if not ROW.fullmatch(rec["row"]):
            raise FormatError(f"{where}: field row: invalid row number")
        if rec["nutrient"] not in inventory["group_of"]:
            raise FormatError(f"{where}: field nutrient: not in the declared inventory")
        if rec["assessment"] not in ASSESSMENTS:
            raise FormatError(f"{where}: field assessment: unknown token")
        for f, tokens in SOURCE_FIELDS.items():
            if rec["assessment"] in NOT_ASSESSED:
                if rec[f] != "":
                    raise FormatError(f"{where}: field {f}: must be empty for this assessment")
            elif rec[f] not in tokens:
                raise FormatError(f"{where}: field {f}: unknown token")
        key = (rec["row"], rec["nutrient"])
        if key in seen:
            raise FormatError(f"{where}: duplicate record for row {rec['row']} and nutrient {rec['nutrient']}")
        seen.add(key)
        records.append(rec)
    return records


def supplied(rec: dict) -> bool:
    """A record for a value the row supplies (its source fields are filled)."""
    return rec["assessment"] not in NOT_ASSESSED


def check_bundle(rows, records, inventory):
    """Rules across the sheet and the sidecar; returns {row number: [records]} in file order."""
    by_row = {r["row"]: [] for r in rows}
    for n, rec in enumerate(records, start=1):
        if rec["row"] not in by_row:
            raise FormatError(f"evidence: line {n}: field row: no such sheet row")
        by_row[rec["row"]].append(rec)
    want = set(inventory["keys"])
    for r in rows:
        recs, s, where = by_row[r["row"]], r["stratum"], f"evidence: row {r['row']}"
        got = {rec["nutrient"] for rec in recs}
        if s in FULL_COVERAGE:
            if got != want:
                missing = sorted(want - got)
                raise FormatError(f"{where}: {s} needs one record for every inventory key"
                                  + (f"; missing {missing[0]}" if missing else ""))
            if any(rec["assessment"] == "match_available" for rec in recs):
                raise FormatError(f"{where}: match_available is for A4 rows only")
        elif s == "A3":
            if recs:
                raise FormatError(f"{where}: A3 rows carry no evidence records")
        elif s == "A4":
            if r["outcome"] == "match_missed":
                if len(recs) != 1 or recs[0]["nutrient"] != A4_KEY or recs[0]["assessment"] != "match_available":
                    raise FormatError(f"{where}: match_missed needs exactly one {A4_KEY} record of assessment match_available")
            elif recs:
                raise FormatError(f"{where}: an A4 row carries a record only when its outcome is match_missed")
        if r["state"] == "compatible_with_stated_assumption":
            values = [rec for rec in recs if supplied(rec)]
            if not values or any(rec["state_basis"] != "stated_assumption" for rec in values):
                raise FormatError(f"review sheet v2: row {r['row']}: column state: compatible_with_stated_assumption "
                                  "needs every supplied value to carry state_basis stated_assumption")
    return by_row
