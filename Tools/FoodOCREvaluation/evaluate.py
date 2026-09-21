#!/usr/bin/env python3
"""Score frozen issue #88 panel outcomes without weakening safety gates."""

from __future__ import annotations

import argparse
import hashlib
import json
import statistics
from collections import Counter
from pathlib import Path
from typing import Any

from corpus import validate_manifest
from validate_contract import validate as validate_contract


def canonical_json(value: Any) -> bytes:
    return (json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")) + "\n").encode()


def file_sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def cell_key(cell: dict[str, Any]) -> tuple[str, str]:
    return cell["row_id"], cell["header_id"]


def semantic_value(cell: dict[str, Any]) -> tuple[Any, ...]:
    return cell.get("comparator"), cell.get("decimal_text"), cell.get("unit")


def score_panel(panel: dict[str, Any], outcome: dict[str, Any]) -> dict[str, Any]:
    truth = panel["ground_truth"]
    expected = {cell_key(cell): cell for cell in truth["cells"]}
    actual = {cell_key(cell): cell for cell in outcome.get("cells", [])}
    exact_cells = 0
    correct_bindings = 0
    correct_units_and_bases = 0
    bound_total = 0
    bound_exact = 0
    conversion_total = 0
    conversion_exact = 0

    for key, reference in expected.items():
        candidate = actual.get(key)
        if candidate is not None:
            correct_bindings += 1
            if candidate.get("unit") == reference.get("unit") and candidate.get("basis") == reference.get("basis"):
                correct_units_and_bases += 1
            if semantic_value(candidate) == semantic_value(reference):
                exact_cells += 1
        if reference.get("comparator") is not None:
            bound_total += 1
            if candidate is not None and candidate.get("comparator") == reference.get("comparator"):
                bound_exact += 1
        if reference.get("serving_conversion") is not None:
            conversion_total += 1
            if candidate is not None and candidate.get("serving_conversion") == reference.get("serving_conversion"):
                conversion_exact += 1

    expected_keys = set(expected)
    actual_keys = set(actual)
    table_exact = expected_keys == actual_keys and all(
        semantic_value(expected[key]) == semantic_value(actual[key])
        and expected[key].get("basis") == actual[key].get("basis")
        and expected[key].get("parent_row_id") == actual[key].get("parent_row_id")
        for key in expected_keys
    )
    wrong_or_unbound = any(
        key not in expected
        or semantic_value(cell) != semantic_value(expected[key])
        or cell.get("basis") != expected[key].get("basis")
        for key, cell in actual.items()
    ) or bool(expected_keys - actual_keys)
    false_save = bool(
        wrong_or_unbound
        and outcome.get("ready_for_confirmation")
        and not outcome.get("unresolved_warning")
    )
    return {
        "expected_cells": len(expected),
        "exact_cells": exact_cells,
        "correct_bindings": correct_bindings,
        "correct_units_and_bases": correct_units_and_bases,
        "bound_total": bound_total,
        "bound_exact": bound_exact,
        "conversion_total": conversion_total,
        "conversion_exact": conversion_exact,
        "table_exact": table_exact,
        "false_save": false_save,
        "decline_expected": bool(truth.get("requires_decline")),
        "declined": bool(outcome.get("declined")),
        "arithmetic_faults": len(outcome.get("arithmetic_faults", [])),
        "arithmetic_faults_detected": sum(bool(item.get("detected")) for item in outcome.get("arithmetic_faults", [])),
        "correction_seconds": outcome.get("correction_seconds"),
    }


def ratio(numerator: int, denominator: int) -> float | None:
    return numerator / denominator if denominator else None


def evaluate(contract: dict[str, Any], manifest: dict[str, Any], outcomes: dict[str, Any]) -> dict[str, Any]:
    validate_contract(contract)
    validate_manifest(manifest, contract, require_complete=True)
    if outcomes.get("schema_version") != 1:
        raise ValueError("unsupported outcome schema")
    by_id = {item["panel_id"]: item for item in outcomes.get("panels", [])}
    selected = [panel for panel in manifest["panels"] if panel["split"] == "untouched_gate"]
    if set(by_id) != {panel["panel_id"] for panel in selected}:
        raise ValueError("outcomes must contain exactly the untouched-gate panel IDs")

    scores = [score_panel(panel, by_id[panel["panel_id"]]) for panel in selected]
    totals = Counter()
    for score in scores:
        for key in (
            "expected_cells", "exact_cells", "correct_bindings", "correct_units_and_bases",
            "bound_total", "bound_exact", "conversion_total", "conversion_exact",
            "table_exact", "false_save", "decline_expected", "arithmetic_faults",
            "arithmetic_faults_detected",
        ):
            totals[key] += score[key]
    decline_correct = sum(score["decline_expected"] and score["declined"] for score in scores)
    correction_times = [float(score["correction_seconds"]) for score in scores if score["correction_seconds"] is not None]
    metrics = {
        "numeric_cell_exact": ratio(totals["exact_cells"], totals["expected_cells"]),
        "row_header_binding": ratio(totals["correct_bindings"], totals["expected_cells"]),
        "full_table_exact": ratio(totals["table_exact"], len(scores)),
        "unit_and_basis": ratio(totals["correct_units_and_bases"], totals["expected_cells"]),
        "bound_preservation": ratio(totals["bound_exact"], totals["bound_total"]),
        "serving_conversion": ratio(totals["conversion_exact"], totals["conversion_total"]),
        "false_save": ratio(totals["false_save"], len(scores)),
        "correct_decline": ratio(decline_correct, totals["decline_expected"]),
        "arithmetic_detection": ratio(totals["arithmetic_faults_detected"], totals["arithmetic_faults"]),
        "correction_seconds": {
            "observed_panels": len(correction_times),
            "median": statistics.median(correction_times) if correction_times else None,
            "maximum": max(correction_times) if correction_times else None,
        },
    }
    thresholds = contract["metrics"]
    gates = {
        "numeric_cell_exact": metrics["numeric_cell_exact"] is not None and metrics["numeric_cell_exact"] >= thresholds["numeric_cell_exact_minimum"],
        "row_header_binding": metrics["row_header_binding"] is not None and metrics["row_header_binding"] >= thresholds["row_header_binding_minimum"],
        "full_table_exact": metrics["full_table_exact"] is not None and metrics["full_table_exact"] >= thresholds["full_table_exact_minimum"],
        "unit_and_basis": metrics["unit_and_basis"] is not None and metrics["unit_and_basis"] >= thresholds["unit_and_basis_minimum"],
        "bound_preservation": metrics["bound_preservation"] is not None and metrics["bound_preservation"] >= thresholds["bound_preservation_minimum"],
        "serving_conversion": metrics["serving_conversion"] is not None and metrics["serving_conversion"] >= thresholds["serving_conversion_minimum"],
        "false_save": metrics["false_save"] is not None and metrics["false_save"] <= thresholds["false_save_maximum"],
        "correct_decline": metrics["correct_decline"] is not None and metrics["correct_decline"] >= thresholds["correct_decline_minimum"],
        "arithmetic_detection": metrics["arithmetic_detection"] is not None and metrics["arithmetic_detection"] >= thresholds["arithmetic_detection_minimum"],
        "correction_time_observed_for_every_panel": len(correction_times) == len(scores),
    }
    critical = all(gates[key] for key in ("false_save", "unit_and_basis", "bound_preservation", "arithmetic_detection"))
    if all(gates.values()):
        decision = "promotion_to_93"
    elif critical:
        decision = "bounded_promotion"
    else:
        decision = "decline"
    return {
        "schema_version": 1,
        "contract_version": contract["contract_version"],
        "scope": "untouched_gate",
        "fixture_counts": {
            "panels": len(scores),
            "numeric_cells": totals["expected_cells"],
            "bounded_cells": totals["bound_total"],
            "serving_conversions": totals["conversion_total"],
            "decline_panels": totals["decline_expected"],
            "arithmetic_faults": totals["arithmetic_faults"],
        },
        "metrics": metrics,
        "gates": gates,
        "recommendation": {
            "decision": decision,
            "automatic_save": False,
            "side_by_side_confirmation_required": True,
        },
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--contract", required=True, type=Path)
    parser.add_argument("--manifest", required=True, type=Path)
    parser.add_argument("--outcomes", required=True, type=Path)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    contract = json.loads(args.contract.read_text())
    manifest = json.loads(args.manifest.read_text())
    outcomes = json.loads(args.outcomes.read_text())
    report = canonical_json(evaluate(contract, manifest, outcomes))
    if args.output:
        args.output.write_bytes(report)
    else:
        print(report.decode(), end="")


if __name__ == "__main__":
    main()
