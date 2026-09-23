#!/usr/bin/env python3
"""Acquire public raw nutrition images for the pre-registered v2 inventory.

This prepares candidates only. It never runs OCR, assigns ground truth, or
opens the untouched gate. The output directory should be local and ignored.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Callable

from validate_contract_v2 import select_split, validate


SEARCH_URL = "https://uk.openfoodfacts.org/api/v2/search"
USER_AGENT = "WeeklyHealthReport-public-evaluation/2.0 (https://github.com/syamaner/WeeklyHealthReport)"
PAGE_SIZE = 100
SEARCH_INTERVAL_SECONDS = 6.5  # Open Food Facts documents 10 search requests/minute.
MAX_IMAGE_BYTES = 25_000_000


def canonical_json(value: Any) -> bytes:
    return (json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")) + "\n").encode()


def request_bytes(url: str, *, attempts: int = 3) -> bytes:
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    for attempt in range(attempts):
        try:
            with urllib.request.urlopen(request, timeout=60) as response:
                content = response.read(MAX_IMAGE_BYTES + 1)
            if len(content) > MAX_IMAGE_BYTES:
                raise ValueError("public response exceeds byte cap")
            return content
        except (urllib.error.HTTPError, urllib.error.URLError, TimeoutError):
            if attempt + 1 == attempts:
                raise
            time.sleep(2 ** attempt)
    raise AssertionError("unreachable")


def legacy_exclusions(manifests: list[Path]) -> tuple[set[str], set[str], set[str]]:
    ids: set[str] = set()
    hashes: set[str] = set()
    codes: set[str] = set()
    for path in manifests:
        for panel in json.loads(path.read_text()).get("panels", []):
            identifier = panel.get("panel_id")
            digest = panel.get("image_sha256")
            if identifier:
                ids.add(identifier)
                match = re.match(r"^off:([0-9]{8,14}):", identifier)
                if match:
                    codes.add(match.group(1))
            if digest:
                hashes.add(digest)
            source_code = panel.get("source", {}).get("product_code")
            if source_code:
                codes.add(str(source_code))
    return ids, hashes, codes


def selected_raw_source(product: dict[str, Any], contract: dict[str, Any]) -> dict[str, str] | None:
    code = str(product.get("code", ""))
    if not re.fullmatch(r"[0-9]{8,14}", code):
        return None
    if contract["corpus"]["country_tag"] not in product.get("countries_tags", []):
        return None
    role = product.get("images", {}).get("nutrition_en", {})
    raw_id = str(role.get("imgid", ""))
    revision = str(role.get("rev", ""))
    if not raw_id.isdigit() or not revision.isdigit():
        return None
    padded = code.zfill(13)
    folder = f"{padded[:3]}/{padded[3:6]}/{padded[6:9]}/{padded[9:]}"
    return {
        "panel_id": f"off:{code}:nutrition_en.{revision}:raw-{raw_id}",
        "product_code": code,
        "selection_revision": revision,
        "raw_image_id": raw_id,
        "selected_role": "nutrition_en",
        "source_provider": "Open Food Facts",
        "country_tag": contract["corpus"]["country_tag"],
        "source_licence_url": contract["corpus"]["source_licence_url"],
        "raw_image_url": f"{contract['corpus']['source_aws_base_url']}{folder}/{raw_id}.jpg",
    }


def search_url(page: int) -> str:
    query = urllib.parse.urlencode({
        "fields": "code,product_name,countries_tags,images",
        "page": page,
        "page_size": PAGE_SIZE,
    })
    return f"{SEARCH_URL}?{query}"


def save_checkpoint(path: Path, state: dict[str, Any]) -> None:
    staged = path.with_suffix(".json.tmp")
    staged.write_bytes(canonical_json(state))
    staged.replace(path)


def acquire(
    contract: dict[str, Any], output_dir: Path, *, excluded_ids: set[str],
    excluded_hashes: set[str], excluded_codes: set[str], target: int,
    maximum_pages: int, fetch: Callable[[str], bytes] = request_bytes,
    sleep: Callable[[float], None] = time.sleep,
    newly_exposed_codes: set[str] | None = None,
) -> dict[str, Any]:
    validate(contract)
    if target < contract["corpus"]["minimum_new_candidates"]:
        raise ValueError("target is below the pre-registered eligible minimum")
    output_dir.mkdir(parents=True, exist_ok=True)
    image_dir = output_dir / "images"
    image_dir.mkdir(exist_ok=True)
    checkpoint = output_dir / "candidate-inventory-v2.json"
    newly_exposed_codes = newly_exposed_codes or set()

    def digest_exclusions(codes: set[str]) -> str:
        return hashlib.sha256(canonical_json({
            "panel_ids": sorted(excluded_ids),
            "image_hashes": sorted(excluded_hashes),
            "product_codes": sorted(codes),
        })).hexdigest()

    effective_excluded_codes = excluded_codes | newly_exposed_codes
    exclusion_digest = digest_exclusions(effective_excluded_codes)
    if checkpoint.exists():
        state = json.loads(checkpoint.read_text())
        if state.get("contract_sha256") != hashlib.sha256(canonical_json(contract)).hexdigest():
            raise ValueError("checkpoint was made with a different contract")
        if (newly_exposed_codes and state.get("exclusions_sha256") == digest_exclusions(excluded_codes)
                and state.get("exclusions_sha256") != exclusion_digest):
            exposed = [panel for panel in state["panels"] if panel["product_code"] in newly_exposed_codes]
            if {panel["product_code"] for panel in exposed} != newly_exposed_codes:
                raise ValueError("new development exposure was not in the candidate inventory")
            state.setdefault("development_exposures", []).extend({
                "panel_id": panel["panel_id"], "image_sha256": panel["image_sha256"],
                "reason": "source_feasibility_visual_probe_before_split",
            } for panel in exposed)
            state["panels"] = [panel for panel in state["panels"] if panel["product_code"] not in newly_exposed_codes]
            state["exclusions_sha256"] = exclusion_digest
            save_checkpoint(checkpoint, state)
        if state.get("exclusions_sha256") != exclusion_digest:
            raise ValueError("checkpoint was made with different development exclusions")
    else:
        state = {
            "schema_version": 2,
            "status": "candidate_inventory_only_no_ground_truth_or_gate",
            "contract_sha256": hashlib.sha256(canonical_json(contract)).hexdigest(),
            "exclusions_sha256": exclusion_digest,
            "started_at": datetime.now(timezone.utc).isoformat(),
            "next_page": 1,
            "search_responses": [],
            "panels": [],
            "source_only_exclusions": [],
            "development_exposures": [],
        }
    excluded_codes = effective_excluded_codes
    seen_codes = {panel["product_code"] for panel in state["panels"]}
    seen_hashes = {panel["image_sha256"] for panel in state["panels"]}
    while len(state["panels"]) < target and state["next_page"] <= maximum_pages:
        page = state["next_page"]
        if page > 1:
            sleep(SEARCH_INTERVAL_SECONDS)
        raw = fetch(search_url(page))
        payload = json.loads(raw)
        if not isinstance(payload.get("products"), list):
            raise ValueError("search response lacks products")
        state["search_responses"].append({"page": page, "sha256": hashlib.sha256(raw).hexdigest()})
        for product in payload["products"]:
            source = selected_raw_source(product, contract)
            if source is None:
                continue
            code = source["product_code"]
            if code in excluded_codes or code in seen_codes:
                continue
            try:
                image = fetch(source["raw_image_url"])
            except (urllib.error.HTTPError, urllib.error.URLError, TimeoutError, ValueError) as error:
                state["source_only_exclusions"].append({
                    "panel_id": source["panel_id"], "reason": "raw_image_unavailable",
                    "error_type": type(error).__name__,
                })
                continue
            if not image.startswith(b"\xff\xd8\xff") or not image.endswith(b"\xff\xd9"):
                state["source_only_exclusions"].append({
                    "panel_id": source["panel_id"], "reason": "not_complete_jpeg",
                })
                continue
            digest = hashlib.sha256(image).hexdigest()
            if digest in excluded_hashes or digest in seen_hashes or source["panel_id"] in excluded_ids:
                state["source_only_exclusions"].append({
                    "panel_id": source["panel_id"], "reason": "previously_exposed_or_duplicate_image",
                })
                continue
            local_name = f"{source['panel_id'].replace(':', '_')}_{digest[:12]}.jpg"
            local_path = image_dir / local_name
            local_path.write_bytes(image)
            state["panels"].append({
                **source,
                "image_sha256": digest,
                "local_image": str(local_path.relative_to(output_dir)),
                "product_name_hint": product.get("product_name") or None,
                "ground_truth": {"verification_status": "pending"},
            })
            seen_codes.add(code)
            seen_hashes.add(digest)
            if len(state["panels"]) == target:
                break
        state["next_page"] = page + 1
        save_checkpoint(checkpoint, state)
        print(f"page={page} eligible={len(state['panels'])} source_exclusions={len(state['source_only_exclusions'])}", file=sys.stderr, flush=True)
    return state


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--contract", required=True, type=Path)
    parser.add_argument("--output-dir", required=True, type=Path)
    parser.add_argument("--exclude-manifest", required=True, type=Path, action="append")
    parser.add_argument("--target", type=int, default=140)
    parser.add_argument("--maximum-pages", type=int, default=20)
    parser.add_argument("--exclude-development-probe-code", action="append", default=[])
    args = parser.parse_args()
    contract = json.loads(args.contract.read_text())
    excluded_ids, excluded_hashes, excluded_codes = legacy_exclusions(args.exclude_manifest)
    state = acquire(
        contract, args.output_dir, excluded_ids=excluded_ids,
        excluded_hashes=excluded_hashes, excluded_codes=excluded_codes,
        target=args.target, maximum_pages=args.maximum_pages,
        newly_exposed_codes=set(args.exclude_development_probe_code),
    )
    print(f"eligible={len(state['panels'])}; required={args.target}; gate_unopened=true")
    if len(state["panels"]) < args.target:
        raise SystemExit("public inventory did not reach the pre-registered minimum")
    for panel in state["panels"]:
        expected_name = f"{panel['panel_id'].replace(':', '_')}_{panel['image_sha256'][:12]}.jpg"
        if panel["local_image"] != f"images/{expected_name}":
            raise ValueError("candidate local image path does not match frozen identity")
        actual_hash = hashlib.sha256((args.output_dir / panel["local_image"]).read_bytes()).hexdigest()
        if actual_hash != panel["image_sha256"]:
            raise ValueError("candidate image bytes no longer match inventory SHA-256")
    # Selection remains a separate deliberate freeze operation. This verifies
    # that every candidate has the contract's provenance and no legacy overlap.
    select_split(
        contract, state["panels"], excluded_panel_ids=excluded_ids,
        excluded_image_hashes=excluded_hashes,
        excluded_product_codes=excluded_codes | set(args.exclude_development_probe_code),
    )


if __name__ == "__main__":
    main()
