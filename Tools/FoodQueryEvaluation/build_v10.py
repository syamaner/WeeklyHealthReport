"""Build synthetic-v10: v9 unchanged plus cocoa and "per cent" cases for food-query-parser-v11.

Covers #382 (phase A of #381, docs/cocoa-aware-search-v1.md). Expectations were written
before the parser change and first run against food-query-parser-v10 (origin/main
f163e4a1), whose hash the manifest records. Reasons are not scored; clarify cases pin the
route only. The guard cases keep their v10 parse.
"""
import hashlib
import json
from pathlib import Path

root = Path(__file__).parent
data = json.loads((root / "synthetic-v9.json").read_text())
cases = data["cases"]
INVARIANTS = ["preserve_original_query", "explicit_selection_and_confirmation",
              "no_invented_nutrition", "no_inferred_density_or_serving_weight"]
UNKNOWN = "percentage_meaning_unknown"
GRAMS = lambda value: {"value": value, "unit": "g"}
NEW = [
    # Cocoa or cacao wording names the cocoa percentage; a bare one searches chocolate.
    ("100% cacao", "chocolate", {"cocoa_percent": 100}, None, "search", None),
    ("85% cocoa", "chocolate", {"cocoa_percent": 85}, None, "search", None),
    ("100% CACAO", "chocolate", {"cocoa_percent": 100}, None, "search", None),
    ("85%cocoa", "chocolate", {"cocoa_percent": 85}, None, "search", None),
    ("85 % cacao", "chocolate", {"cocoa_percent": 85}, None, "search", None),
    ("20g 85% cocoa", "chocolate", {"cocoa_percent": 85}, GRAMS(20), "search", None),
    ("dark 90% cocoa", "dark chocolate", {"cocoa_percent": 90}, None, "search", None),
    ("bitter 85% cacao", "bitter chocolate", {"cocoa_percent": 85}, None, "search", None),
    # Cocoa wording leaves the food text so chocolate rows are retrieved.
    ("85% cocoa chocolate", "chocolate", {"cocoa_percent": 85}, None, "search", None),
    ("chocolate 85% cocoa solids", "chocolate", {"cocoa_percent": 85}, None, "search", None),
    ("cocoa solids 85% chocolate", "chocolate", {"cocoa_percent": 85}, None, "search", None),
    ("dark chocolate 70% cacao", "dark chocolate", {"cocoa_percent": 70}, None, "search", None),
    ("plain chocolate 70% cocoa solids", "plain chocolate", {"cocoa_percent": 70}, None, "search", None),
    # "per cent" is "percent" for every key.
    ("dark chocolate 85 per cent", "dark chocolate", {"cocoa_percent": 85}, None, "search", None),
    ("dark chocolate 85 per-cent", "dark chocolate", {"cocoa_percent": 85}, None, "search", None),
    ("10 per cent fat yoghurt", "yoghurt", {"fat_percent": 10}, None, "search", None),
    ("2 per cent milk", None, {}, None, "clarify", UNKNOWN),
    ("10 per cent less fat yoghurt", None, {}, None, "clarify", "relative_percentage"),
    ("70-85 per cent dark chocolate", None, {}, None, "clarify", "unresolved_number"),
    # Two cocoa percentages conflict.
    ("dark chocolate 70% cocoa 85% cocoa", None, {}, None, "clarify", "conflicting_variants"),
    # Other cocoa products keep the v10 question about what the percentage means.
    ("100% cocoa powder", None, {}, None, "clarify", UNKNOWN),
    ("100% cacao paste", None, {}, None, "clarify", UNKNOWN),
    ("100% cocoa mass", None, {}, None, "clarify", UNKNOWN),
    ("70% cocoa beans", None, {}, None, "clarify", UNKNOWN),
    ("cacao nibs 100%", None, {}, None, "clarify", UNKNOWN),
    ("100% cocoa butter", None, {}, None, "clarify", UNKNOWN),
    ("85% cacao bar", None, {}, None, "clarify", UNKNOWN),
    ("85% hot cocoa", None, {}, None, "clarify", UNKNOWN),
    # A bare number is not a declared percentage.
    ("cocoa solids 90", None, {}, None, "clarify", "unresolved_number"),
    # Guards that keep their v10 parse.
    ("25g 99% dark chocolate", "dark chocolate", {"cocoa_percent": 99}, GRAMS(25), "search", None),
    ("100% peanut butter", "peanut butter", {"ingredient_percent": 100}, None, "search", None),
    ("hot cocoa", "hot cocoa", {}, None, "search", None),
    ("salmon chocolate", "salmon chocolate", {}, None, "search", None),
]
for query, food, attributes, quantity, route, reason in NEW:
    number = len(cases) + 1
    cases.append({
        "id": f"nlp-{number:03}", "family": "cocoa_percent_v10", "scenario_group": f"v10-{number:03}", "query": query,
        "expected": {"food": food, "attributes": attributes, "quantity": quantity, "route": route, "reason": reason},
        "invariants": INVARIANTS,
    })
data.update(origin="v9 plus 33 invented cocoa and per cent cases for food-query-parser-v11", cases=cases)
fixture = root / "synthetic-v10.json"
fixture.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n")
manifest = {
    "schema_version": 1, "fixture": fixture.name, "sha256": hashlib.sha256(fixture.read_bytes()).hexdigest(),
    "case_count": len(cases), "new_case_count": len(NEW), "expectation_revisions": [], "independent_holdout": False,
    # food-query-parser-v10 (origin/main f163e4a1) before the first run of these cases.
    "parser_sha256_before_first_run": "7c4d5c9b8b2d0d708ec2e7e4b7f1916fff5c8b93f40b6ed593c484697ead04cc",
}
(root / "manifest-v10.json").write_text(json.dumps(manifest, indent=2) + "\n")
print(manifest)
