"""R1, the drops-only export of the pinned release (E3 disposition D1 and D2; plan decision 10).

Pure: bytes and parsed documents in, bytes and counts out. R1 is derived from the pinned
`personal-food-catalogue-v1` file by removal only, never rebuilt from working files, so every
entry, field and value it keeps is byte-for-byte what the pinned release held:

- `withhold_entries` (pfd-exclusions-v1): the entry keeps no label value and no reference.
- `withhold_values` (pfd-exclusions-v1) and the unresolved values (pfd-unresolved-v1, every
  stratum: unresolved is never a pass): the value is removed. A listed key must be in the frozen
  nutrient inventory. When it is not a label value of the entry, the reviewed value came from the
  entry's generic reference, so that reference is removed instead, whether `merge` or `candidate`
  (a known error or an unresolved value is never offered through a reference). A listed key on an
  entry with neither is refused.
- `reference_candidates` (pfd-exclusions-v1): a merge reference becomes `candidate`.
- Switch `a1`: every Open Food Facts label value (`exact_product_dataset`) is removed.
- Switch `a2`: every merge reference becomes `candidate`.

No merge is ever created, so a merge that only removing values would make eligible stays a
candidate. Sources no longer cited by any value are removed; `generated` and `generic_corpora`
are unchanged. `check_drops_only` proves the output only removes; `check_applied` proves every
required removal happened.

When any label value is removed (withheld, unresolved or by `a1`), the entry's `merge` reference
becomes a `candidate`, so the merged record never silently supplies those nutrients in their
place: the plan says a reference is never a new merge after label values are removed, including
references attached to A1 entries (section 6). Entries keep
their pinned `basis`, which the merge condition already met when the pinned file was built.
"""
import hashlib
import json
import re

SCHEMA_UNRESOLVED = "pfd-unresolved-v1"
ENTRY_ID = re.compile(r"pfc:[0-9a-f]{12}")
RELEASE_ID = re.compile(r"pfc:sha256:[0-9a-f]{64}")
NUTRIENT = re.compile(r"[a-z][a-z0-9_]*")
OFF_KIND = "exact_product_dataset"
SWITCHES = ("a1", "a2")


class R1Error(ValueError):
    """An input that cannot produce a drops-only R1. Messages carry no title, entry ID or value."""


def release_id(data: bytes) -> str:
    return "pfc:sha256:" + hashlib.sha256(data).hexdigest()


def dumps(doc: dict) -> bytes:
    """The export's own serialisation (export_v1.main)."""
    return json.dumps(doc, indent=1, ensure_ascii=False).encode()


# pfd-unresolved-v1: {"schema", "release_id", "withhold_values": [{"entry_id", "nutrient"}]}

def unresolved_list(rows, by_row) -> list:
    """Every value assessed `unresolved`, from the frozen review v2 parsers' output
    (score_a_v2.validate). Sorted, each (entry, nutrient) once."""
    out = set()
    for r in rows:
        for rec in by_row[r["row"]]:
            if rec["assessment"] == "unresolved":
                out.add((r["entry_id"], rec["nutrient"]))
    return [{"entry_id": e, "nutrient": n} for e, n in sorted(out)]


def _validate_unresolved(doc):
    if not isinstance(doc, dict) or set(doc) != {"schema", "release_id", "withhold_values"} \
            or doc["schema"] != SCHEMA_UNRESOLVED:
        raise R1Error("unresolved: not a pfd-unresolved-v1 document")
    if not isinstance(doc["release_id"], str) or not RELEASE_ID.fullmatch(doc["release_id"]):
        raise R1Error("unresolved: invalid release_id")
    vals, seen = doc["withhold_values"], set()
    if not isinstance(vals, list):
        raise R1Error("unresolved: withhold_values must be a list")
    for n, v in enumerate(vals):
        if not isinstance(v, dict) or set(v) != {"entry_id", "nutrient"} \
                or not (isinstance(v["entry_id"], str) and ENTRY_ID.fullmatch(v["entry_id"])) \
                or not (isinstance(v["nutrient"], str) and NUTRIENT.fullmatch(v["nutrient"])):
            raise R1Error(f"unresolved: value {n}: fields must be entry_id and nutrient")
        if (v["entry_id"], v["nutrient"]) in seen:
            raise R1Error(f"unresolved: value {n}: listed twice")
        seen.add((v["entry_id"], v["nutrient"]))
    if [(v["entry_id"], v["nutrient"]) for v in vals] != sorted(seen):
        raise R1Error("unresolved: values must be in ascending (entry_id, nutrient) order")


