# Untouched Taiwan run (phase 5, #255)

Status: **run once, 18 October 2026. No photo route (B or C) passed the pre-registered bars.** Route A on its untouched pasted-text cases passed every bar on route output but fails the arithmetic mutation-detection bar, which tests the shared arithmetic policy rather than the route (section 6). The 40 untouched Taiwan photos were unsealed under the contract rules and run through route B and three route C arms, each exactly once. There were no reruns, no tuning after results and no infrastructure failures. Machine-readable counts (case ids only, no model answers): [`untouched-taiwan-v1.json`](untouched-taiwan-v1.json).

- **Truth evidence:** model-drafted, owner-verified (no owner corrections). The 40 usable tables were drafted by Qwen 3.5 and checked by the owner, who made no corrections, so anchoring on the draft cannot be ruled out. Section 4 lists three cells that look wrong.
- **Limits** (plan section 3.5): the photos are crowd-sourced Open Food Facts uploads, not this app's captures. A route C result here is evaluation-only egress. Any product use still needs ZDR routing, a versioned contract, a privacy update and owner approval.

## 1. How it ran

- **Contract:** `frozen_for_untouched_run`, every artefact pinned, validated before each arm. The decline gate is `label-capture-decline-gate-v2`, and it ran on every route.
- **Unseal:** the `--unseal` flag plus the sealed manifest SHA-256. Every photo's bytes were checked against the manifest. `log_images` was False, and the logs are outside the repository.
- **Run once:** a run register outside the repository refuses any second start of a route and arm. All four entries are complete.
- **Route C arms:** the frozen development pins.

  | Arm | Slug | Endpoint | Reasoning |
  |---|---|---|---|
  | Gemini 4 Argon | `google/gemini-4-argon` | `google-ai-studio` | on |
  | GPT-6.1 Sol | `openai/gpt-6.1-sol` | `openai` | on |
  | GPT-6 Luna | `openai/gpt-6-luna` | `openai` | off |

  Every arm ran with 16,384 output tokens, a $0.20 per-call stop, the unchanged retry policy and the whole-call deadline.
- **Pre-run checks (free):**
  - The catalogue showed the same slug, endpoint, provider, prices, parameters and status for all three arms. The Gemini endpoint now also lists a `discount` field, but its prompt and completion prices are unchanged.
  - Available credit ($47.73, the smaller of the key limit and the account balance) covered each arm and the $40 sealed reservation.
  - Both fictional qualification labels passed for every arm.
- **Calls:** 40 calls per arm, every response from the requested model and provider. There were no retries, no unknown costs, no failed or schema-invalid cases and no deadline cuts.
- **Route B:** Vision revision 3 (`zh-Hant`, `en-US`), the pinned serialiser and the shared parser. Both binaries were built from the pinned sources on the day, and their hashes are frozen in the contract.
- **Route A:** run once afterwards on its own untouched pasted-text set, by owner decision of 18 October 2026 (section 6).

## 2. Results against the bars (40 tables, Taiwan stratum)

| Metric | Bar | Gemini 4, on | Sol, on | Luna, off | Route B |
|---|---|---|---|---|---|
| Strict cells | ≥ 95% | 521/601 (86.7%) **fail** | 538/601 (89.5%) **fail** | 536/601 (89.2%) **fail** | 74/601 (12.3%) **fail** |
| Row / header binding | ≥ 98% | 563/654 (86.1%) **fail** | 580/654 (88.7%) **fail** | 573/654 (87.6%) **fail** | 80/654 **fail** |
| Unit and basis | 100% | 524/601 **fail** | 542/601 **fail** | 548/601 **fail** | 74/601 **fail** |
| Full table | ≥ 75% | 33/40 (82.5%) pass | 33/40 (82.5%) pass | 30/40 (75.0%) pass | 4/40 **fail** |
| Serving conversions | ≥ 98% | 290/335 (86.6%) **fail** | 291/335 (86.9%) **fail** | 282/335 (84.2%) **fail** | 33/335 **fail** |
| Servings per pack | ≥ 98% | 35/39 **fail** | 36/39 **fail** | 37/39 **fail** | 5/39 **fail** |
| Bounds | 100% | 0/1 **fail** | 0/1 **fail** | 0/1 **fail** | 0/1 **fail** |
| Correct decline | ≥ 95% | no denominator (the set has no required decline) | same | same | same |
| False-ready | 0 | **2** fail | **1** fail | **4** fail | 0 pass |
| False declines (reported) | n/a | 5 | 4 | 2 | 35 |
| Would mark ready | n/a | 33 | 32 | 31 | 2 |
| Arithmetic mutation detection (on truth) | 100% | 50/54 **fail** | 50/54 **fail** | 50/54 **fail** | 50/54 **fail** |
| Median cost per photo | ≤ $0.02 | $0.0105 | $0.0162 | $0.0006 | none |
| p50 / p90 latency | p90 ≤ 20 s | 9.9 / 15.5 s | 16.7 / **22.6** s | 5.8 / 9.8 s | n/a |
| Reported cost for 40 photos | n/a | $0.4329 | $0.8996 | $0.0386 | none |

