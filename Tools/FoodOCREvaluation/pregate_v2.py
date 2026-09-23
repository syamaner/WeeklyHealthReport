#!/usr/bin/env python3
"""Audit candidate images before preparing an independent OCR v2 review pack.

This never runs a recognizer, scores an outcome, or assigns gate status.
"""

from __future__ import annotations

import argparse
import json
import re
from collections import Counter
from pathlib import Path
from typing import Any

SHA256 = re.compile(r"[0-9a-f]{64}\Z")
PUBLIC_IMAGE_PREFIX = "https://images.openfoodfacts.org/images/products/"


def audit_candidates(candidate: dict[str, Any], prior_selection: dict[str, Any],
                     prior_truth: dict[str, Any]) -> dict[str, Any]:
    """Return only unreviewed, unselected, hash-pinned public image identities.

    Any inconsistent identity or duplicate image fails the entire audit, rather
    than silently dropping a panel and making the apparent pool look cleaner.
    """
    if (candidate.get("schema_version") != 1 or prior_selection.get("schema_version") != 1
            or prior_truth.get("schema_version") != 1):
        raise ValueError("unsupported manifest or selection schema")
    selected = {panel["panel_id"]: panel["image_sha256"] for panel in prior_selection["panels"]}
    reviewed = {panel["panel_id"]: panel["image_sha256"] for panel in prior_truth["panels"]}
    if (len(selected) != len(prior_selection["panels"])
            or len(reviewed) != len(prior_truth["panels"])
            or selected != reviewed
            or len(set(selected.values())) != len(selected)):
        raise ValueError("prior selection and ground truth have conflicting image identities")
    excluded_ids = set(selected)
    excluded_hashes = set(selected.values())

    seen_ids: set[str] = set()
    seen_hashes: set[str] = set()
    remaining = []
    for panel in candidate["panels"]:
        panel_id, image_hash = panel["panel_id"], panel["image_sha256"]
        if not panel_id or not SHA256.fullmatch(image_hash):
            raise ValueError("candidate lacks a valid panel ID or image hash")
        if panel_id in seen_ids or image_hash in seen_hashes:
            raise ValueError("candidate corpus repeats a panel ID or image hash")
        seen_ids.add(panel_id)
        seen_hashes.add(image_hash)
        if panel_id in excluded_ids or image_hash in excluded_hashes:
            continue
        if panel.get("ground_truth", {}).get("verification_status") != "pending":
            raise ValueError(f"unexpected ground-truth status: {panel_id}")
        if not panel.get("source", {}).get("image_url", "").startswith(PUBLIC_IMAGE_PREFIX):
            raise ValueError(f"unsupported public image source: {panel_id}")
        remaining.append({
            "panel_id": panel_id,
            "image_sha256": image_hash,
            "image_url": panel["source"]["image_url"],
            "local_image": panel["local_image"],
            "old_split": panel["split"],
        })
    remaining.sort(key=lambda panel: panel["panel_id"])
    return {
        "schema_version": 1,
        "status": "inventory_only_not_ground_truth_or_gate",
        "prior_selected_count": len(prior_selection["panels"]),
        "remaining_count": len(remaining),
        "old_split_counts": dict(sorted(Counter(panel["old_split"] for panel in remaining).items())),
        "panels": remaining,
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--candidate", type=Path, required=True)
    parser.add_argument("--prior-selection", type=Path, required=True)
    parser.add_argument("--prior-truth", type=Path, required=True)
    args = parser.parse_args()
    result = audit_candidates(
        json.loads(args.candidate.read_text()),
        json.loads(args.prior_selection.read_text()),
        json.loads(args.prior_truth.read_text()),
    )
    print(json.dumps(result, ensure_ascii=False, sort_keys=True, indent=2))


if __name__ == "__main__":
    main()
