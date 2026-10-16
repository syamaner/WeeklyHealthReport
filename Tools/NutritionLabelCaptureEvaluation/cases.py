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
    for photo in manifest["photos"]:
        if photo["split"] != "development":
            continue
        case_id = f"off-taiwan:{photo['barcode13']}:nutrition_zh.{photo['revision']}"
        path = image_root / "development" / f"{photo['order']:02d}-{photo['barcode13']}-nutrition_zh.{photo['revision']}.jpg"
        if sha256_file(path) != photo["sha256"]:
            raise ValueError(f"{case_id} bytes do not match the manifest")
        cases.append({
            "id": case_id,
            "input": {"kind": "image", "path": str(path)},
            "truth": truths.get(case_id),
            "metadata": {"corpus": "off_taiwan", "split": "development", "sha256": photo["sha256"],
                         "coverage_tags": ["zh_hant"], "licence": manifest["licence"], "attribution": photo["attribution"]},
        })
    return cases


def load_untouched_photos(manifest_path: Path, image_root: Path, *, unseal: bool, manifest_sha256: str | None,
                          truth_path: Path | None = None, contract_path: Path = CONTRACT) -> list[dict[str, Any]]:
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
    for photo in manifest["photos"]:
        if photo["split"] != "untouched":
            continue
        case_id = f"off-taiwan:{photo['barcode13']}:nutrition_zh.{photo['revision']}"
        path = image_root / "sealed" / f"{photo['order']:02d}-{photo['barcode13']}-nutrition_zh.{photo['revision']}.jpg"
        cases.append({
            "id": case_id,
            "input": {"kind": "image", "path": str(path)},
            "truth": truths[case_id],
            "metadata": {"corpus": "off_taiwan", "split": "untouched", "sha256": photo["sha256"],
                         "licence": manifest["licence"], "attribution": photo["attribution"]},
        })
    return cases
