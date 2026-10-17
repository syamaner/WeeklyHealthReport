# Route B on development photos (phase 2, #255)

Run on 17 October 2026 through Inspect AI (`mockllm/model` as the nominal model; no model or network call), with:

- **Recogniser:** `vision_v3.swift` (`label-capture-vision-v3`), `VNRecognizeTextRequest` revision 3, accurate, recognition languages `zh-Hant` and `en-US`, language correction on (inherited from the frozen v1 adapter), macOS 27.0.1 (26A434). `en-GB` was requested but is not advertised by this Vision revision, so it is not used; `en-US` is recorded, not represented as British-English support.
- **Serialiser:** `serialise_lines.py` (`label-capture-serialiser-v1`): binding by column header and order within a column, header-row skew correction, two-line headers joined, footnote headers dropped, unbound values emitted so the parser declines.
- **Parser:** the shared `NutritionLabelParsing` (`nutrition-label-text-parser-v1`) through `NutritionLabelTextParse` with route `B`.

Machine-readable summary, per-case outcome flags and serialiser counts: [`route-b-development-v1.json`](route-b-development-v1.json). The Inspect log (recognised lines and serialised text) is outside the repository.

**This is a development result, not evidence for promotion.** Every image here is exposed development material, the serialiser was tuned on these same images, and a Mac run proves software behaviour only.

## Corpus actually run

| Stratum | Cases run | Recorded but not run |
|---|---:|---|
| Taiwan `zh-Hant` (Open Food Facts development photos) | 20 (orders 1 to 20 less 4 and 17, plus refills 61 and 62) | Orders 4 and 17: English-only labels, excluded |
| UK `en` (v2 public development review images) | 39 | 1 panel the owner excluded in that review |
| Muesli (owner photo) | 0 | Not run: its consent record has `local_routes` false |

The plan's UK development set (40 v1 gate images and 60 v2 tuning images) could not be used: the v1 panel images are no longer on disk and the v2 public selection was never acquired. The UK stratum here is the 40 exposed v2 public development review images that are on disk, with their frozen, owner-verified review. That review records no servings-per-pack or serving-size line, so those are not scored for UK cases. No UK image was downloaded. UK untouched set deferred by the owner on 17 Oct 2026; acquire a fresh sealed UK set only if Taiwan results justify it. Until then no promotion decision for UK label photos.

Taiwan truth is the Claude-drafted first pass (`first_pass_unverified`), awaiting the owner's second pass.

## Results against the pass bars

| Metric | Bar | Taiwan `zh-Hant` | UK `en` |
|---|---|---|---|
| Strict numeric-cell exact | ≥ 95% | 84 / 214 (39.3%) **fail** | 9 / 311 (2.9%) **fail** |
| Row / header binding | ≥ 98% | 95 / 238 (39.9%) **fail** | 9 / 325 (2.8%) **fail** |
| Unit and basis | 100% | 94 / 214 (43.9%) **fail** | 13 / 311 (4.2%) **fail** |
| Full-table exact | ≥ 75% | 3 / 15 (20.0%) **fail** | 1 / 22 (4.5%) **fail** |
| Serving conversions exact | ≥ 98% | 55 / 123 (44.7%) **fail** | 0 / 116 (0%) **fail** |
| Servings per pack exact | ≥ 98% | 7 / 15 (46.7%) **fail** | no denominator (not recorded) |
| Printed bounds preserved | 100% | no denominator | 0 / 11 (0%) **fail** |
| Correct decline | ≥ 95% | 5 / 5 **pass** | 17 / 17 **pass** |
| False-ready | 0 | **2** of 20 **fail** | 0 of 39 pass |
| Automatic persistence | 0 | 0 pass | 0 pass |
| Arithmetic mutation detection (on truth) | 100% | 20 / 21 **fail** | 10 / 13 **fail** |

Muesli: not run (no consent), so the plan's binding stress case on the real photo is unmeasured; a synthetic one-row-offset fixture in `tests/test_phase2.py` binds correctly.

False declines on usable tables: Taiwan 8 of 15, UK 20 of 22. Route B declines far more often than it misbinds, which is the intended failure direction, but it leaves very little usable output.

## Where binding fails

- **Recognition, not binding, dominates Taiwan.** Vision misreads label characters (熱量 as 鱸量, 飽和 as 飯和 or 鮑和), which become unrecognised rows that block ready; it reads some traditional characters as simplified ones (參 as 参, 營 as 营), which the parser's simplified-character guard then declines as `unsupported_language` (3 cases); and it drops whole rows or single cells (a missed 糖 or 鈉 label, a missed % cell), giving `count_mismatch` (5).
- **Column offset.** Before the serialiser was constrained, a free vertical shift chosen to bind the most values moved a whole column by one row when a label was missed (orders 3, 6, 15, 20 and 62); the parser happened to decline those. The final rule only shifts a column when it binds every value one-to-one and agrees with a complete neighbouring column (or there is no complete neighbour), so a missed label now surfaces as a count mismatch.
- **UK panels** fail mostly before binding: tilted and perspective photos (fixed partly by header-row deskew), headers printed over two lines (`Per` above `100g`), energy rows with stacked or slashed kJ and kcal, labels with the unit in the label (`Energy kJ`, which the parser's vocabulary does not recognise: `value_without_unit`, 6), bilingual or multi-panel packs (`multiple_panels`, 3; `unsupported_language`, 2) and footnotes or reference-intake tables inside the crop (`no_basis_header`, 5).
- **Both false-ready tables are Taiwan recognition errors the policy cannot see:** one misread digit (55.6 read as 55.3 in a sugars cell) with the servings-per-pack line missed, and one table where Vision missed a 0% reference-intake cell. The parser allows a row without a percentage (trans fat and sugars often have none), so the missing cell does not block ready, and the arithmetic check cannot detect either error.

## Limits

These are repeated from plan section 3.5 and apply here: Chinese photo coverage is development-only and anecdotal; the UK stratum is exposed development material with no untouched counterpart; the images are crowd-sourced uploads, not this app's captures; and route B on any device still needs the owner's physical-device spot check before any promotion.
