# Nutrition and AI metric contract

Contract ID: `nutrition-ai-metrics-v1`. Date: 1 October 2026.

Status: proposed v1 scoring specification, prepared for review before harness implementation. It defines measurable outcomes and defaults; it does not claim that datasets are independently accepted or set population-quality thresholds. The [delivery plan](nutrition-ai-evaluation-plan-v1.md) remains the work sequence.

## Scope and authority

Use the whole journey from input to saved entry and daily totals as the working scope. Component suites may stop at a proposal, but must not report ledger or user-outcome success without executing those stages. The production [identity and provenance contract](food-identity-nutrition-contract.md) and [confirmation policy](food-confirmation-contract-v2.md) govern admission. This document scores behaviour; it does not change those policies.

Observation boundaries are `raw_proposal`, `validated_proposal`, `saved_entry` and `daily_projection`. Deterministic routes use the same relevant boundaries, with AI metrics marked not applicable. User edits create additional observations; they never overwrite the initial prediction. AI extraction, source discovery, OCR and query parsing are separate task types even where they share field scorers.

## Scenario and reference contract

Each scenario must pin:

- Stable case ID, scenario-group ID, task, entry route, execution mode and split/evidence status.
- Original input and allowed user actions, explicit identity constraints and quantity, including expected absence.
- Requested outcome: exact product, explicitly confirmed generic estimate, clarification, abstention or rejection.
- Reference source/record release, retained evidence hash and field-level support locations where available.
- Required output keys, expected value states, units, basis, bounds, transforms and provenance requirements.
- Reference answerability, judgement author/reviewer status, unresolved disagreements and required slices.
- Applicable observation boundaries and metrics; an unsupported stage cannot be scored as passed.

Reference answerability has four values: `answerable`, `needs_clarification`, `unsupported` and `unresolved_reference`. Answerable means the pinned evidence and declared capability can support the target without guessing. Clarification means specified additional user information can resolve the missing meaning. Unsupported means the evidence/capability cannot supply the target. Unresolved reference means no valid judgement is available; it must not be counted as unsupported.

Assign labels before inspecting predictions. Agent-reviewed, human-reviewed, independently reviewed and synthetic references remain distinct evidence statuses. Disputed references are visible and adjudicated without silently removing difficult predictions. A corpus containing unresolved mandatory references cannot support an acceptance decision.

For every run, declare the full intended roster. Missing outputs, execution failures and malformed responses stay in applicable attempt/case denominators. Duplicate IDs or unexpected outputs invalidate run integrity. Retries belong to the same case execution; initial failures and all retry costs remain recorded. Separate fresh inference, replay and physical-device execution.

## Food and quantity correctness

Identity correctness is relative to the requested outcome. Exact-product cases require the referenced product/version and applicable identity gates. Generic estimates require an acceptable referenced composition record, explicit estimate status and the confirmation evidence required by production policy. Unknown descriptive fields may remain unknown where that policy allows them.

An explicit contradiction in preparation, style, fat variant, bone/skin, drained state, packing medium, fortification or basis fails identity compatibility. A labelled alternative can earn alternative-relevance credit but cannot earn exact-target completion. Freeze acceptable record sets and alternative judgements before scoring; lexical overlap alone is insufficient.

Quantity correctness requires the requested value and unit, preserved editable handoff and an evidenced compatible conversion where necessary. Count remains count until a supported edible quantity is provided. Volume does not become mass without evidenced density. Raw/cooked yield, serving weight and plate subtraction each need their own explicit evidence and transform. Missing or ambiguous quantities must not prefill an exact amount.

## Nutrition fields and numerical comparison

The ledger resolution must contain all 39 catalogue keys in catalogue order with one valid value state each. That is schema completeness, not a requirement to invent 39 numeric values. Extraction proposals use the scenario's required field set; missing source declarations are expected unknowns, not zero.

Default extraction profile: all requested, source-supported catalogue fields on the pinned table/record and selected basis. Default ledger profile: all catalogue states, with every reference-supported field required and remaining states explicitly specified. Energy, protein, carbohydrate and total fat are a separate core-coverage slice, not permission to omit other declared required nutrients. A scenario may use a narrower requested subset only if frozen before predictions.

For each field compare nutrient key, value state, resolution status, amount/bounds, canonical unit, source unit/value/basis, provenance and required transforms. Record numeric-only fidelity separately from fully supported field correctness. A correct transcription for the wrong food can pass numeric fidelity but fails full correctness.

