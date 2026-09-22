#!/usr/bin/env python3
"""Acquire a hash-pinned public candidate corpus from Open Food Facts."""

from __future__ import annotations

import argparse
import gzip
import hashlib
import json
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from corpus import split_for

API = "https://uk.openfoodfacts.org/api/v2/search"
PRODUCT_API = "https://world.openfoodfacts.org/api/v2/product/{code}"
LICENCE = "https://openfoodfacts.github.io/documentation/docs/Product-Opener/api/tutorials/license-be-on-the-legal-side/"
USER_AGENT = "WeeklyHealthReport-evaluation/1.0 (https://github.com/syamaner/WeeklyHealthReport)"


def canonical_json(value: Any) -> bytes:
    return (json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")) + "\n").encode()


def request_bytes(url: str, *, attempts: int = 5) -> bytes:
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    for attempt in range(attempts):
        try:
            with urllib.request.urlopen(request, timeout=60) as response:
                return response.read()
        except (urllib.error.HTTPError, urllib.error.URLError, TimeoutError):
            if attempt + 1 == attempts:
                raise
            time.sleep(2 ** attempt)
    raise AssertionError("unreachable")


def full_image_url(display_url: str) -> str:
    suffix = ".400.jpg"
    if not display_url.startswith("https://images.openfoodfacts.org/") or not display_url.endswith(suffix):
        raise ValueError(f"unsupported selected image URL: {display_url}")
    return display_url[: -len(suffix)] + ".full.jpg"


def selected_nutrition(product: dict[str, Any]) -> tuple[str, str] | None:
    display = product.get("selected_images", {}).get("nutrition", {}).get("display", {})
    if not display:
        return None
    language = "en" if "en" in display else sorted(display)[0]
    return language, full_image_url(display[language])


def panel_id(code: str, image_url: str) -> str:
    filename = image_url.rsplit("/", 1)[-1]
    stem = filename.removesuffix(".full.jpg")
    return f"off:{code}:{stem}"


def candidate_codes_from_aws_index(path: Path) -> list[str]:
    codes: set[str] = set()
    with gzip.open(path, "rt") as source:
        for key in source:
            key = key.strip()
            if not key.startswith("data/50") or not key.endswith(".json.gz"):
                continue
            parts = key.removeprefix("data/").split("/")
            if len(parts) < 2 or not parts[-1].removesuffix(".json.gz").isdigit():
                continue
            code = "".join(parts[:-1])
            if 8 <= len(code) <= 14 and code.isdigit():
                codes.add(code)
    return sorted(codes, key=lambda code: hashlib.sha256(f"issue88-candidate-v1:{code}".encode()).digest())


def panel_from_product(product: dict[str, Any], image_dir: Path) -> dict[str, Any] | None:
    selection = selected_nutrition(product)
    if not selection or "en:united-kingdom" not in product.get("countries_tags", []):
        return None
    language, image_url = selection
    image_bytes = request_bytes(image_url)
    image_hash = hashlib.sha256(image_bytes).hexdigest()
    code = str(product["code"])
    identifier = panel_id(code, image_url)
    local_name = f"{identifier.replace(':', '_')}_{image_hash[:12]}.jpg"
    (image_dir / local_name).write_bytes(image_bytes)
    return {
        "panel_id": identifier,
        "image_sha256": image_hash,
        "split": split_for(identifier, image_hash),
        "country_tag": "en:united-kingdom",
        "families": [],
        "local_image": local_name,
        "source": {
            "provider": "Open Food Facts",
            "product_code": code,
            "product_name": product.get("product_name") or None,
            "image_language": language,
            "image_url": image_url,
            "licence_url": LICENCE,
            "nutrition_data_per_hint": product.get("nutrition_data_per") or None,
            "serving_size_hint": product.get("serving_size") or None,
        },
        "ground_truth": {"verification_status": "pending"},
    }


def discover_from_aws_index(args: argparse.Namespace) -> dict[str, Any]:
    panels: list[dict[str, Any]] = []
    response_evidence: list[dict[str, Any]] = []
    args.image_dir.mkdir(parents=True, exist_ok=True)
    codes = candidate_codes_from_aws_index(args.aws_key_index)
    for position, code in enumerate(codes[: args.maximum_products], start=1):
        query = urllib.parse.urlencode({
            "fields": "code,product_name,countries_tags,selected_images,nutrition_data_per,serving_size"
        })
        raw = request_bytes(f"{PRODUCT_API.format(code=code)}?{query}")
        response_evidence.append({"product_code": code, "sha256": hashlib.sha256(raw).hexdigest()})
        payload = json.loads(raw)
        product = payload.get("product") if payload.get("status") == 1 else None
        panel = panel_from_product(product, args.image_dir) if product else None
        if panel is not None and panel["image_sha256"] not in {item["image_sha256"] for item in panels}:
            panels.append(panel)
        if position % 10 == 0 or panel is not None:
            print(f"products_checked={position} selected_panels={len(panels)}", file=sys.stderr, flush=True)
        if len(panels) == args.target:
            break
        time.sleep(args.product_request_interval)
    return {
        "schema_version": 1,
        "acquired_at": datetime.now(timezone.utc).isoformat(),
        "discovery": {
            "api": PRODUCT_API,
            "aws_key_index_sha256": hashlib.sha256(args.aws_key_index.read_bytes()).hexdigest(),
            "candidate_order": "sha256('issue88-candidate-v1:' + product_code)",
            "response_evidence": response_evidence,
            "user_agent": USER_AGENT,
        },
        "panels": panels,
    }


def discover(args: argparse.Namespace) -> dict[str, Any]:
    panels: list[dict[str, Any]] = []
    seen_urls: set[str] = set()
    response_evidence: list[dict[str, Any]] = []
    args.image_dir.mkdir(parents=True, exist_ok=True)

    page = args.start_page
    while len(panels) < args.target and page < args.start_page + args.maximum_pages:
        query = urllib.parse.urlencode({
            "fields": "code,product_name,countries_tags,selected_images,nutrition_data_per,serving_size",
            "page": page,
            "page_size": args.page_size,
        })
        raw = request_bytes(f"{API}?{query}")
        response_evidence.append({"page": page, "sha256": hashlib.sha256(raw).hexdigest()})
        payload = json.loads(raw)
        for product in payload.get("products", []):
            selection = selected_nutrition(product)
            if not selection or "en:united-kingdom" not in product.get("countries_tags", []):
                continue
            language, image_url = selection
            if image_url in seen_urls:
                continue
            seen_urls.add(image_url)
            image_bytes = request_bytes(image_url)
            image_hash = hashlib.sha256(image_bytes).hexdigest()
            code = str(product["code"])
            identifier = panel_id(code, image_url)
            local_name = f"{identifier.replace(':', '_')}_{image_hash[:12]}.jpg"
            (args.image_dir / local_name).write_bytes(image_bytes)
            panels.append({
                "panel_id": identifier,
                "image_sha256": image_hash,
                "split": split_for(identifier, image_hash),
                "country_tag": "en:united-kingdom",
                "families": [],
                "local_image": local_name,
                "source": {
                    "provider": "Open Food Facts",
                    "product_code": code,
                    "product_name": product.get("product_name") or None,
                    "image_language": language,
                    "image_url": image_url,
                    "licence_url": LICENCE,
                    "nutrition_data_per_hint": product.get("nutrition_data_per") or None,
                    "serving_size_hint": product.get("serving_size") or None,
                },
                "ground_truth": {"verification_status": "pending"},
            })
            if len(panels) == args.target:
                break
        print(f"page={page} selected_panels={len(panels)}", file=sys.stderr, flush=True)
        page += 1
        if len(panels) < args.target:
            time.sleep(args.request_interval)

    return {
        "schema_version": 1,
        "acquired_at": datetime.now(timezone.utc).isoformat(),
        "discovery": {
            "api": API,
            "first_page": args.start_page,
            "last_page": page - 1,
            "page_size": args.page_size,
            "response_evidence": response_evidence,
            "user_agent": USER_AGENT,
        },
        "panels": panels,
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--image-dir", required=True, type=Path)
    parser.add_argument("--target", type=int, default=140)
    parser.add_argument("--start-page", type=int, default=1)
    parser.add_argument("--maximum-pages", type=int, default=500)
    parser.add_argument("--page-size", type=int, default=10, choices=range(1, 11))
    parser.add_argument("--request-interval", type=float, default=6.5)
    parser.add_argument("--aws-key-index", type=Path)
    parser.add_argument("--maximum-products", type=int, default=2000)
    parser.add_argument("--product-request-interval", type=float, default=0.75)
    args = parser.parse_args()
    if args.target < 100:
        raise SystemExit("target must be at least 100 real panels")
    manifest = discover_from_aws_index(args) if args.aws_key_index else discover(args)
    args.output.write_bytes(canonical_json(manifest))
    if len(manifest["panels"]) < args.target:
        raise SystemExit(f"only acquired {len(manifest['panels'])} of {args.target} requested panels")


if __name__ == "__main__":
    main()