Automatic persistence was 0 in every arm.

## 3. Plain reading

- **No route is promotable on this result.** Every route C arm fails strict cells, binding, conversions, servings per pack, bounds and the zero false-ready bar. The full-table bar is the only one any arm clears. Route B is safe (no false-ready) but declines 35 of 40 usable tables.
- **Development overstated Taiwan.** On the 15 usable development tables, Gemini 4 was exact on every cell. On the untouched 40 it is exact on 33 tables and 86.7% of cells.
  - Most of the cell loss comes from tables the models (or the gate) declined. A declined table loses all its cells: Gemini 4 declined 5 usable tables and Sol 4.
  - The rest is misreads in the remaining tables.
- **False-ready happens in every arm.**
  - **Luna off (4 tables).** One table where the reading went wrong: the per-serving energy is 129 against 0, and the serving size is read as 29 against 287.5. Two tables missed a 0% reference-intake cell. One table missed an unrecognised 鈣 row.
  - **Gemini 4 (2 tables).** The `off-taiwan:3228022000311` case in section 4, plus one cholesterol row given fat as its parent, which the truth does not.
  - **Sol (1 table).** The `off-taiwan:3228022000311` case only.
  - **Pattern:** a missing reference-intake cell does not block ready in route C. Route B has that guard; route C's mapping does not.
- **The decline gate's G3 declined two usable tables in some arms** (`off-taiwan:4710022030713` and `off-taiwan:4711957513876`). Both look like layouts where a mandatory row was not read. Gate v2 was frozen and is reported as it ran.
- **Correct decline is untested:** the untouched set has no required decline, so that bar has no denominator, which is not a pass.
- **Cost and latency:** Gemini 4 and Luna are within both product ceilings. Sol is within the cost ceiling but over the p90 latency ceiling (22.6 s against 20 s).

## 4. Anything unexpected

1. **A likely truth error on `off-taiwan:3228022000311` (owner re-check in progress; correction path in section 7).** Gemini 4 and Sol independently read three cells as 74.5大卡 (energy per serving), 82公克 (fat per 100 g) and 57公克 (saturated fat per 100 g). The owner-verified truth has 745大卡, 8.2公克 and 5.7公克.
   - The truth's values are implausible together: 745 kcal is impossible in a 10 g serving. The models' values are consistent with each other: 82% fat and 74.5 kcal per 10 g fit a butter-like product.
   - If the truth is wrong, both arms lose a false-ready table and three cells.
   - In the truth, the per-serving and per-100 g columns carry identical values for energy (745), fat (8.2) and saturates (5.7), so one column's values look copied into the other. The models read 745大卡 per 100 g and 8.2公克 fat per serving, which agree with the truth, and differ only in the other column.
   - Nothing was changed. The truth stays frozen for this run, and any correction is the owner's to make and report as a deviation.
2. **The one bounded cell** (`off-taiwan:4710022030713`, sugars "less than 1 g") is in a table that every route declined, so the bounds bar is 0/1 for all four.
3. **Arithmetic mutation detection is 50/54 on the untouched truth.** This checks the policy, not the routes, and it fails its 100% bar as it did on development.

## 5. Spend

| Item | Reported cost |
|---|---:|
| Untouched calls (sealed reservation): 120 calls | $1.3710 |
| Qualification (development budget): 6 calls | $0.0494 |
| **This run** | **$1.4204** |
| Spend ledger total after the run | $18.19 |

- **Sealed reservation:** 120 of the 200 reserved calls used, 80 remain.
- **Credit:** no unknown-cost calls and no cut attempts. Available credit after the run was about $46.

## 6. Route A on the untouched pasted-text set (owner decision, 18 October 2026)

The untouched pasted-text cases were rendered once with the frozen generator path and run once through the shipped Swift parser, decline gate v2 and the frozen scorer. There was no network call and no tuning.

- **The cases:** the FDA dataset 188 rows and closed-template candidates whose hash assigns them to `untouched`. They had been counted but never rendered.
  - The FDA CSV matched its pinned hash.
  - `run_untouched_text.py` applies exactly the per-row logic of `build_cases.py`. A test shows the same path reproduces the 104 committed development FDA and template cases byte for byte.
  - The parser binary matched its frozen hash.
- **The set:** 107 cases.
  - 75 FDA 188 cases: 60 usable tables plus 15 hash-seeded required declines, which are Simplified Chinese or energy without a unit.
  - 32 template cases: tables with bounds, a reference-intake column, per 100 ml, single-column layouts and 本包裝含2.5份.
  - Dataset SHA-256 `9eace6511eee1a0defb1c251a772b152a9a13169a49d894ca67e7cf2cc09c3c4`.
  - This meets the adequacy minimum of 30 untouched synthetic Chinese cases.

