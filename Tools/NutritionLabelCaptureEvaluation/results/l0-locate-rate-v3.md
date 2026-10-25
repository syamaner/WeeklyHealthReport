# L0 locate rate v3: locator v2 and the attention policy (L1c, #316)

Status: **offline measurement, 25 October 2026. No model, provider or network call.** It repeats [v2](l0-locate-rate-v2.md) (locator v1) with locator v2 (`label-photo-vision-locate-v2`, [spec 17.11](../../../docs/label-photo-ai-prefill-v1.md)) at the decided 240 px minimum, and measures an alternative attention policy for the owner. Inputs, preparation, recognition, truth and the attention draft rules are unchanged. Counts and case IDs only: [`l0-locate-rate-v3.json`](l0-locate-rate-v3.json), written by [`../l0_locate.py`](../l0_locate.py).

These counts are for locator v2 as pinned after round 6 of the #321 review ([spec 17.14](../../../docs/label-photo-ai-prefill-v1.md)): recovery locates but never confirms, and with two or more columns a value is confirmed only when every one of the reading's headers is located in the header band, in order, with its own header directly above it (the value's centre within the header's span, or the header's centre within the value's) and one value token in its cell. They replace the earlier v2 runs (61.2%, 60.0%, then 52.4% for Gemini), each of which could confirm a wrong reading after one model error.

## Untouched Taiwan, 240 px, current blocking policy

| | Gemini 4 Argon | GPT-6.1 Sol | Luna |
|---|---|---|---|
| Pre-filled tables | 34 | 35 | 37 |
| Correct values | 557 | 564 | 566 |
| found | 207 (37.2%) | 214 (37.9%) | 214 (37.8%) |
| not found | 70 | 89 | 67 |
| ambiguous | 280 | 261 | 285 |
| Ambiguous values (all) with a located region | 129 of 281 | 128 of 263 | 127 of 308 |
| Silent wrong values / needing a check | 4 / 4 | 4 / 4 | 52 / 52 |
| Silent-error tables / fully caught | 2 / 1 | 3 / 3 | 5 / 4 |
| Tables with no attention item | 3 | 3 | 3 |
| Attention items per table, median / p90 | 14 / 18 | 14 / 18 | 13 / 19 |
| Serving lines found | 39 / 68 | 41 / 70 | 42 / 72 |

Locator v1 on the same photos (v2 results): 42.2%, 42.7%, 42.8% found; medians 11, 10, 10.

## Alternative policy (measured, not adopted): only items with evidence block

| | Gemini 4 Argon | GPT-6.1 Sol | Luna |
|---|---|---|---|
| Blocking items per table, median / p90 | 0 / 1 | 0 / 2 | 0 / 3 |
| Tables with no blocking item | 28 | 27 | 28 |
| Silent wrong values still blocking | 0 of 4 | 2 of 4 | 6 of 52 |
| Silent-error tables fully blocked | 0 of 2 | 2 of 3 | 0 of 5 |

## Development Taiwan, 240 px (15 photos)

| | Gemini 4 Argon | GPT-6.1 Sol | Luna |
|---|---|---|---|
| Correct values found | 132 / 238 (55.5%) | 132 / 237 (55.7%) | 130 / 229 (56.8%) |
| Attention items per table, median / p90 | 8 / 14 | 8 / 14 | 8 / 14 |
| Alternative policy: blocking median / p90 | 0 / 4 | 0 / 4 | 0 / 5 |
| Alternative policy: silent wrong values still blocking | 0 of 0 | 0 of 1 | 5 of 7 |

## Plain reading

- With every header required, locator v2 confirms fewer values than v1 (37% against 42%) and leaves more to check (median 14 against 11), though about 128 of its ambiguous values per arm come with a region to zoom to. The round-6 own-header test cost about two points (39.0% before it, for Gemini). v1's lower bar is what the review rounds showed to be unsafe.
- Every silent wrong value of every arm still needs a check.
- The likely blocker (not yet measured case by case) is the reference-intake column's header, often printed over two lines; spec 17.14 proposes confirming that column by its % unit instead.
- Limits are those of v1 and v2: public crowd-sourced photos, one Mac and Vision revision, truth with an unknown per-cell error rate, and user behaviour unmeasured.
