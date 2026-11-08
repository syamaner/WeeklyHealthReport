"""The owner's query template, its assembly into pfd-query-set-v1, and the owner-only lookup. Pure.

The owner fills in a CSV (one row per query) in a spreadsheet; `assemble` turns it into the unsplit
query set, checking every entry ID against the pinned import file and every generic record against the
pinned corpora. Errors name the row and column, never a cell's value, so they can be shared.

`lookup` is for the owner's own screen only: it lists the entries (or generic records) whose fields
contain every word typed, in alphabetical order and with no score, and says which fields matched, so
the owner chooses the expected answer and step themselves rather than accepting a ranking.
"""
import csv
import io
import re

import formats

TEMPLATE_COLUMNS = ("query", "negative", "answer", "entry_ids", "step", "generic")
ANSWERS = {"entry", "generic", "none"}
YES_NO = {"yes": True, "no": False}
STEPS = {"1": 1, "2": 2, "3": 3, "title": 1, "variety": 2, "concept": 3}
LOOKUP_LIMIT = 25


class QueryTemplateError(ValueError):
    pass


def template() -> bytes:
    out = io.StringIO()
    csv.writer(out, lineterminator="\n").writerow(TEMPLATE_COLUMNS)
    return out.getvalue().encode("utf-8")


def _norm(text: str) -> str:
    return " ".join(text.casefold().split())


def _split_cell(cell: str):
    return [p for p in re.split(r"[\s;,]+", cell.strip()) if p]


def _generic_cell(cell: str, row: int):
    refs = []
    for part in [p.strip() for p in cell.split(";") if p.strip()]:
        source, sep, record_id = part.partition("=")
        if not sep or source.strip() not in formats.GENERIC_SOURCES or not record_id.strip():
            raise QueryTemplateError(f"row {row}: generic must be source=record_id items separated by ;")
        refs.append({"source": source.strip(), "record_id": record_id.strip()})
    return refs


def assemble(template_bytes: bytes, release_id: str, entry_ids: set, generic_ids: dict) -> dict:
    """The unsplit query set. `entry_ids` is every ID in the pinned import file; `generic_ids` maps
    each pinned source to its record IDs. Query IDs follow row order: q-0001, q-0002 and so on."""
    try:
        text = template_bytes.decode("utf-8-sig")
    except UnicodeDecodeError:
        raise QueryTemplateError("the template must be saved as UTF-8 CSV")
    reader, rows = csv.reader(io.StringIO(text), strict=True), []
    try:
        for row in reader:
            rows.append(row)
    except csv.Error:
        # The line is the file's line (a quoted cell can span lines), so the owner can find it in an editor.
        raise QueryTemplateError(f"line {reader.line_num}: invalid CSV quoting or an oversized cell") from None
    if not rows or tuple(c.strip().casefold() for c in rows[0]) != TEMPLATE_COLUMNS:
        raise QueryTemplateError("the first row must be the template header: " + ",".join(TEMPLATE_COLUMNS))
    queries, seen = [], set()
    for n, raw in enumerate(rows[1:], start=2):
        if not any(c.strip() for c in raw):
            continue  # blank rows are allowed while filling in
        if len(raw) > len(TEMPLATE_COLUMNS):
            raise QueryTemplateError(f"row {n}: {len(raw)} cells; the header has {len(TEMPLATE_COLUMNS)} columns, "
                                     f"so a cell after generic must be removed")
        cell = dict(zip(TEMPLATE_COLUMNS, [c.strip() for c in raw] + [""] * (len(TEMPLATE_COLUMNS) - len(raw))))
        if not cell["query"]:
            raise QueryTemplateError(f"row {n}: query is empty")
        key = _norm(cell["query"])
        if key in seen:
            raise QueryTemplateError(f"row {n}: query: the same query appears on an earlier row")
        seen.add(key)
        negative = YES_NO.get(cell["negative"].casefold())
        if negative is None:
            raise QueryTemplateError(f"row {n}: negative must be yes or no")
        kind = cell["answer"].casefold()
        if kind not in ANSWERS:
            raise QueryTemplateError(f"row {n}: answer must be entry, generic or none")
        if negative and kind != "none":
            raise QueryTemplateError(f"row {n}: negative/answer: a negative query must have answer none")
        if kind == "entry":
            ids = _split_cell(cell["entry_ids"])
            if not ids or any(not formats.ENTRY_ID.fullmatch(i) for i in ids):
                raise QueryTemplateError(f"row {n}: entry_ids must list one or more pfc: entry IDs")
            if any(i not in entry_ids for i in ids):
                raise QueryTemplateError(f"row {n}: entry_ids: an entry ID is not in the pinned import file")
            step = STEPS.get(cell["step"].casefold())
            if step is None:
                raise QueryTemplateError(f"row {n}: step must be 1 (title), 2 (variety) or 3 (concept)")
            if cell["generic"]:
                raise QueryTemplateError(f"row {n}: an entry answer leaves generic empty")
            answer = {"kind": "entry", "entry_ids": list(dict.fromkeys(ids)), "step": step}
        elif kind == "generic":
            refs = _generic_cell(cell["generic"], n)
            if not refs:
                raise QueryTemplateError(f"row {n}: a generic answer names at least one source=record_id")
            if any(r["record_id"] not in generic_ids.get(r["source"], ()) for r in refs):
                raise QueryTemplateError(f"row {n}: generic: a generic record is not in the pinned corpora")
            if cell["entry_ids"] or cell["step"]:
                raise QueryTemplateError(f"row {n}: a generic answer leaves entry_ids and step empty")
            answer = {"kind": "generic", "generic": refs}
        else:
            if cell["entry_ids"] or cell["step"] or cell["generic"]:
                raise QueryTemplateError(f"row {n}: a none answer leaves entry_ids, step and generic empty")
            answer = {"kind": "none"}
        queries.append({"query_id": f"q-{len(queries) + 1:04d}", "text": raw[0], "negative": negative,
                        "answer": answer})
    if not queries:
        raise QueryTemplateError("the template has no queries")
    doc = {"schema": "pfd-query-set-v1", "release_id": release_id, "queries": queries}
    formats.parse_query_set(formats.dumps(doc))  # the scorer's own check, before anything is written
    return doc


