#!/usr/bin/env python3
"""Improve unopened-gate drafts with public precomputed OFF OCR sidecars."""

from __future__ import annotations

import argparse
import hashlib
import json
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Any

from build_annotation_draft import propose_semantic_families
from prepare_review import bases_from_text, canonical_json, cells_from_text, transcript_score

PRODUCT_API = "https://world.openfoodfacts.org/api/v2/product/{code}"
USER_AGENT = "WeeklyHealthReport-evaluation/1.0 (https://github.com/syamaner/WeeklyHealthReport)"


def request_bytes(url: str, attempts: int = 6) -> bytes:
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    for attempt in range(attempts):
        try:
            with urllib.request.urlopen(request, timeout=60) as response:
                return response.read()
        except urllib.error.HTTPError as error:
            if error.code != 429 or attempt + 1 == attempts:
                raise
            retry_after = float(error.headers.get("Retry-After", 10))
            time.sleep(max(retry_after, 10 * (attempt + 1)))
        except (urllib.error.URLError, TimeoutError):
            if attempt + 1 == attempts:
                raise
            time.sleep(2 ** attempt)
    raise AssertionError("unreachable")


def extract_transcript(payload: dict[str, Any]) -> str:
    roots = payload.get("responses", [payload])
    root = roots[0] if roots else payload
    return str(
        root.get("fullTextAnnotation", {}).get("text")
        or (root.get("textAnnotations") or [{}])[0].get("description")
        or ""
    ).strip()


def role_and_revision(panel_id: str) -> tuple[str, int]:
    selected = panel_id.rsplit(":", 1)[-1]
    role, revision = selected.rsplit(".", 1)
    return role, int(revision)


def sidecar_url(image_url: str, image_id: str) -> str:
    directory = image_url.rsplit("/", 1)[0]
    return f"{directory}/{image_id}.json"


def refresh_public_drafts(workspace: Path) -> int:
    manifest_path = workspace / "review-manifest.json"
    manifest = json.loads(manifest_path.read_text())
    refreshed = 0
    for panel in manifest["panels"]:
        if panel["draft_source"] != "open-food-facts-google-ocr-sidecar":
            continue
        transcript = panel["draft_transcript"]
        panel["draft_cells"] = cells_from_text(transcript)
        stub = {"headers": [{"basis": basis} for basis in bases_from_text(transcript)]}
        panel["proposed_families"] = propose_semantic_families(transcript, stub)
        refreshed += 1
    manifest_path.write_text(canonical_json(manifest))
    return refreshed


def augment(args: argparse.Namespace) -> None:
    if any((args.workspace / "annotations").glob("*.json")):
        raise ValueError("review has started; drafts can no longer be changed")
    selection = json.loads(args.selection.read_text())
    split_by_id = {panel["panel_id"]: panel["split"] for panel in selection["panels"]}
    manifest_path = args.workspace / "review-manifest.json"
    manifest = json.loads(manifest_path.read_text())
    changed = 0
    for position, panel in enumerate(manifest["panels"], start=1):
        if split_by_id[panel["panel_id"]] != "untouched_gate":
            continue
        role, expected_revision = role_and_revision(panel["panel_id"])
        query = urllib.parse.urlencode({"fields": "code,images"})
        product_payload = json.loads(request_bytes(f"{PRODUCT_API.format(code=panel['product_code'])}?{query}"))
        metadata = product_payload.get("product", {}).get("images", {}).get(role)
        if not metadata or int(metadata.get("rev", -1)) != expected_revision:
            print(f"panel={position}/100 sidecar=missing_metadata", flush=True)
            time.sleep(args.request_interval)
            continue
        url = sidecar_url(panel["image_url"], str(metadata["imgid"]))
        raw = request_bytes(url)
        transcript = extract_transcript(json.loads(raw))
        panel["public_ocr_evidence"] = {
            "image_id": str(metadata["imgid"]),
            "selected_revision": expected_revision,
            "sidecar_url": url,
            "sidecar_sha256": hashlib.sha256(raw).hexdigest(),
        }
        if transcript and transcript_score(transcript) > transcript_score(panel["draft_transcript"]):
            panel["draft_source"] = "open-food-facts-google-ocr-sidecar"
            panel["draft_transcript"] = transcript
            panel["draft_cells"] = cells_from_text(transcript)
            stub = {"headers": [{"basis": basis} for basis in bases_from_text(transcript)]}
            panel["proposed_families"] = propose_semantic_families(transcript, stub)
            changed += 1
        print(f"panel={position}/100 sidecar=available improved={changed}", flush=True)
        time.sleep(args.request_interval)
    manifest_path.write_text(canonical_json(manifest))
    refresh_public_drafts(args.workspace)
    print(f"gate_drafts_improved={changed}/40", flush=True)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--selection", required=True, type=Path)
    parser.add_argument("--workspace", required=True, type=Path)
    parser.add_argument("--request-interval", type=float, default=1.5)
    parser.add_argument("--refresh-only", action="store_true")
    args = parser.parse_args()
    if args.refresh_only:
        print(f"public_drafts_refreshed={refresh_public_drafts(args.workspace)}")
    else:
        augment(args)


if __name__ == "__main__":
    main()
