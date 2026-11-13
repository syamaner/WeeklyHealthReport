# Personal food database import v2

Status: approved by the owner on 13 November 2026 (five decisions in section 2). A delta contract:
everything in [import v1](personal-food-catalogue-import-v1.md) that this document does not name
stays in force for both schemas, and a `personal-food-catalogue-v1` file stays valid forever under
exactly the v1 rules, rule codes and fixtures.

## 1. Purpose

The app's barcode lookup and text search project Open Food Facts records under
`off-product-projection-v6` ([plan](off-barcode-candidate-plan-v1.md), owner approval 12 November
2026): a lone per 100 panel that contradicts the pack wins over the pack, and a single per-serving
panel is scaled to per 100. Catalogue v1 cannot carry a scaled value, because its `source_value` is
exactly `{value, unit}` and `transforms` holds exactly one pair, and a scaled value needs the serving
size and, for sodium stated in grams, two transforms. v2 is v1 plus that shape, so the skill's
catalogue builds admit the same records the app admits.

## 2. Owner decisions (13 November 2026)

1. A new wire schema, `personal-food-catalogue-v2`, defined by this delta contract. v1 files keep the
   v1 rules, rule codes and golden SHA-256 exactly.
2. The skill always writes v2 (one code path, deterministic output); there is no v1 fallback.
3. Confirm shows "Some values scaled from a 28 g serving" (`ml` for a volume serving) for a database
   entry whose candidate uses a scaled value, matching the barcode route's "scaled from a 28 g
   serving" source line.
4. The on-device store keeps the data file name `personal-food-catalogue-v1.json` as a fixed storage
   name, not the schema, so an installed database keeps loading with no migration.
5. The private catalogue is rebuilt after merge, not in the change itself; the skill's change report
   stays in the private workspace.

The approval also covers the provenance fix of section 4: a scaled value's source carries a
per-serving basis, never per 100.

v1 section 12 decision 3 named a later "v2 with a count basis" for supplements. That work, if it
comes, takes the next free schema version; this document does not change the supplement decision.

## 3. File format `personal-food-catalogue-v2`

`schema` is `personal-food-catalogue-v2`. Every v1 rule applies, with these additions only:

1. **Projection v6.** An Open Food Facts release may name `off-product-projection-v6`: the release
   form becomes `pfc-off:sha256:<64 hex>:projection:off-product-projection-v<4, 5 or 6>:retrieved:<YYYY-MM-DD>`,
   and `pipeline_version` equals the projection in the ID, as in v1. A v1 file citing v6 is still
   `source-form`.
2. **The serving transform.** `off-serving-to-100` / `v1` is allowed on any of the eight Open Food
   Facts nutrients (`energy_consumed`, `protein`, `carbohydrates`, `fat_total`, `fat_saturated`,
   `fiber`, `sugar`, `sodium`), only on `exact_product_dataset` values whose release names
   `off-product-projection-v6`, with the source unit equal to the canonical unit (after `mass-g-to-mg`
   for sodium in grams). Anything else is `transform-scope`. It is a scaling, not a calculation: it is
   absent from `NutrientDerivation.calculatedTransforms`, so the food export marks such a value
   `calculated: false`, as it does a barcode-lookup v6 value.
3. **The serving.** `source_value` gains one optional key, `serving: {quantity, unit}`, present if and
   only if the value's transforms include `off-serving-to-100`. `quantity` is a finite number above 0
   and below 1e15, never a boolean or text; `unit` is `g` or `ml`. A malformed serving, or a serving
   without the transform or the reverse, is `source-value`. The unit must match the entry's basis
   (`g` for `per_100_g`, `ml` for `per_100_ml_as_labelled`), else `transform-scope`.
