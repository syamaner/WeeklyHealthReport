# UX revamp phase 5: favourites, quick add and water (#198) architecture gate

Status: **approved 12 October 2026 (Q1 to Q11); implemented on this branch.** Contract: [food-quick-add-contract-v1.md](food-quick-add-contract-v1.md). Specification: [ux-revamp-v1.md](ux-revamp-v1.md) (contract change 4). Wireframes: [`Favourites.dc.html`](designs/ux-revamp-v1/Favourites.dc.html), [`QuickAdd.dc.html`](designs/ux-revamp-v1/QuickAdd.dc.html).

Entry condition: phase 3 (#196, PR #207: `relogInput`, archive contract 5) is merged. Contract tests land first; owner decisions Q1 to Q11 are approved before production code. Quick add creates a new log item at version 1 (amends the specification's "new version").

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
| Domain | `FavouriteEntry`, `FavouriteVersion`, `FavouriteBinding` (log item version or reference), `FavouriteAmount`, `FavouriteArrangement` with strict decoding; `ReferenceFoodID`; `ProvenanceSourceKind.appReferenceDefinition`; `CaptureKind.referenceDefinition` | new `FoodLedgerDomain/Favourites.swift`, `Nutrition.swift`, `ValidatedDecoding.swift` |
| Application | `QuickAddPolicy` (eligibility union and requirement split over `FoodLogPolicy`); `favouriteInput` sharing the generalised restore with `relogInput`, stripping aliases; named `save` change skipping canonically identical stored evidence (removing `relogSource`); `FavouriteMutation` outside `LedgerMutation` with `LedgerPayload` dispatch by operation type in commit, verify, import and replay; whole-projection `minimumContractVersion` and `recordCount`; `PlainWaterReference.v1` input; `FavouritesProjection` (arrangement, heads, built-in water, derived estimate status); `FavouritesService` (save, revise, arrange); plain water daily total; operations, registry, contract 6 | `FoodConfirmation.swift`, new `QuickAdd.swift`, `Favourites.swift`, `PlainWaterReference.swift`, `FoodIntakeProjection.swift`, `LedgerCommands.swift`, `CanonicalFoodArchive.swift` |
| Infrastructure | Migration `v6_favourites`; favourite tables with exactly-one-binding `CHECK` and immutability triggers; payload dispatch on insert; readers for evidence existence and by log item version; in-memory store parity | `FoodLedgerGRDB/FoodLedgerMigrations.swift`, `FoodLedgerGRDBStore.swift`, `FoodLedgerTestSupport/InMemoryFoodLedgerStore.swift` |
| Presentation | `FavouritesView` and view model, `QuickAddSheet` and view model, chip row, Save as favourite toggle; copy only | new `FoodLedgerPresentation/FavouritesView.swift`, `QuickAddSheet.swift`; `FoodConfirmationView.swift`; Common foods copy (Q6) in `CommonFoodsView.swift` |
| Composition root and app | Route `favourites` replacing the phase 3 placeholder; Home chips and sheet presentation state; one clock and calendar; Daily JSON pin test | `FoodLedgerCompositionRoot.swift`, `Views/AppRoute.swift`, `AppShellView.swift`, `FoodIntakeHomeView.swift`, `Models/DailyHealthExport.swift` |

## Dependency direction

Presentation → Application → Domain; GRDB → application ports → Domain. Views never decide eligibility, estimate status or totals; they render `QuickAddPolicy` and projection output. Favourite and water routes are entry-route adapters that build `FoodConfirmationState`; Confirm is unchanged and `FoodConfirmationService.save` gains only the named evidence-existence skip. The FoodLedgerKit import-boundary check covers the new files; no new target.

## Invariants protected

One save path and one policy for Confirm and quick add; nothing logs on a tap; estimates always open Confirm; favourites are never exact aliases; favourite edits touch no log record; pinned bindings are immune to later source-entry edits; water is exact, mL only, no energy, aggregated daily-first with No data for empty days; historical bytes unchanged; HealthKit read-only; egress unchanged.

## Risks

- **Two "favourite" stores.** Inventory favourites remain; Q6 renames their copy so users do not expect them on Home.
- **Generalising the restore.** `restoredConfirmationInput` gains a pinned-version entry point; recent foods and reopen must keep identical behaviour (regression tests from PR #207 stay green).
- **Second operation after Log.** A failed `save_favourite_v1` leaves a logged entry without a favourite; the UI states it and retries idempotently on the log item version key. An app kill between them is accepted; recovery is Save as favourite from the saved entry.
- **Evidence reuse.** Without the existence skip a second water log or a quick add after source removal would fail `immutableRecord`; tests A and B guard it.
- **Encoded mutations.** Favourite records stay out of `LedgerMutation`; a typed payload chosen by operation type keeps `.ledger` bytes identical and makes archive import, verification and the contract check see favourites (tests C, O to Q).
- **Contract 6 downgrade.** Older builds cannot open data or archives; release note, as for contracts 4 and 5.
- **Phase 3 not merged.** Entry condition; if PR #207 changes `relogInput` or contract 5, re-derive numbering and `minimumContractVersion` ordering (6 checked before 5).
- **Water completeness.** Home's water figure is plain water logged; the nutrient total may be a known minimum (Q8).
- **Accessibility.** Chips and presets keep 44 pt targets at accessibility sizes; reorder has a VoiceOver alternative (move up / move down actions).

## Tests

The contract's section 8 list (1 to 11 and A to U) is the gate. By level:

1. **Pure:** `QuickAddPolicy` eligibility union and requirement split; Q10 bound; arrangement projection (first four, removed, missing, competing favourite and arrangement heads); built-in water show and hide; water reference golden bytes, nutrients and completeness; plain water predicate; daily-first water totals with DST and backdating; strict decoding; provenance and capture kind switch classification.
2. **Persistence and archive (memory and GRDB):** sheet save equals Confirm save; repeated water saves and saves after source removal, restoration, correction and re-timing write no duplicate evidence; favourite edits leave log bytes unchanged; binding consistency; no alias growth; `save_favourite_v1` idempotency; literal pre-v6 payload, hash and projection fixtures; contract 6 for water-only ledgers, `unknownSchema(6)`, migration rewrites no row.
3. **View model:** chip tap writes nothing; one Log press saves once; invalid custom amount and out-of-window time block Log inline; ineligible favourite routes to Confirm; "Logged. Favourite not saved" with retry.
4. **Native render tests (hosted, synthetic data):** Favourites populated, empty and with an estimate row; Home chip row with built-in water and four favourites; quick-add sheet ready, custom-invalid and saving; Confirm with Save as favourite; each at standard and accessibility text sizes, light and dark.
5. **Simulator UI:** Home water chip → sheet → Log 250 mL appears in Food Log and the water total; favourite chip → sheet → Log; estimate favourite opens Confirm; reorder changes Home chips; photo rows show "Not yet available".
6. **App:** `DailyHealthExportTests` rejects a contract-6 food document.
7. **Gates:** complete FoodLedgerKit and simulator suites, Xcode static analysis, boundary check, `git diff --check`; device check of logging water and a favourite from Home.

## Rebase notes (12 October 2026, after phases 3 and 4 merged)

Checked against `main` at `def4b19` (phase 3 #207 as `34fae5d`, phase 4 #211 as `def4b19`). No contract rule changes; the items below are file references, representation details and one resolved open item.

- **Entry condition holds.** Archive contract 5 and schema `food-ledger-v5` landed with phase 3 as described: `minimumContractVersion` returns 5 for reviewed web manifest v2 evidence, `relogInput` and `relogState` exist, `relogSource` is the only retained-evidence mechanism and the default operation registry is still `builtInV4` (contract 5 added no operation type). Contract 6 and `food-ledger-v6` follow directly; contract 6 conditions are checked before contract 5 ones. No renumbering.
- **Registry.** A new `LedgerOperationRegistry.builtInV6` admits the three favourite operations; the store, verifier and ledger service defaults move from `builtInV4` to `builtInV6`. `builtInV4` keeps rejecting them.
- **Reader ports.** `FoodConfirmationReading` gains `foodConfirmation(logItemVersionID:)` (the pinned-version aggregate) and `evidence(id:)` (the Q11 existence check); a new `FavouriteReading` port returns the favourite records. Both stores and the test readers implement them. `FoodConfirmationService` takes an injected canonical encoder for the byte comparison (defaulting to the canonical JSON encoder).
- **Phase 4 finishing.** Confirm hosts inside Add food finish through `FoodEntryFinish` and `AppNavigationCoordinator.finishFoodEntry`. "Log and save favourite" writes the favourite before finishing; when the favourite fails, Confirm stays open on "Logged. Favourite not saved" with Try again and Done, and Done finishes as usual. The quick-add sheet is presentation state of Home (outside Add food), so after Log it closes and Home reloads; nothing navigates.
- **Food Log strip (F1 resolved).** Phase 4 kept water out of the strip until this phase defined it. Under Q8 the strip gains one "Water" cell showing **plain water logged** for the day, the same figure as Home, labelled as plain water logged, and No data when none is logged. `FoodIntakeSummary` totals and the four existing cells are unchanged; the dietary water nutrient total stays in each entry's nutrients with its known-minimum rule.
- **Favourites route.** Add food's "Favourites" row opened the Common foods screen as a phase 3 placeholder; it now opens the Favourites screen. A new `AppRoute.favourites` raw value is added (existing raw values unchanged) and restores to itself. Common foods keeps its route and data; only its copy changes (Q6).
- **Water identity representation.** `PackingMediumState` and `FortificationState` have no `not_applicable` case, so the reference record uses the existing conventions for "nothing applies": packing medium `named("none")` and fortification `unfortified`. Bone, skin and drained are `not_applicable`. The candidate's edible quantity is the known 100 mL basis quantity (the CoFID convention), so v5 raises no edible quantity difference. Exact, fully known identity, as the contract requires.
- **Water source release identifier.** `sourceReleaseID` is `weeklyhealthreport.reference:plain-water-v1` (source ID `weeklyhealthreport.reference`, release `plain-water-v1`), following the existing `<source>:<release>` identifier style.
- **Home.** Home is redesigned in phase 6 (#199). This phase adds the quick-add chip row, the sheet and a plain water figure to the current Home only.

### Implementation notes

- **Switch sites.** The exhaustive switches over `ProvenanceSourceKind` are the three nutrient validation switches in `Nutrition.swift` (measured: admitted with a record ID; augmented and bounded: refused). No presentation code switches over provenance or capture kind, so there is no "App reference" label site; water entries are labelled by the plain water source line instead. Generic and reviewed web policies classify the new cases as not generic and not applicable (test J).
- **Favourites store rules.** Both stores admit competing favourite and arrangement heads (as they arrive from an archive merge) and the projection fails explicitly; lineage, binding existence and the product-only binding are enforced at insert.
- **Usual foods.** With Add food's Favourites row now opening Favourites, Usual foods (the renamed Common foods) is linked from Settings › Data. Its route and data are unchanged.
- **Add food.** The Favourites section lists the quick-add items; a tap opens the same sheet or Confirm as a Home chip and, after Log, ends through Add food's single post-save exit.

### Review and journey QA fixes (12 October 2026, at 3a6264b)

- **Sheet completion (QA D1, high).** The sheet's view model now calls a completion exactly once after the one successful Log; the host dismisses the sheet there and reloads Home (or ends Add food through its single post-save exit). Completion is no longer inferred by observing the model's phase from a parent that did not observe it. Edit is unavailable once saving has started, so a logged sheet cannot be logged again through Confirm.
- **Favourites unreadable in Add food.** Add food shows "Favourites could not be read." with a way to Favourites, as Home does, instead of "No favourites yet".
- **Volume source.** The quick-add sheet and the Confirm opened from quick add run the rebuilt input through the same milk volume source enrichment as every other Confirm factory, and Confirm carries the offering.
- **Plain water and Save as favourite (QA D2), note for the owner.** Confirm no longer offers "Save as favourite" when the entry's source is the `plain-water-v1` reference: water is already the built-in quick add, and its name and default amount are editable in Favourites, so saving it again only produced a second "Water" item. No contract rule changed: a plain water favourite created by editing the built-in item is still a `.reference(.plainWaterV1)` chain, and the service still accepts a favourite bound to a saved water entry. If you want water entries to be favouritable from Confirm (for example several water sizes), that is a presentation change only.
- **Home empty state (QA D3)** reads "No favourites yet" above Manage favourites. **Chips (QA D4)** show the name on one block (truncating if needed) and the amount in full on its own line.
- **Plain water known minimum.** `PlainWaterDayTotal.total` returns the water total with its incomplete count; an entry edited to a unit that cannot be scaled makes the figure a known minimum, shown as "730 mL+" ("at least" for VoiceOver), the same style as the strip.
- **Daily JSON admission** passes the projection's favourites to `minimumContractVersion`, so a document relabelled as contract 3 while carrying favourite records is rejected.
- **Built-in water guards.** Saving, removing or arranging the built-in water item is refused (`builtInWaterAlreadySaved`) once any plain water favourite chain exists; nothing is written.
- The Sendable conversion warnings in the composition root are fixed.
