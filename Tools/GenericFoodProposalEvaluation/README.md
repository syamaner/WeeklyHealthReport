# Generic food proposal evaluation

This evaluates the actual Swift OpenRouter adapters and closed source-binding
policy. It does not use model-written nutrition as gold. The current datasets are
development evidence, not independent acceptance or calibrated confidence.

`development-24` contains authored HTML/plain-text fixtures whose food descriptors
include entries from the user's authorised list and Taiwan market dishes. Every
numeric panel is fictional. These files must never enter a real food catalogue.
The `build_development_roster.py` script writes raw fixtures and invokes the Swift
format projector without network access. Gold is authored before predictions.

`frozen_run.py freeze` retains the executable, resource bundle, production source,
evaluation scripts, raw fixtures and projected documents. The plan contains their
hashes, expected outcomes, group metadata, request limits and reported-cost stops.
No environment file is read, enumerated, copied or hashed. `run` uses the established
private credential loader and passes values only through the child environment.
The runner does not print arbitrary child output. Run the snapshotted script so
later edits cannot silently change a frozen run.

```sh
python3 -B Tools/GenericFoodProposalEvaluation/frozen_run.py freeze \
  Tools/GenericFoodProposalEvaluation/development-24/roster.json \
  /private/tmp/weekly-health-nutrition-generic-build/debug/FoodProposalProbe \
  Tools/GenericFoodProposalEvaluation/runs/development-24-v1

python3 -B Tools/GenericFoodProposalEvaluation/runs/development-24-v1/snapshot/source/Tools/GenericFoodProposalEvaluation/frozen_run.py \
  run Tools/GenericFoodProposalEvaluation/runs/development-24-v1

python3 -B Tools/GenericFoodProposalEvaluation/runs/development-24-v1/snapshot/source/Tools/GenericFoodProposalEvaluation/evaluate.py \
  Tools/GenericFoodProposalEvaluation/runs/development-24-v1
```

New freezes record reference validation `source-review-gold-v2`: six explicit
nutrient slots, finite nonnegative declarations, a finite positive basis, explicit
nonempty name/document lists, and valid abstention choices. Unknowns remain null;
boolean values and malformed numeric references are rejected before runtime or
credential-loader access. Every equivalent basis is checked without adding any
conversion. A repeated valid basis is harmless and remains accepted. The prospective
roster builder completes this validation before creating its destination or copying
evidence, so rejected gold cannot leave an apparently prepared run. Retained frozen
runners and scores are unchanged; use each historical run's original runner.

Each document uses at most one extraction and one optional selection request. No
eligible candidate means no selection request. Discovery-only cases use one native
web-search request and require a separate source-coverage audit. Acquisition is a
keyless Swift command and must be reported separately from extraction quality.
Continuing a run never retries an attempted case. Transport failure with unknown
cost stops later cases. Stops based on reported cost are not prepaid hard caps.

For extraction-only comparisons, set `selection: false` and `extractor` to `luna`,
`sol`, `qwen`, `grok` or `opus`. The app explicitly uses Grok extraction and Luna search/source choice; routes are evaluated with the
same provider-neutral binding contract and cannot silently change search routing.
Each route pins its endpoint and expected response provider, disables fallback,
requires parameters and requests ZDR/no data collection. Model inference retention
settings do not establish the search plugin's retention policy. Sol requires low
reasoning; Qwen requests reasoning disabled. Grok uses low reasoning on `xai/zdr`;
Opus omits optional reasoning on `google-vertex/global` (serving Anthropic, not
Gemini). Every route keeps the same 4096-token output ceiling. Runtime qualification is separate from
catalogue compatibility. A timeout or upstream rate limit is an availability failure,
not evidence of weak nutrition reasoning or an invalid API key. HTTP-200 error
envelopes are classified using their numeric upstream code.

