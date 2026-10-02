# OFF staged retrieval integration v2 proposal

Status: concrete follow-up to the frozen v44/v45 evaluations; request budget approved by the user on 29 September 2026. Existing uncommitted implementation is in the unified-food-search worktree. No runtime change is made by this proposal.

The paired prototype improves profile coverage, but the actual Swift adapter retains only Ambrosia on the four original branded queries. FAGE is blocked by percentage parsing and an overly strict name-token rule. Automatic Gemini nutrition remains unimplemented. Preserve exact-product unknowns and user selection while closing those gaps.

## Request budget decision

The earlier #148 contract required at most one request per eligible provider per submitted query; the approved replacement below supersedes it. The successful OFF experiment instead uses Search-a-licious for discovery, followed by v3.6 details for authoritative units and packaging input sets. Index `_100g` keys alone are not basis evidence; a captured milk detail explicitly says 100 ml.

Approved replacement: **one OFF stage per submission, at most one search plus two distinct product-detail requests**. Stop early if the required evidence is sufficient. Never paginate, retry automatically, repeat a code or fetch on each keystroke. Keep local results usable throughout. Disabled OFF means zero search/detail requests. Query edits, selection, leaving the screen or disabling the service cancel both discovery and detail work; late completions cannot publish. Each call is size/time bounded and the overall stage has a deadline. Exceeding that deadline retains local results and allows the next eligible stage. Use a shared rate-limit budget across submissions; do not multiply budgets by creating adapter instances.

The existing single-request option can be retained, but then Search-a-licious results are source leads only; its index values cannot be presented as admitted nutrition. That gives up the demonstrated detail-stage benefit. No Google spending or new live evaluation is included in either option.

## Architecture and implementation order

1. Add a bounded discovery/detail transport behind the existing application-owned enrichment port. Search-a-licious schemas, GTIN validation, field query escaping, response limits and v3.6 product parsing stay in infrastructure. Product IDs come only from validated discovery hits. No model-provided URL is fetched. Keep the source detail and hash available for field provenance.
2. Version the source-panel projection to support explicit mass and volume bases and explicitly evidenced serving normalization. Preserve one complete input set per candidate; reject conflicting packaging sets or expose them as separate reviewed alternatives. No density guesses, aggregate backfill or silent cross-panel nutrient merge. Salt and sodium require distinct source fields or an explicit versioned conversion; don't rename them. Admit direct sodium with explicit unit conversion and source provenance; computed-only/estimated values remain unknown under the current closed admission rule.
3. Treat the literal branded percentage case as discovery-only until its meaning is supported. It can find FAGE Total 2% without filling a quantity or asserting that 2% means fat. Require brand/variant/category evidence under a tested relevance rule; do not merely remove inconvenient tokens.
4. Apply the same runtime rules in evaluation: four-macro profile availability, sodium completeness, preparation/basis, source disagreement, identity confidence and save eligibility are separate. Only a previously proven identity claim can stop enrichment; nutrition completeness alone cannot establish identity. A source profile is not a save success.
5. Integrate Gemini nutrition only after these adapter contracts and source-acquisition/admission contracts pass. Existing citation-only debug discovery cannot manufacture a nutrition candidate.

## Acceptance

Replay the original captured products and original queries through the real Swift adapters; keep all omissions and failures. Add contract cases for zero/two detail bounds, duplicate/invalid codes, wrong returned identity, cancellation between stages, stale completions, shared rate limiting, redirects/errors/oversize bodies, mixed bases, direct versus computed sodium and percentage discovery. Keep v42's failed run and all previous seals unchanged.

Run focused Swift tests, full FoodLedgerKit tests, simulator suite and static analysis after the slice stabilises. Save/reopen tests must retain selected source, explicit preparation, quantity and unknowns. A later bounded live run validates actual endpoints and timing; separate device testing validates the one-search experience. This proposal is not release acceptance.

Evidence: [combined replay](../Tools/LocalHybridSearchEvaluation/v44/findings.md), [actual Swift adapter parity diagnostic](../Tools/LocalHybridSearchEvaluation/v45/findings.md). Live story: [#148](https://github.com/syamaner/WeeklyHealthReport/issues/148).

## Budget implementation checkpoint — 30 September 2026

The approved transport is implemented locally in the existing worktree: 325 package tests (one optional skip), 279 simulator tests and static analysis passed. Issues #148/#172/#100 are updated. No commit, push, release or live provider calls. Runtime relevance, nutrition admission and Gemini remain later work. See [v46 findings](../Tools/LocalHybridSearchEvaluation/v46/findings.md).

## Direct sodium admission checkpoint — 30 September 2026

The shared Swift OFF projection now preserves direct modern packaging sodium, original source units/bounds and versioned gram-to-milligram conversion provenance. Captured Ambrosia changes from incomplete to complete nutrition (40 mg from 0.04 g per 100 g); uncertain identity remains and sufficient queries stay 0/4. Legacy/computed-only sodium and volume/serving conversions remain unsupported. Full package 329 tests (one optional skip), simulator 279 passed, static analysis passed. No live calls or release. See `Tools/LocalHybridSearchEvaluation/v47/findings.md`; percentage/name relevance remains next.

## Retrieval and admission cycles completed — 30 September 2026

v48–v53 implemented literal-percentage/category discovery, explicit volume panels, a live-proven full-text request repair, and narrow category plural equivalence. Live v52: 2/4 original queries yielded candidates; one complete nutrition profile. Offline replay of its exact products after the plural fix: 3/4 candidates, two complete profiles; zero fully sufficient matches. FAGE variant selection remains unresolved. Final package 342 tests (one skip), simulator 279 passed, static analysis passed. No credentials, Gemini calls, commit/push or release. The failed v50 live gate and v51 diagnostic are retained. See `Tools/LocalHybridSearchEvaluation/v53/findings.md`.
