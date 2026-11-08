"""The pfd-results-v2 allow-list writer for Part A of the v2 review. Pure.

Design: docs/personal-food-database-review-v2-design.md, section 5. The same design as results.py
(pfd-results-v1, which Part B keeps writing): closed field names, whole-number counts, intervals,
`passes` true, false or null, and the release ID. It adds `part_a_bars` (one of its two tokens),
boolean `<bar>_not_assessable` flags and closed `<measure>_unresolved` counts. Any other key, or
any string other than the schema, part, bar set and release ID, is refused, so no title, brand or
entry ID can be written.
"""
import json
import re

from formats import RELEASE_ID, dumps

SCHEMA = "pfd-results-v2"
BAR_SETS = {"v1_accepted", "v2_proposed"}
_CHECKS = ("identity", "state", "variety")
_VALUE_TOKENS = ("correct", "error_basis", "error_state", "error_transcription", "error_derivation", "error_source",
                 "unresolved", "missing", "missing_source_available", "present_unquantified", "candidate_only")
_VALUE_STRATA = ("a1", "a2", "a5")

MEASURES = {"a1_wrong_identity_state_or_variety", "a5_wrong_identity_state_or_variety",
            "a2_different_food_or_other_state", "a3_misleading", "a4_match_missed",
            "a1_value_evidence_errors", "a5_value_evidence_errors",
            *(f"{k}_{g}_value_evidence_errors" for k in _VALUE_STRATA for g in ("macro", "micro"))}
COUNTS = (
    {f"{k}_entries" for k in ("a1", "a2", "a3", "a4", "a5")}
    | {f"{k}_{c}_{w}" for k in ("a1", "a2", "a3", "a4", "a5") for c in _CHECKS for w in ("passed", "failed", "unresolved")}
    | {f"{k}_values_{t}" for k in _VALUE_STRATA for t in _VALUE_TOKENS}
    | {f"{k}_{g}_correct" for k in _VALUE_STRATA for g in ("macro", "micro", "other")}
    | {f"{k}_{x}" for k in _VALUE_STRATA for x in ("other_value_errors", "rows_complete_macro", "rows_complete_micro",
                                                   "values_stated_assumption", "values_unknown_state")}
    | {"a3_misleading_other_state", "a3_misleading_close", "a3_sensible", "a4_nothing_suitable"}
    | {f"{m}_unresolved" for m in MEASURES}
)
FLAGS = {"a1_nutrient_disagreements_not_assessable", "a5_nutrient_disagreements_not_assessable"}
MEASURE_KEYS = {"count", "of", "interval", "allowed", "passes"}
DOC_KEYS = {"schema", "part", "release_id", "part_a_bars", "measures"}


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


def build(release_id: str, part_a_bars: str, measures: dict) -> bytes:
    if not isinstance(release_id, str) or not RELEASE_ID.fullmatch(release_id):
        raise ResultsError("release_id not allowed")
    if part_a_bars not in BAR_SETS:
        raise ResultsError("part_a_bars must be v1_accepted or v2_proposed")
    if not isinstance(measures, dict):
        raise ResultsError("measures must be an object")
    for k, v in measures.items():
        if k in MEASURES:
            _check_measure(k, v)
        elif k in COUNTS:
            if not _int(v):
                raise ResultsError(f"{k}: must be a whole number")
        elif k in FLAGS:
            if not isinstance(v, bool):
                raise ResultsError(f"{k}: must be true or false")
        else:
            raise ResultsError("unknown result field")
    doc = {"schema": SCHEMA, "part": "A", "release_id": release_id, "part_a_bars": part_a_bars, "measures": measures}
    data = dumps(doc)
    # Belt and braces: the only strings in the file are field names, the schema, part, bar set and release.
    strings = set(re.findall(r'"((?:[^"\\]|\\.)*)"', data.decode("utf-8")))
    permitted = DOC_KEYS | {SCHEMA, "A", release_id, part_a_bars} | MEASURE_KEYS | MEASURES | COUNTS | FLAGS
    if strings - permitted:
        raise ResultsError("a string outside the allow-list reached the results file")
    return data


def parse(data: bytes) -> dict:
    """A pfd-results-v2 file, accepted only when it re-encodes to the same bytes."""
    try:
        doc = json.loads(data.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError):
        raise ResultsError("results: not valid UTF-8 JSON") from None
    if not isinstance(doc, dict) or set(doc) != DOC_KEYS or doc["schema"] != SCHEMA or doc["part"] != "A":
        raise ResultsError("results: not a pfd-results-v2 file")
    if build(doc["release_id"], doc["part_a_bars"], doc["measures"]) != data:
        raise ResultsError("results: not in canonical form")
    return doc
