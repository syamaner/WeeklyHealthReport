"""Build synthetic-v9: v8 unchanged plus household-container cases for food-query-parser-v10.

Covers #335 ("3 mugs of tea" was not a household portion). Expectations were written
alongside the parser change and first run against food-query-parser-v9 (origin/main
6615d157), whose hash the manifest records. Reasons are not scored, so the cases that
already clarified under v9 because of an unresolved number are boundary evidence only;
the cases without a number are the ones the route distinguishes.
"""
import hashlib
import json
from pathlib import Path

root = Path(__file__).parent
data = json.loads((root / "synthetic-v8.json").read_text())
cases = data["cases"]
INVARIANTS = ["preserve_original_query", "explicit_selection_and_confirmation",
              "no_invented_nutrition", "no_inferred_density_or_serving_weight"]
PORTION = "portion_weight_unknown"
NEW = [
    # #335: plural containers are household portions, like their singular forms.
    ("3 mugs of tea", None, {}, None, "clarify", PORTION),
    ("2 mugs coffee", None, {}, None, "clarify", PORTION),
    ("a mug of coffee", None, {}, None, "clarify", PORTION),
    ("mugs of tea", None, {}, None, "clarify", PORTION),
    ("2 cups of tea", None, {}, None, "clarify", PORTION),
    ("cups of coffee", None, {}, None, "clarify", PORTION),
    ("glasses of milk", None, {}, None, "clarify", PORTION),
    ("2 glasses of milk", None, {}, None, "clarify", PORTION),
    ("pots of yoghurt", None, {}, None, "clarify", PORTION),
    ("packs of crisps", None, {}, None, "clarify", PORTION),
    # Containers that were already plural keep their route.
    ("2 jars of honey", None, {}, None, "clarify", PORTION),
    ("3 tubs of yoghurt", None, {}, None, "clarify", PORTION),
    ("2 cartons of milk", None, {}, None, "clarify", PORTION),
    # A mug cake keeps its v9 portion question; a branded "cups" name now clarifies like "cup".
    ("mug cake", None, {}, None, "clarify", PORTION),
    ("peanut butter cups", None, {}, None, "clarify", PORTION),
    # Words that only contain a unit are unchanged.
    ("cupcakes", "cupcakes", {}, None, "search", None),
    ("potatoes", "potatoes", {}, None, "search", None),
    # A zero household amount clarifies like "0 pieces cheese"; no amount is read from it.
    ("0 mugs of tea", None, {}, None, "clarify", PORTION),
]
for query, food, attributes, count, route, reason in NEW:
    number = len(cases) + 1
    cases.append({
        "id": f"nlp-{number:03}", "family": "household_containers_v9", "scenario_group": f"v9-{number:03}", "query": query,
        "expected": {"food": food, "attributes": attributes,
                     "quantity": None if count is None else {"value": count, "unit": "count"},
                     "route": route, "reason": reason},
        "invariants": INVARIANTS,
    })
data.update(origin="v8 plus 18 invented household-container cases for food-query-parser-v10", cases=cases)
fixture = root / "synthetic-v9.json"
fixture.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n")
manifest = {
    "schema_version": 1, "fixture": fixture.name, "sha256": hashlib.sha256(fixture.read_bytes()).hexdigest(),
    "case_count": len(cases), "new_case_count": len(NEW), "expectation_revisions": [], "independent_holdout": False,
    # food-query-parser-v9 (origin/main 6615d157) before the first run of these cases.
    "parser_sha256_before_first_run": "1ee58fea7a8633ce07930a22f60512572d23074db27ec741575d5512a7f21721",
}
(root / "manifest-v9.json").write_text(json.dumps(manifest, indent=2) + "\n")
print(manifest)
