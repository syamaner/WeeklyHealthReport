# Phase 4: decline gate, offline re-score and UK diagnosis (#255)

Status: **development only, 18 October 2026.** No API call was made in this phase. Everything below comes from the saved development outputs of phases 1 to 3 (Inspect logs outside the repository), re-scored offline. The untouched Taiwan photos, the untouched truth file and the sealed set were not opened, read or run.

**Current figures:** section 8, decline gate v2 with the owner amendments and the review fixes. **Sections 2 and 3 are pre-amendment figures (gate v1, before the amendments), superseded by sections 5 and 8.** The amendments sharpen UK reading but raise UK false-ready from 28 to 61 over the ten route C arms, and route C false-ready over both strata from 49 to 83 (82 under gate v1). No arm meets the zero false-ready bar on development.

Machine-readable counts (case ids only, no model answers): [`decline-gate-rescore-v1.json`](decline-gate-rescore-v1.json) (gate v1, pre-amendment, commit f313578c), [`amendments-rescore-v1.json`](amendments-rescore-v1.json) (gate v1 with amendments, commit ac584932), [`gate-v2-rescore-v1.json`](gate-v2-rescore-v1.json) (current) and [`uk-diagnosis-v1.json`](uk-diagnosis-v1.json).

The limits of plan section 3.5 apply: these are exposed development images, the Taiwan development truth is Claude-drafted and awaits the owner's second pass, the UK stratum has no untouched counterpart, and no development number can promote a route.

## 1. The decline gate (`label-capture-decline-gate-v1`; superseded by v2, section 8)

`decline_gate.py` is a pure, route-independent gate. The Inspect solver `decline_gate_solver` runs it after every route's extraction (A, B and C, development and untouched tasks alike) and before scoring. It reads only the candidate and the label format the case declares (Taiwan 營養標示 or UK nutrition declaration, from the case's corpus or stratum). It can **decline** (every cell withheld as unknown, as plan section 6 requires of a decline) or **block ready**. It never edits, fills, converts or reorders a value, and a passing candidate is returned unchanged. Failed (schema-invalid) and already declined candidates pass through untouched. The gate is frozen in the contract (`decline_gate` block) and its source is pinned by hash.

| Rule | Action | Rule text | Reason |
|---|---|---|---|
| G1 `unsupported_script` | Decline | Any printed label, header, value or serving line holds kana, Hangul or a Simplified-only Han character | Plan section 6 limits v1 to `en` and `zh-Hant`. A Han character is Simplified-only when it is in GB 2312 (the Simplified national set) but not in CP950 (Big5, the Taiwan Traditional set); both codecs ship with Python, so there is no hand-made list. U+30FB (・) and U+30FC (ー) are punctuation in Chinese text too, so they are not counted as kana |
| G2 `not_a_food_nutrition_panel` | Decline | A header, row label or serving line names a food supplement, supplement facts, or a softgel, caplet or 錠 dose | Food supplements are exempt from the nutrition declaration of retained Regulation (EU) 1169/2011 (Article 29(1)(a)) and are labelled per daily dose under the Food Supplements (England) Regulations 2003; Taiwan capsule and tablet foods have their own labelling rule. `capsule`, 膠囊 and English `tablet` are not markers (coffee capsules, Scottish tablet) |
| G3 `required_row_missing` | Decline | A mandatory row of the declared format has no readable amount in any amount column | UK: 1169/2011 Article 30(1) and Annex XV (energy kJ and kcal, fat, saturates, carbohydrate, sugars, protein, salt). Taiwan: 包裝食品營養標示應遵行事項 (熱量, 蛋白質, 脂肪, 飽和脂肪, 反式脂肪, 碳水化合物, 糖, 鈉). A missing mandatory row means a cut-off, obscured or non-conforming table |
| G4 `column_count_mismatch` | Decline | A mandatory row has an amount in one amount column but not in another (reference-intake columns excluded) | Plan section 6 declines a count mismatch between a column's values and the row labels. Reference intake is excluded because Taiwan labels print `*` where no reference value exists |
| G5 `required_basis_missing` | Block ready | UK only: no per 100 g or per 100 ml column | 1169/2011 Article 32(2). No Taiwan column rule, because the plan's own coverage treats single-column Taiwan tables as usable |
| G6 `required_serving_declaration_missing` | Block ready | Taiwan only: no printed serving size (每一份量) or servings per pack (本包裝含…份) | Both lines are mandatory in the Taiwan format |