`capture_discovery.py freeze-references` snapshots prospective reference URLs and
the actual capture binary. `build_prospective_roster.py` checks reviewed raw hashes,
keeps paired variant pages in a common order and freezes expected source document
IDs as well as names. It accepts only source-reviewed explicit basis equivalents;
no numerical scaling is introduced. `reproject_comparison.py` replays retained raw
bytes through a changed projector with unchanged gold and labels the result as an
exposed repair experiment. These are separate from genuinely new source runs.

Current wire version `openrouter-food-extraction-wire-v3` uses one required object
slot for each of the six nutrients. The adapter validates that shape and translates
it into the unchanged domain proposal array; duplicate or missing nutrient slots
cannot be repaired silently. Evidence arrays contain catalogue IDs, not model-written
quotes. Catalogue v2 deterministically attaches unchanged captured text within the
declared document. Long blocks use overlapping excerpts of at most 1400 characters;
domain binding still checks numeric context in the complete original block, so an
excerpt cannot strip a source bound. Unknown IDs, duplicate references and wrong
documents fail closed. Catalogue v2 omits long DOM locators from provider input,
while retaining them in original documents and manifests. The model still decides nutrient meaning and applicability.
HTML projection v6 allows up to 3 MB of raw HTML/text; PDFs retain a separate 1 MB
limit. Existing depth, node, 512-block and 30,000-character limits remain closed.
It retains nested rows and inline
blocks, combines adjacent explicit value/unit cells and records its version in
locators. An unambiguous adjacent definition term/description pair becomes one
`definition_row`. Ordinary paragraphs/divs within cells remain inside their table
row; nested table rows retain separate boundaries. Binding v5 permits an explicit parenthesised unit within a single
table/definition row only when the entire row is quoted and its columns contain
literal numeric tokens. It never borrows units across rows; bounded values remain
unknown. Basis and column meaning still require source evidence and review.
Binding also checks qualifiers and
numeric boundaries in the original block, so a clipped quote cannot turn `<6g`
into an exact `6g` claim. Adjacent English/Chinese verbal bounds, approximations
and plus/minus declarations are also rejected. This still does not prove nutrient meaning: explicit user
review and semantic evaluation remain necessary.

New frozen runs record hashes of generated outputs in each completion receipt;
scoring fails if a retained output was subsequently changed, deleted or added.
Earlier runs lack this output receipt check and must be described accordingly.
This detects changes against the local receipt; it is not external attestation.
`reconcile_generation.py` can make one read-only lookup of a retained generation's
billing metadata, leaving original receipts unchanged. A 404 is unresolved cost,
not zero cost. Separate subsequent experiments must retain that uncertainty in
their metadata and overall accounting. No attempted inference is automatically retried.

Scoring includes every frozen case, even failures and unattempted cases. A missing
prediction is not successful abstention. Wrong identity or basis invalidates the
associated nutrient claims. Missing values must remain unknown; invented zero is
an error. Reports include field precision/recall, unknown preservation, whole-case
success, paired extractor/Jev outcomes, and family/layout/domain/slice groups.
Disabled selection arms have no Jev denominator. Model groups are reported separately;
do not combine the same food across models into additional independent samples.
Paraphrases and shared families are not treated as independent observations.
Selector failures remain visible rather than being hidden by successful extraction.
Separate Swift contracts establish persistence and confirmation behaviour; provider
JSON alone does not prove a saved entry or correct daily totals.

`compare_runs.py LEFT_RUN RIGHT_RUN NEW_OUTPUT.json` compares two extractor-only
runs after verifying their frozen inputs and output receipts. It requires matching
planned cases, queries, gold, source documents, runtime, prompt/schema, evaluator
and pacing. It recomputes scores with the frozen evaluator instead of trusting
editable score files. Paired outcomes include failures and unattempted cases;
family/domain groups expose related samples. Reported cost per usable panel is
unknown whenever any request cost is unknown. Observed median and nearest-rank
p90 request latency include reported failed-request timings and retain missing
timing coverage. These are descriptive development comparisons, not statistical
superiority or end-to-end acquisition/UI measurements.

