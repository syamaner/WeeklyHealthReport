"""Stratum assignment, the seeded Part A sample and the review sheet rows. Pure.

Seeded order never depends on the Python version: entries are ordered by SHA-256 of
"<seed>|<entry id>", then by id.
"""
import hashlib

from formats import NUTRIENTS, FormatError

QUOTAS = {"A2": 40, "A3": 40, "A4": 20}
TOP = 30


def seeded_order(seed: int, ids):
    return sorted(ids, key=lambda i: (hashlib.sha256(f"{seed}|{i}".encode()).hexdigest(), i))


def stratum(entry) -> str:
    """A5 > A1 > A2 > A3 > A4 (plan section 3.1)."""
    kinds = {v.get("source_kind") for v in (entry.get("label_nutrients") or {}).values() if isinstance(v, dict)}
    if "manual_declaration" in kinds:
        return "A5"
    if "exact_product_dataset" in kinds:
        return "A1"
    ref = entry.get("generic_reference") or {}
    if ref.get("role") == "merge":
        return "A2"
    if ref.get("role") == "candidate":
        return "A3"
    return "A4"


def top_entries(counts: dict, ids, top: int = TOP):
    """The most-bought entries: count descending, then id; entries with no purchases never count."""
    ranked = sorted((i for i in ids if counts.get(i, 0) > 0), key=lambda i: (-counts[i], i))
    return ranked[:top]


def draw(entries, counts: dict, seed: int):
    """The sample as pfd-sample-v1 fields (without schema and release_id)."""
    by_stratum = {}
    for e in entries:
        by_stratum.setdefault(stratum(e), []).append(e["id"])
    top = set(top_entries(counts, [e["id"] for e in entries]))
    chosen, replacements, quotas = [], {}, {}
    for s in ("A1", "A5"):
        ids = sorted(by_stratum.get(s, []))
        quotas[s] = len(ids)
        chosen += [{"entry_id": i, "stratum": s, "reason": "top30" if i in top else "census"} for i in ids]
    for s, base in QUOTAS.items():
        ids = by_stratum.get(s, [])
        fixed = sorted(i for i in ids if i in top)
        quota = min(len(ids), max(base, len(fixed)))
        rest = seeded_order(seed, [i for i in ids if i not in top])
        picked = rest[:max(0, quota - len(fixed))]
        quotas[s] = quota
        chosen += [{"entry_id": i, "stratum": s, "reason": "top30"} for i in fixed]
        chosen += [{"entry_id": i, "stratum": s, "reason": "draw"} for i in picked]
        replacements[s] = rest[len(picked):]
    return {"seed": seed, "quotas": quotas, "entries": chosen, "replacements": replacements}


def _matched(entry, corpora_records):
    ref = entry.get("generic_reference")
    if not ref:
        return ""
    rec = corpora_records.get(ref["source"], {}).get(ref["record_id"])
    if rec is None:
        raise FormatError("sheet: a generic reference names a record that is not in the bundled corpus")
    name, state = rec
    return f"{ref['source']}: {name} ({state}; {ref['match']}; {ref['role']})"


def _values(entry):
    lab = entry.get("label_nutrients") or {}
    return "; ".join(f"{k} {lab[k]['value']} {lab[k]['unit']}" for k in NUTRIENTS if k in lab)


def sheet_rows(sample, entries, corpora_records):
    """Rows for pfd-review-sheet-v1: the sample in order, then each stratum's replacement order."""
    by_id = {e["id"]: e for e in entries}
    plan = [(e["entry_id"], e["stratum"], e["reason"]) for e in sample["entries"]]
    for s in ("A2", "A3", "A4"):
        plan += [(i, s, "replacement") for i in sample["replacements"].get(s, [])]
    rows = []
    for n, (i, s, reason) in enumerate(plan, start=1):
        e = by_id[i]
        rows.append({"schema": "pfd-review-sheet-v1", "row": n, "stratum": s, "reason": reason, "entry_id": i,
                     "title": e.get("title") or "", "brand": e.get("brand") or "",
                     "matched": _matched(e, corpora_records), "values": _values(e)})
    return rows
