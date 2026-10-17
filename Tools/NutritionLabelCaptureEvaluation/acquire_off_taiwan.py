#!/usr/bin/env python3
"""Select, pin and download the Open Food Facts Taiwan `nutrition_zh` photos.

Owner-approved on 17 October 2026 (plan section 3.5): 60 photos, about 28.9 MB.
The selection rule is fixed here and covered by unit tests:

1. Search-a-licious query `countries_tags:"en:taiwan"`, every page.
2. Keep products whose `images` include the key `nutrition_zh`.
3. Sort by SHA-256 of the UTF-8 13-digit barcode (`code.zfill(13)`).
4. Take the first 60: the first 20 are development, the next 40 untouched.

Downloads go to a new, empty directory outside any git checkout. Image bytes are
treated as untrusted data: they are hashed and written, never decoded, opened or
executed here. Untouched files go to `sealed/` and are made read-only; this
script never reads them back except to hash them. The committed manifest holds
identities, hashes and attribution only, never image bytes.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import stat
import subprocess
import sys
import time
import urllib.parse
import urllib.request
from collections.abc import Callable, Iterable
from datetime import UTC, datetime
from pathlib import Path
from typing import Any

SEARCH_URL = "https://search.openfoodfacts.org/search"
QUERY = 'countries_tags:"en:taiwan"'
IMAGE_KEY = "nutrition_zh"
IMAGE_BASE = "https://images.openfoodfacts.org/images/products/"
USER_AGENT = "WeeklyHealthReport-public-evaluation/3.0 (https://github.com/syamaner/WeeklyHealthReport)"
PAGE_SIZE = 100
SELECTED = 60
DEVELOPMENT = 20
APPROVED_MAX_BYTES = 40_000_000
LICENCE = "CC BY-SA 3.0"
LICENCE_URL = "https://creativecommons.org/licenses/by-sa/3.0/"
SOURCE_TERMS_URL = "https://world.openfoodfacts.org/terms-of-use"


def barcode13(code: str) -> str:
    if not code.isdigit():
        raise ValueError(f"non-numeric barcode {code!r}")
    return code.zfill(13)


def order_key(code: str) -> str:
    return hashlib.sha256(barcode13(code).encode("utf-8")).hexdigest()


def image_path(code: str) -> str:
    padded = barcode13(code)
    if len(padded) == 13:
        return "/".join([padded[0:3], padded[3:6], padded[6:9], padded[9:]])
    return padded


def candidate_from_hit(hit: dict[str, Any]) -> dict[str, Any] | None:
    images = hit.get("images") or {}
    selected = images.get(IMAGE_KEY)
    if not isinstance(selected, dict):
        return None
    code = str(hit.get("code", ""))
    if not code.isdigit():
        return None
    rev = str(selected["rev"])
    imgid = str(selected.get("imgid", ""))
    raw = images.get(imgid) if imgid else None
    uploader = raw.get("uploader") if isinstance(raw, dict) else None
    return {
        "barcode": code,
        "barcode13": barcode13(code),
        "order_key_sha256": order_key(code),
        "image_key": IMAGE_KEY,
        "revision": rev,
        "raw_image_id": imgid or None,
        "uploader": uploader or "unknown",
        "url": f"{IMAGE_BASE}{image_path(code)}/{IMAGE_KEY}.{rev}.full.jpg",
    }


def rank(hits: Iterable[dict[str, Any]]) -> list[dict[str, Any]]:
    """Every eligible product, in hash order, numbered from 1."""
    seen: dict[str, dict[str, Any]] = {}
    for hit in hits:
        candidate = candidate_from_hit(hit)
        if candidate and candidate["barcode13"] not in seen:
            seen[candidate["barcode13"]] = candidate
    ordered = sorted(seen.values(), key=lambda item: item["order_key_sha256"])
    for index, item in enumerate(ordered):
        item["order"] = index + 1
    return ordered


# Pre-registered refill order (owner decision B, 17 October 2026): the replacements for
# excluded development photos take the next barcodes in hash order (61, 62, ...), and any
# untouched refill comes after them. Up to 27 refills (orders 61 to 87) are approved, each
# downloaded only when an exclusion needs it, with the reason logged.
REFILL_FIRST_ORDER = SELECTED + 1
REFILL_LAST_ORDER = 87


def refill_targets(ranked: list[dict[str, Any]], orders: list[int]) -> list[dict[str, Any]]:
    if any(order < REFILL_FIRST_ORDER or order > REFILL_LAST_ORDER for order in orders):
        raise ValueError("refills are limited to orders 61 to 87")
    by_order = {item["order"]: item for item in ranked}
    missing = [order for order in orders if order not in by_order]
    if missing:
        raise ValueError(f"no eligible product at orders {missing}")
    return [dict(by_order[order]) for order in orders]


def select(hits: Iterable[dict[str, Any]], count: int = SELECTED, development: int = DEVELOPMENT) -> list[dict[str, Any]]:
    chosen = rank(hits)[:count]
    for index, item in enumerate(chosen):
        item["order"] = index + 1
        item["split"] = "development" if index < development else "untouched"
    return chosen


def fetch_json(url: str) -> dict[str, Any]:
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(request, timeout=60) as response:
        return json.loads(response.read().decode("utf-8"))


def fetch_all_hits(
    fetch: Callable[[str], dict[str, Any]] = fetch_json, pause: float = 2.0
) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
    hits: list[dict[str, Any]] = []
    pages: list[dict[str, Any]] = []
    page = 1
    while True:
        query = urllib.parse.urlencode({"q": QUERY, "page": page, "page_size": PAGE_SIZE, "fields": "code,images"})
        url = f"{SEARCH_URL}?{query}"
        payload = fetch(url)
        page_hits = payload.get("hits") or []
        hits.extend(page_hits)
        pages.append({"page": page, "url": url, "hits": len(page_hits), "count": payload.get("count")})
        if page >= int(payload.get("page_count") or 0) or not page_hits:
            return hits, pages
        page += 1
        time.sleep(pause)


def download(url: str) -> bytes:
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(request, timeout=120) as response:
        return response.read()


def refill(argv: list[str]) -> int:
    """Download pre-registered refills into the existing folder and log them in the manifest."""
    parser = argparse.ArgumentParser(description="refill excluded photos in pre-registered hash order")
    parser.add_argument("--out", type=Path, required=True, help="the existing photo folder outside any git checkout")
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--replace", required=True, help="comma-separated orders being replaced, e.g. 4,17")
    parser.add_argument("--reason", required=True, help="logged exclusion reason for the replaced photos")
    parser.add_argument("--max-bytes", type=int, required=True, help="hard stop for this refill batch")
    args = parser.parse_args(argv)

    out = args.out.expanduser().resolve()
    probe = subprocess.run(["git", "-C", str(out), "rev-parse", "--show-toplevel"], capture_output=True, text=True)
    if probe.returncode == 0:
        print(f"refusing a folder inside a git checkout: {probe.stdout.strip()}", file=sys.stderr)
        return 2
    manifest = json.loads(args.manifest.read_text(encoding="utf-8"))
    replaced = [int(order) for order in args.replace.split(",")]
    photos = {p["order"]: p for p in manifest["photos"]}
    if any(order not in photos for order in replaced):
        print("an order to replace is not in the manifest", file=sys.stderr)
        return 3
    if len({photos[order]["split"] for order in replaced}) != 1:
        print("one refill batch replaces photos from one split only", file=sys.stderr)
        return 3
    split = photos[replaced[0]]["split"]
    previous = manifest.get("refills", [])
    used = sorted(item["order"] for item in previous)
    next_order = (used[-1] + 1) if used else REFILL_FIRST_ORDER
    if split == "development" and any(p["split"] == "untouched" for p in previous):
        print("development replacements must precede untouched refills in hash order", file=sys.stderr)
        return 3
    orders = list(range(next_order, next_order + len(replaced)))

    hits, _ = fetch_all_hits()
    ranked = rank(hits)
    first = {item["barcode13"]: item["order"] for item in ranked[:SELECTED]}
    if first != {p["barcode13"]: p["order"] for p in manifest["photos"]}:
        print("the first 60 in hash order no longer match the manifest; stopping", file=sys.stderr)
        return 4
    targets = refill_targets(ranked, orders)
    folder = out / ("development" if split == "development" else "sealed")
    total = 0
    downloaded: list[tuple[Path, bytes, dict[str, Any]]] = []
    for item, old in zip(targets, replaced, strict=True):
        data = download(item["url"])
        total += len(data)
        if total > args.max_bytes:
            print(f"refill batch {total} bytes exceeds the {args.max_bytes} byte stop; nothing written", file=sys.stderr)
            return 5
        item.update(
            {
                "split": split,
                "replaces_order": old,
                "replacement_reason": args.reason,
                "bytes": len(data),
                "sha256": hashlib.sha256(data).hexdigest(),
                "attribution": (
                    f"Nutrition label photo of product {item['barcode']} by Open Food Facts contributor "
                    f"{item['uploader']}, {LICENCE} ({LICENCE_URL}), from Open Food Facts ({item['url']})."
                ),
            }
        )
        downloaded.append((folder / f"{item['order']:02d}-{item['barcode13']}-{IMAGE_KEY}.{item['revision']}.jpg", data, item))
        time.sleep(0.5)
    for target, data, _ in downloaded:
        if target.exists():
            print(f"refusing to overwrite {target}", file=sys.stderr)
            return 6
        target.write_bytes(data)
        if split != "development":
            os.chmod(target, stat.S_IRUSR | stat.S_IRGRP)
    for order in replaced:
        photos[order]["excluded"] = True
        photos[order]["exclusion_reason"] = args.reason
    manifest["refills"] = previous + [item for _, _, item in downloaded]
    manifest["refill_rule"] = (
        "Owner decision B, 17 October 2026: up to 27 refills (orders 61 to 87) in hash order, each downloaded only when an "
        "exclusion needs it, reason logged. Development replacements take the next orders first (61, 62), untouched refills after."
    )
    args.manifest.write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + "\n")
    print(
        json.dumps(
            [{k: i[k] for k in ("order", "barcode13", "revision", "bytes", "sha256", "replaces_order")} for _, _, i in downloaded], indent=1
        )
    )
    print(f"refill batch total {total} bytes")
    return 0


def main() -> int:
    if len(sys.argv) > 1 and sys.argv[1] == "refill":
        return refill(sys.argv[2:])
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", type=Path, required=True, help="new, empty directory outside any git checkout")
    parser.add_argument("--expected-urls", type=Path, help="candidate URL list to compare with the re-derived selection")
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--search-snapshot", type=Path, help="optional path to write the raw search pages summary")
    args = parser.parse_args()

    out = args.out.expanduser().resolve()
    if out.exists() and any(out.iterdir()):
        print(f"refusing non-empty output directory {out}", file=sys.stderr)
        return 2
    probe = subprocess.run(["git", "-C", str(out.parent), "rev-parse", "--show-toplevel"], capture_output=True, text=True)
    if probe.returncode == 0:
        print(f"refusing output inside a git checkout: {probe.stdout.strip()}", file=sys.stderr)
        return 2

    hits, pages = fetch_all_hits()
    chosen = select(hits)
    eligible = len({found["barcode13"] for h in hits if (found := candidate_from_hit(h)) is not None})
    if len(chosen) != SELECTED:
        print(f"only {len(chosen)} eligible products", file=sys.stderr)
        return 3
    comparison = None
    if args.expected_urls:
        expected = [line.strip() for line in args.expected_urls.read_text().splitlines() if line.strip()]
        derived = [item["url"] for item in chosen]
        comparison = {
            "expected_count": len(expected),
            "same_order": expected == derived,
            "same_set": set(expected) == set(derived),
            "missing_from_derived": sorted(set(expected) - set(derived)),
            "extra_in_derived": sorted(set(derived) - set(expected)),
        }
        print(json.dumps(comparison, indent=1))
        if not comparison["same_set"]:
            print("re-derived selection differs from the candidate list; stopping before download", file=sys.stderr)
            return 4

    (out / "development").mkdir(parents=True)
    (out / "sealed").mkdir()
    total = 0
    for item in chosen:
        data = download(item["url"])
        total += len(data)
        if total > APPROVED_MAX_BYTES:
            print(f"cumulative size {total} exceeds the approved {APPROVED_MAX_BYTES}; stopping", file=sys.stderr)
            return 5
        item["bytes"] = len(data)
        item["sha256"] = hashlib.sha256(data).hexdigest()
        folder = "development" if item["split"] == "development" else "sealed"
        target = out / folder / f"{item['order']:02d}-{item['barcode13']}-{IMAGE_KEY}.{item['revision']}.jpg"
        target.write_bytes(data)
        if folder == "sealed":
            os.chmod(target, stat.S_IRUSR | stat.S_IRGRP)
        item["attribution"] = (
            f"Nutrition label photo of product {item['barcode']} by Open Food Facts contributor "
            f"{item['uploader']}, {LICENCE} ({LICENCE_URL}), from Open Food Facts ({item['url']})."
        )
        time.sleep(0.5)
    os.chmod(out / "sealed", stat.S_IRUSR | stat.S_IXUSR | stat.S_IRGRP | stat.S_IXGRP)

    manifest = {
        "schema_version": "off-taiwan-photo-manifest-v1",
        "acquired_at": datetime.now(UTC).replace(microsecond=0).isoformat(),
        "owner_approval": "Owner approved 60 Open Food Facts Taiwan nutrition_zh photos (about 28.9 MB) on 17 October 2026.",
        "selection_rule": {
            "query": QUERY,
            "endpoint": SEARCH_URL,
            "image_key": IMAGE_KEY,
            "order": "ascending SHA-256 of the UTF-8 13-digit barcode (code zero-padded to 13)",
            "selected": SELECTED,
            "development": "orders 1 to 20",
            "untouched": "orders 21 to 60",
            "eligible_products_on_day": eligible,
            "search_result_count_on_day": pages[0]["count"] if pages else None,
        },
        "candidate_list_comparison": comparison,
        "licence": LICENCE,
        "licence_url": LICENCE_URL,
        "source_terms_url": SOURCE_TERMS_URL,
        "storage": "Image bytes are kept outside the repository; none are committed.",
        "sealing": (
            "Untouched files were hashed on download and written read-only to a separate sealed folder. "
            "They are not opened, viewed, OCR'd or sent to any model before the single frozen run."
        ),
        "total_bytes": total,
        "photos": chosen,
    }
    args.manifest.write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + "\n")
    if args.search_snapshot:
        args.search_snapshot.write_text(json.dumps(pages, indent=2) + "\n")
    print(f"downloaded {len(chosen)} photos, {total} bytes")
    return 0


if __name__ == "__main__":
    sys.exit(main())
