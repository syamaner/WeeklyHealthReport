# L0 locate rate (label photo AI pre-fill, #316)

Status: **offline measurement, 25 October 2026. No model, provider or network call.** Phase L0 of [label photo AI pre-fill v1](../../../docs/label-photo-ai-prefill-v1.md) (sections 6.1, 17.6 and 17.9). Machine-readable counts and case IDs only: [`l0-locate-rate-v1.json`](l0-locate-rate-v1.json), written by [`../l0_locate.py`](../l0_locate.py).

## Method

- **Answers:** the saved route C outputs of the untouched Taiwan run (40 photos; Gemini 4 Argon reasoning on, GPT-6.1 Sol reasoning on, GPT-6 Luna reasoning off) and the 15 usable Taiwan development photos, as `correction_effort.py` loads them, in its **assisted** view (the product design: only the route's own decline, a failed output, G1 and G2 decline).
- **Photos:** the public Open Food Facts Taiwan photos in the private evaluation folder, matched to each case by SHA-256 and used uncropped (they are panel photos already).
- **Preparation (E3):** orientation applied to pixels, sRGB, long edge at most 2,048 px and at most 3.2 MP, JPEG 0.85 (then 0.75, 0.65) with no metadata dictionary, at most 1,500,000 bytes, short edge at least 480 px. Every accepted photo encoded at 0.85; the largest was 2,048 px.
- **Recognition:** Apple Vision on this Mac (macOS 27.0.1), `VNRecognizeTextRequest` revision 3, accurate, `zh-Hant` and `en-US`, language correction off, on the prepared JPEG bytes. The stored route B outputs carry no per-substring geometry, so Vision was re-run locally.
- **Matcher:** the Swift `LabelValueMatcher` in [`Tools/LabelPhotoLocateL0`](../../LabelPhotoLocateL0) (`label-photo-vision-locate-v1`), the file L1 carries into the package; 11 synthetic unit tests.
- **Correct and wrong** values use the correction-effort matching against the frozen, corrected untouched truth (with its anchoring caveat). A **silent** wrong value is one no gate flag marks.
- **Attention (draft rules):** a value or serving line not found or ambiguous; a value a failed arithmetic or consistency check implicates (energy against its macronutrients, kJ against kcal, per serving against per 100, a sub-row above its parent); a G3 or G4 flagged row.

## Untouched Taiwan (E3 as specified)

| | Gemini 4 Argon | GPT-6.1 Sol | Luna |
|---|---|---|---|
| Photos refused (short edge under 480 px) | 8 | 8 | 8 |
| Pre-filled tables | 29 | 30 | 32 |
| Correct values | 479 | 487 | 505 |
| found | 356 (74.3%) | 345 (70.8%) | 375 (74.3%) |
| not found | 54 | 69 | 57 |
| ambiguous | 69 | 73 | 73 |
| Wrong values (all silent) | 4 | 3 | 44 |
| silent, attention by the locator | 4 | 1 | 26 |
| silent, attention by the locator or a check | 4 | 1 | 29 |
| Silent-error tables | 2 | 2 | 4 |
| fully caught | 1 | 1 | 2 |
| Tables with no attention item | 3 | 3 | 3 |
| Attention items per table, median / p90 | 3 / 13 | 3 / 13 | 3.5 / 15 |
| Serving lines found | 40 / 58 | 42 / 60 | 44 / 64 |

## Sensitivity: untouched, short-edge minimum lifted

| | Gemini 4 Argon | GPT-6.1 Sol | Luna |
|---|---|---|---|
| Pre-filled tables | 37 | 38 | 40 |
| Correct values found | 443 / 603 (73.5%) | 431 / 610 (70.7%) | 453 / 597 (75.9%) |
| Silent wrong values / attention by locator or check | 4 / 4 | 4 / 2 | 67 / 46 |
| Silent-error tables / fully caught | 2 / 1 | 3 / 2 | 7 / 3 |
| Tables with no attention item | 4 | 4 | 4 |
| Attention items per table, median / p90 | 3 / 12 | 4 / 13 | 3.5 / 14 |

## Development Taiwan (15 photos, 3 refused by the minimum)

All three arms: 12 pre-filled tables, 145 of 193 or 194 correct values found (74.7% to 75.1%), 24 of 24 serving lines found, 1 table with no attention item, attention median 2 and p90 10 or 11. Gemini made no wrong value; Sol and Luna one silent wrong value each, not caught.

## Plain reading

- About three in four correct values are found on the photo; the rest are not found (11 to 14%) or ambiguous (14 to 15%), mostly repeated values such as 0公克 where a row label was not read exactly once.
- For Gemini 4 Argon, the arm the contract chose, every silent wrong value became an attention item; one of its two silent-error tables also had a wrong serving line that was found on the photo, so that table is not fully caught.
- The attention burden is real: a median of 3 items and a p90 of 13 per table, and about 1 table in 10 opens with none.
- The 480 px minimum refuses 8 of 40 public photos (small crowd-sourced crops). Gemini read those 8 with no silent error.
- Limits: public crowd-sourced photos, not this app's captures; one Mac and one Vision revision; truth with an unknown per-cell error rate; whether users resolve attention items carefully is not measured.
