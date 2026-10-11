# UX revamp phase 6: Home (#199) phase plan

Status: **architecture gate passed with changes, 11 October 2026; changes folded in below.** Contract: [today-so-far-projection-v1.md](today-so-far-projection-v1.md) (`today_so_far_health_v1`, owner decisions D1 to D11). Specification: [ux-revamp-v1.md](ux-revamp-v1.md). Wireframe: [`designs/ux-revamp-v1/Main.dc.html`](designs/ux-revamp-v1/Main.dc.html). Carries #142's outstanding acceptance.

Order: (1) behaviour-neutral pure extractions (weight lookback function, `BloodPressureReading.latestValid`) as their own commit with existing tests unchanged; (2) contract tests; (3) Home. No HealthKit type, schema, egress or export change.

## Layout (wireframe order)

| Block | Content | States |
|---|---|---|
| Header | Weekday and date, large title "Today", gear to Settings | |
| Food card | "Food logged", link to Food Log; energy kcal and entry count; protein, carbohydrates, fat, water; "+" on a known minimum with one footnote ("Fat unknown for 1 entry, so 41 g is a known minimum.") | Empty ("Nothing logged yet today", never 0 kcal), partial, failed with Try again, loading |
| Add food | Prominent button to Add food | |
| Quick add | Up to four chips from Favourites, "Edit" to Favourites; chips open the quick-add sheet | Hidden until #198 lands; empty shows "Add favourites" link |
| Health · today so far | Steps so far, active energy so far, sleep last night ("so far" before noon), latest weight and blood pressure with times; link to Health; footer "Today is still in progress. Health summaries use completed days." plus "As of HH:mm" | Per row: loading, value, no data or no access, failed; whole card: Health unavailable |
| Today's notes | Today's note count, opens today's notes | No notes ("None yet") |

Home is today only. Day navigation and recent-day previews move to Food Log (#197).

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
| Home screen | `Views/FoodIntakeHomeView.swift` (`isHome`, day navigation) | New `Views/HomeView.swift`; `FoodIntakeHomeView` keeps the Food Log role until #197 |
| Food totals | `FoodIntakeProjection` (`food-intake-summary-v1`) | Unchanged; water appears once #198's water reference contributes mL |
| Health highlights | none | `Models/TodaySoFarHealth.swift`; conformance appended to `HealthKit/HealthKitClient.swift` (private helpers, no modifier change); `Views/TodaySoFarHealthModel.swift`; `HealthReportFormatter` `todaySoFar` copy |
| Refresh | `scenePhase`, `significantTimeChangeNotification` in `FoodIntakeHomeView` | `HomeView`; food also after save, edit, remove, restore; health per contract section 6 |
| Routes | `foodLog`, `healthReport`, `notes`, `noteEditor`, `settings` | Unchanged, plus `todayNotes`, `todayNoteEditor` |
| Boundaries | `Packages/FoodLedgerKit/Scripts/check-boundaries.sh` (packages only) | New app check in the same CI job: no `import HealthKit`, `SwiftUI` or `UIKit` in `WeeklyHealthReport/Models/*.swift` (all files pass today) |

## Risks

- **Fourth day rule by accident.** D1 keeps the existing sleep bucket and labels it in progress before noon.
- **Adapter drift.** Tests run on fakes, so the `HealthKitClient.swift` diff is reviewed: appended lines plus the one no-op lookback edit only.
- **Zero leaks.** Formatter tests cover every state; nothing nil renders as 0.
- **Authorisation on first Home appearance (D5).** Same read set, once per session.
- **Notes day confusion.** Pinning and restoring the export selection is tested both ways.
- **Water depends on #198.** Hidden until the reference exists, never 0.
- **Stale values.** No live updates; "As of HH:mm" shows staleness.

## Tests

- Contract tests in the projection contract section 9, written first.
- Home composition: card order; each feature contributes its card; a stub extra health highlight renders without editing `HomeView` or `HomeCardID`.
- Food card: empty is not zero; known-minimum note; refresh after save, edit, remove, restore and on rollover; reporting day across DST (from #142).
- Notes: with the export on a past day, the Home row shows today's count and opens today; leaving restores the export's day; restoration of `todayNotes` and `todayNoteEditor` with and without a draft; existing `.notes` restoration unchanged.
- Native render (simulator, hosted `UIHostingController` snapshots): empty and partial food, every health state, default and `accessibility3` Dynamic Type; VoiceOver reads "Steps, 6,412 so far" and "Blood pressure, 123 over 78 millimetres of mercury, 07:10".
- Full simulator suite, Xcode static analysis, both boundary checks, `git diff --check`.
- Device: contract section 10, logging from Home, rollover after midnight. Simulator evidence is not live HealthKit validation.

## Out of scope

Health screen and Export redesign (#200), new HealthKit types, trends, targets, net energy, background refresh.
