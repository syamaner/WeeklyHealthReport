# Generic food proposal integration v1

## Scope and authority

The user authorised autonomous implementation and bounded OpenRouter tests, extended
for the next 24 hours, until **09:06 Europe/London on 5 October 2026 (08:06 UTC)**.
This supersedes the earlier 08:00 and 10:00 goal wording. Xcode permission was
explicitly reaffirmed. The subsequent instruction defers device testing until
all coding jobs and any relevant other-agent merge are complete; further device
and interactive simulator checks are deferred meanwhile. No commit, push or
release is requested in this chat. The isolated checkout now includes upstream
`a1591a0` (workout PR #181) and the earlier Taiwan catalogue. The shared checkout
and other agents' checkouts are not edited.

## Latest verified state

> **Current repair result, 4 October:** the unit/basis and applicability repairs are implemented on `79efe835`.
> The fresh follow-up passed its predeclared gates: 10/11 captured cases (10/12 including acquisition),
> 4/4 required abstentions and primary search 6/6. The exposed regression scored 17/20 under unchanged gold.
> App confirmation now requires successful Luna applicability checking after Grok extraction; no Gemini/Jev calls.
> New cost: 66 calls, $0.921713950, all known. Package/evaluator/simulator/static-analysis gates passed.
> Read the [repair results and limitations](generic-food-proposal-repair-results-20261004.md).
> Changes remain local and uncommitted. Earlier checkpoints below are historical, including the failed original holdout.

Current validation: 694 package tests (5 opt-in skips), 114 evaluator tests, 315 simulator tests
(one opt-in skip), successful static analysis, and three subsequent offline workflow replays.
The current flow adds mandatory categorical applicability checking; unavailable checking cannot fall
back to extraction. All following chronological implementation sections are historical.

## Architecture gate

The existing verified manufacturer route remains a separate contract. This feature
adds a generic **proposal**, with source quotes and unknowns, that a person reviews
before the existing confirmation and quantity workflow. A matching number proves
literal correspondence, not correct product identity, nutrient semantics or meal
applicability. Model confidence is uncalibrated and cannot grant save authority.

Responsibilities and dependency direction:

* Domain: versioned document references, proposal values, strict literal/unit/basis
  validation and conflict rejection. No networking, provider or HTML dependency.
* Application: bounded discovery/capture/extraction/selection orchestration through
  consumer-owned capabilities; cancellation and immutable review snapshots.
* Infrastructure: public HTTPS acquisition, format-based document projection,
  OpenRouter transport and optional Jev selection. Keychain credentials are isolated
  from website acquisition; only submitted food terms and source material go out.
* Presentation: explicit opt-in/key validation, source/proposal review, unresolved
  values and conflicts, followed by the existing editable food confirmation.

Extension axes are discovery, capture formats, structured extraction and selection.
New public websites do not require domain or admission switch cases. New formats
must implement the same bounded document contract. Existing source-specific readers
can remain optional fast paths.

Closed invariants: no inferred nutrient, density, serving weight, salt-to-sodium or
kJ conversion; no cross-panel merging; source hash and exact quotes retained;
missing basis blocks scaling; distinct partial/failed/cancelled states; stale query
or key changes invalidate results; source content is untrusted data. AI output is
never labelled independently verified. Explicit user review cannot silently remove
unknown exact-product identity requirements.

### Confirmation extension

The persistence bridge uses a new `reviewed_web_proposal` provenance kind, always
augmented rather than measured. Its versioned review manifest retains the captured
blocks, original proposal, source hash, query, user's chosen exact-product versus
representative-estimate scope, and three explicit review acknowledgements (identity,
basis, nutrients/unknowns). Only a bound, non-conflicting proposal can reach this
bridge. Exact-product scope retains every existing unknown-identity save blocker.
Representative scope uses confirmation policy v4 and remains visibly estimated.
One source-declared serving may be counted without inventing a gram weight; its
closed manifest/provenance policy is distinct from ordinary food-piece counts.
Existing archives remain readable; older app versions do not understand the new
provenance value and are not claimed to import these new records.

Contract tests cover false citations, wrong numbers and units, negative/bounded
values, missing basis, duplicate keys/IDs, panel conflicts, Chinese serving labels,
prompt injection, partial nutrients, cancellation and credential replacement.
Persistence tests must demonstrate retained provenance and incomplete totals before
any proposal-to-ledger route is considered complete.

## Evidence and evaluation

### Review suggestion gate

The staged workflow exposed an application gap: an extractor could recommend
`none` while returning literally bound candidates from an unsuitable source. The
UI showed those candidates without the extractor's recommendation. Review policy
`food-proposal-review-choice-v1` keeps all candidates inspectable but permits the
confirmation bridge only for the current suggested eligible candidate. `none`,
`clarify`, rejected IDs and non-preferred alternatives cannot prepare confirmation.
An optional successful selector supplies the suggestion; unavailable ranking falls
back to the extractor's suggestion. A suggestion never bypasses explicit scope,
three acknowledgements, literal binding, unknowns or existing save admission.
The application owns this closed decision policy; presentation displays and
enforces it again at preparation. Contract tests cover extractor and selector
abstention, eligible positive choice and failed ranking. No persistence schema or
source value changes are needed: no rejected review reaches the existing bridge.

### Source selection gate

The existing first-annotation strategy retrieved readable but unsuitable Irish
market and staging pages in two of six cases. A frozen six-call experiment selected
only among the existing three native leads, using generic exact-product/market and
primary-source criteria. It matched all predeclared metadata-only expectations:
four selections and two abstentions, without increasing source coverage. Reported
cost was $0.001400925; no search calls or retries occurred in that experiment.

The application adds a consumer-owned source-choice capability before capture.
The OpenRouter infrastructure adapter uses the qualified Luna/Azure strict index
contract without search, and the application independently checks the returned
index against the same offered leads. An abstention or failed selection preserves
the leads for inspection but does not capture or extract automatically. Supplied
URLs skip both discovery and lead selection. Maximum calls become one discovery,
one lead selection, one extraction and the existing optional candidate selector;
the overall 150-second deadline and no-retry rule remain. Ordinary new websites
still require no code. Source selection is a fallible applicability judgement,
never source verification or nutrition admission; binding and explicit user review
remain mandatory. Tests cover bounds, negative choices, cancellation, partial
failure and no later calls. Live extraction gold and prior first-lead runs remain
frozen and are not relabelled as results from the new orchestration.

### Composition route decision

The app now explicitly composes Grok/xAI for extraction, while Luna/Azure remains
the search and source-choice route. On identical compact catalogue inputs, Grok
passed 19/19 exposed public cases versus Luna's 14/19, and all six staged workflow
extraction decisions versus Luna's three. A separate four-case source set was tied
at 3/4: Grok timed out on one request and Luna rejected another case's identity
evidence. Those failures remain in their denominators. These small related
development samples support an implementation choice, not statistical superiority
or independent acceptance. Grok costs more and its observed 90-second timeout
remains an availability limitation. No automatic fallback or retry is introduced.
The provider adapter's injectable default remains Luna for existing callers and
matched tests; the app composition root makes its extraction choice explicit.

### Public HTML size gate (05:45 London)

Bounded diagnostic HTTP/1.1 GETs measured two previously rejected primary HTML
pages at 1,231,653 and 2,377,937 bytes. Both exceed the original 1 MB transport
limit without requiring script execution. HTML/text projection v6 accepts up to
3 MB; transport remains capped at that body limit plus 64 KiB framing. Existing
50,000-node, depth-64, 512-block and 30,000-text-character limits remain, as do
public-IP pinning, HTTPS, three connections and deadlines. PDF projection retains
its explicit 1 MB limit. No truncation, decompression or host exceptions are added.
Tests must cover an ordinary page above the previous limit, rejection above the
new limit and PDF rejection above its unchanged limit. A new keyless capture
experiment is separately labelled; original acquisition failures remain frozen.

### Evidence request size gate (05:37 London)

The FAGE paired input sent 7,338 source-text characters and 79,596 locator
characters across 374 blocks. Those paths are useful for retained source
traceability, but the response contract cites evidence IDs, never paths.
Catalogue v2 removes locators from provider input while preserving block order,
IDs, kinds and exact source text. The complete captured documents and coordinates
remain unchanged locally and in the review manifest. This changes only the
provider input representation, not binding, schema, gold or confirmation policy.
Contract tests must prove retained references and source documents are unchanged,
and a separately frozen comparison must measure the effect. Earlier runs retain
catalogue v1 and are not re-labelled as compact-input results.

### Additional provider qualification (05:20 London)

Grok 4.7 on `xai/zdr` and Claude Opus 4.7 on `google-vertex/global` are
catalogue-eligible alternatives. Both advertise structured outputs and ZDR. They
remain infrastructure adapters using the same wire v3/schema v5/prompt v9,
4096-token ceiling and closed binding policy. Grok requires low reasoning; Opus
omits optional reasoning. No fallback is permitted and response provider/model
identity must match. All five routes pass shared local contracts. Catalogue
eligibility is not runtime qualification or food accuracy; each new route first
gets two fixed English/Chinese fictional cases. The app default remains Luna.

Catalogue evidence: [Grok endpoints](https://openrouter.ai/api/v1/models/x-ai/grok-4.7/endpoints),
[Opus endpoints](https://openrouter.ai/api/v1/models/anthropic/claude-opus-4.7/endpoints),
[ZDR endpoints](https://openrouter.ai/api/v1/endpoints/zdr). Provider prices and
availability are observations at qualification time, not durable guarantees.

Grok passed both qualification cases with eight declared fields and four unknowns
preserved; two requests reported $0.023786. Opus returned HTTP 400 for the nullable
enum representation on its first request. That run stopped, with the second case
unattempted and the first request's cost unknown. It was not an authentication
failure. In addition, schema v5 has 24 union-bearing parameters, exceeding the
[documented Claude limit of 16](https://platform.claude.com/docs/en/build-with-claude/structured-outputs#schema-complexity-limits).
The observed error names the enum; the union-count issue is a separate compatibility
finding, not an observed second error. Opus is not runtime-qualified and has no
food-accuracy result. The next matched comparison uses Luna and Grok on 19 exposed
primary-source cases, with unchanged gold and identical current projected inputs.

### Reviewed-source correction gate (04:54 London)

Admission profile v3 will require a valid retained web-review manifest at save,
including when the user supplies identity corrections. Those corrections may
change user-observed identity and presentation, with an assertion, but cannot
change the source nutrients or reinterpret their denominator while retaining web
provenance. Such changes require a separate evidence contract and are rejected.
Reopening restores the original source name/brand from the validated manifest;
the corrected product name/identity remain in the saved product version. Both
storage contracts must prove this distinction and preserve normal quantity edits.

Binding v5 additionally rejects adjacent English/Chinese verbal bounds and
approximations (for example “at least”, “小於”, “以上”) and plus/minus declarations,
including when a model excerpt omits them. This is a closed literal-policy repair;
it does not claim to recognise every linguistic way of qualifying a number.
The already-frozen prospective wire-v3 run retains binding v4 and is labelled
accordingly rather than retroactively assigning it the new policy.

Projection v5 preserves a table row when its cells contain ordinary paragraph/div
formatting. Nested table rows and JSON-LD retain independent boundaries. This
repairs format structure without a host-specific rule or copied header units;
contract tests cover nested cell formatting and nested tables separately.

### Header-unit extension gate (04:27 London)

Binding v4 permits an explicit parenthesised nutrient unit in the label of one
captured `tr` or `definition_row`, followed only by numeric columns separated by
`|` or `/`. The complete row must be quoted. Only an exact, unqualified column
value can bind; bounds, ranges, approximations, mixed units and partial quotations
cannot become exact values. This does not extend basis inference or prove which
column applies. Human semantic review remains required. Projection v4 preserves
an unambiguous adjacent HTML `dt`/`dd` pair as one definition row, without adding
units or numbers. These are format rules, with no source-host conditions.

Responsibilities remain unchanged: HTML pairing is infrastructure; closed literal
validation is domain policy; AI chooses identity and applicable columns for review.
Contract tests cover both row forms, qualified neighbouring columns, wrong units,
partial quotes, malformed pairings and unsupported free text. Previously frozen
results remain unchanged; exposed-case repairs are reported separately.

### Evidence-reference adapter gate (04:40 London)

OpenRouter wire v3 will request evidence IDs instead of model-authored quotations.
The infrastructure adapter creates a deterministic catalogue of source excerpts,
maps every returned ID within its declared document, and attaches the unchanged
captured text to the existing domain reference type. Long blocks use overlapping
bounded excerpts; validation still checks numeric context in the original block.
Unknown IDs, duplicate references and cross-document citations are rejected.
The model still chooses identity, basis, nutrient meaning and values; this does
not repair those decisions or treat a valid citation as semantic verification.

This changes the provider wire contract, not domain admission or source facts.
All extractor routes must pass the same catalogue/reference contract tests,
including wrong-document IDs, long-block qualifier clipping and invalid values.
Existing frozen wire-v2 runs remain unchanged. A new run must retain its wire-v3
runtime, prompt, schema and unchanged gold before any provider request.

The Python prototype is frozen outside this checkout at
`nutrition-structured-proposals-v1/generic-source-v1`. It has 46 passing contract
tests and ten authorised provider calls costing $0.005305992 in reported charges.
Its public Quorn capture and three synthetic development cases demonstrate a
working prototype, not independent accuracy or a demonstrated benefit from Jev.

The app implementation requires its own Swift contract tests, captured-response
replay, live provider integration checks, the simulator suite and static analysis.
Evaluation must keep capture failures separate from extraction quality, include all
planned cases in denominators, freeze gold before predictions, and distinguish
agent-authored development cases from independent holdout acceptance. Food families,
source domains and layouts must be grouped to avoid inflated generalisation claims.

## Overnight runbook

Continue implementation through intermediate milestones. Use bounded provider runs
with request journals, reported cost coverage and no automatic retries. Never
inspect, copy, print or hash `.env`; only the existing private credential loader may
consume it. Keep a current local handoff here as implementation progresses. At the
deadline leave tests, costs, app readiness and remaining limitations explicit, and
pause the attached heartbeat. Do not call the goal complete while required work is
outstanding.

## Historical checkpoint: 01:55 London, 4 October

Implemented in this isolated checkout:

* `GenericFoodProposal.swift`: pure typed proposal/document/selection contracts,
  literal and unit binding, partial values and conflict handling. No ledger writes.
* `GenericFoodProposalReview.swift`: injected discovery/capture/extraction/selection
  orchestration, one capture and no retries. Presentation and save integration remain.
* Format-based SwiftSoup projection plus pinned-public-IP HTTPS capture. The first
  format profile supports UTF-8 HTML/text, IPv4 HTTPS and identity encoding; PDF,
  OCR, rendering, compressed content and IPv6-only sources are explicit limitations.
* OpenRouter adapter with strict schema/duplicate-key checks, pinned Azure extraction,
  Exa discovery and optional TypeSafe Jev selection. Existing Gemini code is still
  present; the app composition root has not yet been switched.
* An opt-in `FoodProposalProbe` executable and private evaluation wrapper.

Validation: 41 focused Swift tests pass (15 domain, 8 projection, 9 provider and
9 public-acquisition tests). The Swift capture successfully fetched the public
Quorn page into 160 blocks without a key. The frozen Swift extraction/selection
pilot at `Tools/GenericFoodProposalEvaluation/swift-public-01` passed its one
development case: energy 103 kcal, protein 16 g, carbohydrate 2.6 g, fat 1.7 g and
fibre 6.9 g per 100 g; sodium unknown. Two provider calls reported $0.00347812 total.
Both required routes were observed. Jev returned confidence 0.35, compared with 0.91
in the earlier Python pilot; neither is a calibrated correctness probability.

Next work: review/confirmation provenance contract and persistence tests, credential
and review UI, composition-root switch, orchestration cancellation/error tests,
broader evaluation and complete simulator/static-analysis gates. Do not describe
this checkpoint as an integrated or delivered app feature.

Build cache: `/private/tmp/weekly-health-nutrition-generic-build`. Focused tests:

```sh
swift test --package-path Packages/FoodLedgerKit \
  --scratch-path /private/tmp/weekly-health-nutrition-generic-build \
  --filter 'GenericFoodProposalTests|GenericFoodDocumentProjectorTests|OpenRouterFoodProviderTests|PublicFoodSourceCaptureTests'
```

Current provider references checked on 4 October:
[structured output](https://openrouter.ai/docs/guides/features/structured-outputs),
[web search](https://openrouter.ai/docs/guides/features/plugins/web-search),
[Jev](https://openrouter.ai/docs/guides/community/jev), and
[key validation](https://openrouter.ai/docs/api/api-reference/api-keys/get-current-api-key).
The pinned TLS implementation uses Apple's documented
[server-name verification override](https://developer.apple.com/documentation/security/sec_protocol_options_set_tls_server_name(_:_:)).

## Historical checkpoint: 02:50 London, 4 October

The app composition now instantiates OpenRouter discovery/extraction and optional
Jev selection, with a separate device-only key store. The generic web-review action
sits alongside unchanged local CoFID/USDA/TFDA and optional OFF search. No Gemini
provider remains in the app composition root. Existing Gemini package adapters and
regressions are retained. Review is explicit; opening the screen or typing does not
send food terms. A supplied URL skips discovery.

The source-review screen retains partial values, quote references, source links,
conflicts and uncalibrated ranking confidence. Exact-product versus representative
scope must be chosen explicitly, with three review acknowledgements. Prepared
confirmation does not infer intake quantity or save. The reviewed manifest and
unknown nutrients survive save/reopen through both memory and GRDB stores. A half
source serving scales declared values without inventing weight. Stale query, URL,
credential and reused-candidate-ID results are rejected.

Ten orchestration tests cover call bounds, optional ranking failures, extraction
quota failures with retained links, concurrent requests, cancellation and deadline.
The complete FoodLedgerKit run passed 615 tests with two intentional skips and zero
failures. An unsigned iOS simulator app build passed. Complete simulator tests are
running; static analysis and device/provider UI acceptance remain pending.

The 24-case authored development source dataset is frozen under
`Tools/GenericFoodProposalEvaluation/runs/development-24-v1`. It includes local food
descriptors from the authorised list, Taiwan dishes, preparation/variant confusion,
partial and missing basis, zero/unknown distinctions, conflicts, ranges, negative
values and source prompt injection. Its numeric panels are fictional, not food
facts. The run snapshots the actual executable, resource bundle, production sources,
raw inputs, projected documents and pre-prediction gold. At most 48 provider calls,
no retries, per-case reported-cost stop $0.05 and whole-run reported-cost stop $1.50;
these stops are not prepaid hard spending caps. Unknown cost stops later cases.
All roster cases remain in scoring denominators. The evaluator compares extractor
preference after binding against Jev on the same proposals and reports source/layout/
family groups. Eleven synthetic metric tests pass. Independent acceptance and
confidence calibration remain unestablished.

Reproducibility correction for the earlier one-case Swift public pilot: its source
and executable paths were hashed but not snapshotted, and subsequent work changed
those paths. Its retained document, requests, responses and gold remain evidence of
the observed run; the original executable cannot be reconstructed from those hashes
alone. Do not claim the pilot is a fully frozen replay. The new 24-case runner fixes
this by retaining copies, not merely hashes of mutable paths.

## PDF format gate

The public capture audit found a text PDF menu. PDF support belongs in infrastructure
behind the existing document-capture capability, without changing nutrient admission
or adding a website adapter. A separate PDFKit projector extracts text-only
page rows with page/rectangle locators and the original byte hash. It does not open
a PDF view, execute actions, follow attachments, fetch images, perform OCR or infer
table-header units. Whole-input byte, page, character and block ceilings apply;
encrypted, image-only, mixed unreadable and oversized documents fail explicitly
rather than silently omitting pages. PDF text ordering is not visual proof of a
table relationship, so the same literal binding and explicit source review remain.
Seven focused tests cover text, image-only/empty, page limits, encryption, retained
page locators, prompt-like text as data and unchanged source hash. Both pages of the
captured university menu were rendered and inspected. The row projection fits the
bounded document contract, but this source names a different restaurant from the
discovery query and its column-header units do not satisfy the literal number/unit
rule. Projection success is therefore not a successful answer to that query.

## Historical checkpoint: 03:38 London, 4 October

Default app selection now uses the extractor preference after closed binding;
Jev remains an explicit evaluation capability. On 24 authored development cases,
Luna passed 23/24 against Jev 20/24 with no Jev-only wins. Live discovery returned
native leads for 12/12 queries; the first-source capture audit succeeded for 7/12.
Only three captured pages supported directly usable partial panels. The extraction
run passed one of those three and correctly abstained on the other four pages.
Thus the original end-to-end directly usable first-source coverage was 1/12, not
5/7. Brand evidence and cross-panel reference failures motivated binding v2 and
prompt v4. A separate three-case exposed repair run then passed 3/3 for extraction
and 2/3 with Jev. These are development findings, not independent acceptance.

The earlier full package gate passed 615 tests (two intentional skips). Complete
iOS simulator tests passed 281/281 and Xcode static analysis succeeded. PDF support,
retained alternative links, stale-credential failure handling and extractor-route
configuration were added afterward; their focused tests pass, and final broad
gates must be refreshed after implementation settles. Eleven presentation tests,
seven PDF tests, twelve provider tests and thirteen evaluator tests now pass.

Eight new primary-source references were reviewed before predictions and captured
through the actual Swift transport in `runs/prospective-capture-8-v1`. They include
paired FAGE variants, four Taiwan sources, a salt-only sodium declaration and an
unsupported dry-cube basis. All eight captures succeeded. The reference reviewer
is reconciling the captured text before gold is frozen. References are agent-reviewed,
not human-ratified. The upcoming extraction comparison holds documents, prompt and
schema constant and omits search and Jev. App default remains Luna; Sol and Qwen
are infrastructure evaluation routes, not automatically promoted alternatives.

The four-case qualification roster stopped after two Sol attempts: one successful
English response and one HTTP-200 envelope containing upstream error 429 without
usage. Known cost is $0.0092735; the failed call cost remains unknown. A read-only
generation lookup returned 404, retained separately without changing original
receipts. Qwen cases were not attempted in that run. No inference retry occurred.

## Historical checkpoint: 04:13 London, 4 October

The refreshed full FoodLedgerKit gate passed 638 tests with two intentional skips
and no failures. This covers HTML projection v3, PDF rows v1, binding v3, fixed-slot
OpenRouter wire v2, provider adapter v2 and admission profile v2. Native simulator
rendering is now being checked with synthetic services; opening and typing must
not call a provider or confirm a food. A new complete simulator run and static
analysis remain pending after these changes.

The first eight-source prospective run passed 4/8 strict cases (3/7 answerable,
1/1 correct abstention). One failure was an overly narrow source-name allowlist:
the observed Supau name included the published bottle description. That is a
post-prediction adjudication observation, not a change to the frozen score. Other
failures were a real protein-value error, separate numeric/unit cells and a missing
basis label. The first exposed repair run passed 5/8; the next, under projection v3
and prompt v6, passed 7/8 with 20/20 selected declared claims correct and 20/24
required fields recovered. Its remaining candidate repeated a protein field and
was rejected. The new provider-only wire v2 prevents repeated nutrient slots while
preserving domain validation. Two exposed qualification cases then passed 2/2,
with all eight declared fields and four unknowns preserved, cost $0.000834720.

The candidate model study does not establish a superior challenger. Sol passed
one English qualification but rate-limited the Chinese request; a later paced
comparison rate-limited its first new request. Qwen's first request timed out.
All three failed-request costs remain unknown. Their original runs and unattempted
case denominators are retained. The later paced Luna arm cost $0.031539725 for
eight requests; all those costs are known. These results support keeping Luna as
the available app default, not declaring other models nutritionally inferior.

Six further primary pages from six new domains were captured and reviewed before
predictions under `runs/prospective-capture-6-v2`: Kongyen, Smai, Nutella, itsu,
Greggs and Kanekyu. The expected outcomes are five partial panels and one
abstention for an unsupported brewed-tea basis. The reviewer retained the source's
own Smai inconsistencies, explicit unknowns and Greggs' declared one-serving/103g
equivalence. The frozen prospective wire-v2 run is in progress. It has generated
output hashes in addition to input snapshots. All references remain agent-reviewed
development evidence, not human-ratified independent acceptance or calibration.

Architecture repair: original-context numeric binding and manifest-to-candidate
identity/value checks are closed, versioned policy changes. Format projection and
fixed-slot wire translation remain infrastructure responsibilities. A reviewed
manifest cannot authorise altered candidate amounts, invented zeros or another
food identity. No added website-specific parser, nutrient inference or automatic
save is introduced.

## Historical checkpoint: 04:50 London, 4 October

The complete simulator suite passed 282 tests. Native screenshots at standard and
accessibility text sizes were inspected; opening and typing made no provider call
or confirmation. The first render assertion incorrectly required an untruncated
large navigation title; the corrected assertion checks the visible screen heading.
The full package suite then passed 642 tests with two intentional skips, and Xcode
static analysis succeeded. These full gates precede the evidence-catalogue adapter
below and must be refreshed after it stabilises.

The fresh six-source wire-v2 run passed 5/6 strict cases, with 18/18 selected claims
correct and 18/23 required declared fields recovered. It cost $0.014114645 across
six requests. Its remaining case had header-only units. Projection/binding v4 now
supports explicit unit-bearing table/definition rows without inferring units or
turning bounded values into exact values. The subsequent exposed 14-case regression
passed 10/14, with 33/33 selected claims correct, 33/47 required fields recovered,
two correct abstentions and no invented unknowns. All 14 requests were available
and reported $0.045580915. Do not present this exposed repair set as a fresh holdout.

Its failures demonstrated quotation-copy variability and omitted fields: two
JSON-LD quotation mismatches, one shortened basis label and one omitted exact value
beside a bounded column. Wire v3/catalogue v1 now attaches original source excerpts
from returned evidence IDs, preserving the closed domain checks. Nineteen focused
provider/catalogue tests pass, including all three route configurations and a
long-excerpt boundary that removes a visible qualifier but is rejected against the
original source. Two exposed English/Chinese qualification cases pass 2/2, preserving
eight declared fields and four unknowns; two requests reported $0.000706910. The
14-source wire-v3 comparison is in progress. The source agent is preparing a further
prospective set for capture review before predictions.

Nine persistence contracts now pass across both stores, including exact-product
save only after explicit user identity corrections, with the original source
candidate, unknown nutrients and review manifest retained. No code fills those
identity fields from AI confidence. A representative estimate remains a separate
explicit scope. There is no commit, push, release or physical-device acceptance.

## Historical checkpoint: 06:42 London, 4 October

The app composes OpenRouter only for this flow: Luna/Azure discovery and source
choice, followed by Grok/xAI extraction. Optional Jev remains off. Local TFDA,
CoFID, USDA and optional OFF remain in their existing local-first flow. All 24
authored parser cases remain in the dataset: 16 have descriptor seeds from the
authorised food/scenario list, and eight cover Taiwan market dishes. Their numbers
are fictional contract fixtures, never real-food nutritional reference values.

Current source/binding stack: HTML projection v6 (3 MB raw), PDF v1 (1 MB raw),
evidence catalogue v2, extraction wire v3/schema v5/prompt v9, binding v5, reviewed
admission v3 and application review-choice v1. Source-choice v1 uses the exact
qualified Luna prompt/schema. Six retained live responses replay through the Swift
adapter with semantic request equality, original request/response hashes and no
provider calls. The source-choice prompt contains generic source criteria; no
publisher allowlist or website parser was introduced.

Matched compact-input results (every planned case retained):

| Development set | Luna strict pass | Grok strict pass | Interpretation |
| --- | --- | --- | --- |
| 19 exposed public cases | 14/19 | 19/19 | Grok recovered 65/65 declared fields; related development cases |
| Four newly captured set-D cases | 3/4 | 3/4 | Different failures; Grok's 90-second timeout has unknown cost |
| Six staged workflow extraction cases | 3/6 | 6/6 | Two sources were unsuitable before extraction |

The six-query first-lead workflow captured 6/6 pages but only 4/6 were eligible
sources. Grok produced three useful panels and one source-supported abstention;
the two wrong-source abstentions do not become coverage successes. It also emitted
two literally eligible candidates while preferring none. That finding caused the
new confirmation guard, rather than being hidden by a preferred-choice score.
`evaluate_workflow.py` reports both preferred choices and reviewable offers and
checks that no stage substituted a URL, changed a query or omitted a failed case.
The workflow is staged with source review before inference, not measured app-tap
latency or independent acceptance.

The source-choice experiment then correctly retained four leads and abstained on
the two unsuitable ones. This improves routing safety but does not increase 4/6
source coverage. Its six calls reported $0.001400925, all known. Request parity and
offline replay establish implementation correspondence, not new independent model
predictions. The six fresh set-E restaurant/prepared-food URLs have now been
captured: five succeeded and Nando's failed projection despite a complete HTTP200
body. Source review is in progress before any extraction predictions. Wu-Tau's
missing explicit denominator will remain a deliberate abstention challenge.

`Tools/GenericFoodProposalEvaluation/run-inventory-20261004-0630.json` records 258
frozen Swift inference requests: 252 known costs total $1.990015083, with six
unknown-cost requests retained. Separate from that inventory are six source-choice
requests ($0.001400925), the legacy two-request Swift pilot ($0.003478120), and ten
earlier Python prototype requests ($0.005305992). These sum to $2.000200120 in known
reported costs, plus six unresolved request costs; they are not a verified credit
statement. Repeated foods/models are never pooled as independent quality samples.

Full validation at this checkpoint: 671 package tests with three intentional skips
and no failures; 283 simulator tests with no failures; Xcode analysis succeeded.
The skips include opt-in replay/live evidence tests; the new six-response replay
was separately run successfully. The last HTTP402 classification repair passed 23
focused provider/source-choice tests after the full suites. A native rendered
result shows the extractor's abstention without Jev and proves preparation remains
blocked despite complete review acknowledgements. This does not prove physical
device interaction through every review toggle and save. Logs are
`/private/tmp/nutrition-generic-full-package-v6.log`,
`/private/tmp/nutrition-generic-simulator-tests-v5.log`,
`/private/tmp/nutrition-generic-analysis-v4.log` and
`/private/tmp/nutrition-provider-final-replay-v1.log`.

The pinned-IP TLS implementation retains hostname verification through
[`sec_protocol_options_set_tls_server_name`](https://developer.apple.com/documentation/security/sec_protocol_options_set_tls_server_name(_:_:)),
which Apple documents as overriding the endpoint name for certificate verification.
No trust-evaluation override is installed. This primary-source check supplements
the local transport contracts; it is not a penetration-test claim.

Work continues until 10:00 London. No `.env` inspection, commit, push, issue,
TestFlight upload or device installation has occurred in this phase.

The subsequent offline integration replay also passed all six retained workflows
through the current Swift reviewer: two source abstentions stop before capture;
four sources reach capture/extraction; three supported recommendations permit
explicit confirmation review and one abstains. Retained requests match generated
requests semantically, raw source bytes are reprojected, and plan/request/response
hashes are checked. The transport cannot network and the credential is synthetic.
This adds integration evidence without new provider predictions or cost. Log:
`/private/tmp/nutrition-workflow-offline-replay-v1.log`.
## Historical checkpoint: 07:36 London, 4 October

The production choice remains Luna/Azure discovery and primary-only source choice,
Grok/xAI extraction, and no Jev. The new set-F comparison tied at 5/5, so the
route decision remains based on the preceding matched evidence and its recorded
availability/cost trade-offs, not a claim that Grok wins every dataset.

| Additional development set | Luna | Grok | Original source denominator |
| --- | --- | --- | --- |
| Set E, new restaurant/prepared foods | 4/5 | 5/5 | Five captured of six URLs; useful panels 2/6 and 3/6 |
| Set F, milk/tuna/oats and Taiwan drinks/meals | 5/5 | 5/5 | Five captured of eight URLs; four useful panels for each route |
| Existing fictional 24-case contract roster | Prior 24/24 | 24/24 | Reused authored fixtures; not a matched new comparison |

Set E Grok retained 15/15 declared fields and 3/3 required unknown fields. Its
Wu-Tau and restaurant-rice-versus-packaged-topping cases abstained correctly.
Set F retained 8/8 declared fields and 16/16 required unknowns in its four
answerable cases for both routes. The dry-oats case abstained because the retained
page supplied a prepared 40 g serving rather than the requested dry 100 g panel.
The two Taiwan selections were a named medium-cup, normal-ice, less-sugar pearl
milk tea and a beef-noodle per-100-g energy declaration. Sugar was not promoted to
carbohydrate. The additional Grok run on fictional sources completed all 24 cases, with 18 supported selections, six abstentions, 91/91
declared fields and 17/17 required unknowns. All fictional values remain excluded
from real food data.

Set-F Caffe Nero and the two Taiwan PDFs failed the actual bounded reader with
`capture_responseTooLarge`. The PDF captures did not retain response bytes, so
separate visual research is not substituted for captured evidence. The failures
stay in the eight-URL denominator. Offline replay of the retained Biona and
Nando's bytes also classified their previous generic projection failures as
`capture_responseTooLarge`; historical run outcomes were not rewritten. An
exploratory main-landmark-only projection still exceeded the block limit for both,
so no main-content truncation policy was adopted. HTML and PDF size failures now
have a specific error; successful projection versions and all bounds remain
unchanged.

### Search and source-choice decisions

Twelve frozen breadth requests compared Exa `max_results` 3 and 5 on identical
six-query inputs. Native leads increased from 18 to 30, but both arms covered
five of six queries with an eligible first lead. Keep three results. Itsu's first
lead improved in both arms relative to an earlier run; this is observed search
variability, not evidence of a breadth effect.

A separately frozen generic retailer-fallback policy was rejected. It selected
Irish FAGE for a UK request on one of six cases. The existing primary-only v1
policy safely abstained on exactly the same metadata, while both policies retained
five matching primary sources, including useful partial information. No retailer
was selected by the experimental model. A keyless Morrisons fallback capture
returned HTTP403, further preventing an end-to-end coverage claim. V1 remains
unchanged; old expectations and results remain immutable. These small control
runs do not establish a statistical policy effect.

### Admission v4 architecture and repair

`reviewed-web-admission-v4` checks the exact retained review-manifest bytes using
an explicitly injected `Digesting` capability. The composition root supplies the
same SHA256 implementation used by the ledger; domain code gains no crypto SDK,
network, storage or clock dependency. Semantic rebinding and byte-hash integrity
are distinct checks. Per-nutrient manifest references must identify the actual
candidate, nutrient, blocks, original literal and binding version; capture times
must match the retained source. Source release identity is bound to its manifest
hash.

Save checks this before writing. Reopen and idempotent recovery share the complete
retained-source reconstruction/admission function, including original source
identity, manifest hash, nutrient facts, saved resolution values and serving
basis. Legitimate user corrections of name/brand remain separate from original
source names. Fourteen reviewed-source contracts pass, including altered manifest
bytes, unchanged manifests paired with changed nutrient values/references/times,
and corrupted saved resolutions. Twenty-four shared-store contracts also pass.
The new policy is unreleased; earlier local v3 reviewed-web development records
are not claimed to pass v4 admission. Existing non-web records retain their route.

### Evaluation integrity and current validation

Capture audit v2 binds documents, raw bodies and capture receipts to a completion
receipt. Its builder validates IDs, URLs, runtime and resource bundle before
creating output directories. The new retailer and set-F captures exercised that
receipt contract live without provider calls. New frozen inference runs also
verify completed output receipts before using costs to authorise another call.
Missing/unfinished receipts stop continuation; unknown recorded request costs and
unverified attempts are distinct. Negative/non-finite costs and changed receipts
fail closed. No automatic retry or credential-file inspection is introduced.

The current Python suite passes 77 tests. Package validation before the latest
admission repair passed 673 tests with two intentional skips, including the two
opt-in offline replays. Focused admission/PDF and recovery checks pass after the
repair. The current full simulator suite passes 283 tests, and Xcode static
analysis succeeds. Full package validation will be refreshed after the live-smoke
probe finishes. Current logs:

- `/private/tmp/nutrition-manifest-recovery-v4.log`
- `/private/tmp/nutrition-admission-v4-pdf-gates.log`
- `/private/tmp/nutrition-python-gates-v9.log`
- `/private/tmp/nutrition-generic-simulator-tests-v7.log`
- `/private/tmp/nutrition-generic-analysis-v5.log`

`run-inventory-20261004-0735.json` records 302 frozen Swift requests, 296 known
costs totalling $2.518508813 and six unknown costs. Thirty separately frozen
search/source-choice experiment calls add $0.091538575. The earlier pilot and
Python prototype add $0.008784112 as separately labelled legacy evidence. Across
these recorded scopes, known reported charges total $2.618831500, plus the six
unresolved request costs. This is not a credit-statement reconciliation. A live
six-query orchestration smoke is being prepared separately and is not included
in these totals or quality scores.

### Reproduction and delivery boundary

Run these from the isolated worktree. They use simulator/software fixtures and
have no live inference authority of their own:

```sh
swift test --package-path Packages/FoodLedgerKit \
  --scratch-path /private/tmp/weekly-health-nutrition-generic-build
python3 -m unittest discover -s Tools/GenericFoodProposalEvaluation -p 'test_*.py'
xcodebuild -project WeeklyHealthReport.xcodeproj -scheme WeeklyHealthReport \
  -destination 'platform=iOS Simulator,id=E94E3624-9C41-45BC-9BF8-FB466A1C15DE' \
  -derivedDataPath /private/tmp/nutrition-generic-app-build \
  -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO test
xcodebuild -project WeeklyHealthReport.xcodeproj -scheme WeeklyHealthReport \
  -destination 'platform=iOS Simulator,id=E94E3624-9C41-45BC-9BF8-FB466A1C15DE' \
  -derivedDataPath /private/tmp/nutrition-generic-app-build CODE_SIGNING_ALLOWED=NO analyze
```

The simulator ID is local to this machine. Signing is disabled for these software
checks; no signed-device or live HealthKit acceptance is implied. Public source
content is retained locally for review, without an inferred redistribution licence.
No commit, push, issue, release or physical-device installation is authorised.
Independent source acceptance, calibrated confidence and representative human
review on a physical device remain separate from these development results.


### Explicit market conflict gate (architecture before implementation)

The live whole-review smoke exposed a second Irish-source selection for an
explicit UK query, despite the unchanged primary-only source-choice prompt.
The next repair is a closed, versioned application policy which rejects obvious
conflicts between an explicitly named market and recognised country markers in a
URL. It runs after a source is chosen (so the frozen source-choice request remains
comparable), before acquisition, and again against a redirected document URL
before extraction. Supplied source URLs pass the same check. Unknown or ambiguous
geography remains unknown; this does not certify country applicability or replace
source review. No brand/domain-specific reader or model confidence threshold is
introduced. The policy is pure and uses no provider, locale service or network.

Contracts must cover the observed UK/Irish conflict, UK/Taiwan and same-market
sources, unknown URLs, multiple requested markets, word boundaries, explicit
region-bearing URL components, redirects, manual source URLs, and preservation of
alternative leads without capture/extraction after rejection. Presentation gets a
specific explanation rather than a credential error. The original paid run stays
unchanged; repairs are checked offline before any separate future experiment.


## Historical checkpoint: 08:02 London, 4 October

The authorised deadline remains 10:00 London. No commit, push, release or device
installation has occurred. The current app uses Luna/Azure search and source
choice, Grok/xAI extraction, and no optional Jev pass. Model and search requests
use OpenRouter; Gemini is not a runtime dependency of this new workflow.

### Actual live whole-review trial

A new frozen smoke used the actual Swift `GenericFoodProposalReviewer`, production
provider routes and bounded public-source capture for the six original workflow
queries. It retained executable/resources/source, every request/response, capture
bytes where available, stage timing and output completion hashes. The plan hash is
`6a30acc953900c4ccd817346dc677a2ba5919c58d8fb0416352c64a339c25db0`.

Four of six planned queries completed and exposed a candidate eligible for explicit
confirmation review: Kongyen natto, Mugu apple rice crackers, itsu chicken gyoza and
Tilda dry basmati. Their complete review times were approximately 23.31, 18.44,
33.36 and 43.86 seconds. This is actual application orchestration latency, not
human review time or a saved-entry measurement. FAGE failed acquisition after a
wrong-market source choice. Ikari was not attempted: Tilda's completed case cost
$0.0513903 and crossed the frozen $0.05 per-case continuation threshold. The runner
stopped, retained the original six-query denominator, and made no retries.

Fourteen provider calls reported $0.181578775; all fourteen costs are known.
The original smoke deliberately did not define a numeric accuracy score. A
separate post-prediction source audit checked the four completed panels against
the retained source context: sixteen declared fields and eight unknown fields
matched that review. It is agent-reviewed, exposed development evidence, not
independent acceptance or four new food families. The audit does not change the
original smoke report or its scoring scope.

External immutable report:
`/Users/sertanyamaner/Documents/ChatGPT/New project/nutrition-structured-proposals-v1/generic-source-v1/workflow-live-smoke-v1/report.md`.
The separate source audit is
`Tools/GenericFoodProposalEvaluation/workflow-live-smoke-post-prediction-audit-v1.json`.

### Generic explicit-market repair

The original v1 selector again chose `https://ie.fage/yoghurts/fage-total-0` for an
explicit UK request. Its previous correct abstention on different retained lead
metadata did not establish reliable country selection. The paid observation is
preserved as a failure.

`food-source-market-conflict-v1` now rejects a recognised contrary country marker
after source choice and before capture. Supplied URLs pass the same check; a final
redirected document URL is checked before extraction. The latter cannot prevent
the redirect fetch itself. All discovered links remain available, and no other
source is automatically retried. A specific UI explanation distinguishes the
market problem from credentials or provider availability.

This is a conservative URL-marker safeguard, not proof of the source's market.
Its deliberately narrow initial table recognises UK/GB, Ireland and Taiwan in
country suffixes, leading host labels and leading path/complete en/zh locale
segments. It handles the observed `ie.fage` form without per-brand handlers.
Language-only paths and unrelated suffixes such as `.io`, `.ai`, `.co` and `.tv`
do not establish a country. Only one explicitly named supported query market
activates rejection; multiple markets or unrecognised geography remain unknown.
Other countries, neutral URLs, spelling variants and country applicability still
require model judgement and explicit source review. Future table extensions need
versioned policy tests rather than a website parser.

Focused contracts cover selected and supplied sources, no-selector operation,
redirects, no automatic fallback, same/unknown/contradictory markers, word
boundaries, ambiguous queries and alternative-link presentation. The exact live
FAGE request/response pair also replays through the current adapter and reviewer:
two retained provider responses, then `sourceMarketConflict`, with zero capture
or extraction calls. The six-case older orchestration replay still passes.
Neither replay can access the network or credentials.

### Verified state and accounting

After this production repair, the full package suite passes **684 tests**, with
two intentional skips and zero failures; opt-in source-choice and workflow replays
were enabled. The Python evaluator suite passes **89 tests**. The complete native
simulator suite passes **283 tests**, and Xcode static analysis succeeds. The only
analysis warning concerns the existing absence of an AppIntents framework
metadata dependency. Logs:

- `/private/tmp/nutrition-generic-full-package-v9.log`
- `/private/tmp/nutrition-python-gates-v11.log`
- `/private/tmp/nutrition-market-conflict-v1.log`
- `/private/tmp/nutrition-market-conflict-live-replay-v1.log`
- `/private/tmp/nutrition-generic-simulator-tests-v8.log`
- `/private/tmp/nutrition-generic-analysis-v6.log`

The new inventory `run-inventory-20261004-0757.json` adds verified smoke receipts
to the prior inventory, preserving all legacy limitations. All recorded scopes
contain 358 requests, 352 known costs totalling **$2.800410275**, and six unresolved
request costs. This is response-reported accounting, not a reconciled credit
statement. No unknown request is treated as free.

Remaining acceptance boundaries are unchanged: independent human/source review,
a prospectively separated holdout, source truth and applicability, confidence
calibration, and actual device interaction. Large, scanned, protected,
script-dependent or inaccessible documents can still fail the bounded reader.
This work demonstrates a functioning OpenRouter-only route and explicit failure
handling, not universal website coverage or statistical superiority over Gemini.


## Historical checkpoint: 08:15 London, 4 October

The remaining unattempted Ikari query has now completed as a separately frozen
one-case follow-up, `workflow-live-smoke-v2-ikari`. It is not a resumption or rewrite
of v1. The v2 harness retains the exact six-query original cohort and separately
records the selected one-query denominator; unknown, repeated, empty or reordered
subset IDs are rejected. It now explicitly stops on source-capture timeouts as
well as provider/reviewer/harness timeouts. V1's broad timeout criteria did not
match its handling of a known-cost keyless capture timeout, which allowed later
queries to proceed. That protocol limitation remains in the original report;
v2 closes it and has synthetic coverage.

Ikari used three calls and reported **$0.030680475**, all known, with a complete
review time of **19.630 seconds**. The official two-page PDF lacked the requested
per-100-g denominator. The extractor recommended `none`; no candidate was allowed
for confirmation. It also emitted one candidate whose nutrient references did
not bind across separate PDF value/unit blocks, so the binder rejected it as
`invalidNutrient`. This is correct no-confirmation behaviour with a rejected
candidate, not a clean bound extraction or an independent accuracy score. No
previously attempted query was called again. Plan hash:
`ccc9a5db43373fbbbc37a60588505dbe05e1273b54ba5b780a5da21971a4e252`.

A final presentation repair removes unconfigured providers from Search details.
Persisted Gemini preferences cannot create a misleading Gemini row in the new app
composition. Actual pending activity and retained failure reports remain visible,
and historical Gemini-capable callers retain their display contract.

After these changes, the full package suite passes **686 tests**, with two
intentional skips and zero failures; the evaluator suite passes **96 tests**.
All **283 simulator tests** pass, and static analysis succeeds. No further code
changes are known to be required at this checkpoint. Updated logs:

- `/private/tmp/nutrition-generic-full-package-v10.log`
- `/private/tmp/nutrition-python-gates-v12.log`
- `/private/tmp/nutrition-configured-search-status-v2.log`
- `/private/tmp/nutrition-generic-simulator-tests-v9.log`
- `/private/tmp/nutrition-generic-analysis-v7.log`

`run-inventory-20261004-0813.json` records all scopes: **361 requests**, **355 known
costs totalling $2.831090750**, and **six unresolved request costs**. The new
follow-up snapshot and every output/request/response cost receipt were verified
before inclusion. There is no pooled cross-version workflow accuracy score.

The 10:00 London continuation deadline and heartbeat remain active. Further work
should address a concrete new finding or acceptance-preparation gap; do not repeat
these completed provider calls or full build suites merely to occupy the window.
At the deadline, pause the heartbeat and hand off the exact local state, limits
and current evidence. Source/runtime snapshots and original failures remain
immutable. The shared dirty checkout remains untouched, and all implementation
is local to the attached isolated worktree. No commit, push, release or personal
HealthKit export has been performed.


## Historical checkpoint: 09:15 London, 4 October

The user extended autonomous work until 09:06 London on 5 October, reaffirmed
Xcode access, then required device testing to wait until all coding jobs are
finished, including relevant work by another agent. The heartbeat records that
sequence and condition. Do not treat the old 10:00 deadline as current authority.

Before that deferral, the opt-in native test
`testInteractiveReviewedPartialProposalSavesOnlyAfterExplicitReview` passed:
204.5 seconds, one test, synthetic data and a temporary GRDB ledger. Native
controls required representative-estimate scope and all three acknowledgements
before Continue; quantity was initially blank. Entering 50 g showed 3 g protein
from the source's 6 g per 100 g. Save remained disabled until accepting the match.
Saving created exactly one operation; reopening retained the evidence, estimate
status and unknown energy/sodium. Only fake credential validation ran; no paid
request or personal ledger was involved. The temporary ledger was removed.

Evidence: `/private/tmp/nutrition-native-interaction-run-v1.log` and
`Tools/GenericFoodProposalEvaluation/native-evidence/20261004-reviewed-partial-saved.png`.
The ordinary suite skips this opt-in interactive harness. It is separate from
the preceding 283-test simulator run and is neither physical-device nor
VoiceOver acceptance.

The other chat, “Locate issue 116 implementation”, had already merged workout
reader PR #181. GitHub main was verified as
`a1591a08324f57f7f451cb82f17cada0631fe7da`. Its 24 changed paths overlap this work
only at README.md. The isolated checkout was fast-forwarded to that exact commit
after backing up every locally modified tracked file. A three-way README merge
was clean; all 26 other modified tracked files remained byte-identical. No
untracked path collided with upstream. The receipt and original local files are
in `/private/tmp/nutrition-before-upstream-7e71tg6i/`. The shared dirty checkout
was not changed. No nutrition commit or remote mutation was performed.

Existing frozen evaluator snapshots remain immutable and retain their original
source versions. The combined app build and static analysis both succeeded without launching a
simulator or device test (`/private/tmp/nutrition-integrated-build-analysis-v1.log`).
Warnings were the pre-existing AppAuth `resumeExternalUserAgentFlow(with:)`
deprecation and missing AppIntents framework metadata; no errors were reported.
Do not attribute previous simulator test results to the new combined tree. Further
native checks remain deferred until coding and relevant integration work are complete.


## Historical checkpoint: 09:21 London, 4 October

An evaluator preflight audit demonstrated that the previous validator accepted
boolean or negative reference nutrients, an infinite serving basis, and a string
in place of an allowed-name list. These are now rejected before freeze runtime
or credential-loader access by `source-review-gold-v2`, recorded in new plans.
All six nutrient slots remain explicit; finite zero nutrients and null unknowns
remain valid. Primary/equivalent bases must be finite and positive. Name/document
identities and abstention choices must be explicit nonempty lists. Repeating a
valid primary basis among equivalents is harmless and remains supported.

The prospective roster builder now constructs and validates every case before
creating its output directory or copying evidence. Regression tests prove that
malformed reference numbers, identities and equivalents leave no prepared output;
an invalid freeze cannot reach file hashing or credential-loader access.

All 100 evaluator tests pass in `/private/tmp/nutrition-python-gates-v15.log`.
A read-only structural check of 33 retained frozen plans (301 case instances,
including repeated foods and routes) passes the corrected validator. This is
compatibility evidence, not 301 independent foods or new quality results.
Receipt: `/private/tmp/nutrition-gold-preflight-retrospective-v2.json`. Historical
plans, runners, raw sources, predictions and scores were not changed. No provider
call was made. Swift code is unchanged since the combined build/analysis above,
so no additional simulator run was needed or started.


## Requirements audit: 09:25 London, 4 October

The [completion audit](generic-food-proposal-completion-audit-v1.md) maps the
original requirements to current source, tests and retained live evidence. It
confirms 16 user descriptor seeds within the 24 authored cases (16 local/general,
8 Taiwan-market), while preserving their fictional-nutrition label. The TFDA
adapter and catalogue are byte-identical to current merged main.

Completion remains unproven: the other chat is coding privacy/backup release
prerequisites, so its eventual relevant merge must be reconciled before the final
combined simulator run. Device testing remains deferred. No new provider calls,
Swift edits, commits or remote mutations occurred during this audit.


## Historical checkpoint: 09:30 London, 4 October

The evaluation framework now includes an offline prospective-holdout preflight.
`holdout_audit.py` verifies supplied frozen development plan/document hashes and
checks shared comparison IDs, normalised queries, declared families, source
domains/explicit domain groups, URLs and raw source hashes. Unattempted planned
cases also count as exposed because their references may already have informed
development. Omitted history and semantic aliases cannot be inferred; source
review is still required. Passing never claims independent accuracy or confidence
calibration.

`frozen_run.py freeze --holdout-against EXPOSED_RUN` (repeat for each relevant run)
rejects overlap before runtime/credential-loader access or output creation. A
passing report and exposure index are retained in the hashed snapshot. Ordinary
development runs remain explicitly labelled and historical snapshots unchanged.
The new audit correctly rejects all 19 existing public cases as a fresh holdout
when compared with the already-exposed Grok run. Report:
`Tools/GenericFoodProposalEvaluation/public-19-holdout-overlap-audit-v1.json`.

All 109 evaluator tests pass (`/private/tmp/nutrition-python-gates-v16.log`), including
tampered evidence, path escape, credential-file rejection, all overlap axes,
unattempted cases, freeze-before-spend and successful audit retention. No new
provider call or device test ran. The other chat remains active with its privacy/
backup release work; final combined integration and simulator gates remain pending.


## Pending PR #182 integration preparation: 09:37 London, 4 October

The other chat's coding change is now PR #182, inspected at head
`434d40e3b338c9be6956d1e549c9245ad7eb4ee8` on base `a1591a0`. It adds privacy-policy
access and backup exclusion, including a small storage-directory change in
`FoodLedgerCompositionRoot.swift`. Preserve that protection during integration.
The other chat is delivering this PR; this task does not merge it remotely.

Its policy correctly describes its released Gemini baseline. The local nutrition
composition needs a subsequent OpenRouter-specific policy update. Exact prepared
text is `/private/tmp/nutrition-openrouter-privacy-policy-prepared.txt`; its receipt
and expected upstream policy hash are in the adjacent `.json`. It covers explicit
query actions, Exa/source-selection data, public-source text sent for extraction,
local review evidence, separate provider/search retention, and legacy unused
Gemini keys. It preserves the other agent's HealthKit, Drive, backup and reversible
food-history disclosures. No policy has been applied or published yet. Compare
the merged policy with the receipt before applying this prepared update; revise
against any changed upstream wording rather than replacing it blindly.

Official sources checked on 4 October:

- [OpenRouter ZDR scope](https://openrouter.ai/docs/guides/features/zdr) applies to
  inference routing, not every enabled search service or plugin.
- [Provider policies](https://openrouter.ai/docs/guides/privacy/provider-logging)
  distinguish model handling from third-party tools.
- [Exa's public policy](https://exa.ai/privacy-policy) permits query use for service
  improvement/training and distinguishes separately governed business processing.
  The specific OpenRouter/Exa agreement was not inspected; no search ZDR guarantee
  is claimed.

The official [server-tool migration page](https://openrouter.ai/docs/guides/features/server-tools/web-search)
labels the web plugin deprecated and describes model-controlled zero-to-many
search calls. The [plugin page](https://openrouter.ai/docs/guides/features/plugins/web-search)
still documents the current fixed Exa request and one search per request. No
removal date was established. Retain the qualified one-search adapter for this
checkpoint; replacing it with the beta server tool would require a separately
versioned request-count/cost contract, provider qualification and fresh workflow
evaluation. Existing live results do not validate that replacement.


### Verified dependency wait: PR #182 hosted attempt

The required hosted run `37189201443` completed with 311 passing tests and one
failure in `FoodSearchQuantityNativeTests.testGeminiSuggestionsRenderWithoutScriptsOrPersistentStorage`,
an existing synthetic WebKit text-readiness assertion. The privacy tests passed.
The owning WeeklyHealthReport worker retained the failed `.xcresult`, confirmed
that this test was unchanged, passed a focused local recheck and requested one
retry of the failed hosted job. Root cause is not established here. Do not convert
the retry into an unqualified first-attempt pass or edit this shared test while
its owner is diagnosing it. PR #182 and final nutrition integration remain pending.

For compact dependency status use worker chat
`01a10423-e413-7cd2-9170-60633cbb7eda`; parent chat
`01a10414-79bc-7141-988c-871c3fa7fa31` also coordinates unrelated PacePrompt tests.
Read-only monitoring does not authorise messages or release actions from this chat.
The worker was confirmed active when the retry was requested. No additional
nutrition tests, provider requests, code edits or device checks were run while
waiting for this dependency.


## Final combined verification

PR #182 merged at `fcf3c8c8c3f638dd14f2dfeb88a2213020063297`. Both overlapping
files (README and FoodLedgerCompositionRoot) merged cleanly; all 25 other modified
tracked files remained byte-identical. Backup-excluded directory preparation stays
before ledger access. The prepared OpenRouter policy was applied only after its
expected upstream hash matched. Final app-bundle and source policy bytes match.

After coding settled, the complete combined simulator suite passed 315 tests with
one expected opt-in skip and zero failures; static analysis succeeded. The existing
WebKit test passed locally in 2.578 seconds. The final gate log is
`/private/tmp/nutrition-final-integrated-simulator-analysis-v1.log`. No source edits
followed this gate. Existing AppAuth, synthetic HKWorkout initializer and AppIntents
warnings remain. The 314-file source/configuration index and retained log hashes
are in `Tools/GenericFoodProposalEvaluation/final-verification-20261004.json`.
No extra provider call, physical-device test, personal Health export or nutrition
release occurred. The final handoff explicitly retains independent-acceptance and
future delivery boundaries.
