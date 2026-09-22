#!/usr/bin/env python3
"""Freeze verified human annotations without opening the Vision gate."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
from typing import Any

from corpus import validate_ground_truth
from review_server import FAMILIES, validate_annotation


def canonical_json(value: Any) -> bytes:
    return (json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")) + "\n").encode()


def finalize(selection: dict[str, Any], review_manifest: dict[str, Any], annotations_dir: Path) -> dict[str, Any]:
    if selection["counts"] != {"tuning": 60, "untouched_gate": 40}:
        raise ValueError("sealed selection is not the frozen 60/40 split")
    sealed_by_id = {panel["panel_id"]: panel for panel in selection["panels"]}
    reviewed = []
    family_counts = {family: 0 for family in FAMILIES}
    split_counts = {"tuning": 0, "untouched_gate": 0}
    for panel in review_manifest["panels"]:
        annotation_path = annotations_dir / f"{panel['review_index']:03d}.json"
        if not annotation_path.exists():
            raise ValueError(f"panel {panel['review_index']} is not reviewed")
        annotation = json.loads(annotation_path.read_text())
        validate_annotation(annotation, panel)
        sealed = sealed_by_id.get(panel["panel_id"])
        if not sealed or sealed["image_sha256"] != panel["image_sha256"]:
            raise ValueError(f"sealed identity mismatch for {panel['panel_id']}")
        ground_truth = {
            "verification_status": annotation["verification_status"],
            "full_transcript": annotation["full_transcript"],
            "cells": annotation["cells"],
            "requires_decline": annotation["requires_decline"],
            "decline_reason": annotation["decline_reason"],
            "correction_seconds": annotation["correction_seconds"],
            "review": {
                "reviewer": annotation["reviewer"],
                "verified_at": annotation["verified_at"],
                "verified_against_image_sha256": panel["image_sha256"],
            },
        }
        validation_panel = {"panel_id": panel["panel_id"], "image_sha256": panel["image_sha256"], "ground_truth": ground_truth}
        validate_ground_truth(validation_panel)
        split_counts[sealed["split"]] += 1
        for family in annotation["families"]:
            family_counts[family] += 1
        reviewed.append({
            "panel_id": panel["panel_id"],
            "image_sha256": panel["image_sha256"],
            "image_url": panel["image_url"],
            "product_code": panel["product_code"],
            "product_name": panel["product_name"],
            "split": sealed["split"],
            "families": annotation["families"],
            "ground_truth": ground_truth,
        })
    if split_counts != {"tuning": 60, "untouched_gate": 40}:
        raise ValueError(f"reviewed split mismatch: {split_counts}")
    missing = sorted(family for family, count in family_counts.items() if count == 0)
    if missing:
        raise ValueError(f"review does not cover required families: {', '.join(missing)}")
    return {
        "schema_version": 1,
        "review_contract": "printed-nutrition-ocr-human-review-v1",
        "selection_sha256": hashlib.sha256(canonical_json(selection)).hexdigest(),
        "counts": split_counts,
        "family_counts": family_counts,
        "panels": reviewed,
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--selection", required=True, type=Path)
    parser.add_argument("--workspace", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    selection = json.loads(args.selection.read_text())
    review_manifest = json.loads((args.workspace / "review-manifest.json").read_text())
    result = finalize(selection, review_manifest, args.workspace / "annotations")
    args.output.write_bytes(canonical_json(result))
    print(f"frozen_ground_truth_sha256={hashlib.sha256(args.output.read_bytes()).hexdigest()}")


if __name__ == "__main__":
    main()
