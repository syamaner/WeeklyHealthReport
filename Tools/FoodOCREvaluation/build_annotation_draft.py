#!/usr/bin/env python3
"""Create candidate-only annotations; never marks them independently verified."""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path
from typing import Any

from geometry import bind


def raw_path(raw_dir: Path, panel_id: str) -> Path:
    return raw_dir / (panel_id.replace(":", "_") + ".json")


def propose_semantic_families(transcript: str, result: dict[str, Any]) -> list[str]:
    lowered = transcript.casefold()
    families: set[str] = set()
    for header in result["headers"]:
        families.add(header["basis"])
    if re.search(r"(?:<|≤)\s*\d", transcript):
        families.add("bound")
    if re.search(r"\bsalt\b", lowered):
        families.add("salt")
    if re.search(r"\bsodium\b", lowered):
        families.add("sodium")
    if "saturates" in lowered or "of which sugars" in lowered:
        families.add("nested_rows")
    if len(result["headers"]) > 1:
        families.add("multi_column")
    return sorted(families)


def build_draft(manifest: dict[str, Any], raw_dir: Path, split: str | None = None) -> dict[str, Any]:
    draft = json.loads(json.dumps(manifest))
    draft["panels"] = [panel for panel in draft["panels"] if split is None or panel["split"] == split]
    for panel in draft["panels"]:
        raw = json.loads(raw_path(raw_dir, panel["panel_id"]).read_text())
        transcript = "\n".join(
            observation["candidates"][0]["text"]
            for observation in raw.get("observations", [])
            if observation.get("candidates")
        )
        result = bind(raw)
        panel["annotation_draft"] = {
            "warning": "candidate only; visually verify every character and relationship",
            "recognizer_transcript": transcript,
            "proposed_cells": result["cells"],
            "proposed_semantic_families": propose_semantic_families(transcript, result),
            "proposed_decline": result["declined"],
            "unresolved_reasons": result["unresolved_reasons"],
        }
    return draft


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--manifest", required=True, type=Path)
    parser.add_argument("--raw-dir", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--split", choices=("tuning", "untouched_gate"))
    args = parser.parse_args()
    manifest = json.loads(args.manifest.read_text())
    value = build_draft(manifest, args.raw_dir, args.split)
    args.output.write_text(json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")) + "\n")


if __name__ == "__main__":
    main()
