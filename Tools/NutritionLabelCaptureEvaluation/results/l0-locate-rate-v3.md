# L0 locate rate v3: locator v2 and the attention policy (L1c, #316)

Status: **offline measurement, 25 October 2026. No model, provider or network call.** It repeats [v2](l0-locate-rate-v2.md) (locator v1) with locator v2 (`label-photo-vision-locate-v2`, [spec 17.11](../../../docs/label-photo-ai-prefill-v1.md)) at the decided 240 px minimum, and measures an alternative attention policy for the owner. Inputs, preparation, recognition, truth and the attention draft rules are unchanged. Counts and case IDs only: [`l0-locate-rate-v3.json`](l0-locate-rate-v3.json), written by [`../l0_locate.py`](../l0_locate.py).

## Untouched Taiwan, 240 px, current blocking policy

| | Gemini 4 Argon | GPT-6.1 Sol | Luna |
|---|---|---|---|
| Pre-filled tables | 34 | 35 | 37 |
| Correct values | 557 | 564 | 566 |
| found | 341 (61.2%) | 347 (61.5%) | 346 (61.1%) |
| not found | 77 | 96 | 70 |
| ambiguous | 139 | 121 | 150 |
| Silent wrong values / needing a check | 4 / 4 | 4 / 4 | 52 / 52 |
| Silent-error tables / fully caught | 2 / 1 | 3 / 3 | 5 / 4 |
| Tables with no attention item | 5 | 5 | 5 |
| Attention items per table, median / p90 | 6.5 / 17 | 7 / 17 | 8 / 17 |
| Serving lines found | 39 / 68 | 41 / 70 | 42 / 72 |

Locator v1 on the same photos (v2 results): 42.2%, 42.7%, 42.8% found; medians 11, 10, 10.

## Alternative policy (measured, not adopted): only items with evidence block

| | Gemini 4 Argon | GPT-6.1 Sol | Luna |
|---|---|---|---|
| Blocking items per table, median / p90 | 0 / 2 | 0 / 2 | 0 / 5 |
| Tables with no blocking item | 22 | 21 | 22 |
| Silent wrong values still blocking | 1 of 4 | 2 of 4 | 12 of 52 |
| Silent-error tables fully blocked | 0 of 2 | 2 of 3 | 0 of 5 |

Blocking here means a gate flag, a failed check, or the photo contradicting the value (its token printed only in another row or column, or a different token in its own located cell). Every other attention item becomes a soft marker covered by one table-level confirmation.

## Development Taiwan, 240 px (15 photos)

| | Gemini 4 Argon | GPT-6.1 Sol | Luna |
|---|---|---|---|
| Correct values found | 189 / 238 (79.4%) | 189 / 237 (79.7%) | 185 / 229 (80.8%) |
| Attention items per table, median / p90 | 2 / 9 | 2 / 9 | 2 / 9 |
| Alternative policy: blocking median / p90 | 0 / 3 | 0 / 3 | 0 / 3 |
| Alternative policy: silent wrong values still blocking | 0 of 0 | 0 of 1 | 5 of 7 |

## Plain reading

- Locator v2 lifts the found rate from 42% to 61% with every silent wrong value still needing a check; the attention median falls from 11 to 6.5 (Gemini).
- The alternative policy removes nearly all blocking, but most silent wrong values would then rest only on the table-level confirmation (3 of Gemini's 4, 2 of Sol's 4, 40 of Luna's 52).
- Limits are those of v1 and v2: public crowd-sourced photos, one Mac and Vision revision, truth with an unknown per-cell error rate, and user behaviour unmeasured.