**Overfitting guard.** Development data motivated the gate (phase 3: false-ready tables and missed declines). The rules were written from the regulations and plan section 6 and then run once over the saved outputs; no rule, marker or threshold was added or tuned to fit a development case. Image-quality declines (blur, small print, a cropped edge with every row still read) are invisible in a candidate, so the gate does not attempt them.

**Why Python, not Swift.** Route C's mapping and the scorer are Python, CI's label-capture job runs on Linux without the Swift CLI, and the GB 2312 and Big5 codecs ship with Python. No product path consumes route C yet. A product phase would port the frozen rules into `NutritionLabelParsing` behind the same test vectors (`tests/test_phase4.py`). The Swift parser's own script guard (a fixed list of 14 Simplified characters plus kana and Hangul, used by routes A and B) is unchanged; it counts U+30FB as kana, which is why route B declines the muesli photo, and the gate does not.

## 2. Development results before and after the gate (pre-amendment, gate v1; superseded by sections 5 and 8)

All counts are re-scored offline with the unchanged scorer; the "before" columns reproduce the published phase 1 to 3 numbers exactly. "Gate declines" counts the tables the gate declined, split by whether the truth required a decline; the bracket counts declined tables that had been exactly right.

### Taiwan (20 photos)

| Arm | Correct decline | False-ready | False declines | Full table | Would mark ready | Gate declines (required) | Gate declines (usable) |
|---|---|---|---|---|---|---|---|
| Route B | 5/5 → 5/5 | 1 → 1 | 8 → 9 | 3/15 → 3/15 | 3 → 3 | 0 | 1 (0 exact) |
| Luna, off | 3/5 → **5/5** | 4 → 4 | 0 → 0 | 11/15 → 11/15 | 13 → 13 | 2 | 0 (0 exact) |
| Luna, on | 2/5 → 4/5 | 2 → 2 | 0 → 0 | 12/15 → 12/15 | 13 → 13 | 2 | 0 (0 exact) |
| Luna Pro, off | 4/5 → 4/5 | 5 → 5 | 0 → 0 | 10/15 → 10/15 | 14 → 14 | 0 | 0 (0 exact) |
| Luna Pro, on | 2/5 → 4/5 | 3 → 3 | 0 → 0 | 13/15 → 13/15 | 14 → 14 | 2 | 0 (0 exact) |
| Grok, on | 3/5 → **5/5** | 1 → 1 | 0 → 0 | 14/15 → 14/15 | 14 → 14 | 2 | 0 (0 exact) |
| Gemini 4, on | 3/5 → 4/5 | 1 → 1 | 0 → 0 | 15/15 → 15/15 | 14 → 14 | 1 | 0 (0 exact) |
| Sol, on | 3/5 → 4/5 | 2 → 2 | 0 → 0 | 14/15 → 14/15 | 14 → 14 | 1 | 0 (0 exact) |
| Sol Pro, on | 3/5 → 4/5 | 2 → 2 | 0 → 0 | 14/15 → 14/15 | 14 → 14 | 1 | 0 (0 exact) |
| Opus 5.5, on | 3/5 → **5/5** | 1 → **0** | 0 → 2 | 13/15 → 13/15 | 12 → 11 | 2 | 2 (0 exact) |
| Fable 5.1, on | 3/5 → **5/5** | 1 → 1 | 0 → 1 | 13/15 → 13/15 | 12 → 12 | 2 | 1 (0 exact) |

### UK (39 images)