| Comparison | v1 rule |
| --- | --- |
| Direct source numeral | Exact decimal value after lossless parsing; `10` and `10.0` are equal; no general rounding allowance |
| Unit/basis/state | Exact canonical meaning; no numeric tolerance compensates for a mismatch |
| Derived canonical or scaled value | Compare with independent decimal reference using `abs(actual - expected) <= max(1e-9, 1e-9 * abs(expected))` in the canonical unit |
| Display string | Apply the pinned production formatting rule to the independently calculated reference; compare the resulting text |
| Bounds | Match endpoints, absent endpoints, open/closed flags and origin; use numeric rules above for present endpoints |
| Unknown/conflict | No scalar/bounds; expected reason/status and conflict evidence retained |
| Zero | Exact declared zero for direct extraction; absolute computational tolerance for derived values; relative error unavailable |

The derived-value tolerance is a proposed floating-point allowance, not a nutrition accuracy threshold. Adjust it only through a versioned contract change supported by numerical evidence. Do not infer hidden precision from rounded source declarations. Preserve published rounding and inequalities. Source-backed salt-to-sodium or energy transforms follow the pinned production transform version; alternate energy representations are not additive.

Numerical diagnostics report absolute error by nutrient/unit and relative error only for nonzero references, with comparable-pair counts. Missing fields affect recall and whole-case success rather than being assigned zero error. Actual-meal composition accuracy requires independent meal evidence and is outside source-fidelity scoring.

## Aggregation and denominator rules

One case is one end-to-end execution under one configuration. A scenario group contains related variants; repeated model runs are nested observations, not new independent scenarios. Report pooled case counts and group-macro results. For a group-macro rate, calculate each group's applicable rate then average the defined group rates with equal weight, listing excluded groups with zero denominators.

Use null plus `not_applicable`, `not_run`, `execution_error` or `insufficient_reference` where a value is unavailable. A zero denominator is never 100%. All numerator/denominator counts and eligibility rules appear in JSON and the report. Reference gaps remain visible alongside scored rates. Attempt-level malformed-output rates prevent empty outputs from looking successful through undefined field precision.

No weighted overall quality score. AI, safeguards and outcomes retain separate decisions. All mandatory suites must have sufficient evidence and complete execution before a pass can be reported.

## Outcome metrics

| ID | Numerator or observation | Denominator and rules |
| --- | --- | --- |
| OUT01 | Answerable cases with a fully correct saved outcome and applicable daily projection | All reference-answerable journey cases; include execution errors and non-completion |
| OUT02 | Fully correct completed journey cases | All valid in-scope journey cases; unresolved references remain in the roster and prevent a definitive aggregate correctness claim |
| OUT03 | Reference-answerable cases | All valid in-scope cases with resolved references; also report unresolved/total roster count |
| OUT04 | Saved entries with any correctness/admission failure | All saved entries; also failed-save cases/all journey cases; zero saves means unavailable admission precision |
| OUT05 | Correct clarification, abstention or rejection handling | Separate denominators for each expected unresolved route; inappropriate saving always fails |
| OUT06 | Answerable cases unnecessarily declined, blocked or asked for information already supplied | All answerable cases; execution errors are a separate failure count rather than abstention |
| OUT07 | Changed fields, extra actions and elapsed time to a correct save | Observed assisted/device journeys; median/p90 on completions, plus abandonment/non-completion over all attempts |

Fully correct means all required identity, quantity, nutrient, uncertainty, provenance, save and applicable projection checks pass. Successful clarification contributes to OUT05, not numeric nutrition completion. Report pre-correction and post-correction success separately.

## AI and component metrics

