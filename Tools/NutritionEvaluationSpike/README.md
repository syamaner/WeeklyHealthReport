# Offline nutrition evaluation spike

This is the first integration spike for the [evaluation plan](../../docs/nutrition-ai-evaluation-plan-v1.md). It runs the real Swift query parser, rescores historical development-only extraction evidence, and executes synthetic probes through the production `FoodConfirmationService` using an in-memory store. It provides a Promptfoo comparison table and a separate three-scorecard overview.

## Architecture and evidence boundary

`run.py` owns execution and manifests; `extraction.py` wraps the original pure extraction scorer; `scoring.py` projects observations; `provider.py` supplies local observations to Promptfoo; `assertions.py` checks case expectations. Swift owns actual parser/save behaviour. Evaluation dependencies do not enter the app. New adapters must preserve case identity, complete rosters and observation-stage meaning.

The unsupported-count case injects a fictional proposal that two units weigh 80 g without evidence. That is a synthetic AI-stage failure, not a newly measured model failure. The save service receives the original count and no conversion evidence and must reject it. A second case with a compatible 100 g quantity must save. This tests actual save validation and avoids crediting a safeguard that blocks everything. It does not claim that an adapter would safely admit an invented conversion object or that all conversion attacks are covered.

The extraction adapter invokes original request construction and scoring without running collectors, resolvers or gate functions. It checks selected-source document text hashes and identity, raw-versus-bound response equality, and byte-independent report equivalence to the retained v3 development report. It filters to development cases and sources before scoring. The underlying extraction corpus's old holdouts were already consumed; no holdout predictions are read by this spike. Other suites' reserved cases are not loaded.

Historical USDA resource drift is recorded separately because the extraction contract also pins resources used by its resolver experiment. This spike excludes the resolver. A successful replay does not validate the changed USDA data or today's source pages. References remain historically agent-reviewed, and evidence-line checks do not substitute for new independent semantic review.

## Setup

Node, Python 3.10 or later and the Apple Swift compiler are required. Installation uses the package registry; evaluation uses no network. Promptfoo is pinned to 0.123.1. Its installed dependency lock is copied into each successful run; future reproducibility should use that lock rather than resolving transitive dependencies again.

```sh
npm install --prefix /private/tmp/whr-promptfoo-spike --no-audit --no-fund promptfoo@0.123.1
```

The private retained extraction documents must exist at `/private/tmp/gemini-nutrition-v2-documents-host`, or supply another hash-identical directory with `--documents`. They are not copied into HTML/JSON reports. Missing or changed documents fail closed; the spike does not fetch replacements.

## One command

Run from the repository root, selecting a fresh directory:

```sh
Tools/NutritionEvaluationSpike/run.sh \
  --output /private/tmp/whr-nutrition-spike-new-run \
  --promptfoo /private/tmp/whr-promptfoo-spike/node_modules/.bin/promptfoo
```

The macOS OS sandbox denies networking and execution of `/usr/bin/security`; an EPERM network probe must succeed before the pipeline proceeds. The Codex filesystem sandbox may require execution approval to create this nested OS sandbox. Provider credentials are not inherited by compiler/Promptfoo subprocesses. Promptfoo telemetry, update checks, cache, sharing and persistent result writes are disabled, and its configuration directory is inside the run directory. Swift modules compile directly from production sources without SwiftPM dependency resolution.

## Outputs and interpretation

- `report.html`: AI, safeguard and user-outcome overview with links to details.
- `promptfoo.html` and `promptfoo.json`: case-level expectation results and observations.
- `query-report.json`: original scorer's full strict-field, family, routing and safety diagnostics.
- `extraction-report.json`: exact historical v3 development scorer output.
- `safeguard-observations.json`: actual validation error and stored-record counts.
- `summary.json`, `observations.json`, `manifest.json`, `dependency-lock.json` and `execution.log`: attribution, code/reference/dependency hashes and reproducibility evidence.
- `run-error.json`: failures/incomplete execution; never a quality pass.

Promptfoo's pass count means the specified regression expectations were met. It is not a weighted AI-quality or nutrition-accuracy score. Its `numRequests` counts 533 local adapter invocations in the initial run, not 533 model/provider requests. No inference or model judging occurs. The deliberate unsupported proposal remains a synthetic AI failure while its correctly blocked save passes the safeguard expectation.

