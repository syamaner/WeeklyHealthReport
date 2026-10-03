# Nutrition and AI evaluation plan

Date: 1 October 2026. Status: v1 metric specification and inventory prepared; the first offline Promptfoo spike is implemented and verified. Acceptance thresholds and independent evidence design remain open.

The [v1 metric contract](nutrition-ai-metric-contract-v1.md) defines the working scope, exact scoring rules, field profiles, numerical tolerances, denominator rules and failure attribution. The metric tables below are an overview; the contract is the detailed specification for review and the future offline spike.

The [local evaluation inventory](nutrition-ai-evaluation-inventory-v1.md) maps existing suites and test evidence to those metrics, records baseline compatibility and exposure status, and provides the implementation checklist for the offline spike. The inventory audit is complete; no fresh quality run was made.

The [offline spike result](nutrition-ai-offline-spike-v1.md) records the first executed integration: 511 parser regressions, 20 historical extraction cases and two production save-service probes in one report. The [runner](../Tools/NutritionEvaluationSpike/README.md) documents local execution and its evidence boundaries.

This plan defines a common evaluation contract for the nutrition journey and its AI components, followed by a staged harness that produces a meaningful local report. The immediate priority is to agree what is measured and how it is judged. Promptfoo is the provisional runner choice, subject to a small offline integration spike.

Success means that a user can record the intended food and quantity, with nutrition supported by the selected evidence and with estimates, missing values and unresolved ambiguity represented honestly. A generic composition estimate and an exact branded-product match are distinct outcomes and must be scored separately.

## Scope and decision status

- Include AI capability, application safeguards and the resulting user outcome in one evaluation framework.
- Working scope: the journey through confirmation, stored entries and daily totals, as specified in the v1 metric contract; proposal-only evaluation remains a useful component suite.
- Evaluate both initial proposals and final reviewed outcomes. User corrections cannot retroactively make an initial prediction correct.
- Keep offline replay, fresh local execution, live provider/source runs and physical-device results separate.
- The user subsequently authorised the local offline spike, including its pinned temporary framework installation. Provider calls, spend, personal-data transmission, publication and remote repository changes remain outside this phase.
- HealthKit metrics, medical interpretation and changes to nutrition-admission policy are outside this plan.

## Existing material to preserve

The repository already contains useful component evaluations. Inventory their exact revisions and contracts before migration; recorded results are historical checkpoints, not results from this plan.

| Material | Starting use | Limit to preserve |
| --- | --- | --- |
| [Food query evaluation](../Tools/FoodQueryEvaluation/README.md) | Parsing, routing and quantity scoring | Exposed synthetic scenarios are development regressions, not independent acceptance |
| [Search quality evaluation](../Tools/FoodSearchQuality/README.md) | Ranked retrieval and source coverage | Broad food relevance does not establish exact identity or variant correctness |
| [Generic food match evaluation](generic-food-match-evaluation.md) | Existing matching judgements and policy | Preserve historical contracts and result provenance |
| [OCR evaluation](../Tools/FoodOCREvaluation/README.md) | Structured panel extraction and correction workflow | Respect existing frozen splits, gate history and family-coverage requirements |
| [Gemini nutrition extraction evaluation](../Tools/GeminiNutritionExtractionEvaluation/README.md) | Source-supported field extraction and abstention | Experimental outputs are not app nutrition-admission evidence |
| [Local hybrid evaluation](../Tools/LocalHybridSearchEvaluation/README.md) | Local versus assisted candidate coverage | Distinguish verified leads from admitted nutrient records |

Some experimental directories were untracked in the checkout inspected for planning. Their inclusion here does not establish a committed, reproducible baseline. Freeze the intended files and hashes before integrating them.

Existing [identity and provenance rules](food-identity-nutrition-contract.md) and [confirmation policy](food-confirmation-contract-v2.md) remain authoritative. This evaluation plan does not silently change them.

## Three scorecards and observation points

| Scorecard | Question |
| --- | --- |
| AI capability | Does the AI understand, discover, extract and qualify information correctly? |
| Application safeguards | Does the application admit supported information and block unsupported information correctly? |
| User outcome | Can the user complete a correct record with reasonable effort? |