| Arm | Correct decline | False-ready | False declines | Full table | Would mark ready | Gate declines (required) | Gate declines (usable) |
|---|---|---|---|---|---|---|---|
| Route B | 17/17 → 17/17 | 0 → 0 | 21 → 21 | 1/22 → 1/22 | 0 → 0 | 0 | 0 (0 exact) |
| Luna, off | 5/17 → 10/17 | 2 → 2 | 1 → 4 | 14/22 → 14/22 | 8 → 8 | 5 | 3 (0 exact) |
| Luna, on | 6/17 → 11/17 | 3 → 3 | 3 → 6 | 10/22 → 10/22 | 8 → 8 | 5 | 3 (0 exact) |
| Luna Pro, off | 3/17 → 8/17 | 3 → 3 | 3 → 5 | 13/22 → 13/22 | 10 → 10 | 5 | 2 (0 exact) |
| Luna Pro, on | 7/17 → 9/17 | 2 → 2 | 4 → 8 | 10/22 → 10/22 | 8 → 8 | 2 | 4 (0 exact) |
| Grok, on | 5/17 → 10/17 | 2 → 2 | 4 → 8 | 10/22 → 10/22 | 8 → 8 | 5 | 4 (0 exact) |
| Gemini 4, on | 3/17 → 9/17 | 6 → 5 | 1 → 5 | 13/22 → 13/22 | 16 → 15 | 6 | 4 (0 exact) |
| Sol, on | 8/17 → 12/17 | 3 → 3 | 5 → 7 | 10/22 → 10/22 | 8 → 8 | 4 | 2 (0 exact) |
| Sol Pro, on | 8/17 → 12/17 | 2 → 2 | 5 → 7 | 11/22 → 11/22 | 8 → 8 | 4 | 2 (0 exact) |
| Opus 5.5, on | 4/17 → 9/17 | 3 → 2 | 6 → 9 | 9/22 → 9/22 | 9 → 8 | 5 | 3 (0 exact) |
| Fable 5.1, on | 3/17 → 9/17 | 5 → 4 | 1 → 5 | 12/22 → 12/22 | 14 → 13 | 6 | 4 (0 exact) |

### Muesli photo and route A

