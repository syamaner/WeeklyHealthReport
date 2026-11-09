#!/usr/bin/env python3
"""Pull food-relevant text from the app's own daily exports (local copies).

food-daily-*.json   -> entries[].display_name, item_class (no amounts, units or dates)
health-daily-*.json -> today.notes (free text, one string per saved note)
Nothing else (HealthKit values, workouts, identifiers) is copied.

Usage: python3 -I extract_exports.py <exports_dir> <work_dir> [--print-notes]
"""
import json
import sys
from collections import Counter
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from workspace_guard import check_output  # noqa: E402


def main(src: Path, work: Path):
    eaten, notes = [], []
    for p in sorted(src.rglob("food-daily-*.json")):
        d = json.load(open(p))
        for e in d.get("entries", []):
            eaten.append({"name": e.get("display_name"), "item_class": e.get("item_class")})  # no amounts or dates
    for p in sorted(src.rglob("health-daily-*.json")):
        d = json.load(open(p))
        for i, n in enumerate((d.get("today") or {}).get("notes") or []):
            notes.append({"date": d.get("report_date"), "i": i, "text": n})
    # Same date can appear in several files (re-exports); keep exact duplicates once.
    seen, uniq = set(), []
    for n in notes:
        k = (n["date"], n["text"])
        if k not in seen:
            seen.add(k)
            uniq.append({"text": n["text"]})  # the date was only needed to de-duplicate
    (work / "eaten-entries.json").write_text(json.dumps(eaten, indent=1, ensure_ascii=False))
    # Note text is printed for the agent to read once and turn into an intake file of foods only;
    # it is never written to a work file (it can hold names, places or medical detail).
    if "--print-notes" in sys.argv:
        for n in uniq:
            print("--- note"); print(n["text"])
    names = Counter(e["name"] for e in eaten)
    print(f"food entries: {len(eaten)}, distinct names: {len(names)}, notes: {len(uniq)}, "
          f"chars: {sum(len(n['text']) for n in uniq)}")


if __name__ == "__main__":
    main(Path(sys.argv[1]), check_output(sys.argv[2]))  # optional third argument: --print-notes
