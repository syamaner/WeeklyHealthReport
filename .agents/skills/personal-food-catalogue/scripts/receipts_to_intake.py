#!/usr/bin/env python3
"""Turn newly extracted receipt lines into an intake file of NEW titles only.

Run extract_items.py on the new receipts into a fresh folder first (its gate must
pass). Titles already in the catalogue are skipped, non-food is dropped, and pack
size is kept in the title. The receipt families already in the catalogue keep
their numbers, so cached lookups stay valid.

Usage: python3 -I receipts_to_intake.py <workspace> <new purchase-lines.jsonl> <source_id> <out_intake.json>
"""
import json
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import build_unique as B  # noqa: E402
import intake as I  # noqa: E402
from workspace_guard import check, check_output  # noqa: E402
from private_config import require  # noqa: E402


def main(ws, lines_path, source_id, out_path):
    ws = check(Path(ws))
    cat_path = ws / "out" / "personal-food-catalogue.json"
    cat = json.load(open(cat_path)) if cat_path.exists() else {"items": []}  # first build: nothing known yet
    known = {I.norm(t) for i in cat["items"] for t in i.get("titles", [i["title"]])}
    seen, items, skipped = set(), [], {"known": 0, "non_food": 0}
    for l in open(lines_path):
        r = json.loads(l)
        title = B.clean(r["name"])
        k = I.norm(title)
        if k in seen:
            continue
        seen.add(k)
        if k in known:
            skipped["known"] += 1
            continue
        if B.NON_FOOD.search(title):
            skipped["non_food"] += 1
            continue
        kind = "supplement" if B.SUPPLEMENT.search(title) else "food"
        items.append({"title": title, "brand": None, "aliases": [], "kind": kind, "state": None,
                      "region": None, "note": f"retailer: {r.get('retailer')}", "label": None})
    doc = {"source": {"id": source_id, "kind": "pdf", "captured": time.strftime("%Y-%m-%d"),
                      "description": "new receipt titles only (sanitised extraction)"}, "items": items}
    check_output(out_path).write_text(json.dumps(doc, indent=1, ensure_ascii=False))
    print(f"{len(items)} new titles; skipped {skipped}")


if __name__ == "__main__":
    require()
    main(*sys.argv[1:5])
