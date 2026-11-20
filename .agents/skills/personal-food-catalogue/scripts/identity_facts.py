"""Food details from the catalogue, schema `personal-food-catalogue-estimates-v4`
(docs/personal-food-catalogue-identity-facts-v1-amendment.md sections I1.1 to I1.5).

Pure, apart from `read_record`, which the caller supplies (apply_estimates.record_reader). It holds:

- the codec rules of `identity_facts` (`facts-keys`, `facts-value`, `facts-state`), which
  export_v1._check applies to a v4 file only and the Swift codec mirrors code for code;
- the candidate identity of section I1.3 and the facts-aware merge rule, mirroring
  `PersonalFoodDatabaseCandidateBuilder.mergeEligible` and `.identity`;
- the approved facts input (`pfc-approved-identity-facts-v1`) and the checker of section I1.5 step 5:
  "merge ineligible", "entry would disappear", estimate contradictions, and `as_sold` entries usually
  searched with "raw".

Nothing here prints or returns a title, brand or value; reports carry entry IDs and counts only.
"""
import json

SCHEMA = "personal-food-catalogue-estimates-v4"
RULE_CODES = ("facts-keys", "facts-value", "facts-state")
KEYS = ("preparation", "bone", "skin", "drained", "packing_medium", "fortification")
VALUES = {
    "preparation": ("as_sold", "raw", "cooked", "unknown"),
    "bone": ("with_bone", "boneless", "not_applicable", "unknown"),
    "skin": ("skin_on", "skinless", "not_applicable", "unknown"),
    "drained": ("drained", "undrained", "not_applicable", "unknown"),
    "packing_medium": ("as sold", "not applicable", "water", "brine", "oil", "olive_oil", "sauce", "unknown"),
    "fortification": ("unfortified", "unknown"),  # fortified is never admitted (decision I1-D2)
}
UNKNOWN = {k: "unknown" for k in KEYS}
INPUT_SCHEMA = "pfc-approved-identity-facts-v1"
INPUT_KEYS = {"schema", "rows"}
ROW_KEYS = {"entry_id", "facts"}
ROW_OPTIONAL = {"accept_disappear"}
# Titles or aliases that are usually searched with "raw" (section I1.5 step 5): nuts, seeds, dried fruit.
RAW_SEARCHED_CATEGORIES = {"nut_seed"}
RAW_SEARCHED_WORDS = {"almond", "almonds", "cashew", "cashews", "walnut", "walnuts", "hazelnut", "hazelnuts",
                      "pecan", "pecans", "pistachio", "pistachios", "peanut", "peanuts", "seed", "seeds",
                      "raisin", "raisins", "sultana", "sultanas", "apricot", "apricots", "date", "dates",
                      "fig", "figs", "prune", "prunes", "cranberries", "nut", "nuts"}


class FactsRefused(Exception):
    """An approved facts file that cannot be used; the message never names a food."""


def preparation_agrees(preparation, state) -> bool:
    """Section I1.1: raw admits raw or unknown, cooked admits cooked or unknown, every other state
    as_sold or unknown."""
    if state == "raw":
        return preparation in ("raw", "unknown")
    if state == "cooked":
        return preparation in ("cooked", "unknown")
    return preparation in ("as_sold", "unknown")


def check(value, state, err, where):
    """Section I1.2 for one entry's non-null `identity_facts`: `facts-keys`, else one `facts-value`,
    else `facts-state`. The strict reader already refuses a repeated key (`duplicate-key`)."""
    if not isinstance(value, dict) or set(value) != set(KEYS):
        return err("facts-keys", where)
    if not all(isinstance(value[k], str) and value[k] in VALUES[k] for k in KEYS):
        return err("facts-value", where)
    if not preparation_agrees(value["preparation"], state):
        err("facts-state", where)


# ---- candidate identity (section I1.3) ----------------------------------------------------------

def own_identity(item) -> dict:
    """No merge: each fact from `identity_facts` where it is not unknown, else today's mapping
    (preparation from `state` for raw or cooked, every other fact unknown)."""
    facts = item.get("identity_facts") or UNKNOWN
    out = dict(facts)
    if out["preparation"] == "unknown":
        out["preparation"] = item["state"] if item["state"] in ("raw", "cooked") else "unknown"
    return out


