"""Part A counts for the v2 best-estimate review, and the exclusion list as data. Pure.

Design: docs/personal-food-database-review-v2-design.md, section 3 and section 6 (exclusions).

- The sheet holds exactly the sealed sample's initial entries, in order; rows are never replaced.
- Each entry counts at most once per measure. Fail beats unresolved, unresolved beats pass.
- A1 and A5: failed entries over decided entries (failed plus all-pass), so a share never exceeds
  one; assessed value evidence errors (any error_*) over assessed values (correct plus error_*),
  judged against the one value bar on macro and micro together, with macro and micro reported
  separately for information. The non-assessed tokens never enter a denominator and are counted on
  their own; "other" keys get coverage counts and never enter an error denominator.
- A2: merge_failed over A2 entries without an unresolved outcome; A2 value evidence errors are
  informational. A3: misleading (other-state or close, one token per entry) over resolved
  entries. A4: match_missed over decided entries, informational.
- A measure whose stratum has an unresolved entry or value has `passes` None (not final), and every
  measure carries a closed `<measure>_unresolved` count: unresolved entries for an entry measure,
  unresolved values of its group for a value measure.
- Under v1_accepted the A1 and A5 pack bars are reported as `<bar>_not_assessable`, never a pass.
"""
from bars_v2 import BAR_SETS, BarsError, judge, not_assessable
from formats import STRATA, FormatError
from formats_v2 import (ASSESSMENTS, CHECKS, ERRORS, FULL_COVERAGE, GROUPS, check_bundle, check_status,
                        entry_status, supplied)
from stats import wilson

# measure: bar name under each set (None: informational, no bar)
MEASURE_BARS = {
    "a1_wrong_identity_state_or_variety": {"v1_accepted": "a1_wrong_product_or_variant",
                                           "v2_proposed": "a1_wrong_identity_state_or_variety"},
    "a1_value_evidence_errors": {"v2_proposed": "a1_value_evidence_errors"},
    "a1_macro_value_evidence_errors": {},
    "a1_micro_value_evidence_errors": {},
    "a2_different_food_or_other_state": {"v1_accepted": "a2_different_food_or_other_state",
                                         "v2_proposed": "a2_different_food_or_other_state"},
    "a2_macro_value_evidence_errors": {},
    "a2_micro_value_evidence_errors": {},
    "a3_misleading": {"v1_accepted": "a3_misleading", "v2_proposed": "a3_misleading"},
    "a4_match_missed": {},
    "a5_wrong_identity_state_or_variety": {},
    "a5_value_evidence_errors": {"v2_proposed": "a5_value_evidence_errors"},
    "a5_macro_value_evidence_errors": {},
    "a5_micro_value_evidence_errors": {},
}
VALUE_TOKENS = tuple(t for t in ASSESSMENTS if t != "match_available")
MISLEADING = ("misleading_other_state", "misleading_close")


def validate(sample, rows, records, inventory):
    expected = [(e["entry_id"], e["stratum"], e["reason"]) for e in sample["entries"]]
    if [(r["entry_id"], r["stratum"], r["reason"]) for r in rows] != expected:
        raise FormatError("review sheet v2: rows differ from the sealed sample's initial entries (each once, in order)")
    return check_bundle(rows, records, inventory)


def _entry_unresolved(r) -> bool:
    return entry_status(r) == "unresolved" if r["stratum"] in ("A1", "A5") else r["outcome"] == "unresolved"