- **Muesli:** unchanged for every arm (route C exact everywhere; route B still declined by the parser's own script guard).
- **Route A** (207 pasted cases): unchanged except one v1 UK case. `v1:off:5010525167350:nutrition_en.5:spaced` has no salt row in its truth, so G3 declines a table that was exactly right (full table 80/80 → 79/80, one false decline). One more v1 case (`nutrition_nl.5`, no per 100 g header in its truth) is blocked from ready by G5. Both truths come from older or non-UK panels in the v1 corpus; they are listed for the owner, not changed.

### What the gate does and does not fix

- **Correct decline rises in every route C arm** (Taiwan up to 5/5 for Luna off, Grok, Opus and Fable; UK from 3 to 8 of 17 up to 8 to 12 of 17), and the gate never declined a table that had been exactly right in any route B or C arm. The extra false declines are all tables that were already wrong (a missing or unread mandatory row), so full-table counts are unchanged.
- **False-ready barely moves** (53 → 49 over the ten arms and both strata). The premise that most false-ready tables came from Simplified Chinese, cut-off rows and supplements does not hold on re-examination: every arm already declined both Simplified Chinese photos, and the supplements were never ready. After the gate, the remaining 49 false-ready tables are:
  - **30 on images the truth declines for image quality** that the candidate cannot show: `off:5057172978809` (left edge clipped, 10 arms), `off:5052909355021` (full-pack photo, small print, 10 arms), `off-taiwan:4710228034096` (bottom row cut off, 6 arms; see section 3.3), `off:5060201623175`, `off:5015696447201`, `off:5010292978418`. In each, the model read every mandatory row.
  - **19 on usable tables with a wrong value or binding**, led by `off-taiwan:1490274741355` (6 arms) and `off-taiwan:4710090070222` (3 arms).
- So **no route C arm meets the zero false-ready bar on development even with the gate**. Opus 5.5 reaches 0 on Taiwan only.

## 3. UK diagnosis (offline; pre-amendment figures, superseded by sections 5 and 8)

Every UK product cell and serving conversion was classified per arm (`uk_diagnosis.py`). The headline is that **most of the UK loss is convention, not reading**.

### 3.1 Strict cells (311 product cells in 22 usable tables)

| Arm | Exact as scored | Lost to RI-absolute failure (M1) | Lost to unit in row label (M2) | Model declined a usable table | Genuine misreads or missing cells | Counterfactual with M1 and M2 |
|---|---:|---:|---:|---:|---:|---:|
| Luna, off | 253 | 36 | 12 | 10 | 0 | 283 (91.0%, superseded) |
| Luna, on | 238 | 36 | 8 | 24 | 5 | 262 |
| Luna Pro, off | 241 | 36 | 8 | 26 | 0 | 267 |
| Luna Pro, on | 227 | 36 | 12 | 34 | 2 | 257 |
| Grok, on | 225 | 36 | 12 | 35 | 3 | 255 |
| Gemini 4, on | 269 | 18 | 12 | 10 | 2 | 281 (90.4%) |
| Sol, on | 214 | 36 | 4 | 54 | 3 | 236 |
| Sol Pro, on | 215 | 36 | 4 | 54 | 2 | 237 |
| Opus 5.5, on | 194 | 36 | 8 | 71 | 2 | 220 |
| Fable 5.1, on | 250 | 36 | 12 | 9 | 4 | 280 (90.0%) |

### 3.2 Serving conversions (116 truth conversions)

| Arm | Exact as scored | Count-only portion, no mass printed | Same mass, header wording differs | Model or mapping gave no mass | Cell not matched | Counterfactual S1 |
|---|---:|---:|---:|---:|---:|---:|
| Luna, off | 7 | 46 | 0 | 52 | 11 | 7/70 |
| Luna, on | 9 | 46 | 0 | 52 | 9 | 9/70 |
| Luna Pro, off | 18 | 46 | 0 | 43 | 9 | 18/70 |
| Luna Pro, on | 7 | 46 | 9 | 43 | 11 | 16/70 |
| Grok, on | 16 | 46 | 9 | 34 | 11 | 25/70 |
| Gemini 4, on | 33 | 46 | 35 | 0 | 2 | **68/70** |
| Sol, on | 9 | 46 | 0 | 52 | 9 | 9/70 |
| Sol Pro, on | 9 | 46 | 0 | 52 | 9 | 9/70 |
| Opus 5.5, on | 15 | 46 | 18 | 18 | 19 | 33/70 |
| Fable 5.1, on | 24 | 46 | 26 | 9 | 11 | 50/70 |

### (a) Scoring and ground-truth convention mismatches

1. **Serving conversion is scored as the header's portion wording.** The UK truth records `serving_conversion` as the per-serving header's text (`50g pack`, `2 sausages`, `1 cracker`, `1/6 pack`, `approx. 88g`, `75g uncooked`, `130g sausage roll`), while the plan defines it as the printed serving quantity and unit, and the Taiwan truth follows that (`320毫升`). Route C's mapping emits the quantity and unit (`50g`, `88g`, `75g`), so it can never match the wording. Example: `off:5000187132315` truth `50g pack`, Gemini `50g`. This alone accounts for 35 of Gemini's 83 lost conversions.
2. **Count-only portions print no mass or volume.** 46 of the 116 truth conversions (`2 sausages`, `1 cracker`, `1/6 pack`, `1 slice`, `1 pack`) carry no printed grams or millilitres, and the plan forbids inferring one, so no route can earn them; the mapping correctly says `unknown`. Examples: `off:5057172728022`, `off:5057172706181`, `off:5057172859696`.
3. **Absolute reference-intake columns fail the whole candidate.** Some panels print an "RI for an average adult" column (`8400kJ`, `70g`). Models classify it as basis `reference_intake`; the candidate validator then rejects any non-% reference-intake cell and fails the whole table, losing 18 to 36 good cells per arm. The truth does not record that column at all. Examples: `off:5057172706181`, `off:5010251767503`.
4. **The unit is printed in the row label.** On panels with `Energy kJ` and `Energy kcal` rows, the value cell prints only `704`. The truth records `704kJ`; the model faithfully returns `704`, which the mapping cannot read, so the energy cells drop out. Examples: `off:5057172728022`, `off:5057172859696`, `off:5060011955695`.
5. **Reference-intake parentage and coverage are inconsistent in the truth.** In the two UK truths with a %RI column (`off:5053990185917`, `off:5057624572234`), reference-intake rows have their own row ids and no parent, while the matching amount rows (saturates, sugars) do have a parent; a candidate that keeps one row with one parent can never be exact. Other truths omit a printed %RI column altogether (`off:5057172859696`), so a correct read of it counts as extra cells.
6. **Bilingual unrecognised rows key on the whole printed label.** `off:5060323902912` prints `acidi grassi monoinsaturi/ monounsaturates`; the truth keys the English half only, so the row can never match.

### (b) Genuine model errors

- **Value misreads are rare:** `48.2` read as `49.2` (Grok, `off:5010482793302`), `71` as `7.1` (Luna on, `off:5060413823295`), and a bound invented (`0.03g` read as `<0.03 g`, Sol, `off:5031396074394`).
- **Over-cautious declines of usable tables** are the largest model-side loss for Sol, Sol Pro and Opus 5.5 (54 to 71 cells). Declining is the safe direction, but it costs usable output.
- **Leaving the serving size unread** when the per-serving header prints it (`PER PACK (50g)*`, `per 40 g serving`): Luna, Sol and Sol Pro return `unknown` in 34 to 52 conversions, while Gemini fills it every time. This is partly instruction and mapping design (the mapping reads only the serving size line, not the header), so M3 below would also move it.

### Proposed amendments (owner decision; applied 18 October 2026, section 5)

| Id | Change | Effect on development (counterfactual) |
|---|---|---|
| S1 | Score a serving conversion on its printed mass or volume (decimal and canonical unit), not the header wording; leave count-only portions with no printed mass out of the denominator | Gemini 33/116 → 68/70; Fable 24/116 → 50/70 |
| M1 | Route C mapping leaves an absolute reference-intake value out as unread (as it already does for `*`), instead of failing the whole candidate | Part of the strict-cell counterfactual below |
| M2 | Route C mapping takes the unit from the row label when the label prints exactly one energy unit and the value prints none | With M1: Gemini 269 → 281/311, Luna off 253 → 283, Fable 250 → 280 |
| M3 | Route C mapping also reads the serving quantity from a per-serving header that prints a mass or volume | Not simulated |
| T1 | UK truth convention: reference-intake cells share the row and parent of their amount row, and every printed %RI column is transcribed or the scorer ignores reference-intake extras for full-table | Not simulated |

*Superseded:* this counterfactual predicted at most 91.0% strict cells; with the amendments actually applied (and decline gate v2), Luna off reaches 301/311 (96.8%) and Gemini 4 299/311 (section 8).

### 3.3 Possible ground-truth errors (for the owner; nothing edited)

- `off:5010482793302` (UK): the truth has per-slice saturates `0.1g` and sugars `1.7g`; 8 of 10 arms read no per-slice value for these two rows. Worth a look at the image.
- `off-taiwan:4710228034096` (Taiwan development, Claude-drafted): the truth declines because the per-100 ml sodium is "not legible"; 6 of 10 arms read `19毫克`, which is what the per-serving `52毫克` scales to (52 × 100 / 275 = 18.9). Either the value is legible and the truth should be a usable table, or the models inferred it. Worth a look at the image.
- `v1:off:5010525167350` (route A, v1 truth): no salt row; `v1:off:5060457050039:nutrition_nl.5`: no per 100 g header. Possibly older or non-UK panels; the gate declines or blocks them.
- All UK truth headers have empty `printed_text` (header text is scored only when a basis repeats, so this is informational).

## 4. Whole-call deadline (connect and DNS bounded after the review, section 8)

`openrouter_client.http_post` now bounds the **whole attempt** by the time left of the call's 180 s budget. DNS is resolved in a thread abandoned at the deadline (getaddrinfo has no portable timeout), and connect() (TCP and TLS) is called explicitly with the time left; after it returns the deadline is checked and the socket timeout reset to the time left before sending (added after the review). A watchdog timer then shuts the socket down at the deadline, so a server that never sends headers or a body trickled byte by byte ends there, and the body is read in chunks with a deadline check between chunks. A cut attempt returns status 0 (transport error or timeout), so the retry policy is unchanged: `Retry-After` honoured, at most 5 attempts, 180 s overall. Redirects are still never followed. Tests (local 127.0.0.1 server, no provider): a body trickled at one byte per 0.1 s is cut at a 1 s deadline; a server that sleeps before its headers, a stalled DNS lookup and a stalled TLS handshake are each cut at 1 s; the retry loop with the real post stays inside a 2 s overall deadline; a 307 is returned, not followed. **All ten phase 3 development arms ran without this deadline** (per-read socket timeouts only; Grok's slowest call took 263 s).

