"""Build synthetic-v7: v6 unchanged plus plural food-name cases for food-lexical-terms-v9.

The query parser is unchanged (food-query-parser-v8). These cases pin the food
text it hands to retrieval for plural names, so the retrieval-side plural
folding (docs/food-lexical-terms-v9.md) receives what it expects. The parser's
own bounded singular list still turns "almonds" and "blueberries" into the
singular; every other plural reaches retrieval as typed. Expectations were
written against the parser hash in the manifest before the first run.
"""
import hashlib
import json
from pathlib import Path

root = Path(__file__).parent
repo = root.parent.parent
data = json.loads((root / "synthetic-v6.json").read_text())
cases = data["cases"]
INVARIANTS = ["preserve_original_query", "explicit_selection_and_confirmation",
              "no_invented_nutrition", "no_inferred_density_or_serving_weight"]
NEW = [
    ("almonds", "almond", None, "search", None),
    ("walnuts", "walnuts", None, "search", None),
    ("cashews", "cashews", None, "search", None),
    ("hazelnuts", "hazelnuts", None, "search", None),
    ("pistachios", "pistachios", None, "search", None),
    ("peanuts", "peanuts", None, "search", None),
    ("lentils", "lentils", None, "search", None),
    ("chickpeas", "chickpeas", None, "search", None),
    ("tomatoes", "tomatoes", None, "search", None),
    ("potatoes", "potatoes", None, "search", None),
    ("berries", "berries", None, "search", None),
    ("blueberries", "blueberry", None, "search", None),
    ("30 g almonds", "almond", {"value": 30, "unit": "g"}, "search", None),
    ("100g walnuts", "walnuts", {"value": 100, "unit": "g"}, "search", None),
    ("a handful of walnuts", "walnuts", None, "clarify", "portion_weight_unknown"),
    # Words that only look plural: the parser must hand them on unchanged.
    ("hummus", "hummus", None, "search", None),
    ("couscous", "couscous", None, "search", None),
    ("asparagus", "asparagus", None, "search", None),
    ("molasses", "molasses", None, "search", None),
]
for query, food, quantity, route, reason in NEW:
    number = len(cases) + 1
    cases.append({
        "id": f"nlp-{number:03}", "family": "plural_food_v7", "scenario_group": f"v7-{number:03}", "query": query,
        "expected": {"food": food, "attributes": {}, "quantity": quantity, "route": route, "reason": reason},
        "invariants": INVARIANTS,
    })
data.update(origin="v6 plus 19 invented plural food-name cases for food-lexical-terms-v9", cases=cases)
fixture = root / "synthetic-v7.json"
fixture.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n")
parser = repo / "Packages/FoodLedgerKit/Sources/FoodLedgerApplication/FoodQueryParser.swift"
manifest = {
    "schema_version": 1, "fixture": fixture.name, "sha256": hashlib.sha256(fixture.read_bytes()).hexdigest(),
    "case_count": len(cases), "new_case_count": len(NEW), "expectation_revisions": [], "independent_holdout": False,
    # food-query-parser-v8, unchanged by food-lexical-terms-v9, before the first run of these cases.
    "parser_sha256_before_first_run": hashlib.sha256(parser.read_bytes()).hexdigest(),
}
(root / "manifest-v7.json").write_text(json.dumps(manifest, indent=2) + "\n")
print(manifest)