4. **One chain.** `transforms` holds one pair, or exactly `[mass-g-to-mg/v1, off-serving-to-100/v1]` in
   that order (the app's order) for sodium in grams. Any other two-element list, or a longer one, is
   `transform-shape`.
5. **Arithmetic.** `value = source_value.value × 1000 (with mass-g-to-mg) × 100 / serving.quantity`,
   with v1's tolerance of 0.5 per cent; otherwise `transform-arithmetic`. An expected value that is not
   finite (a tiny serving such as 1e-320 overflows the scale) is also `transform-arithmetic`.
6. **Plausibility.** A value carrying `off-serving-to-100` above 100 g, 100,000 mg or 900 kcal per 100
   is rejected with the new code `serving-implausible`, mirroring the app, which declines such a
   record. The skill never writes one; this is defence in depth.
7. **One serving per release.** Within one entry, every `exact_product_dataset` value citing one
   release has the same serving, or none has one; otherwise the new code `serving-mismatch`. They come
   from one panel.

Rule codes: v2 adds `serving-implausible` and `serving-mismatch`. A v1 file can never get them; the
v1 fixture manifest keeps listing the v1 set, and the v2 manifest lists both sets. A file with an
unknown schema gets `schema` and the v1 rules for the rest, as before.

Deviation recorded at the architecture gate: the design proposal bounded `quantity` below 1e6. The
app admits any finite numeric serving above 0, so that bound would let the skill write files its own
check refuses; v2 uses the nutrient number bound, below 1e15, instead.

Example of a scaled sodium value (synthetic):

```json
{"value": 400.0, "unit": "mg", "source_kind": "exact_product_dataset",
 "source_release": "pfc-off:sha256:<64 hex>:projection:off-product-projection-v6:retrieved:2026-11-13",
 "record_id": "off:gtin:00000000000024", "match": "probable",
 "transforms": [{"transform_id": "mass-g-to-mg", "version": "v1"},
                {"transform_id": "off-serving-to-100", "version": "v1"}],
 "source_value": {"value": 0.112, "unit": "g", "serving": {"quantity": 28, "unit": "g"}}}
```

## 4. App behaviour

- **Release.** The database release's `schemaVersion` is the file's own schema, so it names
  `personal-food-catalogue-v2` for a v2 file. It is still a pure function of the file's bytes (the
  schema is inside them), so release immutability holds; stored v1 releases are untouched.
- **Store.** The manifest records the file's schema; a stored manifest is valid for either schema and
  for nothing else, and keeps `version` 1 and its byte form. The data file name stays
  `personal-food-catalogue-v1.json` (decision 4). A manifest whose schema differs from the decoded
  file reads as damaged, never as a release with the wrong `schemaVersion`: the search index and
  Settings both treat it so, and importing the same bytes again repairs the manifest (the store reuses
  a release folder only when its manifest names the same file and schema).
- **Provenance.** The candidate builder gives a scaled value the source basis
  `perServing(quantity g or ml)` and the panel's own number, with the transforms in file order. This
  reproduces the barcode route's provenance for the same record, so a saved log from either route
  carries the same transform pairs and source basis shape. A value without a serving keeps the
  entry's basis, as in v1.
- **Confirm.** When a value the candidate uses carries `off-serving-to-100`, Confirm's Food section
  shows "Some values scaled from a 28 g serving" (decision 3), from the candidate's own values
  (`FoodSearchResultText.databaseScaledServingNotes`). The candidate's material differences carry the
  same line after "Your food database entry · per 100 g", which search rows list. The serving is written as the barcode route writes it ("28", "12.5", no
  trailing ".0"), through one shared helper, `OpenFoodFactsServingText`. A panel-wins entry needs no
  extra line: its basis line already reads "per 100 mL as labelled".
  The serving line writes `ml` as the barcode route does (decision 3), while the existing basis line
  keeps its own "mL", so a scaled per 100 ml entry shows both spellings; aligning them is a separate
  copy decision for the owner.
- **Closed rule in one place.** The transform pair, the projection version and the plausibility
  limits live in one Domain constant, `OpenFoodFactsServingRule`, used by `OpenFoodFactsLookup`, the
  codec and the candidate builder. The skill mirrors the values; the tests pin them.

## 5. Skill

