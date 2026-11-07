#!/usr/bin/env python3
"""Rebuild the catalogue from what is already in work/, then export and report.

Offline: runs no fetch. Order: validate_mappings -> assemble -> assemble_extras ->
export_v1 -> coverage report.

Usage: python3 -I build.py <workspace> <repo_root>
"""
import json
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from workspace_guard import check  # noqa: E402


def run(*args):
    r = subprocess.run([sys.executable, "-I", *map(str, args)], capture_output=True, text=True)
    print(r.stdout.rstrip())
    if r.returncode:
        print(r.stderr.rstrip())
        sys.exit(r.returncode)


def main(ws: Path, repo: Path):
    res = repo / "Packages/FoodLedgerKit/Sources/FoodGenericSearch/Resources"
    work, out = ws / "work", ws / "out"
    if (work / "mapping-batch-1.txt").exists():
        run(HERE / "validate_mappings.py", work, res / "cofid-2021-generic-search-v1.json")
    run(HERE / "assemble.py", work, res / "cofid-2021-generic-search-v1.json", out, res / "usda-generic-v1.json")
    run(HERE / "assemble_extras.py", work, out / "personal-food-catalogue.json", res)
    run(HERE / "export_v1.py", ws, repo)
    items = [i for i in json.load(open(out / "personal-food-catalogue.json"))["items"] if i["kind"] == "food"]
    has = lambda i, k: (i["nutrients"].get(k) or {}).get("value") is not None
    n = len(items)
    w = sum(i["purchase_lines"] for i in items) or 1
    print(f"\nentries {n}; energy {sum(has(i, 'energy_consumed') for i in items) / n:.1%}; "
          f"weighted by purchases {sum(i['purchase_lines'] for i in items if has(i, 'energy_consumed')) / w:.1%}")
    for k in ("protein", "fiber", "sodium", "calcium", "iron", "vitamin_c", "vitamin_d", "vitamin_b12", "iodine"):
        print(f"  {k:12s} {sum(has(i, k) for i in items) / n:.1%}")
    empty = [i["title"] for i in items if not i["nutrient_sources"]]
    print(f"no nutrients yet: {len(empty)}")


if __name__ == "__main__":
    main(check(Path(sys.argv[1])), Path(sys.argv[2]).expanduser())
