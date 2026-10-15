# UX revamp phase 2: Confirm food (#195) architecture gate

Status: **draft for owner review, 11 October 2026.** Contract: [food-confirmation-contract-v5.md](food-confirmation-contract-v5.md) (the specification's "Confirmation v3", policy `food_confirmation_v5`). Specification: [ux-revamp-v1.md](ux-revamp-v1.md). Wireframe: [`designs/ux-revamp-v1/Confirm.dc.html`](designs/ux-revamp-v1/Confirm.dc.html).

Contract tests land first; the screen follows. Owner decisions D1 to D7 (contract section 13, all marked recommended) are approved before production code.

## Responsibilities and files

| Layer | Owns in this phase | Files |
|---|---|---|
| Domain | `IdentityContradiction` (unchanged); persisted closed facet, source-state and choice types; under D1 `FoodLogDecisionRecord` with strict decoding and optional `UserAssertion.confirmation` | `FoodLedgerDomain/IdentityAndRecords.swift`, `ValidatedDecoding.swift` |
| Application | `FoodLogRequirement` and pure `FoodLogPolicy.requirements(state:now:calendar:)` (deviation: application, not domain); offered options per facet; `food_confirmation_v5`; reducer actions `decideDifference`, `setOccurredAt`, `confirmRetainedWeight`, `log`; removal of `acceptClosestMatch`; service enforces policy, exact decision set, bypasses, When window, one assertion with golden strings, no aliases for estimates (D6); `FoodEntryEstimateStatus` projection; `confirm_food_v3` in `declaredQuantityTypes`, registry v4 and `confirmedLogItemID`; food contract 4 | `FoodConfirmation.swift`, `FoodConfirmationPolicy.swift`, new `FoodLogPolicy.swift` (also holds the `FoodEntryEstimateStatus` projection), `FoodLedgerService.swift`, `LedgerCommands.swift`, `CanonicalFoodArchive.swift` |
| Infrastructure | Metadata-only migration `v4_confirmation_decisions`; schema 4 identity; registry wiring | `FoodLedgerGRDB/FoodLedgerMigrations.swift`, `FoodLedgerGRDBStore.swift` |
| Presentation | New screen order; one requirement renderer; inline decision rows; When row; Log bar with blocked reason; correction sheet; no copy naming a disclosure | `FoodLedgerPresentation/FoodConfirmationView.swift` (screen and inline correction sheet) and `FoodLogRequirementText.swift`; the Food Log row label in `WeeklyHealthReport/Views/FoodIntakeHomeView.swift` |
| Composition root and app | One clock and calendar wired into view model and service (service authoritative); unchanged route wiring; Daily JSON food admission pinned to contract `<= 3` (D7) | `WeeklyHealthReport/FoodLedger/FoodLedgerCompositionRoot.swift`, `WeeklyHealthReport/Models/DailyHealthExport.swift` |

## Dependency direction

Presentation → Application → Domain. GRDB → Application ports → Domain. The view model reads requirements and options from `FoodLogPolicy`; it never computes eligibility, differences or reporting days. Copy lives only in presentation. The existing FoodLedgerKit import-boundary check covers the new files; no new target is needed.

## Invariants protected

Source identity and nutrients are never changed by a decision; differences stay a closed set computed as today, with today's reopened and correction bypasses; exact-product unknowns block; generic equal unknowns stay unknown; no requirement is lost; exactly one assertion per save; edits write only a log version; reporting day is derived from `occurredAt` with the injected calendar; history is append-only; historical payloads re-encode byte for byte. The claim grammar is persisted, versioned data, not UI copy.

## Screen structure (wireframe order)

| Wireframe block | Content | Today's source |
|---|---|---|
| Navigation | Cancel, "Confirm food" | `Leave without saving`, title |
| Food | Name, plain source line ("UK reference food · cooked"), estimate label and "Unknown details stay unknown" whenever the save would be an estimate, "Choose a different match" | `identitySection`, `candidateSection` picker |
| Inline decisions | One question per `decideDifference` with policy-offered options; serving basis and edible quantity as acknowledgement rows | `differencesSection` and the closest-match text field |
| Missing source details | `sourceIdentityMissing` with "Choose a different match" and "Add food details" (sheet) | Missing-details caption and correction disclosure |
| Amount eaten | Amount, unit, measured weight, conversion, "Weighed on a plate", **When** | `quantitySection`, plate and direct-weight rows |
| Nutrition for the amount | Energy, protein, carbohydrates, fat; "More nutrients" disclosure | `compactNutritionSection`, "More nutrients" |
| Source | Source name with Details (release, record, basis) | "Source details" disclosure |
| Save as favourite | Slot left empty; no library record (D4) | none |
| Footnote | "Need to correct the food itself?" pointing to match or the saved entry | new |
| Log bar | "Log 248 kcal" (or "Log" when energy is unknown); disabled with the first requirement | `actionSection` "Save food" |

## Existing Confirm states

| Today | Phase 2 |
|---|---|
| `undecided` / "Accept this match" | Removed; Log is acceptance |
| `acceptedClosestMatch(explanation)` | Inline decisions, recorded as a labelled estimate |
| `declined` / "None of these" | Cancel |
| `editing` with requirements | Blocked bar with reason, inline rows marked |
| `editing`, no requirements | Ready |
| `saving` | Log shows progress; inputs disabled |
| `saveFailed(message)` | Inline failure above the bar with "Try again"; state retained |
| `saved(logItemID)` | Saved confirmation and Done (route decides the destination). **15 October 2026, owner decision:** a new single food closes Confirm on Log and the destination shows "Logged · …" with Undo; list import, Edit and a failed favourite keep this saved state (see phase 4, "Log closes Confirm with Undo") |
| Reopened (`reopened != nil`) | Same screen titled for editing; When starts at the stored time; decisions not asked again |
| Direct weight needs reconfirmation | "Keep this weight" inline action |

## Entry routes (all build `FoodConfirmationState` and reach the same screen)

Generic search (CoFID, USDA, TFDA, personal library) via `GenericFoodSearchFlowView`; reviewed web proposal via `OpenRouterFoodReviewFlowView`; barcode, direct and through search, via `BarcodeFoodFlowView`; paste or dictate per item via `FoodListImportView`; saved entry Edit via `FoodIntakeHomeView` / `SavedFoodEntrySheet` → `model(reopening:)`. None changes in this phase; a simulator UI test per route asserts it lands on the new screen.

## Risks

- **D2 gap:** the wireframe's skin question does not arise from current data (search routes set the expected identity to the first candidate); this phase adds no inference.
- **Old binaries:** schema 4 makes downgrade impossible, and a v5 binary always exports archive contract 4, which older builds cannot import. The release note states both.
- **Correction reach:** removing the disclosure could strand an exact product with unknown identity; the requirement row's sheet prevents it.
- **Time zones and midnight:** a changed time re-derives the day; an unchanged instant keeps the stored day; "Now" resolves at commit.
- **Daily JSON:** without the D7 pin, bumping the food contract would silently widen schema-4 admission.
- **Hidden callers:** `Tools/NutritionEvaluationSpike` builds `FoodConfirmationState` and must compile after the reducer change.
- **Accessibility:** inline decisions are the first VoiceOver stop after the food; the blocked reason is announced with the disabled button; targets stay at 44 pt at accessibility text sizes.

## Tests

The contract's section 11 list (items 1 to 17) is the gate. By level:

1. **Pure policy:** requirement mapping table; bypasses; offered options per facet; exact decision-set and `sourceState` checks; strict decoding; golden reason and claim strings; When window, midnight and DST cases in `Europe/London` and `Pacific/Auckland` (29 March, 25 October 2026); reviewed web `invalidReviewedSource` before policy.
2. **Persistence and archive (memory and GRDB):** edit-only mutations; one assertion per save; estimate projection after save, reopen and archive round trip; alias rule; time-edit head move with removal and restoration; literal v1 to v4 payloads, hashes and legacy archives byte for byte; registry, contract and schema admission (`unknownSchema(4)`, no row rewrite); retry recovery for `confirm_food_v3`.
3. **App:** `DailyHealthExportTests` rejects a contract-4 food document.
4. **View model:** Log disabled until requirements clear; one press saves once; failure keeps state; blocked reason is the first requirement; estimate label and unknowns notice on the primary screen; reopen shows the stored time.
5. **Simulator UI:** each entry route reaches Confirm; a difference blocks until answered; backdating to yesterday lists the entry on that day; Dynamic Type at accessibility sizes; VoiceOver order.
6. **Gates:** `Tools/NutritionEvaluationSpike` compiles; complete FoodLedgerKit and simulator suites; Xcode static analysis; boundary check; `git diff --check`; device check of the full log journey.
