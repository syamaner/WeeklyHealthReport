#!/usr/bin/env python3
"""Validate the closed issue #88 evaluation contract."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any


def validate(contract: dict[str, Any]) -> None:
    if contract["schema_version"] != 1:
        raise ValueError("unsupported contract schema")
    corpus = contract["corpus"]
    if corpus["minimum_panels"] < 100:
        raise ValueError("the corpus minimum cannot be below 100")
    if corpus["minimum_untouched_gate_panels"] < 40:
        raise ValueError("the untouched gate must contain at least 40 panels")
    if corpus["synthetic_panels_permitted"]:
        raise ValueError("synthetic panels cannot satisfy issue #88")
    if not corpus["ground_truth_requires_independent_visual_verification"]:
        raise ValueError("source metadata or OCR cannot be ground truth")

    policy = contract["policy"]
    forbidden_true = ("automatic_save", "confidence_can_authorize_persistence", "physical_camera_claims")
    if any(policy[key] for key in forbidden_true):
        raise ValueError("unsafe promotion policy")
    if not policy["side_by_side_confirmation_required"]:
        raise ValueError("side-by-side confirmation is mandatory")

    metrics = contract["metrics"]
    for key in ("arithmetic_detection_minimum", "bound_preservation_minimum", "unit_and_basis_minimum"):
        if metrics[key] != 1.0:
            raise ValueError(f"critical metric {key} must remain exact")
    if metrics["false_save_maximum"] != 0.0:
        raise ValueError("false-save tolerance must remain zero")
    for key, value in metrics.items():
        if not 0.0 <= value <= 1.0:
            raise ValueError(f"metric {key} is outside [0, 1]")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("contract", type=Path)
    args = parser.parse_args()
    validate(json.loads(args.contract.read_text()))


if __name__ == "__main__":
    main()
