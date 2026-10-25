# L0 locate rate v3: locator v2 and the attention policy (L1c, #316)

Status: **offline measurement, 25 October 2026. No model, provider or network call.** It repeats [v2](l0-locate-rate-v2.md) (locator v1) with locator v2 (`label-photo-vision-locate-v2`, [spec 17.11](../../../docs/label-photo-ai-prefill-v1.md)) at the decided 240 px minimum, and measures an alternative attention policy for the owner. Inputs, preparation, recognition, truth and the attention draft rules are unchanged. Counts and case IDs only: [`l0-locate-rate-v3.json`](l0-locate-rate-v3.json), written by [`../l0_locate.py`](../l0_locate.py).

These counts are for locator v2 as pinned after the #321 review ([spec 17.12](../../../docs/label-photo-ai-prefill-v1.md)): recovery locates but never confirms. They replace the first v2 run (61.2% for Gemini), which could confirm a wrong reading after one model error.

## Untouched Taiwan, 240 px, current blocking policy

| | Gemini 4 Argon | GPT-6.1 Sol | Luna |
|---|---|---|---|
| Pre-filled tables | 34 | 35 | 37 |
| Correct values | 557 | 564 | 566 |
| found | 334 (60.0%) | 340 (60.3%) | 339 (59.9%) |
| not found | 74 | 93 | 67 |
| ambiguous | 149 | 131 | 160 |
| Ambiguous values (all) with a located region | 10 of 150 | 10 of 133 | 10 of 183 |
| Silent wrong values / needing a check | 4 / 4 | 4 / 4 | 52 / 52 |
| Silent-error tables / fully caught | 2 / 1 | 3 / 3 | 5 / 4 |
| Tables with no attention item | 5 | 5 | 5 |
| Attention items per table, median / p90 | 6.5 / 17 | 7 / 17 | 8 / 18 |
| Serving lines found | 39 / 68 | 41 / 70 | 42 / 72 |

Locator v1 on the same photos (v2 results): 42.2%, 42.7%, 42.8% found; medians 11, 10, 10.

## Alternative policy (measured, not adopted): only items with evidence block

| | Gemini 4 Argon | GPT-6.1 Sol | Luna |
|---|---|---|---|
| Blocking items per table, median / p90 | 0 / 2 | 0 / 2 | 0 / 5 |
| Tables with no blocking item | 26 | 24 | 25 |
| Silent wrong values still blocking | 0 of 4 | 2 of 4 | 6 of 52 |
| Silent-error tables fully blocked | 0 of 2 | 2 of 3 | 0 of 5 |

Blocking here means a gate flag, a failed check, or the photo contradicting the value on a row whose own label is located and a column separated by located headers. Every other attention item becomes a soft marker covered by one table-level confirmation.

## Development Taiwan, 240 px (15 photos)

| | Gemini 4 Argon | GPT-6.1 Sol | Luna |
|---|---|---|---|
| Correct values found | 179 / 238 (75.2%) | 179 / 237 (75.5%) | 175 / 229 (76.4%) |
| Attention items per table, median / p90 | 2 / 9 | 2 / 9 | 2 / 9 |
| Alternative policy: blocking median / p90 | 0 / 3 | 0 / 3 | 0 / 3 |
| Alternative policy: silent wrong values still blocking | 0 of 0 | 0 of 1 | 5 of 7 |

## Plain reading

- Locator v2 lifts the found rate from 42% to 60% with every silent wrong value still needing a check; the attention median falls from 11 to 6.5 (Gemini).
- Recovery only locates now; on these photos it seldom leaves a single located candidate (10 ambiguous values per arm come with a region).
- The alternative policy removes nearly all blocking, but it would leave every one of Gemini's silent wrong values, 2 of Sol's and 46 of Luna's resting on the table-level confirmation.
- Limits are those of v1 and v2: public crowd-sourced photos, one Mac and Vision revision, truth with an unknown per-cell error rate, and user behaviour unmeasured.
