#!/usr/bin/env python3
"""Version a pre-gate review selection after a source-language exclusion.

Keep every other review index stable so existing human annotations remain tied
to the same image. The replacement is the next hash-ranked, unselected panel
in the same split, chosen without consulting recognition or review outcomes.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import shutil
from pathlib import Path
from typing import Any

from build_annotation_draft import propose_semantic_families
from prepare_review import (
    bases_from_text,
    canonical_json,
    cells_from_text,
    selection_key,
    tesseract_candidates,
    transcript_score,
)


def replacement_for(
    manifest: dict[str, Any], selection: dict[str, Any], excluded_index: int
) -> dict[str, Any]:
    excluded = next(panel for panel in selection["panels"] if panel["review_index"] == excluded_index)
    selected_ids = {panel["panel_id"] for panel in selection["panels"]}
    eligible = sorted(
        (
            panel for panel in manifest["panels"]
            if panel["split"] == excluded["split"]
            and panel["panel_id"] not in selected_ids
            and panel["source"].get("image_language") == "en"
        ),
        key=lambda panel: selection_key(panel["panel_id"]),
    )
    if not eligible:
        raise ValueError("no unused English-language panel in the excluded split")
    return eligible[0]


def replace(
    manifest: dict[str, Any], selection: dict[str, Any], review_manifest: dict[str, Any],
    excluded_index: int, image: Path, workspace: Path,
) -> tuple[dict[str, Any], dict[str, Any]]:
    if selection["counts"] != {"tuning": 60, "untouched_gate": 40}:
        raise ValueError("unexpected review split")
    old = next(panel for panel in selection["panels"] if panel["review_index"] == excluded_index)
    old_review = next(panel for panel in review_manifest["panels"] if panel["review_index"] == excluded_index)
    if old_review["panel_id"] != old["panel_id"] or old_review["image_sha256"] != old["image_sha256"]:
        raise ValueError("review selection and manifest disagree")
    if (workspace / "annotations" / f"{excluded_index:03d}.json").exists():
        raise ValueError("excluded panel already has a human annotation")
    candidate = replacement_for(manifest, selection, excluded_index)
    if hashlib.sha256(image.read_bytes()).hexdigest() != candidate["image_sha256"]:
        raise ValueError("replacement image does not match the pinned candidate")
    destination_name = f"{excluded_index:03d}-{candidate['image_sha256'][:12]}.jpg"
    destination = workspace / "images" / destination_name
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(image, destination)
    source, transcript = max(tesseract_candidates(destination), key=lambda item: transcript_score(item[1]))
    cells = cells_from_text(transcript)
    families = propose_semantic_families(
        transcript, {"headers": [{"basis": basis} for basis in bases_from_text(transcript)]}
    )
    new_review = {
        "review_index": excluded_index,
        "panel_id": candidate["panel_id"],
        "product_name": candidate["source"].get("product_name"),
        "product_code": candidate["source"]["product_code"],
        "image_file": destination_name,
        "image_sha256": candidate["image_sha256"],
        "image_url": candidate["source"]["image_url"],
        "draft_source": source,
        "draft_transcript": transcript,
        "draft_cells": cells,
        "proposed_families": families,
    }
    new_sealed = {
        "review_index": excluded_index,
        "panel_id": candidate["panel_id"],
        "split": candidate["split"],
        "image_sha256": candidate["image_sha256"],
        "selection_key": selection_key(candidate["panel_id"]).hex(),
    }
    versioned = dict(selection)
    versioned["panels"] = [new_sealed if panel["review_index"] == excluded_index else panel for panel in selection["panels"]]
    versioned["supersedes_selection_sha256"] = hashlib.sha256(canonical_json(selection).encode()).hexdigest()
    versioned["replacement"] = {
        "review_index": excluded_index,
        "excluded_panel_id": old["panel_id"],
        "replacement_panel_id": candidate["panel_id"],
        "reason": "User excluded the bilingual KA panel from the English-language human-review queue before the untouched gate.",
        "rule": "next unused hash-ranked English-language candidate in the same split",
    }
    updated_review = dict(review_manifest)
    updated_review["panels"] = [new_review if panel["review_index"] == excluded_index else panel for panel in review_manifest["panels"]]
    return versioned, updated_review


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--manifest", required=True, type=Path)
    parser.add_argument("--selection", required=True, type=Path)
    parser.add_argument("--workspace", required=True, type=Path)
    parser.add_argument("--image", required=True, type=Path)
    parser.add_argument("--excluded-index", required=True, type=int)
    parser.add_argument("--selection-output", required=True, type=Path)
    args = parser.parse_args()
    if args.selection_output.exists():
        raise ValueError("will not overwrite an existing frozen selection")
    manifest = json.loads(args.manifest.read_text())
    selection = json.loads(args.selection.read_text())
    review_path = args.workspace / "review-manifest.json"
    review_backup = args.workspace / "review-manifest-v1.json"
    if review_backup.exists():
        raise ValueError("will not overwrite the original review manifest backup")
    review_manifest = json.loads(review_path.read_text())
    versioned, updated_review = replace(
        manifest, selection, review_manifest, args.excluded_index, args.image, args.workspace
    )
    review_backup.write_text(canonical_json(review_manifest))
    args.selection_output.write_text(canonical_json(versioned))
    review_path.write_text(canonical_json(updated_review))
    print(f"replacement_panel_id={versioned['replacement']['replacement_panel_id']}")
    print(f"selection_sha256={hashlib.sha256(args.selection_output.read_bytes()).hexdigest()}")


if __name__ == "__main__":
    main()