## 5. Owner amendments applied (18 October 2026)

The owner approved S1, M1, M2, M3 and T1 exactly as proposed in section 3, recorded as pre-registered before the untouched run (contract block `amendments_2026_10_18`, sources re-pinned).

- **S1:** the scorer now compares a serving conversion's printed mass or volume (decimal and canonical unit), and count-only portions leave the denominator.
- **M1, M2, M3:** these are in `route_c_mapping.py`.
  - M2 adds one guard to the proposal: the label's unit must agree with the row's nutrient, so a contradicting unit is never attached.
- **T1:** this is in `cases.apply_uk_truth_convention_t1`, applied when the UK development review is loaded.
  - Reference-intake cells now share their amount row and its parent.
  - `reference_intake_transcribed` tells the scorer not to count reference-intake reads as extras where the truth did not transcribe the column.
  - T1 changed 23 of the 39 UK records (43 changes, each logged in [`t1-uk-truth-changes-v1.json`](t1-uk-truth-changes-v1.json)). The frozen v2 review is untouched.
  - T1 is not applied to route A's synthetic `v2dev` cases, whose rendered truth is part of the pinned dataset.

All saved development outputs were re-scored offline (no API call), with route C re-mapped from its saved wire answers: [`amendments-rescore-v1.json`](amendments-rescore-v1.json). In the tables below:

