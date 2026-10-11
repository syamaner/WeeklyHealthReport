# Opt-in nutrition re-resolution — v1

Issue #101 consumes section 9 of the food identity/nutrition contract. This is a
new effective materialisation of an existing log, not a product reformulation.

## Architecture gate

- Pure domain diffing compares all 39 ordered nutrient entries, preserving exact,
  augmented, bounded and unknown states and provenance changes. It does not
  perform provider lookup or mutate records.
- Application orchestration owns explicit source/method selection, a read-only
  proposal bound to the current log/resolution IDs, stale-proposal rejection and
  an idempotent atomic accept operation. Decline/interruption makes no mutation.
- A consumer-owned resolution-provider port exposes immutable target release and
  matcher identities. The initial adapter uses only the already accepted bundled
  CoFID corpus and lexical matcher, bypassing personal-library reuse. A newer
  dataset/model must be independently accepted and installed before an adapter
  can offer it. Synthetic release versions are tests, never production options.
- The local store provides current log history and existing confirmation records.
  Presentation shows old/new source and method identities, candidate description,
  item identity checks and nutrient-level differences before explicit acceptance.

Provider lookup is the volatile seam. Evidence immutability, compatibility, source
identity, nutrient states, supersession and original/effective resolution IDs are
closed existing invariants. Alternate provider fixtures share behavioural tests;
memory and SQLite stores prove the same acceptance/history contract.

## Acceptance invariants

Accept appends a resolution version superseding the unambiguous resolution-lineage head,
a candidate decision and a new log version pointing at that resolution. It retains
the same product version, consumed quantity, occurrence date and original
resolution ID. The reason records the explicit re-resolution trigger. Existing
source releases, evidence, resolution/log versions and exported artifacts are not
rewritten. Existing archive records and supersession IDs provide reconciliation
metadata for later exports; there is no automatic export or HealthKit write.

Several logs can reference one resolution. Advancing that resolution lineage does
not advance those other logs: only the selected log receives a new effective
materialisation. Its before/after comparison uses its own prior effective result.

The original product's complete confirmed identity remains fixed. A known source
contradiction is blocked. Missing source identity fields require a separate,
explicit compatibility confirmation and reason, recorded as a user assertion.
As in the existing populated-correction flow, the raw candidate's contradictory/
unknown decision remains rejected, not relabelled as an exact selected match;
the new resolution cites the user's assertion. No source identity is rewritten.

Source removal, unavailable targets, incompatible candidates and interrupted or
declined proposals leave the effective log unchanged. No-op proposals do not append
records. A proposal is invalid if the log changed while it was being reviewed.
No-op means the same full nutrient entries, source-release set and candidate record;
a method-only rerun with identical results does not create another version.
Uncertain save retries use the same prepared command/record IDs. A newer approved
source can change a nutrient to unknown or change an interval; neither is hidden
by a scalar-only diff.

## Evidence boundary

The currently bundled source is CoFID 2021. This feature does not invent a newer
release, promote a new matcher or imply personal-food validation. Re-running the
same approved source can yield no change. Source/model upgrades are only available
when a real approved immutable target is installed. No provider, account, network
or physical-device action is required for local delivery.

## Review surface and validation

Open **Food logging → Review Nutrition Updates**. Choose an installed target, then
a saved product entry and a proposed candidate. Nothing is preselected. Inspect
the source descriptions, unchanged product identity, nutrition basis, all 39
before/after nutrient entries and expandable provenance. Confirm source identity
gaps separately, provide a reason and accept, or decline without a write.
Original capture evidence and historical log/resolution versions remain inspectable.

This first UI covers product-composed entries, not mixture re-resolution. An
uncertain save retains its exact command for retry during the app session; closing
the app discards unsaved review state, not any committed ledger history. The next
launch reads the actual saved effective version. No background rerun is scheduled.

Synthetic memory/SQLite contract tests cover read-only preview, explicit acceptance,
immutable history, idempotent retries, target removal, stale proposals, candidate
changes, new unknowns, mixed-source provenance, no-op reruns, blocked known identity
contradictions and explicitly asserted source gaps. Pure diff tests cover changed
bounds and measured/augmented/provenance changes. Presentation tests cover explicit
selection, decline and recovery after a lost save response, including source removal
after a successful commit. A later quantity correction retains the confirmed
product identity and accepted effective nutrition. The real bundled adapter is
tested without promoting automatic candidate acceptance.

Local delivery validation: 139 package tests, 254 unsigned simulator tests, Xcode
static analysis, 15 evaluation-tool tests and unchanged frozen matching-report
verification pass. The existing app models/formatting/presentation coverage gate
is 96.49%; that figure is not coverage of every new package or UI line. No physical
device, personal-food, provider or HealthKit-write validation was performed.
