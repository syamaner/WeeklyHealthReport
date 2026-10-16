"""Route-independent scoring for `label-capture-candidate-v1` (plan section 5). Pure.

Matching reuses the frozen v2 semantics: canonical nutrient, parent and semantic
basis; numeric text, comparator, unit and basis are compared without rewriting;
missing candidates stay in denominators; declined images stay in denominators;
duplicate same-basis columns earn credit only through distinct verified printed
headers, never by list order. The Inspect scorers in `inspect_task.py` call these
functions, so the scoring is identical for every route.
"""

from __future__ import annotations

import json
import re
import unicodedata
from collections import Counter
from pathlib import Path
from typing import Any

import arithmetic
from candidate import validate_candidate

HERE = Path(__file__).resolve().parent
NUTRIENTS = {
    "energy_kj",
    "energy_kcal",
    "fat",
    "saturates",
    "trans_fat",
    "carbohydrate",
    "sugars",
    "added_sugars",
    "fibre",
    "protein",
    "salt",
    "sodium",
}
NOT_A_CONVERSION = {None, "", "unknown", "not_applicable"}

# Metric name -> (numerator count, denominator count, contract threshold key, direction)
METRICS = {
    "strict_cells": ("cells_exact", "product_cells", "numeric_cell_exact_minimum", "min"),
    "binding": ("cells_bound", "all_cells", "row_header_binding_minimum", "min"),
    "unit_and_basis": ("cells_unit_basis", "product_cells", "unit_and_basis_minimum", "min"),
    "full_table": ("tables_exact", "usable_tables", "full_table_exact_minimum", "min"),
    "serving_conversions": ("conversions_exact", "conversions", "serving_conversion_minimum", "min"),
    "servings_per_pack": ("servings_per_pack_exact", "servings_per_pack", "servings_per_pack_minimum", "min"),
    "bounds": ("bounds_exact", "bounded_cells", "bound_preservation_minimum", "min"),
    "correct_decline": ("declines_correct", "declines_required", "correct_decline_minimum", "min"),
    "false_ready": ("false_ready", "cases", "false_ready_maximum", "max_count"),
}


def normalise_label(text: Any) -> str:
    return re.sub(r"\s+", " ", unicodedata.normalize("NFC", str(text or ""))).strip().lower()


def compact(text: Any) -> str:
    """Serving quantities compare with all whitespace removed, so `90 公克` equals `90公克`."""
    return re.sub(r"\s+", "", unicodedata.normalize("NFC", str(text or "")))


def nutrient_key(cell: dict[str, Any]) -> str:
    nutrient = cell.get("nutrient")
    if nutrient in NUTRIENTS:
        return nutrient
    label = re.sub(r"^of which\s+", "", normalise_label(cell.get("printed_label")))
    return f"unrecognised:{label}"


def parent_key(cell: dict[str, Any], cells_by_row: dict[str, dict[str, Any]]) -> str:
    parent = cell.get("parent_row_id")
    if not parent:
        return ""
    if parent in NUTRIENTS:
        return parent
    owner = cells_by_row.get(parent)
    return nutrient_key(owner) if owner else f"row:{parent}"


def _header_texts(table: dict[str, Any]) -> dict[str, str]:
    return {h.get("header_id"): normalise_label(h.get("printed_text")).replace(" ", "") for h in table.get("headers") or []}


def keyed_cells(table: dict[str, Any]) -> tuple[dict[tuple, dict[str, Any]], set[tuple]]:
    """Map each cell to its semantic key; return (unique keys -> cell, ambiguous keys)."""
    cells = table.get("cells") or []
    by_row = {c.get("row_id"): c for c in cells}
    headers = _header_texts(table)
    basis_counts = Counter(h.get("basis") for h in table.get("headers") or [])
    keys: dict[tuple, list[dict[str, Any]]] = {}
    for cell in cells:
        basis = cell.get("basis")
        header = headers.get(cell.get("header_id"), "") if basis_counts.get(basis, 0) > 1 else ""
        key = (nutrient_key(cell), parent_key(cell, by_row), basis, header)
        keys.setdefault(key, []).append(cell)
    unique = {key: group[0] for key, group in keys.items() if len(group) == 1}
    ambiguous = {key for key, group in keys.items() if len(group) > 1}
    return unique, ambiguous