def build_unresolved(release: str, values: list) -> bytes:
    doc = {"schema": SCHEMA_UNRESOLVED, "release_id": release, "withhold_values": values}
    _validate_unresolved(doc)
    return json.dumps(doc, sort_keys=True, separators=(",", ":")).encode() + b"\n"


def parse_unresolved(data: bytes) -> dict:
    try:
        doc = json.loads(data.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError):
        raise R1Error("unresolved: not valid UTF-8 JSON") from None
    _validate_unresolved(doc)
    if build_unresolved(doc["release_id"], doc["withhold_values"]) != data:
        raise R1Error("unresolved: not in canonical form")
    return doc


def _listed(exclusions, unresolved):
    drops = {}
    for v in exclusions["withhold_values"]:
        drops.setdefault(v["entry_id"], {})[v["nutrient"]] = "withheld_value"
    for v in unresolved["withhold_values"]:
        drops.setdefault(v["entry_id"], {}).setdefault(v["nutrient"], "unresolved")
    return drops


def derive(pinned: dict, exclusions: dict, unresolved: dict, switches: dict, nutrients):
    """Returns (R1 document, counts). `pinned` is the parsed pinned release; `exclusions` and
    `unresolved` are parsed and must name the same release (the caller checks the bytes' ID);
    `nutrients` is the frozen inventory's key set."""
    if set(switches) != set(SWITCHES) or not all(isinstance(v, bool) for v in switches.values()):
        raise R1Error("switches: exactly a1 and a2, each true or false")
    if exclusions["release_id"] != unresolved["release_id"]:
        raise R1Error("the exclusion and unresolved lists name different releases")
    items = {it["id"]: it for it in pinned["items"]}
    gone = set(exclusions["withhold_entries"])
    demote = set(exclusions["reference_candidates"])
    drops = _listed(exclusions, unresolved)
    if any(k not in nutrients for keys in drops.values() for k in keys):
        raise R1Error("a listed nutrient is not in the frozen inventory")
    unknown = (gone | demote | set(drops)) - set(items)
    if unknown:
        raise R1Error(f"{len(unknown)} listed entries are not in the pinned release")

    counts = {k: 0 for k in ("entries", "entries_withheld", "values_kept", "values_dropped_a1",
                             "values_dropped_withheld_entry", "values_dropped_withheld_value",
                             "values_dropped_unresolved", "references_removed_withheld_entry",
                             "references_removed_for_value", "references_demoted_to_candidate",
                             "entries_with_no_nutrition", "sources_removed")}
    out_items = []
    for it in pinned["items"]:
        new = dict(it)
        labels = dict(it["label_nutrients"])
        ref = it["generic_reference"]
        if it["id"] in gone:
            counts["entries_withheld"] += 1
            counts["values_dropped_withheld_entry"] += len(labels)
            labels = {}
            if ref is not None:
                counts["references_removed_withheld_entry"] += 1
            ref = None
        else:
            label_dropped = False
            for key, why in sorted(drops.get(it["id"], {}).items()):
                if key in labels:
                    del labels[key]
                    counts["values_dropped_" + why] += 1
                    label_dropped = True
                elif it["generic_reference"] is not None:
                    if ref is not None:  # several listed keys may come through one reference
                        ref = None
                        counts["references_removed_for_value"] += 1
                else:
                    raise R1Error("a listed value is neither a label value nor reachable through a reference")
            if switches["a1"]:
                for key in [k for k, v in labels.items() if v["source_kind"] == OFF_KIND]:
                    del labels[key]
                    counts["values_dropped_a1"] += 1
                    label_dropped = True
            if ref is not None and ref["role"] == "merge" and (switches["a2"] or it["id"] in demote or label_dropped):
                ref = {**ref, "role": "candidate"}
                counts["references_demoted_to_candidate"] += 1
        new["label_nutrients"] = labels
        new["generic_reference"] = ref
        counts["entries"] += 1
        counts["values_kept"] += len(labels)
        if not labels and ref is None:
            counts["entries_with_no_nutrition"] += 1
        out_items.append(new)

    cited = {v["source_release"] for it in out_items for v in it["label_nutrients"].values()}
    sources = [s for s in pinned["sources"] if s["source_release_id"] in cited]
    counts["sources_removed"] = len(pinned["sources"]) - len(sources)
    doc = {k: pinned[k] for k in pinned}
    doc["sources"], doc["items"] = sources, out_items
    return doc, counts


