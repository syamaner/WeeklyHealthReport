"""Build retrieval-scenarios-v7: the frozen v6 cases plus dark chocolate cocoa cases.

cocoa-percent-policy-v1 (#382, docs/cocoa-aware-search-v1.md) ranks rows by their stated
cocoa band. The new cases search dark chocolate at stated cocoa percentages, phrasings
that name cocoa or cacao, the UK name "plain chocolate", and guards. Labels come from the
name rule below, written independently of the policy code and applied to every record
retrieved by the composite-generic-ranking-v9 (before) and v10 (after) replays. Pass both
ungraded v7 replays, the v9 replay first; without a replay, new cases are ungraded. No
earlier case may retrieve a new record (the v3 to v6 reports stay byte-identical), so
the build stops if one does.
"""
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).parent
# (id, family, query, requested cocoa percent or None)
NEW_CASES = [
    ("r106", "cocoa-in-band", "dark chocolate 70%", 70),
    ("r107", "cocoa-in-band", "dark chocolate 85%", 85),
    ("r108", "cocoa-in-band", "20g dark chocolate 85%", 85),
    ("r109", "cocoa-in-band", "dark chocolate 40%", 40),
    ("r110", "cocoa-in-band", "dark chocolate 50%", 50),
    ("r111", "cocoa-nearest-band", "90% dark chocolate", 90),
    ("r112", "cocoa-nearest-band", "99% dark chocolate", 99),
    ("r113", "cocoa-estimate", "dark chocolate 100%", 100),
    ("r114", "cocoa-estimate", "100% cacao", 100),
    ("r115", "cocoa-phrasing", "85% cocoa chocolate", 85),
    ("r116", "cocoa-phrasing", "chocolate 85% cocoa solids", 85),
    ("r117", "cocoa-phrasing", "dark chocolate 85 per cent", 85),
    ("r118", "cocoa-phrasing", "85% cacao", 85),
    ("r119", "cocoa-uk-name", "dark chocolate", None),
    ("r120", "cocoa-uk-name", "plain chocolate", None),
    ("r121", "cocoa-guard", "mint dark chocolate", None),
]
MINT = {"r121"}
# A chocolate product or mention rather than a bar of plain dark chocolate.
PRODUCT = ("coated", "covered", "filled", "fondant", "centres", "cake", "cakes", "biscuit", "biscuits",
           "cookies", "candies", "beverage", "beverages", "drink", "mix", "milk", "white", "syrup",
           "spread", "pudding", "puddings", "ice", "doughnuts", "cereal", "cereals", "bar", "bars",
           "liquid", "mexican", "chips", "morsels", "frosting", "sauce", "nut", "nuts", "wafer")


def stated_band(name):
    """The cocoa band a name states outside parentheses, plus two documented source facts."""
    lowered = name.split(" · ")[0].lower()
    if lowered == "chocolate, plain" or lowered.startswith("chocolate, plain,"):
        return (36, 50)  # CoFID 17-491 description: "6 bars, 3 brands; 36-50% cocoa solids".
    if lowered == "baking chocolate, unsweetened, squares":
        return (100, 100)  # Unsweetened chocolate is chocolate liquor (21 CFR 163.111).
    outside = re.sub(r"\([^)]*\)", " ", lowered)
    match = re.search(r"(\d+)\s*-\s*(\d+)\s*%\s*(?:cacao|cocoa)", outside)
    return (int(match.group(1)), int(match.group(2))) if match else None


def grade(case_id, requested, name):
    """3 plain dark chocolate in the asked band, 2 another band, 1 a product or mention, 0 unrelated."""
    words = set(re.findall(r"[a-z]+", name.split(" · ")[0].lower()))
    if not words & {"chocolate", "cocoa", "cacao"}:
        return 0
    if case_id in MINT:
        return 3 if {"mint", "dark", "chocolate"} <= words else 1
    band = stated_band(name)
    if words & set(PRODUCT) or band is None:
        return 1
    if requested is None:
        return 3
    return 3 if band[0] <= requested <= band[1] else 2


def main():
    """Arguments: the composite-generic-ranking-v9 replay, then the v10 replay (ungraded v7 rows)."""
    data = json.loads((ROOT / "retrieval-scenarios-v6.json").read_text())
    replays = [json.loads(Path(path).read_text()) for path in sys.argv[1:]]
    replay = [row for rows in replays for row in rows]
    if len(replays) == 2:
        before = {}
        for row in replays[0]:
            before.setdefault((row["id"], row["source"]), []).append(row["records"])
        for row in replays[1]:
            if row["id"] in {case["id"] for case in data["cases"]} and [row["records"]] != before.get((row["id"], row["source"])):
                raise SystemExit(f"{row['id']} {row['source']} changed; the frozen v3 to v6 reports must not move")
    for case_id, family, query, requested in NEW_CASES:
        names = {}
        for row in replay:
            if row["id"] == case_id:
                names.update(zip(row["records"], row["names"]))
        grades = {rid: grade(case_id, requested, name) for rid, name in sorted(names.items())}
        # Where a retrieved row states the asked band, rows that state another band are
        # incorrect variants; with no such row, the nearest band is a tentative estimate.
        has_band = requested is not None and any(value == 3 for value in grades.values())
        incorrect = sorted(rid for rid, value in grades.items() if has_band and value == 2)
        data["cases"].append({
            "family": family,
            "grades": grades,
            "id": case_id,
            "incorrectVariantRecords": incorrect,
            "labelNames": dict(sorted(names.items())),
            "market": None,
            "preparation": None,
            "query": query,
        })
    data.update(version="retrieval-scenarios-v7",
                focus="v6 cases plus dark chocolate cocoa percentages (cocoa-percent-policy-v1)",
                labelRules="build_retrieval_v4.py to build_retrieval_v7.py name rules; same-author development labels")
    out = ROOT / "retrieval-scenarios-v7.json"
    out.write_text(json.dumps(data, indent=2, sort_keys=True, ensure_ascii=False) + "\n")
    print(f"Wrote {len(data['cases'])} cases to {out.name}")


if __name__ == "__main__":
    main()
