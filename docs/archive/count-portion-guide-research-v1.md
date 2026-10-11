# Count and portion guides: research v1

Date: 27 September 2026. Baseline: merged main 6eed40bf1b9130eabeaef8760d74862c6dd039e5 (PR #162).

Status: UX decisions approved by the user on 27 September 2026; source-guide admission remains pending. Research and contract preparation only. No production source, schema, provider, nutrient value or app behaviour changed. Build 11 device testing belongs to the other chat. Existing retrieval fixtures and results remain unchanged.

## Approved UX decisions

The user approved both count/size estimates and direct measured weight, edible-weight guidance, explicit estimate labels and overrides, actionable missing-input messages, supported guides only, and source details behind disclosure.

Measured weight means the food as eaten: for example, an egg weighed after peeling and boiling or frying. Keep the selected preparation consistent with that weight and the nutrition record; never substitute a raw record silently. For fried foods, do not infer added oil or absorbed fat from the measured weight. Any separately logged ingredients continue through their existing flow. Typed grams are user-reported measurements only when that basis is explicitly selected.

This approval settles UX direction, not admission of the historical UK source or permission for new provider calls. Production implementation and source-guide admission remain separate work.

## Recommendation

Start with whole chicken eggs using a versioned, source-specific portion guide. Keep count, size and estimated edible grams visible; allow the user to replace the total weight. Do not offer a universal small/medium/large selector for all foods. A guide must support the selected food, part, preparation and size convention.

Do not ship the USDA size labels as UK carton sizes. A UK guide needs an explicit admission decision for the evidence below and a reviewed mapping to catalogue records. Pending that decision, measured edible grams remain the supported path.

## Existing admitted source: offline inspection

Inspected the existing local USDA SR Legacy April 2018 archive, not a new download or API call:

`/private/tmp/whr-source-probe/FoodData_Central_sr_legacy_food_json_2018-04.zip`

SHA-256: `0fe8ae486a2c8eb42cb96413f058deb51863a46c8fb8eeb4b1fb45006dd338ef`.

Read JSON records inside the ZIP with Python zipfile/json. These are source household portion weights, not measurements of the user's food. The existing projection in `Tools/FoodSourceEvaluation/project_usda.py` retains identity/nutrients but does not project `foodPortions`. Production use would require a versioned projection and contract review.

| FDC record | Descriptor | Portion ID | Source grams for amount 1 |
| --- | --- | --- | ---: |
| 171287 whole egg, raw, fresh | small | 88379 | 38 |
| 171287 | medium | 88378 | 44 |
| 171287 | large | 88374 | 50 |
| 171287 | extra large | 88375 | 56 |
| 171287 | jumbo | 88376 | 63 |
| 173424 whole egg, hard-boiled | large | 92500 | 50 |
| 172183 egg white, raw, fresh | large | 90043 | 33 |
| 168195 clementines, raw | fruit | 82645 | 74 |

The whole raw egg record also contains a cup measure; exclude it from count choices. These JSON entries use an undetermined measure-unit ID (9999), so unit ID alone cannot establish piece semantics. Admission must review the descriptor and record context. No uncertainty or confidence interval was extracted; do not manufacture one.

Banana record 173944 supplies length-qualified sizes: extra small 81 g, small 101 g, medium 118 g, large 136 g and extra large 152 g. Cup and NLEA-serving entries are separate measures and must not enter the piece-size menu. Clementines support a fruit guide, not invented size categories. Bread slices require a specific product/source serving; bowls and arbitrary meat pieces have no universal weight.

[USDA SR Legacy documentation](https://www.ars.usda.gov/ARSUserFiles/80400525/Data/SR-Legacy/SR-Legacy_Doc.pdf) documents common-measure gram weights and nutrient values per 100 g edible portion. [FDC documentation](https://fdc.nal.usda.gov/data-documentation/) identifies SR Legacy as the final April 2018 release.

## UK source candidate, not admitted

[Department of Health egg sampling report, June 2012](https://assets.publishing.service.gov.uk/government/uploads/system/uploads/attachment_data/file/167974/Nutrient_analysis_of_eggs_Sampling_Report.pdf), printed pages 6, 8, 18 and 21, reports UK collection in March 2011, twelve sub-samples, and average whole/shell masses. Some large samples included eggs below 63 g; individual sampling sheets also contain inconsistent 2010 dates. It is historical sampling evidence, not a current population estimate.

Derived from rounded published averages: raw medium 59.2 − 7.6 = 51.6 g; raw large 66.3 − 8.3 = 58.0 g; boiled medium 58.8 − 6.5 = 52.3 g; boiled large 64.9 − 7.1 = 57.8 g. These are proposed estimates, not directly reported edible gram values or universal defaults. No small/extra-large evidence is established here. Do not extrapolate.

[APHA marketing guidance](https://assets.publishing.service.gov.uk/media/69382d2de447374889cd8f73/EMR01_Guidance_on_legislation_covering_egg_marketing_November_2025.pdf), actual document version 8 dated 17 September 2026, defines shell-egg sizes: small below 53 g, medium 53–under 63 g, large 63–under 73 g, extra large at least 73 g. These categories do not establish edible portion weights.

PDF text inspected; screenshot retrieval for page 18 failed, so visual verification of that raw table remains an admission prerequisite. The boiled table screenshot request returned successfully. No new report data was bundled.

## Proposed user flow

1. Search “2 eggs”; preserve the original phrase and parsed count.
2. User selects the food and confirms preparation. Do not infer boiled/raw or whole/white/yolk from a generic count.
3. Show “Amount eaten: 2 eggs” and “Size: Choose a size”. Offer only supported choices, identify the size convention, and do not silently select medium.
4. Show “Estimated edible weight: … g” with “Excludes shell” for whole eggs. Put source/version details behind a disclosure.
5. Offer “Enter measured weight” as a first-class alternative to the size guide, with a total edible-weight field in grams. A user choosing this path explicitly reports that the weight was measured; label it “Measured weight (entered by you)”. It requires no size selection or portion guide. Also allow editing an estimated total without claiming it was weighed. Retain count and any prior guide for explanation, but use the entered total for the quantity calculation. For whole eggs, prompt for weight without shells; for fruit, clarify the edible part. Do not infer measurement merely because a grams field was filled.
6. Save through the existing confirmation flow. If a guide is unavailable, say “Enter the total weight without shells to save” beside that field.

Example only: two large eggs using USDA record 171287, portion 88374, produce 100 g. This is a US source guide; it is not a UK-large conversion.

Mixed sizes require separately selected supported sizes or an entered total. Changing food/part/preparation invalidates the guide and calculated weight. Changing count recomputes an estimate, but must not silently overwrite a manual total. Direct grams/millilitres remain unchanged. No density conversion is introduced.

## Architecture gate for a future implementation

Responsibilities: source adapters project admitted guides; pure domain values define applicability and arithmetic; application orchestration maintains count/guide/override state; presentation explains choices and missing input. Wire adapters at the existing composition root.

Stable invariants: preserve query text, candidate identity and nutrition provenance; never invent missing weights/nutrients; require positive finite weights; never silently accept an alternative or autosave. Keep quantity provenance separate from nutrition provenance.

Credible extension axis: a consumer-owned guide lookup capability accepting a selected food identity, returning versioned guides or none. Avoid a universal serving repository. Same-record guides are the initial policy; cross-source mappings require explicit reviewed identities and preserve both sources.

Persisted evidence needs a versioned contract: guide ID/version, source record and portion ID, preparation/part/size convention, count, source grams per count unit, calculated total, and any user-entered total with its explicitly selected basis (user-reported measured or user-entered estimate). A direct measured-weight entry may have no guide metadata. Preserve historical guides so a saved entry remains reproducible after updates. An estimated quantity must not become a measured quantity because its nutrient record is authoritative.

## Required contract and UI cases

- Exact supported record/part/preparation matches; unsupported and cross-source matches abstain.
- US and UK size conventions cannot substitute silently.
- Whole eggs, whites and yolks remain distinct; raw guides cannot populate cooked foods.
- Reject cup/serving descriptors in piece menus; absent size choices remain absent.
- Two supported large eggs calculate count × source weight; shell-inclusive input is not accepted as edible weight by inference.
- Invalid/non-finite quantities cannot save; fractional-count behaviour follows the existing quantity contract rather than a new implicit rule.
- Food changes invalidate stale estimates; count edits preserve deliberate manual totals unless the user returns to estimates.
- Direct user-reported measured grams work without a guide or size selection and take precedence over count estimates.
- Save/reopen preserves guide version, entered weight and quantity basis; old records remain reproducible.
- Unknown nutrition fields remain unknown; manual quantities do not change candidate provenance.
- UI presents the missing weight beside the field, exposes a clear recovery action, and remains usable with VoiceOver and larger text.

These are proposed development tests, not independent device acceptance. Implementation would require package tests, the complete simulator suite once stable, Xcode analysis, and separate device validation. This documentation-only phase does not justify those app builds.

## Admission decision still required

Choose between an explicitly labelled USDA guide on compatible USDA records, or a UK guide using the historical report after visual verification, source admission and catalogue mapping. A full UK small/medium/large menu is not supported by the evidence inspected. Further foods require their own admitted record-level guides; do not generalise the egg calculation.
