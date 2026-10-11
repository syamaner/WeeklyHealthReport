# UX revamp phase 5: favourites, quick add and water (#198) architecture gate

Status: **draft for owner review, 11 October 2026.** Contract: [food-quick-add-contract-v1.md](food-quick-add-contract-v1.md). Specification: [ux-revamp-v1.md](ux-revamp-v1.md) (contract change 4). Wireframes: [`Favourites.dc.html`](designs/ux-revamp-v1/Favourites.dc.html), [`QuickAdd.dc.html`](designs/ux-revamp-v1/QuickAdd.dc.html).

Sequenced after phase 3 (#196, PR #207: `relogInput`, archive contract 5). Contract tests land first; owner decisions Q1 to Q10 are approved before production code.

## Screens

| Screen | Content | States |
|---|---|---|
| Favourites | "On Today's quick add" (first four, drag to reorder), "Other favourites" (estimate label where derived), create from Food search, Barcode, Web lookup; label photo and food photo "Not yet available"; rename, default amount, remove | Empty, loading, failed (competing heads), source unverifiable |
| Home quick-add chips | First four of the arrangement (built-in Water 250 mL when none stored); tap opens the sheet or, for an ineligible favourite, Confirm | No favourites (Water only) |
| Quick-add sheet | Food line, presets (water 150 / 250 / 330 / 500 mL) or Other amount, When, source line, Edit, "Log <amount>" | Ready, custom amount invalid, time out of window, saving, failed, saved |
| Confirm (v5) | "Save as favourite" toggle in the D4 slot; "Log and save favourite" when preset | Logged but favourite not saved, with Try again |

## Responsibilities and files

| Layer | Owns in this phase | Files |
|---|---|---|
| Domain | `FavouriteEntry`, `FavouriteVersion`, `FavouriteBinding`, `FavouriteAmount`, `FavouriteArrangement` with strict decoding; `ReferenceFoodID`; `ProvenanceSourceKind.appReferenceDefinition` | new `FoodLedgerDomain/Favourites.swift`, `Nutrition.swift`, `ValidatedDecoding.swift` |
| Application | `QuickAddPolicy` (eligibility and requirement split over `FoodLogPolicy`); `favouriteInput` sharing the generalised restore with `relogInput`; `PlainWaterReference.v1` input; `FavouritesProjection` (arrangement, heads, built-in water, derived estimate status); `FavouritesService` (save, revise, arrange); plain water daily total; operations, registry, contract 6 | `FoodConfirmation.swift`, new `QuickAdd.swift`, `Favourites.swift`, `PlainWaterReference.swift`, `FoodIntakeProjection.swift`, `LedgerCommands.swift`, `CanonicalFoodArchive.swift` |
| Infrastructure | Migration `v6_favourites`; favourite tables, reader by log item version; in-memory store parity | `FoodLedgerGRDB/FoodLedgerMigrations.swift`, `FoodLedgerGRDBStore.swift`, `FoodLedgerTestSupport/InMemoryFoodLedgerStore.swift` |
| Presentation | `FavouritesView` and view model, `QuickAddSheet` and view model, chip row, Save as favourite toggle; copy only | new `FoodLedgerPresentation/FavouritesView.swift`, `QuickAddSheet.swift`; `FoodConfirmationView.swift`; Common foods copy (Q6) in `CommonFoodsView.swift` |
| Composition root and app | Route `favourites` replacing the phase 3 placeholder; Home chips and sheet presentation state; one clock and calendar; Daily JSON pin test | `FoodLedgerCompositionRoot.swift`, `Views/AppRoute.swift`, `AppShellView.swift`, `FoodIntakeHomeView.swift`, `Models/DailyHealthExport.swift` |

## Dependency direction

Presentation → Application → Domain; GRDB → application ports → Domain. Views never decide eligibility, estimate status or totals; they render `QuickAddPolicy` and projection output. Favourite and water routes are entry-route adapters that build `FoodConfirmationState`; Confirm and `FoodConfirmationService.save` do not change behaviour. The FoodLedgerKit import-boundary check covers the new files; no new target.

## Invariants protected

One save path and one policy for Confirm and quick add; nothing logs on a tap; estimates always open Confirm; favourites are never exact aliases; favourite edits touch no log record; pinned bindings are immune to later source-entry edits; water is exact, mL only, no energy, aggregated daily-first with No data for empty days; historical bytes unchanged; HealthKit read-only; egress unchanged.

## Risks

- **Two "favourite" stores.** Inventory favourites remain; Q6 renames their copy so users do not expect them on Home.
- **Generalising the restore.** `restoredConfirmationInput` gains a pinned-version entry point; recent foods and reopen must keep identical behaviour (regression tests from PR #207 stay green).
- **Second operation after Log.** A failed `save_favourite_v1` leaves a logged entry without a favourite; the UI states it and retries idempotently.
- **Contract 6 downgrade.** Older builds cannot open data or archives; release note, as for contracts 4 and 5.
- **Phase 3 not merged.** If PR #207 changes `relogInput` or does not take contract 5, this contract's numbering and construction section are re-derived before implementation.
- **Water completeness.** Home's water figure is plain water logged; the nutrient total may be a known minimum (Q8).
- **Accessibility.** Chips and presets keep 44 pt targets at accessibility sizes; reorder has a VoiceOver alternative (move up / move down actions).

## Tests

The contract's section 7 list (1 to 13) is the gate. By level:

1. **Pure:** `QuickAddPolicy` eligibility and the requirement split; arrangement projection (first four, removed, missing, competing heads); water reference golden bytes and nutrients; daily-first water totals with DST and backdating; strict decoding.
2. **Persistence and archive (memory and GRDB):** sheet save equals Confirm save; favourite edits leave log bytes unchanged; pinned binding after source correction and removal; no library alias; contract 6 admission, `unknownSchema(6)`, migration rewrites no row; v1 to v5 byte-for-byte fixtures; retry recovery.
3. **View model:** chip tap writes nothing; one Log press saves once; invalid custom amount and out-of-window time block Log inline; ineligible favourite routes to Confirm; "Logged. Favourite not saved" with retry.
4. **Native render tests (hosted, synthetic data):** Favourites populated, empty and with an estimate row; Home chip row with built-in water and four favourites; quick-add sheet ready, custom-invalid and saving; Confirm with Save as favourite; each at standard and accessibility text sizes, light and dark.
5. **Simulator UI:** Home water chip → sheet → Log 250 mL appears in Food Log and the water total; favourite chip → sheet → Log; estimate favourite opens Confirm; reorder changes Home chips; photo rows show "Not yet available".
6. **App:** `DailyHealthExportTests` rejects a contract-6 food document.
7. **Gates:** complete FoodLedgerKit and simulator suites, Xcode static analysis, boundary check, `git diff --check`; device check of logging water and a favourite from Home.
