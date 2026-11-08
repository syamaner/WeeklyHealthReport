#!/usr/bin/env python3
"""Match foods from the owner's notes and logged entries against the catalogue.

Classes:
  product   - a catalogue product whose title carries the item's brand and words
  concept   - a catalogue entry whose concept / variety / alias equals the item or an alias
  partial   - catalogue titles share the item's main words (needs an alias or a new entry)
  new       - nothing in the catalogue
Usage: python3 -I match_inputs.py <work_dir> <catalogue_json>
"""
import json
import re
import sys
from collections import Counter
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from workspace_guard import check_output  # noqa: E402

STOP = set("the and with of in a raw cooked boiled fried roast roasted steamed baked fresh plain whole "
           "full fat style drained canned slices slice sliced flesh only average".split())


def toks(s):
    # "&" stays inside a token, unstemmed, so short ampersand brands survive tokenising
    return {t.rstrip("s") if "&" not in t else t for t in re.findall(r"[a-z0-9%&]+", s.casefold())
            if t not in STOP and (len(t) > 1 or "&" in t)}


def main(work: Path, cat_path: Path):
    cat = [i for i in json.load(open(cat_path))["items"]]
    keys = []
    for i in cat:
        names = {i.get("concept") or "", i.get("variety") or "", *i.get("aliases", [])} - {""}
        keys.append((i, {n.casefold() for n in names}, toks(i["title"])))
    # Foods taken from notes or other free text arrive as intake files (references/inputs.md);
    # a legacy notes-items.json is read too if present.
    notes = []
    for f in sorted((work / "intake").glob("*.json")):
        notes += json.load(open(f)).get("items", [])
    legacy = work / "notes-items.json"
    if legacy.exists():
        notes += json.load(open(legacy))["items"]
    eaten = work / "eaten-entries.json"
    logged = Counter(e["name"] for e in json.load(open(eaten)) if e["name"] != "Water") if eaten.exists() else Counter()
    inputs = [{"term": n.get("term") or n["title"], "aliases": n.get("aliases", []), "brand": n.get("brand"), "from": "intake",
               "kind": n.get("kind", "food"), "freq": n.get("freq")} for n in notes]
    inputs += [{"term": name, "aliases": [], "brand": None, "from": f"logged x{c}", "kind": "food"} for name, c in logged.items()]
    out = []
    for it in inputs:
        if it["kind"] == "supplement":
            out.append({**it, "class": "supplement", "matches": []})
            continue
        forms = [it["term"], *it["aliases"]]
        lower = {f.casefold() for f in forms}
        best = []
        if it["brand"]:
            bt = toks(it["brand"])
            for i, names, tt in keys:
                if bt and bt <= tt and (toks(it["term"]) - bt) <= tt | toks(" ".join(names)):
                    best.append(("product", i["title"]))
        if not best:
            for i, names, tt in keys:
                if lower & names:
                    best.append(("concept", i["title"]))
        if not best:
            ft = [toks(f) for f in forms if toks(f)]
            for i, names, tt in keys:
                pool = tt | toks(" ".join(names))
                if any(f <= pool for f in ft):
                    best.append(("partial", i["title"]))
        cls = best[0][0] if best else "new"
        out.append({**it, "class": cls, "matches": [t for _, t in best[:5]], "n_matches": len(best)})
    (work / "input-match.json").write_text(json.dumps(out, indent=1, ensure_ascii=False))
    print(Counter(o["class"] for o in out))
    for cls in ("partial", "new"):
        print(f"--- {cls}")
        for o in out:
            if o["class"] == cls:
                print(f"  [{o['from']}] {o['term']}" + (f"  ~ {o['matches'][:2]}" if o["matches"] else ""))


if __name__ == "__main__":
    main(check_output(sys.argv[1]), Path(sys.argv[2]))
