# Food confirmation contract v2 — issue #161

Architecture gate, before implementation: pure identity compatibility remains in
FoodLedgerDomain and stays strict for provider selection, augmentation and replay.
FoodLedgerApplication owns the explicit user-confirmation policy; presentation
consumes that policy and never infers missing identity. The volatile quantity-guide
boundary is consumer-owned and accepts only food-specific, versioned, evidenced
edible-weight guides. No guide data is enabled in this change.

`food_confirmation_v2` permits an explicitly accepted generic composition snapshot
with unknown descriptive fields. It requires retained generic-search evidence,
nonempty exclusively generic-dataset nutrient provenance belonging to the selected
record/release, and a known serving basis. Equal unknown fields are retained as
unknown rather than reported as differences. Different fields still require an
explanation or correction. Exact-product and panel confirmation retain v1's
mandatory-identity checks. Corrections cannot opt an exact product into this rule.

The user assertion records acceptance of a composition estimate under v2, not
verification of missing facts. CandidateDecision continues to reject a source with
unknown compatibility under the unchanged strict domain contract; its reasons and
original nutrients remain retained. An asserted estimate may be used by the saved
resolution, as with an asserted correction. The resolution method and assertion
identify this path; no stored v1 data is rewritten. Reopened quantity edits reuse
the saved product and resolution, including their unknowns and policy evidence.

Quantity, plate subtraction, basis incompatibility, unknown nutrient and source
provenance rules are unchanged. Count requires a measured edible weight/volume;
no shell mass, density, portion weight or nutrient is invented. A future guide
must keep count, guide ID/version/evidence, estimate and measured override distinct.

Contracts: ordinary generic rice/milk/yoghurt/eggs save and reopen without changed
identity/nutrients/evidence; strict source selection remains rejected; exact-product
gaps still block; count without conversion blocks; query/filter edits invalidate
results, hints and stale suggestions. Ranking scenarios distinguish whole eggs
from explicit whites and preserve Greek/Greek-style wording and tentative alternatives.

Evidence gap: bundled USDA search data retains nutrients, names and preparation,
not food-portion weights; CoFID search data has no evidenced small/medium/large egg
edible-weight guide. Shell-on egg grades alone would not establish edible weight.
Additional source ingestion is deferred pending separate approval. Manual measured
edible-weight override remains available. Historical retrieval evaluations remain
unchanged; these regressions are exploratory software evidence, not independent
frozen retrieval acceptance or physical-device validation.

An unknown-identity saved estimate is not eligible for exact personal-library reuse.
A repeated search rediscovers the bundled source record for fresh explicit
confirmation. Known-identity library reuse retains its existing contract.
Re-resolution likewise keeps its strict identity requirements and can remain
unavailable for an unknown-identity estimate; v2 does not silently augment it.

## Final local validation

- Complete FoodLedgerKit suite: 213 tests, zero failures, one opt-in public replay
  skipped. New save/reopen contracts pass for both in-memory and GRDB stores.
- Complete iOS 26.5 simulator suite: 274 passed, zero failures/skips.
- Xcode static analysis and FoodLedgerKit import boundaries passed.
- Four retrieval-scoring tests passed; current replay exactly reproduces the v4
  expected metrics against the unchanged v3 judgements. Six manifest hashes verify.
- `git diff --check` passed. Primary checkout was clean and not modified.

Simulator, synthetic guide and bundled-source tests do not establish device
usability, actual food identity or source-backed egg-size weights. No provider,
phone control, HealthKit write or TestFlight upload occurred.