The parser is deterministic. Its legacy gate requires routing/quantity on all cases and every scored field on search-eligible cases. Strict food/attribute disagreements on clarify/reject cases remain in the original report rather than being relabelled correct. Common-metric supported-field precision/recall, independent acceptance, full ledger-to-daily-total journeys, voice and user effort are not implemented in this spike.

## Verification

```sh
python3 -m unittest discover -s Tools/NutritionEvaluationSpike/tests -v
```

Contract tests reject missing/duplicate/extra observations, wrong case identities, unexpected saves and a safeguard that blocks supported controls. The offline run itself verifies actual production compilation/execution and Promptfoo's complete result roster. Production code and simulator behaviour are unchanged; a full simulator suite is not required for this tool-only spike.

The decision supported by this spike is whether Promptfoo can integrate local runners and reports usefully. Broader quality thresholds and acceptance decisions remain under the metric contract and inventory.

## Current private development profile

The original spike above remains a historical framework integration. For the
current reviewed NLP/retrieval revision, use the separate offline composition:

```sh
/bin/sh Tools/NutritionEvaluationSpike/run-current.sh \
  --private-root /absolute/path/outside-git/private-evaluation \
  --output /absolute/path/outside-git/fresh-current-run
```

No installation or provider is needed. The macOS sandbox denies all network
activity and execution of `/usr/bin/security`. A loopback-denial probe must pass.
Provider credential variables are excluded from child environments. The private
root must contain the completed ranking-v5 runner bundle, its verification
manifest, owner-only `current-profile-config-v1.json`, retained public-page capture and acceptance preparation files. The private profile pins the capture manifest and source roster; personal source identities do not enter repository configuration. Paths
and symlinks are resolved; private inputs/outputs inside Git and existing output
directories are rejected. Only the fixed trusted runner file roster is copied,
after hash verification. Never copy personal artifacts into this repository.

The command stages a fresh owner-only component directory, runs the actual
production-parser and retrieval adapters, verifies retained source bytes, and
runs the acceptance preflight. It writes `report.html`, `REPORT.md`, `report.json`,
`run-manifest.json`, per-command logs and component reports. Retained snapshots
are never overwritten. Exit 2 means the current component profile completed but
the overall evaluation is incomplete; exit 1 means an integrity/execution or
exercised safeguard, journey or fixed-source contract failure. There is deliberately no overall-pass exit for this
partial profile.

`current_report.py` is a pure projector of established component reports;
`run_current.py` owns filesystem adapters, fixed suite orchestration, hashes and
report rendering. This architecture keeps framework/application dependencies
unchanged. Stable boundaries are complete rosters, frozen references, quantity
safeguards, source identity, privacy and truthful incomplete/not-run states.
Provider and physical profiles remain separate adapters. Synthetic save/projection outcomes are explicitly scoped below.
No new scoring framework, production module or speculative universal interface
is introduced. The report contract is `current-nutrition-report-v6` (earlier snapshots are retained): known safeguard failures remain visible even when another component is missing or malformed. Contract tests reject missing/duplicate/wrong observations,
broken safeguard counts, source integrity errors and vacuous overall passes.

Current ratios are descriptive development evidence, with exposed mixed-review
references and partial annotations. Retained webpage integrity is not nutrient
fidelity, and confirmation mechanics are not successful saved intake. The
seven missing profiles remain visible. No historical extraction/Promptfoo result
is silently relabelled as a fresh run. The earlier acceptance preparation pins
may be stale after repairs; their preflight result is reported separately rather
than automatically refreshed. Quality thresholds and fresh acceptance references
still require a separate freeze.

Run the same test command documented above; the current-profile contracts are
included. This phase changes evaluation tooling only, so it does not repeat the
previously passed Swift simulator and static-analysis gates.

### Fixed-source extraction profile

`fixed_source.py` separates a restricted evaluation-only HTML table reader from a
pure scorer and private file orchestration. Domain scoring consumes plain records;
filesystem/hash handling stays at the runner boundary. It does not modify app
extraction, confirmation or persistence. There are no provider clients. The stable
`fixed-source-nutrients-v1` contract requires exact source identity/hash, independent
column bases, nutrient states/units/decimals and table/row/column support. Ordinary
future proposal adapters can use the same scorer; merged, ragged, duplicate and
unselected ambiguous table layouts fail closed in this deliberately limited adapter.

A private `fixed-source-config-v1.json` optionally connects a pre-frozen reference
and captured HTML inside the supplied private root. An optional frozen table index selects a panel explicitly; without it multiple matching panels fail. The reference values never
enter the reader; only the scorer sees them. Config paths cannot escape the root
or enter Git. References, observations and copied reference bytes remain private.
The config pins the reference bytes; the reference pins the captured source bytes.
The run manifest pins the public adapter/scorer code.

