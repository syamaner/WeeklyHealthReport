# Online food search recovery v1

## Problem and scope

A completed discovery can produce source links without an admissible nutrition
candidate. The previous main-search UI labelled an unsupported host or URL as an
unsupported nutrition format, collapsed request timeouts and connection failures
into “Unavailable”, and suggested changing the food name even when a service failed.

This local repair preserves failure categories and makes source access and recovery
visible before the results list. It does not increase source coverage. Nutrition
admission remains limited to the supported manufacturer adapters and the existing
single recipe path. Discovery success, source verification, usable candidate coverage
and device usability must remain separate evaluation outcomes.

## Architecture gate

- Infrastructure (`GeminiFoodWebDiscovery`) translates URL loading errors to plain
  application errors; raw responses, credentials and SDK error types do not cross
  into presentation. Unknown failures stay unknown.
- Application-owned error enums carry timeout, connection and request rejection
  separately. `GeminiFoodSearch` preserves them and the existing cancellation,
  request deadline and exact-key authority checks.
- Source review v4 classifies nonempty citations with no eligible URL as an
  unsupported source and retains citations. Empty citations remain an empty result.
- Presentation owns recovery text and whether to offer an explicit new search.
  Temporary failures offer “Search again”, which runs the existing pipeline using
  current settings. There is no automatic retry or enlarged request budget.
- Source admission, identity, nutrient provenance, quantity rules, credentials,
  provider/model selection and selected-source request limits are unchanged.
  Existing provider and source acquisition ports remain the extension points.

Contract tests cover transport classification, expired/cancelled work, exact-key
invalidation, citation retention without acquisition of unsupported URLs, empty
results, explicit retry, and query-edit invalidation. Native simulator rendering
checks source/recovery controls without scrolling using synthetic inputs.

## Local validation and device runbook

1. Run focused adapter, source-review, enrichment-contract and presentation tests.
2. Run the FoodLedgerKit suite and `Packages/FoodLedgerKit/Scripts/check-boundaries.sh`.
3. Run the complete simulator suite and Xcode static analysis once code stabilises.
4. Review the final diff and keep personal fixtures and screenshots outside Git.
5. After a separately authorised test release, repeat the private device cases with
   the build number recorded. Distinguish typed request failure, unsupported source,
   unverified source content and genuine no-match states. Check source access with
   the keyboard open and dismissed, and confirm local results survive online failure.
6. Retry explicitly only when appropriate. Record outcome and latency separately;
   a displayed explanation or successful discovery is not a usable nutrition match.

The earlier device screenshots alone do not establish why the request marked
“Unavailable” failed. This repair provides categories for a subsequent run; it
cannot retrospectively recover a timeout, HTTP response or selected citation.
No live provider calls, paid evaluation, credential changes or release upload form
part of this repair's local validation.

## Remaining coverage work

Design and evaluate additional source adapters against frozen public source evidence
before expanding admission. Measure verified candidate coverage, identity correctness,
nutrient/basis fidelity, latency and recovery success independently. Preserve unknown
portion weights and require explicit choice for broader food or variety alternatives.
Personal query labels and source documents remain in the private evaluation workspace.

## Validation receipt — 2026-10-03

Local changes on base `f6e4c49d80a435010e30738741555429c10630b7`:

- FoodLedgerKit: 537 tests executed, two opt-in replay tests skipped, zero failures.
- Complete iOS simulator suite: 281 passed, zero failures or skips, including the
  native empty-result source/retry render check. iPhone 17 Pro simulator, iOS 27.0.
- Xcode static analysis: succeeded.
- Package dependency-boundary check and `git diff --check`: passed.

Retained local results: `/private/tmp/whr-search-recovery-package-full.log`,
`/private/tmp/whr-search-recovery-full.xcresult`, and
`/private/tmp/whr-search-recovery-analysis.log`.
These results establish local regression coverage, not live provider or physical
phone acceptance. No new build has been uploaded; the repair remains uncommitted.
