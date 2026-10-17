#!/usr/bin/env python3
"""Validate `frozen-contract-v1.json`: closed bars, tolerances, stops and artefact hashes.

`--pin` rewrites the artefact hashes from the working tree. It is a development
convenience only; once the status is `frozen_for_untouched_run` pinning is refused.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
from pathlib import Path
from typing import Any

import openrouter_route

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[1]

EXPECTED_METRICS = {
    "numeric_cell_exact_minimum": 0.95,
    "row_header_binding_minimum": 0.98,
    "unit_and_basis_minimum": 1.0,
    "full_table_exact_minimum": 0.75,
    "serving_conversion_minimum": 0.98,
    "servings_per_pack_minimum": 0.98,
    "bound_preservation_minimum": 1.0,
    "correct_decline_minimum": 0.95,
    "false_ready_maximum": 0,
    "arithmetic_detection_minimum": 1.0,
}
PINNED = [
    "Tools/NutritionLabelCaptureEvaluation/candidate-schema-v1.json",
    "Tools/NutritionLabelCaptureEvaluation/candidate.py",
    "Tools/NutritionLabelCaptureEvaluation/score.py",
    "Tools/NutritionLabelCaptureEvaluation/arithmetic.py",
    "Tools/NutritionLabelCaptureEvaluation/budget.py",
    "Tools/NutritionLabelCaptureEvaluation/openrouter_route.py",
    "Tools/NutritionLabelCaptureEvaluation/requirements-dev.lock",
    "Tools/NutritionLabelCaptureEvaluation/cases.py",
    "Tools/NutritionLabelCaptureEvaluation/inspect_task.py",
    "Tools/NutritionLabelCaptureEvaluation/requirements.txt",
    "Tools/NutritionLabelCaptureEvaluation/synthetic/render.py",
    "Tools/NutritionLabelCaptureEvaluation/build_cases.py",
    "Tools/NutritionLabelCaptureEvaluation/synthetic/development-cases-v1.jsonl",
    "Tools/NutritionLabelCaptureEvaluation/fixtures/off-taiwan-manifest-v1.json",
    "Tools/NutritionLabelCaptureEvaluation/fixtures/fda-188-source-v1.json",
    "Tools/NutritionLabelCaptureEvaluation/fixtures/ground-truth-off-taiwan-development-v1.json",
    "Tools/NutritionLabelCaptureEvaluation/openrouter/label-image-extraction-instruction-v1.txt",
    "Tools/NutritionLabelCaptureEvaluation/openrouter/label-image-wire-schema-v1.json",
    "Packages/FoodLedgerKit/Sources/NutritionLabelParsing/LabelCaptureCandidate.swift",
    "Packages/FoodLedgerKit/Sources/NutritionLabelParsing/LabelVocabulary.swift",
    "Packages/FoodLedgerKit/Sources/NutritionLabelParsing/NutritionLabelTextParser.swift",
    "Packages/FoodLedgerKit/Tools/NutritionLabelTextParse/main.swift",
]


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def count_unions(node: Any) -> int:
    """Union-bearing parameters: anyOf/oneOf, or a type list."""
    if isinstance(node, dict):
        own = int("anyOf" in node or "oneOf" in node or isinstance(node.get("type"), list))
        return own + sum(count_unions(value) for value in node.values())
    if isinstance(node, list):
        return sum(count_unions(item) for item in node)
    return 0


def validate(contract: dict[str, Any], root: Path = REPO) -> list[str]:
    errors = []
    if contract.get("contract_version") != "label-capture-evaluation-v1":
        errors.append("contract_version must be label-capture-evaluation-v1")
    if contract.get("metrics") != EXPECTED_METRICS:
        errors.append("metrics differ from the plan's pre-registered bars")
    tolerance = contract.get("arithmetic", {}).get("tolerance", {})
    if tolerance != {
        "uk": {"absolute_kcal": 15, "relative": 0.10},
        "taiwan": {"absolute_kcal": 15, "relative": 0.10},
        "us": {"absolute_kcal": 20, "relative": 0.20},
    }:
        errors.append("arithmetic tolerances differ from decision 10")
    if contract.get("arithmetic", {}).get("kj_kcal_relative_tolerance") != 0.02:
        errors.append("kJ / kcal tolerance must be 2%")
    route_c = contract.get("route_c", {})
    if route_c.get("per_call_stop_usd") != 0.05 or route_c.get("total_stop_usd") != 25 or route_c.get("unknown_cost_calls_allowed") != 3:
        errors.append("route C spend stops differ from decision 9")
    if route_c.get("retries") != 0 or route_c.get("max_output_tokens") != 4096 or route_c.get("timeout_seconds") != 90:
        errors.append("route C call limits differ from the plan")
    if contract.get("status") == "development_phase_1" and route_c.get("enabled") is not False:
        errors.append("route C must stay disabled in phase 1")
    provider = route_c.get("provider_block", {})
    if provider != openrouter_route.provider_block("<endpoint>"):
        errors.append("route C provider block must pin one endpoint, deny collection, require ZDR and forbid fallbacks")
    if route_c.get("never_sees_untouched_truth_or_drafts") is not True:
        errors.append("route C must never see untouched truth or drafts")
    drafting = contract.get("untouched_truth_drafting", {})
    if drafting.get("route_c_never_sees_untouched_truth_or_drafts") is not True or "Qwen" not in drafting.get("pass_1", ""):
        errors.append("untouched truth drafting must follow owner decision A")
    route_c_models = " ".join(route_c.get("models_in_run_order", []) + route_c.get("reserve_models", []))
    if "Qwen" in route_c_models:
        errors.append("the untouched-truth drafting model cannot also be a route C model")
    refill = contract.get("corpus", {}).get("off_taiwan", {}).get("refill_rule", {})
    if refill.get("batch_stop_bytes") != 5_000_000 or "61 to 87" not in refill.get("approved_orders", ""):
        errors.append("Taiwan refill rule must match owner decision B")
    wire = root / "Tools/NutritionLabelCaptureEvaluation/openrouter/label-image-wire-schema-v1.json"
    if wire.exists() and count_unions(json.loads(wire.read_text())) > 16:
        errors.append("route C wire schema exceeds 16 union-bearing parameters")
    taiwan = contract.get("corpus", {}).get("off_taiwan", {})
    if (taiwan.get("selected"), taiwan.get("development"), taiwan.get("untouched")) != (60, 20, 40):
        errors.append("Taiwan photo split must be 60 = 20 development + 40 untouched")
    manifest = root / taiwan.get("manifest", "")
    if not manifest.is_file() or sha256(manifest) != taiwan.get("manifest_sha256"):
        errors.append("Taiwan manifest hash does not match the contract")
    artefacts = contract.get("frozen_artefacts", {})
    if sorted(artefacts) != sorted(PINNED):
        errors.append("frozen_artefacts must pin exactly the listed artefacts")
    for path, expected in artefacts.items():
        target = root / path
        if not target.is_file():
            errors.append(f"pinned artefact missing: {path}")
        elif sha256(target) != expected:
            errors.append(f"pinned artefact changed: {path}")
    return errors


def pin(contract_path: Path) -> None:
    contract = json.loads(contract_path.read_text())
    if contract.get("status") == "frozen_for_untouched_run":
        raise SystemExit("refusing to re-pin a contract frozen for the untouched run")
    contract["corpus"]["off_taiwan"]["manifest_sha256"] = sha256(REPO / contract["corpus"]["off_taiwan"]["manifest"])
    contract["frozen_artefacts"] = {path: sha256(REPO / path) for path in PINNED}
    contract_path.write_text(json.dumps(contract, indent=2, ensure_ascii=False) + "\n")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("contract", type=Path)
    parser.add_argument("--pin", action="store_true")
    args = parser.parse_args()
    if args.pin:
        pin(args.contract)
    errors = validate(json.loads(args.contract.read_text()))
    for error in errors:
        print(error, file=sys.stderr)
    print("contract valid" if not errors else f"{len(errors)} contract error(s)")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
