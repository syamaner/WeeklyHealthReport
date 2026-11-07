#!/usr/bin/env python3
"""Collapse unique foods into families and write a CoFID name index.

Usage: python3 -I prepare_families.py <work_dir> <cofid_json>
Writes work/families.json, work/cofid-index.tsv and work/mapping-batch-N.txt.
"""
import csv
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from workspace_guard import check_output  # noqa: E402


def main(work: Path, cofid: Path):
    fam_of = {}
    for base, keys in json.load(open(work / "pack-variant-families.json")).items():
        for k in keys:
            fam_of[k] = base
    families = {}
    for kind in ("food", "supplement"):
        for r in csv.DictReader(open(work / f"unique-{kind}.csv")):
            fid = kind + ":" + fam_of.get(r["product_key"], r["product_key"])  # never mix food and supplements
            f = families.setdefault(fid, {"family_id": fid, "kind": kind, "titles": [], "packs": [],
                                          "purchase_lines": 0, "retailers": set()})
            f["titles"].append(r["title"])
            if r["pack_text"]:
                f["packs"].append(r["pack_text"])
            f["purchase_lines"] += int(r["purchase_lines"])
            f["retailers"] |= set(r["retailers"].split("; "))
    out = []
    for f in families.values():
        f["titles"] = sorted(set(f["titles"]), key=len)
        f["title"] = f["titles"][-1]
        f["packs"] = sorted(set(f["packs"]))
        f["retailers"] = sorted(f["retailers"])
        out.append(f)
    out.sort(key=lambda f: (-f["purchase_lines"], f["title"]))
    for i, f in enumerate(out, 1):
        f["n"] = i
    (work / "families.json").write_text(json.dumps(out, indent=1, ensure_ascii=False))

    recs = json.load(open(cofid))["records"]
    with open(work / "cofid-index.tsv", "w") as fh:
        for r in recs:
            fh.write(f"{r['record_id']}\t{r['name']}\n")
    import re as _re
    with open(work / "cofid-names.txt", "w") as fh:  # "row<TAB>name", read by validate_mappings and the agents
        for r in recs:
            m = _re.search(r":row:(\d+):", r["record_id"])
            if m:
                fh.write(f"{m[1]}\t{r['name']}\n")

    foods = [f for f in out if f["kind"] == "food"]
    size = -(-len(foods) // 4)
    for b in range(4):
        chunk = foods[b * size:(b + 1) * size]
        (work / f"mapping-batch-{b + 1}.txt").write_text(
            "\n".join(f"{f['n']}\t{f['title']}" for f in chunk) + "\n")
    print("families:", len(out), "food:", len(foods), "cofid records:", len(recs), "batch size:", size)


if __name__ == "__main__":
    main(check_output(sys.argv[1]), Path(sys.argv[2]))
