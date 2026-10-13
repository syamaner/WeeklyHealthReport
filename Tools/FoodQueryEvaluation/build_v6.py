"""Build synthetic-v6: v5 unchanged plus egg-count cases for food-query-parser-v8.

Expectations were written against food-query-parser-v7 before the first run;
the manifest records that parser's hash. Counts stay counts: no portion weight,
energy or nutrient is implied by any expectation.
"""
import hashlib
import json
from pathlib import Path

root = Path(__file__).parent
data = json.loads((root / "synthetic-v5.json").read_text())
cases = data["cases"]
INVARIANTS = ["preserve_original_query", "explicit_selection_and_confirmation",
              "no_invented_nutrition", "no_inferred_density_or_serving_weight"]
NEW = [
    ("2 scrambled eggs", "scrambled egg", {}, 2, "search", None),
    ("two fried eggs", "fried egg", {}, 2, "search", None),
    ("3 poached eggs", "poached egg", {}, 3, "search", None),
    ("a fried egg", "fried egg", {}, 1, "search", None),
    ("one poached egg", "poached egg", {}, 1, "search", None),
    ("2 x scrambled eggs", "scrambled egg", {}, 2, "search", None),
    ("2 Acme scrambled eggs", "scrambled egg", {"brand": "Acme"}, 2, "search", None),
    ("2 scrambled eggs 120g", None, {}, None, "clarify", "count_mass_scope"),
    ("2 fried bananas", None, {}, None, "clarify", "unsupported_count_preparation"),
    ("2 pan fried eggs", None, {}, None, "clarify", "unsupported_count_preparation"),
    ("not fried 2 eggs", None, {}, None, "clarify", "negated_preparation_scope"),
    ("0 fried eggs", None, {}, None, "reject", "nonpositive_quantity"),
]
for query, food, attributes, count, route, reason in NEW:
    number = len(cases) + 1
    cases.append({
        "id": f"nlp-{number:03}", "family": "egg_count_v6", "scenario_group": f"v6-{number:03}", "query": query,
        "expected": {"food": food, "attributes": attributes,
                     "quantity": None if count is None else {"value": count, "unit": "count"},
                     "route": route, "reason": reason},
        "invariants": INVARIANTS,
    })
data.update(origin="v5 plus 12 invented egg-count cases for food-query-parser-v8", cases=cases)
fixture = root / "synthetic-v6.json"
fixture.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n")
manifest = {
    "schema_version": 1, "fixture": fixture.name, "sha256": hashlib.sha256(fixture.read_bytes()).hexdigest(),
    "case_count": len(cases), "new_case_count": len(NEW), "expectation_revisions": [], "independent_holdout": False,
    # food-query-parser-v7 (origin/main c94da260) before the first run of these cases.
    "parser_sha256_before_first_run": "8e5ecf71419c29edbe582cfa5ac3f524aa33179d7ed917fe920452bd477ce3ae",
}
(root / "manifest-v6.json").write_text(json.dumps(manifest, indent=2) + "\n")
print(manifest)