The `current-nutrition-report-v3` scorecard separates numeric transcription from
fully supported fields and whole-source success. Six predeclared fault injections
check wrong basis, missing field, unknown changed to zero, invented scoop mass,
wrong unit and wrong support column. Fault detection is **scorer contract evidence**,
not model quality or production safe blocking. Unknown sodium remains unknown;
salt conversion is outside this profile. Source serving mass cannot establish a
user scoop mass. Both published columns retain their own declared rounding.

One exposed, assistant-transcribed source is descriptive development evidence.
Fresh model extraction, general source fidelity, app admission, saved totals and
independent acceptance remain unrun. Success keeps the overall decision incomplete;
a fixed-source contract failure exits 1 and remains visible. Synthetic repository
contract tests contain no private source tables or personal records.

### Synthetic production save and daily projection

The current `current-nutrition-report-v4` profile always executes the versioned
`synthetic-save-daily-journeys-v1` suite. `journey.swift` supplies synthetic populated
confirmation inputs and invokes production `FoodConfirmationService`, reopen/edit,
`FoodLogManagementService` and `FoodIntakeProjection`. The store is an isolated
`InMemoryFoodLedgerStore`; no personal ledger or persistent database is opened.
Fixed clock, IDs and UTC calendar make the observations reproducible.

Architecture gate: the fixture runner owns setup/actions only; production types
own admission, mutation and projection. `journey.py` owns pure comparison and
compile/run orchestration at separate function boundaries. The report projector
owns truthful stage/status and denominator presentation. The immutable synthetic
reference is hash-frozen before execution; the run pins and rechecks all compiled
Swift source bytes. This extends the existing evaluation composition without new
app interfaces or dependencies. Contract tests preserve roster completeness,
unknowns, scaling, replacement semantics, provenance and non-vacuous outcome success.

Thirteen cases cover 100 g and 50 g scaling, two entries, immutable quantity edit,
idempotent retry, three blocked inputs (count without conversion, unaccepted
candidate, cleared amount), an empty different day, partial nutrient knowledge,
completed-day preview, removal and restoration. Expected active rows, quantities,
operation/version counts, numeric/unknown totals, incomplete counts and source
provenance remain separate observations. The two-entry subtotal and edit reference
are explicit synthetic arithmetic, independent of production summary calculation.
The reference also requires all 39 total keys and seven previews excluding today.

Ten save/projection cases and three blocking cases are descriptive synthetic
outcomes. Failed blocking updates the safeguard scorecard; failed supported saves
or totals cannot be hidden by correctly blocking everything. Missing/duplicate
observations invalidate integrity. Output includes raw observations, per-case
failures, reference bytes, production source pins and compile/run logs.

This suite starts at populated confirmation, not parser/model input, and does not
establish real-user outcomes, GRDB persistence, UI behaviour, exhaustive quantities,
mixtures, competing-version coverage or independent acceptance. The remaining gap
is named `full_save_and_daily_totals_coverage`; overall status stays incomplete.
No fresh model inference or device action is added. Evaluation Swift compiles the
current production domain/application/test-support modules; app production source
is unchanged, so full simulator/static-analysis gates are not repeated.

The current reference revision is `journey-reference-v3.json`, pinned by
`journey-freeze-v3.json`. Earlier synthetic revisions are retained: v1 reused an
immutable capture ID in the second-entry fixture; v2 supplied distinct captures;
v3 also pins the exact expected validation error for each blocked case. Operational
errors cannot earn successful-blocking credit. All revisions are exposed development
material, and each final run freezes its active bytes before predictions.

### Linked typed-query journeys

The `current-nutrition-report-v5` composition also runs nine frozen synthetic
queries through `FoodQueryParser`, the production hash-verifying CoFID adapter,
`FoodConfirmationState`/reducer, `FoodConfirmationService` and `FoodIntakeProjection`.
An isolated in-memory store, fixed clock/IDs and UTC calendar protect personal data
and make the run reproducible. Source modules are compiled directly, with an unused
Bundle accessor shim; the explicit corpus constructor verifies the real source bytes.
This adapter is CoFID-only, with no personal library, milk-volume offering, composite,
pasted-list route or UI execution.

