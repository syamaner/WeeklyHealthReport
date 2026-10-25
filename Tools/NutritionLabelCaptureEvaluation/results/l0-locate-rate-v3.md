# L0 locate rate v3: locator v2 and the attention policy (L1c, #316)

Status: **offline measurement, 25 October 2026. No model, provider or network call.** It repeats [v2](l0-locate-rate-v2.md) (locator v1) with locator v2 (`label-photo-vision-locate-v2`, [spec 17.11](../../../docs/label-photo-ai-prefill-v1.md)) at the decided 240 px minimum, and measures an alternative attention policy for the owner. Inputs, preparation, recognition, truth and the attention draft rules are unchanged. Counts and case IDs only: [`l0-locate-rate-v3.json`](l0-locate-rate-v3.json), written by [`../l0_locate.py`](../l0_locate.py).

These counts are for locator v2 as pinned after the #321 re-check ([spec 17.13](../../../docs/label-photo-ai-prefill-v1.md)): recovery locates but never confirms, headers count only in the header band, and found needs the value's own header. They replace the earlier v2 runs (61.2%, then 60.0% for Gemini), which could confirm a wrong reading after one model error.

## Untouched Taiwan, 240 px, current blocking policy

| | Gemini 4 Argon | GPT-6.1 Sol | Luna |
|---|---|---|---|
| Pre-filled tables | 34 | 35 | 37 |
| Correct values | 557 | 564 | 566 |
| found | 292 (52.4%) | 298 (52.8%) | 299 (52.8%) |
| not found | 70 | 89 | 67 |
| ambiguous | 195 | 177 | 200 |
| Ambiguous values (all) with a located region | 44 of 196 | 44 of 179 | 42 of 223 |
| Silent wrong values / needing a check | 4 / 4 | 4 / 4 | 52 / 52 |
| Silent-error tables / fully caught | 2 / 1 | 3 / 3 | 5 / 4 |
| Tables with no attention item | 3 | 3 | 3 |
| Attention items per table, median / p90 | 7 / 18 | 8 / 17 | 8 / 18 |
| Serving lines found | 39 / 68 | 41 / 70 | 42 / 72 |

Locator v1 on the same photos (v2 results): 42.2%, 42.7%, 42.8% found; medians 11, 10, 10.

## Alternative policy (measured, not adopted): only items with evidence block

| | Gemini 4 Argon | GPT-6.1 Sol | Luna |
|---|---|---|---|
| Blocking items per table, median / p90 | 0 / 1 | 0 / 2 | 0 / 3 |
| Tables with no blocking item | 27 | 26 | 27 |
| Silent wrong values still blocking | 0 of 4 | 2 of 4 | 6 of 52 |
| Silent-error tables fully blocked | 0 of 2 | 2 of 3 | 0 of 5 |

Blocking here means a gate flag, a failed check, or the photo contradicting the value on a row whose own label is located and a column separated by located headers. Every other attention item becomes a soft marker covered by one table-level confirmation.

## Development Taiwan, 240 px (15 photos)

| | Gemini 4 Argon | GPT-6.1 Sol | Luna |
|---|---|---|---|
| Correct values found | 154 / 238 (64.7%) | 154 / 237 (65.0%) | 152 / 229 (66.4%) |
| Attention items per table, median / p90 | 6 / 14 | 6 / 14 | 5 / 14 |
| Alternative policy: blocking median / p90 | 0 / 4 | 0 / 4 | 0 / 5 |
| Alternative policy: silent wrong values still blocking | 0 of 0 | 0 of 1 | 5 of 7 |

## Plain reading

- Locator v2 lifts the found rate from 42% to 52% with every silent wrong value still needing a check; the attention median falls from 11 to 7 (Gemini).
- Most of the remaining ambiguity is a column whose own header was not read in the header band; 44 such values per arm come with a located region to zoom to.
- The alternative policy removes nearly all blocking, but it would leave every one of Gemini's silent wrong values, 2 of Sol's and 46 of Luna's resting on the table-level confirmation.
- Limits are those of v1 and v2: public crowd-sourced photos, one Mac and Vision revision, truth with an unknown per-cell error rate, and user behaviour unmeasured.