| Metric | Bar | Route A, untouched pasted text |
|---|---|---|
| Strict cells | ≥ 95% | 1093/1093 (100%) pass |
| Row / header binding | ≥ 98% | 1123/1123 pass |
| Unit and basis | 100% | 1093/1093 pass |
| Full table | ≥ 75% | 92/92 pass |
| Serving conversions | ≥ 98% | 599/599 pass |
| Servings per pack | ≥ 98% | 92/92 pass |
| Bounds | 100% | 36/36 pass |
| Correct decline | ≥ 95% | 15/15 pass |
| False-ready | 0 | 0 of 107 pass |
| False declines (reported) | n/a | 0 |
| Would mark ready | n/a | 92 of 92 usable tables |
| Automatic persistence | 0 | 0 pass |
| Arithmetic mutation detection (on truth) | 100% | 110/116 **fail**: tenfold serving 69/72, basis transposition 32/35, bound replaced by exact 9/9 |

**Plain reading:**
- On clean synthetic pasted text in the known shapes, the parser read every cell, bound every row, kept every bound, declined every required decline and offered nothing wrong as ready.
- **The one failed bar measures the shared arithmetic policy, not the parser.** It applies the three frozen mutations to the truth and asks whether the arithmetic check notices. 6 of 116 mutations pass the tolerance, as on development.
  - Under plan section 10, every section 5 bar must pass, so strictly route A does not meet the promotion rule as written.
  - Whether a policy bar should block a route that read everything correctly is the owner's decision.
  - That decision is needed before route A moves to its own product contract (decision 11).
- **Limits** (plan section 3.5): all of this text is synthetic, rendered from verified values by the same generator family the parser was developed against. Real pasted Taiwan or UK text from web pages is unmeasured, so a product phase would have to spot-check real pasted examples first.

## 7. Correction path for the untouched truth (prepared, not applied)

The owner is re-checking every cell of `off-taiwan:3228022000311:nutrition_zh.12` against the photo. Nothing changes until the answers are in. The path is:

1. The owner's answers go in a separate corrections file, `{case_id, cells: [{nutrient, basis, was, now}]}`. The frozen truth file is never edited, and its pinned hash stays valid.
2. `rescore_untouched.py` checks the frozen truth hash and applies the corrections in memory to a copy.
   - It refuses a correction that matches no cell or several cells, whose `was` text is stale, or that targets an excluded record.
   - It re-scores the saved, already gated outputs of all four untouched arms offline, before and after the correction. There is no rerun and no API call.
3. The deviation is recorded in the contract (`untouched_truth_deviations`), with the answers, the changed cells and both sets of numbers. This report is then updated, keeping the original figures.

With no corrections the tool reproduces every arm's numbers exactly: route B 74/4/0, Luna 536/30/4, Gemini 4 521/33/2 and Sol 538/33/1 (strict cells, full tables, false-ready). A template listing every cell of the record, with the three questioned cells, is ready for the owner's answers outside the repository.

## 8. Photo AI: conclusion, decision deferred

**Conclusion:** no photo route passed the pre-registered bars on the untouched Taiwan set.
- Route C fails strict cells, conversions, servings per pack, bounds and the zero false-ready bar in every arm.
- Route B fails on coverage, because it declines almost everything.

Nothing here supports promoting a photo route under the plan's rules.

**For information only (not a recommendation to ship): AI pre-fill with a mandatory Confirm.** Suppose the route C output were used only to pre-fill the shared Confirm screen beside the photo, with every cell requiring the user's explicit selection and the Log action as the only save.
- **Effort:** the best arms would hand the user an exactly right table about four times in five (33 of 40 here). They would leave a wrong or missing cell to correct in most of the rest, and decline about one in eight usable tables, which the user would then enter by hand.
- **Silent errors:** the risk the zero false-ready bar guards against is that a user accepts a wrong pre-filled table without noticing. On this set that would have been 1 to 4 tables in 40 per arm (2.5% to 10%), before any reduction from the user's own check, which is unmeasured.
  - Some errors are plausible-looking: a tenfold slip, or a missing 0% reference value.
  - The arithmetic check does not catch all of them.
- **Cost and latency:** Gemini 4 and Luna fit the cost and latency ceilings. Sol is over the latency ceiling.

Any product use of a photo route, pre-fill or otherwise, would need:
- its own versioned contract;
- ZDR, no-collection routing;
- updates to `privacy-and-egress.md` and `privacy-policy.txt` (which currently say photos are not attached to OpenRouter requests);
- separate owner approval.

The decision is left for later.

## 9. What this does and does not show

- **It shows:** on 40 untouched public Taiwan photos, the three frozen route C arms read most tables but still offer some wrong tables as ready, and none meets the bars.
- **It does not show:**
  - real-world rates beyond this denominator;
  - UK labels, because the UK untouched set is deferred;
  - real pasted text.
- **Next decisions are the owner's:** the truth of `off-taiwan:3228022000311` (section 7), whether route A goes to its own product contract (section 6), and the photo AI question (section 8).