`evaluate_workflow.py DISCOVERY_RUN CAPTURE_RUN EXTRACTION_RUN NEW_OUTPUT.json`
verifies all three frozen plans, original result receipts and copied native leads.
It recomputes extraction scores with the frozen evaluator and reads the source
eligibility review and capture report retained before inference. The original
query denominator includes missing search/capture results. Wrong-market or staging
sources cannot become coverage successes through safe abstention. Preferred-choice
abstention and other eligible candidate offers are reported separately, since a
model can return a bound candidate it declines to recommend. This is a staged
actual-adapter development workflow, not elapsed single-tap UI evidence. Later
source-choice orchestration has its own contracts and does not rewrite these runs.

The opt-in `FrozenFoodWorkflowReplayTests` replays retained discovery and
source-choice responses, reprojects retained website bytes, and replays Grok
extraction through the current `GenericFoodProposalReviewer`. Its transport cannot
network and uses a synthetic credential. It checks request parity, hashes, call
counts and the current confirmation-choice guard. The two declined sources stop
before capture; three supported proposals and one abstention survive the remaining
four workflows. This is integration replay, not six new live predictions:

```sh
FOOD_WORKFLOW_REPLAY=1 swift test --package-path Packages/FoodLedgerKit \
  --scratch-path /private/tmp/weekly-health-nutrition-generic-build \
  --filter FrozenFoodWorkflowReplayTests
```

The retained external source-choice artefacts are required; ordinary test runs
skip this local replay rather than reaching the network or accessing credentials.

Model-route promotion uses the same captured inputs and frozen gold, retaining
availability, latency and cost alongside correctness. A better exposed development
score supports an implementation decision, not a production accuracy claim. The
current Grok choice has a recorded timeout; neither unknown cost nor an unattempted
case is zero. Endpoint/model IDs describe the route reported by OpenRouter, not an
immutable model-weights snapshot. Multiple runs on the same foods measure repeated
behaviour, not more independent foods. Changes to input compaction, prompt, schema,
capture or binding require a separately labelled experiment.

`holdout_audit.py` checks a candidate roster against explicitly supplied frozen
development plans. It verifies plan and source-document hashes, then checks
comparison IDs, normalised queries, declared food families, source URLs, raw-body
hashes and source domains (including parent/subdomain relationships). A reviewed
`domain_group` can associate related country/brand domains; the tool does not guess
semantic families or infer a public-suffix/brand grouping. All planned development
cases count as exposed even if their predictions were never attempted. Supply the
complete relevant development history; omitted runs cannot be checked.

```sh
python3 -B Tools/GenericFoodProposalEvaluation/holdout_audit.py \
  CANDIDATE_ROSTER.json NEW_AUDIT.json --development-run EXPOSED_RUN

python3 -B Tools/GenericFoodProposalEvaluation/frozen_run.py freeze \
  CANDIDATE_ROSTER.json FOOD_PROPOSAL_PROBE NEW_RUN \
  --holdout-against EXPOSED_RUN
```

Repeat `--development-run` or `--holdout-against` for every relevant frozen run.
With the freeze flag, overlap or unverifiable development evidence stops before
runtime or credential-loader access and before creating the destination. A passing
audit and its declared exposure index are included in the hashed snapshot. Passing
means only no detected overlap in the supplied metadata; independent acceptance
and confidence calibration remain false. Without the flag, an ordinary labelled
development run remains permitted. Historical frozen runs are unchanged.
`public-19-holdout-overlap-audit-v1.json` demonstrates that all 19 previously exposed
public cases are rejected as a new holdout, even across different model routes.
No additional predictions or provider charges are part of that check.

Confidence remains uncalibrated. Exact evidence binding, source applicability,
nutrient meaning and user review are distinct requirements; no model confidence
threshold can substitute for any of them. Independent acceptance still needs a
predeclared source-reviewed holdout across new food families/domains, separate
acquisition failures, and review of the complete device flow. The current suite
demonstrates an OpenRouter-only implementation and observed results; it does not
establish universal superiority over Gemini or a model-provider causal effect.

