#!/usr/bin/env python3
"""Freeze a verified public development review without creating a v2 gate."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
from typing import Any

from review_server import canonical_json, validate_annotation


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def build_snapshot(workspace: Path, approval_path: Path) -> dict[str, Any]:
    manifest_bytes = (workspace / "review-manifest.json").read_bytes()
    manifest = json.loads(manifest_bytes)
    approval_bytes = approval_path.read_bytes()
    approval = json.loads(approval_bytes)
    panels = manifest.get("panels", [])
    if manifest.get("review_status") != "development_review_not_gate" or len(panels) != 40:
        raise ValueError("expected the 40-panel v2 public development review, not an acceptance gate")
    if approval.get("decision") != "all_saved_declines_final" or not approval.get("source"):
        raise ValueError("explicit final-decline approval is required")

    indices = [panel["review_index"] for panel in panels]
    if sorted(indices) != list(range(1, 41)):
        raise ValueError("review indices must be exactly 1 through 40")
    if len({panel["panel_id"] for panel in panels}) != 40 or len({panel["image_sha256"] for panel in panels}) != 40:
        raise ValueError("duplicate panel or image identity")

    resolved = approval.get("final_reason_overrides", {})
    if not isinstance(resolved, dict):
        raise ValueError("final reason overrides must be an object")
    result_panels = []
    decline_indices = []
    unchanged_drafts = 0
    for panel in panels:
        index = panel["review_index"]
        image_file = panel["image_file"]
        if Path(image_file).name != image_file:
            raise ValueError(f"invalid image filename at panel {index}")
        image_bytes = (workspace / "images" / image_file).read_bytes()
        if sha256(image_bytes) != panel["image_sha256"]:
            raise ValueError(f"image hash mismatch at panel {index}")
        annotation_bytes = (workspace / "annotations" / f"{index:03d}.json").read_bytes()
        annotation = json.loads(annotation_bytes)
        validate_annotation(annotation, panel)
        if annotation.get("verification_status") != "independently_verified" or not annotation.get("verified_at"):
            raise ValueError(f"saved visual review is incomplete at panel {index}")
        if annotation["requires_decline"]:
            decline_indices.append(index)
        reason = resolved.get(str(index), annotation["decline_reason"])
        if str(index) in resolved and (not annotation["requires_decline"] or not str(reason).strip()):
            raise ValueError(f"invalid decline reason override at panel {index}")
        draft_path = workspace / "assistant_drafts" / f"{index:03d}.json"
        if draft_path.exists():
            draft = json.loads(draft_path.read_bytes())
            fields = ("full_transcript", "cells", "families", "requires_decline", "decline_reason")
            unchanged_drafts += all(annotation.get(field) == draft.get(field) for field in fields)
        result_panels.append({
            "review_index": index,
            "panel_id": panel["panel_id"],
            "image_sha256": panel["image_sha256"],
            "image_url": panel["image_url"],
            "product_code": panel["product_code"],
            "product_name": panel["product_name"],
            "annotation_sha256": sha256(annotation_bytes),
            "review": {
                "reviewer": annotation["reviewer"],
                "verified_at": annotation["verified_at"],
                "verification_status": annotation["verification_status"],
                "correction_seconds": annotation["correction_seconds"],
            },
            "ground_truth": {
                "full_transcript": annotation["full_transcript"],
                "cells": annotation["cells"],
                "families": annotation["families"],
                "requires_decline": annotation["requires_decline"],
                "decline_reason": reason,
            },
            "original_decline_reason": annotation["decline_reason"] if str(index) in resolved else None,
        })

    approved_indices = approval.get("approved_panel_indices")
    if approved_indices != decline_indices:
        raise ValueError("approved decline indices do not match the saved reviews")
    if not set(resolved).issubset({str(index) for index in decline_indices}):
        raise ValueError("reason override targets a non-declined panel")
    return {
        "schema_version": 1,
        "kind": "public_development_review_freeze",
        "acceptance_gate": False,
        "untouched_personal_case": "deferred",
        "review_manifest_sha256": sha256(manifest_bytes),
        "decline_approval_sha256": sha256(approval_bytes),
        "decline_approval_source": approval["source"],
        "counts": {"panels": 40, "usable_tables": 40 - len(decline_indices), "declines": len(decline_indices)},
        "audit": {"annotations_matching_assistant_drafts": unchanged_drafts},
        "panels": result_panels,
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--workspace", required=True, type=Path)
    parser.add_argument("--approval", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    snapshot = build_snapshot(args.workspace, args.approval)
    data = canonical_json(snapshot)
    with args.output.open("xb") as output:
        output.write(data)
    print(f"frozen_development_review_sha256={sha256(data)}")
    print(f"usable={snapshot['counts']['usable_tables']} declined={snapshot['counts']['declines']}")


if __name__ == "__main__":
    main()
