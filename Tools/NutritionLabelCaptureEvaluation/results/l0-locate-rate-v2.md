# L0 locate rate v2 (label photo AI pre-fill L1a, #316)

Status: **offline measurement, 25 October 2026. No model, provider or network call.** It repeats [v1](l0-locate-rate-v1.md) with the L1a matcher pinned in the package (`Sources/FoodLabelPhotoReading/LabelValueMatcher.swift`, SHA-256 `b2498fbf…`: headers by containment, a row distance limit of 1/3 of the label spacing, an unlisted-column rule, and an order pass that only resolves ambiguous values under the conditions of [spec 6.1 step 6 and 17.10](../../../docs/label-photo-ai-prefill-v1.md)) and the decided 240 px short-edge minimum (P5). Inputs, preparation otherwise, recognition, truth and attention draft rules are unchanged from v1. Counts and case IDs only: [`l0-locate-rate-v2.json`](l0-locate-rate-v2.json), written by [`../l0_locate.py`](../l0_locate.py).

These counts replace two earlier v2 runs that are not kept: 81.7% for Gemini 4 Argon with an order pass the #320 invariant review blocked, and 81.0% before the re-check added the row distance limit. Both could find a value on a row it may not belong to.

## Untouched Taiwan, 240 px

| | Gemini 4 Argon | GPT-6.1 Sol | Luna |
|---|---|---|---|
| Photos refused (short edge under 240 px) | 3 | 3 | 3 |
| Pre-filled tables | 34 | 35 | 37 |
| Correct values | 557 | 564 | 566 |
| found | 410 (73.6%) | 394 (69.9%) | 419 (74.0%) |
| not found | 67 | 82 | 59 |
| ambiguous | 80 | 88 | 88 |
| Wrong values (all silent) | 4 | 4 | 52 |
| silent, attention by the locator | 4 | 2 | 39 |
| silent, attention by the locator or a check | 4 | 2 | 40 |
| Silent-error tables / fully caught | 2 / 1 | 3 / 2 | 5 / 2 |
| Tables with no attention item | 5 | 4 | 5 |
| Attention items per table, median / p90 | 5 / 12 | 5 / 12 | 5 / 14 |
| Serving lines found | 49 / 68 | 51 / 70 | 51 / 72 |

## Comparison: untouched, 480 px (the v1 photo set) with the v2 matcher

| | Gemini 4 Argon | GPT-6.1 Sol | Luna |
|---|---|---|---|
| Pre-filled tables | 29 | 30 | 32 |
| Correct values found | 349 / 479 (72.9%) | 334 / 487 (68.6%) | 363 / 505 (71.9%) |
| Tables with no attention item | 4 | 4 | 4 |
| Attention items per table, median / p90 | 5 / 12 | 5 / 12 | 5.5 / 14 |

v1 on the same photos found 74.3%, 70.8% and 74.3%, with 3 tables clear in each arm and a median of 3.

## Development Taiwan, 240 px (15 photos, none refused)

| | Gemini 4 Argon | GPT-6.1 Sol | Luna |
|---|---|---|---|
| Correct values found | 196 / 238 (82.4%) | 196 / 237 (82.7%) | 192 / 229 (83.8%) |
| Silent wrong values / caught | 0 / 0 | 1 / 0 | 7 / 4 |
| Tables with no attention item | 5 | 6 | 6 |
| Attention items per table, median / p90 | 1 / 10 | 1 / 10 | 1 / 10 |

## Plain reading

- The row distance limit makes the locator stricter: about as many values are found as in v1 (73.6% against 74.3%), but none can be found on a row it may not belong to, and ambiguous values rise to 80.
- For Gemini 4 Argon every silent wrong value is still an attention item; the table that stays partly silent has a wrong serving line found on the photo. Luna, the weakest arm, now has 40 of 52 silent wrong values flagged (32 before the limit).
- The attention burden is a median of 5 per table, and about one table in seven opens clear.
- Limits are those of v1: public crowd-sourced photos, one Mac and Vision revision, truth with an unknown per-cell error rate, and user behaviour unmeasured.
