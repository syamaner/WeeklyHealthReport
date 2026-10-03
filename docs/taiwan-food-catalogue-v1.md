# Taiwan food catalogue v1

## Architecture gate and source contract

User scope: usual fruit, vegetables and foods in Taiwan, with offline availability.
The first slice is a reviewed selection from TFDA dataset 8543, not a claim of full
Taiwanese food coverage. The complete public snapshot has 2,180 records; unreviewed
records are not bundled. Public data source: https://data.gov.tw/en/datasets/8543 .

A deterministic offline Python projector owns grouping, record-name checks, exact
nutrient/unit mapping and frozen source hashes. The curated mapping owns explicitly
reviewed translations and aliases. An infrastructure `TFDAGenericFoodSearch` adapter
implements the existing application-owned `GenericFoodSearching` interface; the
composition root adds it to the existing local composite. No network/provider work
occurs at runtime for this source. Domain and confirmation policy remain unchanged.

Closed invariants: one source record per candidate; explicit per-100-g edible basis;
source preparation only when explicitly stated; no density, piece weight or cooking
conversion; null is unknown; no cross-source nutrient backfill. Source name, sample
preparation, record ID, archive hash and field-level source location remain traceable.
Chinese sample names are retained alongside reviewed English names; aliases affect
retrieval only. All results require user selection as Taiwan composition estimates.

Energy uses the source field 熱量 (kcal), not 修正熱量 and not an app calculation.
Carbohydrate retains 總碳水化合物 including its source convention. Only explicitly
mapped source nutrients are projected; vitamin-equivalence conventions, IU values,
water-to-volume conversion and unmapped fields remain unknown. Declared zeros remain
zero, blanks remain missing. Source sample preparation for lab analysis does not
establish a serving size or imply that the user cooked or peeled the food.

## Licence and provenance

Taiwan Food and Drug Administration, 2026, 食品營養成分資料集 (Nutrition
Information Database), public snapshot retrieved 2026-10-03. This Open Data is made
available under Open Government Data License 1.0; users may use it subject to its
conditions: https://data.gov.tw/license . This projection changes layout and adds
reviewed English retrieval labels; it is not endorsed by TFDA.

## Validation plan

- Hash-bound rebuild and all projected values compared with their original source rows.
- Synthetic malformed/duplicate/null/unit/name-drift projection tests.
- Real bundled positive retrieval in English, Chinese and reviewed romanisation.
- Negative controls for wrong ingredients, preparation, frozen/dried variants and brands.
- Confirmation stays undecided; count/volume cannot become edible grams without evidence.
- Composite main-search and list-search integration, source label and persistence round trip.
- Package suite, complete simulator suite, dependency boundaries and static analysis.

These are exposed development regressions. Independent accuracy and physical-device
acceptance remain separate. Private notes, receipts, stock and device labels are not
inputs to the importer or repository fixtures.

## Reproduce and interpret the report

The public download is https://data.fda.gov.tw/data/opendata/export/20/json . Keep
the full ZIP outside Git. From the repository root, with that local ZIP:

```sh
python3 Tools/FoodSourceEvaluation/project_tfda.py /path/to/20-json.zip Tools/FoodSourceEvaluation/tfda-reviewed-foods-v1.json /tmp/tfda-generic-v1.json
python3 Tools/FoodSourceEvaluation/audit_tfda.py /path/to/20-json.zip /tmp/tfda-generic-v1.json /tmp/tfda-audit.json
python3 -m unittest discover -s Tools/FoodSourceEvaluation/tests -p 'test_tfda_projection.py'
swift test --package-path Packages/FoodLedgerKit --filter TFDAGenericFoodSearchTests
```

The pinned public-source audit is `Tools/FoodSourceEvaluation/tfda-public-source-audit-v1.json`.
It records 63 reviewed foods from 2,180 source records, with all 1,163 projected
values corresponding to their exact source row, field, unit and literal. All 63
have four source macros; 53 declared zero values are retained. Thirty records have
unknown cooking state, which remains unknown. The slice comprises 20 fruit, 25
vegetable, three mushroom and 15 other food records. None of these counts is a
representative user-query coverage rate.

The existing frozen CoFID/USDA evaluation reports retain their historical two-source
composition. They must not be relabelled as evidence for the new three-source app.
This TFDA source audit, catalogue retrieval contracts, real composite query/list
contracts and two-store save/reopen contract provide separate development evidence.
A future independent acceptance run must freeze all three source projections.

## Local validation receipt — 2026-10-03

- Deterministic rebuild matched the bundled projection byte for byte; offline audit
  passed all 1,163 field comparisons. Four projector regression tests passed.
- All 193 reviewed aliases reached their intended record. These are exposed
  development cases, not held-out accuracy observations.
- Full FoodLedgerKit suite: 546 tests, two optional skips, zero failures. Includes
  the real three-source composite, main/list quantity handoff, and save/reopen
  through both in-memory and GRDB stores.
- Complete iPhone 17 Pro simulator suite: 281 passed, zero failures or skips.
- Xcode static analysis, package dependency boundaries and `git diff --check` passed.
- No provider inference calls, private-data import, commit, push or upload occurred.
  These changes are uncommitted in the isolated nutrition-test-build worktree and
  are not in an installed or TestFlight build. Physical-device acceptance remains open.

Local evidence: `/private/tmp/whr-tfda-package-full.log`,
`/private/tmp/whr-tfda-full.xcresult`, `/private/tmp/whr-tfda-analysis.log`.
Before device acceptance, build this candidate and test `lian wu`, `蓮霧`, `guava`,
`空心菜`, `scallion pancake` and `冷凍蔥油餅`; inspect the TFDA label, source sample,
explicit edible grams, confirmation and save/reopen. Verify plain pancake does not
silently become frozen, and a fruit count does not create a portion weight.

Release-preparation follow-up: unsigned iPhone Release build passed, and all four
bundled public JSON resources match their repository bytes, including the TFDA hash
above. No unexpected data resources were found. All eleven TFDA/USDA projector tests
pass and are now included in the existing nutrition CI job; workflow YAML validates.
See `nutrition-test-build-readiness-v1.md` for the current delivery boundary and
physical-device checklist. No new package/simulator rerun was needed after the
CI-command and documentation-only follow-up.
