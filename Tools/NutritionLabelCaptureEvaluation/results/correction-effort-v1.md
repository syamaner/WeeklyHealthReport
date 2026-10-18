# Correction effort (post-freeze analysis, #255)

Status: **offline analysis, 18 October 2026, owner-approved the same day.** It reads the saved outputs of the untouched Taiwan run and of the development runs, and the frozen, corrected truth. Nothing was rerun and no API call was made. Machine-readable counts and case ids: [`correction-effort-v1.json`](correction-effort-v1.json), written by [`../correction_effort.py`](../correction_effort.py).

**What this is, and what it is not.**

- The pre-registered bars measured fully automatic reading. The owner's guiding principle is different: recognition pre-fills, the user validates and optionally corrects, and estimates and exceptions are visible. This analysis asks how much a user would have to edit on Confirm if a route only pre-filled the table.
- It is **not a pass or fail**, and it does **not change the pre-registered verdict**: no photo route passed ([`untouched-taiwan-v1.md`](untouched-taiwan-v1.md)).
- The truth is model-drafted and owner-verified, with the **anchoring caveat**: owner verification missed at least one drafting error, so the per-cell truth has an unknown error rate. Every count below is effort against that truth.
- **User behaviour is not measured.** Whether a user actually catches a wrong pre-filled value is unknown; the silent-error counts are the cases the disclaimer exists for.
- It is a post-freeze analysis addition, recorded in the contract under `post_freeze_record_edits`. No pinned scoring file changed.

## 1. How edits are counted

Per usable table (not excluded and not a required decline), the pre-filled output is compared with the truth using the scorer's own semantic key (nutrient, parent, basis, and the printed header for duplicate same-basis columns).

| Measure | Counted when |
|---|---|
| Correction | A pre-filled value sits in a slot the truth has, but the value, comparator or unit differs. A right value bound to the wrong column or parent is **one** binding correction, not a fill plus a removal |
| Fill | A gradable truth cell has no pre-filled value (left out, unread or `unknown`) |
| Removal | A pre-filled value where the truth has no printed cell (reference-intake cells are not removals where the truth did not transcribe that column, amendment T1) |
| Serving lines | The serving size and the servings per pack, each a correction, fill or removal, or not scored (the UK development review transcribed no serving lines) |
| Edits per table | Corrections + fills + removals + serving-line edits |
| Whole table by hand | A hard decline on a usable table: the user types or pastes the whole table. Counted separately, with the cells it would need, and left out of the edit distribution |
| Silent error | A correction or removal in a row the Confirm flags (G3 and G4 rows) would not mark, or a wrong or invented serving line (G6 flags only a missing one). The user must spot these unaided |
| Silent omission | Reported apart from silent errors: a row the route left out entirely, with no flag, so it is simply absent from Confirm |

Two views of the same saved outputs:

- **As run:** gate v2 as frozen. Every gate decline (G1 to G4) and every route decline is a whole table by hand. On the untouched set this is the saved gated output; re-applying gate v2 to the saved ungated output reproduces all 40 saved outputs in every arm, which the script checks. The development runs predate the gate, so gate v2 is applied offline there, as `rescore_development.py` does.
- **Assisted design:** the ungated output with only the hard declines of the assisted design: the route's own decline (no table, the parser's binding failures, a model decline), a failed output, G1 (`unsupported_script`) and G2 (`not_a_food_nutrition_panel`). G3 to G6 become flags on Confirm.

Median and p90 are over the pre-filled tables only (p90 is nearest-rank). Edits are counted per value: a whole-column misread counts every cell in it.

## 2. Untouched Taiwan (40 usable tables, primary)