Architecture gate: `linked.swift` owns scenario actions/composition only; production
modules own parsing, search, admission and totals. `linked.py` owns a pure scorer and
file/compile orchestration; the master projector owns stage-aware reporting. Stable
contracts are original text, complete case/key rosters, explicit selection/acceptance,
source identity/provenance, quantity units and unknown states. Existing ports are
used without new app abstractions. Changing a source adapter cannot weaken the
neutral observation/reference contract.

Generation inputs (`linked-input-v1.json`) contain only authored text and explicit
user actions: selected public record ID, accept/leave unaccepted/clear quantity.
Expected nutrients never enter the runner. The separate exposed development reference
pins the public catalogue hash and all 39 daily totals per case; numeric expectations
use independent Decimal arithmetic over the published catalogue declarations, rather
than calling production calculation. Unsupported source-to-canonical units remain unknown: water declared in grams does not become millilitres. Trace/unmapped source fields remain unknown in the saved resolution and contribute no exact subtotal. Empty days retain
null totals. The reference and scenario input are hash-frozen before execution.

Four supported saves cover grams, kilograms converted by the parser and cooked eggs;
three expected blocks cover count without conversion, unaccepted selection and cleared
quantity. A rejected zero amount and a no-result search remain in the full nine-case
roster. The runner attempts save before acceptance to verify no records are written,
then executes the specified selection and user action. It verifies original text,
unchanged candidate nutrients, catalogue manifest/source-record provenance, separate candidate-to-capture links and estimate assertions. Numeric generic totals retain their estimate flags.
This does not treat a retrieved or top-ranked candidate as automatically accepted.

The report keeps full journey success, four supported saves, three expected blocked
outcomes, two expected stops and seven exercised safeguards separate. Stage denominators
are parser 9, retrieval 8, handoff 7, save 7 and daily projection 7; unsupported stages
remain explicitly unrun. Whole-case errors remain visible even if later blocking is
correct. Exact expected validation errors prevent operational failures earning credit.
Missing, duplicate or unexpected observations invalidate integrity. Tests cover wrong
selection, amount, subtotal, unknown-to-zero, missing cases and vacuous block-all success.

This demonstrates limited typed-query continuity through production logic, not fresh
model quality, real user behaviour, persistent database correctness, complete route
coverage or independent acceptance. The overall report remains incomplete. All raw
observations/reports stay in the private output; repository scenarios contain public
catalogue data and separately authored synthetic inputs only.

The active linked reference is revision v3. Earlier references and private trials remain retained: v1 missed generic estimate flags and used an incorrect nutrient-to-capture linkage; v2 also assumed water mass was canonical volume. v3 freezes correct source semantics before the final run. These exposed development repairs are not independent acceptance.

### Pasted-list and multi-item journeys

The `current-nutrition-report-v6` composition adds `synthetic-list-report-v1`:
seven independently authored synthetic lists, fourteen parsed lines and all 39 daily
totals per list. The frozen actions expect nine consumed entries, three quantity
blocks, one context line and one search miss. These are expected outcomes; a report
must show actual failure rather than treating every blocked supported save as success.

Architecture gate: `list_journey.swift` supplies explicit scenario selection and
acceptance actions to production `FoodListParser`, `FoodListImportService`, confirmation
and daily projection. `list_journey.py` compares observations against separate frozen
public-source references. Domain admission rules are unchanged. The list adapter reuses
the production modules compiled by the immediately preceding linked suite, checking
its complete source pins and the reused libraries/module bytes before and after use.
There is no new app interface, provider, database or speculative framework dependency.
The master composition runs this suite after linked queries in the same offline sandbox.

Cases cover context plus two foods, two deliberately identical consumed lines, a
partially answerable list, missing quantity, source miss, blank/bullet formatting and
half-item count. The scorer compares line number and original text, segmentation,
query/preparation/notice/quantity, explicit handoff, initial unaccepted state,
preaccept blocking, per-line write delta, original descriptor/source provenance,
remaining unresolved food lines and complete daily known/incomplete/estimate states.
Duplicate consumed lines are two explicit inputs; deduplicating them cannot pass.
Expected arithmetic uses Decimal over public catalogue data, including unknown canonical
water and preserved generic estimate flags. Reference facts do not enter the runner.

Missing/duplicate cases invalidate integrity. Missing/duplicated/merged parsed lines
fail list correctness and remain in the fourteen-line denominator. Context and no-result
routes have no observable confirmation capture, represented as null for that stage;
original parsed line text is still compared. Whole-list completeness and partial saved
subtotals remain separate. Safeguards verify no preaccept writes, no context/miss writes,
and no admission of expected unsupported quantities. An earlier identity gate can mask
a quantity-specific check; matching the expected quantity error is required for that
line's outcome correctness, and is never inferred from generic blocking.

