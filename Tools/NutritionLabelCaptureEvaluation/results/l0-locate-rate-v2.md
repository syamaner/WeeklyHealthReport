# L0 locate rate v2 (label photo AI pre-fill L1a, #316)

Status: **offline measurement, 25 October 2026. No model, provider or network call.** It repeats [v1](l0-locate-rate-v1.md) with the L1a matcher pinned in the package (`Sources/FoodLabelPhotoReading/LabelValueMatcher.swift`, SHA-256 `51837a1c…`: headers by containment, and an order pass that only resolves ambiguous values under the conditions of [spec 6.1 step 6 and 17.10](../../../docs/label-photo-ai-prefill-v1.md)) and the decided 240 px short-edge minimum (P5). Inputs, preparation otherwise, recognition, truth and attention draft rules are unchanged from v1. Counts and case IDs only: [`l0-locate-rate-v2.json`](l0-locate-rate-v2.json), written by [`../l0_locate.py`](../l0_locate.py).

These counts replace an earlier v2 run (81.7% for Gemini 4 Argon) made with an order pass that the #320 invariant review blocked because it could place a wrong value on another row; that run is not kept.

## Untouched Taiwan, 240 px

| | Gemini 4 Argon | GPT-6.1 Sol | Luna |
|---|---|---|---|
| Photos refused (short edge under 240 px) | 3 | 3 | 3 |
| Pre-filled tables | 34 | 35 | 37 |
| Correct values | 557 | 564 | 566 |
| found | 451 (81.0%) | 439 (77.8%) | 465 (82.2%) |
| not found | 67 | 82 | 59 |
| ambiguous | 39 | 43 | 42 |
| Wrong values (all silent) | 4 | 4 | 52 |
| silent, attention by the locator | 4 | 2 | 29 |
| silent, attention by the locator or a check | 4 | 2 | 32 |
| Silent-error tables / fully caught | 2 / 1 | 3 / 2 | 5 / 2 |
| Tables with no attention item | 8 | 7 | 8 |
| Attention items per table, median / p90 | 2 / 11 | 2 / 12 | 2 / 14 |
| Serving lines found | 49 / 68 | 51 / 70 | 51 / 72 |

## Comparison: untouched, 480 px (the v1 photo set) with the v2 matcher

| | Gemini 4 Argon | GPT-6.1 Sol | Luna |
|---|---|---|---|
| Pre-filled tables | 29 | 30 | 32 |
| Correct values found | 384 / 479 (80.2%) | 373 / 487 (76.6%) | 404 / 505 (80.0%) |
| Tables with no attention item | 6 | 6 | 6 |
| Attention items per table, median / p90 | 2 / 12 | 2 / 12 | 2 / 14 |

v1 on the same photos found 74.3%, 70.8% and 74.3%, with 3 tables clear in each arm and a median of 3.

## Development Taiwan, 240 px (15 photos, none refused)

| | Gemini 4 Argon | GPT-6.1 Sol | Luna |
|---|---|---|---|
| Correct values found | 209 / 238 (87.8%) | 209 / 237 (88.2%) | 205 / 229 (89.5%) |
| Silent wrong values / caught | 0 / 0 | 1 / 0 | 7 / 4 |
| Tables with no attention item | 6 | 7 | 7 |
| Attention items per table, median / p90 | 1 / 7 | 1 / 7 | 1 / 7 |

## Plain reading

- The L1a matcher lifts the found rate from about 74% to 80% on the v1 photo set; lowering the minimum to 240 px adds 5 tables at 81.0%.
- For Gemini 4 Argon every silent wrong value is still an attention item; the table that stays partly silent has a wrong serving line found on the photo.
- The attention burden falls to a median of 2 per table, and about one table in four opens clear. Not found values (12%) are the larger remainder, mostly numbers or units that Vision misreads or splits on small photos.
- Limits are those of v1: public crowd-sourced photos, one Mac and Vision revision, truth with an unknown per-cell error rate, and user behaviour unmeasured.
