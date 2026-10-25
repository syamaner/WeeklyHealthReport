# L0 locate rate v2 (label photo AI pre-fill L1a, #316)

Status: **offline measurement, 25 October 2026. No model, provider or network call.** It repeats [v1](l0-locate-rate-v1.md) with the L1a matcher pinned in the package (`Sources/FoodLabelPhotoReading/LabelValueMatcher.swift`, SHA-256 `db15fba7…`: headers by containment, a row distance limit of 1/3 of the label spacing, an unlisted-column rule, no found value without its own located row label, and an order pass that only resolves ambiguous values under the conditions of [spec 6.1 step 6 and 17.10](../../../docs/label-photo-ai-prefill-v1.md)) and the decided 240 px short-edge minimum (P5). Inputs, preparation otherwise, recognition, truth and attention draft rules are unchanged from v1. Counts and case IDs only: [`l0-locate-rate-v2.json`](l0-locate-rate-v2.json), written by [`../l0_locate.py`](../l0_locate.py).

These counts replace three earlier v2 runs that are not kept: 81.7% for Gemini 4 Argon with an order pass the #320 invariant review blocked, 81.0% before the row distance limit, and 73.6% before the rule for an unlocated own row label. Each could find a value on a row it may not belong to.

## Untouched Taiwan, 240 px

| | Gemini 4 Argon | GPT-6.1 Sol | Luna |
|---|---|---|---|
| Photos refused (short edge under 240 px) | 3 | 3 | 3 |
| Pre-filled tables | 34 | 35 | 37 |
| Correct values | 557 | 564 | 566 |
| found | 344 (61.8%) | 329 (58.3%) | 350 (61.8%) |
| not found | 67 | 82 | 59 |
| ambiguous | 146 | 153 | 157 |
| Wrong values (all silent) | 4 | 4 | 52 |
| silent, attention by the locator | 4 | 4 | 47 |
| silent, attention by the locator or a check | 4 | 4 | 47 |
| Silent-error tables / fully caught | 2 / 1 | 3 / 3 | 5 / 3 |
| Tables with no attention item | 4 | 3 | 4 |
| Attention items per table, median / p90 | 6 / 16 | 7 / 16 | 7 / 16 |
| Serving lines found | 49 / 68 | 51 / 70 | 51 / 72 |

## Comparison: untouched, 480 px (the v1 photo set) with the v2 matcher

| | Gemini 4 Argon | GPT-6.1 Sol | Luna |
|---|---|---|---|
| Pre-filled tables | 29 | 30 | 32 |
| Correct values found | 288 / 479 (60.1%) | 274 / 487 (56.3%) | 294 / 505 (58.2%) |
| Tables with no attention item | 3 | 3 | 3 |
| Attention items per table, median / p90 | 7 / 16 | 8 / 16 | 8 / 16 |

v1 on the same photos found 74.3%, 70.8% and 74.3%, with 3 tables clear in each arm and a median of 3.

## Development Taiwan, 240 px (15 photos, none refused)

| | Gemini 4 Argon | GPT-6.1 Sol | Luna |
|---|---|---|---|
| Correct values found | 171 / 238 (71.8%) | 171 / 237 (72.2%) | 167 / 229 (72.9%) |
| Silent wrong values / caught | 0 / 0 | 1 / 0 | 7 / 4 |
| Tables with no attention item | 2 | 3 | 3 |
| Attention items per table, median / p90 | 2 / 11 | 2 / 11 | 2 / 11 |

## Plain reading

- The v2 locator is strict: a value is found only on its own located row, within a third of the label spacing, in a known column. About 62% of correct values meet that on these photos (74% in v1, which could also find values on the wrong row).
- Ambiguous values are the main remainder (146 for Gemini); the 66 added by the last rule are values whose own row label is not located exactly once on the photo.
- For Gemini 4 Argon every silent wrong value is still an attention item; the table that stays partly silent has a wrong serving line found on the photo. Sol's silent wrong values are now all flagged (4 of 4), and Luna's 47 of 52.
- The attention burden is a median of 6 per table, and about one table in nine opens clear.
- Limits are those of v1: public crowd-sourced photos, one Mac and Vision revision, truth with an unknown per-cell error rate, and user behaviour unmeasured.