Capture raw AI proposal, validated proposal and final recorded outcome as separate observations linked to one scenario. Also retain deterministic-only route results so AI assistance can be compared with a meaningful baseline.

Example: a model invents a portion weight and the validator rejects it. Record an AI unsupported-conversion failure, a successful safeguard and an unresolved user journey. Do not collapse these into one pass. Tool errors, timeouts and invalid output are explicit failures or unavailable results, never silently excluded cases.

## Proposed outcome metrics

Answerability must be independently labelled against the declared capability and pinned reference sources before inspecting predictions. An unavailable reference is an evidence gap, not proof that a scenario is unanswerable.

| ID | Metric | Definition |
| --- | --- | --- |
| OUT01 | Correct completion on answerable scenarios | Fully correct recorded outcomes divided by reference-answerable scenarios |
| OUT02 | Overall correct completion | Fully correct recorded outcomes divided by all valid in-scope scenarios, including coverage gaps |
| OUT03 | Answerable coverage | Scenarios with sufficient compatible evidence in the evaluated sources divided by all valid in-scope scenarios |
| OUT04 | Incorrect admission | Incorrect or unsupported recorded outcomes divided by all recorded outcomes; include the raw count and rate over all scenarios |
| OUT05 | Appropriate clarification or abstention | Correctly handled unresolved scenarios divided by scenarios requiring clarification or abstention; report the two routes separately |
| OUT06 | Unnecessary abstention | Answerable scenarios unnecessarily declined or blocked divided by answerable scenarios |
| OUT07 | Correction burden | Field corrections, additional interactions and median/p90 time to a correct record; report abandonment and non-completion separately |

A fully correct outcome satisfies identity, explicit constraints, quantity, nutrient evidence, provenance, uncertainty representation and stored-result requirements. Define the required nutrient fields per scenario before scoring; an empty record cannot obtain full correctness merely by avoiding false claims.

## Proposed AI and component metrics

| ID | Metric | Definition and scoring boundary |
| --- | --- | --- |
| AI01 | Intent interpretation | Route confusion matrix and per-class precision/recall; exact identity attributes and quantity value/unit; unexpected quantity-prefill count |
| AI02 | Identity-compatible retrieval | Hit@1/5 on independently labelled acceptable records; nDCG@5 with a frozen relevance rubric; explicit contradiction exposure@1/5 |
| AI03 | Grounded discovery | Attempts yielding accessible, independently verified, identity-compatible evidence divided by discovery attempts; incremental answerable coverage against the same local-only cases |
| AI04 | Supported-field precision | Correct and supported emitted nutrient fields divided by all emitted nutrient fields |
| AI05 | Supported-field recall | Correct and supported recovered fields divided by reference-supported required fields |
| AI06 | Whole-record correctness | Cases satisfying every required field, identity, source, preparation, status and basis condition divided by eligible cases |
| AI07 | Unsupported claims | Unsupported emitted claims divided by emitted claims, plus cases containing any unsupported claim divided by cases; separate identity, nutrient and conversion claims |
| AI08 | Uncertainty handling | Appropriate clarification/abstention and unnecessary abstention at the raw proposal boundary, separate from downstream safeguard behaviour |
| AI09 | Schema and tool compliance | Contract-valid responses divided by attempts; counts of tool, request-budget and source-instruction violations |
| AI10 | Robustness | Paired semantic consistency under meaning-preserving changes; correctness under deliberate changes of food, quantity or evidence |
| AI11 | Repeatability | Per-case correctness across a predefined number of fresh runs, disagreement rate and cases with any invariant violation |
| SYS01 | Quantity conversion | Correct conversions divided by reference-supported conversions; unsupported conversions proposed and admitted reported separately |
| SYS02 | Confirmation and storage | Preservation of selected identity, quantity and provenance; stale selections, duplicate saves and lost saves |
| SYS03 | Daily totals | Per-nutrient arithmetic and completeness/estimate-state correctness, including edits, deletions and reporting-day boundaries |
| OPS01 | Runtime and efficiency | Completion/failure rate; median/p95 latency; requests, tokens and observed cost per correct outcome; show successful and failed attempt distributions |