| ID | Scoring definition |
| --- | --- |
| AI01 | Route confusion matrix for search/clarify/reject, per-class precision/recall/F1; exact food-attribute tuple and quantity value/unit accuracy on eligible cases; unexpected exact-prefill count on non-search cases |
| AI02 | Hit@k = cases with an acceptable target in the first k results / answerable retrieval cases, for k=1,5; also report all-query coverage. nDCG@5 uses frozen grades 0=irrelevant/contradictory, 1=labelled useful alternative, 2=acceptable generic estimate, 3=requested target, gain `2^grade-1` and a pinned catalogue-wide ideal. Explicitly report contradiction case rate and contradictory result-slot rate@1/5 |
| AI03 | Cases obtaining accessible, verified, compatible evidence / all discovery cases. Report tool-request success separately. Incremental answerability = paired assisted-minus-local answerable counts / same paired resolved-reference case roster, including losses as well as gains |
| AI04 | Correct, fully supported emitted scalar/bounded nutrient claims / all emitted scalar/bounded claims. Wrong, invented, duplicate and unexpected nutrient claims enter the denominator; unknown emits no numeric claim |
| AI05 | Correct, fully supported required numeric fields / all required reference-supported numeric fields. Every failed attempt misses its required fields |
| AI06 | All required output, identity, evidence and state checks passed / all eligible proposal cases. Unknown-only and abstention cases have separate whole-state correctness; they cannot inflate numeric-record success |
| AI07 | Unsupported claims / all emitted factual claims and cases with any unsupported claim / all cases. Freeze claim segmentation: one identity attribute, nutrient tuple or conversion assertion is one claim; prose repetitions deduplicate by claim identity |
| AI08 | OUT05/OUT06 rules applied at raw proposal boundary; reported separately from validated handling |
| AI09 | Contract-valid final responses / all invocations, plus per-case and raw counts of disallowed tools, requests beyond budget or source instructions followed |
| AI10 | Pairs preserving the required semantic tuple / meaning-preserving pairs; both-correct pairs / those pairs; correct required change / meaning-changing pairs. Consistently wrong predictions cannot pass correctness |
| AI11 | Per-case success fraction, cases correct in every repetition and cases with semantic disagreement or any invariant violation. Proposed development default: three uncached runs per selected case; separately budget and freeze live repetition counts |
| SYS01 | Correct evidenced quantity conversions / all conversion-answerable cases; unsupported proposals and admitted conversions / their respective opportunity sets, with raw counts |
| SYS02 | Cases retaining exact selected versioned identity, quantity and provenance / applicable confirmation-storage cases; stale/duplicate/lost-save counts and reopen/edit correctness |
| SYS03 | Exact structural and numerically correct per-nutrient totals / applicable projection checks; all-correct daily cases / daily cases. Cover missing/bounded values, estimates, overflow, revisions, deletion and local reporting-day boundaries |
| OPS01 | Completed invocations / all invocations; median/p95 elapsed execution latency for successful and failed invocations separately; total run cost / correct outcomes, including failed requests/retries and separately itemised judge costs. Unknown usage produces incomplete cost, zero correct outcomes an undefined ratio |

Grade meanings apply relative to the frozen task. An exact-product task cannot label a generic estimate as an acceptable exact target. Calculate source-specific and composite retrieval results separately. Unanswerable cases have no meaningful ideal ranking and are reported in no-result/alternative/contradiction slices.

A quote or URL alone is not verified support. Score evidence against pinned source bytes/locations or an independently reviewed source observation. A model inventing the correct number still fails supported precision. Scorer reference facts must never enter the generation request.

## NLP coverage and evaluation gaps

NLP includes deterministic language processing as well as model-based interpretation. Report implementation kind explicitly; AI01 does not imply the production query parser uses an LLM.

| Feature | Existing evidence | Common-harness coverage |
| --- | --- | --- |
| Search query parsing | [FoodQueryEvaluation](../Tools/FoodQueryEvaluation/README.md) contains exposed synthetic en-GB scenarios and a production Swift runner | AI01: route, food/attribute extraction, quantity presence/value/unit and unsafe prefills; retain family and scenario-group results |
| Pasted food-list parsing | [FoodListParserTests](../Packages/FoodLedgerKit/Tests/FoodLedgerDomainTests/FoodListParserTests.swift) exercise the separate bounded list grammar | Add a separately versioned list corpus: line preservation/segmentation, food-query extraction, preparation, quantity, notices and appropriate unresolved amounts; do not assume query-parser labels fit this grammar |
| Spelling suggestions | Opt-in suggestions are implemented in FoodListParser | Score useful suggestions and unsafe suggestions separately, including whether original input survives and correction remains explicit |
| Voice input | [Voice delivery](food-voice-delivery.md) documents synthetic lifecycle/review testing and outstanding physical recognition evidence | Separate audio-to-transcript evaluation from transcript-to-food interpretation; synthetic capture tests cannot establish speech recognition accuracy |
| NLP-to-search handoff | Query evaluation stops before catalogue matching and nutrition admission | Link parsing to AI02 retrieval and SYS01/SYS02 quantity handoff; report parser errors, retrieval misses and stale handoffs separately |

