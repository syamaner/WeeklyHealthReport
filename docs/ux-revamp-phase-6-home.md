# UX revamp phase 6: Home (#199) phase plan

Status: **draft for owner review, 11 October 2026.** Contract: [today-so-far-projection-v1.md](today-so-far-projection-v1.md) (`today_so_far_health_v1`, owner decisions D1 to D9). Specification: [ux-revamp-v1.md](ux-revamp-v1.md). Wireframe: [`designs/ux-revamp-v1/Main.dc.html`](designs/ux-revamp-v1/Main.dc.html). Carries #142's outstanding acceptance.

Contract tests land first. No HealthKit type, schema, egress or export change.

## Layout (wireframe order)

| Block | Content | States |
|---|---|---|
| Header | Weekday and date, large title "Today", gear to Settings | |
| Food card | "Food logged", link to Food Log; energy kcal and entry count; protein, carbohydrates, fat, water; "+" on a known minimum with one footnote ("Fat unknown for 1 entry, so 41 g is a known minimum.") | Empty ("Nothing logged yet today", never 0 kcal), partial, failed with Try again, loading |
| Add food | Prominent button to Add food | |
| Quick add | Up to four chips from Favourites, "Edit" to Favourites; chips open the quick-add sheet | Hidden until #198 lands; empty shows "Add favourites" link |
| Health · today so far | Steps so far, active energy so far, sleep last night, latest weight and blood pressure with times; link to Health; footer "Today is still in progress. Health summaries use completed days." plus "As of HH:mm" | Per row: loading, value, no data or no access, failed; whole card: Health unavailable |
| Today's notes | Row with note count, opens notes for today | No notes ("None yet") |

Home is today only. Day navigation and recent-day previews move to Food Log (#197); "Return to today" is removed from Home.

## Home cards contributed per feature

```swift
enum HomeCardID: Int, Comparable, CaseIterable { case food, addFood, quickAdd, healthToday, notes }
struct HomeCard: Identifiable { let id: HomeCardID; let content: @MainActor () -> AnyView }
```

Factories live with each feature (`FoodLedger/FoodHomeCards.swift` for food, add food and quick add; `Views/TodaySoFarHealthCard.swift`; `Notes/NotesHomeCard.swift`). The composition root collects them; `HomeView` sorts by `HomeCardID` and renders. Adding a highlight changes the health card's projection and formatter only, never `HomeView`. Same pattern and tests as `SettingsSection` (#194). A missing food ledger contributes an unavailable food card rather than omitting it.

## Mapping to code

| Concern | Today | Phase 6 |
|---|---|---|
| Home screen | `Views/FoodIntakeHomeView.swift` (`isHome`, day navigation) | New `Views/HomeView.swift`; `FoodIntakeHomeView` keeps the Food Log role (`isHome == false`) until #197 replaces it |
| Food totals | `FoodIntakeProjection` / `FoodIntakeSummary` (`food-intake-summary-v1`) | Reused unchanged; water appears once #198's fixed water reference contributes mL |
| Health highlights | none | `Models/TodaySoFarHealth.swift`, `HealthKit/HealthKitClient+TodaySoFar.swift`, `Views/TodaySoFarHealthModel.swift`, `HealthReportFormatter` `todaySoFar` copy |
| Refresh | `scenePhase`, `significantTimeChangeNotification` in `FoodIntakeHomeView` | Moved to `HomeView`; food refresh also after save, edit, remove, restore; health per contract section 5 |
| Routes | `AppRoute.foodLog`, `.healthReport`, `.notes`, `.settings` | Unchanged raw values; notes row pushes the notes route directly instead of via `dailyExport` (restoration table entry for `notes` updated with a test) |
| Diagnostics | `DeveloperDiagnosticsView` | "Today so far (Home)" section |

## Risks

- **Fourth day rule by accident.** "Last night" near midnight or before waking can look wrong; D1 keeps the existing bucket and the copy states absence.
- **Export or report drift.** Sharing private HealthKit primitives could alter export predicates; golden snapshots and unchanged report tests are the guard, and `HealthDataProviding` stays untouched.
- **Zero leaks.** A nil formatted as "0" on the card would violate "unknown is never zero"; formatter tests cover every state.
- **Authorisation on launch (D5).** Showing the HealthKit sheet on first Home appearance changes first-run flow; it requests the existing read set only.
- **Water depends on #198.** Until #198's water reference exists the water cell is hidden, never shown as 0.
- **Notes route change.** Pushing notes outside `dailyExport` alters restoration; covered by `AppNavigationTests`.
- **Stale values.** No live updates; "As of HH:mm" makes staleness visible.

## Tests

- Contract tests 1 to 12 in the projection contract, written first.
- Home composition: card order, each feature contributes exactly its card, a stub extra highlight renders without editing `HomeView`.
- Food card: empty is not zero; partial shows the known-minimum note; refresh after save, edit, remove, restore and on day rollover; reporting day across DST (carried from #142).
- `AppNavigationTests` for the notes route and Home-to-Health, Food Log, Settings links.
- Native render tests (simulator, `ImageRenderer` or hosted `UIHostingController` snapshots): Home with empty food, partial food, all health states (loading, available, no data, failed, unavailable), at default and `accessibility3` Dynamic Type; VoiceOver labels read "Steps, 6,412 so far" and "Blood pressure, 123 over 78 millimetres of mercury, 07:10".
- Full simulator suite, Xcode static analysis, boundary check, `git diff --check`.
- Device: contract section 9 Apple Health comparison, logging from Home, rollover after midnight. Simulator evidence is not live HealthKit validation.

## Out of scope

Health screen and Export redesign (#200), new HealthKit types, trends, targets, net energy, background refresh.
