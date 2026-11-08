"""Versioned file formats for the personal food database evaluation. Pure: bytes in, data out.

Every parser refuses an unknown schema, key, token or answer kind. Error messages name the row,
column or field only, never the value, so a private title, ID or query never reaches a console.
"""
import csv
import hashlib
import io
import json
import re

NUTRIENTS = ("energy_consumed", "fat_total", "fat_saturated", "carbohydrates", "sugar", "fiber", "protein", "sodium")
STRATA = ("A1", "A2", "A3", "A4", "A5")
LABEL_STRATA = ("A1", "A5")
PRODUCT_TOKENS = {"right_product", "wrong_variant", "wrong_product", "skipped"}
NUTRIENT_TOKENS = {"agrees", "differs", "not_on_pack", "missing_in_entry"}
VERDICT_TOKENS = {
    "A2": {"same_food_same_state", "same_food_other_state", "different_food", "skipped"},
    "A3": {"sensible", "misleading_close", "misleading_other_state", "skipped"},
    "A4": {"nothing_suitable", "match_missed", "skipped"},
}
SHEET_SCHEMA = "pfd-review-sheet-v1"
SHEET_COLUMNS = ("schema", "row", "stratum", "reason", "entry_id", "title", "brand", "matched", "values",
                 "product", *NUTRIENTS, "verdict")
REASONS = {"census", "top30", "draw", "replacement"}
ENTRY_ID = re.compile(r"pfc:[0-9a-f]{12}")
RELEASE_ID = re.compile(r"pfc:sha256:[0-9a-f]{64}")
HEX64 = re.compile(r"[0-9a-f]{64}")
QUERY_ID = re.compile(r"q-[0-9]{4}")
GENERIC_SOURCES = {"cofid", "usda", "tfda"}
SETS = {"development", "held-out"}


class FormatError(ValueError):
    """A refused file. The message never contains a value from the file."""


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def release_id(export_bytes: bytes) -> str:
    return "pfc:sha256:" + sha256(export_bytes)


def _json(data: bytes, what: str):
    try:
        return json.loads(data.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError):
        raise FormatError(f"{what}: not valid UTF-8 JSON") from None


def _keys(obj, allowed, what, required=None):
    if not isinstance(obj, dict):
        raise FormatError(f"{what}: must be an object")
    if set(obj) - set(allowed):
        raise FormatError(f"{what}: unknown field")
    missing = set(required if required is not None else allowed) - set(obj)
    if missing:
        raise FormatError(f"{what}: missing field {sorted(missing)[0]}")


def dumps(obj) -> bytes:
    """Canonical JSON bytes: sorted keys, two-space indent, UTF-8, trailing newline."""
    return (json.dumps(obj, indent=2, sort_keys=True, ensure_ascii=False) + "\n").encode("utf-8")


# personal-food-catalogue-v1 (read only: the fields this tool needs)

def export_entries(export_bytes: bytes):
    doc = _json(export_bytes, "import file")
    if not isinstance(doc, dict) or doc.get("schema") != "personal-food-catalogue-v1" or not isinstance(doc.get("items"), list):
        raise FormatError("import file: not a personal-food-catalogue-v1 file")
    corpora = {c.get("source"): c.get("corpus_sha256") for c in doc.get("generic_corpora") or [] if isinstance(c, dict)}
    out = []
    for i, it in enumerate(doc["items"]):
        if not isinstance(it, dict) or not isinstance(it.get("id"), str) or not ENTRY_ID.fullmatch(it["id"]):
            raise FormatError(f"import file: item {i}: invalid id")
        out.append(it)
    if len({it["id"] for it in out}) != len(out):
        raise FormatError("import file: duplicate entry id")
    return out, corpora


# pfd-purchase-counts-v1

def parse_purchase_counts(data: bytes) -> dict:
    doc = _json(data, "purchase counts")
    _keys(doc, {"schema", "release_id", "counts"}, "purchase counts")
    if doc["schema"] != "pfd-purchase-counts-v1":
        raise FormatError("purchase counts: unknown schema")
    if not isinstance(doc["release_id"], str) or not RELEASE_ID.fullmatch(doc["release_id"]):
        raise FormatError("purchase counts: invalid release_id")
    counts = doc["counts"]
    if not isinstance(counts, dict):
        raise FormatError("purchase counts: counts must be an object")
    for n, (k, v) in enumerate(counts.items()):
        if not ENTRY_ID.fullmatch(k) or isinstance(v, bool) or not isinstance(v, int) or v < 0:
            raise FormatError(f"purchase counts: entry {n}: invalid id or count")
    return doc


