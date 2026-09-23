#!/usr/bin/env python3
"""Prepare an image-first review of unused public panels, not a v2 gate."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import tempfile
from pathlib import Path
from typing import Any, Callable

from acquire import request_bytes
from build_annotation_draft import propose_semantic_families
from prepare_review import bases_from_text, cells_from_text, tesseract_candidates, transcript_score
from pregate_v2 import audit_candidates

ORDER_SEED = "issue93-v2-development-review-order-v1"


def canonical_json(value: Any) -> bytes:
    return (json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")) + "\n").encode()


def checked_image(path: Path, expected_hash: str, fetch: Callable[[str], bytes], url: str) -> None:
    if path.exists():
        actual = hashlib.sha256(path.read_bytes()).hexdigest()
        if actual != expected_hash:
            raise ValueError(f"existing image hash mismatch: {path.name}")
        return
    image = fetch(url)
    if hashlib.sha256(image).hexdigest() != expected_hash:
        raise ValueError(f"downloaded image hash mismatch: {path.name}")
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary = tempfile.mkstemp(prefix="panel-", suffix=".jpg", dir=path.parent)
    try:
        with os.fdopen(descriptor, "wb") as destination:
            destination.write(image)
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def prepare(candidate: dict[str, Any], selection: dict[str, Any], truth: dict[str, Any],
            workspace: Path, *, fetch: Callable[[str], bytes] = request_bytes,
            ocr: Callable[[Path], list[tuple[str, str]]] = tesseract_candidates) -> dict[str, Any]:
    inventory = audit_candidates(candidate, selection, truth)
    manifest_path = workspace / "review-manifest.json"
    if manifest_path.exists() or (workspace / "annotations").exists():
        raise ValueError("review workspace already exists; refusing to overwrite reviews")
    originals = {panel["panel_id"]: panel for panel in candidate["panels"]}
    ordered = sorted(inventory["panels"], key=lambda panel: hashlib.sha256(
        f"{ORDER_SEED}:{panel['panel_id']}".encode()).digest())
    reviewed = []
    for index, panel in enumerate(ordered, start=1):
        original = originals[panel["panel_id"]]
        image_name = f"{index:03d}-{panel['image_sha256'][:12]}.jpg"
        image_path = workspace / "images" / image_name
        checked_image(image_path, panel["image_sha256"], fetch, panel["image_url"])
        candidates = ocr(image_path)
        if not candidates:
            raise ValueError(f"no independent OCR draft was produced: {panel['panel_id']}")
        source, transcript = max(candidates, key=lambda item: transcript_score(item[1]))
        stub = {"headers": [{"basis": basis} for basis in bases_from_text(transcript)]}
        reviewed.append({
            "review_index": index,
            "panel_id": panel["panel_id"],
            "product_name": original["source"].get("product_name"),
            "product_code": original["source"]["product_code"],
            "image_file": image_name,
            "image_sha256": panel["image_sha256"],
            "image_url": panel["image_url"],
            "draft_source": source,
            "draft_transcript": transcript,
            "draft_cells": cells_from_text(transcript),
            "proposed_families": propose_semantic_families(transcript, stub),
        })
        print(f"prepared={index}/{len(ordered)}", flush=True)
    manifest = {
        "schema_version": 1,
        "review_label": "Issue #93 · v2 development review",
        "review_description": "Review unused public panels against their images. Drafts are unverified; this is not an untouched v2 gate or production acceptance.",
        "review_status": "development_review_not_gate",
        "blinded": True,
        "order_seed": ORDER_SEED,
        "panels": reviewed,
    }
    workspace.mkdir(parents=True, exist_ok=True)
    (workspace / "annotations").mkdir(exist_ok=False)
    descriptor, temporary = tempfile.mkstemp(prefix="review-manifest-", suffix=".json", dir=workspace)
    try:
        with os.fdopen(descriptor, "wb") as destination:
            destination.write(canonical_json(manifest))
        os.replace(temporary, manifest_path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)
    return manifest


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--candidate", required=True, type=Path)
    parser.add_argument("--prior-selection", required=True, type=Path)
    parser.add_argument("--prior-truth", required=True, type=Path)
    parser.add_argument("--workspace", required=True, type=Path)
    args = parser.parse_args()
    prepare(
        json.loads(args.candidate.read_text()),
        json.loads(args.prior_selection.read_text()),
        json.loads(args.prior_truth.read_text()),
        args.workspace,
    )


if __name__ == "__main__":
    main()