def counts(doc: dict) -> dict:
    qs = doc["queries"]
    by_kind = {k: sum(q["answer"]["kind"] == k for q in qs) for k in sorted(ANSWERS)}
    return {"queries": len(qs), "negative": sum(q["negative"] for q in qs), **by_kind}


def _words(text: str):
    return [w for w in re.split(r"[^\w]+", text.casefold()) if w]


def _strings(value):
    if isinstance(value, str):
        return [value]
    if isinstance(value, list):
        return [v for v in value if isinstance(v, str)]
    return []


ENTRY_FIELDS = (("title", ("title", "titles", "aliases")), ("brand", ("brand",)), ("variety", ("variety",)), ("concept", ("concept",)))


def lookup_entries(entries, text: str, limit: int = LOOKUP_LIMIT):
    """(id, brand, title, matched) for every entry whose fields hold every typed word; alphabetical."""
    words = _words(text)
    if not words:
        return [], 0
    out = []
    for e in entries:
        groups = {name: set(_words(" ".join(s for f in fields for s in _strings(e.get(f))))) for name, fields in ENTRY_FIELDS}
        if all(any(w in g for g in groups.values()) for w in words):
            matched = [name for name, g in groups.items() if any(w in g for w in words)]
            out.append((e["id"], e.get("brand") or "", e.get("title") or "", matched))
    out.sort(key=lambda r: (_norm(r[2]), _norm(r[1]), r[0]))
    return out[:limit], len(out)


def lookup_generic(records: dict, text: str, aliases=None, limit: int = LOOKUP_LIMIT):
    """(source=record_id, name, preparation) for every pinned generic record whose name, or one of its
    search aliases, holds every word; alphabetical by name."""
    words = set(_words(text))
    if not words:
        return [], 0
    aliases = aliases or {}
    out = []
    for source, recs in records.items():
        for rid, (name, prep) in recs.items():
            names = [name, *aliases.get(source, {}).get(rid, ())]
            if any(words <= set(_words(n)) for n in names):
                out.append((f"{source}={rid}", name, prep))
    out.sort(key=lambda r: (_norm(r[1]), r[0]))
    return out[:limit], len(out)
