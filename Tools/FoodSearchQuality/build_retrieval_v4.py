"""Build retrieval-scenarios-v4: the frozen v3 cases plus part-word cases.

Labels for the new cases are assigned by the documented name rules below to
every record the actual adapters retrieved for that query (the record set is
union of the replays before and after ranking v7, because source truncation
can change membership). Pass the ungraded replays written by
WHR_RETRIEVAL_REPORT_V4. Without a replay, the new cases are written ungraded
so that the replays can be produced first.
"""
import json
import sys
from pathlib import Path

ROOT = Path(__file__).parent
PARTS = ("skin", "liver", "giblets", "fat")
NEW_CASES = [
    ("r073", "unrequested-part", "150 g grilled chicken"),
    ("r074", "unrequested-part", "grilled chicken"),
    ("r075", "unrequested-part", "200g roast chicken"),
    ("r076", "unrequested-part", "150g roast pork"),
    ("r077", "requested-part", "roast chicken with skin"),
    ("r078", "requested-part", "chicken liver"),
    ("r079", "produce-skin", "eating apple"),
    ("r080", "produce-skin", "200g baked potato"),
]
PROCESSED = ("juice", "sauce", "pie", "chips", "crisps", "canned", "dried", "dehydrated", "mashed", "frozen",
             "salad", "croquettes", "fritters", "waffles", "hash", "pancakes", "puffs", "flour", "powder")


def fields(name):
    return [f.strip() for f in name.lower().split(",")]


def is_part_record(f):
    """The second comma field names the part itself (skin, skin only, liver)."""
    return len(f) > 1 and f[1].split(" ")[0] in PARTS


def unrequested_part_grade(query, name):
    """Meat without the unrequested part is preferred; the part alone is wrong."""
    f = fields(name)
    meat = "pork" if "pork" in query else "chicken"
    if meat not in f[0]:
        return (0, True) if f[0] in PARTS else (1, False)
    if is_part_record(f):
        return 0, True
    text = name.lower()
    if meat == "pork":
        if "cured" in text:
            return 1, False
        if "lean and fat" in text:
            return 2, False
        return (3, False) if "lean" in text else (1, False)
    if "meat and skin" in text:
        return 2, False
    if "meat" in text or "without skin" in text or "skinless" in text:
        return 3, False
    return 1, False


def requested_part_grade(query, name):
    """An explicitly requested part is the wanted record, never penalised."""
    f = fields(name)
    text = name.lower()
    if "liver" in query:
        if f[0] in ("liver", "chicken") and "liver" in f[:2]:
            return 3, False
        return (1, False) if "liver" in text else (0, False)
    if "chicken" not in f[0]:
        return 1, False
    if "meat and skin" in text:
        return 3, False
    if is_part_record(f):
        return 1, False
    return 2, False


def produce_skin_grade(query, name):
    """Produce eaten with its skin is not an unrequested part: skin-on is preferred."""
    f = fields(name)
    text = name.lower()
    food = "apple" if "apple" in query else "potato"
    if not f[0].startswith(food) or any(word in text for word in PROCESSED):
        return 1, False
    if food == "potato" and "baked" not in text:
        return 1, False
    if "flesh only" in text or "without skin" in text or "peeled" in text:
        return 2, False
    return 3, False


def main():
    data = json.loads((ROOT / "retrieval-scenarios-v3.json").read_text())
    replay = [row for path in sys.argv[1:] for row in json.loads(Path(path).read_text())]
    for case_id, family, query in NEW_CASES:
        names = {}
        for row in replay:
            if row["id"] == case_id:
                names.update(zip(row["records"], row["names"]))
        grade = {"unrequested-part": unrequested_part_grade, "requested-part": requested_part_grade,
                 "produce-skin": produce_skin_grade}[family]
        graded = {rid: grade(query, name) for rid, name in sorted(names.items())}
        data["cases"].append({
            "family": family,
            "grades": {rid: g for rid, (g, _) in graded.items()},
            "id": case_id,
            "incorrectVariantRecords": sorted(rid for rid, (_, wrong) in graded.items() if wrong),
            "labelNames": dict(sorted(names.items())),
            "preparation": None,
            "query": query,
        })
    data.update(version="retrieval-scenarios-v4",
                focus="v3 cases plus unrequested and requested part words and produce skin (ranking v7)",
                labelRules="build_retrieval_v4.py name rules; same-author development labels")
    out = ROOT / "retrieval-scenarios-v4.json"
    out.write_text(json.dumps(data, indent=2, sort_keys=True, ensure_ascii=False) + "\n")
    print(f"Wrote {len(data['cases'])} cases to {out.name}")


if __name__ == "__main__":
    main()
