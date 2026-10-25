# L0 locate rate v2 (label photo AI pre-fill L1a, #316)

Status: **offline measurement, 25 October 2026. No model, provider or network call.** It repeats [v1](l0-locate-rate-v1.md) with the L1a matcher pinned in the package (`Sources/FoodLabelPhotoReading/LabelValueMatcher.swift`, SHA-256 `ea1ab9c9…`: headers by containment, values compared as tokens (comparator, sign, number with separators, unit), the number alone only with the model's unit read beside it, no found value without a unit, a row distance limit of 1/3 of the label spacing, an unlisted-column rule, no found value without its own located row label or, with more than one column, its own located header, and an order pass that only resolves ambiguous values under the conditions of [spec 6.1 step 6 and 17.10](../../../docs/label-photo-ai-prefill-v1.md)) and the decided 240 px short-edge minimum (P5). Inputs, preparation otherwise, recognition, truth and attention draft rules are unchanged from v1. Counts and case IDs only: [`l0-locate-rate-v2.json`](l0-locate-rate-v2.json), written by [`../l0_locate.py`](../l0_locate.py).

These counts replace four earlier v2 runs that are not kept: 81.7% for Gemini 4 Argon with an order pass the #320 invariant review blocked, 81.0% before the row distance limit, 73.6% before the rule for an unlocated own row label, and 61.8% before values were compared as tokens. Each could find a value it should not.

## Untouched Taiwan, 240 px

| | Gemini 4 Argon | GPT-6.1 Sol | Luna |
|---|---|---|---|
| Photos refused (short edge under 240 px) | 3 | 3 | 3 |
| Pre-filled tables | 34 | 35 | 37 |
| Correct values | 557 | 564 | 566 |
| found | 235 (42.2%) | 241 (42.7%) | 242 (42.8%) |
| not found | 76 | 95 | 69 |
| ambiguous | 246 | 228 | 255 |
| Wrong values (all silent) | 4 | 4 | 52 |
| silent, attention by the locator | 4 | 4 | 52 |
| silent, attention by the locator or a check | 4 | 4 | 52 |
| Silent-error tables / fully caught | 2 / 1 | 3 / 3 | 5 / 4 |
| Tables with no attention item | 1 | 1 | 1 |
| Attention items per table, median / p90 | 11 / 17 | 10 / 17 | 10 / 20 |
| Serving lines found | 39 / 68 | 41 / 70 | 42 / 72 |

## Comparison: untouched, 480 px (the v1 photo set) with the v2 matcher

| | Gemini 4 Argon | GPT-6.1 Sol | Luna |
|---|---|---|---|
| Pre-filled tables | 29 | 30 | 32 |
| Correct values found | 197 / 479 (41.1%) | 204 / 487 (41.9%) | 204 / 505 (40.4%) |
| Tables with no attention item | 1 | 1 | 1 |
| Attention items per table, median / p90 | 10 / 20 | 9.5 / 17 | 11 / 20 |

v1 on the same photos found 74.3%, 70.8% and 74.3%, with 3 tables clear in each arm and a median of 3.

## Development Taiwan, 240 px (15 photos, none refused)

| | Gemini 4 Argon | GPT-6.1 Sol | Luna |
|---|---|---|---|
| Correct values found | 133 / 238 (55.9%) | 133 / 237 (56.1%) | 131 / 229 (57.2%) |
| Silent wrong values / caught | 0 / 0 | 1 / 0 | 7 / 5 |
| Tables with no attention item | 2 | 2 | 2 |
| Attention items per table, median / p90 | 8 / 14 | 8 / 14 | 8 / 14 |

## Plain reading

- The v2 locator is a strict corroborator: a value is found only where the same comparator, number and unit are printed on its own located row, within a third of the label spacing, under its own located header when the table has more than one column. About 42% of correct values meet that on these photos.
- Ambiguous values are most of the remainder (246 for Gemini). A comparison run (not committed) shows the header rule alone accounts for 81 of them: the two column headers are often not located exactly once on these crowd-sourced photos.
- Every silent wrong value of every arm is now an attention item except one wrong serving line (Gemini) and one Luna table.
- The attention burden is a median of 11 per table, with one table in 34 opening clear. Recovering found values safely is phase L1c (locator v2).
- Limits are those of v1: public crowd-sourced photos, one Mac and Vision revision, truth with an unknown per-cell error rate, and user behaviour unmeasured.
