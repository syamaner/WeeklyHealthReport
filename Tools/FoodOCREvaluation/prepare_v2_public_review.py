#!/usr/bin/env python3
"""Prepare a blinded, image-first review pack from frozen public v2 identities."""

from __future__ import annotations

import argparse
import hashlib
import json
import shutil
from pathlib import Path
from typing import Any

from acquire_v2_public import canonical_json


ORDER_DOMAIN = "issue93-v2-image-first-review-v1:"


def prepare(selection: dict[str, Any], image_root: Path, workspace: Path) -> dict[str, Any]:
    if selection.get("status") != "identities_and_split_frozen_no_ground_truth_or_gate":
        raise ValueError("frozen v2 identities are required")
    if len(selection.get("panels", [])) != 100:
        raise ValueError("frozen v2 selection must contain exactly 100 panels")
    if workspace.exists():
        raise ValueError("review workspace already exists; refusing overwrite")
    ordered = sorted(selection["panels"], key=lambda panel: hashlib.sha256(
        f"{ORDER_DOMAIN}{panel['panel_id']}".encode()).digest())
    workspace.mkdir(parents=True)
    (workspace / "images").mkdir()
    (workspace / "annotations").mkdir()
    review_panels = []
    for index, panel in enumerate(ordered, start=1):
        original = image_root / panel["local_image"]
        digest = hashlib.sha256(original.read_bytes()).hexdigest()
        if digest != panel["image_sha256"]:
            raise ValueError(f"raw image hash mismatch: {panel['panel_id']}")
        image_file = f"{index:03d}-{digest[:12]}.jpg"
        shutil.copyfile(original, workspace / "images" / image_file)
        review_panels.append({
            "review_index": index,
            "panel_id": panel["panel_id"],
            "product_name": panel.get("product_name_hint"),
            "product_code": panel["product_code"],
            "image_file": image_file,
            "image_sha256": digest,
            "review_mode": "image_first",
            "draft_source": "none; inspect the image itself",
            "draft_transcript": "",
            "draft_cells": [],
            "proposed_families": [],
        })
    manifest = {
        "schema_version": 1,
        "review_label": "WeeklyHealthReport · issue #93 public v2",
        "review_description": "Image-first visual ground truth. No OCR draft is shown; the frozen evaluation split is hidden and the v2 gate is unopened.",
        "review_status": "v2_frozen_image_first_ground_truth_pending",
        "blinded": True,
        "frozen_selection_sha256": hashlib.sha256(canonical_json(selection)).hexdigest(),
        "panels": review_panels,
    }
    (workspace / "review-manifest.json").write_bytes(canonical_json(manifest))
    return manifest


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--selection", type=Path, required=True)
    parser.add_argument("--image-root", type=Path, required=True)
    parser.add_argument("--workspace", type=Path, required=True)
    args = parser.parse_args()
    manifest = prepare(json.loads(args.selection.read_text()), args.image_root, args.workspace)
    print(f"image_first_review_ready={len(manifest['panels'])}; OCR_draft=false; gate_unopened=true")


if __name__ == "__main__":
    main()
