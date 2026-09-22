#!/usr/bin/env python3
"""Convert one hash-pinned raw Vision gate run to fail-closed scoring inputs."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
from typing import Any

from arithmetic_mutations import MUTATIONS, mutation_probes
from geometry import bind


def raw_filename(panel_id: str) -> str:
    return panel_id.replace(":", "_") + ".json"


def build_outcomes(
    manifest: dict[str, Any], fixture_sha256: str, raw_dir: Path, contract: dict[str, Any],
) -> dict[str, Any]:
    panels = [panel for panel in manifest["panels"] if panel["split"] == "untouched_gate"]
    if len(manifest["panels"]) != 100 or len(panels) != 40:
        raise ValueError("expected the frozen 100/40 review fixture")
    run = json.loads((raw_dir / "run-manifest.json").read_text())
    if run.get("scope") != "untouched_gate" or run.get("fixture_sha256") != fixture_sha256:
        raise ValueError("raw run does not match the frozen untouched fixture")
    source_hash = hashlib.sha256(Path(__file__).with_name("vision.swift").read_bytes()).hexdigest()
    if run.get("vision_source_sha256") != source_hash or len(str(run.get("binary_sha256", ""))) != 64:
        raise ValueError("raw run recognizer build is not pinned to the frozen source")
    if run.get("panel_ids") != [panel["panel_id"] for panel in panels]:
        raise ValueError("raw run panel order differs from the frozen fixture")
    expected_files = {raw_filename(panel["panel_id"]) for panel in panels} | {"run-manifest.json"}
    if {path.name for path in raw_dir.iterdir()} != expected_files:
        raise ValueError("raw run contains missing or unexpected files")
    mutation_contract = contract["arithmetic_faults"]
    if tuple(mutation_contract["mutations"]) != MUTATIONS or not mutation_contract["derived_from_real_ground_truth_only"]:
        raise ValueError("arithmetic mutation contract differs from the frozen implementation")
    probes = mutation_probes(manifest, mutation_contract["seed"])
    outcomes = []
    for panel in panels:
        raw_path = raw_dir / raw_filename(panel["panel_id"])
        raw = json.loads(raw_path.read_text())
        if (raw.get("schemaVersion") != 1 or raw.get("imageSHA256") != panel["image_sha256"]
                or raw.get("recognizer") != "Apple Vision VNRecognizeTextRequest"
                or raw.get("recognitionLevel") != "accurate"
                or raw.get("recognitionLanguages") != ["en-US"]
                or raw.get("usesLanguageCorrection") is not True):
            raise ValueError(f"raw recognizer identity mismatch: {panel['panel_id']}")
        bound = bind(raw)
        outcomes.append({
            "panel_id": panel["panel_id"],
            "raw_sha256": hashlib.sha256(raw_path.read_bytes()).hexdigest(),
            "cells": bound["cells"],
            "ready_for_confirmation": bound["ready_for_confirmation"],
            "unresolved_warning": bound["unresolved_warning"],
            "declined": bound["declined"],
            "unresolved_reasons": bound["unresolved_reasons"],
            "arithmetic": bound["arithmetic"],
            "arithmetic_faults": probes.get(panel["panel_id"], []),
            "correction_seconds": panel["ground_truth"]["correction_seconds"],
        })
    return {
        "schema_version": 1,
        "fixture_sha256": fixture_sha256,
        "scope": "untouched_gate",
        "arithmetic_mutation_status": "three deterministic mutations of real untouched ground truth; arithmetic policy only, not Vision recognition",
        "panels": outcomes,
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--manifest", required=True, type=Path)
    parser.add_argument("--raw-dir", required=True, type=Path)
    parser.add_argument("--contract", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    if args.output.exists():
        raise ValueError("will not overwrite gate outcomes")
    fixture_bytes = args.manifest.read_bytes()
    result = build_outcomes(
        json.loads(fixture_bytes), hashlib.sha256(fixture_bytes).hexdigest(), args.raw_dir,
        json.loads(args.contract.read_text()),
    )
    args.output.write_text(json.dumps(result, ensure_ascii=False, sort_keys=True, separators=(",", ":")) + "\n")


if __name__ == "__main__":
    main()
