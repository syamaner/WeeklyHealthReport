# Unified food search contract v1

Status: agreed 29 September 2026; coordinator/UI and the first OFF database adapter with default-off settings implemented locally. Default-off Gemini composition and Alpro/Arla/Oatly UK source admission implemented locally on 30 September. Narrow named-dish discovery and labelled unknown-preparation alternatives are locally validated. See [delivery readiness](unified-food-search-delivery-readiness-v1.md); broader source coverage, fresh live quality and device acceptance remain pending.
Stories: [#148](https://github.com/syamaner/WeeklyHealthReport/issues/148),
[#172](https://github.com/syamaner/WeeklyHealthReport/issues/172),
[#100](https://github.com/syamaner/WeeklyHealthReport/issues/100).

## Product contract

Search once. Show local results immediately, including saved exact aliases, then
use an enabled online database when more evidence is needed. Reassess the combined
results before using enabled Gemini with valid BYOK. Skip unavailable services.
Keep the results usable while enrichment runs; the user chooses a candidate or None.
There is no separate web-search tap in the normal experience. Retain a manual
Gemini trigger only in debug controls, subject to the same access and evidence rules.

Match confidence, nutrition completeness, source-basis applicability and missing
user quantity are separate dimensions. A sufficient candidate must itself have a
strong match, complete required nutrition and compatible basis. Do not combine
one candidate's strong identity with another's complete nutrients. A missing amount
alone needs user input, not another provider call. A missing source basis/conversion
may justify enrichment. Confidence categories require evaluated assessment rules;
exact-name matches or lexical ranking scores alone do not establish strong identity.

Enrichment proposes alternatives. It does not accept, save or silently replace a
selected food. Different source records remain distinct. Deduplicate only identical
source-release/record identities, rejecting conflicting payloads. Never silently
combine nutrients, raw/cooked states, units, density or portion weights. Source and
record identifiers belong under expandable details. Missing fields stay explicit.

## Architecture gate

- Domain: existing closed identity, provenance, nutrient, quantity and save rules.
  No domain schema change is needed for routing. Source admission remains versioned.
- Application: `FoodSearchEscalationPolicy` owns deterministic stage decisions;
  `FoodSearchSession` consumes each stage token once and rejects old completions,
  including responses from another session. Session identifiers can be injected in tests.
  `ProgressiveFoodSearchCoordinator` owns tasks, incremental candidate batches and
  independent candidate assessments. It publishes local results before awaiting I/O.
- Infrastructure: online database and Gemini adapters own HTTP, credentials and
  source parsing/admission. A narrow consumer-owned enrichment port receives only
  displayed food terms, never a ledger request/history/evidence object. Alternate
  adapters must pass the same request, provenance, cancellation and failure contracts.
- Presentation: one results list, explicit selection/decline, compact loading/failure
  state, service settings and debug controls. Composition root wires concrete adapters.
- Dependencies: application imports only domain/Foundation; no UI, provider SDK,
  Keychain or network dependencies. Existing Swift package target boundaries enforce
  this split. Neither routing nor provider confidence can override admission/save rules.

The coordinator is wired into `GenericFoodSearchViewModel`. The app composition root
now supplies the OFF text-search adapter behind an explicit default-off preference.
It merges accepted batches and assesses actual candidates; model-self-reported
confidence is not admission. Default-off Gemini acquisition/admission and the exact validated-key lifecycle are
now wired and synthetically tested. This local implementation is not merged or
released; current live quality and device acceptance remain separate gates.

## Lifecycle and access

A submitted search begins with local retrieval. Each stage is consumed at most once;
no automatic retries or calls per keystroke. A failure may advance to the next eligible
service and must preserve already published results. Query/preparation edits, new
submission, service disable, leaving the flow, selection and decline invalidate the
session and cancel transport. Late responses from cancellation-ignoring providers
cannot publish. The chosen candidate and quantity snapshot are immutable for review.

Service enablement is separate from key presence. Existing keys do not opt users into
new automatic transmission. Enablement explains displayed terms, billing and retention;
validation sends no food terms. A rejected credential makes Gemini unavailable;
permission, quota and connectivity failures do not prove rejection. Disable/remove
cancels pending work. Store user keys in ThisDeviceOnly Keychain. Never attach HealthKit,
diary history, saved-food records or capture evidence to remote requests.

## Evidence and evaluation

The old explicit-tap [v1 discovery contract](gemini-grounded-food-discovery-plan-v1.md)
is historical delivered behaviour, superseded as the target product experience.
Citation leads remain unverified until the separate nutrition admission contract passes.
The existing citation-only adapter cannot satisfy a nutrition-enrichment port unchanged.

Compare local-only, local plus database and full staged search over identical queries.
Label acceptable closest matches separately from exact matches and incompatibilities.
Measure useful selectable recall/rank, incorrect candidates, correct/complete fields,
preparation/basis compatibility, incremental provider benefit, escalation decisions,
latency and per-search calls/cost. Include service failures and stale responses, plus
save/reopen regressions. Freeze fresh independent acceptance labels; consumed holdouts
and v1–v22 artifacts remain development/historical evidence and are not overwritten.

Synthetic contract tests prove stage order, access gating, same-candidate sufficiency,
no retry, stale/duplicate rejection and cancellation. Actual adapters then need shared
contracts, paired evaluation and UI/save/reopen tests. Run package, simulator and static
analysis gates once the slice stabilises; device/provider acceptance stays separate.

## Foundation validation — 29 September 2026

Implemented `food_search_escalation_v1` and the session lifecycle guard on local
branch `codex/unified-food-search`, based on `312b20c` (the open #176 branch).
The isolated checkout preserves the frozen evaluation directories in the primary
checkout. That first slice did not yet wire the policy into the application; the subsequent
coordinator slice below does.

- 14 focused policy/session tests pass, including service eligibility, separate
  nutrition/basis gaps, missing amount, same-candidate sufficiency, failures,
  duplicate/stale completions and cross-session isolation.
- Full FoodLedgerKit package: 274 tests, one optional OFF replay skipped, zero failures.
  One earlier final rerun stalled in the existing presentation test bundle and was
  stopped; the bounded unbuffered rerun passed. The cause was not established.
- Full app simulator suite: 279 passed on iPhone 17 Pro / iOS 26.5.
- Xcode static analysis and `git diff --check` passed. Analysis retained an existing
  AppAuth deprecation warning and the no-AppIntents metadata notice.
- No live provider calls or device/release validation were performed for this slice.

Commands: `swift test --package-path Packages/FoodLedgerKit`;
`xcodebuild analyze` and `xcodebuild test` with project/scheme `WeeklyHealthReport`,
simulator destination `05401B02-3665-4219-B862-52D9D3C7807E` and signing disabled.
The focused package filter is `FoodSearchEscalationPolicyTests`.

The coordinator slice below implements the next application/UI milestone. Keep the
story open until admitted online adapters, enablement settings and acceptance pass.

## Coordinator slice architecture gate — 29 September 2026

The next slice wires the application coordinator into the existing search view model.
Local search remains synchronous for the existing immediate-result contract; remote
work is asynchronous and cancellable. Provider ports receive a bounded `foodTerms`
value only; all query evidence and local history stay inside the application.

A pure merge validates route/candidate alignment and source/evidence identity before
appending a batch. It retains existing row order, deduplicates identical source/record
payloads, and rejects conflicting batches atomically. Selection snapshots the current
confirmation then stops enrichment. View-model invalidation and lifecycle events
cancel tasks and invalidate session tokens, including cancellation-ignoring providers.

A conservative versioned assessment checks core nutrition, requested preparation and
quantity basis separately. Only already confirmed local alias reuse can establish a
strong match in this slice; ordinary lexical matches remain uncertain until #100
calibrates a broader assessment. This is a routing rule, not nutrition admission.
Remote adapters cannot claim saved-library reuse. The current citation-only Gemini
adapter remains a debug tool and is not injected into the nutrition-enrichment port.

Tests must cover progressive publication, stable rows/selection, deduplication and
atomic rejection, minimal outbound payload, every service gate, failure fallback,
stale queries and service disable, as well as quantity/save/reopen regressions.

## Coordinator implementation boundary

`FoodSearchResultMerger` keeps the first row for an unchanged source-release/record
identity. Repeated capture occurrences and ranking hints can differ; capture evidence
is retained without replacing the first candidate's links or merging nutrient values.
Every source fact, nutrient value/provenance, release manifest and reused evidence ID
must agree. A conflict rejects the whole batch before publication. Different releases
remain distinct. The coordinator retains original input evidence if local retrieval
fails before an admitted remote candidate arrives. Identifier generation is injected.

`ConservativeFoodSearchCoverageAssessment` treats exact names as uncertain and only
confirmed local reuse as strong. Its v1 required fields are energy, protein,
carbohydrates, total fat and sodium; resolved exact values count as complete for
routing, while unknown, bounded or conflicting values do not. Other nutrients stay
explicitly unknown where absent. Preparation and source basis are separate checks;
no density, portion weight or nutrition is inferred. Broader confidence calibration
remains #100 work. The conservative policy may call an opted-in database for every
non-reused local query; it is not a calibrated network/cost optimisation.

The view uses stable source/record IDs and append-only ordering. Selecting a row
freezes confirmation/quantity and cancels enrichment. Status content is below results,
with a reserved toolbar spinner, so status transitions do not move existing rows.
Manual Gemini is reachable only after enabling Developer tools in Search options.
This debug preference does not opt the user into automatic remote requests.

Remaining: admitted online database/Gemini adapters, shared contracts against those
actual adapters, persistent service enablement/validated-key lifecycle, calibrated
paired evaluation and representative device/accessibility checks. No provider was
called to implement or test this coordinator slice.

## Coordinator validation — 29 September 2026

The coordinator and progressive UI are implemented locally in the same isolated
`codex/unified-food-search` checkout; changes remain uncommitted and unreleased.

- 26 focused tests passed: 22 new coordinator/merge/presentation cases plus four
  existing quantity handoff and save/reopen regressions.
- Full FoodLedgerKit package: 296 tests, one optional OFF replay skipped, zero failures.
- Full app simulator suite: 279 passed on iPhone 17 Pro / iOS 26.5.
- Xcode static analysis and final whitespace/diff checks passed. The build reported
  the no-AppIntents metadata notice; there were no new analysis findings.
- The application target still composes local sources only. Synthetic delayed
  providers prove orchestration and presentation behaviour, not online retrieval
  quality, provider nutrition admission, device acceptance or a TestFlight release.

The same package/analyse/simulator commands above were used. The focused filter was
`ProgressiveFoodSearch|FoodSearchResultMergerTests|SearchQuantityHandoffTests`.
No frozen evaluation files in the primary checkout were changed.

## Open Food Facts text-search architecture gate — 29 September 2026

The first runtime database adapter uses OFF's documented legacy full-text endpoint
(`/cgi/search.pl`, requesting the 3.6 product representation). v2 structured search
cannot implement plain food terms; the endpoint is isolated behind an adapter-owned
transport so its replacement does not affect routing or admission. One submitted
search requests at most ten products, with no pagination or detail-fetch fan-out.
Use a shared transport instance at the composition root, bounded response/time,
no redirects/cookies/cache, a seven-second attempt interval and no automatic retry.
Only displayed food terms and fixed API parameters leave the app.

Extract the existing mass-product projection without changing its barcode behaviour.
Both barcode and text search use the same whole-record nutrient admission rules:
explicit mass pack/basis, one packaging input set, no inferred preparation/density,
exact-product provenance and unknowns. Text search must validate returned GTINs,
require all meaningful food-name tokens in the product name/brand, deduplicate
identical products and reject conflicting duplicate codes. Search rank is not
identity confidence. Persisted results retain source hash, timestamp and licences.

A default-off, separately persisted OFF toggle enables automatic database fallback.
Changing it cancels the current search; it never submits the existing query.
The app composition root owns preferences and the shared adapter. Gemini automatic
nutrition stays unavailable until its separate source-acquisition/admission adapter
exists; the existing debug key/discovery controls remain available. Do not present
an operational Gemini toggle that cannot yet enrich results.

Contract tests cover outbound fields and rate/size/failure/cancellation boundaries,
shared barcode/search projection semantics, malformed and unrelated products,
conflicting duplicates, unknown/exact-product preservation, and default-off settings
including cancel-without-resubmit. No live provider calls are part of this slice.

API references: [OFF API guide](https://openfoodfacts.github.io/openfoodfacts-server/api/)
and [official search handler](https://github.com/openfoodfacts/openfoodfacts-server/blob/main/cgi/search.pl).

## OFF implementation boundary

`OpenFoodFactsSearch` is composed in the application with one shared
`OFFHTTPSearchTransport` instance. `off-search-mass-candidates-v1` reuses the existing
mass-product nutrient projection. Returned consumer GTINs must validate; case-level
GTIN-14 is not admitted. The selected product JSON is hashed independently, and
retrieval time/licences are carried in the source release. The original local query
and remote-query evidence remain distinct; no barcode scan is fabricated.

The settings screen is **Search options → Search services → Open Food Facts**.
Its v1 preference defaults off and is independent of debug tools or Gemini key
presence. Enable/disable cancels without resubmitting. Gemini has no misleading
operational switch while its nutrition adapter is absent. Existing debug credentials
and citation discovery remain unchanged.

This is retrieval/admission infrastructure, not evidence of improved recall or
save success. Liquid/ambiguous-basis records remain omitted. Exact-product unknown
identity blocks saving; generic estimate tolerance is not applied to these records.
No sodium conversion, cross-record backfill, recipe inference or new source-basis
conversion was introduced. A future wider source admission must be separately
versioned and evaluated. The legacy search endpoint is replaceable behind the
transport; unavailable responses preserve the local result list.

## OFF slice validation — 29 September 2026

- Focused adapter/settings/regression suite: 26 tests, 25 passed and one optional
  OFF replay skipped. This includes 12 new cases in the OFF/settings slice.
- Full FoodLedgerKit: 308 tests, 307 passed and one optional replay skipped; zero failures.
- Full app simulator suite: 279 passed, zero skipped/failures, iPhone 17 Pro / iOS 26.5.
- Xcode static analysis passed; only the existing no-AppIntents metadata notice.
- Final `git diff --check` passed. No provider, device or TestFlight acceptance.
- All unified-search changes remain uncommitted/unreleased in the isolated worktree.
  The frozen evaluation directories in the primary checkout are unchanged.

Evidence: `/tmp/unified-off-focused-final.log`, `/tmp/unified-off-package-final.log`,
`/tmp/unified-off-analysis.log`, `/tmp/unified-off-simulator-final.xcresult` and
`/tmp/unified-off-simulator-summary.json`. Commands are the package/analyse/simulator
commands recorded above; focus filter `ProgressiveFoodSearchPresentationTests|OpenFoodFactsSearchTests|OFFHTTPSearchTransportTests|OpenFoodFactsLookupTests`.

## OFF quantity-free query repair — 29 September 2026

Responsibility stays in the OFF adapter: the existing parser separates intake
quantity from food identity, and the adapter reconstructs provider keywords from
the food and its parsed descriptors. Mass, volume and count are not sent as
product keywords. Brand, preparation, fat percentage and other identity descriptors
are retained. Original input remains capture evidence; unknown identity and
explicit selection remain mandatory. Recognised brand tokens also participate in
local filtering of returned products. No provider or domain interface changes.

The capture method is versioned `off-search-candidates-v2`; nutrient admission
remains `off-search-mass-candidates-v1`. Endpoint, transport limits and projection
are unchanged. Legacy keyword search remains provisional pending a separate
Search-a-licious evaluation. This repair alone does not establish recall improvement
or resolve OFF 503 responses.

Contract tests cover quantity removal across mass/volume/count, preserved brand and
preparation/fat descriptors, original evidence, fat alternatives, unknown identity,
brand mismatch and clarification before networking. Newly run OFF evals retain
30-second spacing and stop on service errors; frozen v23 results are not overwritten.
The original v23 app inputs were archived with hashes in the primary checkout at
`Tools/LocalHybridSearchEvaluation/off-query-fix/` before this change. The v23 live
input verification will correctly reject the changed app checkout.

Validation: FoodLedgerKit 312 tests executed (311 passed, one optional OFF replay
skipped), full simulator 279 passed, Xcode static analysis passed, final diff check
passed. Logs: `/tmp/off-query-fix-package.log`, `/tmp/off-query-fix-analysis.log`,
`/tmp/off-query-fix-simulator.xcresult`. A separate four-case diagnostic through the
actual repaired adapter sent `brown rice boiled` and received HTTP 503 on its first
call; it stopped without sending the remaining three. Live coverage improvement
is not yet established. No commit, push, device installation or release.

## OFF bounded retrieval v2 — approved 29 September 2026

The user approved replacing the single OFF request limit with one submitted OFF stage containing at most one Search-a-licious search and two distinct v3.6 product-detail requests. Earlier single-request/full-text descriptions above are historical checkpoints and are superseded for this slice.

Architecture gate: the existing `FoodSearchEnriching` application port, coordinator, UI and closed nutrition admission remain unchanged. `OFFHTTPSearchTransport` owns the discovery/detail protocol, response validation, request budget, deadline and cancellation. Raw index nutrients are never returned to admission. The existing product projection receives only validated detail products. The composition root retains one shared transport, so query changes cannot create fresh rate-limit budgets.

Each physical request starts at least seven seconds after the preceding attempt on that transport, including failed/cancelled attempts. New submissions during an active stage or cooldown are rejected without networking. The complete stage, including waits, is capped at 20 seconds with monotonic cancellation. Maximum ten discovery hits, two distinct checksum-valid consumer GTINs, 500 kB per response and 500 kB assembled product envelope. No pagination, retries, redirects, cookies, credentials or alternate-host fallback. Product details must return the requested identity; exact product-not-found may consume a slot and advance to the other already-selected code. Other failures stop the stage and preserve previously published local results.

Requests use the documented POST search contract and GET v3.6 product details. Displayed terms are escaped as literal search terms, not accepted as query-language instructions. The current assessor cannot establish strong identity from a remote lexical result, so nutrient completeness alone does not short-circuit the second permitted detail read. Admission, sodium, mass/volume, percentage discovery and Gemini nutrition remain subsequent separately validated changes.

Validation covers actual URLSession transport with synthetic replies: request shape/privacy, zero/one/two detail calls, duplicate/invalid/case-level IDs, failed and timed-out search envelopes, wrong detail identity, exact 404 versus service failure, oversized responses, shared pacing, concurrent submissions, cancellation during pacing and HTTP, and total deadline. Reuse all existing search/barcode/lifecycle contracts; then full package, simulator and static analysis. No live provider calls are part of implementation validation.

API references: https://openfoodfacts.github.io/search-a-licious/users/ref-openapi/ and https://openfoodfacts.github.io/openfoodfacts-server/api/ (checked 29 September 2026). The documented product-read limit is 15/minute/IP; seven-second spacing on this shared search transport stays below that without bypassing the separate existing barcode throttle.

### Bounded retrieval v2 validation — 30 September 2026

Implemented locally: new `OFFHTTPSearchTransport.swift`; the existing application port and mass-only admission remain unchanged. Thirteen new transport contracts pass. Full FoodLedgerKit: 325 tests, 324 passed and one optional OFF replay skipped; zero failures. Full iOS 26.5 simulator suite: 279 passed. Static analysis passed, with only the existing no-AppIntents metadata warning. Final diff checks passed. No new live-provider, key, device, commit, push or release activity.

The raw captured-response replay completed Heinz's two detail reads; Alpro, FAGE and Ambrosia remained capture-incomplete because the selected codes were not all in the previous capture. This is not a live service failure or retrieval-quality acceptance. The transport currently chooses the first two distinct checksum-valid consumer codes in server order; it does not reuse the prototype's hand-reviewed per-query selection. Search query construction also differs from that older capture. Current OFF admission and source-confidence gaps remain as documented in the evaluation; the request-budget change does not resolve them.

Reproduce checks with `swift test --package-path Packages/FoodLedgerKit`; focused filter `OFFStagedRetrievalTests|OFFHTTPSearchTransportTests|OFFHTTPSProductTransportTests|OpenFoodFactsSearchTests`; `xcodebuild test` / `xcodebuild analyze` using the project/scheme `WeeklyHealthReport`, simulator `05401B02-3665-4219-B862-52D9D3C7807E`, signing disabled. This run used `/tmp/unified-food-search-derived`, `/tmp/off-stage-v2-simulator.xcresult` and `/tmp/off-stage-v2-analysis.log`. Frozen v46 evidence is retained in the primary checkout's `Tools/LocalHybridSearchEvaluation/v46`, including the 82-file pre-change v45 application snapshot.

## OFF direct sodium projection v3 — 30 September 2026

Architecture gate: the shared OFF adapter owns interpretation of source fields; domain nutrient values, units, provenance and persistence contracts stay unchanged. Admit sodium only from the already-selected, single packaging/as-sold/per-100-g modern input set, with an explicit numeric `value` and `g` or `mg` unit. Preserve original source amount/unit/bounds and record a versioned gram-to-milligram transform when needed. Keep computed-only values, salt conversion, legacy sodium, other panels, serving and volume conversions unknown. Legacy `_100g` values use normalised units and cannot safely inherit contributor units.

Version the projection, source schema and release identity so changed interpretation cannot collide with an old release. Identity and confidence rules remain closed and unchanged. Barcode and search share admission. Contracts cover exact/zero/bounded conversions, invalid/overflow values, computed-only and legacy rejection, source provenance, shared paths and save/reopen. Validate a captured-response replay separately from retrieval quality, then full package, simulator and static analysis. No live calls are required.

Source format reference: [OFF Nutrition module](https://openfoodfacts.github.io/openfoodfacts-server/dev/ref-perl-pod/ProductOpener/Nutrition.html) distinguishes declared `value` from `value_computed`; [product schema](https://openfoodfacts.github.io/documentation/docs/Product-Opener/schemas/schemas/product/) distinguishes legacy normalised values from contributor units (checked 30 September 2026).

### Direct sodium v3 validation

Four new contract methods pass, and existing barcode/search parity plus explicit-correction save/reopen contracts now exercise converted sodium. Full FoodLedgerKit: 329 tests, 328 passed and one optional replay skipped; full simulator 279 passed; static analysis passed. Captured v47 replay: Ambrosia retains 0.04 g as 40 mg per 100 g, making runtime nutrition complete; match remains uncertain and all six unknown identity fields persist. Original-query sufficiency remains 0/4. Other original query outcomes and the separate FAGE diagnostic are unchanged. No live requests, new credentials, device acceptance, commits, pushes or release. Evidence is frozen in the primary checkout at `Tools/LocalHybridSearchEvaluation/v47`; the pre-change v46 app inputs and earlier artifacts remain preserved.

## Literal percentage and category discovery v1 — 30 September 2026

Architecture gate: application-owned `ParsedFoodQuery.allowsCandidateDiscovery` separates candidate discovery from quantity/identity resolution. Only a sole `percentage_meaning_unknown` clarification may proceed; all other ambiguities/rejections remain blocked. The parser continues returning clarification with no quantity. Presentation, coordinator and OFF use this same versioned eligibility rule. No change to save policy or strong-match assessment.

OFF relevance v3 may use one explicit English category to cover name terms missing from a branded product, only when the product's nonempty brand tokens are present in the query. Category labels remain visible on the candidate and do not become verified identity. Never combine multiple category fragments, translate unknown tags, treat a category as a brand or drop remaining query tokens. Literal unspecified percentages must match the product name's explicit percentage; this neither infers fat nor normalises nutrition. Greek versus Greek-style remains a visible source difference. No fuzzy spelling repair in this slice.

The original query remains evidence; discovery carries only the quantity-free literal descriptor. Search capture/match and search source schema versions advance; barcode/nutrient conversion contracts remain unchanged. Tests cover literal descriptors, wrong/missing percentages, category/brand negatives, unrelated terms, multi-reason ambiguity, presentation/coordinator eligibility and no quantity prefill. Replay the same captured products before broadening validation; no new live requests.

### Literal discovery validation

v48 completed: 335 package tests (334 passed, one optional replay skipped), simulator 279 passed, static analysis passed. Original captured queries now have 2/4 complete nutrition profiles; sufficient matches remain 0/4. Literal percentage and category discovery do not resolve identity or quantity. The real UI/coordinator/OFF test passes. Frozen v48 evidence remains in the primary checkout.

## Explicit mass/volume projection v4 — 30 September 2026

Architecture gate: OFF selects exactly one modern packaging/as-sold panel whose explicit per-100 basis agrees with the unambiguous mass or volume package unit. Domain `ResolutionBasis.per100Millilitres`, source nutrient values, quantity and save/persistence contracts already support volume. Extend the shared adapter rather than add a provider-specific domain type. Source nutrients keep their original panel and basis; sodium unit conversion is independent of food mass/volume. Legacy volume, serving normalization, density, cross-panel backfill and mixed/duplicate compatible panels remain unsupported. When optional per_quantity/per_unit are present, require consistency with the declared per-100 basis.

Version the projection, source schemas and match metadata; preserve prior source releases. Source basis selects interpretation, not consumed amount. Tests cover volume units, missing/contradictory metadata, same/other basis panels, computed sodium, mass/volume coverage and volume save/reopen/offline reuse. Replay original queries unchanged, with a separately labelled captured Alpro name diagnostic to measure admission without claiming original-name relevance. No live provider calls.

### Explicit basis validation

v49 completed: 339 package tests (338 passed, one optional replay skipped), simulator 279 passed, static analysis passed. Save/reopen/offline reuse contracts preserve both mass and volume bases. The separately labelled captured Alpro diagnostic retains the volume panel's 1.8 g fat per 100 ml and leaves sodium unknown; no values are borrowed from its mass panel. Original-query complete profiles remain 2/4 and runtime-sufficient matches 0/4. No new live-provider, credential, device or release activity in v49. Frozen evidence and the 125-file pre-change v48 snapshot remain in the primary checkout.

## OFF full-text query construction v3 — 30 September 2026

Architecture gate: only the infrastructure query builder changes. Live v50 found 0/4 candidates; v51's three paced syntax probes identified unfielded quoted terms targeting a literal `*` field in deployed OFF. Use lowercase space-separated escaped text, without injected quotes/AND. Lowercase reserved boolean words, escape Lucene punctuation including range/field/regex/wildcard syntax, and preserve original evidence in the application layer. Upstream parser uses uppercase reserved operators; candidate/identity/source admission remains unchanged. No confidence or nutrition rule is loosened. The same one-search/two-detail, seven-second pacing and 20-second stage budget applies. Test literal/percentage/Unicode/operator inputs and full existing transport contracts, then full package/simulator/analysis and the separately frozen four-query live replay. Preserve v50/v51 evidence.

## OFF category singular/plural equivalence — 30 September 2026

v52 repaired live query construction: four successful stages returned eight detail products; two of four original queries yielded candidates and one complete nutrition profile. All 340 package tests (one optional skip), 279 simulator tests and static analysis passed after updating an older request-shape expectation. No identity confidence was relaxed.

Next architecture gate: normalise only the grammatical `drink`/`drinks` pair within the existing OFF category comparison, symmetrically for missing query terms and source category terms. Keep original category labels, brand requirement, complete remaining-term coverage, percentage validation and source panels unchanged. No fuzzy matching, flavour substitution or new service calls. Advance search capture/match/schema versions to preserve interpretation provenance. Validate singular/plural positives and wrong brand/flavour/category negatives, then replay the actual v52 returned products against the same four queries. Capture replay is a paired development result, not a second live run.

### Final category equivalence validation

v53 passed 342 package tests (341 passed, one optional replay skipped), 279 simulator tests and static analysis. Replaying the exact eight v52 live-returned records changes original-query candidates from 2/4 to 3/4 and complete nutrition from 1/4 to 2/4. FAGE remains omitted and fully sufficient matches remain 0/4. This is offline replay, not a fresh live run. Issues #148/#100 record the separate evidence. No commit, push or release; the next slice is bounded variant-aware discovery selection, followed by Gemini content-bound nutrition admission. All source evidence and failed prior gates remain preserved in the primary evaluation checkout.

## Bounded explicit-variant discovery ordering — 30 September 2026

Architecture gate: OFF transport v4 gives earlier detail slots to index product names with the query's explicit literal percentage and complete remaining query-term coverage from name plus explicit brand. This is infrastructure retrieval priority only. It does not infer percentage meaning, drop flavour/preparation terms, reconstruct categories or admit index nutrition. Unknown/malformed/partial evidence preserves provider order behind explicit matches; ties preserve order. Normalised validated GTINs remain distinct and all authoritative detail checks remain unchanged. No larger budget or retry: one search, at most two details, seven-second pacing, 20-second stage deadline. Synthetic fixtures prove ordering, not real-world FAGE recall. Validate hard negatives, stable ordering, duplicate identities and detail-only evidence, then unchanged captured replay and full gates. No provider calls authorised by this slice.

## Gemini source-content admission foundation — 30 September 2026

Architecture gate: the application layer owns a pure, closed source-table binding rule and immutable evidence types. Infrastructure decodes bounded independently acquired source-projection bytes and hashes them; provider types/network/Keychain do not enter the rule. Extraction proposals must identify the selected document, product record, byte hash, exact nutrient cell and literal. The trusted source projection is never model output. Bind only direct four-macro declarations to explicit per-100-g/ml two-column panels, with contiguous nutrition-section boundaries and original declared precision. Unknown preparation, identity, sodium, serving conversions and optional formulation metadata are not inferred. A bound declaration is not a food candidate or save permission. Test captured table segments and hard negatives before acquisition/provider wiring. No live calls in this slice.

## Independent source-page acquisition boundary — 30 September 2026

The consumer-owned acquisition port returns source bytes, URL chain, timestamp and SHA-256, with no nutrition or identity assertion. Its infrastructure actor accepts an exact composition-owned host allowlist; no model-supplied host expansion, automatic redirects, cookies, credential inheritance or retries. Proposed implementation ceilings are three total HTTP attempts including redirects, seven-second pacing, 500 KB per response and a 20-second deadline. Only UTF-8 HTML 200 responses become captured content. Source acquisition is not yet wired to automatic Gemini: its complete runtime request budget and page projection remain separate integration gates. Offline URLProtocol tests incur no provider calls.

The same acquisition slice adds table projection with SwiftSoup 2.13.9, pinned exactly and confined to the infrastructure target. Its inspected manifest declares no dependencies or build plugins. This uses a maintained HTML parser while keeping DOM types outside the application boundary. Preserve row/cell/segment positions (including blank and trailing br segments), spans, table identity and raw-HTML hash; do not infer or zip nutrient values. SwiftSoup applies HTML5 tree normalisation; this is explicitly a new projection version, not a claim of strict raw-markup parity with the Python prototype. Reject nested tables, unsupported shapes and exceeded resource limits. HTML projection does not execute scripts or fetch linked resources. Test projection plus the existing pure binder with controlled/captured factual tables before live composition.

SwiftSoup’s MIT licence notice is included in the FoodGenericSearch resource bundle. Both package and Xcode resolution files must retain the exact 2.13.9 pin at delivery.

## Deterministic source-panel reading — 30 September 2026

Extend the existing binder with direct macro reading from the selected captured panel, reusing exact literal/unit/basis and section checks. Infrastructure enumerates explicit basis rows and returns separate panels; it does not choose among them or merge missing nutrients. Every profile retains document/record/hash and table/basis-cell identity. Incomplete profiles remain incomplete; generic/recipe applicability and exact-product identity are still outside this rule. The existing binding contract remains v1; deterministic reading has its own version. This work is offline and does not depend on approving additional runtime requests.

Final source-boundary review adds an explicit 4,096-byte initial/redirect URL cap under acquisition v2, checked before sending a destination. A synthetic fetch-to-HTML-projection-to-panel-binding contract verifies the same source hash and per-100-ml values across the complete acquisition chain. No Gemini or live HTTP transport is invoked.

## Exact-key validation lifecycle repair — 30 September 2026

The debug Gemini view-model now binds usability to the exact successfully validated credential in private transient memory. A replacement key cannot inherit an earlier flag; the stored key is checked before sending food terms and before publishing a reply. An old rejection does not remove a different replacement observed on completion. Leaving the flow or starting replacement validation clears transient usability. Stored keys remain solely in the existing device Keychain; no new automatic requests or persisted opt-in are introduced. Synthetic store/provider tests cover replacements before/during validation and discovery. Shared automatic-service composition remains pending.

## Raw source compatibility repair — v60

v59 actual-HTML replay recovered 0/3 reviewed product panels: Alpro exceeded the original 500 KB raw cap, while Arla and Oatly have unsupported table/basis layouts. Acquisition v3 and HTML projection v2 share a 2,000,000-byte raw HTML limit; structured projections remain bounded to 500,000 bytes. Script content remains unexecuted and omitted. DOM/table limits, request count, pacing, deadline and application admission are unchanged. The transport remains unwired pending runtime-budget approval. Replay results and full validation are recorded in v60 after execution.

Final v60: 41 focused contracts; 390 package tests (389 passed, one optional skip); 279 simulator tests and static analysis passed. Actual raw-page extraction improves from 0/3 to 1/3 reviewed positive panels; two reviewed negatives stay unadmitted and one unreviewed capture is separate. Alpro matches all four macros exactly; Arla inline basis and Oatly table-caption basis remain unsupported. No live provider/key use or release. Runtime request-budget decision remains pending.


## v61–v63 bounded Gemini runtime integration (30 September 2026)

The user approved one Gemini grounded-discovery call plus at most three HTTPS source-page attempts including redirects for one selected native citation. The limits are 30 seconds for discovery, 20 seconds for source acquisition, 50 seconds composed, seven-second source pacing, 2 MB raw HTML and 500 KB projected tables. No alternate-page or model extraction retry is allowed. This approval does not authorise a paid live evaluation or release.

Application-owned exact-key/generation grants separate transient request authority from the Keychain adapter. The shared credential editor validates explicitly without food terms; closing it cancels unfinished work while preserving completed session validation. A stored key, typing, toggling a service or opening a screen cannot send a food query. Automatic Gemini requires both separate default-off consent and a currently validated exact key, and starts only on a submitted search when coverage remains insufficient. Revalidation, replacement, removal, rejection, cancellation and deadlines reject stale grants. Only a current explicit provider credential rejection invalidates usability; quota, permission and network failures do not delete a key.

`GeminiGroundedSourceReview` selects one eligible native annotation, validates the acquired envelope, and independently projects/reads its page. `AlproSourceCandidateAdmission` is the first supported source adapter, with exact Alpro UK URL, page identity, matching product fragments and one complete four-macro table. It preserves raw/projection hashes, source-cell literals, units, basis and retrieval provenance. Model prose and unsupported pages cannot supply nutrients. No source identity field is invented. The original captured Alpro page produces one exact-product candidate with six unresolved identity fields. Explicit corrected identity can save/reopen through both stores while retaining the original source candidate and provenance.

`GeminiFoodSearch` adapts this composition to the existing enrichment port. Completed discovery metadata follows both candidate and no-candidate routes through the append-only result merger. Normal results show native citation links and the supplied Google search suggestions in the existing restricted renderer, without displaying model nutrition as food data. The developer-only manual route remains citation-only. Source acquisition failures currently end that enrichment stage and preserve earlier candidates; retaining citation metadata for those partial failures is a separate follow-up.

The six-page offline runtime replay uses the production Alpro host restriction and captured native redirect chains. One Alpro candidate is admitted; five unsupported final hosts produce unavailable-stage outcomes. This is a coverage limitation, not a six-food live recall benchmark. The earlier v60 reader score (one of three reviewed positive panels) measures a different, broader reader cohort. No paid provider requests or Keychain reads are part of these synthetic tests/replays.


## v64: partial-source failure retains discovery (30 September 2026)

A completed native discovery is now retained when its selected source fails acquisition, envelope validation or deterministic binding. The application-owned partial failure carries only discovery metadata and a typed failure reason; it contains no page or nutrition candidate. Source-review v2 maps source errors separately from Google credential errors. The enrichment adapter preserves citations and suggestions with a no-candidate outcome, including when source-specific admission throws. Merging keeps earlier food rows and displays the source failure beside the discovery links; a newer successful discovery clears an older failure. No unsupported source becomes admissible through this recovery.

Cancellation, stale exact-key grants and the composed deadline still prevent publication, including when a source client ignores cancellation. A source-only timeout inside the overall budget can retain discovery; the whole-request timeout cannot. No retry, extra source, host expansion, key deletion or request-budget increase is introduced. v63's documented loss of partial attribution is superseded by this repair.


## v65: explicit caption and inline basis locations (30 September 2026)

The source reader v2 now understands one unambiguous table caption declaring per 100 g/ml and repeated per-100 denominators in a single cell's paired segments. `FoodSourceBasisLocation` distinguishes actual header cells, captions and inline cell segments. Captions are never converted into invented cells. Each inline nutrient retains its own denominator location; original literal, unit, mass/volume basis, raw/projection hashes and source-cell coordinates remain intact. Bound declarations identify the binding version. The original header binder remains v1; new caption/inline binding is explicitly v2. Legacy cell fixtures and saved Alpro provenance remain compatible.

The closed rule rejects competing captions/headers, duplicate nutrients, mixed or missing inline denominators, unsupported serving/preparation basis, malformed segments, bounds, unsupported units and values that cannot preserve their decimal amount. A product/section heading stops the read; missing macros cannot be supplied by later sections. It admits direct four-macro declarations only, without product identity, salt conversion, density, serving extrapolation or preparation inference. Cancellation cannot become an empty successful result.

On the same six saved HTML pages, exact four-macro reader matches improve from 1/3 to 3/3 reviewed positive pages: Alpro, Arla and Oatly. Both reviewed negative pages still yield no panel. One unreviewed page remains reported separately. These are known development failures repaired against existing reviews, not held-out or live recall proof. The separate production-runtime replay still admits only the existing Alpro candidate and retains all six citation sets. The runtime host list and source-specific candidate admission are unchanged; Arla/Oatly product identity require a separate evidence gate.


## v66: manufacturer-specific identity and runtime composition (30 September 2026)

Arla UK admission requires the exact fetched canonical/og:url/Product url and @id, a matching visible heading/brand/product name, and a single ProductDetails table within the selected product container. Its data-model EAN must equal the root Product GTIN. Oatly UK admission requires an exact UK canonical page, en-gb language and UK title, with one heading/table container whose SKU matches the single root Product. Nested related products never qualify. Oatly's Product URL may be the exact canonical or its explicit same-path global catalogue alias on www.oatly.com; the alias is checked as a string, never fetched or used to establish a UK formulation. Product/table scope and SKU tie the nutrition to the current UK page. Unknown identity and formulation remain unknown. Query coverage uses selected-product words, excluding page-title boilerplate; a literal whole/skimmed descriptor must occur in the selected source name and is never inferred from a numeric fat value.

A small shared infrastructure builder retains direct four-macro source values and provenance. Alpro's v1 release metadata, schema and pointer strings remain byte-for-byte equivalent in the captured replay. Arla/Oatly use manufacturer-source-panel-v2, retaining their inline/caption basis locations and binding versions. No domain rule, source nutrient, density or conversion is added. The existing independent source admission port composes the three adapters by exact final host; unsupported sources retain discovery only.

After the focused identity, full coordinator composition and both-store save/reopen contracts passed, the app composition registered www.arlafoods.co.uk and www.oatly.com alongside the existing Alpro hosts. The same one-Gemini/one-source/three-HTTPS-attempt budget, redirect policy, default-off consent and validated-key requirements remain. These checks and replays make no live requests.

The same six captured pages and original queries now produce three reviewable candidates instead of one. All retain six unresolved decisive identity fields and are not generic estimates. Arla's original 230ml query is incompatible with its per-100-g source, so consumed nutrient totals remain unavailable; no density is assumed. After explicit synthetic identity correction, matching-unit save/reopen and quantity edits preserve the original candidate and provenance through both stores. The existing policy can retain an entered incompatible quantity with unavailable totals; this slice does not change that save policy. Device and broader live-quality acceptance remain separate.

## Preparation wording reconciliation (v68)

The pure parser now uses `food-query-parser-v3`: explicit raw/uncooked wording combined with a cooking method requires clarification before any local or enabled-provider lookup. Uncooked is represented as raw, retaining the original query and source identity. The independent `food-query-discovery-v1` percentage exception remains: a lone unresolved percentage may retrieve candidates, but cannot prefill an amount or bypass a preparation conflict. No nutrient or source metadata changes belong to this parser repair.

The actual-presentation offline audit preserves all 32 original v23 candidate outcomes, prevents all six newly constructed contradiction queries from reaching search, and verifies uncooked/raw quinoa yield equal candidate facts. The earlier 11 captured OFF/Gemini paired flows retain their source facts and request order. Descriptive soups and porridge-with-water remain pre-search clarification gaps; bare cooked-weight sirloin still has a ranking gap. These are tracked separately from missing provider coverage; this cycle makes no live accuracy or complete everyday-query support claim.

## Direct food names and explicit recovery (v69)

`generic-representation-ranking-v3` prefers a directly named requested term over a parenthetical-only mention, after primary-food matching and before generic representation bonuses. This source-neutral lexical preference never determines species or selects a candidate. CoFID matcher v8 retains full meaningful-token coverage and the existing score floor, with a narrow exception for a directly named second comma field (no parentheses or recipe connectors). USDA matcher v9 records the shared ranking change. Nutrient/source identity rules remain unchanged.

A missed whole cow's/cows-milk query can offer an explicit broader whole-milk search while retaining the entered amount and original evidence. It does not automatically strip species, return a cow-confirmed record or apply a density. The user starts the suggested search and reviews the original source name; skimmed, flavoured and other-species wording is not rewritten by this recovery. Existing exact-record milk volume conversion still requires its separate explicit choice.

The registered development contrasts and unchanged everyday/captured-provider replays are recorded in v69. These are deterministic offline behaviour checks, not held-out relevance or live provider acceptance. Boiled-method mapping and descriptive-dish discovery remain separate unfinished work.

## Preparation request interpretation — v70

`food-query-preparation-v1` interprets recognised cooking-method words as a coarse cooked-state request at the application boundary. `GenericFoodSearchRequest` resolves absent/unknown request preparation consistently for direct adapter and presentation callers while preserving explicit identity fields. Presentation and coordinator reject contradictory explicit filters; coverage uses the same query interpretation. This does not populate source metadata.

Extracted method wording is retained in local lexical retrieval and OFF candidate compatibility. Boiled is not treated as a synonym for roasted. A missing method-specific record yields no local result and remains eligible for enabled enrichment. Raw/uncooked remain raw, and ambiguous wording such as a roast cut, smoked or dried does not supply cooked state. Known raw candidates are incompatible with an unambiguous cooked request; source unknowns remain unknown. Original evidence, quantity, literal percentage meaning and explicit selection are unchanged. OFF typed-search capture policy advances to `off-search-candidates-v5`; source nutrition schema is unchanged.

Registered offline contrasts and prior replay cohorts are recorded in primary-checkout `Tools/LocalHybridSearchEvaluation/v70`. Development-corpus results do not establish live provider accuracy or device acceptance.

## Named-dish discovery — v71

`food-query-discovery-v2` permits a bounded set of single-dish descriptions through an existing clarification route: lentil-and-tomato soup (either ingredient order, optional red lentils and retained homemade/Baxters wording) and porridge made with water or milk. These are initial observed lexical forms, not a general recipe parser or a brand/ingredient assertion. Arbitrary prefixes, additional dishes, mixed quantities, portions, approximate amounts, unresolved percentage meaning and preparation conflicts do not receive this exception.

The parser retains its clarification reasons, original evidence and nil quantity. The UI explains that ingredients, proportions and consumed amount still need review. Local retrieval can use quantity-free parsed terms for these descriptions, retaining every descriptive word; enabled OFF/Gemini receive the same discovery permission. Provider budgets, source admission, nutrient basis, source unknowns and explicit selection are unchanged. Searching a named dish does not combine ingredients, infer a recipe, fill an amount or admit model-written nutrition.

Primary-checkout `Tools/LocalHybridSearchEvaluation/v71` records the 30 preregistered contrasts and measured replays. Reaching a source after a previous pre-search stop is reported separately from finding a reviewable nutrition record.

## Source-unknown preparation during named-dish discovery — v72

`food-preparation-discovery-v1` permits unknown source preparation only as an alternative for the bounded named-dish clarification path, where recipe and consumed amount remain unresolved. Ordinary explicit raw/cooked filtering, all other identity/basis constraints and strict saved-alias reuse retain their previous behaviour. Source-name words may veto an opposing raw/cooked state but never populate missing source metadata. Literal method words remain required retrieval terms.

Source-declared compatible preparation ranks ahead of unknown alternatives, including across local sources and fat preferences. Unknown rows retain their source values and show that the requested preparation is not established. Coverage remains uncertain, with preparation basis unknown and amount needing user input. Explicit confirmation and manually entered quantities are required; no source identity, nutrient value, density or recipe proportions are inferred. Matchers advance to CoFID v9, USDA v10 and composed ranking v7. Domain/source schemas are unchanged.

The primary-checkout v72 offline evaluation measures alternatives separately from proven preparation matches and keeps the earlier frozen evidence.
