#!/usr/bin/env python3
"""Validate the pre-registered v2 public OCR contract and split rule."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
from pathlib import Path
from typing import Any


REQUIRED_FAMILIES = {
    "bilingual", "bound", "crumpled", "curved", "difficult_crop", "flat",
    "glossy", "missing_row", "multi_column", "nested_rows", "per_100g",
    "per_100ml", "per_serving", "salt", "small_font", "sodium",
}
METRIC_FLOORS = {
    "numeric_cell_exact_minimum": 0.95,
    "row_header_binding_minimum": 0.98,
    "full_table_exact_minimum": 0.75,
    "unit_and_basis_minimum": 1.0,
    "bound_preservation_minimum": 1.0,
    "serving_conversion_minimum": 0.98,
    "correct_decline_minimum": 0.95,
    "arithmetic_detection_minimum": 1.0,
}
SPLIT_ALGORITHM = "v2-eligible-100-sha256-order-v1"
SPLIT_DOMAIN = "printed-panel-v2-gate-v1:"


def validate(contract: dict[str, Any]) -> None:
    if contract.get("schema_version") != 2 or contract.get("contract_version") != "printed-nutrition-ocr-evaluation-v2":
        raise ValueError("unsupported v2 contract")
    if contract.get("status") != "pre_registered_no_v2_gate_run":
        raise ValueError("contract must not claim a v2 gate run")
    corpus = contract["corpus"]
    minima = {
        "minimum_new_candidates": 140,
        "minimum_independently_verified_panels": 100,
        "tuning_panels": 60,
        "untouched_gate_panels": 40,
        "minimum_usable_untouched_tables": 30,
        "minimum_untouched_declines": 5,
        "minimum_untouched_bounded_cells": 10,
        "minimum_untouched_serving_conversions": 20,
    }
    if any(corpus.get(key, 0) < value for key, value in minima.items()):
        raise ValueError("v2 corpus or denominator minimum weakened")
    if (corpus["minimum_independently_verified_panels"], corpus["tuning_panels"],
            corpus["untouched_gate_panels"]) != (100, 60, 40):
        raise ValueError("the versioned selection rule requires exactly 60/40 of 100")
    if (corpus.get("permitted_source") != "Open Food Facts revision-pinned public nutrition images"
            or corpus.get("country_tag") != "en:united-kingdom"
            or not corpus.get("source_licence_url", "").startswith("https://openfoodfacts.")):
        raise ValueError("unsupported public source or licence")
    if set(corpus["required_families"]) != REQUIRED_FAMILIES or len(corpus["required_families"]) != len(REQUIRED_FAMILIES):
        raise ValueError("required family coverage changed")
    if (corpus.get("synthetic_panels_permitted") or not corpus.get("real_panels_only")
            or not corpus.get("exclude_all_v1_and_v2_development_panel_ids_and_image_hashes")
            or not corpus.get("ground_truth_requires_independent_image_first_visual_verification")
            or not corpus.get("assistant_or_source_ocr_cannot_be_ground_truth")
            or not corpus.get("declined_images_remain_in_scoring_denominators")):
        raise ValueError("v2 corpus provenance weakened")

    selection = contract["selection"]
    if selection.get("algorithm_id") != SPLIT_ALGORITHM or not all(selection.get(key) for key in (
        "freeze_selected_identities_and_split_before_v2_recognition",
        "no_post_outcome_replacement_or_rerun", "one_time_untouched_gate",
    )):
        raise ValueError("v2 split or one-time gate weakened")
    schema = contract["candidate_schema"]
    if set(schema["basis_values"]) != {"per_100g", "per_100ml", "per_serving", "reference_intake"}:
        raise ValueError("candidate basis schema changed")
    if set(schema["bound_comparators"]) != {"<", "<="}:
        raise ValueError("candidate bound schema changed")
    if not all(schema.get(key) for key in (
        "unknown_must_remain_explicit", "reference_intake_constants_are_not_product_amounts",
        "unprinted_serving_conversion_cannot_be_inferred",
    )):
        raise ValueError("candidate correctness invariant weakened")
    required_cells = {
        "row_id", "parent_row_id", "header_id", "basis", "printed_text", "comparator",
        "decimal_text", "unit", "serving_conversion", "persistence_authorized", "requires_user_selection",
    }
    if set(schema["required_cell_fields"]) != required_cells:
        raise ValueError("candidate cell schema changed")
    if (schema.get("required_status") != "user_selection_only"
            or schema.get("required_ready_for_confirmation") is not False
            or schema.get("required_automatic_save") is not False
            or schema.get("required_candidate_persistence_authorized") is not False
            or schema.get("required_candidate_requires_user_selection") is not True):
        raise ValueError("candidate acceptance boundary weakened")
    required_top_level = {
        "schema_version", "image_sha256", "status", "candidates", "unresolved_reasons",
        "ready_for_confirmation", "unresolved_warning", "declined", "automatic_save",
    }
    if set(schema["required_top_level_fields"]) != required_top_level:
        raise ValueError("candidate top-level schema weakened")

    metrics = contract["metrics"]
    if set(metrics) != set(METRIC_FLOORS) | {"false_ready_maximum"}:
        raise ValueError("v2 metric set changed")
    if any(not isinstance(metrics[key], (int, float)) or not 0 <= metrics[key] <= 1 or metrics[key] < floor
           for key, floor in METRIC_FLOORS.items()):
        raise ValueError("v2 metric threshold weakened")
    if metrics["false_ready_maximum"] != 0.0:
        raise ValueError("false-ready tolerance must remain zero")
    scoring = contract["scoring"]
    required_scoring = {
        "match_key", "normalization", "numeric_cell_exact_denominator", "full_table_exact_denominator",
        "bound_denominator", "serving_conversion_denominator", "false_ready",
        "correct_decline_denominator", "arithmetic_faults", "zero_or_missing_critical_denominator",
    }
    if set(scoring) != required_scoring:
        raise ValueError("v2 scoring field set changed")
    if not all(isinstance(value, str) and value.strip() for value in scoring.values()):
        raise ValueError("scoring denominator or matching rule missing")

    policy = contract["safety_policy"]
    if any(policy.get(key) for key in ("automatic_save", "confidence_can_authorize_persistence", "physical_camera_claims")):
        raise ValueError("unsafe v2 promotion policy")
    if not all(policy.get(key) for key in (
        "candidate_cells_require_explicit_user_selection", "side_by_side_original_image_required",
        "failed_or_unknown_cells_remain_explicit", "bounds_remain_intervals",
    )) or policy.get("personal_case_gate") != "deferred":
        raise ValueError("v2 manual-selection or personal-case boundary weakened")
    recommendation = contract["recommendation"]
    if not recommendation.get("all_metric_and_safety_gates_required_for_93_eligibility") or not recommendation.get(
        "public_gate_cannot_by_itself_close_93_or_promote_automatic_acceptance"
    ):
        raise ValueError("v2 recommendation boundary weakened")
    if recommendation.get("options") != [
        "decline", "continue_evaluation_only", "eligible_for_93_manual_selection_review",
    ]:
        raise ValueError("v2 recommendation options changed")


def select_split(
    contract: dict[str, Any], eligible_panels: list[dict[str, str]], *,
    excluded_panel_ids: set[str], excluded_image_hashes: set[str],
) -> dict[str, str]:
    """Select and split eligible identities before review or v2 recognition."""
    validate(contract)
    if len(eligible_panels) < contract["corpus"]["minimum_new_candidates"]:
        raise ValueError("too few new eligible public candidates")
    ids = [item["panel_id"] for item in eligible_panels]
    hashes = [item["image_sha256"] for item in eligible_panels]
    if len(set(ids)) != len(ids) or len(set(hashes)) != len(hashes):
        raise ValueError("duplicate eligible panel or image")
    if set(ids) & excluded_panel_ids or set(hashes) & excluded_image_hashes:
        raise ValueError("eligible inventory reuses exposed v1 or v2 development evidence")
    if any(not isinstance(value, str) or not re.fullmatch(r"[0-9a-f]{64}", value) for value in hashes):
        raise ValueError("unverified image SHA-256 identity")
    if any(not isinstance(value, str) or not value for value in ids):
        raise ValueError("missing panel identity")
    ordered = sorted(eligible_panels, key=lambda item: (
        hashlib.sha256(f"{SPLIT_DOMAIN}{item['image_sha256']}:{item['panel_id']}".encode()).digest(),
        item["panel_id"],
    ))
    selected = ordered[:contract["corpus"]["minimum_independently_verified_panels"]]
    tuning_count = contract["corpus"]["tuning_panels"]
    return {
        item["panel_id"]: "tuning" if index < tuning_count else "untouched_gate"
        for index, item in enumerate(selected)
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("contract", type=Path)
    args = parser.parse_args()
    validate(json.loads(args.contract.read_text()))
    print("v2_contract_valid=true; untouched_gate_unopened=true")


if __name__ == "__main__":
    main()
