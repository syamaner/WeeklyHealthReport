#!/usr/bin/env python3
"""The E13 qualification case list (docs/label-photo-ai-prefill-v1.md E13 and 17.21).

Writes the case list the Swift runner (`Tools/LabelPhotoE13`) reads, outside the repository:

- the 20 usable Taiwan development photos and the 40 usable untouched Taiwan photos, found by the
  SHA-256 their truth records pin (a photo whose bytes do not match is an error);
- the 10 remaining approved refills, orders 78 to 87 (owner decision B, 17 October 2026, and the
  E13 approval). With `--download-refills` they are downloaded from Open Food Facts (public
  CC BY-SA 3.0 images, no key) into their own folder, after re-deriving the hash order and checking
  that it still gives the manifest's refills 61 to 77 at the same orders; any difference stops
  before downloading. A 10,000,000 byte stop covers the batch. They have no truth yet, so E13
  reports them for identity, cost, latency and declines only.

Nothing here calls a model. The list and the refill manifest hold paths, hashes and attribution.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
from pathlib import Path
from typing import Any

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

import acquire_off_taiwan as off  # noqa: E402

MANIFEST = HERE / "fixtures" / "off-taiwan-manifest-v1.json"
DEVELOPMENT_TRUTH = HERE / "fixtures" / "ground-truth-off-taiwan-development-v1.json"
UNTOUCHED_TRUTH = HERE / "fixtures" / "ground-truth-off-taiwan-untouched-v1.json"
E13_REFILL_ORDERS = list(range(78, 88))
REFILL_STOP_BYTES = 10_000_000


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def usable_records(path: Path) -> list[dict[str, Any]]:
    return [r for r in json.loads(path.read_text(encoding="utf-8"))["records"] if not r.get("excluded")]


def photo_cases(records: list[dict[str, Any]], folder: Path, split: str) -> list[dict[str, Any]]:
    by_hash = {sha256(p): p for p in sorted(folder.glob("*.jpg"))}
    cases = []
    for record in records:
        path = by_hash.get(record["input_sha256"])
        if path is None:
            raise SystemExit(f"{record['case_id']}: no photo in {folder} has its pinned SHA-256")
        cases.append({"id": record["case_id"], "split": split, "path": str(path), "sha256": record["input_sha256"]})
    return cases


def check_order(ranked: list[dict[str, Any]], manifest: dict[str, Any]) -> None:
    """The re-derived hash order must still give every manifest photo, refills included, its order."""
    by_order = {item["order"]: item["barcode13"] for item in ranked}
    for photo in [*manifest["photos"], *manifest["refills"]]:
        if by_order.get(photo["order"]) != photo["barcode13"]:
            raise SystemExit(f"order {photo['order']} is no longer {photo['barcode13']}; the hash order changed, nothing downloaded")


def download_refills(folder: Path) -> list[dict[str, Any]]:
    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    hits, _ = off.fetch_all_hits()
    ranked = off.rank(hits)
    check_order(ranked, manifest)
    targets = off.refill_targets(ranked, E13_REFILL_ORDERS)
    folder.mkdir(parents=True, exist_ok=True)
    total, photos = 0, []
    for target in targets:
        data = off.download(target["url"])
        total += len(data)
        if total > REFILL_STOP_BYTES:
            raise SystemExit(f"the {REFILL_STOP_BYTES} byte stop was reached at order {target['order']}; later orders not written")
        path = folder / f"{target['order']:02d}-{target['barcode13']}-nutrition_zh.{target['revision']}.jpg"
        path.write_bytes(data)
        photos.append(
            {
                **target,
                "split": "e13_refill",
                "bytes": len(data),
                "sha256": hashlib.sha256(data).hexdigest(),
                "attribution": f"Nutrition label photo of product {target['barcode13']} by Open Food Facts contributor "
                f"{target['uploader']}, {off.LICENCE} ({off.LICENCE_URL})",
            }
        )
    (folder / "e13-refills-manifest.json").write_text(
        json.dumps({"orders": E13_REFILL_ORDERS, "licence": off.LICENCE, "total_bytes": total, "photos": photos}, indent=1) + "\n"
    )
    return photos


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    private = Path.home() / "WHR-label-eval-private"
    parser.add_argument("--photos", type=Path, default=private / "off-taiwan-v1")
    parser.add_argument("--refills", type=Path, default=private / "e13-refills-v1")
    parser.add_argument("--download-refills", action="store_true")
    parser.add_argument("--out", type=Path, required=True, help="the case list, outside the repository")
    args = parser.parse_args(argv)
    if args.out.resolve().is_relative_to(HERE.parents[1]):
        raise SystemExit("--out must be outside the repository")
    cases = photo_cases(usable_records(DEVELOPMENT_TRUTH), args.photos / "development", "development")
    cases += photo_cases(usable_records(UNTOUCHED_TRUTH), args.photos / "sealed", "untouched")
    if args.download_refills:
        download_refills(args.refills)
    refill_manifest = json.loads((args.refills / "e13-refills-manifest.json").read_text(encoding="utf-8"))
    for photo in refill_manifest["photos"]:
        path = args.refills / f"{photo['order']:02d}-{photo['barcode13']}-nutrition_zh.{photo['revision']}.jpg"
        if sha256(path) != photo["sha256"]:
            raise SystemExit(f"refill order {photo['order']} does not match its recorded SHA-256")
        cases.append(
            {
                "id": f"off-taiwan:{photo['barcode13']}:nutrition_zh.{photo['revision']}",
                "split": "e13_refill",
                "path": str(path),
                "sha256": photo["sha256"],
            }
        )
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(cases, indent=1) + "\n", encoding="utf-8")
    print({split: sum(c["split"] == split for c in cases) for split in ("development", "untouched", "e13_refill")})
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