def score(sample: dict, rows, records, inventory: dict, bar_set: str) -> dict:
    if bar_set not in BAR_SETS:
        raise BarsError("part_a_bars is not a known bar set")
    by_row = validate(sample, rows, records, inventory)
    group = inventory["group_of"]
    out, stratum_open = {}, {}

    def measure(name, count, n, unresolved_count):
        m = {"count": count, "of": n, "interval": list(wilson(count, n)) if n else None}
        bar = MEASURE_BARS[name].get(bar_set)
        if bar:
            m.update(judge(bar_set, bar, count, n, stratum_open[name[:2].upper()]))
        out[name] = m
        out[f"{name}_unresolved"] = unresolved_count

    for s in STRATA:
        k, rs = s.lower(), [r for r in rows if r["stratum"] == s]
        recs = [rec for r in rs for rec in by_row[r["row"]]]
        stratum_open[s] = any(_entry_unresolved(r) for r in rs) or any(rec["assessment"] == "unresolved" for rec in recs)
        out[f"{k}_entries"] = len(rs)
        for c in CHECKS:
            got = [check_status(r, c) for r in rs]
            for st, word in (("pass", "passed"), ("fail", "failed"), ("unresolved", "unresolved")):
                out[f"{k}_{c}_{word}"] = got.count(st)
        if s not in FULL_COVERAGE:
            continue
        tokens = [rec["assessment"] for rec in recs]
        for t in VALUE_TOKENS:
            out[f"{k}_values_{t}"] = tokens.count(t)
        for g in GROUPS:
            out[f"{k}_{g}_correct"] = sum(1 for rec in recs if group[rec["nutrient"]] == g and rec["assessment"] == "correct")
        out[f"{k}_other_value_errors"] = sum(1 for rec in recs if group[rec["nutrient"]] == "other" and rec["assessment"] in ERRORS)
        for g in ("macro", "micro"):
            keys = inventory["groups"][g]
            out[f"{k}_rows_complete_{g}"] = sum(
                1 for r in rs if all(rec["assessment"] == "correct" for rec in by_row[r["row"]] if rec["nutrient"] in keys))
        out[f"{k}_values_stated_assumption"] = sum(1 for rec in recs if supplied(rec) and rec["state_basis"] == "stated_assumption")
        out[f"{k}_values_unknown_state"] = sum(1 for rec in recs if supplied(rec) and rec["state_basis"] == "unknown")

    for s in ("A1", "A5"):
        rs = [r for r in rows if r["stratum"] == s]
        status = [entry_status(r) for r in rs]
        measure(f"{s.lower()}_wrong_identity_state_or_variety", status.count("fail"),
                status.count("fail") + status.count("pass"), status.count("unresolved"))
    for s in FULL_COVERAGE:
        recs = [rec for r in rows if r["stratum"] == s for rec in by_row[r["row"]]]
        both = []
        for g in ("macro", "micro"):
            mine = [rec["assessment"] for rec in recs if group[rec["nutrient"]] == g]
            both += mine
            errors = sum(1 for t in mine if t in ERRORS)
            measure(f"{s.lower()}_{g}_value_evidence_errors", errors, errors + mine.count("correct"), mine.count("unresolved"))
        if s in ("A1", "A5"):  # the plan's one value bar, judged on macro and micro together
            errors = sum(1 for t in both if t in ERRORS)
            measure(f"{s.lower()}_value_evidence_errors", errors, errors + both.count("correct"), both.count("unresolved"))

    a2 = [r["outcome"] for r in rows if r["stratum"] == "A2"]
    measure("a2_different_food_or_other_state", a2.count("merge_failed"), len(a2) - a2.count("unresolved"), a2.count("unresolved"))
    a3 = [r["outcome"] for r in rows if r["stratum"] == "A3"]
    measure("a3_misleading", sum(a3.count(t) for t in MISLEADING), len(a3) - a3.count("unresolved"), a3.count("unresolved"))
    out["a3_misleading_other_state"] = a3.count("misleading_other_state")
    out["a3_misleading_close"] = a3.count("misleading_close")
    out["a3_sensible"] = a3.count("sensible")
    a4 = [r["outcome"] for r in rows if r["stratum"] == "A4"]
    measure("a4_match_missed", a4.count("match_missed"), a4.count("match_missed") + a4.count("nothing_suitable"),
            a4.count("unresolved"))
    out["a4_nothing_suitable"] = a4.count("nothing_suitable")
    for bar in not_assessable(bar_set):
        out[f"{bar}_not_assessable"] = True
    return out


def exclusion_list(sample: dict, rows, records, inventory: dict) -> dict:
    """What the later export phase withholds (design section 6), by entry ID and inventory key:

    - withhold_entries: every value and reference of an entry failing identity, merged state or
      material variety (A1, A5: any failing check; A2: merge_failed; A3: a misleading candidate or a
      different food);
    - withhold_values: every value assessed error_*, in any stratum, even within a passing bar;
    - reference_candidates: every reference left unresolved, which stays a candidate.
    """
    by_row = validate(sample, rows, records, inventory)
    entries, values, candidates = [], [], []
    for r in rows:
        s, outcome = r["stratum"], r["outcome"]
        if s in ("A1", "A5"):
            bad, open_ = entry_status(r) == "fail", entry_status(r) == "unresolved"
        elif s == "A2":
            bad, open_ = outcome == "merge_failed", outcome == "unresolved"
        elif s == "A3":
            bad = outcome in MISLEADING or r["identity"] == "different_food"
            open_ = outcome == "unresolved" and not bad
        else:
            bad = open_ = False
        if bad:
            entries.append(r["entry_id"])
        elif open_:
            candidates.append(r["entry_id"])
        values += [{"entry_id": r["entry_id"], "nutrient": rec["nutrient"], "assessment": rec["assessment"]}
                   for rec in by_row[r["row"]] if rec["assessment"] in ERRORS]
    return {"withhold_entries": entries, "withhold_values": values, "reference_candidates": candidates}
