"""Build synthetic-v8: v7 unchanged plus count cases for food-query-parser-v9.

Covers #317 ("2 hard boiled eggs") and the parse part of #315 ("3 pieces
banana"). Expectations were written alongside the parser change and first run
against food-query-parser-v8 (origin/main 4df98216), whose hash the manifest
records. Counts stay counts: no portion weight, energy or nutrient is implied.
"""
import hashlib
import json
from pathlib import Path

root = Path(__file__).parent
data = json.loads((root / "synthetic-v7.json").read_text())
cases = data["cases"]
INVARIANTS = ["preserve_original_query", "explicit_selection_and_confirmation",
              "no_invented_nutrition", "no_inferred_density_or_serving_weight"]
BOILED = {"preparation": "boiled"}
NEW = [
    # #317: hard boiled counts like boiled. The food text is what the uncounted form gives.
    ("2 hard boiled eggs", "hard egg", BOILED, 2, "search", None),
    ("two hard boiled eggs", "hard egg", BOILED, 2, "search", None),
    ("a hard boiled egg", "hard egg", BOILED, 1, "search", None),
    ("2 x hard boiled eggs", "hard egg", BOILED, 2, "search", None),
    ("2 hard boiled eggs 100g", None, {}, None, "clarify", "count_mass_scope"),
    ("2 hard bananas", None, {}, None, "clarify", "unsupported_count_preparation"),
    ("0 hard boiled eggs", None, {}, None, "reject", "nonpositive_quantity"),
    # #315: "N pieces <counted item>" is the count shown for "N <items>".
    ("3 pieces banana", "banana", {}, 3, "search", None),
    ("3 pieces of banana", "banana", {}, 3, "search", None),
    ("2 pieces apple", "apple", {}, 2, "search", None),
    ("1 piece banana", "banana", {}, 1, "search", None),
    ("two pieces of banana", "banana", {}, 2, "search", None),
    ("a piece of banana", None, {}, None, "clarify", "portion_weight_unknown"),
    ("3 pieces cheese", None, {}, None, "clarify", "portion_weight_unknown"),
    ("3 pieces banana 120g", None, {}, None, "clarify", "count_mass_scope"),
    ("0 pieces banana", None, {}, None, "reject", "nonpositive_quantity"),
]
for query, food, attributes, count, route, reason in NEW:
    number = len(cases) + 1
    cases.append({
        "id": f"nlp-{number:03}", "family": "count_forms_v8", "scenario_group": f"v8-{number:03}", "query": query,
        "expected": {"food": food, "attributes": attributes,
                     "quantity": None if count is None else {"value": count, "unit": "count"},
                     "route": route, "reason": reason},
        "invariants": INVARIANTS,
    })
data.update(origin="v7 plus 16 invented count-form cases for food-query-parser-v9", cases=cases)
fixture = root / "synthetic-v8.json"
fixture.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n")
manifest = {
    "schema_version": 1, "fixture": fixture.name, "sha256": hashlib.sha256(fixture.read_bytes()).hexdigest(),
    "case_count": len(cases), "new_case_count": len(NEW), "expectation_revisions": [], "independent_holdout": False,
    # food-query-parser-v8 (origin/main 4df98216) before the first run of these cases.
    "parser_sha256_before_first_run": "45ba48c0ce06b594069e029ee650e7757d2a2de7b65e405ed02e96cf02620745",
}
(root / "manifest-v8.json").write_text(json.dumps(manifest, indent=2) + "\n")
print(manifest)
