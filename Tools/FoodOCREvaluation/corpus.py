"""Closed corpus and split invariants for issue #88."""

from __future__ import annotations

import hashlib
import re
from typing import Any

SHA256 = re.compile(r"^[0-9a-f]{64}$")


def split_for(panel_id: str, image_sha256: str) -> str:
    if not panel_id or not SHA256.fullmatch(image_sha256):
        raise ValueError("panel ID and lowercase image SHA-256 are required")
    bucket = hashlib.sha256(f"{image_sha256}:{panel_id}".encode()).digest()[0]
    return "tuning" if bucket <= 152 else "untouched_gate"


def validate_ground_truth(panel: dict[str, Any]) -> None:
    truth = panel.get("ground_truth", {})
    if truth.get("verification_status") != "independently_verified":
        raise ValueError(f"panel {panel['panel_id']} has no independent ground truth")
    if not truth.get("full_transcript"):
        raise ValueError(f"panel {panel['panel_id']} has no exact transcript")
    review = truth.get("review", {})
    if review.get("verified_against_image_sha256") != panel["image_sha256"]:
        raise ValueError(f"panel {panel['panel_id']} verification is not tied to its image hash")
    if not review.get("reviewer") or not review.get("verified_at"):
        raise ValueError(f"panel {panel['panel_id']} has incomplete review provenance")
    keys: set[tuple[str, str]] = set()
    for cell in truth.get("cells", []):
        required = (
            "row_id", "parent_row_id", "header_id", "basis", "printed_text",
            "comparator", "decimal_text", "unit", "serving_conversion",
        )
        if any(key not in cell for key in required):
            raise ValueError(f"panel {panel['panel_id']} has an incomplete ground-truth cell")
        key = (cell["row_id"], cell["header_id"])
        if key in keys:
            raise ValueError(f"panel {panel['panel_id']} has a duplicate row/header cell")
        keys.add(key)


def validate_manifest(manifest: dict[str, Any], contract: dict[str, Any], *, require_complete: bool = True) -> None:
    if manifest.get("schema_version") != 1:
        raise ValueError("unsupported manifest schema")
    panels = manifest.get("panels", [])
    ids: set[str] = set()
    hashes: set[str] = set()
    family_counts = {family: 0 for family in contract["corpus"]["required_families"]}
    gate_count = 0

    for panel in panels:
        panel_id = panel["panel_id"]
        image_hash = panel["image_sha256"]
        if panel_id in ids:
            raise ValueError(f"duplicate panel ID: {panel_id}")
        if image_hash in hashes:
            raise ValueError(f"duplicate image bytes: {image_hash}")
        ids.add(panel_id)
        hashes.add(image_hash)
        expected_split = split_for(panel_id, image_hash)
        if panel["split"] != expected_split:
            raise ValueError(f"split mismatch for {panel_id}")
        gate_count += int(expected_split == "untouched_gate")
        if panel.get("country_tag") != contract["corpus"]["country_tag"]:
            raise ValueError(f"panel {panel_id} lacks the frozen UK country tag")
        if not panel.get("source", {}).get("image_url", "").startswith("https://images.openfoodfacts.org/"):
            raise ValueError(f"panel {panel_id} has an unsupported image source")
        if require_complete:
            validate_ground_truth(panel)
        for family in set(panel.get("families", [])):
            if family in family_counts:
                family_counts[family] += 1

    if require_complete:
        if len(panels) < contract["corpus"]["minimum_panels"]:
            raise ValueError("manifest has fewer than the frozen panel minimum")
        if gate_count < contract["corpus"]["minimum_untouched_gate_panels"]:
            raise ValueError("manifest has fewer than the frozen untouched-gate minimum")
        missing = sorted(family for family, count in family_counts.items() if count == 0)
        if missing:
            raise ValueError(f"manifest misses required families: {', '.join(missing)}")
