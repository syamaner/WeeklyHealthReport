#!/usr/bin/env python3
"""Run the local Apple Vision adapter over hash-verified corpus images."""

from __future__ import annotations

import argparse
import hashlib
import json
import subprocess
from pathlib import Path


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--binary", required=True, type=Path)
    parser.add_argument("--manifest", required=True, type=Path)
    parser.add_argument("--image-dir", required=True, type=Path)
    parser.add_argument("--output-dir", required=True, type=Path)
    parser.add_argument("--split", choices=("tuning", "untouched_gate"))
    args = parser.parse_args()
    manifest = json.loads(args.manifest.read_text())
    args.output_dir.mkdir(parents=True, exist_ok=True)
    panels = [panel for panel in manifest["panels"] if not args.split or panel["split"] == args.split]
    for index, panel in enumerate(panels, start=1):
        image_path = args.image_dir / panel["local_image"]
        digest = hashlib.sha256(image_path.read_bytes()).hexdigest()
        if digest != panel["image_sha256"]:
            raise SystemExit(f"image hash mismatch: {panel['panel_id']}")
        completed = subprocess.run([str(args.binary), str(image_path)], check=True, capture_output=True)
        result = json.loads(completed.stdout)
        if result["imageSHA256"] != digest:
            raise SystemExit(f"recognizer hash mismatch: {panel['panel_id']}")
        output_name = panel["panel_id"].replace(":", "_") + ".json"
        (args.output_dir / output_name).write_text(
            json.dumps(result, ensure_ascii=False, sort_keys=True, separators=(",", ":")) + "\n"
        )
        print(f"recognized={index}/{len(panels)} panel={panel['panel_id']}", flush=True)


if __name__ == "__main__":
    main()
