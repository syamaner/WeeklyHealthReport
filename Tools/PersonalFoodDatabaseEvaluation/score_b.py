"""Part B measures from a query set and a ranking output. Pure.

Plan section 4.4: for `entry` and `generic` answers an acceptable result must be first (an empty
list is not acceptable); for `none` no database entry may be first (an empty list or a generic first
is acceptable). Top-1 and wrong entry first are over all queries; negative false hits are the `none`
queries with an entry first, over the `none` queries. One false hit therefore counts once in each.
"""
from formats import FormatError
from stats import wilson
from bars import judge


def _ok(answer, c):
    if c is None:
        return False
    if answer["kind"] == "entry":
        return c["kind"] == "entry" and c["entry_id"] in answer["entry_ids"]
    if answer["kind"] == "generic":
        return c["kind"] == "generic" and (c["source"], c["record_id"]) in {(g["source"], g["record_id"]) for g in answer["generic"]}
    return c["kind"] == "generic"  # none: a generic first is acceptable; empty is handled by the caller


def score(query_set: dict, ranking: dict):
    if query_set["release_id"] != ranking["release_id"]:
        raise FormatError("ranking output: release differs from the query set")
    if query_set.get("set") and query_set["set"] != ranking["set"]:
        raise FormatError("ranking output: set differs from the query set")
    results = {r["query_id"]: r["candidates"] for r in ranking["results"]}
    queries = query_set["queries"]
    if set(results) != {q["query_id"] for q in queries}:
        raise FormatError("ranking output: query IDs differ from the query set")
    n = len(queries)
    top1 = top3 = step_ok = step_n = wrong_entry = wrong_generic = generic_n = none_n = neg_false = 0
    for q in queries:
        a, cands = q["answer"], results[q["query_id"]]
        first = cands[0] if cands else None
        if a["kind"] == "none":
            none_n += 1
            hit = first is None or first["kind"] == "generic"
            if first is not None and first["kind"] == "entry":
                neg_false += 1
            top1 += hit
            top3 += hit
        else:
            hit = _ok(a, first)
            top1 += hit
            top3 += any(_ok(a, c) for c in cands[:3])
            if a["kind"] == "entry" and hit and first is not None:
                step_n += 1
                step_ok += first["step"] == a["step"]
            if a["kind"] == "generic":
                generic_n += 1
                wrong_generic += first is not None and first["kind"] == "generic" and not hit
        if first is not None and first["kind"] == "entry" and not (a["kind"] == "entry" and hit):
            wrong_entry += 1

    def m(count, of, bar=None):
        out = {"count": count, "of": of, "interval": list(wilson(count, of)) if of else None}
        if bar:
            out.update(judge(bar, count, of))
        return out

    return {"queries": n, "none_queries": none_n,
            "b_top1_acceptable": m(top1, n, "b_top1_acceptable"),
            "b_top3_acceptable": m(top3, n),
            "b_step_correct": m(step_ok, step_n),
            "b_wrong_generic_first": m(wrong_generic, generic_n),
            "b_wrong_entry_first": m(wrong_entry, n, "b_wrong_entry_first"),
            "b_negative_false_hits": m(neg_false, none_n, "b_negative_false_hits")}
