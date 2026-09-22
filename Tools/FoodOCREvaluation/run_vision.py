#!/usr/bin/env python3
"""Run the local Apple Vision adapter over hash-verified corpus images."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import subprocess
from pathlib import Path
from typing import Any


def preflight(manifest: dict[str, Any], image_dir: Path, output_dir: Path, split: str | None) -> list[dict[str, Any]]:
    panels = [panel for panel in manifest["panels"] if not split or panel["split"] == split]
    if split == "untouched_gate" and (len(manifest["panels"]) != 100 or len(panels) != 40):
        raise ValueError("the untouched run requires the frozen 100/40 reviewed fixture")
    if output_dir.exists() and any(output_dir.iterdir()):
        raise ValueError("output directory is not empty; refusing to repeat or overwrite a gate run")
    names: set[str] = set()
    for panel in panels:
        name = panel["panel_id"].replace(":", "_") + ".json"
        if name in names:
            raise ValueError(f"duplicate output name: {name}")
        names.add(name)
        image_path = image_dir / panel["local_image"]
        digest = hashlib.sha256(image_path.read_bytes()).hexdigest()
        if digest != panel["image_sha256"]:
            raise ValueError(f"image hash mismatch: {panel['panel_id']}")
    return panels


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--binary", required=True, type=Path)
    parser.add_argument("--manifest", required=True, type=Path)
    parser.add_argument("--image-dir", required=True, type=Path)
    parser.add_argument("--output-dir", required=True, type=Path)
    parser.add_argument("--split", choices=("tuning", "untouched_gate"))
    parser.add_argument("--fixture-sha256", help="required frozen fixture hash for the untouched gate")
    args = parser.parse_args()
    fixture_bytes = args.manifest.read_bytes()
    fixture_hash = hashlib.sha256(fixture_bytes).hexdigest()
    if args.split == "untouched_gate" and args.fixture_sha256 != fixture_hash:
        raise SystemExit("untouched fixture hash is absent or mismatched")
    manifest = json.loads(fixture_bytes)
    panels = preflight(manifest, args.image_dir, args.output_dir, args.split)
    if not args.binary.is_file() or not os.access(args.binary, os.X_OK):
        raise SystemExit("Vision binary is missing or not executable")
    args.output_dir.mkdir(parents=True, exist_ok=True)
    (args.output_dir / "run-manifest.json").write_text(json.dumps({
        "schema_version": 1,
        "scope": args.split,
        "fixture_sha256": fixture_hash,
        "binary_sha256": hashlib.sha256(args.binary.read_bytes()).hexdigest(),
        "vision_source_sha256": hashlib.sha256(Path(__file__).with_name("vision.swift").read_bytes()).hexdigest(),
        "panel_ids": [panel["panel_id"] for panel in panels],
    }, sort_keys=True, separators=(",", ":")) + "\n")
    for index, panel in enumerate(panels, start=1):
        image_path = args.image_dir / panel["local_image"]
        completed = subprocess.run([str(args.binary), str(image_path)], check=True, capture_output=True)
        result = json.loads(completed.stdout)
        if result["imageSHA256"] != panel["image_sha256"]:
            raise SystemExit(f"recognizer hash mismatch: {panel['panel_id']}")
        output_name = panel["panel_id"].replace(":", "_") + ".json"
        (args.output_dir / output_name).write_text(
            json.dumps(result, ensure_ascii=False, sort_keys=True, separators=(",", ":")) + "\n"
        )
        print(f"recognized={index}/{len(panels)} panel={panel['panel_id']}", flush=True)


if __name__ == "__main__":
    main()