The older `swift-public-01` pilot retains one observed public Quorn run and reported
costs. Its executable was hashed at a mutable build path but not copied before later
builds. This limits replay reproducibility; do not pool it as a fresh independent
test or treat its hashes as proof of the current executable.

Further acceptance needs independent source review, prospectively separated domain
and food-family groups, representative public acquisition and failure coverage,
and device review of the complete user flow. No result here proves that every
website, source layout, Taiwan dish or real meal is supported.

Capture audit v2 retains output hashes for the document, raw response bodies and
capture receipt, and verifies them before building a prospective roster. Missing
source bodies remain missing evidence, not image/OCR gold. New inference runners
verify completion receipts before resume-budget calculations. An interrupted or
unjournalled attempt stops further calls even if no recorded request cost exists;
unverified attempts are distinct from known request counts. Frozen historical
runners and results retain their original behaviour and provenance.


`workflow_smoke.py` freezes the six original workflow queries and runs each through
the actual reviewer, including live discovery, source choice, capture and
extraction. Its maximum is eighteen provider requests, no automatic retries,
150 seconds per review, and separately retained reported-cost stops. A stopped
run retains all six queries in the denominator. The script verifies request and
response hashes and response-reported costs before continuing. This is a workflow
smoke; allowed confirmation IDs are not numeric accuracy or a saved food entry.
The retained `workflow-live-smoke-v1` trial completed four, failed one capture,
and left one unattempted after its cost stop. Its separately labelled source
audit is post-prediction evidence. It must not be pooled with prospective scores.

The live wrong-market selection is now an additional opt-in offline replay.
`food-source-market-conflict-v1` rejects supported explicit query/URL-country
conflicts before capture and again before extraction after redirects. Source
choice requests stay unchanged. The current narrow UK/GB, IE and TW marker table
is not a global source-eligibility classifier; unknown geography still needs
applicability review. The original live result remains unchanged by this repair.


Workflow smoke v2 requires an explicit nonempty ordered subset using
`--ids CASE_ID [CASE_ID ...]`. It retains the original six-query plan byte-for-byte, freezes
the current runtime/source and records both original-cohort and subset denominators.
Use each run's snapshotted runner for verification and execution; the current v2
verifier is not a replacement for a retained v1 verifier. A follow-up for a
previously unattempted query remains a separate development run. It must not be
silently pooled with the earlier model/runtime observations. V2 explicitly stops
on keyless capture timeout too. Its retained Ikari follow-up returned no permitted
confirmation and a rejected candidate; abstention and binding failure remain
distinct facts.


## Prospective follow-up on 4 October

The [24-source holdout](../../docs/generic-food-proposal-holdout-20261004.md)
failed its predeclared gates: 20/24 captures, 13/20 correct captured-source review
outcomes, and 4/6 matching primary-source searches. The six searches reuse foods
from the 24-source cohort; they are not six additional independent foods. All 26
new calls have reported costs totalling $0.584324675. The evidence is agent-reviewed,
not independent human acceptance or calibrated confidence. These cases are now
exposed regression material and must not be reused as a fresh holdout after repairs.

Holdout preflight v2 includes actual captured URL hosts, including redirect hosts,
and retains query/family exposure for historical discovery plans whose declared
host is explicitly `unobserved` or `not_known_before_discovery`. Such missing hosts
are counted and remain unknown; they cannot be used on a provided-document case
or extended to arbitrary malformed domains. The complete 33-plan audit covers 301
planned case instances, including 18 discovery cases without known domains.
Three new regression tests cover these boundaries; all 112 evaluator tests pass.
Production Swift code and provider routing were not changed during this follow-up.

## Repository and local evidence boundary

The repository retains evaluator code, synthetic development fixtures and summary reports. Captured-page corpora, raw provider responses, full frozen run snapshots and native screenshots remain local in the isolated nutrition checkout or the private artifact paths cited in reports. References to those captures are provenance receipts, not a claim that raw evidence is bundled in a fresh checkout. No credentials are included.
