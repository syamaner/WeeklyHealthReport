# L0 locate rate v4: locator v3, header bases (L1d, #316)

Status: **offline measurement, 25 October 2026. No model, provider or network call.** This run repeats [v3](l0-locate-rate-v3.md) (locator v2 as pinned in #321 after round 6) with locator v3 (`label-photo-vision-locate-v3`, [spec 17.15](../../../docs/label-photo-ai-prefill-v1.md)). The minimum short edge is still 240 px.

Inputs, preparation, recognition, truth and the attention rules are unchanged from v3. The one input difference is that each job now passes every header of the reading, including those with no printed text, together with its basis (amount or reference intake). Counts and case IDs only are in [`l0-locate-rate-v4.json`](l0-locate-rate-v4.json), written by [`../l0_locate.py`](../l0_locate.py).

Locator v3 keeps every v2 rule, including round 6's own-header span and one token per cell, and relaxes the header rule in one place:
- **Amount headers.** Only the amount columns' headers (per serving, per 100 g or ml) must be located in the header band, in order.
- **Reference-intake values.** A reference-intake value is confirmed by its % unit and by its position beside the amount columns, never as an amount column.
- **Amount values.** An amount value is never confirmed with a % unit.
- **Unlocated headers.** When a header is not located, a row may hold no more value tokens than the reading has columns.
- **D4.** A per-serving header printed with its serving quantity in brackets now counts as a header line.

## Untouched Taiwan, 240 px, current blocking policy

| | Gemini 4 Argon | GPT-6.1 Sol | Luna |
|---|---|---|---|
| Pre-filled tables | 34 | 35 | 37 |
| Correct values | 557 | 564 | 566 |
| found | 243 (43.6%) | 250 (44.3%) | 248 (43.8%) |
| not found | 70 | 89 | 67 |
| ambiguous | 244 | 225 | 251 |
| Ambiguous values (all) with a located region | 93 of 245 | 92 of 227 | 93 of 274 |
| Silent wrong values / needing a check | 4 / 4 | 4 / 4 | 52 / 52 |
| Silent-error tables / fully caught | 2 / 1 | 3 / 3 | 5 / 4 |
| Tables with no attention item | 5 | 5 | 5 |
| Attention items per table, median / p90 | 9.5 / 18 | 9 / 18 | 9 / 20 |
| Serving lines found | 30 / 68 | 32 / 70 | 33 / 72 |

Against locator v2 as pinned after round 6 (v3 results), the found rate rises:
- Gemini: 37.2% to 43.6%
- Sol: 37.9% to 44.3%
- Luna: 37.8% to 43.8%

The median number of values to check falls from 14, 14 and 13 to 9 for every arm.

Against v2 as it stood after round 4 (39.0% for Gemini, median 14), the rise is 4.6 points. Locator v1, which is unsafe, found 42.2%, 42.7% and 42.8%, with medians of 11, 10 and 10.

A comparison run with D4 switched off, made before the round-6 tolerance was carried over, gave the same counts as D4 on. On these photos the gain comes from the header bases. That run is not committed.

## Alternative policy (measured, not adopted): only items with evidence block

Evidence keeps v2's bar (every header located), so these counts are unchanged from v3.

| | Gemini 4 Argon | GPT-6.1 Sol | Luna |
|---|---|---|---|
| Blocking items per table, median / p90 | 0 / 1 | 0 / 2 | 0 / 3 |
| Tables with no blocking item | 28 | 27 | 28 |
| Silent wrong values still blocking | 0 of 4 | 2 of 4 | 6 of 52 |
| Silent-error tables fully blocked | 0 of 2 | 2 of 3 | 0 of 5 |

## Development Taiwan, 240 px (15 photos)

The value counts are unchanged from v3; 27 of 30 serving lines are found, against 28.

| | Gemini 4 Argon | GPT-6.1 Sol | Luna |
|---|---|---|---|
| Correct values found | 132 / 238 (55.5%) | 132 / 237 (55.7%) | 130 / 229 (56.8%) |
| Attention items per table, median / p90 | 8 / 15 | 8 / 15 | 8 / 14 |

## Plain reading

- Locator v3 confirms more values than v2 as pinned and more than v1: Gemini 43.6%, against 37.2% for v2 and 42.2% for v1. It leaves a median of 9 values to check, against 14 and 11.
- It keeps clean every attack scenario of the #321 rounds (A to E, run with no bases, with bases named from the header text, and with the last column forced to reference intake). It also adds scenarios of its own:
  - % and amount columns mislabelled, in either direction;
  - an amount header missing;
  - a % value with a matching amount-like number;
  - an omitted column;
  - a narrow column touching an amount column;
  - bracketed quantities that do not match the serving size.
- Every silent wrong value of every arm still needs a check, as with v2.
- After round 1 of the #322 review, a serving line matched by its quantity alone counts only outside the table and with its own words beside it (G1). After round 2, the words must sit directly beside the quantity (H1), and fewer again are found (30, 32 and 33 after round 3, against 39, 41 and 42 before round 1); the value counts do not change.
- Fewer ambiguous values come with a region (93 against 129). That fits values that had a region now being found, but it has not been checked case by case.
- The limits are those of v1 to v3:
  - public crowd-sourced photos;
  - one Mac and one Vision revision;
  - truth with an unknown per-cell error rate;
  - user behaviour not measured.