- **Before** is the gated, pre-amendment state (`decline-gate-rescore-v1.json`, commit `f313578c`).
- **After** is the gated state with the amendments.
- The gate is applied in both.

### UK (39 images)

| Arm | Strict cells | Full table | Serving conv. | Correct decline | False-ready | False declines | Would mark ready |
|---|---|---|---|---|---|---|---|
| Route B | 8/311 → 8/311 | 1/22 → 1/22 | 0/116 → 0/70 | 17/17 → 17/17 | 0 → 0 | 21 → 21 | 0 → 0 |
| Luna, off | 209/311 → 301/311 | 14/22 → 19/22 | 0/116 → 70/70 | 10/17 → 8/17 | 2 → **6** | 4 → 1 | 8 → 17 |
| Luna, on | 192/311 → 264/311 | 10/22 → 14/22 | 9/116 → 69/70 | 11/17 → 9/17 | 3 → **8** | 6 → 4 | 8 → 17 |
| Luna Pro, off | 211/311 → 285/311 | 13/22 → 17/22 | 18/116 → 70/70 | 8/17 → 6/17 | 3 → **7** | 5 → 3 | 10 → 18 |
| Luna Pro, on | 167/311 → 259/311 | 10/22 → 16/22 | 0/116 → 70/70 | 9/17 → 8/17 | 2 → **5** | 8 → 5 | 8 → 17 |
| Grok, on | 166/311 → 258/311 | 10/22 → 15/22 | 9/116 → 70/70 | 10/17 → 9/17 | 2 → **6** | 8 → 5 | 8 → 15 |
| Gemini 4, on | 209/311 → 283/311 | 13/22 → 18/22 | 26/116 → 70/70 | 9/17 → 7/17 | 5 → **6** | 5 → 2 | 15 → 17 |
| Sol, on | 184/311 → 238/311 | 10/22 → 14/22 | 9/116 → 70/70 | 12/17 → 10/17 | 3 → **6** | 7 → 6 | 8 → 16 |
| Sol Pro, on | 185/311 → 239/311 | 11/22 → 16/22 | 9/116 → 70/70 | 12/17 → 10/17 | 2 → **4** | 7 → 6 | 8 → 15 |
| Opus 5.5, on | 150/311 → 222/311 | 9/22 → 13/22 | 8/116 → 62/70 | 9/17 → 8/17 | 2 → **6** | 9 → 7 | 8 → 14 |
| Fable 5.1, on | 190/311 → 282/311 | 12/22 → 17/22 | 17/116 → 70/70 | 9/17 → 7/17 | 4 → **7** | 5 → 2 | 13 → 17 |

The UK strict-cell figures before the amendments are lower than the ungated figures in section 3.1, because the gate's G3 declined tables whose energy cells the mapping could not read.

### Taiwan, muesli and route A

- **Taiwan (20 photos), muesli and route A Taiwan cases:** every number is unchanged.
  - The Taiwan conversions already printed a mass, so S1 gives the same counts.
  - M1 to M3 and T1 do not touch these tables.
- **Route A UK:** strict cells and full tables are unchanged.
  - `v1` conversions go from 195/195 to 150/150 and `v2dev` from 116/116 to 70/70, because count-only portions leave the denominator.

### What the amendments change