# pfd-sample-v1

def parse_sample(data: bytes) -> dict:
    doc = _json(data, "sample")
    _keys(doc, {"schema", "release_id", "seed", "quotas", "entries", "replacements"}, "sample")
    if doc["schema"] != "pfd-sample-v1":
        raise FormatError("sample: unknown schema")
    if not RELEASE_ID.fullmatch(str(doc["release_id"])) or not isinstance(doc["seed"], int) or isinstance(doc["seed"], bool):
        raise FormatError("sample: invalid release_id or seed")
    for n, e in enumerate(doc["entries"]):
        _keys(e, {"entry_id", "stratum", "reason"}, f"sample: entry {n}")
        if not ENTRY_ID.fullmatch(str(e["entry_id"])) or e["stratum"] not in STRATA or e["reason"] not in REASONS - {"replacement"}:
            raise FormatError(f"sample: entry {n}: invalid value")
    if set(doc["replacements"]) - {"A2", "A3", "A4"} or set(doc["quotas"]) - set(STRATA):
        raise FormatError("sample: unknown stratum")
    return doc


# pfd-review-sheet-v1 (CSV, UTF-8, one header row)

def write_sheet(rows) -> bytes:
    buf = io.StringIO()
    w = csv.writer(buf, lineterminator="\n")
    w.writerow(SHEET_COLUMNS)
    for r in rows:
        w.writerow([r.get(c, "") for c in SHEET_COLUMNS])
    return buf.getvalue().encode("utf-8")


def parse_sheet(data: bytes):
    try:
        text = data.decode("utf-8-sig")
    except UnicodeDecodeError:
        raise FormatError("review sheet: not valid UTF-8") from None
    reader = csv.reader(io.StringIO(text))
    header = next(reader, None)
    if tuple(header or ()) != SHEET_COLUMNS:
        raise FormatError("review sheet: header does not match pfd-review-sheet-v1")
    rows = []
    for n, raw in enumerate(reader, start=2):
        if not any(cell.strip() for cell in raw):
            continue
        if len(raw) != len(SHEET_COLUMNS):
            raise FormatError(f"review sheet: line {n}: wrong number of columns")
        r = dict(zip(SHEET_COLUMNS, (c.strip() for c in raw)))
        if r["schema"] != SHEET_SCHEMA:
            raise FormatError(f"review sheet: line {n}: column schema: unknown schema")
        if not r["row"].isdigit() or int(r["row"]) != len(rows) + 1:
            raise FormatError(f"review sheet: line {n}: column row: rows must be numbered 1, 2, 3 in order")
        if r["stratum"] not in STRATA or r["reason"] not in REASONS or not ENTRY_ID.fullmatch(r["entry_id"]):
            raise FormatError(f"review sheet: line {n}: invalid stratum, reason or entry_id")
        if r["stratum"] in LABEL_STRATA:
            if r["verdict"]:
                raise FormatError(f"review sheet: line {n}: column verdict: must be empty for {r['stratum']}")
            if r["product"] and r["product"] not in PRODUCT_TOKENS:
                raise FormatError(f"review sheet: line {n}: column product: unknown token")
            for k in NUTRIENTS:
                if r[k] and r[k] not in NUTRIENT_TOKENS:
                    raise FormatError(f"review sheet: line {n}: column {k}: unknown token")
            filled = [k for k in NUTRIENTS if r[k]]
            if r["product"] == "skipped" and filled:
                raise FormatError(f"review sheet: line {n}: a skipped entry has nutrient verdicts")
            if r["product"] and r["product"] != "skipped" and len(filled) != len(NUTRIENTS):
                raise FormatError(f"review sheet: line {n}: every nutrient column needs a verdict")
            if not r["product"] and filled:
                raise FormatError(f"review sheet: line {n}: nutrient verdicts without a product verdict")
        else:
            if r["product"] or any(r[k] for k in NUTRIENTS):
                raise FormatError(f"review sheet: line {n}: label columns must be empty for {r['stratum']}")
            if r["verdict"] and r["verdict"] not in VERDICT_TOKENS[r["stratum"]]:
                raise FormatError(f"review sheet: line {n}: column verdict: unknown token")
        rows.append(r)
    return rows