| Arm | View | 0 edits | 1 to 2 | 3 to 5 | 6+ | By hand | Median / p90 | Total edits | Silent-error tables | Silent omissions |
|---|---|---|---|---|---|---|---|---|---|---|
| Gemini 4, on | as run | 34 (85%) | 1 | 0 | 0 | 5 (86 cells) | 0 / 0 | 2 | 1 | 0 |
| Gemini 4, on | assisted | 35 (88%) | 1 | 1 | 0 | 3 (48 cells) | 0 / 0 | 6 | 2 | 1 |
| Sol, on | as run | 34 (85%) | 2 | 0 | 0 | 4 (70 cells) | 0 / 0 | 2 | 1 | 0 |
| Sol, on | assisted | 34 (85%) | 3 | 1 | 0 | 2 (40 cells) | 0 / 1 | 7 | 3 | 0 |
| Luna, off | as run | 30 (75%) | 4 | 0 | 4 | 2 (38 cells) | 0 / 7 | 73 | 5 | 1 |
| Luna, off | assisted | 30 (75%) | 4 | 1 | 5 | 0 | 0 / 7 | 96 | 7 | 2 |
| Route B | as run | 4 (10%) | 1 | 0 | 0 | 35 (574 cells) | 0 / 1 | 1 | 0 | 0 |
| Route B | assisted | 4 (10%) | 1 | 0 | 0 | 35 (574 cells) | 0 / 1 | 1 | 0 | 0 |

Cross-checks against the run: the as-run zero-edit counts equal the corrected full-table exact counts (34, 34, 30, 4), and the as-run hand counts equal the reported false declines (5, 4, 2, 35).

### Edits by kind (pre-filled tables)

| Arm | View | Corrections (value / unit / binding) | Fills | Removals | Serving size (corr. / fill / rem.) | Servings per pack (corr. / fill / rem.) |
|---|---|---|---|---|---|---|
| Gemini 4, on | as run | 2 (0 / 0 / 2) | 0 | 0 | 0 / 0 / 0 | 0 / 0 / 0 |
| Gemini 4, on | assisted | 2 (0 / 0 / 2) | 1 | 2 | 0 / 0 / 0 | 0 / 0 / 1 |
| Sol, on | as run | 1 (1 / 0 / 0) | 0 | 0 | 0 / 1 / 0 | 0 / 0 / 0 |
| Sol, on | assisted | 2 (2 / 0 / 0) | 2 | 2 | 0 / 1 / 0 | 0 / 0 / 0 |
| Luna, off | as run | 29 (15 / 0 / 14) | 14 | 26 | 2 / 1 / 0 | 0 / 1 / 0 |
| Luna, off | assisted | 34 (20 / 0 / 14) | 23 | 33 | 2 / 1 / 0 | 1 / 1 / 1 |
| Route B | both | 0 | 0 | 0 | 0 / 1 / 0 | 0 / 0 / 0 |

### Hard declines on usable tables

| Arm | As run | Assisted design |
|---|---|---|
| Gemini 4, on | 5: 3 model declines, 2 G3 (`4710022030713`, `4711957513876`) | 3 model declines |
| Sol, on | 4: 2 model declines, 2 G3 (`4711957513876`, `4712893950282`) | 2 model declines |
| Luna, off | 2: G3 (`4710022030713`, `4711957513876`) | 0 |
| Route B | 35 parser declines | 35 parser declines |

No usable table hit G1 or G2, so the assisted view removes only the G3 declines. Releasing them does not come free: every released table needs edits, and some carry silent errors (below).

### Silent errors (the cases the disclaimer exists for)

Case ids are shortened to the barcode; the full ids are in the JSON.

- **Gemini 4.** As run, 1 table: `4972767003715`, a cholesterol row pre-filled under fat as its parent. The values are right; the nesting is wrong (2 binding corrections). The assisted view adds `4710022030713` (a G3 release): an invented row and an invented servings-per-pack line, plus an unflagged row left out.
- **Sol.** As run, 1 table: `4710126001718`, one wrong saturated-fat value; the arithmetic check fails on it, so a warning would show. The assisted view adds the two G3 releases: `4711957513876` (a wrong energy value, the arithmetic check fails) and `4712893950282` (an invented row the check does not see).
- **Luna.** As run, 5 tables: `3228022000311` (9 wrong values), `4710018164101` (6 wrong values and the serving size), `4710088886590` (a column bound to the wrong basis, 6 binding corrections, plus 10 fills), `4710543022082` (the serving size), `4713105808025` (24 invented values and 8 binding corrections). The assisted view adds `4710022030713` and `4711957513876`.
- **Route B:** none, because it pre-fills almost nothing.

