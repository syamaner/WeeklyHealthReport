#!/usr/bin/env python3
"""Freeze public v2 panel identities and 60/40 split; do not run OCR or a gate."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from acquire_v2_public import canonical_json, legacy_exclusions
from validate_contract_v2 import select_split


def freeze(
    contract: dict[str, Any], inventory: dict[str, Any], image_root: Path, *,
    excluded_ids: set[str], excluded_hashes: set[str], excluded_codes: set[str],
) -> dict[str, Any]:
    if inventory.get("status") != "candidate_inventory_only_no_ground_truth_or_gate":
        raise ValueError("unsupported candidate inventory status")
    if len(inventory.get("panels", [])) < contract["corpus"]["minimum_new_candidates"]:
        raise ValueError("candidate inventory is below the contract minimum")
    for exposure in inventory.get("development_exposures", []):
        match = re.fullmatch(r"off:([0-9]{8,14}):nutrition_en\.[0-9]+:raw-[0-9]+", exposure["panel_id"])
        if not match:
            raise ValueError("development exposure identity is malformed")
        excluded_codes.add(match.group(1))
        excluded_ids.add(exposure["panel_id"])
        excluded_hashes.add(exposure["image_sha256"])
    for panel in inventory["panels"]:
        name = f"{panel['panel_id'].replace(':', '_')}_{panel['image_sha256'][:12]}.jpg"
        if panel.get("local_image") != f"images/{name}":
            raise ValueError("candidate local image path does not match identity")
        image = (image_root / "images" / name).read_bytes()
        if hashlib.sha256(image).hexdigest() != panel["image_sha256"]:
            raise ValueError("candidate image SHA-256 mismatch")
        if panel.get("ground_truth") != {"verification_status": "pending"}:
            raise ValueError("candidate inventory already contains review data")
    assignments = select_split(
        contract, inventory["panels"], excluded_panel_ids=excluded_ids,
        excluded_image_hashes=excluded_hashes, excluded_product_codes=excluded_codes,
    )
    panels_by_id = {panel["panel_id"]: panel for panel in inventory["panels"]}
    selected = [{**panels_by_id[panel_id], "split": split} for panel_id, split in assignments.items()]
    return {
        "schema_version": 2,
        "status": "identities_and_split_frozen_no_ground_truth_or_gate",
        "frozen_at": datetime.now(timezone.utc).isoformat(),
        "contract_sha256": hashlib.sha256(canonical_json(contract)).hexdigest(),
        "candidate_inventory_sha256": hashlib.sha256(canonical_json(inventory)).hexdigest(),
        "selection_algorithm": contract["selection"]["algorithm_id"],
        "development_exposures": inventory.get("development_exposures", []),
        "panels": selected,
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--contract", type=Path, required=True)
    parser.add_argument("--inventory", type=Path, required=True)
    parser.add_argument("--exclude-manifest", type=Path, action="append", required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if args.output.exists():
        raise SystemExit("frozen selection already exists; refusing overwrite")
    contract = json.loads(args.contract.read_text())
    inventory = json.loads(args.inventory.read_text())
    excluded_ids, excluded_hashes, excluded_codes = legacy_exclusions(args.exclude_manifest)
    result = freeze(
        contract, inventory, args.inventory.parent,
        excluded_ids=excluded_ids, excluded_hashes=excluded_hashes,
        excluded_codes=excluded_codes,
    )
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_bytes(canonical_json(result))
    print("frozen=100; tuning=60; untouched=40; ground_truth_pending=true; gate_unopened=true")


if __name__ == "__main__":
    main()