def _known(value: Any) -> dict[str, Any] | None:
    return value if isinstance(value, dict) else None


def servings_equal(truth: Any, candidate: Any) -> bool:
    t, c = _known(truth), _known(candidate)
    if t is None or c is None:
        return t is None and c is None
    return t.get("decimal_text") == c.get("decimal_text") and bool(t.get("approximate")) == bool(c.get("approximate"))


def serving_size_equal(truth: Any, candidate: Any) -> bool:
    t, c = _known(truth), _known(candidate)
    if t is None or c is None:
        return t is None and c is None
    return t.get("decimal_text") == c.get("decimal_text") and t.get("canonical_unit") == c.get("canonical_unit")


def strict_equal(expected: dict[str, Any], found: dict[str, Any] | None) -> bool:
    return bool(found) and all(
        (expected.get(field) or "=") == (found.get(field) or "=") if field == "comparator" else expected.get(field) == found.get(field)
        for field in ("decimal_text", "comparator", "canonical_unit", "basis")
    )


def effective_ready(candidate: dict[str, Any]) -> tuple[bool, dict[str, Any]]:
    """What the route would mark ready after the shared arithmetic policy."""
    check = arithmetic.check_table(candidate)
    ready = bool(candidate.get("would_mark_ready")) and not candidate.get("declined") and check["status"] != arithmetic.FAIL
    return ready, check


def score_case(candidate: dict[str, Any] | None, truth: dict[str, Any]) -> dict[str, Any]:
    """Score one route output against one truth record; returns counts and flags."""
    errors = validate_candidate(candidate) if candidate is not None else ["no candidate"]
    failed = bool(errors) or candidate is None
    # A failed output is scored as an empty, undeclined table so it stays in every denominator.
    output: dict[str, Any] = (
        {"declined": False, "cells": [], "headers": [], "serving_size": "unknown", "servings_per_pack": "unknown"}
        if failed or candidate is None
        else candidate
    )
    result: dict[str, Any] = {name: 0 for spec in METRICS.values() for name in spec[:2]}
    result.update(
        {
            "cases": 1,
            "failed": int(failed),
            "failure_reasons": errors,
            "declined": int(bool(output.get("declined"))),
            "false_declines": 0,
            "extra_cells": 0,
            "automatic_persistence": int(
                not failed
                and (
                    output.get("automatic_save") is not False
                    or output.get("ready_for_confirmation") is not False
                    or any(c.get("persistence_authorized") is not False for c in output.get("cells") or [])
                )
            ),
            "serving_size_exact": 0,
            "serving_size_known": 0,
        }
    )
    ready, check = effective_ready(output) if not failed else (False, {"status": arithmetic.NOT_CHECKABLE, "warnings": []})
    result["would_mark_ready_after_arithmetic"] = int(ready)
    result["energy_check"] = arithmetic.energy_status(output) if not failed else arithmetic.NOT_CHECKABLE
    result["arithmetic_status"] = check["status"]
    result["arithmetic_warnings"] = check.get("warnings", [])

    if truth.get("requires_decline"):
        result["declines_required"] = 1
        result["declines_correct"] = int(bool(output.get("declined")))
        result["false_ready"] = int(ready)
        result["full_table_exact"] = 0
        return result

    result["usable_tables"] = 1
    result["false_declines"] = int(bool(output.get("declined")))
    expected, truth_ambiguous = keyed_cells(truth)
    found, found_ambiguous = keyed_cells(output) if not output.get("declined") else ({}, set())
    all_exact = not truth_ambiguous
    for key, cell in expected.items():
        candidate_cell = None if key in found_ambiguous else found.get(key)
        all_exact = _count_expected(result, cell, candidate_cell) and all_exact
    # Duplicate same-basis columns without distinct printed headers never earn credit.
    for cell in truth.get("cells") or []:
        if keyed_key(cell, truth) in truth_ambiguous:
            _count_expected(result, cell, None)
    extra = [key for key in list(found) + list(found_ambiguous) if key not in expected]
    result["extra_cells"] = len(extra)
    if _known(truth.get("servings_per_pack")):
        result["servings_per_pack"] = 1
        result["servings_per_pack_exact"] = int(servings_equal(truth.get("servings_per_pack"), output.get("servings_per_pack")))
    truth_size = _known(truth.get("serving_size"))
    if truth_size is not None and truth_size.get("decimal_text"):
        result["serving_size_known"] = 1
        result["serving_size_exact"] = int(serving_size_equal(truth.get("serving_size"), output.get("serving_size")))
    table_exact = (
        not output.get("declined")
        and all_exact
        and not extra
        and not found_ambiguous
        and servings_equal(truth.get("servings_per_pack"), output.get("servings_per_pack"))
        and (not result["serving_size_known"] or result["serving_size_exact"])
    )
    result["tables_exact"] = int(table_exact)
    result["full_table_exact"] = int(table_exact)
    result["false_ready"] = int(ready and not table_exact)
    return result


