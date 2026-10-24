# UX revamp phase 4: Food Log and saved entry (#197) architecture gate

Status: **approved for implementation under the owner's overnight authority, 11 October 2026; implemented on `feat/197-food-log`.** Architecture gate passed with changes, folded in. Builds on phase 3 (`feat/196-add-food-search`, PR #207). Specification: [ux-revamp-v1.md](ux-revamp-v1.md). Wireframes: [`FoodLog`](designs/ux-revamp-v1/FoodLog.dc.html), [`EntryDetail`](designs/ux-revamp-v1/EntryDetail.dc.html). Carries the outstanding acceptance of #143 and #165.

**Presentation only.** No persisted format, schema, archive contract, confirmation policy version, `food-intake-summary-v2` behaviour, Daily JSON or egress change. Every write in this phase goes through services that already exist (`FoodConfirmationService.save` for edits, `FoodLogManagementService` for remove and restore), now reached through one application service. Anything that would need a contract is listed under Deferrals with the reason.

Pure, contract and view-model tests land first; screens follow. Owner decisions F1 to F8 (below) are approved before production code; F1 has a conservative default because the owner was not available at the gate.

## Responsibilities and files

| Layer | Owns in this phase | Files |
|---|---|---|
| Domain | No new type and no behaviour change. `FoodIntakeContribution` exposes the scaling predicate `FoodIntakeSummary` already uses (`isScalable`), so other code can ask without a second rule | `FoodIntakeSummary.swift` |
| Application | **`FoodLogReadingService`**: the Food Log orchestration (below). `FoodLogDayContent`: rows, totals, removed rows with removal times, per-entry estimate and unknown keys, built from `FoodIntakeProjection` and an explicit estimate set. `FoodEntryHistory`: structural history events from an entry's log versions and the conversion versions they reference. `SavedFoodEntryDetail`: read-only content from `StoredFoodConfirmation`, the row's totals and the history. `FoodLogDayNavigation`: previous, next, today and bounds over reporting-day keys. `FoodLogEditComparison`: one pure comparator shared by `FoodLogPolicy.editChanges(_:)` and the save path | new `FoodLogReadingService.swift`, `FoodLogDayContent.swift`, `FoodEntryHistory.swift`, `SavedFoodEntryDetail.swift`, `FoodLogDayNavigation.swift`, `FoodLogEditComparison.swift`; changed `FoodLogPolicy.swift`, `FoodConfirmation.swift` (save path calls the comparator; outputs unchanged), `FoodIntakeProjection.swift` (in-memory `FoodIntakeLogRow` gains the removing version's `createdAt`; nothing persisted) |
| Infrastructure | Nothing new. `ArchiveFoodLogHistoryReader` already reads versions from either store | none |
| Presentation | `FoodLogViewModel` behind the consumer-owned port `FoodLogStore`; `SavedFoodEntryViewModel`; totals, flags and history formatters; Confirm edit-mode wording and the single post-save exit | new `FoodLedgerPresentation/FoodLogViewModel.swift`, `SavedFoodEntryViewModel.swift`, `FoodLogTotalsText.swift`, `SavedFoodEntryText.swift`; changed `FoodConfirmationView.swift` |
| App and composition root | `FoodLogView` (replaces the `isHome: false` branch of `FoodIntakeHomeView`); `SavedFoodEntryView` (replaces `SavedFoodEntrySheet`); a `FoodLogStore` adapter that only forwards to `FoodLogReadingService`, built with the injected `confirmationClock` and calendar (not `SystemLedgerClock()`); the coordinator's focus day | `WeeklyHealthReport/Views/FoodLogView.swift`, `SavedFoodEntryView.swift`; `FoodIntakeHomeView.swift` (Home branch only); `FoodLedgerCompositionRoot.swift`; `AppShellView.swift`; the navigation coordinator |

New `FoodLedgerPresentation` files follow the target's convention of not importing Foundation explicitly (SwiftUI and the package modules suffice). The boundary script already allows the imports needed and does not change.

### `FoodLogReadingService` (application)

Takes `FoodLedgerService`, `any FoodLogHistoryReading`, the `FoodConfirmationService` (reopen, estimate status, `lastEnteredAmount`), `any LedgerClock` and `any LedgerIDGenerating`.

- `day(reportingDate:)` returns `FoodLogDayContent`, computing the estimate set and passing it in explicitly.
- `savedEntry(_:)` returns `SavedFoodEntryDetail?` (nil when missing).
- `remove(_:expected:)` and `restore(_:expected:)` call `FoodLogManagementService` with the fixed reason strings "Removed by user from Food Log" and "Restored by user from Food Log", the same strings whether the action starts in the Food Log or the saved entry. The existing service already selects `removeLogItemV2` / `restoreLogItemV2` for weight-declared entries; contract tests pin it. `staleVersion` and `conflictingVersions` map to one typed outcome, `FoodLogChangeOutcome.changedElsewhere`, so presentation shows "Entry unchanged" and reloads; any other error maps to `.notSaved`.
- No formatting and no view state. Tested in `FoodLedgerContractTests` against the memory and GRDB stores.

The composition root's `changeLogEntry`, `estimateLogItemIDs` and `intakeProjection` move behind this service; Home keeps calling `intakeProjection` until #199.

### `FoodLogStore` (presentation, consumer-owned)

```swift
protocol FoodLogStore {
    func day(_ reportingDate: String) async throws -> FoodLogDayContent
    func savedEntry(_ id: LogItemID) async throws -> SavedFoodEntryDetail?
    func remove(_ id: LogItemID, expected: LogItemVersionID) async throws -> FoodLogChangeOutcome
    func restore(_ id: LogItemID, expected: LogItemVersionID) async throws -> FoodLogChangeOutcome
}
```

The port is async so the loading state is real and reads can leave the main actor later without changing the view model; the first adapter may forward synchronously. Reopening for edit stays on the existing `model(reopening:)`, passed to `SavedFoodEntryViewModel` as a closure. An in-memory fake backs the view-model tests.

Dependency direction: Presentation → Application → Domain; the composition root wires the GRDB store into `FoodLogReadingService` and the service into the `FoodLogStore` adapter. Views format application values; they never scale nutrients, decide estimate status, derive reporting days, diff versions or pick reason strings.

## Invariants protected

- **Append-only versions.** Edit writes a new log version through confirmation v5 (a product version only when identity is corrected); remove and restore write `removeLogItem(V2)` / `restoreLogItem(V2)` versions with the fixed reason strings. Nothing is deleted or rewritten; history and evidence survive.
- **Day rules.** Food Log shows the stored `reportingDate` of each current head, as today. Day keys come only from `FoodReportingDay.key(for:calendar:)` with the injected confirmation calendar, so Food Log and Confirm agree on "today". An edit that changes the time re-derives the day through the existing service rule (an unchanged instant keeps the stored day). Food Log is a food-ledger projection, separate from completed-day Health averages, the Daily JSON selected-day rule and Home's today-so-far values.
- **Unknown is never zero; empty is not zero.** Totals use `FoodIntakeSummary` unchanged: a known subtotal with at least one unknown or unscalable contribution is a known minimum ("+"); no known contribution is "Unknown"; an empty day has no totals at all.
- **One scaling rule.** The saved entry decides whether nutrition can be shown for the amount only through `FoodIntakeContribution.isScalable`, the predicate the summary already applies.
- **Exports.** Editing, removing or restoring a past entry never changes or implies a change to an already exported snapshot; copy says so where the action happens.
- **No interpretation.** No targets, goals, ranges, colours meaning good or bad, or medical wording.
- **No egress.** No screen in this phase calls a provider or the network. Opening a saved entry re-verifies retained evidence locally only (reviewed web manifests are rehashed, never refetched).

## Screens and states

### Food Log (restyled, wireframe `FoodLog`)

| Block | Content | Today's code | Change |
|---|---|---|---|
| Navigation | Back, title "Food Log" | same | none |
| Day | Previous day, date (opens the date picker), next day (disabled on today); "Return to today" when not today | Chevron buttons and an inline compact `DatePicker`; `Calendar.current` and `Date()` in the view | Logic moves to `FoodLogDayNavigation`; the date label reads "Sunday 11 October" and opens the picker |
| Totals strip | Energy, Protein, Carbohydrates, Fat; footnote "Known values only. "+" means at least one entry has this nutrient unknown." | Five cards: energy, protein, carbohydrates, fat, fibre, each with "known" and an "incomplete" caption | One compact row (stacked at accessibility sizes). **Amended 23 October 2026 (F10, #288):** fibre returns to the strip as a fifth column, "Fibre", after fat; in the saved entry it stays under "All nutrients". **Water stays out of the strip until #198** (F1). "+" replaces "known" and the caption |
| Add food | Prominent button | Section with an "Add food" link (phase 3) | Prominent button. **Amended 13 October 2026 (owner decision D, approved in the UX review on #140):** on a past day Add food carries that day, and Confirm and the quick-add sheet start When on it at the current clock time; the footnote reads "New foods start on this day at the current time. You can change When before logging." A day older than 7 days leaves When at Now, with "Entries can be logged up to 7 days back." List import stays Now (v5 section 10). **Amended 14 October 2026 (owner decision after a device check):** on a Food Log day older than the backdating window, Add food is not offered, because it would log for now; the section shows only "Entries can be logged up to 7 days back." (the day header's "Return to today" selects today), and the "New foods are logged for now." footnote is gone. Within the window and on today nothing changes, and quick add from Home is unaffected. Previously the footnote was "New foods are logged for now. To log on this day, set When on the confirm screen." |
| Entries | Time, name, amount line, flags, energy | Name, energy, "time · quantity", and a status line that can read "Estimate · UK CoFID · Source estimate" | One row per entry: time column, name, amount ("150 g"), flags line, energy right-aligned. Flags: "Estimate" once, then "<Nutrient> unknown" for unknown energy, protein, carbohydrates or fat (F3). When energy is unknown the energy slot reads "Energy unknown" as text and VoiceOver reads it; it is never blank. Source names move to the saved entry |
| Removing | Swipe to remove; footnote "Swipe an entry to remove it. Removed entries can be restored." | Swipe and context menu, `confirmationDialog` | Same mechanics; the context menu stays for keyboard and pointer users; copy aligned with the saved entry alert |
| Removed | Collapsed "Removed · 1 entry"; each row "Removed 11:02 · not in totals" and Restore | Always-expanded "Removed entries" section | Collapsed `DisclosureGroup`; removal time from the removing version's `createdAt`, now carried on the in-memory row; Restore with a 44 pt target |
| Past 7 days | not in the wireframe | "Past 7 days" list | Removed (F5); the date picker and day buttons cover it |

| State | Shown as |
|---|---|
| Loading | "Loading food log" progress row in place of the totals and entries; day controls stay usable |
| Empty day | No totals strip; "No food logged" with "An empty log does not mean no food was eaten."; Add food stays; Removed may still appear |
| Partial | Known values with "+", per-entry unknown flags; "Unknown" when no entry on the day has a known value |
| Past day | Same screen with the date, "Return to today" and the When footnote |
| Failed | "Food log unavailable" with the existing specific messages (competing versions, mixed meal, unreadable store) and "Try again"; never an empty or zero state |
| Remove or restore not applied | Alert "Entry unchanged": `.changedElsewhere` says the entry changed elsewhere and the log reloads; `.notSaved` says it could not be saved |

### Saved entry (new read-only screen, wireframe `EntryDetail`)

Pushed from a Food Log row (not a sheet), back button "Food Log", "Edit" in the navigation bar.

| Block | Content | Source of values |
|---|---|---|
| Header | Name; "150 g · today, 12:40" (entered amount and unit, then the edible amount when converted, for example "1 mug · 240 mL"); "Estimate" label with "Unknown details stay unknown" when the current version is an estimate | `SavedFoodEntryDetail` from `StoredFoodConfirmation`, `FoodConfirmationService.lastEnteredAmount`, `FoodEntryEstimateStatus` |
| Nutrition | Energy, protein, carbohydrates, fat for the amount; "All nutrients" disclosure with every key, "Unknown" for unknown and bounded values, "Estimated" beside augmented values | The row's own single-contribution `FoodIntakeSummary` totals, so the numbers equal what the Food Log adds up |
| Source | Source name and record description with basis ("UK CoFID reference · Chicken, breast, grilled without skin, meat only · per 100 g"); recorded decisions ("Skin · None eaten") | Resolution and source release; the v5 decision record when present |
| History | Newest first (see History events) | `FoodEntryHistory` |
| Remove | "Remove from log" (destructive) opens the alert "Remove this entry?" / "It leaves this day's totals. You can restore it from Removed in the Food Log." with Cancel and Remove | `FoodLogReadingService.remove` with the head version as the expected version |
| Footnote | "Edit keeps the original as history. Exports already sent are not changed." | static copy |

| State | Shown as (none is ever a blank screen) |
|---|---|
| Loading | Title "Saved entry", progress "Loading saved food" |
| Loaded | As above |
| Nutrition not calculable | Loaded; when `isScalable` is false the Nutrition block reads "Nutrition can't be calculated for this amount" with a reason chosen by structure: unit mismatch ("The source gives values per 100 g; this entry is in mL") or unknown basis ("The source does not say what amount its values are for"). No figures, no zero; Edit offered |
| Edit unavailable | Loaded read-only content stays; Edit shows "This entry can't be edited right now" with Retry when `model(reopening:)` fails (for example a retained source no longer verifies) |
| Missing | "Saved entry unavailable" with Retry and Back |
| Failed | "Could not open saved food" with "Your saved food is unchanged.", Retry and Back |

Edit pushes Confirm in edit mode. Removed entries are not opened (F6); their row offers Restore only.

### History events

`FoodEntryHistory` reads an entry's log versions and the `QuantityConversionVersion`s they reference, ordered by ordinal (newest first). Each step from a predecessor to its successor is classified **by structure only, never by parsing `correctionReason`**, in this order:

1. Composition becomes `.removed` → "Removed"; composition returns from `.removed` → "Restored".
2. The product version changed → "Food details corrected" (also listing any amount or time change made in the same save).
3. Only the effective resolution changed → "Nutrition updated" (re-resolution).
4. Otherwise time and quantity: "Time changed 12:40 to 13:10", "Amount changed 120 g to 150 g", or both. For a converted entry the from and to amounts are the conversions' source quantities ("1 mug to 2 mugs"), with the edible amount when it differs.

The first version is "Logged". Every event carries the version's `createdAt`.

### Confirm in edit mode and after Log (fixes from tap-throughs)

| Issue | Cause today | Change |
|---|---|---|
| After Log, the saved entry shows both Back and Done | `navigationBarBackButtonHidden` only while unsaved; the toolbar swaps Cancel for the completion title and the saved section adds a second button | After a successful save: back button hidden, toolbar action removed, and **one** exit in the Log bar's place carrying the host-supplied `completionTitle` ("Done" for Add food, edit and sheet-hosted Confirm; "Next line" for list import) |
| The edit button reads "Log … kcal" | `logButtonTitle` ignores `reopened` | Edit mode reads "Save changes", disabled with "No changes to save" while `FoodLogPolicy.editChanges` is false (F2); "Log 248 kcal" stays for new entries |
| Food Log rows repeat "Estimate" / "Source estimate" | `sourceStatus` joins the entry estimate flag, source names and the summary's `includesEstimates` | One flags line from `FoodLogDayContent`: "Estimate" at most once; source names and augmented-value detail only on the saved entry |

**Edit comparison.** `FoodLogEditComparison` is extracted from the reuse rules already in `FoodConfirmation.swift`: the `makeConversion` fields, a `.new` plate choice counting as a change, `occurredAt`, `calculatedEdibleQuantity()`, the weight declaration and any identity correction. Both `editChanges` and the save path call it, so "unchanged" means the same thing to the button and to the service. F2 is presentation gating only: the service does not refuse an unchanged save, and no new requirement kind is added.

After "Save changes", Done returns to the saved entry, which reloads and shows the new history row.

### Log closes Confirm with Undo (owner decision, 15 October 2026)

For a new single food, Log now saves and finishes the journey at once, to the destination Done used (the `FoodEntryFinish` rules above: the Food Log on the entry's day, Home, or Favourites; a host outside Add food pops itself). The destination then shows a non-modal banner at the bottom:

- **Text.** "Logged · 260 kcal" with the energy the Log button stated; "Logged" when that energy is not known; "Logged without nutrition" when logged without nutrition. With Save as favourite it reads "Logged and saved as favourite · 260 kcal" and adds "Undo removes the entry. The favourite stays." The quick-add sheet's Log button states an amount, so its banner reads "Logged · 250 mL".
- **Undo.** One 44 pt Undo button. For VoiceOver the banner is one element with an explicit label and explicit Undo and Dismiss actions (plus the escape gesture), so Undo is listed once. It calls `FoodLogStore.remove` once, the same path as the Food Log, so the entry gets one appended removed version with the existing reason "Removed by user from Food Log" (no new reason string, no stored-format or contract change) and moves to Removed, where Restore still works. The favourite is never removed. The banner then reads "Entry removed" with no further Undo; "changed elsewhere" and "not saved" outcomes say nothing was removed.
- **Lifetime.** Visible for 5 seconds, or 10 seconds at accessibility Dynamic Type sizes (review fix, 15 October 2026); with VoiceOver running it stays until dismissed or used. VoiceOver announces the logged banner and Undo's outcome (not the moment Undo is in progress), 0.7 seconds after it appears so the focus change from Confirm's pop does not cut it off. Undo is gone after the timeout, after dismissal and after any navigation away from the screen the journey returned to: the banner belongs to that screen (Home, the Food Log, Favourites and the search, web lookup and barcode hosts register through `foodLoggedBannerScreen`, which reports the screen leaving and re-entering the window), so anything pushed over it, through the navigation path or not (opening a saved entry, search results), dismisses it; a change of the navigation path dismisses it too. A sheet opened over the screen covers the banner and keeps VoiceOver inside the sheet, so it is not dismissed by a sheet. Reduce Motion replaces the slide with a fade. An applied Undo reloads the Food Log and Home's food card.
- **Hosts.** Typed search, web lookup, barcode, recent foods, Favourites' log-now routes, Home and Add food quick add (sheet and full Confirm). `FoodLedgerCompositionRoot.singleFoodConfirmation` builds these; `FoodConfirmationView.logTapped` holds the rule.
- **Unchanged.** List import keeps its saved state and "Next line". Edit of a saved entry keeps "Save changes" then Done (the optional "Changes saved" banner was not added: Done returns to the saved entry, whose history already shows the change, so a second confirmation adds nothing). A failed save stays on Confirm with the error and Try again, as before. If the entry saves but the favourite requested with it fails, Confirm also stays, showing "Logged. Favourite not saved" with Try again and Done, because closing would hide that failure.

## Routes and focus day

No new `AppRoute` case. A saved entry needs a `LogItemID`, and `AppRoute` is a raw-value enum whose stored names must not change; the saved entry and its edit are presentation state of `FoodLogView` (`navigationDestination(item:)`), like Search results and Web lookup in phase 3. The specification's Navigation section gains the general rule (below).

**Focus day (F4).** The navigation coordinator holds a non-persisted `foodLogFocusDay: String?` (a reporting-day key). When Confirm saves from Add food that was pushed from the Food Log (`[.foodLog, .addFood]`), Done pops back to `.foodLog` and sets the focus day to the saved entry's reporting date; the Food Log reads and clears it on appear, so a backdated entry is visible. When Add food was restored on its own (`[.addFood]`) or opened from Home, Done returns Home and no focus day is set.

**Add food day (decision D, 13 October 2026).** The coordinator also holds a non-persisted `addFoodDay` set by `openAddFood(fromFoodLogDay:)`, read through `addFoodEntryDay` only while Add food sits directly on the Food Log, and cleared when Add food closes or Done runs. `FoodEntryFinish.entryDay` carries it to search, web lookup, barcode, recent foods and the quick-add sheet (or Confirm for an ineligible favourite). **14 October 2026 (fix):** Favourites opened from Add food also receives Add food's finish, so creating a favourite through Food search, Barcode or Web lookup starts When on the Food Log day and Done finishes the Add food journey like the other routes. This also applies when Add food is on today: Done after creating a favourite there now finishes Add food instead of returning to Favourites (accepted as consistent with the other Add food routes). Favourites opened from Home or Settings still logs for now and returns to Favourites. The pure `FoodEntryWhenPrefill.resolve` turns it into the day at the current clock time (the Gregorian calendar resolves a non-existent wall time), Now for today, or Now with the backdating notice for a day older than the window (still reachable from a sheet or a stale Add food, although since 14 October 2026 the Food Log itself replaces Add food on such a day: `FoodLogViewModel.canAddFoodForSelectedDay` is false exactly when this rule gives `.beyondBackdatingWindow` for the injected clock and calendar). If midnight moves the window past a prefilled time before Log, `occurredAtTooEarly` is shown under When as well as in the Log bar.

| Stored destination | Restores to | Note |
|---|---|---|
| `foodLog` | `[.foodLog]`, today | Unchanged; neither the selected day nor the focus day is persisted (F7) |
| Saved entry or its edit open at suspension | `[.foodLog]` | Not restorable; an unsaved edit is discarded, nothing is written |
| `addFood` | `[.addFood]` | Unchanged from phase 3; Done after Log returns Home |

**Future days.** Navigation never moves past today's key. If a time-zone change leaves entries on a key later than today, the Food Log does not offer that day; the entries reappear when the local day reaches it, and Developer tools still list them. This keeps "next day" honest and is recorded as a known edge.

## Deviations recorded during implementation

- `FoodLogReadingService` also takes the archive (the day projection needs the records) and a `FoodConfirmationReading` (the saved entry needs the stored confirmation); the history reader alone cannot supply either.
- The app-level no-egress test drives the composition root through load, open, edit, remove and restore with a recording `URLProtocol`. The root has no transport injection seam, so the recorder sees shared-session traffic only; the service's dependencies are local stores by type.
- The archive round trip compares the canonical projection and the re-verified archive document, not raw record bytes, because import does not preserve array order.
- Count amounts read "1 unit" or "2 units": the serving name ("mug" in the wireframe) is not stored as a structured value.
- Home (#199 scope) changed only where it shared code: its rows now push the new saved entry instead of the old sheet, show "Estimate" at most once and "Energy unknown" instead of a blank. The Food Log branch of `FoodIntakeHomeView` moved to `FoodLogView`.
- Missing and failed saved entries keep their own navigation titles ("Saved entry unavailable", "Could not open saved food"), as before, so they stay distinct to VoiceOver and to the native tests.
- No XCUITest target exists, so the simulator journey (section 8 of the tests) is left to `journey-qa`; hosted native tests cover first open and reopen (#165), recovery states and the single post-save exit per host.

### Invariant review and journey QA fixes (PR #211)

- Estimates stay labelled. A row says "Estimate" (once) when the saved decisions say so or its own contribution includes estimated values (augmented nutrients or an estimated weight); Home rows follow the same rule. Strip totals whose known values include estimates carry "Includes estimates", and VoiceOver says so.
- Food Log totals abbreviate carbohydrates to "Carbs" in the four-column strip; VoiceOver keeps the full word.
- On the saved entry, "Estimated" appears only beside a value the source augmented; an estimated weight is stated once in the header.
- After midnight or a time-zone change the log follows the new today only when the day shown was today at the last load. The view model reads its calendar on every use, so an auto-updating calendar's time-zone change is seen.
- History names both days when a time change crosses days ("Time changed today, 12:40 to yesterday, 12:40") and records a plate-only or declaration-only change as "Weight details changed". A removal on a later day reads "Removed yesterday, 11:02".
- One time formatter (two-digit hour, as Confirm's picker shows it) serves the Food Log, history, removed rows and Home.
- Done after Log from any Add food route (typed search, web lookup, barcode, recent) finishes through the coordinator. The finish is passed explicitly from the Add food route to each nested host instead of through the environment, which did not reach destinations pushed from inside those hosts. Tests check that each host holds the finish and that leaving after a save finishes through the coordinator; the pushed navigation itself is rechecked by journey QA.
- The focus day is published and the Food Log consumes it on appear and on change, so it is selected whether the log reappears or is already showing.
- Entry rows stack at accessibility text sizes, use plain styling (primary names, grey secondary text) and a chevron; Add food on the Food Log is a full-width filled button.
- The single-exit test renders the real hosts (pushed Add food Confirm, the saved entry's edit host, the list-import host and a plain sheet) and checks the navigation bar: the Confirm title is on top, there is no back button and no bar item. Hosted SwiftUI text is not visible to UIKit, so the one remaining exit is checked through `FoodConfirmationView.exitTitles` and `ListConfirmationHost.toolbarTitles`, the lists those views render from.
- Remove in the Food Log (swipe or context menu) now writes the removal. The alert's dismissal cleared the pending entry before the Remove action's task ran, so nothing was removed; the alert now captures the entry when it appears (`presenting:`) and passes it to `confirmRemoval(_:)`. The saved entry's Remove reads its loaded detail, not alert state, so it was not affected; Home has no removal.
- Add food on the Food Log is a Button that appends the route through the coordinator, styled as a full-width filled button; a NavigationLink inside a Form ignored the button style.
- CoFID records every numeric value as augmented (a generic composition source), so a CoFID entry such as grilled chicken shows "Estimated" beside every known value; that is correct, not a repeat. A mixed fixture test shows measured values are not marked.
- The no-egress test now also reopens a reviewed web entry. Its guarantee comes from types and review (the service depends only on local stores); the test is a tripwire.

## Specification amendment

Add to the Navigation section of [ux-revamp-v1.md](ux-revamp-v1.md): "Destinations that need an identifier (a saved entry, a search result, a web lookup) are presentation state of the screen that owns them; they are not route values and restore to that screen."

## Tests

No contract changes, so the gate is pure, store-parity contract, view-model, render and app-level tests, plus the simulator suite. The gate's contract tests are items 2.1 to 2.8.

1. **Pure, application and domain**
   - `FoodLogDayContentTests`: totals for energy, protein, carbohydrates and fat; known minimum when one entry lacks a nutrient; "Unknown" when none has it; empty day has no totals and `itemCount == 0`; bounded counts as unknown; removed rows excluded from totals but listed with their removal time; per-entry unknown keys limited to the F3 set; energy unknown produces the "Energy unknown" flag; the estimate set is taken as given and "Estimate" appears at most once per row; order by `occurredAt` then log item ID; water never appears in the strip.
   - `FoodEntryHistoryTests`: logged; amount changed (gram entry); amount changed on a converted entry (source quantities from and to); time changed; amount and time together; identity correction plus a quantity change in one save gives one "Food details corrected" event listing the amount change; re-resolution gives "Nutrition updated"; removed; restored; removed then restored then edited; a fixture with a misleading `correctionReason` is still classified by structure.
   - `SavedFoodEntryDetailTests`: gram entry against per 100 g shows figures; an entry against per 100 g logged in mL and an entry with `.unknown` basis give different not-calculable states, with no figures and no zero; named serving; plate-weighed entry shows edible weight; estimate status true, false and unreadable (not labelled, per the existing rule); decisions from a v5 record and from a pre-v5 entry; nutrition equals the row's projection totals.
   - `FoodIntakeSummaryTests` additions: `isScalable` agrees with the summary for every basis and unit pair; a day with one mL-against-per-100 g entry and one unknown-basis entry marks every nutrient as a known minimum; `food-intake-summary-v2` outputs are unchanged on the existing fixtures.
   - `FoodLogDayNavigationTests`: keys only from `FoodReportingDay.key`; previous and next across month and year ends; next disabled on today; no key later than today is offered, including after a time-zone change that leaves entries ahead; `Europe/London` 29 March and 25 October 2026 and `Pacific/Auckland` 27 September 2026; a non-Gregorian display calendar (Buddhist and Japanese) yields the same keys.
   - `FoodLogEditComparisonTests` and `FoodLogPolicyContractTests` additions: `editChanges` false for an untouched reopen (gram, converted, plate, direct weight); true for amount, unit, time, a `.new` plate, a declaration change or a correction.
2. **Contract, memory and GRDB stores (`FoodLedgerContractTests`)**
   1. `FoodLogReadingService` day content is identical from both stores for the same records, and a day with only removed entries has no totals and lists its Removed rows.
   2. Remove then restore through the service writes versions with the fixed reason strings, from the Food Log and from the saved entry alike.
   3. A weight-declared entry is removed and restored with `removeLogItemV2` / `restoreLogItemV2`; an undeclared one with the v1 types.
   4. A head that moved between load and action returns `.changedElsewhere` for both `staleVersion` and `conflictingVersions`, and writes nothing.
   5. Edit parity: for each comparator case, an unchanged save and a changed save produce the same "changed" answer from `editChanges` and from the save path's reuse decisions.
   6. Edit moving the time to the previous day: the entry leaves the original day's `FoodLogDayContent` and appears on the new day; history keeps both versions.
   7. History events are identical from both stores, including a converted entry and a re-resolved entry.
   8. Archive export and import after edit, remove and restore re-encode byte for byte (extends `testBothStoresRetainHistoryThroughRemoveRestoreAndArchiveReplay`).
3. **View model (`FoodLedgerPresentation` tests with an in-memory `FoodLogStore`)**
   - `FoodLogViewModelTests`: loading then loaded; failure kinds map to their states; day change reloads once; next disabled on today; a focus day selects that day and is cleared; significant time change and scene activation reload; remove needs confirmation and calls the store once; a double tap removes once; `.changedElsewhere` shows "Entry unchanged" and reloads; restore moves the row back; empty day shows no totals.
   - `SavedFoodEntryViewModelTests`: first presentation and reopen both reach loaded (the #165 regression); missing, failed and Retry; edit unavailable keeps read-only content; Remove from log asks, removes and returns to the Food Log; after an edit the detail reloads with the new history row.
   - `FoodConfirmationViewModel` additions: `logButtonTitle` is "Save changes" when reopened and "Log 248 kcal" otherwise; edit disabled with "No changes to save" until changed; after save exactly one exit with the host's `completionTitle`.
   - Coordinator: Done after Log from `[.foodLog, .addFood]` pops to `.foodLog` with the entry's reporting day focused; from a restored `[.addFood]` it returns Home with no focus day.
4. **Formatter golden strings:** totals ("1,240", "68 g", "41 g+", "Unknown"), VoiceOver labels ("Fat, at least 41 grams", "Energy unknown"), history lines, flags ("Estimate", "Fat unknown"), both not-calculable reasons.
5. **Native render (`FoodSearchQuantityNativeTests` style):** Food Log populated with "+" and Unknown, empty day, past day, failed, removed collapsed and expanded; a row shows "Estimate" once and no source names; a row with unknown energy shows "Energy unknown"; saved entry for a gram entry, a volume entry against per 100 g, an unknown-basis entry, an estimate and an entry with history; Confirm after a save shows exactly one exit and no back button when hosted by Add food ("Done"), by edit ("Done"), by list import ("Next line") and as a sheet ("Done"); Confirm edit mode shows "Edit food" and "Save changes". Update the existing `WeeklyReportScreenshotTests` Food Log renders to the new view.
6. **App-level egress:** a composition root built with recording transports and stub provider and web clients sees zero requests across Food Log load, opening a saved entry (including a reviewed web entry), edit, remove and restore. This replaces a package-level transport test, because the composition root is where an accidental call would be wired.
7. **Navigation:** `AppNavigationTests` asserts `foodLog` still restores to `[.foodLog]`, `addFood` to `[.addFood]`, and the legacy raw-value list is unchanged (no case added or renamed).
8. **Simulator UI:** Food Log → entry → Edit → Save changes → entry shows "Amount changed"; swipe remove → Removed → Restore, totals change both ways; Remove from log alert Cancel and Remove; previous day and date picker; Add food from the Food Log, backdate to yesterday, Done lands on yesterday; first open and reopen of the same entry never blank; Dynamic Type at accessibility sizes; VoiceOver order (day, totals, Add food, entries, Removed); keyboard: context-menu remove and Return on Restore.
9. **Gates:** the AGENTS.md set; `Tools/NutritionEvaluationSpike` still compiles; device check of edit, remove, restore and first open (#165).

## README updates

- Replace the Food Log sentence ("Food Log supports a selected reporting date, source-aware totals, saved-entry review and existing food capture routes") with: day navigation and date picker; a totals strip for energy, protein, carbohydrates and fat where "+" marks a known minimum and an empty day shows no totals; entries by time with estimate and unknown flags; swipe to remove with a collapsed Removed section and Restore; a read-only saved entry with nutrition, source and history, Edit (a new version) and Remove from log.
- State that edits, removal and restoration never change an export already sent.
- Leave the Home paragraph ("Manage food intake") for #199.

## Owner decisions

| ID | Question | Recommended or default |
|---|---|---|
| F1 | Water in the totals strip | **Open; default applied: water stays out of the strip** until #198 settles what "Water" means (plain water logged versus the dietary water total; draft PR #209, Q8). No format change either way |
| F2 | "Save changes" when nothing changed | Disabled with "No changes to save", as presentation gating only; the service still accepts an unchanged save and no requirement kind is added |
| F3 | Which nutrients get per-entry "unknown" flags | Energy, protein, carbohydrates and fat; others appear only in the saved entry. Unknown energy shows "Energy unknown" in the energy slot, never a blank |
| F4 | Where Done goes after Log from Add food | As specified under Focus day: back to the Food Log on the entry's day when Add food was opened there; Home otherwise. **13 October 2026:** the owner approved decision D, so Add food opened on a past day also prefills When with that day (see the Add food row) |
| F5 | The "Past 7 days" list | Remove it; the date picker covers it. `FoodIntakeDayPreview` stays until Home (#199) decides |
| F6 | Opening a removed entry | Not openable in this phase; Restore only |
| F7 | Persist the selected day across launches | No; Food Log restores to today |
| F8 | Saved entry as push or sheet | Push, per the wireframe; the sheet and its blank-sheet risk go away |
| F9 | What Log does for a new single food | **15 October 2026, owner decision:** Log saves and closes Confirm to the Done destination, then shows "Logged · …" with Undo for 5 seconds, 10 at accessibility text sizes (see "Log closes Confirm with Undo"). List import and Edit are unchanged |
| F11 | Strip energy unit and the "+" footnote (#308) | **24 October 2026, owner-approved backlog:** the strip's energy figure carries "kcal" like every other figure ("1,240 kcal", "1,240 kcal+"), and the footnote "Known values only. "+" means at least one entry has this nutrient unknown." shows only when a figure, plain water included, actually shows "+", matching Home's conditional footnote. Presentation only |
| F10 | Fibre in the totals strip (#288) | **23 October 2026, owner decision:** the strip gains a "Fibre" column after fat, with the same "+" known-minimum mark, "Unknown" when no entry has fibre (never 0 g), "Includes estimates" caption and VoiceOver wording ("Fibre, at least 18 grams") as the other totals. Per-entry unknown flags stay as F3 (energy, protein, carbohydrates, fat), and the saved entry's main nutrition rows are unchanged, so fibre stays under "All nutrients" there. `FoodLogDayContent.stripKeys` gains `fiber`; the F3 set is its own list (`entryFlagKeys`). Presentation only; `food-intake-summary-v3` is unchanged |

## Deferrals

| Item | Reason |
|---|---|
| Water in the Food Log totals | #198 and draft PR #209 Q8 decide whether the label means plain water logged or the dietary water total; showing it earlier would teach the wrong meaning |
| Removing an entry for good | Records are append-only; a hard delete needs a contract and changes archive semantics |
| Changing the food (identity or source) from the saved entry beyond today's correction sheet | Re-resolution has strict identity rules (#198 and confirmation reuse rules); a new route needs its own contract |
| Food-log entries in the Daily JSON export | #97 owns it; this phase changes no export |
| Other nutrients in the strip (fibre was added by F10, #288), nutrient focus views | #145 |
| Mixed meals and recipe components in totals | `unsupportedMixture` stays a failure state until a component contract exists |
| A restorable saved-entry route with an identifier | `AppRoute` is a raw-value enum; associated values would change the persisted navigation format |
| Offering a future day that holds entries after a time-zone change | Rare; needs its own day-navigation rule rather than relaxing "never past today" |
| Totals across several days or trends | #147 |

## Risks

- **Blank saved entry (#165):** the detail loads read-only content separately from the edit model, so a re-verification failure leaves content and a reason instead of an empty view; first presentation and reopen are tested and retested on a device.
- **Totals that disagree:** the saved entry's nutrition comes from the same single-contribution summary and the same `isScalable` predicate as the Food Log, never a second scaling path.
- **Edit drift:** one comparator serves the button and the save path; the parity contract test fails if they diverge.
- **History mislabelling:** classification is structural; free-text reasons are never parsed.
- **Stale actions:** remove and restore pass the displayed head version; a concurrent edit yields "Entry unchanged" and a reload, never a silent overwrite.
- **Midnight and time zones:** keys come only from `FoodReportingDay.key` with the injected calendar and clock; the Food Log reloads on significant time change.
- **Home regression:** `FoodIntakeHomeView` keeps only its Home branch; its render tests stay green until #199 replaces it.
- **Accessibility:** totals stack at accessibility sizes; "+" is spoken as "at least"; rows, Restore and day buttons keep 44 pt targets; flags are text, never colour alone.
