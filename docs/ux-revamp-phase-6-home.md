# UX revamp phase 6: Home (#199) phase plan

Status: **owner-approved, 12 October 2026 (D1 to D11 with every recommended answer; approval comment on PR #208). Architecture gate passed with changes, 11 October 2026; changes folded in below. Rebased on phases 3, 4 and 7; implementation follows phase 5 (#198, PR #209), see Rebase notes.** Contract: [today-so-far-projection-v1.md](today-so-far-projection-v1.md) (`today_so_far_health_v1`, owner decisions D1 to D11). Specification: [ux-revamp-v1.md](ux-revamp-v1.md). Wireframe: [`designs/ux-revamp-v1/Main.dc.html`](designs/ux-revamp-v1/Main.dc.html). Carries #142's outstanding acceptance.

Order: (1) behaviour-neutral pure extractions (weight lookback function, `BloodPressureReading.latestValid`) as their own commit with existing tests unchanged; (2) contract tests; (3) Home. No HealthKit type, schema, egress or export change.

## Layout (wireframe order)

| Block | Content | States |
|---|---|---|
| Header | Weekday and date, large title "Today", gear to Settings | |
| Food card | "Food logged", link to Food Log; energy kcal and entry count; protein, carbohydrates, fat, fibre (amended 23 October 2026, #288); "Plain water logged" (phase 5 Q8); "+" on a known minimum with one footnote ("Fat unknown for 1 entry, so 41 g is a known minimum.") | Empty ("Nothing logged yet today", never 0 kcal), partial, failed with Try again, loading |
| Add food | Prominent button to Add food | |
| Quick add | Up to four chips (`FavouritesProjection.todayCount`), built-in Water 250 mL when no favourite is stored; "Manage favourites" to `favourites`; chips open the quick-add sheet (phase 5) | Empty: "No favourites yet" and Manage favourites; unreadable: "Favourites could not be read." and Review favourites |
| Health · today so far | Steps so far, active energy so far, sleep last night ("so far" before noon), latest weight and blood pressure with times; link to Health; footer "Today is still in progress. Health summaries use completed days." plus "As of HH:mm" | Per row: loading, value, no data or no access, failed; whole card: Health unavailable |
| Today's notes | Today's note count, opens today's notes | No notes ("None yet") |

Home is today only. Day navigation and recent-day previews move to Food Log (#197).

**Amendment, 23 October 2026 (owner decision, #288).** The food card gains a "Fibre" row after Fat (`FoodHomeCardContent.nutrientKeys` gains `fiber`). It is today's food-log fibre total so far under `food-intake-summary-v3`, the same figure as the Food Log strip: "18 g", "18 g+" with the card's one footnote when an entry's fibre is unknown, "Unknown" when no entry has fibre (never 0 g), the "Includes estimates" caption when known values include estimates, and VoiceOver "Fibre, at least 18 grams". Plain water contributes exactly 0 g (food-quick-add-contract-v1 Q1). The row follows the card's existing Dynamic Type layout and appears in Today's Full Page with the card's words. It stays a Home value (D10): it never enters Copy all, the Health report or the export.

## Home cards contributed per feature

```swift
enum HomeCardID: Int, Comparable, CaseIterable { case food, addFood, quickAdd, healthToday, notes }
struct HomeCard: Identifiable { let id: HomeCardID; let content: @MainActor () -> AnyView }
```

Factories live with each feature (`FoodLedger/FoodHomeCards.swift`; `Views/TodaySoFarHealthCard.swift`; `Notes/NotesHomeCard.swift`). The composition root collects them; `HomeView` sorts by `HomeCardID` and renders. A new health highlight touches only the health feature's files (projection, adapter extension, formatter, card); it never changes `HomeView` or `HomeCardID`. A new card kind is a new feature and adds one `HomeCardID` case. A missing food ledger contributes an unavailable food card rather than omitting it.

## Notes pinned to today (D11)

Today `.notes` and `.noteEditor` use `dailyExport.notes`, whose day follows the export's `selectReportDay`, so a Home row could open a past day. Home instead uses two new routes, `todayNotes` and `todayNoteEditor`, on the same `DailyNotesController` (one draft owner, one store). On appear they call a new `pinToday()` that sets the controller's day to today from its injected clock and remembers the export's selection; on disappear `unpinToday()` restores it, and the export screen re-asserts `selectReportDay` on appear. Today's count on Home is `document.snapshot(for: todayID)` with today's ID from the injected clock, independent of the selected day. Saving a today note still calls `onSavedNotesMutation`, which invalidates an export preview only when that preview is today's (existing behaviour). Restoration: `todayNotes` to `[todayNotes]`; `todayNoteEditor` to `[todayNotes, todayNoteEditor]` with a draft, else `[todayNotes]`; `.notes` and `.noteEditor` unchanged. Older builds reading the new raw values fall back to an empty path.

## Mapping to code

| Concern | Today | Phase 6 |
|---|---|---|
| Home screen | `Views/FoodIntakeHomeView.swift` (Home only since phase 4; phase 5 adds chips and plain water) | New `Views/HomeView.swift` replaces it; `FoodIntakeHomeView.swift` is deleted (Food Log is `Views/FoodLogView.swift`) |
| Food totals | `FoodIntakeProjection` (`food-intake-summary-v1`); `root.plainWaterTotal(for:calendar:)` (phase 5) | Unchanged; both called with the root's injected clock and calendar |
| Health highlights | none | `Models/TodaySoFarHealth.swift`; conformance appended to `HealthKit/HealthKitClient.swift` (private helpers, no modifier change); `Views/TodaySoFarHealthModel.swift`; `HealthReportFormatter` `todaySoFar` copy |
| Refresh | `scenePhase`, `significantTimeChangeNotification` in `FoodIntakeHomeView` | `HomeView`; food also after save, edit, remove, restore; health per contract section 6 |
| Routes | `foodLog`, `healthReport`, `addFood`, `favourites` (phase 5), `notes`, `noteEditor`, `settings` | Unchanged, plus `todayNotes`, `todayNoteEditor` appended after `favourites` |
| Boundaries | `Packages/FoodLedgerKit/Scripts/check-boundaries.sh` (packages); `Tools/check-app-boundaries.sh` (phase 7: `Presentation/` imports Foundation only) | Extend `Tools/check-app-boundaries.sh` with a `Models/` rule: no `import HealthKit`, `SwiftUI` or `UIKit` (all files pass today) |

## Risks

- **Fourth day rule by accident.** D1 keeps the existing sleep bucket and labels it in progress before noon.
- **Adapter drift.** Tests run on fakes, so the `HealthKitClient.swift` diff is reviewed: appended lines plus the one no-op lookback edit only.
- **Zero leaks.** Formatter tests cover every state; nothing nil renders as 0.
- **Authorisation on first Home appearance (D5).** Same read set, once per session.
- **Notes day confusion.** Pinning and restoring the export selection is tested both ways.
- **Water follows #198 Q8.** "Plain water logged" with No data when none is logged, "+" when a known minimum; never 0.
- **Stale values.** No live updates; "As of HH:mm" shows staleness.

## Tests

- Contract tests in the projection contract section 9, written first.
- Home composition: card order; each feature contributes its card; a stub extra health highlight renders without editing `HomeView` or `HomeCardID`.
- Food card: empty is not zero; known-minimum note; refresh after save, edit, remove, restore and on rollover; reporting day across DST (from #142).
- Notes: with the export on a past day, the Home row shows today's count and opens today; leaving restores the export's day; restoration of `todayNotes` and `todayNoteEditor` with and without a draft; existing `.notes` restoration unchanged.
- Native render (simulator, hosted `UIHostingController` snapshots): empty and partial food, every health state, default and `accessibility3` Dynamic Type; VoiceOver reads "Steps, 6,412 so far" and "Blood pressure, 123 over 78 millimetres of mercury, 07:10".
- Full simulator suite, Xcode static analysis, both boundary checks, `git diff --check`.
- Device: contract section 10, logging from Home, rollover after midnight. Simulator evidence is not live HealthKit validation.

## Rebase notes (12 October 2026)

Rebased onto `main` with phases 3 (#207), 4 (#211) and 7 (#210), and compared with phase 5 (`docs/198-quick-add-contract`, PR #209, head `0a186c1`). Phase 6 is implemented on top of phase 5 once it merges. These notes override any older reference above; no contract rule changed.

**What moved**

| Item | Where it was assumed | Where it is now |
|---|---|---|
| Home view | `FoodIntakeHomeView` with `isHome` and day navigation | Phase 4 removed day navigation and `isHome`; `FoodIntakeHomeView` is Home only (summary grid, Add food, "Manage food intake", "Export health data", three recent entries opening `SavedFoodEntryView`, Health report link). It still reads `Date()` and `.current` |
| Food Log | `FoodIntakeHomeView` | `Views/FoodLogView.swift` over `FoodLogViewModel` (FoodLedgerPresentation) and `FoodLogReadingService` (FoodLedgerApplication) |
| Add food finish | none | `AppNavigationCoordinator.finishFoodEntry(reportingDay:)`: from Food Log it returns there with `foodLogFocusDay` set; from Home (or restored) it empties the path, so Home reloads on appear. `FoodEntryFinish` is passed to every Confirm host inside Add food |
| Quick add on Home (phase 5) | Hidden placeholder | `FoodIntakeHomeView` gains `quickAddItems` (`root.quickAddItems()`, nil when unreadable), a "Quick add" section with `QuickAddChipRow` over the first `FavouritesProjection.todayCount` (4) items, built-in Water 250 mL when none is stored, "Manage favourites" to `.favourites`, and the sheet through `View.quickAdd(root:request:finish:logged:)` (`QuickAddPresenter` in `FoodLedger/FoodLedgerCompositionRoot.swift`), whose completion runs once after Log and reloads Home |
| Water on Home (phase 5) | Dietary water nutrient total once the reference exists | Q8 of [food-quick-add-contract-v1.md](food-quick-add-contract-v1.md): "Plain water logged" from `root.plainWaterTotal(for:calendar:)` (`PlainWaterDayTotal`), copy from `FoodLogText.plainWaterLabel`, `plainWater(_:)` and `plainWaterAccessibility(_:)`; No data when none, "730 mL+" when a known minimum. The Food Log strip shows the same figure |
| Routes | `foodLog`, `healthReport`, `notes`, `noteEditor`, `settings` | Main adds `addFood` (phase 3) and `exportDestination` (phase 7, restores `[settings, exportDestination]`); phase 5 adds `favourites` (restores `[favourites]`). `notes` restores `[dailyExport, notes]` and `noteEditor` `[dailyExport, notes, noteEditor]` with a draft. `todayNotes` and `todayNoteEditor` are appended after `favourites`; raw values are persisted, so nothing is renamed or reordered, and `AppNavigationTests` route-order expectations gain the two cases |
| Export entry | Home link | Phase 7 puts the Export link on the Health screen (`HealthReportView`, `AppRoute.dailyExport`), matching the navigation tree (Home → Health → Export). Home drops "Export health data" |
| Health screen tiles | none | Phase 7 `Presentation/HealthSummaryTiles.swift` (Foundation only) titles "Steps", "Sleep", "Resting heart rate", "Weight", "Morning blood pressure". Home's rows keep their own labels ("Blood pressure" is the latest pair, not the morning slot) and never reuse the tile values, which are completed-day figures |
| App presentation boundary | New `Models/` check | Phase 7 added `Tools/check-app-boundaries.sh` (CI step "Guard app presentation imports"): every Swift file under `WeeklyHealthReport/Presentation/` imports Foundation only. Phase 6 extends this script rather than adding another |
| `HealthKitClient.swift` | Private helpers, `-30` literal | Unchanged by phases 3, 4, 5 and 7. Helpers still at: `fetchWeightMeasurements` (the `value: -30` lookback), `fetchBloodPressureReadings`, `fetchActiveEnergyKilocalories`, `fetchStepTotal`, `fetchAsleepIntervals`, `fetchCumulativeTotal`; `requestReadAuthorization()` exists |
| Step value type | `CumulativeTotal` in the section 4 port sketch | No such type exists. `fetchStepTotal(in:)` returns `DailyStepTotal` (`Models/StepSummary.swift`: `day`, `steps: Double?`, `sourceNames`). The port uses `TodaySoFarRead<DailyStepTotal>`; the adapter maps `steps == nil` to `.noData`, so `.value` always carries a number. Same rule as the contract, corrected name only |
| Notes plumbing | `DailyNotesController.selectReportDay` | Unchanged (`Notes/DailyNotesController.swift`, `GoogleDrive/DailyDriveSessionController.swift`); `pinToday()` and `unpinToday()` are still new |
| `Models/` imports | Foundation only | `Models/DailyHealthExport.swift` also imports `FoodLedgerApplication`; the new `Models/` rule denies only `HealthKit`, `SwiftUI` and `UIKit`, so it still passes |
| Phase 5 export touch | none | Phase 5 changes one call in `Models/DailyHealthExport.swift` (`minimumContractVersion(for:favourites:)`). Phase 6 does not touch that file; contract test 11 still runs on the merged state |

**Placement for new app types**

- Pure Home health row presentation (row title, value text, accessibility label, state) goes in `Presentation/TodaySoFarHealthPresentation.swift`, Foundation only, so the existing boundary script covers it. Number and time strings stay in `Utilities/HealthReportFormatter.swift` (`todaySoFar` functions), as the contract says.
- Domain types stay in `Models/TodaySoFarHealth.swift`; `TodaySoFarHealthModel` (`@MainActor`, no SwiftUI import needed) in `Views/TodaySoFarHealthModel.swift`; SwiftUI cards in `Views/`.
- Food card and quick-add card factories live in `FoodLedger/FoodHomeCards.swift` and take the composition root; the quick-add card owns its sheet request state and applies `.quickAdd(root:request:logged:)` at card level, and reloads the food card through the shared Home refresh.
- Food reads use `root.confirmationNow` and `root.confirmationDayCalendar` for both `intakeProjection(for:calendar:)` and `plainWaterTotal(for:calendar:)`, replacing `Date()` and the `.current` defaults, so the food card and the health window agree on "today" under one injected clock.

**After phase 5 merged (12 October 2026).** `main` at `3c1304e` matches the phase 5 head these notes were checked against (`0a186c1`) apart from its ledger row, so every phase 5 reference above holds.

**Implementation notes**

- `HomeView` takes `HomeFeature` values (cards, an optional screen-level `decorate`, and a `refresh` for `HomeRefreshTrigger`). Quick add's sheet and full Confirm are presentation state of the Home screen, applied through the food feature's `decorate` with phase 5's `quickAdd(root:request:logged:)`; the chip only sets `FoodHomeModel.quickAddRequest`. This keeps `navigationDestination` out of lazy list rows.
- Notes pinning is driven by the navigation path (`AppRoute.pinsNotesToToday`) rather than per-screen appear and disappear, so pushing the editor over today's notes never flips the day in between. The export keeps its selection in `DailyNotesController`; `pinToday()` overrides it and `unpinToday()` returns to it. Export calls `reassertReportDay()` on appear.
- The health card shows Loading until the first projection for today exists (including while authorisation is requested); a window that cannot be computed shows Could not read Apple Health. Hosted unit tests refresh without requesting authorisation.
- Times use the locale's short time style through `DateFormatter` ("07:05" in en_GB, "7:05 AM" in en_US), as D4 specifies.
- Review fixes (12 October 2026, invariant review and journey QA of `334af539`):
  - The food card keeps the Food Log's "Includes estimates" caption (`FoodLogText.totalCaption`) under the energy headline and each nutrient row; VoiceOver already says "includes estimates".
  - Positive values below the display unit read "Less than 1 kcal so far" and "Less than 1 min", never 0; a returned exact 0 is still "0 so far" (D6).
  - `TodaySoFarHealthModel` uses the food ledger root's clock and calendar, the same as the food card and Home's date.
  - Read authorisation is single-flight: `SingleFlightReadAuthorization` wraps one `HealthKitClient` and is shared by the report (`WeeklyReportViewModel(readAuthorization:)`) and Home, so launch asks once. The read set and empty `toShare` are unchanged; `HealthDataProviding` and `FakeHealthDataProvider` are not changed.
  - "Today’s notes" uses the curly apostrophe.
  - Contract item 11 (accepted): `WeeklyReportScreenshotTests` changed only its two Home render sites, from the deleted `FoodIntakeHomeView` to `FoodHomeCard`, plus new tests; no fixture changed. A water-only day reading 0 kcal and 0 g follows the approved quick add Q1 (water's energy and macros are exact zeros).

**Owner decision F (13 October 2026).** The health card's header is plain text again (partly reversing PR #228's tappable header); its only link is the "Health summaries" row with the subtitle "Completed days", keeping the VoiceOver hint. The food card's known-minimum footnote is one line in every case: "Some values are unknown for N entries, so totals marked + are known minimums.", where N counts distinct current entries lacking a shown total.

**Needs owner decision**

None. Every change above is a file, type or placement reference. Phase 5's Q8 (plain water logged on Home) is already owner-approved in its own contract and replaces this plan's earlier "water once the reference exists" wording without changing a phase 6 rule.

## Out of scope

Health screen and Export redesign (#200), new HealthKit types, trends, targets, net energy, background refresh.
