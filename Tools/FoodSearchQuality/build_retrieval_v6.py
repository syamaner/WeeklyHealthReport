"""Build retrieval-scenarios-v6: the frozen v5 cases plus plural/singular cases.

food-lexical-terms-v9 folds plural forms in query and source-name terms alike.
The new cases search plural food names that bundled source names spell in the
plural or the singular, plus words that only look plural and must not change.
Labels come from the name rules below, applied to every record retrieved by the
food-lexical-terms-v8 and v9 replays. Pass both ungraded v6 replays, the v8
replay first; without a replay, new cases are ungraded. Earlier cases whose v9
replay retrieves records no frozen label covers are extended only through
EXTENDED below, and the build stops if a case needs a rule it does not have.
"""
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).parent
# (id, family, query, singular, plural)
NEW_CASES = [
    ("r088", "plural-nut", "almonds", "almond", "almonds"),
    ("r089", "plural-nut", "walnuts", "walnut", "walnuts"),
    ("r090", "plural-nut", "cashews", "cashew", "cashews"),
    ("r091", "plural-nut", "hazelnuts", "hazelnut", "hazelnuts"),
    ("r092", "plural-nut", "pistachios", "pistachio", "pistachios"),
    ("r093", "plural-nut", "peanuts", "peanut", "peanuts"),
    ("r094", "plural-pulse", "lentils", "lentil", "lentils"),
    ("r095", "plural-pulse", "chickpeas", "chickpea", "chickpeas"),
    ("r096", "plural-produce", "tomatoes", "tomato", "tomatoes"),
    ("r097", "plural-produce", "potatoes", "potato", "potatoes"),
    ("r098", "plural-produce", "berries", "berry", "berries"),
    ("r099", "plural-produce", "blueberries", "blueberry", "blueberries"),
    ("r100", "plural-quantity", "30 g almonds", "almond", "almonds"),
    ("r101", "plural-quantity", "100g walnuts", "walnut", "walnuts"),
    ("r102", "plural-exception", "hummus", "hummus", "hummus"),
    ("r103", "plural-exception", "couscous", "couscous", "couscous"),
    ("r104", "plural-exception", "asparagus", "asparagus", "asparagus"),
    ("r105", "plural-exception", "molasses", "molasses", "molasses"),
]
# A different food made from the named one (milk, butter, flour, a sweet).
PRODUCT = ("butter", "milk", "flour", "paste", "oil", "spread", "soup", "sauce", "chocolate",
           "coated", "candies", "candy", "juice", "puree", "ketchup", "crisps", "chips", "bar",
           "cookies", "cereal", "cereals", "beverages", "drink", "salad", "curry", "pie", "dahl",
           "hummus", "falafel", "stew", "dip", "spreads", "pesto", "brittle", "nougat", "fries",
           "dehydrated", "flakes", "powder", "mashed", "croquettes", "waffles", "pancakes", "scalloped")
# Named-food preparations or forms that are still the food itself.
FORM = ("roasted", "salted", "toasted", "blanched", "flaked", "ground", "canned", "boiled", "cooked",
        "fried", "baked", "dried", "frozen", "honey", "sprouted", "split", "microwaved", "stewed",
        "sun", "drained", "weighed", "smoke", "oil-roasted", "dry")


def words(text):
    # Two-word and alias spellings that the shared lexical policy already treats as one food.
    text = re.sub(r"\bchick ?peas?\b|\bgarbanzos?\b", "chickpea", text.lower())
    return re.findall(r"[a-z]+", text)


def grade(singular, plural, name):
    """3 plain named food, 2 the food in a stated form, 1 a product or mention, 0 unrelated."""
    fields = [words(field) for field in name.split(" · ")[0].split(",")]
    named = {singular, plural}
    head = fields[0] if fields else []
    if head in (["nuts"], ["nut"]) and len(fields) > 1:
        head = fields[1]
    head = [w for w in head if w not in ("nuts", "nut", "or", "filberts")]
    text = set(words(name.split(" · ")[0]))
    if head and set(head) <= named:
        if text & set(PRODUCT):
            return 1
        return 2 if text & set(FORM) else 3
    return 1 if text & named else 0


# Earlier cases whose v9 replay retrieves records that neither their frozen
# labels nor the v8 replay contained. Only those records are graded, by the
# rule that labelled the case's family; every existing grade stays as frozen.
EXTENDED = {
    "r063": lambda rid, name: grade("oat", "oats", name),
    "r064": lambda rid, name: grade("oat", "oats", name),
    "r083": lambda rid, name: v5_grade("guava", rid, name, False),
    "r085": lambda rid, name: v5_grade("guava", rid, name, True),
}


# Explicit overrides for new v6 labels only (frozen sets are untouched): a
# different species sharing the food word is a related record, not the food.
SPECIES = ("guavas, strawberry",)


def v5_grade(fruit, record, name, taiwan):
    sys.path.insert(0, str(ROOT))
    from build_retrieval_v5 import grade as regional_grade
    value = regional_grade(fruit, record, name, taiwan)
    return min(value, 2) if name.lower().startswith(SPECIES) else value


def main():
    """Arguments: the food-lexical-terms-v8 replay, then the v9 replay (ungraded v6 rows)."""
    data = json.loads((ROOT / "retrieval-scenarios-v5.json").read_text())
    replays = [json.loads(Path(path).read_text()) for path in sys.argv[1:]]
    replay = [row for rows in replays for row in rows]
    if len(replays) == 2:
        before = {}
        for row in replays[0]:
            before.setdefault(row["id"], set()).update(row["records"])
        for case in data["cases"]:
            fresh = {}
            for row in replays[1]:
                if row["id"] == case["id"]:
                    fresh.update((rid, name) for rid, name in zip(row["records"], row["names"])
                                 if rid not in before.get(case["id"], set()) and rid not in case["grades"])
            if not fresh:
                continue
            if case["id"] not in EXTENDED:
                raise SystemExit(f"{case['id']} retrieves new unlabelled records; add a documented rule")
            for rid, name in sorted(fresh.items()):
                case["grades"][rid] = EXTENDED[case["id"]](rid, name)
            case["grades"] = dict(sorted(case["grades"].items()))
            # Recorded apart from any frozen labelNames, so the extension stays visible.
            case["labelExtension"] = {"policy": "food-lexical-terms-v9", "names": dict(sorted(fresh.items()))}
    for case_id, family, query, singular, plural in NEW_CASES:
        names = {}
        for row in replay:
            if row["id"] == case_id:
                names.update(zip(row["records"], row["names"]))
        data["cases"].append({
            "family": family,
            "grades": {rid: grade(singular, plural, name) for rid, name in sorted(names.items())},
            "id": case_id,
            "incorrectVariantRecords": [],
            "labelNames": dict(sorted(names.items())),
            "market": None,
            "preparation": None,
            "query": query,
        })
    data.update(version="retrieval-scenarios-v6",
                focus="v5 cases plus plural/singular folding (food-lexical-terms-v9)",
                labelRules="build_retrieval_v4.py, build_retrieval_v5.py and build_retrieval_v6.py name rules; same-author development labels")
    out = ROOT / "retrieval-scenarios-v6.json"
    out.write_text(json.dumps(data, indent=2, sort_keys=True, ensure_ascii=False) + "\n")
    print(f"Wrote {len(data['cases'])} cases to {out.name}")


if __name__ == "__main__":
    main()
