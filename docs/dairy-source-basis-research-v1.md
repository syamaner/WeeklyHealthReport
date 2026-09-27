# Dairy source and quantity-basis research v1

Status: proposed contract, not source admission or implementation. Evidence read on 27 September 2026 against main `676380b39d068b19ff20f5dfd317e0ff34cdb0d7`. This bounded slice of [#144](https://github.com/syamaner/WeeklyHealthReport/issues/144) does not close broader source coverage or device acceptance.

## Observed problem and decision

The [build-11 report](https://github.com/syamaner/WeeklyHealthReport/issues/144#issuecomment-5858884185) records `200g Greek yoghurt 10% fat` returning labelled USDA alternatives at 4.39/5 g fat per 100 g. It also records `200ml whole milk` selecting CoFID `Milk, whole, pasteurised, average`: nutrition exists per 100 g, but volume totals are unavailable. These are separate identity/coverage and quantity-basis problems.

Recommend retaining explicit alternatives and measured-gram recovery now. A later authorised slice may improve the explanation of the existing CoFID 10.2% Greek-style alternative. Exact 10% coverage needs a compatible whole record, not adjustment of another yoghurt's fat. For everyday whole milk, prefer a narrowly reviewed, versioned conversion on the existing CoFID record if source rights and applicability are established; direct product-specific per-100-mL records are a separate option. Neither route is admitted here.

## Complete bundled projection audit

Run from repository root:

```sh
python3 Tools/FoodSourceEvaluation/audit_dairy_basis_v1.py > /tmp/dairy-audit.json
cmp /tmp/dairy-audit.json Tools/FoodSourceEvaluation/dairy-basis-audit-v1.json
```

The saved result pins both projection hashes and emits every Greek yoghurt-name hit with record identity, fat evidence and source basis. It counts all yoghurt-name hits and scans all records before any retrieval cap. `yog` and `greek` are documented lexical predicates, not a semantic taxonomy or proof of absence from all public sources. USDA basis is established by its current adapter, which always projects per 100 g; the script does not infer volume from a food name.

| Bundled projection | Records | Names containing `yog` | Also containing `greek` | Numeric 10 g fat / 100 g in yoghurt-name records | Milk-name records with volume basis |
| --- | ---: | ---: | ---: | ---: | ---: |
| CoFID 2021 | 2,887 | 17 | 2 | 0 | 0 / 132 |
| USDA Foundation/SR | 8,156 | 91 | 31 | 0 | 0 / 291 |

CoFID row 2875 is **Yogurt, Greek style, plain**, 10.2 g fat/100 g; description: seven samples, six brands, whole milk. Row 2874 is the fruit variant, 8.4 g. USDA includes plain whole-milk Greek records FDC 2259794 (4.39 g) and 171304 (5 g); none of the 31 Greek yoghurt-name hits has numeric fat 10 g/100 g. A source average of 10.2 cannot be rounded into proof of an exact 10% product. Greek and Greek-style remain distinct reviewable types.

The selected milk is CoFID row 1681, per 100 g, fat 3.6 g. CoFID's 31 volume-basis records are outside the `milk` name predicate; USDA's adapter has no volume-basis record. These counts include compound foods whose names contain milk and do not estimate coverage of drinkable milk variants. OFF is an optional exact-barcode network route, not a bundled generic catalogue, and its current mapper is mass-only. Saved personal-library contents are outside this public audit.

## Retrieval, truncation and existing evaluation

`CoFIDGenericFoodSearch` requires all meaningful food tokens, applies identity compatibility, ranks and caps at ten. `USDAGenericFoodSearch` similarly caps at ten, so 31 USDA Greek records can be truncated. The two CoFID Greek records are below that cap for the parsed `greek yoghurt` food terms with default identity; the additional `style` descriptor remains an explicit alternative. `GenericFoodRankingPolicy` penalises unrequested specialisations including `style`, and prefers ordinary whole/plain representations. `CompositeGenericFoodSearch` interleaves the capped lists, sorts representation preferences, then promotes exact numeric fat matches. `FoodQueryCandidateAssessment.matchesFat` uses a tolerance below 0.000001, not a nutritional equivalence threshold.

Thus no numeric-10 yoghurt in the audited name cohort can be hidden by the caps: none exists before them. This does not prove semantic absence under every synonym, an omission-free upstream projection, or that the CoFID near match was visible on device. The build-11 report establishes leading visible results only. A future ranking change must replay actual production search, not treat this Python source inventory as a ranking simulation. Do not relax the fat tolerance or erase `style` to make the case pass.

The v5 query evaluation already contains `200g Greek yoghurt 10% fat` and volume milk phrasing (`180 ml whole milk`). Its 511 same-author synthetic cases measure parsing/routing/quantity hints, not source coverage or ranked nutrition completeness. `SearchQualityDevelopmentTests.testQuantityAndFatVariantDoNotEliminateYoghurtAndRetainEvidence` checks returned alternatives and notes; it does not require an exact 10% record. Existing passing tests therefore do not establish acceptance of either device complaint.

## Official public evidence, not admitted data

| Source inspected | Evidence and limit | Recommendation |
| --- | --- | --- |
| [Olympus UK 10% Greek yoghurt](https://www.olympus-foods.co.uk/products/yogurt/greek-yogurt-10-fat.html) | Manufacturer specifies 10 g fat and 134 kcal per 100 g, with carbohydrate/protein and other label fields. This is a named product, not every Greek yoghurt. The page does not establish immutable release, GTIN, pack variant or formulation date. | Useful exact-fat product candidate for a future reviewed label/source slice. Require product selection and rights review; no generic substitution or micronutrient backfill. |
| [Graham's organic whole milk](https://www.grahamsfamilydairy.com/our-products/organic-range/organic-whole-milk/) | Manufacturer explicitly declares per 100 mL: 65 kcal, protein 3.4 g, carbohydrate 4.9 g, fat 3.6 g. Organic identity is decisive. No complete micronutrient table or immutable formulation evidence established. | Demonstrates direct-volume feasibility for that selected product. Do not copy its values into CoFID average milk. |
| [Arla Cravendale whole milk 2 L](https://www.arlafoods.co.uk/brands/arla-cravendale/cravendale-whole-milk-2l/) | Current page labels its values **per 100 G**, despite selling in litres. | Not admitted as a volume source; packaging volume does not define nutrient basis. |
| [Dairy UK composition tables, August 2025 URL](https://milk.co.uk/wp-content/uploads/2025/08/Nutritional-Composition-of-Dairy.pdf) | Printed pages 3 and 6 give a whole-milk factor 1.03 and explicit 100 mL = 103 g / 200 mL = 206 g. Whole-milk energy is 63 kcal/100 g and rounded 130 kcal/200 mL. Tables cite the seventh summary edition and some updated OHID milk values. | Strong practical UK conversion candidate; rights, immutable artefact hash and exact CoFID applicability still require admission. Do not merge its updated nutrients into the older CoFID record. |
| [FAO/INFOODS Density Database v2, 2012](https://www.fao.org/fileadmin/templates/food_composition/documents/density_DB_v2_0_01.pdf) | Printed page 10 lists UK liquid milk 1.03 in the **specific gravity** column, a dimensionless quantity, alongside distinct density entries from other references. Definitions distinguish these quantities. Copyright page requires a rights decision; public access does not establish unrestricted redistribution. | Corroborating historical reference, not an automatically usable 1.03 g/mL adapter input. Check columns, reference conditions and rights before conversion admission. |

The manufacturer pages are mutable observations. Public reading is authorised; API calls, accounts, integration, redistribution and source adoption are not authorised by this document. This research stores concise factual findings and references, not raw product pages, images or a new nutrient catalogue. No exact current package or independently adjudicated product accuracy is claimed.

## Proposed contract `dairy-source-basis-v1`

Responsibilities and direction: source adapters project admitted records/conversion evidence; pure domain code validates applicability and computes quantities; application orchestration invalidates stale selection; presentation explains source, type differences and missing basis. Keep existing domain nutrition/source records intact. A consumer-owned conversion lookup keyed by selected source-record identity is a credible seam; avoid a universal density service accepting arbitrary names. Adapter alternatives must satisfy the same behavioural tests.

Closed invariants: original input, explicit candidate selection, type/product identity, whole-record nutrients, unknown/bounded values and source provenance remain unchanged. Conversion evidence has separate provenance from nutrition. It cannot manufacture nutrient completeness, change an estimate to measured, or authorise a provider. No schema or production code changes occur here.

An admitted conversion must persist its version/ID, immutable source hash/reference/page or row, applicable nutrition release/record IDs, supported food/preparation/formulation, input volume, documented mass-per-volume rule, converted mass and estimated basis. Specific gravity alone is insufficient without a reviewed derivation and reference conditions. Retain versions for saved-record reproduction. Changing food/source invalidates the rule. User-reported measured grams remain a first-class alternative, following [count-portion-guide-research-v1](count-portion-guide-research-v1.md); this is not count-guide implementation.

Required future development contract cases:

1. Exact original yoghurt phrase retains 200 g and requested 10%; CoFID 10.2 Greek-style and USDA 4.39/5 stay labelled alternatives. No autosave, tolerance relaxation, rounding into identity, or nutrient modification.
2. A separately authorised exact-10 product record must retain named-product identity and declared basis. Equal fat is not proof of product identity; incompatible Greek-style/flavoured variants remain explicit.
3. Inventory, eligible retrieval, returned top-k, user-visible results, selected identity and calculable totals are measured separately. Replay both device phrases plus grams/mL, Greek/Greek-style, percentage and organic/ordinary controls through actual adapters. Freeze expectations before tuning; exposed cases remain regression evidence.
4. CoFID whole milk without an admitted conversion still cannot calculate 200 mL totals. Measured 200 g calculates from the mass source. Direct-volume candidates require their own selected product and per-100-mL evidence.
5. If the reviewed rule is 1.03 g/mL, 200 mL gives **206 g estimated**, then 63 kcal/100 g gives **129.78 kcal before presentation rounding**, carbohydrate 9.476 g, protein 7.004 g and fat 7.416 g. Compute from unrounded mass/source values; do not take rounded Dairy UK 200-mL nutrients or call this measured mass.
6. Conversion rejects unapproved records, organic/product-specific substitutions, condensed/evaporated/powdered or plant milk, invalid/non-finite quantities and missing rule/reference conditions. No universal 1 mL = 1 g. Unknown nutrients stay unknown.
7. Save/reopen, archive round-trip, edit quantity, change candidate and update catalogue retain or invalidate provenance correctly; stale conversions cannot survive a food change. Original input volume and any measured-gram override remain distinguishable.
8. Field-local missing-basis guidance, explicit alternative selection and estimated-mass explanation must be reviewed with VoiceOver/larger text on device. Package/simulator tests and Xcode analysis establish software behaviour only; build-11 observations are prior evidence, not validation of a future change.

Admission gates: agree the exact record allow-list and conversion derivation; verify source rights/attribution/redistribution; pin and inspect the source artefact; review persisted contract compatibility; freeze production-adapter fixtures; then separately authorise implementation. No further research-provider budget is assumed. Broad #144 remains open.