For OPS01, cost includes failed attempts, retries and separately identified judging cost. Missing usage remains unknown. Report replay timing separately from fresh inference latency. Independent repetitions must bypass inference caches; cache configuration belongs in the manifest.

For AI04–AI06, a correct field is the tuple of nutrient, value/state, canonical unit, denominator or basis, inequality/bounds and supporting evidence. A matching number from the wrong column fails. Missing output reduces recall; extra unsupported output reduces precision. Malformed responses and execution failures remain visible in attempt-level metrics even when field metrics are undefined.

Keep source fidelity separate from food representativeness. Correctly copying a generic composition record does not establish the actual composition of a meal. Do not use a generic reference value as ground truth for a specific meal without an appropriate evidence contract.

Measure numerical error per nutrient and canonical unit, with predeclared absolute/relative tolerances and explicit zero handling. Do not average calories, grams and micrograms together. Source rounding, bounds and unknown states need explicit rules rather than a universal percentage tolerance.

## Invariants and acceptance thresholds

Proposed hard gate: zero observed violations in the applicable regression and acceptance suites for unsupported admitted nutrients or conversions, unknown-to-zero substitution, contradictory exact identity, estimates misrepresented as measured values, lost provenance, stale-selection saves, incorrect ledger arithmetic and misleading completeness states.

Raw AI failures and admitted failures have separate gates. A blocked AI error still reduces AI quality and may reduce completion, while demonstrating a working safeguard. Freeze any raw-output failure thresholds by task before acceptance evaluation.

Quality thresholds, family minimums, uncertainty levels and practical regression margins remain to be agreed. Do not select them by looking at holdout results or weaken existing frozen gates. Establish development baselines first, then freeze the acceptance contract before opening independent acceptance data.

Every metric contract must specify population, unit of analysis, numerator, denominator, exclusions, reference rules, tolerance, aggregation, required slices, direction of improvement and gate. Zero denominators produce unavailable values, not perfect scores. Missing mandatory suites or inadequate reference coverage make the overall decision incomplete.

Report counts and confidence intervals where the sampling assumptions support them. Group related examples rather than treating paraphrases or repeated photographs as independent observations. Zero observed errors is not proof of zero real-world risk. Population-wide claims require a defensible sampling population, not just synthetic challenge cases.

## Data and judgement strategy

Maintain development/tuning, exposed regression, independent acceptance and device-usability collections with explicit evidence status. Preserve historical results and labels. Once acceptance examples influence a repair, treat them as exposed for subsequent evaluation; use new independent material for renewed generalisation claims.

Keep related queries, photographs of the same panel, product variants and templates in the same split where they could leak answers. Retain stable scenario-group identifiers and review source overlap between splits. Use existing reviewed evidence where appropriate; gaps are recorded before commissioning further labelling.

Minimum slices include entry route, generic versus exact product, source/provider, food family, preparation/style/fat variants, count/mass/volume, missing conversion, bounded/unknown/conflicting values and execution mode. Include prepared and mixed foods only within explicitly declared capabilities; otherwise evaluate the expected clarification or unsupported route.

Use deterministic scoring for exact fields, schema and invariants. Use independently reviewed judgements for identity equivalence, source support and ambiguity, with explicit adjudication for disagreements. AI judges may assist semantic review after comparison with a human-labelled subset. Pin judge model, prompt and rubric; measure agreement and failure patterns. No AI judge is the sole authority for nutrition admission correctness. Missing evidence cannot be replaced with a confident judge score.

Run fixed-evidence extraction separately from live discovery. Fixed evidence isolates extraction and reasoning; live discovery adds source availability and tool reliability. Source text is untrusted data, including adversarial instructions embedded in fixtures. Include paraphrase, distractor, contradictory-evidence and prompt-injection cases in designated challenge slices.

## Framework choice

Provisional recommendation: Promptfoo for execution, model/prompt comparisons and local inspection, with repository-owned nutrition scorers. Validate this choice before migrating suites.