- **Reading is now close to the bar on UK.**
  - Luna off reaches 301/311 strict cells (96.8%, above the 95% bar) and 19/22 full tables (86%).
  - Every arm except Opus 5.5 reaches 69 or 70 of 70 serving conversions.
- **Safety gets worse on UK.**
  - False-ready rises in every route C arm (UK total 28 → 61). Correct declines fall by one or two per arm.
  - The cause: with energy now readable (M2) and serving quantities now known (M3), tables that the gate's G3 had declined, or that the mapping held back from ready, are now complete and offered as ready.
  - Of the 61 UK false-ready tables after the amendments, 51 are on images the truth declines for image quality: `off:5060201623175`, `off:5057172978809`, `off:5060026822371` and `off:5052909355021` in all 10 arms, and `off:5015696447201` in 9. A candidate cannot show the quality problem behind these declines.
  - The other 10 are usable tables with a wrong value or binding, led by `off:5053990185917` in 7 arms.
  - Before the amendments, the energy-unit failure (M2) had been declining some of these image-quality cases by accident.
- **No route C arm meets the zero false-ready bar** on either stratum after the amendments. Route C false-ready over both strata rises from 49 to 82; Taiwan stays at 21.

## 6. Round-3 owner review (data only; no truth edited)

Review data for the possible truth errors in section 3.3 was prepared outside the repository, from development images on disk only: two entries, each with a resized image (1600 px, JPEG quality 80), the question, the current truth and what each arm read.

- `off-taiwan:4710228034096:nutrition_zh.7` (order 3): is the per-100 ml sodium legible?
- `off:5010482793302:nutrition_en.5`: are per-slice saturates 0.1 g and sugars 1.7 g printed?
- **Skipped:** `v1:off:5010525167350` and `v1:off:5060457050039:nutrition_nl.5`, because the v1 panel images are not on disk. Nothing was downloaded.

The truth stays as it is until the owner answers.

## 7. Not done in this phase

- No API call, no rerun of any arm, no untouched or sealed run. The untouched Taiwan run waits for the owner.
- No truth value was edited. T1 changes only the convention (row ids, parents and the transcription flag) of the UK development truth at load time.

## 8. Invariant review fixes and decline gate v2 (18 October 2026)

The invariant review of PR #259 at `ac584932` asked for the fixes below; the owner decided the review questions as decline gate v2. Gate v1 stays recorded in the contract (`decline_gate.v1`) as the version the earlier re-scores used.

- **M3 unit match.** The serving mass in a per-serving header, and in the serving line (`_serving_size`), is now read with S1's `PRINTED_MASS` pattern, whose unit may not run on into a word, so "2 grilled sausages (90g)" gives 90g and "1 glass (250ml)" gives 250ml, never 2g. No development number changed.
- **Gate v2.**
  - G1 no longer counts 14 shared variant code points (内 温 黄 户 着 奥 吴 吕 没 别 强 兑 虚 册) as Simplified. Each is in GB 2312 but not CP950 only because Big5 encodes a sibling glyph of the same character, and Traditional text commonly uses it. True Simplified text (营 养 质) is still declined.
  - G2 drops 錠 as a standalone marker (口含錠 mints are food); the explicit supplement markers stay.
  - G4 checks only per 100 g or per 100 ml columns, because a per-portion column may list only some rows (1169/2011 Article 33).
- **Connect and DNS deadline.** `connect()` is called explicitly, to an address resolved in a thread that is abandoned at the deadline (`getaddrinfo` has no portable timeout). After it returns the deadline is checked and the socket timeout reset to the time left. New tests cut a stalled DNS lookup and a stalled TLS handshake at a 1 s deadline.
- **Spend after a cut.** A cut after the request was sent is looked up by its generation id if the partial body held one; otherwise, or if the lookup finds no cost, it is charged at the per-call stop as `cut_unreconciled_per_call_ceiling`. A cut before sending cannot have a generation.
- **Re-score hygiene.** `rescore_development.py` checks the split before reading any log and refuses a log sample that is not a development case. It records per-arm false-ready case ids, split into required declines and usable tables, and refuses to overwrite the two earlier result files.

### Re-scored development results (gate v2 with the amendments and fixes)

Before is the pre-amendment gate v1 state (`decline-gate-rescore-v1.json`, commit `f313578c`); after is [`gate-v2-rescore-v1.json`](gate-v2-rescore-v1.json).

