# Bounded search recovery before source expansion

The broad v2 prototype was preserved in `/private/tmp/food-search-broad-prototype.patch` and deferred. This patch deliberately retains the v1 weights, thresholds, token normalisation, candidate limit and identity rules. The historical frozen v1 evaluation is not a fresh evaluation of this patch.

## Architecture and versioned contract

Matcher identifier: `deterministic-lexical-recovery-v1`. The existing adapter handles corpus coverage, the application route carries optional guidance/suggestions, and presentation exposes explicit search buttons. Nutrition/identity invariants, source bytes and exact saved-library reuse remain unchanged. No new source or persistence is introduced.

A query cannot retrieve a candidate solely through connecting words. The reported fish-and-chips variants are rejected as combined meals: CoFID has component records and shop descriptions, not the combined meal. Named ribeye queries explain absent coverage rather than retrieving another cut. Both have explicit follow-up searches requiring independent candidate selection, quantity review and confirmation. Saved exact entries are checked before corpus recovery and remain reusable.

Broader recall/relevance changes, plurals, typo handling, cross-source ranking and generic query/component handling are deferred until source evaluation and an agreed retrieval contract. These guards are a bounded repair of known failures, not a general semantic food-search engine or an accuracy claim.

Contract regressions cover all reported spellings, non-food connector matches, actionable suggestions with corpus hits, evidence retention, existing identity rules and save/reuse.

## Validation — 26 September 2026

Current base: `c115d82c806ee1f9fd50b5775de420c38b87c302`. All 150 FoodLedgerKit tests passed. Package dependency boundaries and `git diff --check` passed. Xcode static analysis and the complete WeeklyHealthReport simulator suite succeeded on iPhone 17 Pro, iOS 26.5, signing disabled. No device usability check, commit, push or TestFlight upload was performed.

## Approved source extension — 26 September 2026

The subsequent USDA adapter is a separate versioned whole-record source; CoFID's bounded recovery rules remain intact. Composite orchestration presents both sources and retains exact saved-library reuse. USDA accepts ribeye spelling variants against its own source descriptions. No combined fish-and-chips recipe is synthesised. See the source expansion contract for mappings and pinned hashes.

After this integration, all 155 package tests passed, package dependency boundaries and `git diff --check` passed, and Xcode static analysis plus the complete iPhone 17 Pro simulator suite succeeded. These are software checks, not a held-out retrieval-quality evaluation or physical-device acceptance. Changes remain local and uncommitted; nothing has been released to TestFlight.

## Multi-source lexical refinement v2

After source admission, CoFID matcher `deterministic-lexical-complete-terms-v2` and USDA matcher `usda-whole-record-complete-terms-v2` now share a versioned, retrieval-only token-equivalence policy. Every meaningful query term must occur in a candidate; connector overlap or an unrelated partial food match cannot satisfy a query. Curated everyday plural forms map to the same terms. Rib-eye/rib eye equivalence remains retrieval-only; original typed evidence and exact saved-library aliases are unchanged. No automatic edit-distance correction is promoted. Existing hard-identity rules run before ranking, and unlike source scores remain uncombined.

Search adds Any/Raw/Cooked preparation controls and presents preparation and source variant before review. Technical lexical differences remain available in source details. The development regression sample covers chicken breast, salmon, olive oil, brown rice, oats, milk, yoghurt, lentils, plural pairs, unrelated partial matches and the user's reported failures. These are reproducible contract/development checks, not independent held-out labels or a retrieval-accuracy claim.