The initially observed production blocker is documented in
[the failure analysis](../../docs/food-list-generic-estimate-evaluation-blocker-v1.md).
The ordinary pasted-list acceptance path retains manual capture evidence, whereas
`food_confirmation_v2` requires generic-search evidence for a composition estimate.
The initial tooling phase kept supported cases failing until the subsequent handoff
repair below. Its historical failing report remains preserved, with no policy bypass.

### List handoff repair

The subsequent local production repair adds search evidence alongside each original
manual capture. `list-reference-v3.json` and `list-freeze-v3.json` are active: the only
reference change from v2 is the number of retained evidence records (two per saved
line). Original input, selected catalogue records, quantities, outcomes, errors,
operation counts, outstanding lines and all nutrient totals remain unchanged.
The observer finds the original manual descriptor by ID and additionally checks the
saved generic-search evidence link. Reference v2 and the original failing private run
are preserved. The closed confirmation policy remains `food_confirmation_v2`.

### Multi-source and volume journeys

Current report v7 adds thirteen frozen cases through the existing CoFID, USDA and
composite adapters, explicit source selection, query/list handoff, confirmation,
save/reopen and all 39 daily nutrient totals. Twelve entries save and one count
requires a conversion. Seven cases exercise the record-bound milk rule: three
explicit conversions produce 206 g from 200 mL; four retain volume and unknown
mass-based totals when no conversion is accepted, the amount changes, or the selected
record is ineligible. This is the existing supported-save contract, not a rejection
of all unsupported nutrient calculations.

Architecture gate: `multi_source.py` owns pure scoring plus local runner composition;
`multi_source.swift` exercises existing application services with deterministic IDs,
clock and in-memory persistence. The runner receives actions and record IDs, never
reference nutrient values. `freeze_multi_source.py` uses separate Decimal arithmetic
on the public source records. Closed contracts cover source identity, explicit consent,
conversion source, amount/unit, provenance, complete roster and unknown totals.
Scorer faults test missing cases, source substitution, silent/stale conversion,
preacceptance writes and invented nutrients. No adapter changes application policy.

Active inputs/reference/freeze are v2. V1 is preserved: before a runnable observation,
review corrected the count scenario to the list entry point (the query parser does
not accept arbitrary item counts) and removed a conjunction from the USDA milk query
that would request clarification. The first trial also found an observer compile
error; it is retained as invalid, with no quality claim. A subsequent development
run passes all thirteen v2 cases. The full profile rebuilds and pins its dependencies.

The compiled generic module now includes USDA and the real milk policy with its
bundled, hash-verified rule. Earlier CoFID-only references and expectations are
unchanged. These are exposed synthetic development scenarios; they do not establish
provider accuracy, representative user outcomes or independent acceptance.

### Integrated candidate workspace

Current report v8 can run from an isolated checkout. It first verifies the immutable
private runner bundle, then changes only the repository assignment in copied runners
and includes the required `FoodQueryDiscoveryPolicy` dependency for the legacy parser.
The manifest records the original bundle hashes, bound repository and effective
runner hashes; copied runners are checked again after execution. Original bundle,
personal files and labels remain unchanged. Workspace-binding tests reject ambiguous
assignments and verify safe path quoting and retained labels.

The private query-route denominator still describes `FoodQueryParser`, which the
current app retains as a diagnostic inside `FoodQueryInterpretation`. It must not be
advertised as current description-discovery accuracy. The linked typed-query adapters
now use the same interpretation and preparation boundary as the current app. Existing
frozen case expectations remain unchanged. Application tests cover discovery without
automatic quantity, alongside explicit negative and conflicting preparation.

The final integrated profile uses multi-source reference v3 with fourteen cases.
It keeps the source-specific USDA volume case as a direct milk query and additionally
retains the prior `without added` description as an unreviewed-amount case. Current
interpretation treats that connector conservatively: amount remains empty and save
must fail with `invalidQuantity`. Both typed-query observers now explicitly pass
`prefillSourceQuantity: false`, matching the actual search-flow composition root.
This corrects the observer's older default, not application admission. The integrated
v2 failure is preserved; v3 rebuilds every dependency with complete hash pins.
The final profile has twelve multi-source saves, two quantity blocks and seven volume
outcomes, alongside the earlier thirteen/nine/seven frozen journey suites.