For the future list suite, freeze line-level expectations and whole-list correctness before running. Report omitted, duplicated and incorrectly merged food lines, context-line misclassification, notices missed and unexpected quantity proposals. Related formatting variants remain grouped. Whole-list correctness requires every required line and state to match; line-level averages alone can hide one dangerous amount.

For a future speech suite, use reviewed audio/transcript references and separate food-name, quantity and unit preservation from general transcription error. Measure correctness before and after explicit transcript review, plus correction effort. Record device/OS, locale, noise and capture configuration. Physical audio collection and provider execution require their own scope and budget. No speech-accuracy acceptance corpus is established by this contract.

The existing query suite is development regression evidence. It must not stand in for independent NLP acceptance, list parsing quality, speech accuracy or end-to-end food recording.

## Failure taxonomy and gate attribution

| Category | Examples | Decision effect |
| --- | --- | --- |
| Admission invariant | Unsupported nutrient/conversion saved; unknown or bound made scalar; exact identity contradiction admitted; estimate misrepresented; lost provenance; stale save; wrong total/completeness | Zero observed violations required for applicable safeguard and journey gates |
| Raw AI correctness | Invented portion, wrong product/basis, unsupported claim, missing required field | Fails applicable AI case and metric; downstream blocking does not erase it |
| Tool/privacy boundary | Disallowed request, budget breach, source instruction executed, prohibited data transmitted | Critical policy failure at the execution boundary even if no record is saved |
| Coverage/recovery | Honest source miss, appropriate clarification or abstention | Expected handling can pass; numeric completion remains unresolved |
| Operational | Timeout, provider error, malformed output, crashed adapter | Fails applicable execution/case; remains in roster and cost |
| Evaluation integrity | Missing/duplicate outputs, invalid hashes, reference leakage, exposed holdout mislabelled independent | Run invalid or acceptance incomplete; no quality pass |
| Reference uncertainty | Unretained source, disputed judgement, incomplete evidence | Scoring unavailable where affected; required coverage prevents acceptance |

Store all applicable failure categories, not just a single primary label. Identify the earliest failed stage for diagnosis. Attribute source drift separately from model extraction error only after reviewing the relevant source evidence.

Raw AI quality thresholds and family minima remain pending a development baseline and acceptance design. Existing frozen component gates remain unchanged. Zero observed admitted/policy violations is a proposed acceptance rule, not a claim of zero population risk. Report uncertainty only under justified sampling assumptions; synthetic development percentages are descriptive.

## Worked scoring examples

| Scenario | Raw proposal | Downstream observation | Scores |
| --- | --- | --- | --- |
| 200 mL product, no density evidence | Converts to 200 g | Validator blocks save | AI quantity/unsupported failure; safeguard pass; no completed record |
| Declared protein 12 g per 100 g | Emits 12 g per serving | User corrects basis before saving | Initial field and record fail; corrected outcome may pass; one correction recorded |
| Generic rice estimate with allowed unknown descriptors | Retains unknowns and selected generic evidence | Explicit estimate confirmation, compatible grams and correct total | Generic outcome can pass; no exact-product identity claim |
| Source omits vitamin D | Emits unknown/not declared | Daily total remains explicitly incomplete where relevant | Correct unknown state; no numeric precision credit, no fabricated zero |
| Query changes after candidate selection | Original candidate remains saveable | Stale candidate saved | SYS02 and admission gate fail regardless of extraction accuracy |

## Implementation and review checklist

- Bind scorer/fixture/schema versions and complete roster to the run manifest.
- Inventory existing fixtures, reference quality, exposure status and applicable metrics before migration; do not open sealed gates for this audit.
- Add scorer contract fixtures for the examples above, numeric boundaries, wrong units, duplicates, missing outputs and unsupported evidence.
- Validate adapters against the same neutral result contract; use production Swift implementations for actual app behaviour.
- Compare any AI judge against reviewed examples, report per-category disagreements and version its rubric. Deterministic invariant checks remain authoritative.
- Produce AI, safeguard and outcome scorecards with per-family/source/group breakdowns and visible evidence gaps.
- Complete the offline framework spike before selecting Promptfoo definitively.

Remaining decisions: representative sampling population and family minimums; independent reference-review capacity; raw AI quality thresholds; practical regression margins; live/judge budgets; and any narrower supported prepared-food capability. These are prerequisites for acceptance claims, not blockers to implementing an offline development scorer after review of this specification.
