"""The pfd-results-v1 allow-list writer: the only thing this tool writes into the repository.

Closed field names, whole-number counts, intervals, booleans for bar results and the release ID.
Any other key, or any string other than the schema, part, set and release ID, is refused, so no
title, brand, query text or entry ID can be written.
"""
import re

from formats import RELEASE_ID, dumps

MEASURES_A = {"a1_wrong_product_or_variant", "a1_nutrient_disagreements", "a5_nutrient_disagreements",
              "a2_different_food_or_other_state", "a3_misleading", "a4_match_missed"}
COUNTS_A = {"a1_entries", "a1_skipped", "a1_wrong_product", "a1_wrong_variant", "a1_not_on_pack", "a1_missing_in_entry",
            "a5_entries", "a5_skipped", "a5_not_on_pack", "a5_missing_in_entry", "a2_skipped", "a3_skipped",
            "a4_skipped", "a2_other_state", "a2_different_food", "a3_misleading_close", "a3_misleading_other_state"}
FLAGS_A = {"a1_skip_limit_exceeded", "a2_short_of_quota", "a3_short_of_quota", "a4_short_of_quota"}
MEASURES_B = {"b_top1_acceptable", "b_top3_acceptable", "b_step_correct", "b_wrong_generic_first",
              "b_wrong_entry_first", "b_negative_false_hits"}
COUNTS_B = {"queries", "none_queries", "owner_development_output_openings"}
MEASURE_KEYS = {"count", "of", "interval", "allowed", "passes"}
SETS = {"development", "held-out"}


class ResultsError(ValueError):
    pass


def _int(v):
    return isinstance(v, int) and not isinstance(v, bool) and v >= 0


def _check_measure(name, m):
    if not isinstance(m, dict) or set(m) - MEASURE_KEYS or not {"count", "of", "interval"} <= set(m):
        raise ResultsError(f"{name}: not an allowed measure")
    if not (_int(m["count"]) and _int(m["of"]) and m["count"] <= m["of"]):
        raise ResultsError(f"{name}: count and of must be whole numbers with count <= of")
    iv = m["interval"]
    if not (iv is None or (isinstance(iv, list) and len(iv) == 2 and all(isinstance(x, float) or x in (0, 1) for x in iv)
                           and all(not isinstance(x, bool) for x in iv))):
        raise ResultsError(f"{name}: interval must be two numbers or null")
    if "allowed" in m and not (m["allowed"] is None or _int(m["allowed"])):
        raise ResultsError(f"{name}: allowed must be a whole number or null")
    if "passes" in m and not (m["passes"] is None or isinstance(m["passes"], bool)):
        raise ResultsError(f"{name}: passes must be true, false or null")


def build(part: str, release_id: str, measures: dict, result_set: "str | None" = None) -> bytes:
    if part not in ("A", "B") or not isinstance(release_id, str) or not RELEASE_ID.fullmatch(release_id):
        raise ResultsError("part or release_id not allowed")
    if part == "B" and result_set not in SETS or part == "A" and result_set is not None:
        raise ResultsError("set not allowed for this part")
    allowed_measures, allowed_counts, allowed_flags = (
        (MEASURES_A, COUNTS_A, FLAGS_A) if part == "A" else (MEASURES_B, COUNTS_B, set()))
    for k, v in measures.items():
        if k in allowed_measures:
            _check_measure(k, v)
        elif k in allowed_counts:
            if not _int(v):
                raise ResultsError(f"{k}: must be a whole number")
        elif k in allowed_flags:
            if not isinstance(v, bool):
                raise ResultsError(f"{k}: must be true or false")
        else:
            raise ResultsError("unknown result field")
    doc = {"schema": "pfd-results-v1", "part": part, "release_id": release_id, "measures": measures}
    if result_set:
        doc["set"] = result_set
    data = dumps(doc)
    # Belt and braces: the only strings in the file are field names, the schema, part, set and release.
    strings = set(re.findall(r'"((?:[^"\\]|\\.)*)"', data.decode("utf-8")))
    permitted = ({"schema", "pfd-results-v1", "part", part, "release_id", release_id, "measures", "set"}
                 | SETS | MEASURE_KEYS | allowed_measures | allowed_counts | allowed_flags)
    if strings - permitted:
        raise ResultsError("a string outside the allow-list reached the results file")
    return data
