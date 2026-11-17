# Web lookup larger pages, phase 1: architecture gate

Status: **gate passed with changes, owner decision Q1 taken (option A), 17 November 2026** (#508). Phase 1 of [web lookup part-read pages v1](web-lookup-part-read-pages-v1-proposal.md) (the accepted contract, "the contract" below). It delivers the larger page bounds (contract section 4, decision W9) and, because a larger page cannot be saved under manifest v2, the complete stored format of manifest v3 (contract sections 6 and 8.4) with a writer for the one-candidate case only. Offer rows 2 and 3, the applicability request on conflicting candidates and the panel list (phase 2) and part-read selection (phase 3) are not built here.

## 1. Scope

In:

- The projector's output bound and `CapturedFoodDocument.validate` rise together from 512 blocks and 30,000 characters to 2,048 blocks and 100,000 characters, for HTML and `text/plain`. PDF keeps its own bounds.
- Stored v1 and v2 manifests keep today's bounds, accept nothing new, and reject a document with `partialRead` or a selected-version locator.
- The complete, frozen storage contract of manifest v3, so that phases 2 and 3 add writers and behaviour without changing the v3 pipeline triple: the domain `partialRead` record with its `validate()` rules and the selected-version constant (nothing writes either yet); the domain choosable rule; per-version choice-policy and presentation sets; strict v3 manifest and gate types; every v3 admission rule of contract section 8.4 with the notes of section 13; the v3 pipeline triple; the food contract number for v3 evidence.
- A v3 writer for the one-candidate case: production writes v3 for every web review from this phase on (one production writer). It prepares only when today's rule permits (the suggested, eligible candidate of a successful check), with `offered` holding that one candidate. v2 keeps a regression-only writer, as v1 did.
- Screen contract `web-lookup-review-v2` for one candidate: its content type, golden content and the part-read line and group title as content rules (no document can be part-read yet). The visible screen does not change.
- `privacy-and-egress.md` and `privacy-policy.txt` for the amount only (section 6).
- Documentation: the contract's status, an amendment note in `generic-food-proposal-integration-v1.md` and `generic-food-review-manifest-v2.md`.

Out (later phases): offer rows 2 and 3 and the choice the person makes between panels; the applicability request for conflicting candidates; the panel list, "Suggested", "Choose a panel", "Different values" and the O4 warning line on screen; removing duplicate candidates; part-read selection, the capture port's permission and source order; the refusal copy.

## 2. Responsibilities

| Layer | Owns in this phase |
|---|---|
| Domain (`FoodLedgerDomain`) | `FoodDocumentBounds`, a closed value with `current` (2,048 / 100,000) and `reviewManifestV1V2` (512 / 30,000: the bound every v1 and v2 manifest was written under). `CapturedFoodDocument.fits(_:)`. `validate()` checks `current`. `FoodDocumentPartialRead` (policy, four counts) as an optional member of `CapturedFoodDocument`, omitted from the encoding when absent, with the contract section 6 rules in `validate()`. The constants `food-document-block-selection-v1` and `swift-food-document-blocks-v7-selected`. `BoundFoodProposal.choosable` (today's `selectionEligible` without the status test) and the public same-identity and conflict predicates already used by binding. |
| Infrastructure (`FoodGenericSearch`) | `GenericFoodDocumentProjector` reads `FoodDocumentBounds.current`. `GenericFoodPDFProjector` names its own unchanged 512 / 30,000 bound. Version string stays `swift-food-document-blocks-v6`. Provider request bodies unchanged: `partialRead` is never serialised by the catalogue, and the `.jev` route excludes it explicitly (it is never present yet). |
| Application (`FoodLedgerApplication`) | v1/v2 closure in two places: `FoodProposalReviewManifestRecord.reviewIsAdmissible` (v1 and v2 cases require `fits(.reviewManifestV1V2)`, no `partialRead`, no selected-version locator; this covers save, reopen, `restoredSourceCandidate`, named serving and estimate status through `scope()`), and `ReviewedFoodProposalConfirmation.validated` for the v2 regression writer and `prepareVersion1`, so a writer refuses before encoding. `manifestDigestIsValid` is unchanged on purpose: it never reads the document and is always paired with `scope()`. v3 types, admission and writer. Choice-policy and presentation sets per manifest version. `CanonicalFoodProjection.minimumContractVersion` for v3 evidence. |
| Presentation | `FoodWebLookupReviewContent` gains the presentation `web-lookup-review-v2` content for one candidate: identical to v1 content for a whole page, plus the part-read line and the "Not in the part read" group title when the document carries `partialRead`. The SwiftUI screen is unchanged because no document is part-read yet and one candidate is offered. |

## 3. Dependency direction

No new imports or targets. Bounds, the part-read record and the choosable rule are domain values; the projector reads them; admission and the writer are application code; presentation reads application content. `check-boundaries.sh` gains no rule now (the selection file belongs to phase 3).

## 4. Settled values

| Item | Value |
|---|---|
| Manifest v3 version | `reviewed-web-proposal-v3` |
| Choice policy, v3 only | `food-proposal-review-choice-v4` (v2 keeps admitting only `food-proposal-review-choice-v3`). It names the offer table of contract section 8.3 as a whole, which v3 admission enforces. Phase 1 writes only row 1, which is identical under the full table, so a phase 1 record and a later row 1 record are the same thing; rows 2 and 3 are told apart by `offered` and `selectionChoice`. The reviewer's own identifier stays `food-proposal-review-choice-v3` until phase 2, and Developer tools shows both |
| Presentations | v2 admits only `web-lookup-review-v1`; v3 admits only `web-lookup-review-v2` |
| Admission version for v3 | `reviewed-web-admission-v7` |
| v3 pipeline triple | `reviewed-web-proposal-v3:food-proposal-binding-v7:reviewed-web-admission-v7` (binding version as on `main` at 23c1e91, written as a literal) |
| v1 and v2 triples | Frozen as literals equal to today's values, so no later constant change moves them; the existing pin in `ReviewManifestV2ContractTests` stays |
| Food contract | v3 evidence needs contract 5, as v2 does; `foodContractVersion` stays 9. Contract 10 is already allocated by two accepted, unimplemented contracts (assistant-pasted estimates v1, personal food catalogue estimates v2), and numbers must be taken in landing order. Under decision W7 an older build that imports v3 evidence is not made to refuse or read it gracefully: it decodes the evidence as text and its admission does not restore the review |
| SQLite schema | Unchanged: the manifest is stored as evidence text, as v2 |
| Document version string | Whole pages keep `swift-food-document-blocks-v6` (contract section 4) |
| Part-read threshold | `FoodDocumentPartialRead.selectionPolicyBounds` (2,048 / 100,000), fixed with policy `food-document-block-selection-v1` and not read from `FoodDocumentBounds.current`, so stored part-read documents keep validating if the capture bound changes |
## 5. v3 admission (contract section 8.4 with the section 13 notes)

A v3 manifest is rejected at save and at reopen when any of these holds:

1. any key outside the closed v3, review or gate key sets, or a missing required key, at every level: the stored JSON must carry exactly the keys its decoded value encodes, inside the document, its blocks, the part-read record, the candidate, every offered candidate and their nested values (owner decision, 17 November 2026; `document.partialRead`, `brand`, `preparation` and the other optional members may be absent). v1 and v2 keep their existing nested leniency;
2. `gate.choicePolicy` other than `food-proposal-review-choice-v4`, or `review.presentation` other than `web-lookup-review-v2`, or `review.action` other than `use_this_source`;
3. `gate.rankingAvailable` false, or `gate.selectionChoice` empty or `none`;
4. `gate.personChoice` different from `candidate.id`;
5. `candidate` not equal, as a whole value, to one member of `offered`;
6. `offered` empty, more than three members, or a repeated id;
7. any offered candidate that does not bind to the retained document, is not choosable, or has a basis that conflicts with `query`;
8. offered candidates that do not all share one name, brand, preparation, basis amount and basis unit (exact equality, the predicate the conflict rule uses);
9. `selectionChoice` naming a candidate that is not in `offered`;
10. `selectionChoice` `clarify` unless `offered` has at least two members and every member conflicts with at least one other member (aligned with offer row 3);
11. `gate.representativeSourceOnly` true with scope `exact_product`;
12. a document that fails `validate()`, including the `partialRead` rules;
13. every rule shared with v2 in `FoodReviewedWebProposalPolicy.scope` (release, evidence, hash, name, brand, URL, capture time, basis, nutrient values and provenance), applied to `candidate`.

Presentation cannot construct a permitting gate or supply `offered`; the writer takes both from the reviewer's result. In this phase the writer refuses unless `GenericFoodProposalReview.permitsConfirmation` holds today, so it only ever writes offer row 1.

## 6. Egress wording for phase 1 (shown to the owner before it lands)

- `privacy-and-egress.md`, OpenRouter web lookup row, added to the "what" cell: "at most 100,000 characters of page text in 2,048 blocks per captured page (distinct page text; long blocks are excerpted with up to 100 characters of overlap) (larger pages, #508)", and the contract added to its contract cell. The overlap clause was added at the owner's request on 17 November 2026, after the invariant review noted it.
- `privacy-policy.txt`, after the sentence "Captured source text and displayed food terms go to OpenRouter and the configured extraction and applicability providers for structured proposals and a separate check against the requested food.": "A page is sent whole up to a fixed size; a larger page is not sent."

The contract's section 10 clauses on part-read pages and on the applicability request for conflicting candidates land with phases 3 and 2.

## 7. Behaviour change named by the review

A discovery run whose first lead lies between the old and new bounds was refused with `responseTooLarge` and fell back to the second lead (`GenericFoodProposalReview.swift:158-163`). It is now reviewed, with no second capture. This follows from W9 and is pinned by a reviewer test.

## 8. Contract tests in this phase

1. 2,048 blocks and 100,000 characters project whole; a 2,049th block or a 100,001st character gives `responseTooLarge`, for HTML and `text/plain`.
2. A page within the old bounds gives byte-identical output; a page between the bounds projects whole with the v6 string; every retained fixture re-projects equal.
4. A PDF over 512 / 30,000 is still refused.
11. `validate()` at the `current` edges; `fits(.reviewManifestV1V2)` at 512/513 blocks and 30,000/30,001 characters; `partialRead` validates against the actual blocks; a locator and `partialRead` mismatch is refused; full counts within the bounds are refused; documents with and without the record round-trip, and without it the bytes are unchanged; existing fixtures and golden bytes unchanged.
12. Every stored v1 and v2 golden review admits and reopens unchanged, and the retained v2 golden bytes rehash through the regression writer; v1 and v2 manifests with 513 blocks, with 30,001 characters, with `partialRead` and with a selected-version locator are rejected through `scope()`, `restoredSourceCandidate` and the save check while `manifestDigestIsValid` stays true; `prepare` (v2 regression) and `prepareVersion1` refuse such documents; a v2 manifest carrying a v3 key, the v4 choice policy or `web-lookup-review-v2` is rejected; the v1, v2 and v3 triples are pinned; golden v3 bytes pin key names and order; one failing case per rule in section 5; `minimumContractVersion` gives 5 with v3 evidence and unchanged values without it.
13. Catalogue and request bodies for a whole page at the new bounds keep their shape; no request body contains `partialRead`; the `.jev` body for a document with `partialRead` is pinned without it.
14 (row 1). The production writer writes v3 with `offered` equal to the one suggested candidate and `personChoice` equal to it; it refuses when today's rule does not permit.
17 (one candidate). Golden `web-lookup-review-v2` content for one candidate, whole and part-read; content rebuilt from a retained v3 manifest equals the content shown; an unknown presentation fails closed.
Reviewer: a first lead between the bounds is reviewed, with no second capture and at most two captures.
App target: the existing reviewed web route still prepares and saves (now as v3), and Developer tools shows the manifest version.
Evaluation: the FoodSearchQuality and FoodQueryEvaluation steps of `ios-ci.yml`.

Existing tests that change: the 513-`<p>` case in `GenericFoodDocumentProjectorTests` and its three 30,001-character assertions (lines 14, 20, 118), and the 30,001-character assertion in `GenericFoodProposalTests` (line 242), each moved to the new bound with a 30,001-character `fits(.reviewManifestV1V2) == false` domain case kept. The comment that the projector "never increases admitted source text" is corrected. Tests that assert production writes v2 move to v3.

## 9. Not established

- Review time, token use and binding at 100,000 characters, saved manifest size, and reopen and diary-list time with manifests over 1 MB (`estimateLogItemIDs` rebinds per row). Contract test 21 measures them before release. Unmeasured today.
- Whether the extraction and applicability routes need a larger output allowance at the new bounds.
- No storage or archive size limit is added; test 21 reports manifest size.
- Anything on a device.

## 10. Review record

One blind architecture-gate review of the first draft (read-only, at 23c1e91): pass with changes. Its findings are folded in: the two named places for the v1/v2 closure, the four tests that pin 30,001-character refusals, option A completed as the whole frozen v3 storage contract, the contract number (5, after finding contract 10 already allocated) and schema position, the second-lead behaviour change, literal v1/v2 triples, the amendment note in integration v1, the presentation row, archives and diary-list time in section 9, the bound's name, and "characters of page text" in the egress row. The owner chose option A on 17 November 2026. This revision has had no review of its own.

After implementation, one blind invariant review of the diff (read-only): pass with notes, nothing blocking. Folded in: the part-read threshold is fixed with the policy instead of following `current`; the v1/v2 part-read rejection test now uses a document that validates and binds, so only the explicit admission rule can reject it; the presentation-taking content initialiser fails closed on an unknown presentation; Developer tools names the saved review's version, choice policy and presentation; the `.jev` and applicability request bodies are pinned without the part-read record; the archive comment cites this gate. One note went to the owner: the approved egress row counted distinct page text, while the catalogue repeats up to 100 characters of overlap per 1,400-character excerpt of a long block. The owner asked for the overlap clause to be added to the row. The fixes have had no review of their own.

An independent blind invariant review at the pull request head (441bb44b): pass with notes, nothing blocking. Folded in: v3 decoding is strict at every level, on the owner's decision; a PDF over its own 512-row bound but within 2,048 blocks is projected and refused; the old writers' refusals have a positive control on the same fixture; the v1/v2 part-read case is checked through `restoredSourceCandidate`, and the selected-locator clause is tested on its own; the Developer tools line reads "Review format if used" and a presentation test pins it with the v3 save. These fixes have had no review of their own.