def record_identity(record) -> dict:
    """A bundled record's facts as `apply_estimates.record_reader` reads them."""
    ident = record.get("identity") or {}
    return {"preparation": record.get("preparation") or "unknown", "bone": ident.get("bone", "unknown"),
            "skin": ident.get("skin", "unknown"), "drained": ident.get("drained", "unknown"),
            "packing_medium": ident.get("packing_medium", "unknown"),
            "fortification": record.get("fortification") or "unknown"}


def contradictions(record: dict, confirmed: dict) -> list:
    """`EstimateIdentityComparison.contradictions`: facets known on both sides and different; as_sold
    and raw are compatible."""
    out = []
    for k in KEYS:
        a, b = record.get(k, "unknown"), confirmed.get(k, "unknown")
        if a in (None, "unknown") or b in (None, "unknown") or a == b:
            continue
        if k == "preparation" and {a, b} == {"as_sold", "raw"}:
            continue
        out.append(k)
    return out


def merge_eligible(item, record) -> bool:
    """`PersonalFoodDatabaseCandidateBuilder.mergeEligible`, with the I1.3 condition for an entry that
    has facts: no stated fact contradicts the record's."""
    ref = item.get("generic_reference")
    if record is None or not ref or ref.get("role") != "merge":
        return False
    if item["state"] not in ("raw", "cooked") or item["basis"] != "per_100_g":
        return False
    if record.get("preparation") != item["state"] or record.get("per_100_g") is not True \
            or record.get("fortification") == "fortified":
        return False
    if item.get("identity_facts") is None:
        return True
    return not contradictions(record_identity(record), own_identity(item))


def entry_identity(item, merged_record):
    """(identity, facts taken from the file): with a merge, the record's identity with its unknown
    facts taken from the file; without, `own_identity`."""
    facts = item.get("identity_facts")
    if merged_record is None:
        return own_identity(item), [k for k in KEYS if facts and facts[k] != "unknown"]
    rec = record_identity(merged_record)
    if facts is None:
        return rec, []
    own, taken = own_identity(item), []
    for k in KEYS[1:]:  # a merge needs a known, equal preparation, so the record's stands
        if rec[k] == "unknown" and own[k] != "unknown":
            rec[k] = own[k]
            taken.append(k)
    return rec, taken


# ---- the approved facts input -------------------------------------------------------------------

def parse(data: bytes) -> dict:
    """`pfc-approved-identity-facts-v1`: {"schema", "rows": [{"entry_id", "facts", "accept_disappear"?}]},
    one row per entry ID, each `facts` a full object with closed values. Only facts the owner approved
    are listed; anything else stays unknown."""
    try:
        doc = json.loads(data)
    except ValueError as e:
        raise FactsRefused(f"approved facts: not JSON ({type(e).__name__})")
    if not isinstance(doc, dict) or set(doc) != INPUT_KEYS or doc["schema"] != INPUT_SCHEMA \
            or not isinstance(doc["rows"], list):
        raise FactsRefused(f"approved facts: not a {INPUT_SCHEMA} document")
    seen = set()
    for n, row in enumerate(doc["rows"]):
        if not isinstance(row, dict) or not ROW_KEYS <= set(row) <= ROW_KEYS | ROW_OPTIONAL \
                or not isinstance(row["entry_id"], str) or row["entry_id"] in seen:
            raise FactsRefused(f"approved facts: row {n} is malformed or repeats an entry")
        if "accept_disappear" in row and not isinstance(row["accept_disappear"], bool):
            raise FactsRefused(f"approved facts: row {n} accept_disappear must be true or false")
        problems = []
        check(row["facts"], "unknown", lambda code, _w: problems.append(code), n)
        if problems and problems != ["facts-state"]:  # the state is the entry's, checked on apply
            raise FactsRefused(f"approved facts: row {n} {problems[0]}")
        seen.add(row["entry_id"])
    return doc


# ---- the checker of section I1.5 step 5 ---------------------------------------------------------

