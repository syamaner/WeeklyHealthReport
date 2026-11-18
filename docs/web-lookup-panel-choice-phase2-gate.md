# Web lookup panel choice, phase 2: architecture gate

Status: **gate passed with changes (one blind review, folded in), 17 November 2026, no production code yet** (#508). Phase 2 of [web lookup part-read pages v1](web-lookup-part-read-pages-v1-proposal.md) ("the contract"): panel choice (contract sections 8 and 9, decision W8, answers O1 to O4). Phase 1 ([gate](web-lookup-larger-pages-phase1-gate.md), PR 512) already landed the complete stored format and admission of manifest v3, the choosable rule and the `web-lookup-review-v2` content for one candidate. This phase adds behaviour and must not change the v3 format, its admission or its pipeline triple. Part-read selection (phase 3) is out of scope.

## 1. Scope

In:

- The applicability check runs over the **choosable** candidates instead of the eligible ones, so a page whose candidates conflict with each other gets the check (answer O3).
- The **offer table** of contract section 8.3, rows 1 to 5, keyed on the recorded answer, as a pure application rule.
- The production writer prepares any offered candidate the person picked, writing `offered` (complete, in display order), `selectionChoice` (the model's answer, possibly `clarify`) and `personChoice`.
- Screen contract `web-lookup-review-v2` for several offered candidates: the panel list, "Suggested", "Choose a panel", the prompt, "Different values", the disabled reason, and the O4 warning line; rebuilt from a retained v3 manifest.
- Every place that tests `selectionEligible` to build, validate or permit a choice moves to `choosable` (listed in section 2).
- The privacy documents for the request change of answer O3, with wording shown to the owner first (section 6).
- Developer tools: choice policy, offered ids, pre-selection, whether a pick is required.

Out: part-read selection and its source order (phase 3); the refusal copy; any change to Confirm or its single Log action; the v3 format; removing duplicate candidates (section 4).

## 2. Responsibilities and the places that move to `choosable`

| Layer | Owns |
|---|---|
| Domain | Unchanged: `choosable`, `sameIdentity`, `conflicting` (phase 1). `FoodProposalSelection` accepts a choice among the **choosable** candidates plus `none` and `clarify`. |
| Infrastructure (`FoodGenericSearch`) | The applicability request carries the choosable candidates and offers their ids; the `.jev` route does the same. Instruction text and `food-proposal-applicability-v1` unchanged (section 4). |
| Application | `GenericFoodProposalReviewer` runs the check when any candidate is choosable. `GenericFoodProposalReview` gains `offer`: the offered candidates in display order, the pre-selected id or none, and whether the warning applies, computed by one pure function of the recorded selection, the validation and the query. `offer` is a computed property of the review (never a stored or init value), so no caller can supply it. `permitsConfirmation(of:)` becomes "offered". `ReviewedFoodProposalConfirmation.prepare` takes the review and the picked candidate, recomputes the offer and refuses a candidate outside it. The reviewer's `choicePolicyVersion` becomes `food-proposal-review-choice-v4`, the identifier v3 already records; **first**, the v2 gate record's known set and its init default are frozen as the literal `food-proposal-review-choice-v3`, so stored v2 reviews and the v2 regression writer are unaffected. |
| Presentation | The view model keeps the person's pick (initially the pre-selection), never a model answer; "Use this source" is enabled only when a pick exists and a scope is chosen. A pure content type builds the panel list from the offer, and from a retained v3 manifest. The SwiftUI view renders it. |

Places that test `selectionEligible` today and move: `FoodProposalSelection.init` (both); `GenericFoodProposalReviewer` (the skip test); `OpenRouterFoodProvider` (applicability body, `.jev` body, their option lists, probability keys and `excluded_candidates`); `GenericFoodProposalReview.permitsConfirmation`; `GenericFoodProposalReviewCopy` (no-suggestion, summary and status copy); the view model's `suggestedProposal`, the suggested section and the "Other sources" list, which read the offer, and from which offered candidates are excluded; the v3 writer's validation, which checks `choosable` itself. These use the domain `choosable`, with no query. Unchanged on purpose: the v1 and v2 regression writers keep `selectionEligible` (shared `validated` takes the rule as a parameter; the v2 writer is also held by `gate.permits`, which needs `selectionChoice == candidate.id`); `FoodReviewedWebProposalPolicy.scope` (it binds one candidate alone, where the two rules agree); the v2 gate record's frozen `choice-v3` set; the Developer tools "eligible" line (kept, with a "choosable" line added).

## 3. The offer rule

Input: the recorded selection (`choice`), `rankingUnavailable`, the validation's candidates in extraction order, and the query. **Offerable** means choosable (the domain rule, no query) and no basis conflict with the query; it is used only by this function. "Same identity" and "conflict" are the phase 1 predicates, evaluated only between offerable candidates and never read from `BoundFoodProposal.status` (which also marks conflicts with unusable candidates).

| Recorded answer | Offered, in extraction order | Pre-selected | Warning |
|---|---|---|---|
| A candidate X that is offerable, with no other offerable candidate of X's identity | X | X | no |
| A candidate X that is offerable, with other offerable candidates of X's identity | X and those candidates | X | no |
| A candidate that is not offerable | nothing | | |
| `clarify`, and at least two offerable candidates of one identity that each conflict with another offerable one | those candidates | none: a pick is required | yes |
| `clarify` otherwise | nothing (answer O1) | | |
| `none`; the check not run, unavailable or failed; no selector composed | nothing | | |

This matches v3 admission (phase 1 gate section 5) exactly, including the third-candidate case: under `clarify` a candidate that conflicts with none of the others is not offered. Offerable candidates of a different identity are never offered with X. Nothing is saved by a pick; the single "Use this source" action, the scope choice and Confirm are unchanged.

## 4. Settled here

- **Duplicates are kept.** Two candidates of one identity with equal values are both offered under row 2, numbered by their distinguishing details. Either pick saves the same values with its own evidence; removing one would need a rule for whose evidence to keep. Under `clarify` two equal candidates alone do not conflict, so nothing is offered; with a third that conflicts with both, all three are offered (admission agrees).
- **Applicability instruction unchanged.** The check may now see two panels of one food with different values. Its existing rules already cover this (`nutrient_meaning`: correct product, panel and column; ambiguity gives `clarify`). Either outcome is safe: a named panel is only a pre-selection, and `clarify` with conflicting panels is row 3 with the warning. The wire version `food-proposal-applicability-v1` and the schema stay; only the candidate set widens. The live measurement (contract test 21) reports how often each outcome occurs.
- **Order on a row 3 screen.** Section title "Choose a panel"; then the warning line (text, above the panels, read first by VoiceOver as plain static text); then the prompt "This page gives more than one set of values. Choose the one that matches your food."; then the rows. After a pick, the warning stays and the title stays.
- **Content as a pure function.** The panel list is a pure function of (`offered`, `selectionChoice`, the selected id, the document, the scope). Distinguishing details and "Entry n of m" are computed over `offered` only, so the live screen and the content rebuilt from a retained v3 manifest are equal; the rebuild takes the selected row from `personChoice`, "Suggested" from `selectionChoice`, the warning from `selectionChoice == clarify` and "Different values" from conflicts within `offered`.
- **Rows.** Each row: name, distinguishing details, basis label and declared values; "Suggested" on the pre-selected row; "Different values" on rows that conflict with another offered row. Rows that conflict also show the nearest heading block (`h1` to `h6`) before the panel's first panel-evidence block in the retained document, when there is one, and the first quote of the panel evidence. One row is selected at a time; the details, quotes and limitations below are the selected row's. Selected state is the selected trait plus a visible checkmark, rows are at least 44 points high, and each row's VoiceOver label names the panel and says whether it is the suggestion.
- **Disabled reason.** With nothing picked: "Choose a panel to use this source." beside the action. With a pick but no scope: the existing scope copy.
- **Summary line.** When a panel list is shown, the summary does not say none suits.
- **Conflict copy (contract section 9).** The sentence that the source "gives conflicting values for this food, so it cannot be used" is no longer shown, because every new review is v3. Where nothing is offered, the existing copy applies in its existing order: the unavailable text when the check failed, the `clarify` text, or "No usable source was found for this food." The "Conflicting values" status becomes "Different values" for an offered row; an unusable candidate keeps its existing status text.
- **Test 20 (an amendment of contract test 20, recorded for the owner).** The repository has no XCUITest target (one app and one unit-test bundle); routes are tested in the app-hosted test target. Test 20 is met by an app-hosted route test (lookup result with conflicting panels, pick, prepare, Confirm admits the saved v3 entry) and a rendered screenshot test of the panel list. A journey walk in the simulator needs a live lookup and is part of the owner's device check.

## 5. Invariants

- The v3 format, admission, pipeline triple and presentation identifiers are unchanged; every phase 1 v3 record is admitted as before; v1 and v2 unchanged.
- Model output never authorises nutrition: the pick and "Use this source" are the person's; under `clarify` nothing is pre-selected.
- No candidate for another food is offered with the suggestion (row 2 is restricted to its identity).
- Unknown stays unknown; the panel list shows only declared values.
- Presentation cannot construct a permitting gate or supply `offered`; the writer takes both from the review's offer and refuses a candidate outside it.

## 6. Owner decisions (17 November 2026)

Both questions below were approved by the owner as proposed: Q1 (the egress wording) and Q2 (the `AGENTS.md` note). Both land with this phase.

**Q1, egress wording (answer O3 needs it shown before it lands).** Proposed:

- `privacy-and-egress.md`, OpenRouter row, added to the "what" cell: "when a page gives more than one set of values for the same food, the applicability check, which skipped such a page or left those sets out before, is also sent, with the captured page text and every usable set extracted from it (panel choice, #508)".
- `privacy-policy.txt`, after the phase 1 sentence: "When a page gives more than one set of values for the same food, the captured page text and those sets are also sent for the check against the requested food."

The request is the existing applicability request (same destination, same content class, at most three attempts); it sends the whole catalogue of the captured page, as it does for any page today.

**Q2, pre-selection and the "no automatic selection" line in `AGENTS.md`** (contract section 13). With an untouched pre-selection, the record cannot tell a pick from a tap, as in v2 today. Proposal: add to the food records rule in `AGENTS.md` "A suggested panel may be pre-selected for the person to confirm or change; it is never saved without their action."

## 7. Contract tests in this phase

14. One case per row of section 3, including the action disabled until a pick under row 3; `clarify` with non-conflicting candidates; the check not run and no selector composed; a named candidate with a basis conflict gives nothing; a non-suggested candidate with a basis conflict is not offered; three candidates of which two conflict; two identical candidates.
15. Two candidates that differ in a declared value are both choosable and both offered; a candidate with a conflict inside itself is not; a choosable candidate of another identity is not offered with the suggestion.
16. The reviewer runs the check for a page whose candidates conflict and records its answer; the applicability body offers the choosable ids and carries the conflicting candidates.
17. Golden `web-lookup-review-v2` content with several candidates, with and without pre-selection, with the warning before and after a pick, and rebuilt from a retained v3 manifest; a named-candidate review does not carry the warning; presentation cannot supply `offered` or a permitting gate; picking and preparing make no network request.
- Writer: prepares the suggestion and a competing pick under row 2, and either pick under row 3, each admitted by v3 admission with `offered` equal to the review's offer; refuses a candidate outside the offer and refuses under row 3 without a pick.
- View model: the pick starts at the pre-selection (or none), changes only by the person's action, resets on a new result, and the action stays disabled without it.
20. App-hosted route test and a rendered screenshot of the panel list (section 4).
- v2 unchanged: the v2 gate record's known set and default stay `choice-v3`; `prepareVersion2` writes `choice-v3` and the golden v2 bytes rehash; `prepareVersion2` refuses a row 2 alternative and a row 3 pick.
- Exhaustive: over small fixtures (equal, conflicting, unusable by an internal conflict, other identity, basis conflict; up to three candidates) and every recorded answer, every offered candidate prepares, and the written manifest has `admissionFailure == nil` with `offered` equal to the offer.
- Row 3 whose only conflict partner is unusable: nothing offered, no "Different values". Two equal candidates plus a conflicting third under `clarify`: all three offered.
- Rebuilt content equals live content for row 2 and row 3 after a pick.
- Offered candidates are absent from "Other sources"; the summary does not say none suits when a list is shown; copy per row and for unavailable, `none` and skip.
- Request bodies: applicability `choice` enum and `candidates`, and `.jev` options, probability keys and `excluded_candidates`, all use domain `choosable` (basis-conflicting candidates included, as today); `FoodProposalSelection` accepts a choosable conflicting id and rejects an unusable one.
- Evaluation: FoodSearchQuality and FoodQueryEvaluation steps of `ios-ci.yml`.

Existing tests that change: the reviewer test that expects no check for a conflicting page (`testNoCandidateSkipsRankingRatherThanSelectingAnInventedCandidate` and any conflict-skip case), copy tests for the conflict sentence and status, `.jev` body tests that pin `excluded_candidates`, and v2 tests that read the reviewer constant. `GenericFoodProposalTests` conflict-status expectations stay.

## 8. Not established

- How often the check names a panel or answers `clarify` on real pages with competing panels; review time and tokens. Contract test 21, after phase 3; the owner chose not to release before then.
- Anything on a device.

## 9. Review record

One blind architecture-gate review of the draft (read-only, at ebfe9986): pass with changes. Folded in: the v2 gate record's `choice-v3` set and default frozen before the reviewer constant moves; the egress wording corrected to say the whole captured page text and every usable set are sent; "offerable" separated from the domain "choosable"; the missing sites (suggested section, "Other sources", summary); content as a pure function over `offered` so the rebuild equals the screen; the conflict copy following contract section 9; conflict evaluated only between offerable candidates; the duplicate case qualified; the shared `validated` split; `offer` computed, never supplied; test 20 recorded as an amendment; the existing tests that change. This revision has had no review of its own.

After implementation, one blind invariant review of the diff (read-only): pass with notes, nothing blocking. Folded in: "Different values" in "Other sources" comes only from a conflict with another choosable candidate, so a conflict with an unusable candidate is not shown as one; each panel's VoiceOver label carries its heading and declared values; the summary says the page gives more than one set of values only when offered panels differ; the provider test includes an unusable candidate and pins the `.jev` criteria keys; the rendered test reads both panels' values and goes on through the view model's pick and prepare to Confirm, with no request beyond key validation; the view model test checks that picking and preparing make no request and that a new result restarts at its own pre-selection. A candidate with a conflict inside itself shows "Needs more information" whether or not it also conflicts with another candidate. The app has no screen that reopens a saved review (contract section 6), so the rebuild of the panel list from a retained manifest is pinned at the content level. These fixes have had no review of their own. After that review the owner approved a correction to the egress row: the check "skipped such a page or left those sets out before" (18 November 2026); the policy sentence is unchanged.