**UK (39 images)**

| Arm | Strict cells | Full table | Serving conv. | Correct decline | False-ready | False declines | Would mark ready |
|---|---|---|---|---|---|---|---|
| Route B | 8/311 → 8/311 | 1/22 → 1/22 | 0/116 → 0/70 | 17/17 → 17/17 | 0 → 0 | 21 → 21 | 0 → 0 |
| Luna, off | 209/311 → 301/311 | 14/22 → 19/22 | 0/116 → 70/70 | 10/17 → 8/17 | 2 → 6 | 4 → 1 | 8 → 17 |
| Luna, on | 192/311 → 280/311 | 10/22 → 14/22 | 9/116 → 69/70 | 11/17 → 9/17 | 3 → 8 | 6 → 3 | 8 → 17 |
| Luna Pro, off | 211/311 → 285/311 | 13/22 → 17/22 | 18/116 → 70/70 | 8/17 → 6/17 | 3 → 7 | 5 → 3 | 10 → 18 |
| Luna Pro, on | 167/311 → 275/311 | 10/22 → 16/22 | 0/116 → 70/70 | 9/17 → 8/17 | 2 → 5 | 8 → 4 | 8 → 17 |
| Grok, on | 166/311 → 273/311 | 10/22 → 15/22 | 9/116 → 70/70 | 10/17 → 9/17 | 2 → 6 | 8 → 4 | 8 → 15 |
| Gemini 4, on | 209/311 → 299/311 | 13/22 → 18/22 | 26/116 → 70/70 | 9/17 → 7/17 | 5 → 6 | 5 → 1 | 15 → 17 |
| Sol, on | 184/311 → 254/311 | 10/22 → 14/22 | 9/116 → 70/70 | 12/17 → 10/17 | 3 → 6 | 7 → 5 | 8 → 16 |
| Sol Pro, on | 185/311 → 255/311 | 11/22 → 16/22 | 9/116 → 70/70 | 12/17 → 10/17 | 2 → 4 | 7 → 5 | 8 → 15 |
| Opus 5.5, on | 150/311 → 238/311 | 9/22 → 13/22 | 8/116 → 62/70 | 9/17 → 8/17 | 2 → 6 | 9 → 6 | 8 → 14 |
| Fable 5.1, on | 190/311 → 298/311 | 12/22 → 17/22 | 17/116 → 70/70 | 9/17 → 7/17 | 4 → 7 | 5 → 1 | 13 → 17 |

**Taiwan (20 photos)**

Unchanged from the pre-amendment state except Opus 5.5:
- false-ready 0 → 1;
- false declines 2 → 1;
- would mark ready 11 → 12.

Under gate v2's G4, a partial per-serving column is no longer declined. That table is wrong, so it is now offered as ready.

**Unchanged:** the muesli photo, route A and route B, apart from the route A UK conversion denominators (count-only portions leave them).

**Gate v2 compared with gate v1, both with the amendments:**
- G4 no longer declines `off:5010482793302`, a usable UK table, in 8 arms: Luna on, Luna Pro on, Grok, Gemini 4, Sol, Sol Pro, Opus 5.5 and Fable 5.1.
  - The models read no per-slice saturates or sugars for it; that is the round-3 truth question.
  - Each of those arms gains 15 or 16 UK strict cells.
- G4 no longer declines `off-taiwan:0848570012982` for Opus 5.5. That table is wrong, so Taiwan false-ready rises by one.
- UK false-ready is unchanged.

**False-ready after the gate, re-derived from the private runs** (per-arm case ids are in `false_ready_after_gate` in the JSON):
- **UK: 61.**
  - 51 are on images the truth declines for image quality: `off:5060201623175`, `off:5057172978809`, `off:5060026822371` and `off:5052909355021` in all 10 arms, `off:5015696447201` in 9, `off:5060131761954` and `off:5010292978418` in 1 each.
  - 10 are usable tables with a wrong value, led by `off:5053990185917` (7 arms).
- **Taiwan: 22.**
  - 6 are required declines (`off-taiwan:4710228034096`, 6 arms).
  - 16 are usable tables with a wrong value, led by `off-taiwan:1490274741355` (6 arms).
- **Route C total: 83.** No arm meets the zero false-ready bar on either stratum.
