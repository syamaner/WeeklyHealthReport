#!/usr/bin/env python3
"""Prepare a blinded 100-panel human review pack using non-SUT OCR drafts."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import shutil
import subprocess
from pathlib import Path
from typing import Any

from build_annotation_draft import propose_semantic_families
from geometry import bind

REVIEW_SEED = "issue88-review-v1"
ORDER_SEED = "issue88-review-order-v1"
NUTRIENTS = (
    (re.compile(r"\b(?:of which )?saturates?\b", re.I), "saturates", "fat"),
    (re.compile(r"\b(?:of which )?sugars?\b", re.I), "sugars", "carbohydrate"),
    (re.compile(r"\bcarbohydrates?\b", re.I), "carbohydrate", None),
    (re.compile(r"\b(?:dietary )?fib(?:re|er)\b", re.I), "fibre", None),
    (re.compile(r"\bproteins?\b", re.I), "protein", None),
    (re.compile(r"\bsodium\b", re.I), "sodium", None),
    (re.compile(r"\bsalt\b", re.I), "salt", None),
    (re.compile(r"\b(?:total )?fat\b", re.I), "fat", None),
    (re.compile(r"\benergy\b", re.I), "energy", None),
)
VALUE = re.compile(r"(?P<printed>(?P<comparator><=|<|≤)?\s*(?P<number>\d+(?:[.,]\d+)?)\s*(?P<unit>kcal|kJ|kj|mg|µg|ug|g|ml|%))", re.I)


def canonical_json(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")) + "\n"


def selection_key(panel_id: str) -> bytes:
    return hashlib.sha256(f"{REVIEW_SEED}:{panel_id}".encode()).digest()


def select_panels(manifest: dict[str, Any]) -> list[dict[str, Any]]:
    by_split = {
        split: sorted((panel for panel in manifest["panels"] if panel["split"] == split), key=lambda item: selection_key(item["panel_id"]))
        for split in ("tuning", "untouched_gate")
    }
    if len(by_split["tuning"]) < 60 or len(by_split["untouched_gate"]) < 40:
        raise ValueError("candidate corpus cannot provide the frozen 60/40 review selection")
    selected = by_split["tuning"][:60] + by_split["untouched_gate"][:40]
    return sorted(selected, key=lambda item: hashlib.sha256(f"{ORDER_SEED}:{item['panel_id']}".encode()).digest())


def transcript_score(text: str) -> int:
    lowered = text.casefold()
    nutrient_hits = sum(word in lowered for word in ("energy", "fat", "satur", "carbo", "sugar", "fibre", "fiber", "protein", "salt", "sodium"))
    values = len(VALUE.findall(text))
    nonempty_lines = sum(bool(line.strip()) for line in text.splitlines())
    replacement_penalty = text.count("�") * 10
    return nutrient_hits * 20 + values * 5 + min(nonempty_lines, 30) - replacement_penalty


def tesseract_candidates(image: Path) -> list[tuple[str, str]]:
    candidates = []
    for psm in (6, 11, 12):
        completed = subprocess.run(
            ["tesseract", str(image), "stdout", "-l", "eng", "--psm", str(psm)],
            check=True,
            capture_output=True,
        )
        candidates.append((f"tesseract-5.5.3-psm-{psm}", completed.stdout.decode("utf-8", errors="replace").strip()))
    return candidates


def bases_from_text(text: str) -> list[str]:
    compact = re.sub(r"\s+", "", text.casefold())
    bases = []
    if "per100g" in compact or "/100g" in compact or ("100g" in compact and any(word in compact for word in ("energy", "fat", "salt"))):
        bases.append("per_100g")
    if "per100ml" in compact or "/100ml" in compact or ("100ml" in compact and any(word in compact for word in ("energy", "fat", "salt"))):
        bases.append("per_100ml")
    if (
        re.search(r"per(?:serving|portion|pack|\d+(?:[./]\d+)?(?:g|ml)?serving)", compact)
        or (any(word in compact for word in ("serving", "portion", "pack")) and len(VALUE.findall(text)) >= 8)
    ):
        bases.append("per_serving")
    if "%ri" in compact or "%dailyvalue" in compact or "%dv" in compact:
        bases.append("reference_intake")
    return list(dict.fromkeys(bases))


def cells_from_text(text: str) -> list[dict[str, Any]]:
    bases = bases_from_text(text)
    if not bases:
        return []
    cells: list[dict[str, Any]] = []
    seen: set[tuple[str, str]] = set()
    lines = text.splitlines()
    row_starts: list[tuple[int, str, str | None]] = []
    for line_index, line in enumerate(lines):
        nutrient = parent = None
        for pattern, candidate, candidate_parent in NUTRIENTS:
            if pattern.search(line):
                nutrient, parent = candidate, candidate_parent
                break
        if nutrient is None:
            continue
        row_starts.append((line_index, nutrient, parent))
    for row_index, (line_index, nutrient, parent) in enumerate(row_starts):
        end = row_starts[row_index + 1][0] if row_index + 1 < len(row_starts) else min(len(lines), line_index + 6)
        block = "\n".join(lines[line_index:end])
        values = list(VALUE.finditer(block))
        maximum = len(bases) * 2 if nutrient == "energy" else len(bases)
        for index, match in enumerate(values[:maximum]):
            unit = match.group("unit").casefold().replace("ug", "µg")
            row_id = f"energy_{unit}" if nutrient == "energy" and unit in ("kj", "kcal") else nutrient
            basis = bases[index % len(bases)] if len(bases) > 1 else bases[0]
            header_id = f"header_{bases.index(basis) + 1}"
            key = row_id, header_id
            if key in seen:
                continue
            seen.add(key)
            comparator = match.group("comparator")
            if comparator == "≤":
                comparator = "<="
            cells.append({
                "row_id": row_id,
                "parent_row_id": parent,
                "header_id": header_id,
                "basis": basis,
                "printed_text": match.group("printed").strip(),
                "comparator": comparator,
                "decimal_text": match.group("number"),
                "unit": unit,
                "serving_conversion": None,
            })
    return cells


def tuning_candidate(panel_id: str, tuning_draft: dict[str, Any]) -> tuple[str, str, list[dict[str, Any]], list[str]] | None:
    panel = next((item for item in tuning_draft["panels"] if item["panel_id"] == panel_id), None)
    if panel is None:
        return None
    draft = panel["annotation_draft"]
    cells = [
        {key: value for key, value in cell.items() if key != "persistence_authorized"}
        for cell in draft["proposed_cells"]
    ]
    return "apple-vision-tuning-only", draft["recognizer_transcript"], cells, draft["proposed_semantic_families"]


def prepare(args: argparse.Namespace) -> None:
    manifest = json.loads(args.manifest.read_text())
    tuning_draft = json.loads(args.tuning_draft.read_text())
    selected = select_panels(manifest)
    images_dir = args.workspace / "images"
    annotations_dir = args.workspace / "annotations"
    images_dir.mkdir(parents=True, exist_ok=True)
    annotations_dir.mkdir(parents=True, exist_ok=True)
    review_panels = []
    sealed = []
    for index, panel in enumerate(selected, start=1):
        source_image = args.image_dir / panel["local_image"]
        image_hash = hashlib.sha256(source_image.read_bytes()).hexdigest()
        if image_hash != panel["image_sha256"]:
            raise ValueError(f"image hash mismatch: {panel['panel_id']}")
        destination_name = f"{index:03d}-{panel['image_sha256'][:12]}.jpg"
        review_image = images_dir / destination_name
        shutil.copyfile(source_image, review_image)
        candidates: list[tuple[str, str, list[dict[str, Any]], list[str]]] = []
        for source, transcript in tesseract_candidates(review_image):
            stub = {"headers": [{"basis": basis} for basis in bases_from_text(transcript)]}
            candidates.append((source, transcript, cells_from_text(transcript), propose_semantic_families(transcript, stub)))
        if panel["split"] == "tuning":
            vision = tuning_candidate(panel["panel_id"], tuning_draft)
            if vision:
                candidates.append(vision)
        source, transcript, cells, semantic_families = max(candidates, key=lambda item: transcript_score(item[1]))
        review_panels.append({
            "review_index": index,
            "panel_id": panel["panel_id"],
            "product_name": panel["source"].get("product_name"),
            "product_code": panel["source"]["product_code"],
            "image_file": destination_name,
            "image_sha256": panel["image_sha256"],
            "image_url": panel["source"]["image_url"],
            "draft_source": source,
            "draft_transcript": transcript,
            "draft_cells": cells,
            "proposed_families": semantic_families,
        })
        sealed.append({
            "review_index": index,
            "panel_id": panel["panel_id"],
            "split": panel["split"],
            "image_sha256": panel["image_sha256"],
            "selection_key": selection_key(panel["panel_id"]).hex(),
        })
        print(f"prepared={index}/100", flush=True)
    (args.workspace / "review-manifest.json").write_text(canonical_json({
        "schema_version": 1,
        "blinded": True,
        "review_seed": REVIEW_SEED,
        "order_seed": ORDER_SEED,
        "panels": review_panels,
    }))
    args.selection_output.write_text(canonical_json({
        "schema_version": 1,
        "review_seed": REVIEW_SEED,
        "order_seed": ORDER_SEED,
        "counts": {"tuning": 60, "untouched_gate": 40},
        "panels": sealed,
    }))


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--manifest", required=True, type=Path)
    parser.add_argument("--tuning-draft", required=True, type=Path)
    parser.add_argument("--image-dir", required=True, type=Path)
    parser.add_argument("--workspace", required=True, type=Path)
    parser.add_argument("--selection-output", required=True, type=Path)
    prepare(parser.parse_args())


if __name__ == "__main__":
    main()