def keyed_key(cell: dict[str, Any], table: dict[str, Any]) -> tuple:
    by_row = {c.get("row_id"): c for c in table.get("cells") or []}
    headers = _header_texts(table)
    basis_counts = Counter(h.get("basis") for h in table.get("headers") or [])
    basis = cell.get("basis")
    header = headers.get(str(cell.get("header_id")), "") if basis_counts.get(basis, 0) > 1 else ""
    return (nutrient_key(cell), parent_key(cell, by_row), basis, header)


def _count_expected(result: dict[str, Any], cell: dict[str, Any], found: dict[str, Any] | None) -> bool:
    product = cell.get("basis") != "reference_intake"
    exact = strict_equal(cell, found)
    result["all_cells"] += 1
    result["cells_bound"] += int(bool(found) and found.get("decimal_text") == cell.get("decimal_text"))
    if product:
        result["product_cells"] += 1
        result["cells_exact"] += int(exact)
        result["cells_unit_basis"] += int(
            bool(found) and found.get("canonical_unit") == cell.get("canonical_unit") and found.get("basis") == cell.get("basis")
        )
        if cell.get("comparator") in ("<", "<="):
            result["bounded_cells"] += 1
            result["bounds_exact"] += int(exact)
    conversion = cell.get("serving_conversion")
    if cell.get("basis") == "per_serving" and conversion not in NOT_A_CONVERSION:
        result["conversions"] += 1
        found_conversion = found.get("serving_conversion") if found else None
        result["conversions_exact"] += int(compact(found_conversion) == compact(conversion))
    return exact


def aggregate(results: list[dict[str, Any]], thresholds: dict[str, float]) -> dict[str, Any]:
    """Sum counts and compare each metric with its pre-registered bar.

    A zero denominator is reported as `no_denominator`, never as a pass.
    """
    totals: Counter = Counter()
    for result in results:
        for key, value in result.items():
            if isinstance(value, int) and not isinstance(value, bool):
                totals[key] += value
    metrics = {}
    for name, (numerator, denominator, threshold_key, direction) in METRICS.items():
        num, den = totals[numerator], totals[denominator]
        bar = thresholds.get(threshold_key)
        if direction == "max_count":
            verdict = "pass" if num <= (bar or 0) else "fail"
            metrics[name] = {"count": num, "denominator": den, "bar": f"<= {bar:g}", "verdict": verdict if den else "no_denominator"}
            continue
        if den == 0:
            metrics[name] = {"numerator": 0, "denominator": 0, "rate": None, "bar": bar, "verdict": "no_denominator"}
            continue
        rate = num / den
        metrics[name] = {
            "numerator": num,
            "denominator": den,
            "rate": round(rate, 4),
            "bar": bar,
            "verdict": "pass" if bar is not None and rate >= bar else "fail",
        }
    metrics["automatic_persistence"] = {
        "count": totals["automatic_persistence"],
        "verdict": "pass" if totals["automatic_persistence"] == 0 else "critical_fail",
    }
    energy = Counter(r.get("energy_check") for r in results)
    return {
        "cases": totals["cases"],
        "failed": totals["failed"],
        "false_declines": totals["false_declines"],
        "extra_cells": totals["extra_cells"],
        "serving_size": {"exact": totals["serving_size_exact"], "known": totals["serving_size_known"]},
        "energy_check_informing_only": dict(sorted(energy.items())),
        "metrics": metrics,
    }


def load_thresholds(contract_path: Path = HERE / "frozen-contract-v1.json") -> dict[str, float]:
    return json.loads(contract_path.read_text())["metrics"]