# pfd-query-set-v1

def _generic_ref(g, what):
    _keys(g, {"source", "record_id"}, what)
    if g["source"] not in GENERIC_SOURCES or not isinstance(g["record_id"], str) or not g["record_id"]:
        raise FormatError(f"{what}: invalid generic record")
    return (g["source"], g["record_id"])


def parse_query_set(data: bytes) -> dict:
    doc = _json(data, "query set")
    _keys(doc, {"schema", "release_id", "set", "queries"}, "query set", required={"schema", "release_id", "queries"})
    if doc["schema"] != "pfd-query-set-v1":
        raise FormatError("query set: unknown schema")
    if not RELEASE_ID.fullmatch(str(doc["release_id"])) or ("set" in doc and doc["set"] not in SETS):
        raise FormatError("query set: invalid release_id or set")
    seen = set()
    for n, q in enumerate(doc["queries"]):
        what = f"query set: query {n}"
        _keys(q, {"query_id", "text", "negative", "answer"}, what)
        if not isinstance(q["query_id"], str) or not QUERY_ID.fullmatch(q["query_id"]) or q["query_id"] in seen:
            raise FormatError(f"{what}: invalid or duplicate query_id")
        seen.add(q["query_id"])
        if not isinstance(q["text"], str) or not q["text"].strip() or not isinstance(q["negative"], bool):
            raise FormatError(f"{what}: invalid text or negative flag")
        a = q["answer"]
        kind = a.get("kind") if isinstance(a, dict) else None
        if kind == "entry":
            _keys(a, {"kind", "entry_ids", "step"}, what)
            if not a["entry_ids"] or not all(isinstance(e, str) and ENTRY_ID.fullmatch(e) for e in a["entry_ids"]) \
                    or isinstance(a["step"], bool) or a["step"] not in (1, 2, 3):
                raise FormatError(f"{what}: invalid entry answer")
        elif kind == "generic":
            _keys(a, {"kind", "generic"}, what)
            if not a["generic"]:
                raise FormatError(f"{what}: a generic answer names at least one record")
            for g in a["generic"]:
                _generic_ref(g, what)
        elif kind == "none":
            _keys(a, {"kind"}, what)
        else:
            raise FormatError(f"{what}: unknown answer kind")
        if q["negative"] and kind != "none":
            raise FormatError(f"{what}: a negative query must have answer kind none")
    return doc


# pfd-ranking-output-v1

def parse_ranking(data: bytes) -> dict:
    doc = _json(data, "ranking output")
    _keys(doc, {"schema", "release_id", "set", "results"}, "ranking output")
    if doc["schema"] != "pfd-ranking-output-v1":
        raise FormatError("ranking output: unknown schema")
    if not RELEASE_ID.fullmatch(str(doc["release_id"])) or doc["set"] not in SETS:
        raise FormatError("ranking output: invalid release_id or set")
    seen = set()
    for n, r in enumerate(doc["results"]):
        what = f"ranking output: result {n}"
        _keys(r, {"query_id", "candidates"}, what)
        if not QUERY_ID.fullmatch(str(r["query_id"])) or r["query_id"] in seen or not isinstance(r["candidates"], list):
            raise FormatError(f"{what}: invalid or duplicate query_id")
        seen.add(r["query_id"])
        for m, c in enumerate(r["candidates"]):
            cw = f"{what}: candidate {m}"
            kind = c.get("kind") if isinstance(c, dict) else None
            if kind == "entry":
                _keys(c, {"kind", "entry_id", "step"}, cw)
                if not ENTRY_ID.fullmatch(str(c["entry_id"])) or isinstance(c["step"], bool) or c["step"] not in (1, 2, 3):
                    raise FormatError(f"{cw}: invalid entry candidate")
            elif kind == "generic":
                _keys(c, {"kind", "source", "record_id"}, cw)
                _generic_ref({"source": c["source"], "record_id": c["record_id"]}, cw)
            else:
                raise FormatError(f"{cw}: unknown candidate kind")
    return doc
