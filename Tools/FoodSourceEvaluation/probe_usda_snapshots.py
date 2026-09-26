#!/usr/bin/env python3
"""Inspect local, official USDA JSON ZIP snapshots; does not access the network."""
import argparse
import hashlib
import json
import zipfile
from pathlib import Path

QUERIES = ("ribeye", "rib eye", "fish and chips", "fish, battered", "fish, fried")

def inspect(path):
    data = path.read_bytes()
    if len(data) > 20_000_000:
        raise ValueError("Archive exceeds 20 MB probe bound")
    with zipfile.ZipFile(path) as archive:
        members = [n for n in archive.namelist() if n.endswith(".json")]
        if len(members) != 1 or archive.getinfo(members[0]).file_size > 250_000_000:
            raise ValueError("Expected one bounded JSON member")
        content = archive.read(members[0])
    decoded = json.loads(content)
    if not isinstance(decoded, dict) or len(decoded) != 1:
        raise ValueError("Expected a single USDA record-array wrapper")
    entries = next(iter(decoded.values()))
    if not isinstance(entries, list):
        raise ValueError("Expected a USDA record array")
    records = [record for record in entries if isinstance(record, dict)]
    return {
        "archive": path.name,
        "archiveBytes": len(data),
        "archiveSHA256": hashlib.sha256(data).hexdigest(),
        "jsonSHA256": hashlib.sha256(content).hexdigest(),
        "publishedArrayCount": len(entries),
        "nonObjectSlots": len(entries) - len(records),
        "records": len(records),
        "hits": {
            query: [{"fdcId": record.get("fdcId"), "description": record.get("description"),
                     "nutrientCount": len(record.get("foodNutrients", []))}
                    for record in records if query in record.get("description", "").lower()]
            for query in QUERIES
        },
    }

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("archives", type=Path, nargs="+")
    args = parser.parse_args()
    print(json.dumps([inspect(path) for path in args.archives], indent=2))
