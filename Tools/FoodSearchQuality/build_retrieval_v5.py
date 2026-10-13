"""Build retrieval-scenarios-v5: the frozen v4 cases plus regional source order cases.

v5 replays the production three-source composite (CoFID, USDA, then Taiwan TFDA
as a regional source). A case may set "market": "taiwan" to replay the Settings
market. Labels for the new cases come from the name rules below, applied to
every record retrieved by the v8-equivalent (all sources interleaved) and v9
replays. Pass both ungraded replays; without a replay, new cases are ungraded.
"""
import json
import sys
from pathlib import Path

ROOT = Path(__file__).parent
NEW_CASES = [
    ("r079", "regional-default", "120 g banana", None, "banana"),
    ("r080", "regional-default", "banana", None, "banana"),
    ("r081", "regional-default", "guava", None, "guava"),
    ("r082", "regional-market", "120 g banana", "taiwan", "banana"),
    ("r083", "regional-market", "guava", "taiwan", "guava"),
    ("r084", "regional-query", "香蕉", None, "banana"),
    ("r085", "regional-query", "芭樂", None, "guava"),
]
PROCESSED = ("dehydrated", "powder", "sauce", "nectar", "canned", "dried", "chips")
VARIETY = ("overripe", "ripe")


def grade(fruit, record, name, taiwan):
    """Plain fruit is wanted; the regional reference is preferred only for Taiwan."""
    head = name.lower().split(",")[0].strip()
    text = name.lower()
    if record.startswith("tfda:"):
        if head.startswith(fruit):
            return 3 if taiwan else 2
        return 0
    if head in (fruit, fruit + "s"):
        if any(word in text for word in PROCESSED):
            return 1
        best = 2 if taiwan else 3
        return best - 1 if any(word in text.split(", ") or word + " " in text for word in VARIETY) else best
    return 1 if fruit in text and not head.startswith("pepper") else 0


def main():
    data = json.loads((ROOT / "retrieval-scenarios-v4.json").read_text())
    replay = [row for path in sys.argv[1:] for row in json.loads(Path(path).read_text())]
    for case_id, family, query, market, fruit in NEW_CASES:
        names = {}
        for row in replay:
            if row["id"] == case_id:
                names.update(zip(row["records"], row["names"]))
        taiwan = market == "taiwan" or family == "regional-query"
        data["cases"].append({
            "family": family,
            "grades": {rid: grade(fruit, rid, name, taiwan) for rid, name in sorted(names.items())},
            "id": case_id,
            "incorrectVariantRecords": [],
            "labelNames": dict(sorted(names.items())),
            "market": market,
            "preparation": None,
            "query": query,
        })
    data.update(version="retrieval-scenarios-v5",
                focus="v4 cases plus Taiwan regional source order (composite v9)",
                labelRules="build_retrieval_v4.py and build_retrieval_v5.py name rules; same-author development labels")
    out = ROOT / "retrieval-scenarios-v5.json"
    out.write_text(json.dumps(data, indent=2, sort_keys=True, ensure_ascii=False) + "\n")
    print(f"Wrote {len(data['cases'])} cases to {out.name}")


if __name__ == "__main__":
    main()
