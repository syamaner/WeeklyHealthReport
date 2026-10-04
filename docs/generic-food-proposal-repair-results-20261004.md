# Generic food proposal repair and evaluation — 4 October 2026

The authorised repair is implemented and verified locally on upstream `79efe83526668e47608e33cbf00655638c2d4826` (PRs #180–183). Nutrition changes remain uncommitted in the isolated `nutrition-generic-review` worktree. The shared checkout is untouched. No release, device installation or policy publication occurred.

## Behaviour repaired

The app uses OpenRouter throughout: Luna/Azure with Exa for discovery, Luna for source choice, Grok/xAI for extraction, then a mandatory Luna applicability check. No Gemini or Jev request is composed. The same OpenRouter credential covers all four bounded requests; a supplied source URL skips the first two. There are no automatic retries.

The separate checker assesses product identity, exclusions, denominator and nutrient meaning against captured evidence. A mismatch, uncertainty, malformed response or unavailable checker prevents confirmation; the extractor cannot supply a fallback approval. Deterministic query-basis checks also guard preparation and retained confirmation scope. All proposals remain inspectable and explicit human review remains required. These are fallible model judgements, not certified facts.

Literal binding v7 accepts `mls`, exact paired kJ/kcal column structures and explicit scalar/structural unit labels. Wrong columns, partial evidence, bounded or approximate values remain unsupported. Missing units/nutrients remain unknown. No salt-to-sodium, kJ, density or portion-weight inference was added. Selection has no numerical confidence: categorical support is not a calibrated probability.

Versions: extraction prompt v11; adapter v4; applicability v1; query basis v1; choice policy v2; confirmation admission v5. The existing schema remains v5. The [architecture gate](generic-food-proposal-repair-v2.md) records responsibilities and invariants.

## Evaluation results

| Evidence | Result | Interpretation |
| --- | --- | --- |
| Original prospective holdout | 13/20 captured cases; 20/24 captured; search 4/6 | Historical failed result, unchanged |
| Exposed 20-case regression, frozen v6/v10 | Extractor 18/20; checked route 17/20; all 6 required abstentions correct | Improvement over historical 13/20, but exposed development evidence; the checker also lost one correct answer |
| Fresh 12-case follow-up, frozen v7/v11 | 11/12 captured; 10/11 correct captured; 10/12 including acquisition failure | All predeclared follow-up gates passed; 6/7 answerable panels and 4/4 abstentions correct |
| Fresh six-query search | Matching primary product/market source at rank 1 on 6/6 | Search-only evidence, not six completed capture/review workflows |
| Exposed Weetabix full flow | Four calls completed in 28.27 seconds; c1 eligible for explicit confirmation | Composition/availability evidence; no save performed |

The fresh follow-up has four UK/local, four Taiwan-market and four general cases. UK/local passed 4/4, Taiwan 3/4, and general 3/3 captured (3/4 including capture failure). It recovered 25/30 required known fields, with 25/25 declared fields correct, 11/12 required unknown fields preserved and zero unknowns promoted to invented known values. The missing answer accounts for the unrecovered fields and unknown. Precision alone is not coverage.

The fresh roster, capture attempts, source references, historical overlap inventory, executable and source snapshot were frozen before inference. The audit checked against 36 retained development plans. The initial protocol names prompt v10; a recorded pre-inference source-review amendment added generic unit layouts in v11/binding v7 before freezing the executable. This is source-aware preparation, not evidence of unseen-layout generalisation. The v6/v10 regression was not rerun or relabelled as v7. No reference or historical result was edited after seeing its prediction.

This is a purposive, agent-reviewed 12-case follow-up, not a random population sample or independent human acceptance set. Its gates do not erase the earlier failed 24-case qualification. It supplies no calibrated confidence or fresh PDF/OCR coverage. On this small follow-up, extraction and the checked route tied; a causal benefit from the checker is not demonstrated.

### Retained failures and adjudication

* **Topcake taro pastry:** the fresh source prints inconsistent per-50g/per-100g figures. Both models requested clarification. Gold expects the printed 100g panel, so this remains a scored failure. No arithmetic correction or replacement was made.
* **Hershey cocoa:** the predeclared capture URL ended in `.html.html` and returned HTTP 406. It remains in the 12-case denominator. Later discovery found the canonical `.html` URL; there was no replacement or retry.
* **Jolly Time and Whitworths:** the exposed regression conservatively abstained because of serving/basis or cross-column source ambiguity. Whitworths is a checker-induced loss against the extractor arm.
* **Mutti:** the extracted name `Finely Chopped Tomatoes - Polpa` is present in source JSON-LD but absent from frozen allowed aliases. Strict scoring counts the identity and five associated nutrient claims incorrect. Values and 125ml basis match the retained source; this is a diagnostic reference-alias issue, not five independently wrong numbers. Gold remains unchanged: primary score is 17/20, not the alias-adjudicated 18/20.

Partial answers remain deliberate. For example, Rowse honey has only one supported target value under the literal-unit contract, and US Calories without an explicit kcal unit remain unknown. Image-only nutrition and pages without a numeric panel abstain. The Oatly 100g request against a 100ml source also abstains rather than inferring density.

### Source and evidence ledger

The local evidence root is `/Users/sertanyamaner/Documents/ChatGPT/New project/nutrition-structured-proposals-v1/generic-source-v1/repair-20261004-v2`.

* `regression-run/`: immutable plan, executable/source snapshot, 20 cases and score.
* `fresh-12/`: predeclared protocol and roster; raw/projected source review; capture failures; frozen extraction/search plans; scores and `discovery-adjudication.json`.
* `workflow-plan.json`, `workflow-result/`, `workflow-completion.json`: four-call end-to-end trace, capture, hashes and confirmation guard result.
* `verification.json`: all 66 request/response hashes and response-reported costs, 888 snapshot-file checks, 248 output-file checks and 13 capture-body checks. All 158 fresh frozen package source/configuration files match current code.

The six successful primary search matches are [Weetabix](https://weetabix.co.uk/our-products/weetabix/weetabix/), [Topcake](https://www.topcake.com.tw/product/Taro-Pastry), [Hershey](https://www.hersheyland.com/products/hersheys-cocoa-100-cacao-natural-unsweetened-8-oz-can.html), [Salico](https://www.salico.com.tw/pages/nutrition-facts), [Lurpak Australia](https://www.lurpak.com/en-au/products/lurpak-slightly-salted-butter-250g/) and [Oatly UK](https://www.oatly.com/en-gb/products/cream/creamy-oat-organic-250ml). These are identity/search references; values are assessed against retained captures, not mutable live pages.

The evaluator's legacy `jev` result keys mean the selected arm for compatibility. These new runs explicitly record `selector_route=applicability` and the `selected` aggregate. No Jev inference occurred.

## Validation and cost

* Final production package gate: 694 tests, 5 expected opt-in skips, no failures. The subsequent test-only replay update passed all 3 opt-in workflow tests, including strict current-request equality for the new four-call trace. Historical replays intentionally ignore changed system instructions and prove only payload/schema/route handling and current confirmation guards, not new-prompt inference.
* Evaluator: 114 Python tests passed. Focused literal-unit suite: 24 passed.
* Simulator: 315 tests, 314 passed and one expected opt-in skip. Xcode static analysis succeeded. No production changes followed this gate; later changes were replay tests and documentation.
* Bundled privacy text matches the updated local policy. The final verification manifest retains source and test/log hashes. No physical-device or new interactive accessibility acceptance is claimed.

| New bounded run | Calls | Reported USD |
| --- | ---: | ---: |
| Exposed regression | 37 | 0.556097725 |
| Fresh extraction/check | 19 | 0.286024400 |
| Fresh search | 6 | 0.043483800 |
| Exposed full workflow | 4 | 0.036108025 |
| **Total** | **66** | **0.921713950** |

All 66 new costs are known and verified against response `usage.cost`; receipt floating-point representations agree within $0.000000000001. Cumulative retained evidence is 453 requests, 447 known costs totalling $4.337129375, plus six historical unknown costs. These are provider-reported charges, not an account balance or ChatGPT subscription cost. No further paid calls are needed for this repair.

## Handoff

The next acceptance boundary is independent review of representative sources and eventual physical-device/accessibility testing after relevant coding and merges finish. Preserve conservative failures and source uncertainty. Do not add site-specific parsers or weaken unknown/basis rules to raise a score. A future reference-alias correction must be separately versioned. No commit, push or distribution is authorised by this chat.