`off_rules.py` follows `OpenFoodFactsLookup.project` rule for rule, including the panel-wins rule,
the per-serving path (`per_quantity` a non-boolean finite number above 0, or text matching
`[0-9]{1,6}(\.[0-9]{1,3})?` in full, so `"112\n"` declines in both), scaling after the g to mg
conversion in the app's double arithmetic (a value that overflows before scaling is left out, as the
app leaves it unknown), refusal when only the scale overflows, and plausibility over every scaled value,
including bound ends the port then leaves out. A record v5 admits keeps `off-product-projection-v5`
and byte-identical values (an integer stays an integer) and releases; only records v5 refuses get v6. The one remaining difference
from the app is v1's: a `<` or `>` value becomes a bound in the app and is left out of the catalogue.

`export_v1.py` (the module keeps its name; it is not a contract) writes schema
`personal-food-catalogue-v2` to `out/personal-food-catalogue-v2.json`, and its `check_bytes` applies
the v1 rules to a v1 file and the v1 plus section 3 rules to a v2 file. `purchase_counts.py` accepts
either schema. A rebuild re-projects the private cache (no new query, no new field, no new endpoint):
v5 admissions are unchanged, v6 records gain values, and an entry whose basis becomes
`per_100_ml_as_labelled` loses a `merge` role through the existing role rule. The skill reports those
counts in the private workspace before the owner imports.

Import a v2 file only on an app build with this change; an older build refuses it as an unknown
schema ("This file is not a food database file from your Mac.") and keeps the active release.

## 6. Architecture gate (13 November 2026)

Responsibilities: the codec, the model, the schema enum and `OpenFoodFactsServingRule` in Domain; the
candidate builder, importer, search index and the serving wording in Application; the store in
`FoodLedgerPersonalDatabase`; the projection in `FoodGenericSearch`. No new port, no framework type
across a port, dependency direction unchanged. Invariants: v1 decoding, rule codes, fixtures and
golden bytes unchanged; stored manifests and releases decode and re-encode unchanged; provenance
equal to the barcode route; `calculated: false` for the serving transform; egress unchanged.

The `architecture-gate` review passed with six changes, all made before production code: the
database release takes its schema from the decoded file and a disagreeing manifest is damaged; the
stored manifest accepts only the two known schemas; the serving wording lives in Application and the
lookup uses it; the transform pair and limits are one Domain constant; the serving quantity has its
own above-zero check (the nutrient number rule accepts 0); the rule-code test compares the enum with
the v2 manifest and the v1 manifest with the v1 subset.

## 7. Privacy and egress

No change. The app adds no destination: import stays a local file, search and Confirm run offline.
The skill adds no query, field or endpoint; v6 re-projects records already in the private cache.
Fixtures are synthetic, and no private data enters the repository. `privacy-and-egress.md` is
unchanged.

## 8. Contract tests (synthetic only)

- Shared fixtures in [`docs/fixtures/personal-food-database-v2/`](fixtures/personal-food-database-v2/),
  written by `test_export_check.py --write-v2` and read by the Swift codec tests
  (`PersonalFoodDatabaseCodecV2Tests`): a golden file with a scaled entry (energy, protein and a
  sodium chain from a 28 g serving) and a panel-wins drink, one `reject-*.json` per v2 rule edge with
  its rule code, and accept files (tolerance edge, v1 content under v2, an ml serving on a per 100 ml
  entry). The v1 folder is unchanged; regenerating it gives identical bytes.
- Parity: every per-serving and panel-wins case in `test_off_rules.py` is mirrored in
  `OpenFoodFactsSkillParityTests.swift`, including `"112\n"`, an implausible bound end, scale
  overflow, and v5 admissions keeping v5. A cross-route test builds the v2 golden's scaled entry
  through the candidate builder and finds the barcode projection's amounts, source values, basis and
  transforms.
- App: the database release names its schema; the importer records it; the store round-trips a v2
  manifest and refuses an unknown schema; a manifest that disagrees with its file is damaged; the
  scaled candidate's provenance, Confirm line (g and ml) and byte-stable round trip; the export check
  accepts its own `build` output.
- CI checks both fixture folders with the skill's checker.

## 9. Validation

The gates in `AGENTS.md`. Device acceptance is the owner's, after merge: rebuild the private
catalogue, read the private change report, import on the iPhone and compare a few scaled entries with
their packs.
