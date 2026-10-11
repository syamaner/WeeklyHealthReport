# Generic food review manifest v2 (#196)

Status: **draft for owner review, 11 October 2026; architecture gate passed with changes, folded in. Documents only; no code has changed.**
This is the change [ux-revamp-v1.md](ux-revamp-v1.md) calls "Single-step web review" (section "Contract changes > 3"). It amends the review manifest defined in [generic-food-proposal-integration-v1.md](generic-food-proposal-integration-v1.md) ("Confirmation extension", "Review suggestion gate", "Admission v4 architecture and repair") and composes with [food-confirmation-contract-v5.md](food-confirmation-contract-v5.md). Phase plan: [ux-revamp-phase-3-search.md](ux-revamp-phase-3-search.md).

## Naming

The manifest version string today is `reviewed-web-proposal-v1`; there is no v2 in code or docs. This contract introduces **`reviewed-web-proposal-v2`** and admission profile **`reviewed-web-admission-v6`**. Code is at `reviewed-web-admission-v5`, introduced on main by `6b5f279` (#187) together with `reviewed-web-proposal-v1` and `food-proposal-binding-v7`; the integration document's "v4" section describes a local, never-merged profile. Binding stays `food-proposal-binding-v7`, choice policy stays `food-proposal-review-choice-v3`, confirmation policy stays `food_confirmation_v5`.

## Baseline at `9fc734d`

From `FoodLedgerApplication/ReviewedFoodProposalConfirmation.swift`, `FoodConfirmation.swift` and `FoodLedgerPresentation/GenericFoodProposalReviewView.swift`.

| Fact | Today |
|---|---|
| Manifest type | `FoodProposalReviewManifest { version, query, document: CapturedFoodDocument, candidate: FoodProposalCandidate, scope, acknowledgement, reviewedAt }`, synthesised `Codable` (unknown keys ignored) |
| Acknowledgement | `FoodProposalAcknowledgement { identityAndScopeReviewed, basisReviewed, nutrientsAndUnknownsReviewed }`; `isComplete` requires all three. Three toggles on `FoodProposalDetailView`; the first resets when the match type changes |
| What the toggles gate | Only the "Continue to food confirmation" button, `ReviewedFoodProposalConfirmation.prepare` (`acknowledgement.isComplete`) and re-verification in `FoodReviewedWebProposalPolicy.scope` at save and reopen. No policy, nutrient or blocker depends on which toggle was set |
| Scope | `FoodProposalReviewScope`: `exact_product`, `representative_estimate`. Exact is hidden when `representativeSourceOnly` |
| Market | Not a field. `GenericFoodProposalReviewViewModel` appends `" [market: <name>]"` to the terms unless the market is Unspecified, so the market is already inside the hashed `query` |
| Encoding | `FoundationCanonicalJSONEncoder`: sorted keys, unescaped slashes, dates as milliseconds since 1970 (fractional milliseconds possible) |
| Retention | The encoded bytes are stored verbatim as the `.text` payload of one `CaptureEvidence` (`kind = .labelText`, `captureMethodVersion = manifest version`, `byteHash = SHA-256 of the bytes`). They are never re-encoded from the struct after save |
| Binding | `SourceRelease.sourceReleaseID = "reviewed-web:" + manifestHash`, `manifestHash`, `artifactHash = document.rawSha256`, `schemaVersion = "<manifest version>:<scope>"`, `pipelineVersion = "<manifest version>:<binding version>:<admission version>"`; each declared nutrient's provenance carries `manifestReference = "manifest-sha256=…;candidate=…;nutrient=…;blocks=…;literal=…;binding=…"` |
| Verification at save | `FoodConfirmationService` (about line 436): `manifestDigestIsValid` and `scope(...) != nil` (exact `pipelineVersion` equality, schema, evidence, manifest version, scope, acknowledgement, raw hash, name, brand, record ID, capture time, basis, `FoodProposalBinding.validate` eligibility, no query basis conflict, every nutrient value, unit, unknown reason and reference); then basis and nutrients unchanged; otherwise `invalidReviewedSource` before policy |
| Verification at reopen and retry | `restoredConfirmationInput` (about line 687): the same checks through `restoredSourceCandidate`, otherwise `integrityFailure` |
| Suggestion gate | `GenericFoodProposalReview.permitsConfirmation` (selection exists, ranking available, proposal is the current `suggestedChoice`, eligible, in the result), enforced only in the presentation view model's `prepare` with stale-query, credential and `representativeSourceOnly` checks. Not persisted |
| Scope into confirmation v5 | `FoodReviewedWebProposalPolicy.scope` feeds `FoodConfirmationPolicy.isGenericEstimate` (representative is an estimate), named-serving admission, the millilitre draft default and Confirm copy. Exact scope builds a fully unknown `DecisiveIdentity`, so `sourceIdentityMissing` blocks until a correction |

## 1. One review action

The three toggles are replaced by one action. The Web lookup screen shows together: food name and brand, source site and page kind, the match type choice, the source basis, every declared nutrient with its value, every undeclared nutrient as "Not stated", the proposal limitations, and the quoted text behind one disclosure. The user chooses the match type, then **Use this source**.

- "Use this source" is disabled while the match type is unset, including when `representativeSourceOnly` is true (only "Similar food estimate" is offered, and it is not preselected), and whenever the gate (section 4) does not permit the proposal.
- Changing the match type needs no re-acknowledgement because nothing is recorded until the press.
- Copy: "Exact product" and "Similar food estimate". Persisted scope raw values do not change.
- Opening the quoted-text disclosure is not required and not recorded (Q3).

## 2. Manifest v2

```
FoodProposalReviewManifestV2 {
  version: "reviewed-web-proposal-v2"
  query: String                          // unchanged rules, 1...300 characters, including the existing " [market: X]" suffix
  document: CapturedFoodDocument         // unchanged
  candidate: FoodProposalCandidate       // unchanged, original bound proposal
  scope: FoodProposalReviewScope         // unchanged raw values
  review: {
    action: "use_this_source"            // closed; the single acknowledgement
    presentation: "web-lookup-review-v1" // closed screen-content identifier
  }
  gate: {
    choicePolicy: "food-proposal-review-choice-v3"
    rankingAvailable: true               // must be true
    selectionChoice: String              // the recorded model choice; must equal candidate.id
    representativeSourceOnly: Bool
  }
  reviewedAt: Date
}
```

- **Single acknowledgement.** `review.action` is the only acknowledgement.
- **Content shown.** `presentation` names a closed screen contract: `FoodWebLookupReviewContent(document:candidate:scope:)`, a pure application projection (name, brand, source host and page kind, basis label, declared nutrients with literal values, undeclared nutrient keys, limitations, quote references). Its output for `web-lookup-review-v1` is pinned by golden tests. Admission only checks that `presentation` is a known closed identifier; it never recomputes the projection. A different screen content needs a new identifier and admission profile.
- **Gate decision as data.** The model's choice is recorded, not re-run, and never becomes authority. Admission v6 rejects, at save and at reopen: `rankingAvailable` false; `selectionChoice` different from `candidate.id`; `selectionChoice` `none` or `clarify`; `representativeSourceOnly` true with `exact_product` scope; an unknown `choicePolicy`.
- **Market.** Stays inside the hashed `query` as the existing suffix; no new field (Q2). The golden v2 fixture pins a query with `[market: United Kingdom]`.
- **Scope, source hash, binding.** Unchanged fields and derivations: `document.rawSha256` is the release `artifactHash`; the manifest SHA-256 is the release ID suffix, `manifestHash` and evidence `byteHash`; `manifestReference` grammar unchanged.
- **Strict decoding.** `FoodProposalReviewManifestV2` and its nested `review` and `gate` types implement a custom `init(from:)` that compares `container.allKeys` with the closed key set and throws on any extra or missing key (including any `acknowledgement` key), then rejects unknown `action`, `presentation` or `choicePolicy` and an empty `selectionChoice`. There is no shared `ValidatedDecoding` helper; this is the mechanism.

Written alongside a v2 manifest: `captureMethodVersion = "reviewed-web-proposal-v2"`, `schemaVersion = "reviewed-web-proposal-v2:<scope>"`, `pipelineVersion = "reviewed-web-proposal-v2:food-proposal-binding-v7:reviewed-web-admission-v6"`, `CandidateMatchMetadata.methodVersion = "reviewed-web-proposal-v2"`. Candidate `variant` and material-difference strings are unchanged.

## 3. Old manifests

- The current struct is frozen and renamed `FoodProposalReviewManifestV1`, keeping synthesised `Codable` (lenient: unknown keys ignored), so every stored v1 payload decodes exactly as today.
- The stored bytes are the reference. They are rehashed as stored at save, reopen, archive and recovery; nothing re-encodes them. Byte-for-byte re-encoding of a v1 fixture is a test-only property that pins the frozen struct shape.
- Decoding dispatches on the `version` field: v1 to V1, v2 to V2, anything else fails closed. Evidence `captureMethodVersion`, release `schemaVersion` prefix and manifest `version` must agree.
- Admission v6 accepts exactly two `pipelineVersion` triples, each tied to one manifest version: `reviewed-web-proposal-v1:food-proposal-binding-v7:reviewed-web-admission-v5` (every record written since `6b5f279`, including released builds) and `reviewed-web-proposal-v2:food-proposal-binding-v7:reviewed-web-admission-v6`. Admission-v4 and any other triple stay rejected, as today.
- A v1 manifest still needs the complete three-part acknowledgement and is not subject to the recorded-gate rules (it has no gate record). A v2 manifest needs the single action and the gate record. Every other check runs identically for both.
- New saves always write v2.

## 4. Unchanged rules

- **Source binding and hashes:** binding v7, raw document hash, manifest SHA-256 over the retained bytes, release ID, per-nutrient references, capture time and record ID checks.
- **Applicability gate:** confirmation still requires a successful applicability check; only the current suggested eligible candidate can prepare confirmation; `none`, `clarify`, rejected IDs, non-preferred alternatives and unavailable checking remain blocking; a query basis conflict still yields `clarify`. The gate is enforced in the application by `ReviewedFoodProposalConfirmation.prepare(review:proposal:scope:)` (taking the `GenericFoodProposalReview`), which writes the gate record, and re-checked from that record by admission v6 at save and reopen. The view model keeps the stale-query and credential checks.
- **Exact-product blockers:** exact scope keeps the fully unknown identity, so `sourceIdentityMissing` blocks until a correction; corrections cannot change nutrients or denominator; representative scope cannot claim an exact product; a source serving is never weight or volume.
- **Egress:** none added or widened. The manifest is local evidence; review sends nothing. Only displayed food terms (with the market suffix, as today) and captured public source text reach OpenRouter, per [privacy-and-egress.md](privacy-and-egress.md).

## 5. Composition with confirmation v5

"Use this source" and Log record different facts, so there is no double acknowledgement and no new prompt.

- **Use this source** accepts the source, its match type and the displayed values and unknowns. It prepares a `PopulatedFoodConfirmation`; it never saves.
- **Log** accepts food, amount, time and source as v5 defines. Confirm does not ask the match type again; it shows it on the source line.
- Representative scope remains a generic estimate under v5 (generic-estimate assertion row, estimate label and "Unknown details stay unknown", no library aliases, `FoodEntryEstimateStatus` estimate). Exact scope remains exact (no assertion when plain, the decisions row when decisions apply, `sourceIdentityMissing` first).
- Manifest checks still run before `FoodLogPolicy` and fail as `invalidReviewedSource`.

### Re-logging a web source (recent foods)

A new public builder `FoodConfirmationService.relogInput(_ saved: StoredFoodConfirmation) -> PopulatedFoodConfirmation` serves recent re-logs. It verifies the manifest digest and restores the source candidate (the same functions as reopen), sets `expectedIdentity` to the source candidate's identity (not the saved, possibly corrected, product identity), `expectedEdibleQuantity = .unknown`, and is opened with `reopened == nil` and `prefillSourceQuantity: false`; only the entered value and unit are prefilled. It references the existing manifest evidence and release and never writes a new manifest, so a re-log of a v1 source stays v1 evidence and does not raise the archive contract.

## 6. Compatibility and admission (following confirmation v5)

| Item | Decision |
|---|---|
| Food archive contract | **5**. `CanonicalFoodProjection.minimumContractVersion` returns 5 when any evidence has `captureMethodVersion == "reviewed-web-proposal-v2"`; archive verification requires contract 5 for such evidence. Contracts 1 to 4 keep importing with identical canonical bytes |
| SQLite | Metadata-only migration `v5_review_manifest`: `user_version = 5`, `schema_identity = food-ledger-v5`, rewriting no rows. The open-policy check at `FoodLedgerGRDBStore.swift:1151` (`metadata == "food-ledger-v4"`) changes to `food-ledger-v5`. A schema-4 opener throws `unknownSchema(5)` |
| Operation | No new operation type; saves stay `confirm_food_v3` (Q1) |
| Older binaries | A v5 confirmation build cannot import a contract-5 archive or open a schema-5 store. Without the bump it would import v2 records and fail them later as `integrityFailure` at reopen |
| Daily JSON | Unchanged literal pin `maximumExportedFoodContractVersion = 3`; food contracts 4 and 5 are both rejected |
| Release note | Downgrading is not possible; archives from this build cannot be restored into the previous build |

## 7. Contract tests (written first)

1. **v1 fixture:** literal manifest bytes captured from a real build, with a fractional-millisecond `reviewedAt`. Decode as V1, rehash to the stored hash; save, reopen and retry-recover on memory and GRDB stores with unchanged scope. Re-encoding byte for byte is asserted as a test-only property.
2. **v2 golden fixture:** literal bytes with a `[market: United Kingdom]` query; the same round trip; key names and order pinned.
3. **Cross-version rejection:** a v2 payload carrying `acknowledgement`; mismatched `version` versus `captureMethodVersion` or `schemaVersion`; a v1 record relabelled v2; an admission-v4 or other unknown triple.
4. **Strict v2 decoding:** extra key, missing key, unknown `action`, `presentation` or `choicePolicy`, empty `selectionChoice`, at the top level and in `review` and `gate`.
5. **Gate at preparation:** `none`, `clarify`, a rejected ID, a non-preferred eligible alternative, ranking unavailable, no selection, a query basis conflict and a stale query each refuse `prepare(review:proposal:scope:)`; only the current suggested eligible candidate prepares.
6. **Recorded gate at save and reopen:** `rankingAvailable` false, `selectionChoice` not the candidate, `none` or `clarify`, and `representativeSourceOnly` with exact scope are each rejected (`invalidReviewedSource` at save, `integrityFailure` at reopen), with the digest valid.
7. **Retained reviewed-source contracts run against v2:** altered bytes, numbers, unknowns, identity, references, times or basis fail at save, reopen and recovery; exact products stay blocked despite review; corrections cannot change nutrients or denominator; source serving is not weight; schema change cannot promote exact to estimate. `testEveryReviewAcknowledgementIsRequired` stays for v1 with a v2 counterpart (action required).
8. **Presentation identifier:** an unknown `presentation` is rejected; `FoodWebLookupReviewContent` golden outputs for a complete panel, a partial panel and a source serving; admission does not call the projection.
9. **v5 composition:** a representative v2 save writes the generic-estimate assertion and reports an estimate; an exact v2 save is blocked by `sourceIdentityMissing` until a correction, then writes `food_confirmation_v5` with no extra assertion.
10. **Re-log builder:** re-logging a corrected exact web product raises `sourceIdentityMissing` again with no carried decisions; quantity prefill is value and unit only; a tampered manifest refuses the builder.
11. **Re-log evidence:** on memory and GRDB stores, for v1 and v2 sources, a re-log saves, writes no new evidence or release rows, and `minimumContractVersion` stays 4 for a v1 source.
12. **Admission and storage:** `minimumContractVersion` is 5 with v2 evidence and 4 otherwise; contract-4 import rejects a contract-5 archive; schema-4 opener throws `unknownSchema(5)`; the migration rewrites no row bytes; Daily JSON rejects food contracts 4 and 5.
13. **Egress:** preparing, saving and re-logging issue no network request (fake transports record zero calls).

## 8. Owner decisions (recommended, awaiting approval)

| ID | Decision | Recommendation |
|---|---|---|
| Q1 | New operation type for v2 saves | No; contract 5 and schema 5 are enough because the operation shape is unchanged |
| Q2 | Recording the market | Keep it inside the hashed query as the existing `" [market: X]"` suffix; no new field or domain type; pinned in the golden v2 fixture |
| Q3 | Record whether the quoted text was opened | No; it is behaviour, not evidence |
| Q4 | Archive and schema bump | Yes, contract 5 and `food-ledger-v5`; downgrade impossible, stated in the release note |
| Q5 | Where the gate lives | Enforced in the application at preparation and recorded in the manifest, re-checked from the record at save and reopen |