| Arm | Silent-error tables, as run | of which the arithmetic check did not fail | Assisted | of which the check did not fail |
|---|---|---|---|---|
| Gemini 4, on | 1 | 1 | 2 | 2 |
| Sol, on | 1 | 0 | 3 | 1 |
| Luna, off | 5 | 2 | 7 | 4 |
| Route B | 0 | 0 | 0 | 0 |

The arithmetic column only says whether a check warning could draw attention to the table, not that the user would act on it. A pre-filled, ready-marked table with a silent error is close to the false-ready count of the run, but not the same: a silent error counts whether or not the route would mark the table ready.

## 3. Development (secondary, labelled development)

These are development outputs: the prompts, the mapping and the gate were developed on them, and the Taiwan development truth is a first-pass draft. They overstate the untouched figures and are shown only for context. On development, the as-run and assisted views are identical for the route C arms (no G3 or G4 decline on a usable table); route B differs on Taiwan.

| Arm | Stratum | Usable | 0 edits | 1 to 2 | 3 to 5 | 6+ | By hand | Median / p90 | Total edits | Silent-error tables |
|---|---|---|---|---|---|---|---|---|---|---|
| Gemini 4, on | Taiwan | 15 | 15 | 0 | 0 | 0 | 0 | 0 / 0 | 0 | 0 |
| Gemini 4, on | UK | 22 | 18 | 3 | 0 | 0 | 1 (10 cells) | 0 / 1 | 4 | 2 |
| Sol, on | Taiwan | 15 | 14 | 1 | 0 | 0 | 0 | 0 / 0 | 1 | 1 |
| Sol, on | UK | 22 | 14 | 3 | 0 | 0 | 5 (54 cells) | 0 / 1 | 4 | 2 |
| Luna, off | Taiwan | 15 | 11 | 3 | 0 | 1 | 0 | 0 / 1 | 9 | 2 |
| Luna, off | UK | 22 | 19 | 2 | 0 | 0 | 1 (10 cells) | 0 / 0 | 3 | 2 |
| Route B, as run | Taiwan | 15 | 3 | 3 | 0 | 0 | 9 (146 cells) | 0.5 / 2 | 4 | 2 |
| Route B, assisted | Taiwan | 15 | 3 | 3 | 0 | 1 | 8 (130 cells) | 1 / 11 | 15 | 3 |
| Route B | UK | 22 | 1 | 0 | 0 | 0 | 21 (317 cells) | 0 / 0 | 0 | 0 |

The muesli photo (1 table) needs no edit in any route C arm and is declined by route B. Every hand count on development is a route decline (model or parser), except one route B Taiwan table declined by G3 as run.

## 4. Plain reading

- **Where a route C arm pre-fills, most tables need no edit.** Gemini 4 and Sol leave 34 or 35 of 40 untouched tables exactly right, with a median and p90 of 0 or 1 edits on the pre-filled ones. Luna also leaves 30 exactly right, but its tail is long: 4 or 5 tables need 6 or more edits (p90 7, up to 32).
- **The larger burden is the whole table by hand.** As run, the best arms decline 4 or 5 usable tables (70 to 86 cells to type). The assisted design releases the G3 declines, which turns 2 tables per arm into pre-filled tables (0 to 4 edits for Gemini 4 and Sol, 4 and 19 for Luna), but also adds silent errors.
- **Silent errors are rare but real.** 1 table in 40 for Gemini 4 and Sol as run (2 and 3 in the assisted view), and 5 to 7 for Luna. Several look plausible and pass the arithmetic check. The user's own check is unmeasured.
- **Route B is safe because it reads almost nothing:** 35 of 40 tables by hand.
- **The verdict is unchanged.** No photo route passed the pre-registered bars; this analysis describes effort, not fitness for product. Any product use of a photo route still needs its own contract, ZDR routing, privacy updates and owner approval.

## 5. Reproduce

```sh
cd Tools/NutritionLabelCaptureEvaluation
.venv/bin/python correction_effort.py --runs ~/WHR-label-eval-private/runs --out results/correction-effort-v1.json
```

It reads the saved Inspect logs outside the repository and the current pinned untouched truth (SHA-256 `8c871d2d…`, after the three owner corrections), makes no call, and refuses to run unless re-applying gate v2 reproduces every saved untouched output.