def _record(read_record, source, record_id):
    try:
        return read_record(source, record_id)
    except Exception:  # noqa: BLE001  a record that cannot be read supplies nothing
        return None


def _known_own_values(item) -> bool:
    return bool(item.get("label_nutrients")) or bool(item.get("estimated_nutrients"))


def raw_searched(item) -> bool:
    words = set()
    for text in [item["title"], *(item.get("titles") or []), *(item.get("aliases") or [])]:
        words |= {w.strip(",.()").lower() for w in text.split()}
    return item.get("category") in RAW_SEARCHED_CATEGORIES or bool(words & RAW_SEARCHED_WORDS)


def assess(item, facts, read_record) -> dict:
    """What stating `facts` on `item` does under I1.3: `merge_ineligible` (the merge holds without the
    facts and not with them), `disappears` (then no known value of its own), `contradictions` (estimate
    evidence IDs the importer would reject) and `raw_searched`."""
    with_facts = {**item, "identity_facts": facts}
    ref = item.get("generic_reference")
    merge_record = _record(read_record, ref["source"], ref["record_id"]) if ref and ref.get("role") == "merge" else None
    was = merge_eligible({**item, "identity_facts": None}, merge_record)
    now = merge_eligible(with_facts, merge_record)
    identity, _ = entry_identity(with_facts, merge_record if now else None)
    contradicting = []
    for key, est in sorted((item.get("estimated_nutrients") or {}).items()):
        rec_id = est.get("evidence_id")
        ev = item.get("_evidence", {}).get(rec_id)
        if not ev or ev.get("source_type") != "national_composition":
            continue
        rec = _record(read_record, ev.get("composition_source"), ev.get("source_reference"))
        if rec is not None and contradictions(record_identity(rec), identity):
            contradicting.append(rec_id)
    return {"merge_ineligible": was and not now, "disappears": was and not now and not _known_own_values(item),
            "contradictions": contradicting,
            "raw_searched": facts is not None and facts["preparation"] == "as_sold" and raw_searched(item)}


def apply(doc: dict, approved: dict, read_record):
    """The v4 document and a report of counts and entry IDs. A row whose entry is missing, whose
    preparation disagrees with the entry's state, whose facts would make an estimate contradict (the
    importer would reject the file) or, unless `accept_disappear` is true, would make the entry
    disappear, is not written; its entry keeps `identity_facts` null. With no row written the caller
    keeps today's v2 or v3 file."""
    evidence = {r["id"]: r for r in doc.get("estimate_evidence") or []}
    rows = {r["entry_id"]: r for r in approved["rows"]}
    report = {"written": [], "missing_entry": [], "state_disagrees": [], "merge_ineligible": [],
              "entry_would_disappear": [], "estimate_contradiction": [], "as_sold_raw_searched": [],
              "all_unknown": []}
    items = []
    for it in doc["items"]:
        row = rows.pop(it["id"], None)
        facts = None
        if row is not None:
            proposed = {k: row["facts"][k] for k in KEYS}
            if all(v == "unknown" for v in proposed.values()):
                report["all_unknown"].append(it["id"])
            elif not preparation_agrees(proposed["preparation"], it["state"]):
                report["state_disagrees"].append(it["id"])
            else:
                got = assess({**it, "_evidence": evidence}, proposed, read_record)
                if got["merge_ineligible"]:
                    report["merge_ineligible"].append(it["id"])
                if got["raw_searched"]:
                    report["as_sold_raw_searched"].append(it["id"])
                if got["contradictions"]:
                    report["estimate_contradiction"].append(it["id"])
                elif got["disappears"] and not row.get("accept_disappear"):
                    report["entry_would_disappear"].append(it["id"])
                else:
                    facts = proposed
                    report["written"].append(it["id"])
        new = {k: v for k, v in it.items()}
        new.setdefault("estimated_nutrients", {})
        new["identity_facts"] = facts
        items.append(new)
    report["missing_entry"] = sorted(rows)
    out = {k: doc[k] for k in doc if k != "estimate_evidence"}
    out["schema"] = SCHEMA
    out["items"] = items
    out["estimate_evidence"] = doc.get("estimate_evidence") or []
    return out, report