| Candidate | Relevant capability | Proposed role |
| --- | --- | --- |
| [Promptfoo](https://www.promptfoo.dev/docs/configuration/expected-outputs/) | Custom assertions and application adapters, comparison workflows | Initial runner candidate |
| [DeepEval](https://deepeval.com/docs/introduction) | Python/pytest-style evaluation, custom and judged metrics, component and trajectory evaluation | Alternative if Python-native integration proves materially simpler |
| [RAGAS](https://docs.ragas.io/en/stable/concepts/) | Grounding/retrieval metrics and custom experiments | Optional selected metric implementation; no additional dependency until justified |
| [Inspect AI](https://inspect.aisi.org.uk/) | Programmable model/tool tasks and custom scoring | Alternative if multi-step agent evaluation becomes central |

These are fit assessments based on documentation inspected during planning, not comparative benchmarks. Built-in faithfulness scores do not establish product identity, portion correctness or nutrition admission. Avoid adopting several frameworks merely to obtain overlapping metrics.

Promptfoo documents [Python providers](https://www.promptfoo.dev/docs/providers/python/) and [HTML/JSON outputs with a local viewer](https://www.promptfoo.dev/docs/configuration/outputs/). The proposed adapter would invoke production Swift code or consume retained structured results. Do not reimplement app behaviour in Python. A local viewer does not make configured model/judge calls offline; the offline profile must prevent those calls explicitly.

## Architecture gate for the future harness

Responsibilities and dependency direction:

1. Versioned scenario and reference contracts define evidence and intended behaviour.
2. Execution adapters invoke the production Swift runner, retained replay or authorised live providers.
3. Pure scorers consume structured observations and references.
4. Orchestration schedules suites, records provenance and enforces execution budgets.
5. Reporting projects results into comparison views and machine-readable artefacts.

Keep framework and provider types at adapter boundaries. Domain correctness and nutrition policy remain in their existing modules; the app must not depend on the evaluation framework. Scorer contracts, unknown semantics, identity/provenance rules and result-schema versions are intentionally closed. Runner, provider, source acquisition, judge and report renderer are credible extension points.

Contract-test adapters against the same scenario/result schema. Validate unique IDs, expected case counts, missing/duplicate outputs, error classification and replay equivalence. Test scorers with deliberately wrong identity, basis, units, bounds, invented portions and missing evidence. Test that aggregate success cannot hide a hard-gate failure or omitted suite. Inject clocks and seeds where needed for reproducibility.

Keep the integration thin: a small adapter and reporting layer around established runners and scorers. Revisit the framework choice if the spike requires extensive replacement infrastructure.

## Report contract

The eventual one-command report should contain:

- Separate AI, safeguard and user-outcome scorecards, with pass/fail/incomplete/not-run status.
- Numerators and denominators, required family/source slices, justified uncertainty estimates and comparable baseline deltas.
- Hard-gate violations shown independently of averages, plus case-level inputs, observations, reference evidence and failure reasons.
- Separate initial versus corrected outcomes, fixed-evidence versus live results and offline versus device evidence.
- Runtime and cost including retries and judging, with unavailable measurements labelled.
- A manifest binding code revision and dirty state/content hashes, source/corpus/label hashes, scorer/schema versions, model/prompt/judge configuration, dependency versions, seeds, cache settings and environment/device details where relevant.
- Local HTML for review and structured JSON for replay and CI; a stable summary schema for later longitudinal comparison.

Preserve an immutable run directory and link comparable prior runs. If corpus or metric definitions change, either rescore both runs under the same contract or mark the comparison non-comparable. Diagnostic reruns must not overwrite original predictions. Personal evidence and secrets must not enter shareable reports; define retention and redaction before any sensitive run.

## Delivery sequence

| Phase | Work | Exit condition |
| --- | --- | --- |
| 1. Metric agreement | Resolve scope, define metric contracts and required fields, audit existing labels and contracts | Reviewed definitions and explicit unresolved evidence gaps; no new harness code required |
| 2. Offline framework spike | Integrate one parser suite, one retained extraction suite and a deliberate unsupported-conversion case | One local command, HTML/JSON report, correct stage attribution, reproducible scoring and no network/provider calls |
| 3. Common harness | Add adapters for retained suites, shared manifests, baseline comparison and hard-gate aggregation | Complete suite inventory; missing/error cases visible; scorer and adapter contract tests pass |
| 4. Development baseline | Run the agreed local suites and inspect family failures | Baseline frozen with exact provenance; quality thresholds and acceptance design agreed before holdout exposure |
| 5. Independent and live evaluation | Execute frozen acceptance and separately authorised live/device profiles | Evidence sufficient for the defined claim, or an explicit incomplete/fail decision with causes |
| 6. Routine operation | Document local command, CI subset, bounded live cadence and regression workflow | Reproducible runbook; clear ownership of labels, thresholds, judge changes and baseline promotion |

The v1 metric specification and local inventory audit are prepared, and the offline integration spike is implemented and verified. Metric review and independent acceptance design remain open. The next phase is the common harness; provider/source requests require a separately agreed request/spend/data budget. Device evaluation remains necessary for physical capture behaviour and measured user effort.

## Decisions to resolve next

- Review the v1 contract's whole-journey scope, required-field profiles and numerical comparison defaults, including bounded and unknown states.
- Select representative populations, required slices, independent reference-review process and coverage minimums.
- Agree critical-failure taxonomy, raw AI thresholds, quality thresholds and regression margins after the development baseline but before acceptance exposure.
- Retain Promptfoo as the recommended development runner following the successful spike; define whether any semantic judge is necessary and its validation/budget.
- Decide how local untracked experimental assets become a reproducible baseline without absorbing unrelated development changes.

## Method references

- [Scikit-learn evaluation guidance](https://scikit-learn.org/stable/modules/cross_validation.html) for holdout leakage and grouped evaluation principles.
- [NIST exact binomial confidence limits](https://itl.nist.gov/div898/software/dataplot/refman2/auxillar/exacbici.htm) for uncertainty with small samples or rare failures, where independent binomial assumptions apply.
- [RAGAS faithfulness](https://docs.ragas.io/en/stable/concepts/metrics/available_metrics/faithfulness/) for one possible grounding diagnostic, not a substitute for nutrition-specific correctness.

## Current offline composition

The [current-profile command](../Tools/NutritionEvaluationSpike/README.md#current-private-development-profile)
now runs the reviewed production NLP and bundled retrieval adapters in one fresh
outside-Git snapshot, verifies retained source-page bytes and checks acceptance
readiness. It projects AI components, exercised safeguards and unrun user outcomes
separately. Missing profiles keep overall acceptance incomplete; known safeguard
failures remain explicit even when another suite is malformed or absent.

This is a thin composition of existing runners and scorers. It does not migrate
sealed corpora, install another framework, execute provider AI, infer nutrition
fidelity from hash integrity or relabel historical framework output as a fresh
run. Provider/judge, OCR, voice, complete save/totals, physical capture and
independent acceptance remain distinct delivery/evidence gaps. Acceptance
preparation pins are never refreshed automatically after implementation drift.

### Fixed-source extraction evaluation, 2 October 2026

The current offline composition now supports one frozen manufacturer table through
an evaluation-only adapter. Freeze source hash, bases, required declarations,
explicit unknowns and cell-level support before observing its output. Report exact
decimal transcription and fully supported fields separately, plus whole-source
success. Scorer fault injections check wrong basis, missing fields, invented zeros,
unsupported scoop conversion, wrong units and wrong columns. These are synthetic
scorer checks; production blocking and fresh model quality remain unrun.

The architecture gate keeps the scorer pure, the restricted HTML reader substitutable
and private file orchestration at the composition boundary. Versioned source identity,
state, units, basis, roster and provenance contracts cannot be overridden by an adapter.
Synthetic behavioural tests protect missing/duplicate outputs, ambiguous layouts,
wrong basis/unit/support and explicit unknowns. No app dependency or Swift change
is introduced. Private captures, references and reports stay outside Git.

This advances limited fixed-source fidelity only. Broad source/model fidelity and
independent acceptance remain gaps. The next implementation phase is the production
save and daily-total journey suite using synthetic inputs and in-memory persistence.

### Synthetic save and daily projection, 2 October 2026

The current one-command profile now runs 13 frozen synthetic cases through actual
confirmation save/reopen, log removal/restoration and daily projection using an
isolated in-memory store. Score ten save/projection outcomes and three blocked
inputs separately. Verify quantity scaling, multiple entries, edit replacement,
idempotency, unknown/incomplete totals, retained provenance, empty days and completed
week boundaries. Missing cases invalidate the roster; blocking all inputs cannot
pass supported outcomes. Production source bytes and reference hashes are pinned
before execution and rechecked afterwards.

This is confirmed-input production evidence. Raw NLP/AI-to-save continuity, real
persistent storage, UI, complete journey families and independent acceptance remain
open. Keep these distinctions in the `current-nutrition-report-v4` scorecards;
partial synthetic success must not become an overall acceptance pass.

### Linked parser, retrieval and saved totals, 2 October 2026

The current v5 composition adds nine frozen synthetic typed queries through production
parsing, CoFID retrieval, explicit confirmation, in-memory save and daily projection.
Freeze scenario actions separately from nutrient references; do not supply expected
nutrition to generation. Pin catalogue bytes and all 39 reference totals using separate
Decimal arithmetic. Compare original input, quantity handoff, explicit acceptance,
source/evidence links and complete nutrient totals. Report stage counts and whole-case
outcomes separately, retaining parser failures even when later admission safely blocks.

This advances typed-query continuity only. Composite and personal-library paths,
pasted lists, supported volume conversion, persistent stores, UI/device behaviour,
provider inference and independent acceptance remain outside this linked profile.

### Pasted-list and multi-item journeys, 2 October 2026

Current report v6 adds seven frozen synthetic lists/fourteen lines through the actual
list parser/import service, explicit per-line confirmation, in-memory save and daily
projection. Compare whole-list completeness, per-line segmentation/quantities/notice
states, remaining unresolved foods and all 39 totals. Reuse only the same run's verified
compiled dependencies; keep references out of generation and preserve null/unrun stages.

The first observations expose a manual-capture/generic-estimate evidence mismatch at
production admission. Keep supported-save failures visible and retain expected references;
blocking everything cannot earn outcome success. The next production repair and its
closed-boundary requirements are recorded in
[the failure analysis](food-list-generic-estimate-evaluation-blocker-v1.md).

### Pasted-list evidence repair, 2 October 2026

The application handoff now retains distinct original manual and actual generic-search
evidence. The closed confirmation policy is unchanged. The fresh offline evaluation
passes seven whole lists, fourteen line outcomes and seven complete daily totals;
nine supported entries save and three unsupported quantities reach their exact error.
Thirteen confirmed-input journeys and nine linked typed-query journeys also pass.
Original private inputs and review labels are unchanged. List reference v3 differs
from v2 only in the two-capture count; no food, quantity, error or total target changed.

The run remains descriptive development evidence and exits `2` for incomplete overall
coverage. Provider/judge calibration, broader nutrient fidelity, receipt OCR, real voice
recognition, broader save coverage, independent acceptance and physical capture remain
unrun. A useful next local slice is linked composite/USDA retrieval and explicit milk
volume-conversion journeys; it should preserve the same save and provenance contract.
Live provider and physical-device work still require their separate authority.

### Integrated next-test-build candidate, 2 October 2026

Local test-build readiness is now documented in
[nutrition test-build readiness](nutrition-test-build-readiness-v1.md). The isolated
candidate preserves current main/build-16 behaviour and incorporates the nutrition
repairs, including negation-safe preparation interpretation. All 43 linked or
confirmed-input synthetic journey cases pass, along with full package/simulator,
static-analysis, unsigned Release and public retrieval reproducibility gates.
The original development checkout and all private sources/labels remain unchanged.
Current report v8 binds the verified private runner copies to the candidate worktree
and preserves complete source/module pins. Public synthetic harness/readiness tests
are included in the candidate CI workflow; private data is never part of CI.

The execution goal is complete at local test-build preparation. Signing, an unused
build number, protected delivery and internal distribution are the next delivery
phase, while independent AI-quality acceptance remains explicitly open.
