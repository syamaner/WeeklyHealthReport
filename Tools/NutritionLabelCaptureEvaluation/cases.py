"""Dataset loading and the sealed-set guard. Pure apart from reading local files.

Development and untouched cases are separate datasets. The untouched loader refuses to
return anything unless the caller passes an explicit unseal flag and the sealed
manifest's SHA-256, and that hash matches both the file and the frozen contract. It
returns image paths only; it never reads, decodes or displays image bytes.
"""

from __future__ import annotations

import hashlib
import json
from pathlib import Path
from typing import Any

HERE = Path(__file__).resolve().parent
CONTRACT = HERE / "frozen-contract-v1.json"


class SealedSetError(PermissionError):
    """Raised when the untouched set is requested without a valid unseal."""


def sha256_file(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def load_jsonl(path: Path) -> list[dict[str, Any]]:
    return [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines() if line.strip()]


def load_development_text(path: Path) -> list[dict[str, Any]]:
    cases = load_jsonl(path)
    for case in cases:
        if case["metadata"].get("split") != "development":
            raise SealedSetError(f"{case['id']} is not a development case")
        if hashlib.sha256(case["input"]["text"].encode("utf-8")).hexdigest() != case["metadata"]["sha256"]:
            raise ValueError(f"{case['id']} text does not match its recorded hash")
    return cases


def load_development_photos(manifest_path: Path, image_root: Path, truth_path: Path | None = None) -> list[dict[str, Any]]:
    """Development Taiwan photos with their (first-pass) truth; for routes B and C later."""
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    truths = {}
    if truth_path is not None:
        truths = {record["case_id"]: record for record in json.loads(truth_path.read_text(encoding="utf-8"))["records"]}
    cases = []
    for photo in manifest["photos"] + manifest.get("refills", []):
        if photo["split"] != "development" or photo.get("excluded"):
            continue
        case_id = f"off-taiwan:{photo['barcode13']}:nutrition_zh.{photo['revision']}"
        path = image_root / "development" / f"{photo['order']:02d}-{photo['barcode13']}-nutrition_zh.{photo['revision']}.jpg"
        if sha256_file(path) != photo["sha256"]:
            raise ValueError(f"{case_id} bytes do not match the manifest")
        cases.append(
            {
                "id": case_id,
                "input": {"kind": "image", "path": str(path)},
                "truth": truths.get(case_id),
                "metadata": {
                    "corpus": "off_taiwan",
                    "split": "development",
                    "sha256": photo["sha256"],
                    "coverage_tags": ["zh_hant"],
                    "licence": manifest["licence"],
                    "attribution": photo["attribution"],
                },
            }
        )
    return cases


def load_untouched_photos(
    manifest_path: Path,
    image_root: Path,
    *,
    unseal: bool,
    manifest_sha256: str | None,
    truth_path: Path | None = None,
    contract_path: Path = CONTRACT,
) -> list[dict[str, Any]]:
    """The 40 untouched Taiwan photos, only after an explicit, hash-bound unseal."""
    if not unseal:
        raise SealedSetError("the untouched set is sealed; pass an explicit unseal flag")
    contract = json.loads(contract_path.read_text(encoding="utf-8"))
    expected = contract["corpus"]["off_taiwan"]["manifest_sha256"]
    if not manifest_sha256 or manifest_sha256 != expected or sha256_file(manifest_path) != expected:
        raise SealedSetError("the sealed manifest hash does not match the frozen contract")
    if contract.get("status") != "frozen_for_untouched_run":
        raise SealedSetError("the contract is not frozen for the untouched run")
    if truth_path is None or sha256_file(truth_path) != contract.get("ground_truth", {}).get("untouched_sha256"):
        raise SealedSetError("untouched ground truth is missing or does not match the frozen hash")
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    truths = {record["case_id"]: record for record in json.loads(truth_path.read_text(encoding="utf-8"))["records"]}
    cases = []
    for photo in manifest["photos"] + manifest.get("refills", []):
        if photo["split"] != "untouched" or photo.get("excluded"):
            continue
        case_id = f"off-taiwan:{photo['barcode13']}:nutrition_zh.{photo['revision']}"
        path = image_root / "sealed" / f"{photo['order']:02d}-{photo['barcode13']}-nutrition_zh.{photo['revision']}.jpg"
        cases.append(
            {
                "id": case_id,
                "input": {"kind": "image", "path": str(path)},
                "truth": truths[case_id],
                "metadata": {
                    "corpus": "off_taiwan",
                    "split": "untouched",
                    "sha256": photo["sha256"],
                    "licence": manifest["licence"],
                    "attribution": photo["attribution"],
                },
            }
        )
    return cases


# --- Route B development photo sets (phase 2) ----------------------------------------

UK_UNITS = {"kj": "kJ", "kcal": "kcal", "g": "g", "mg": "mg", "µg": "µg", "mcg": "µg", "%": "%", "ml": "ml"}
UK_NUTRIENTS = {"energy_kj", "energy_kcal", "fat", "saturates", "trans_fat", "carbohydrate", "sugars", "fibre", "protein", "salt", "sodium"}
UK_REFERENCE_SUFFIX = "_ri"


def _printed_unit(cell: dict[str, Any]) -> str:
    """The unit as printed: the trailing unit in printed_text, else the recorded unit."""
    printed = str(cell.get("printed_text") or "").rstrip()
    for unit in sorted(UK_UNITS, key=len, reverse=True):
        if printed.lower().endswith(unit):
            return printed[-len(unit) :]
    return str(cell.get("unit") or "")


def uk_truth_from_review(panel: dict[str, Any]) -> dict[str, Any]:
    """Convert one frozen v2 development review record to `label-capture-truth-v1`.

    The v2 review (September 2026, image-first, owner-verified) predates this evaluation.
    It records no servings per pack, so that field is `not_recorded` and the scorer leaves
    it out of every denominator; it records no serving-size line, so serving size is
    `unknown` and not scored (per-cell serving conversions still are). Headers are rebuilt
    from the cells' header ids and bases; reference-intake rows (`fat_ri`) become
    reference-intake cells of their nutrient; other rows are unrecognised with the row id
    as the label.
    """
    truth = panel["ground_truth"]
    cells, headers = [], {}
    for cell in truth.get("cells") or []:
        row = str(cell["row_id"])
        unit = _printed_unit(cell)
        canonical = UK_UNITS.get(unit.lower(), unit)
        basis = cell["basis"]
        nutrient = row
        if row.endswith(UK_REFERENCE_SUFFIX):
            nutrient = row[: -len(UK_REFERENCE_SUFFIX)]
            nutrient = "energy_kcal" if nutrient == "energy" else nutrient
            basis = "reference_intake"
        if nutrient not in UK_NUTRIENTS:
            nutrient = "unrecognised"
        headers.setdefault(cell["header_id"], basis)
        conversion = cell.get("serving_conversion")
        cells.append(
            {
                "row_id": row,
                "parent_row_id": cell.get("parent_row_id"),
                "nutrient": nutrient,
                "printed_label": row.replace("_", " "),
                "header_id": cell["header_id"],
                "basis": basis,
                "printed_text": cell.get("printed_text"),
                "comparator": cell.get("comparator") or "=",
                "decimal_text": cell.get("decimal_text"),
                "unit": unit,
                "canonical_unit": canonical,
                "serving_conversion": conversion if basis == "per_serving" else "not_applicable",
            }
        )
    serving = next((c["serving_conversion"] for c in cells if c["basis"] == "per_serving" and c["serving_conversion"]), None)
    return {
        "case_id": panel["panel_id"],
        "input_sha256": panel["image_sha256"],
        "requires_decline": bool(truth.get("requires_decline")),
        "decline_reason": truth.get("decline_reason"),
        "language": "en",
        "jurisdiction": "uk",
        "headers": [
            {"header_id": h, "printed_text": "", "basis": b, "serving_conversion": serving if b == "per_serving" else None}
            for h, b in sorted(headers.items())
        ],
        "serving_size": "unknown",
        "servings_per_pack": "not_recorded",
        "cells": cells,
    }


def load_uk_development_review(workspace: Path) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
    """The 40 exposed v2 public development review images (UK, `en`) with their frozen review.

    Development only: each was exposed by the v2 development review, so none can be
    untouched evidence. A panel the owner excluded in that review is recorded, not scored.
    Returns (cases, exclusions).
    """
    frozen = json.loads((workspace / "frozen-public-development-review-v1.json").read_text(encoding="utf-8"))
    manifest = json.loads((workspace / "review-manifest.json").read_text(encoding="utf-8"))
    files = {p["panel_id"]: p["image_file"] for p in manifest["panels"]}
    if frozen.get("acceptance_gate") is not False:
        raise SealedSetError("the UK review is not a development-only snapshot")
    cases, exclusions = [], []
    for panel in frozen["panels"]:
        panel_id = panel["panel_id"]
        if str(panel["ground_truth"].get("decline_reason") or "").startswith("Exclude "):
            exclusions.append({"id": panel_id, "reason": "excluded by the owner in the v2 development review"})
            continue
        path = workspace / "images" / files[panel_id]
        if sha256_file(path) != panel["image_sha256"]:
            raise ValueError(f"{panel_id} bytes do not match the frozen review")
        cases.append(
            {
                "id": panel_id,
                "input": {"kind": "image", "path": str(path)},
                "truth": uk_truth_from_review(panel),
                "metadata": {
                    "corpus": "uk_v2_development_review",
                    "stratum": "uk_en",
                    "split": "development",
                    "sha256": panel["image_sha256"],
                    "coverage_tags": sorted(panel["ground_truth"].get("families") or []),
                    "licence": "CC BY-SA 3.0 (Open Food Facts)",
                    "attribution": panel.get("image_url"),
                },
            }
        )
    return cases, exclusions


def load_owner_photo(master: Path, consent_path: Path, truth: dict[str, Any], contract_path: Path = CONTRACT) -> dict[str, Any]:
    """The muesli photo for a local route, only with `local_routes` consent (plan section 3.3)."""
    contract = json.loads(contract_path.read_text(encoding="utf-8"))
    expected = contract["corpus"]["muesli"]["stripped_master_sha256"]
    consent = json.loads(consent_path.read_text(encoding="utf-8"))
    if consent.get("master_sha256") != expected or sha256_file(master) != expected:
        raise ValueError("the muesli master or its consent record does not match the contract hash")
    if consent.get("local_routes") is not True:
        raise PermissionError("the owner photo has no local_routes consent")
    return {
        "id": "owner:muesli-6-grain:photo",
        "input": {"kind": "image", "path": str(master)},
        "truth": {**truth, "case_id": "owner:muesli-6-grain:photo", "input_sha256": expected},
        "metadata": {
            "corpus": "owner",
            "stratum": "muesli",
            "split": "development",
            "sha256": expected,
            "coverage_tags": ["zh_hant", "column_offset", "two_column_serving_and_100"],
            "consent_local_routes": True,
            # Route C reads this flag and refuses the photo unless it is exactly true.
            "consent_send_to_openrouter": consent.get("send_to_openrouter") is True,
        },
    }
