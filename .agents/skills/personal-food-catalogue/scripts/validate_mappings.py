#!/usr/bin/env python3
"""Mechanical checks on the concept/CoFID proposals. Downgrades, never upgrades.

Rules (a downgrade moves close/same_food_same_state to concept_only, so the
CoFID record no longer supplies nutrients):
  - product raw or frozen, record cooked (boiled, grilled, roasted ...)
  - product cooked, record raw
  - product smoked, record not smoked (or the reverse) for meat and fish
  - title states a fat percentage the record name does not carry
Frozen products matched to a raw record stay, with a note.

Usage: python3 -I validate_mappings.py <work_dir>
Writes work/mapping-validated.json and prints a summary.
"""
import json
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from workspace_guard import check_output  # noqa: E402

COOKED = re.compile(r"\b(boiled|grilled|roasted|roast|fried|stewed|casseroled|baked|microwaved|steamed|"
                    r"stir-fried|cooked|poached|braised|toasted)\b", re.I)
RAW = re.compile(r"\braw\b", re.I)
SMOKED = re.compile(r"\bsmoked\b", re.I)
FAT = re.compile(r"(\d+(?:\.\d+)?)\s*%\s*fat", re.I)


def _words(text):
    return {w.rstrip("s") for w in re.findall(r"[^\W\d_]{3,}", (text or "").casefold())}


def shares_food_word(m, record_name):
    """Mechanical check that does not trust the model: the chosen record's own name must share a
    word with the mapping's concept, variety or aliases, so a wrong or shifted row is caught."""
    words = _words(m.get("concept")) | _words(m.get("variety"))
    for a in m.get("aliases") or []:
        words |= _words(a)
    return bool(_words(record_name) & words)


def main(work: Path, cofid_path: Path):
    names = dict(l.rstrip("\n").split("\t", 1) for l in open(work / "cofid-names.txt"))
    fat_of = {}
    for r in json.load(open(cofid_path))["records"]:
        mm = re.search(r":row:(\d+):", r["record_id"])
        v = r["nutrients"].get("fat_total", {})
        if mm and v.get("state") == "numeric":
            fat_of[mm[1]] = float(v["value"])
    titles = {f["n"]: f["title"] for f in json.load(open(work / "families.json"))}
    out, changes = [], []
    for p in sorted(work.glob("mapping-[0-9].json")):
        for m in json.load(open(p)):
            m = dict(m)
            row, match = m.get("cofid_row"), m.get("cofid_match")
            rec = names.get(row or "", "")
            title = titles.get(m["n"], "")
            reasons = []
            if row and match in ("close", "same_food_same_state"):
                if "cofid_name" in m and m["cofid_name"] != rec:
                    reasons.append("proposed name differs from the record at its row")
                elif not shares_food_word(m, rec):
                    # no name proposed: the record itself must share a food word with the mapping
                    reasons.append("record name shares no word with the mapped concept, variety or aliases")
            if row and match in ("close", "same_food_same_state"):
                st = m.get("state")
                if st in ("raw", "frozen") and COOKED.search(rec) and not RAW.search(rec):
                    reasons.append(f"product {st}, record cooked")
                if st == "cooked" and RAW.search(rec):
                    reasons.append("product cooked, record raw")
                if m.get("category") in ("meat", "fish") and not re.search(r"ready to cook", title, re.I) \
                        and re.search(r"\b(roast(ed)?|cooked|ready to eat|hot smoked)\b", title, re.I) and RAW.search(rec):
                    reasons.append("title says cooked, record raw")
                if m.get("category") in ("meat", "fish") and bool(SMOKED.search(title)) != bool(SMOKED.search(rec)):
                    reasons.append("smoked state differs")
                tf = FAT.search(title)
                if tf:
                    stated, rf = float(tf[1]), fat_of.get(row)
                    less = re.search(r"less than", title, re.I)
                    ok = rf is not None and (rf <= stated + 0.5 if less else abs(rf - stated) <= 2)
                    if not ok:
                        reasons.append(f"title {tf[0]}, record fat {rf} g/100 g")
                    else:
                        m["validation"] = [f"title {tf[0]} consistent with record fat {rf} g/100 g"]
            if reasons:
                m["cofid_match_agent"] = match
                m["cofid_match"] = "concept_only"
                m["validation"] = reasons
                changes.append((m["n"], title, rec, reasons))
            elif row and m.get("state") == "frozen" and "validation" not in m and RAW.search(rec):
                m["validation"] = ["frozen product, raw record: composition taken as unchanged by freezing"]
            m["cofid_name"] = rec or None
            out.append(m)
    out.sort(key=lambda m: m["n"])
    (work / "mapping-validated.json").write_text(json.dumps(out, indent=1, ensure_ascii=False))
    from collections import Counter
    print("total", len(out), dict(Counter(m["cofid_match"] for m in out)))
    print("downgraded", len(changes))
    for n, t, r, why in changes:
        print(f"  {n:4d} {t[:55]:55s} -> {r[:45]:45s} {'; '.join(why)}")


if __name__ == "__main__":
    main(check_output(sys.argv[1]), Path(sys.argv[2]))
