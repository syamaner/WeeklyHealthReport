#!/usr/bin/env python3
"""Ingest the owner's muesli photo into the private folder (plan section 3.3).

Copies the original into `<private>/masters/`, strips metadata with
`exiftool -all= -tagsFromFile @ -Orientation` (no pixel re-encoding, orientation
kept), verifies that no GPS, maker note, serial number, owner name or date-time
tag remains, and writes a private consent stub with all four flags `false`.
It refuses any input or output inside a git checkout and prints only hashes,
so nothing personal reaches the repository.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import shutil
import subprocess
import sys
from pathlib import Path

FORBIDDEN_TAG = re.compile(
    r"GPS|MakerNote|SerialNumber|OwnerName|Artist|CameraOwner|DateTimeOriginal|CreateDate|ModifyDate|"
    r"DateTimeDigitized|SubSecTime|OffsetTime|LensModel|Make\b|Model\b|Software|HostComputer",
    re.IGNORECASE,
)
CONSENT_FLAGS = ("local_routes", "send_to_openrouter", "commit_ground_truth", "commit_crop")


def sha256_file(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def inside_git_checkout(path: Path) -> bool:
    probe = path if path.is_dir() else path.parent
    while not probe.exists():
        probe = probe.parent
    result = subprocess.run(["git", "-C", str(probe), "rev-parse", "--show-toplevel"], capture_output=True, text=True)
    return result.returncode == 0


def residual_tags(exif_listing: str) -> list[str]:
    """Return metadata lines that must not survive stripping.

    ICC profile descriptors (for example `ProfileDateTime`, `DeviceModel`) describe the
    colour space, not the capture, and are allowed.
    """
    bad = []
    for line in exif_listing.splitlines():
        if line.startswith(("[File]", "[ExifTool]", "[ICC_Profile]", "[Composite]")):
            continue
        if FORBIDDEN_TAG.search(line):
            bad.append(line.strip())
    return bad


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--private", type=Path, required=True, help="private folder, e.g. ~/WHR-label-eval-private/owner")
    parser.add_argument("--expected-sha256", required=True)
    args = parser.parse_args()
    source = args.source.expanduser().resolve()
    private = args.private.expanduser().resolve()
    if inside_git_checkout(source) or inside_git_checkout(private):
        print("refusing a personal input or output path inside a git checkout", file=sys.stderr)
        return 2
    original = sha256_file(source)
    if original != args.expected_sha256:
        print("source hash does not match the expected original", file=sys.stderr)
        return 3
    masters = private / "masters"
    consent_dir = private / "consent"
    masters.mkdir(parents=True, exist_ok=True)
    consent_dir.mkdir(parents=True, exist_ok=True)
    (private / "runs").mkdir(exist_ok=True)
    master = masters / f"{original[:16]}-stripped.jpg"
    if master.exists():
        print(f"refusing to overwrite {master}", file=sys.stderr)
        return 4
    shutil.copyfile(source, master)
    subprocess.run(["exiftool", "-q", "-overwrite_original", "-all=", "-tagsFromFile", "@", "-Orientation", str(master)], check=True)
    listing = subprocess.run(["exiftool", "-G", "-a", "-s", str(master)], check=True, capture_output=True, text=True).stdout
    bad = residual_tags(listing)
    if bad:
        master.unlink()
        print("metadata stripping failed closed:\n" + "\n".join(bad), file=sys.stderr)
        return 5
    stripped = sha256_file(master)
    consent = {
        "schema_version": "label-capture-consent-v1",
        "master_sha256": stripped,
        "original_sha256": original,
        **{flag: False for flag in CONSENT_FLAGS},
    }
    consent_path = consent_dir / f"{stripped[:16]}.json"
    if not consent_path.exists():
        consent_path.write_text(json.dumps(consent, indent=2) + "\n")
    print(json.dumps({"original_sha256": original, "master_sha256": stripped, "remaining_tag_groups": sorted({line.split("]")[0] + "]" for line in listing.splitlines() if line.startswith("[")})}, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
