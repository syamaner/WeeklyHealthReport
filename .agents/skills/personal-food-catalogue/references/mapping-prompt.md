# Mapping prompt for intake items

Give this to one offline subagent per batch of up to about 200 lines. Replace `<W>` with the
workspace path and `<SOURCE>` with the intake source id. Write the name files first if they are
missing (`work/cofid-names.txt`, `work/usda-names.txt`, `work/tfda-names.txt`; see
`prepare_families.py` and the TFDA resource).

```text
Map foods to generic food records for a private nutrition catalogue. Work offline: no web, no
network. Read-only except ONE output file.

Inputs in <W>/work/:
- intake-batch.txt: "n<TAB>food<TAB>state hint<TAB>region (UK or Taiwan)<TAB>note".
- cofid-names.txt: "row<TAB>name" (UK CoFID 2021). Preferred for UK foods.
- usda-names.txt: "index<TAB>name" (USDA). Second choice.
- tfda-names.txt: "index<TAB>English<TAB>Chinese<TAB>preparation" (Taiwan). Preferred for Taiwan items.
Search the name files with grep; do not read them whole.

For EVERY input line output one JSON object:
{"n": <int>, "concept": "plain generic name, singular, lower case", "variety": "<or null>",
 "aliases": [...], "fallback_chain": ["most specific", "...", "concept"],
 "category": fruit|vegetable|herb_spice|dairy|egg|meat|fish|grain_cereal|bakery|legume|nut_seed|oil_fat|condiment_sauce|snack|confectionery|beverage|alcohol|ready_meal|other,
 "product_type": "fresh_whole"|"packaged_single_ingredient"|"packaged_composite",
 "state": "raw"|"cooked"|"canned"|"frozen"|"dried"|"smoked"|"unknown",
 "generic": {"source": "cofid"|"usda"|"tfda"|null, "key": "<cofid row, or usda/tfda index as string, or null>",
             "name": "<exact name from that file or null>",
             "match": "same_food_same_state"|"close"|"concept_only"|"none", "note": "<reason unless same_food_same_state>"}}

Rules:
- Match the food as sold or eaten: fresh produce is raw; roast slices are cooked; canned is canned.
- Never pick a cooked record for a raw food or the reverse, never a different food, never a
  different fat level, flavour or packing medium as "close" (use concept_only). US "enriched" or
  "fortified" records are concept_only unless the food is fortified.
- Composite dishes: the same dish if a record exists, else concept_only or none.
- A correct "none" beats a wrong match; these are proposals a person will review.

Write the JSON array (all lines, input order) to <W>/work/intake-mapping-<SOURCE>.json. Validate it
parses, has one object per input line, and every generic.name equals the name at its key. Reply
with only: count, counts per source and per match, and up to 8 items you were least sure about.
```

## Receipt form (first build only)

For `work/mapping-batch-N.txt` from `prepare_families.py` (lines "n<TAB>title"), use the same rules
with CoFID only, and write `work/mapping-N.json` with, per line: `n`, `concept`, `variety`,
`aliases`, `fallback_chain`, `category`, `product_type`, `state`, `cofid_row` (the row from
`cofid-names.txt` or null), `cofid_name` (the exact name at that row, or null) and `cofid_match`.
`validate_mappings.py` downgrades a mapping to `concept_only` when `cofid_name` differs from the name
at `cofid_row`, or, when no name is given, when the record's name shares no word with the mapping's
concept, variety or aliases; and for state, smoking and fat-level conflicts.