def check_drops_only(pinned: dict, r1: dict) -> list:
    """Proves R1 only removes from the pinned release. Returns rule codes, empty when it holds."""
    errs = []
    if list(pinned) != list(r1):
        return ["top-keys"]
    for k in pinned:
        if k not in ("sources", "items") and pinned[k] != r1[k]:
            errs.append(f"top-changed: {k}")
    pinned_sources = {s["source_release_id"]: s for s in pinned["sources"]}
    for s in r1["sources"]:
        if pinned_sources.get(s["source_release_id"]) != s:
            errs.append("source-added-or-changed")
    if [it["id"] for it in pinned["items"]] != [it["id"] for it in r1["items"]]:
        return errs + ["entries-changed"]
    for a, b in zip(pinned["items"], r1["items"]):
        if list(a) != list(b) or any(a[k] != b[k] for k in a if k not in ("label_nutrients", "generic_reference")):
            errs.append("entry-field-changed")
        for key, v in b["label_nutrients"].items():
            if a["label_nutrients"].get(key) != v:
                errs.append("value-added-or-changed")
        ra, rb = a["generic_reference"], b["generic_reference"]
        if rb is not None and rb != ra and not (ra is not None and ra["role"] == "merge"
                                                and rb == {**ra, "role": "candidate"}):
            errs.append("reference-added-or-promoted")
    return errs


def check_applied(r1: dict, exclusions: dict, unresolved: dict, switches: dict, pinned: dict = None) -> list:
    """Proves every required removal happened. Returns rule codes, empty when it holds. With the
    pinned document, also proves no entry that lost a label value keeps a merge."""
    pinned_items = pinned["items"] if pinned is not None else None
    errs = set()
    items = {it["id"]: it for it in r1["items"]}
    for e in exclusions["withhold_entries"]:
        if e not in items or items[e]["label_nutrients"] or items[e]["generic_reference"] is not None:
            errs.add("withheld-entry-kept")
    for e, keys in _listed(exclusions, unresolved).items():
        if e in items and any(k in items[e]["label_nutrients"] for k in keys):
            errs.add("listed-value-kept")
        ref = items.get(e, {}).get("generic_reference")
        if ref is not None and ref["role"] == "merge":
            errs.add("listed-value-reachable-through-merge")
    for e in exclusions["reference_candidates"]:
        ref = items.get(e, {}).get("generic_reference")
        if ref is not None and ref["role"] == "merge":
            errs.add("candidate-still-merge")
    for it, before in zip(r1["items"], pinned_items or [None] * len(r1["items"])):
        if switches["a1"] and any(v["source_kind"] == OFF_KIND for v in it["label_nutrients"].values()):
            errs.add("a1-value-kept")
        if before is not None and set(it["label_nutrients"]) != set(before["label_nutrients"]) \
                and it["generic_reference"] is not None and it["generic_reference"]["role"] == "merge":
            errs.add("merge-kept-after-label-drop")
        ref = it["generic_reference"]
        if switches["a2"] and ref is not None and ref["role"] == "merge":
            errs.add("a2-merge-kept")
    return sorted(errs)
