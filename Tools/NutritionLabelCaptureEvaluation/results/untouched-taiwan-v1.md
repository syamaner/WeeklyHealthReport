# Untouched Taiwan run (phase 5, #255)

Status: **run once, 18 October 2026; no route passes every bar.** The 40 untouched Taiwan photos were unsealed under the contract rules and run through route B and three route C arms, each exactly once. There were no reruns, no tuning after results and no infrastructure failures. Machine-readable counts (case ids only, no model answers): [`untouched-taiwan-v1.json`](untouched-taiwan-v1.json).

- **Truth evidence:** model-drafted, owner-verified (no owner corrections). The 40 usable tables were drafted by Qwen 3.5 and checked by the owner, who made no corrections, so anchoring on the draft cannot be ruled out. Section 4 lists three cells that look wrong.
- **Limits** (plan section 3.5): the photos are crowd-sourced Open Food Facts uploads, not this app's captures. A route C result here is evaluation-only egress. Any product use still needs ZDR routing, a versioned contract, a privacy update and owner approval.

## How it ran

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
- **Route A:** not run. The untouched pasted-text cases (FDA 188 and template) have never been rendered. Rendering and running them would consume that separate untouched set, so it needs its own owner decision.

## Results against the bars (40 tables, Taiwan stratum)

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

## Plain reading

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

## Anything unexpected

1. **A likely truth error on `off-taiwan:3228022000311`.** Gemini 4 and Sol independently read three cells as 74.5大卡 (energy per serving), 82公克 (fat per 100 g) and 57公克 (saturated fat per 100 g). The owner-verified truth has 745大卡, 8.2公克 and 5.7公克.
   - The truth's values are implausible together: 745 kcal is impossible in a 10 g serving. The models' values are consistent with each other: 82% fat and 74.5 kcal per 10 g fit a butter-like product.
   - If the truth is wrong, both arms lose a false-ready table and three cells.
   - Nothing was changed. The truth stays frozen for this run, and any correction is the owner's to make and report as a deviation.
2. **The one bounded cell** (`off-taiwan:4710022030713`, sugars "less than 1 g") is in a table that every route declined, so the bounds bar is 0/1 for all four.
3. **Arithmetic mutation detection is 50/54 on the untouched truth.** This checks the policy, not the routes, and it fails its 100% bar as it did on development.

## Spend

| Item | Reported cost |
|---|---:|
| Untouched calls (sealed reservation): 120 calls | $1.3710 |
| Qualification (development budget): 6 calls | $0.0494 |
| **This run** | **$1.4204** |
| Spend ledger total after the run | $18.19 |

- **Sealed reservation:** 120 of the 200 reserved calls used, 80 remain.
- **Credit:** no unknown-cost calls and no cut attempts. Available credit after the run was about $46.

## What this does and does not show

- **It shows:** on 40 untouched public Taiwan photos, the three frozen route C arms read most tables but still offer some wrong tables as ready, and none meets the bars.
- **It does not show:**
  - real-world rates beyond this denominator;
  - UK labels, because the UK untouched set is deferred;
  - real pasted text.
- **Next decisions are the owner's:** whether the truth of `off-taiwan:3228022000311` needs correcting (reported as a deviation, never a rerun), and whether to render and run the untouched pasted-text set for route A.
