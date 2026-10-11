# UX revamp phase 4: Food Log and saved entry (#197) architecture gate

Status: **draft for owner review, 11 October 2026.** Builds on phase 3 (`feat/196-add-food-search`, PR #207). Specification: [ux-revamp-v1.md](ux-revamp-v1.md). Wireframes: [`FoodLog`](designs/ux-revamp-v1/FoodLog.dc.html), [`EntryDetail`](designs/ux-revamp-v1/EntryDetail.dc.html). Carries the outstanding acceptance of #143 and #165.

**Presentation only.** No persisted format, schema, archive contract, confirmation policy version, Daily JSON or egress change. Every write in this phase goes through services that already exist (`FoodConfirmationService.save` for edits, `FoodLogManagementService` for remove and restore). Anything that would need a contract is listed under Deferrals with the reason.

Pure and view-model tests land first; screens follow. Owner decisions F1 to F8 (below, all marked recommended) are approved before production code.

## Responsibilities and files

| Layer | Owns in this phase | Files |
|---|---|---|
| Domain | Nothing new. `FoodIntakeSummary`, `FoodIntakeTotal` and `LogItemVersion` are read as they are | none |
| Application | `FoodLogDayContent` (rows, totals, removed rows, per-entry estimate and unknown keys, from `FoodIntakeProjection`); `FoodEntryHistory` (pure events from a log item's versions); `SavedFoodEntryDetail` (structured read-only content from `StoredFoodConfirmation`, the row's totals and the history); `FoodLogDayNavigation` (previous, next, today, bounds, with injected calendar); `FoodLogPolicy.editChanges(_:)` (whether an edit differs from the stored version, reusing the facts `editReason` already compares) | new `FoodLogDayContent.swift`, new `FoodEntryHistory.swift`, new `SavedFoodEntryDetail.swift`; `FoodLogPolicy.swift` |
| Infrastructure | Nothing new. `ArchiveFoodLogHistoryReader` already reads versions from either store | none |
| Presentation | `FoodLogViewModel` behind a small consumer-owned port `FoodLogStore`; Food Log screen; saved entry screen and `SavedFoodEntryViewModel`; totals and history formatters; Confirm edit-mode wording and the single post-save Done | new `FoodLedgerPresentation/FoodLogViewModel.swift`, `FoodLogTotalsText.swift`, `SavedFoodEntryText.swift`; `FoodConfirmationView.swift` |
| App | `FoodLogView` (new, replaces the `isHome: false` branch of `FoodIntakeHomeView`); `SavedFoodEntryView` (replaces `SavedFoodEntrySheet`); `FoodLogStore` adapter on the composition root, using the confirmation clock and calendar | `WeeklyHealthReport/Views/FoodLogView.swift`, `SavedFoodEntryView.swift`; `FoodIntakeHomeView.swift` (Home branch only, unchanged otherwise); `FoodLedgerCompositionRoot.swift`; `AppShellView.swift` |

Dependency direction: Presentation → Application → Domain; the composition root adapts the GRDB store and services to `FoodLogStore`. Views format application values; they never scale nutrients, decide estimate status, derive reporting days or diff versions. `FoodLogStore` lives in `FoodLedgerPresentation` (consumer-owned), carries only application and domain types, and has an in-memory fake for view-model tests. The FoodLedgerKit import-boundary check covers the new files; no new target.

```swift
// FoodLedgerPresentation, consumer-owned
protocol FoodLogStore {
    func day(_ reportingDate: String) throws -> FoodLogDayContent
    func savedEntry(_ id: LogItemID) throws -> SavedFoodEntryDetail?
    func remove(_ id: LogItemID, expected: LogItemVersionID) throws
    func restore(_ id: LogItemID, expected: LogItemVersionID) throws
}
```

Reopening for edit stays on the existing `model(reopening:)`; the view model receives it as a closure, as `SavedFoodEntrySession` does today.

## Invariants protected

- **Append-only versions.** Edit writes a new log version through confirmation v5 (a product version only when identity is corrected); remove and restore write `removeLogItem(V2)` / `restoreLogItem(V2)` versions with the existing reason strings ("Removed by user from Food Log", "Restored by user from Food Log"). Nothing is deleted or rewritten; history and evidence survive.
- **Day rules.** Food Log shows the stored `reportingDate` of each current head, as today. An edit that changes the time re-derives the day through the existing service rule (unchanged instant keeps the stored day). Food Log is a food-ledger projection, separate from completed-day Health averages, the Daily JSON selected-day rule and Home's today-so-far values. Day navigation uses the injected confirmation calendar, so Food Log and Confirm agree on "today".
- **Unknown is never zero; empty is not zero.** Totals use `FoodIntakeSummary` unchanged: a known subtotal with at least one unknown contribution is a known minimum ("+"); no known contribution is "Unknown"; an empty day has no totals at all.
- **Exports.** Editing, removing or restoring a past entry never changes or implies a change to an already exported snapshot; copy says so where the action happens.
- **No interpretation.** No targets, goals, ranges, colours meaning good or bad, or medical wording.
- **No egress.** No screen in this phase calls a provider or the network. Opening a saved entry re-verifies retained evidence locally only (reviewed web manifests are rehashed, never refetched).

## Screens and states

### Food Log (restyled, wireframe `FoodLog`)

| Block | Content | Today's code | Change |
|---|---|---|---|
| Navigation | Back, title "Food Log" | same | none |
| Day | Previous day, date (opens the date picker), next day (disabled on today); "Return to today" when not today | Chevron buttons and an inline compact `DatePicker`; `Calendar.current` and `Date()` in the view | Logic moves to `FoodLogDayNavigation` with the injected calendar and clock; the date label reads "Sunday 11 October" and opens the picker |
| Totals strip | Energy, Protein, Carbohydrates, Fat, Water; footnote "Known values only. "+" means at least one entry has this nutrient unknown." | Five cards: energy, protein, carbohydrates, fat, fibre, each with "known" and an "incomplete" caption | One compact five-column row (stacked at accessibility sizes); fibre leaves the strip (it stays in each entry's "All nutrients"); "+" replaces "known" and the caption |
| Add food | Prominent button | Section with an "Add food" link (phase 3) | Prominent button; on a past day the footnote "New foods are logged for now. To log on this day, set When on the confirm screen." stays |
| Entries | Time, name, amount line, flags, energy | Name, energy, "time · quantity", and a status line that can read "Estimate · UK CoFID · Source estimate" | One row per entry: time column, name, amount ("150 g"), flags line, energy right-aligned. Flags: "Estimate" once, then "<Nutrient> unknown" for unknown strip nutrients (F3). Source names move to the saved entry |
| Removing | Swipe to remove; footnote "Swipe an entry to remove it. Removed entries can be restored." | Swipe and context menu, `confirmationDialog` | Same mechanics; the context menu stays for keyboard and pointer users; copy aligned with the saved entry alert |
| Removed | Collapsed "Removed · 1 entry"; each row "Removed 11:02 · not in totals" and Restore | Always-expanded "Removed entries" section | Collapsed `DisclosureGroup`; removal time from the removing version's `createdAt`; Restore with a 44 pt target |
| Past 7 days | not in the wireframe | "Past 7 days" list | Removed (F5); the date picker and day buttons cover it |

| State | Shown as |
|---|---|
| Loading | "Loading food log" progress row in place of the totals and entries; day controls stay usable |
| Empty day | No totals strip; "No food logged" with "An empty log does not mean no food was eaten."; Add food stays; Removed may still appear |
| Partial | Known values with "+", per-entry unknown flags; "Unknown" when no entry on the day has the nutrient |
| Past day | Same screen with the date, "Return to today" and the When footnote |
| Failed | "Food log unavailable" with the existing specific messages (competing versions, mixed meal, unreadable store) and "Try again"; never an empty or zero state |
| Remove or restore failed | Alert "Entry unchanged" with the reason class (changed elsewhere, so the log reloads; or could not be saved) and the log reloads |

### Saved entry (new read-only screen, wireframe `EntryDetail`)

Pushed from a Food Log row (not a sheet), back button "Food Log", "Edit" in the navigation bar.

| Block | Content | Source of values |
|---|---|---|
| Header | Name; "150 g · today, 12:40" (entered amount and unit, then the edible amount when converted, for example "1 mug · 240 mL"); "Estimate" label with "Unknown details stay unknown" when the current version is an estimate | `SavedFoodEntryDetail` from `StoredFoodConfirmation`, `FoodConfirmationService.lastEnteredAmount`, `FoodEntryEstimateStatus` |
| Nutrition | Energy, protein, carbohydrates, fat for the amount; "All nutrients" disclosure with every key, "Unknown" for unknown and bounded values, "Estimated" beside augmented values | The row's own `FoodIntakeSummary` totals, so the numbers equal what the Food Log adds up |
| Source | Source name and record description with basis ("UK CoFID reference · Chicken, breast, grilled without skin, meat only · per 100 g"); recorded decisions ("Skin · None eaten") | Resolution and source release; the v5 decision record when present |
| History | Newest first: "Logged", "Amount changed 120 g to 150 g", "Time changed", "Food details corrected", "Removed", "Restored", each with its time | `FoodEntryHistory` from `FoodLogHistoryReading.versions(for:)` |
| Remove | "Remove from log" (destructive) opens the alert "Remove this entry?" / "It leaves this day's totals. You can restore it from Removed in the Food Log." with Cancel and Remove | `FoodLogManagementService.remove` with the head version as the expected version |
| Footnote | "Edit keeps the original as history. Exports already sent are not changed." | static copy |

| State | Shown as (none is ever a blank screen) |
|---|---|
| Loading | Title "Saved entry", progress "Loading saved food" |
| Loaded | As above |
| Unsupported conversion | Loaded, with the Nutrition block reading "Nutrition can't be calculated for this amount" and a plain reason ("The source gives values per 100 g; this entry is in mL"); no figures, no zero; Edit offered |
| Edit unavailable | Loaded read-only content stays; Edit shows "This entry can't be edited right now" with Retry when `model(reopening:)` fails (for example a retained source no longer verifies) |
| Missing | "Saved entry unavailable" with Retry and Back |
| Failed | "Could not open saved food" with "Your saved food is unchanged.", Retry and Back |

Edit pushes Confirm in edit mode. Removed entries are not opened (F6); their row offers Restore only.

### Confirm in edit mode and after Log (fixes from tap-throughs)

| Issue | Cause today | Change |
|---|---|---|
| After Log, the saved entry shows both Back and Done | `navigationBarBackButtonHidden` only while unsaved; the toolbar swaps Cancel for "Done" and the saved section adds a second Done | After a successful save: back button hidden, toolbar action removed, one prominent "Done" in the Log bar's place. Exactly one way out |
| The edit button reads "Log … kcal" | `logButtonTitle` ignores `reopened` | Edit mode reads "Save changes", disabled with "No changes to save" until `FoodLogPolicy.editChanges` reports a difference (F2); "Log 248 kcal" stays for new entries |
| Food Log rows repeat "Estimate" / "Source estimate" | `sourceStatus` joins the entry estimate flag, source names and the summary's `includesEstimates` | One flags line from `FoodLogDayContent`: "Estimate" at most once; source names and augmented-value detail only on the saved entry |

After "Save changes", Done returns to the saved entry, which reloads and shows the new history row. After Log from Add food opened from the Food Log, Done returns to the Food Log with the entry's reporting day selected (F4).

## Routes

No new `AppRoute` case. A saved entry needs a `LogItemID`, and `AppRoute` is a raw-value enum whose stored names must not change; the saved entry and its edit are presentation state of `FoodLogView` (`navigationDestination(item:)`), like Search results and Web lookup in phase 3.

| Stored destination | Restores to | Note |
|---|---|---|
| `foodLog` | `[.foodLog]`, today | Unchanged; the selected day is not persisted (F7) |
| Saved entry or its edit open at suspension | `[.foodLog]` | Not restorable; an unsaved edit is discarded, nothing is written |
| `addFood` opened from the Food Log | `[.addFood]` | Unchanged from phase 3 |

`AppNavigationTests` gains a case asserting `foodLog` still restores to `[.foodLog]` and that no route value was added or renamed (the legacy raw-value list stays exact).

## Tests

No contract changes, so the gate is pure, store-parity, view-model and render tests, plus the simulator suite.

1. **Pure, application (`FoodLedgerApplicationTests`)**
   - `FoodLogDayContentTests`: totals for energy, protein, carbohydrates, fat and water; "known minimum" when one entry lacks a nutrient; "unknown" when none has it; empty day has no totals and `itemCount == 0`; bounded counts as unknown; removed rows excluded from totals but listed; per-entry unknown keys limited to the F3 set; estimate flag at most once per row; order by `occurredAt` then log item ID.
   - `FoodEntryHistoryTests`: logged; amount changed (value and unit from and to, including a converted entry); time changed; amount and time together; identity correction; removed; restored; removed then restored then edited; newest first; ties by ordinal; a superseded branch is not invented.
   - `SavedFoodEntryDetailTests`: gram entry against per 100 g; mL entry against per 100 g yields `unsupportedConversion`, never zero; named serving; plate-weighed entry shows edible weight; estimate status true, false and unreadable (not labelled, per the existing rule); decisions from a v5 record and from a pre-v5 entry without one; nutrition equals the row's projection totals.
   - `FoodLogDayNavigationTests`: previous and next across month and year ends; next disabled on today; future dates refused; `Europe/London` 29 March and 25 October 2026 and `Pacific/Auckland` 27 September 2026 day starts; selected day survives a time-zone change by reporting-date key.
   - `FoodLogPolicyContractTests` additions: `editChanges` false for an untouched reopen (gram, converted, plate, direct weight); true for amount, unit, time, plate or correction changes.
2. **Store parity (`FoodLedgerContractTests`, memory and GRDB)**
   - `FoodLogManagementContractTests`: remove from the saved entry then restore, with `staleVersion` when the head moved between load and action; history events identical from both stores; edit after restore supersedes the restored head.
   - Edit moving the time to the previous day: the entry leaves the original day's `FoodLogDayContent` and appears on the new day; history keeps both versions.
   - Archive export and import after edit, remove and restore re-encode byte for byte (extends `testBothStoresRetainHistoryThroughRemoveRestoreAndArchiveReplay`).
   - No egress: a recording transport fake sees zero requests across load, open, edit, remove and restore, including a reviewed web entry.
3. **View model (`FoodLedgerPresentation` tests with an in-memory `FoodLogStore`)**
   - `FoodLogViewModelTests`: loading then loaded; failure kinds map to their states; day change reloads once; next disabled on today; significant time change and scene activation reload; remove needs confirmation and calls the store once; a double tap removes once; stale version shows "Entry unchanged" and reloads; restore moves the row back; empty day shows no totals.
   - `SavedFoodEntryViewModelTests`: first presentation and reopen both reach loaded (the #165 regression); missing, failed and Retry; edit unavailable keeps read-only content; Remove from log asks, removes and returns to the Food Log; after an edit the detail reloads with the new history row.
   - `FoodConfirmationViewModel` additions: `logButtonTitle` is "Save changes" when reopened and "Log 248 kcal" otherwise; edit disabled with "No changes to save" until changed; after save exactly one completion action.
4. **Formatter golden strings:** totals ("1,240", "68 g", "41 g+", "Unknown", "750 mL", "1.25 L"), VoiceOver labels ("Fat, at least 41 grams"), history lines, flags ("Estimate", "Fat unknown", "Salt unknown"), unsupported-conversion reason.
5. **Native render (`FoodSearchQuantityNativeTests` style):** Food Log populated with "+" and Unknown, empty day, past day, failed, removed collapsed and expanded; a row shows "Estimate" once and no source names; saved entry for a gram entry, a volume entry with unsupported conversion, an estimate and an entry with history; Confirm edit mode shows "Edit food" and "Save changes"; Confirm after Log shows one Done and no back button. Update the existing `WeeklyReportScreenshotTests` Food Log renders to the new view.
6. **Simulator UI:** Food Log → entry → Edit → Save changes → entry shows "Amount changed"; swipe remove → Removed → Restore, totals change both ways; Remove from log alert Cancel and Remove; previous day and date picker; Add food from a past day then backdate; first open and reopen of the same entry never blank; Dynamic Type at accessibility sizes; VoiceOver order (day, totals, Add food, entries, Removed); keyboard: context-menu remove and Return on Restore.
7. **Gates:** the AGENTS.md set; `Tools/NutritionEvaluationSpike` still compiles; device check of edit, remove, restore and first open (#165).

## README updates

- Replace the Food Log sentence ("Food Log supports a selected reporting date, source-aware totals, saved-entry review and existing food capture routes") with: day navigation and date picker; a totals strip for energy, protein, carbohydrates, fat and water where "+" marks a known minimum and an empty day shows no totals; entries by time with estimate and unknown flags; swipe to remove with a collapsed Removed section and Restore; a read-only saved entry with nutrition, source and history, Edit (a new version) and Remove from log.
- State that edits, removal and restoration never change an export already sent.
- Leave the Home paragraph ("Manage food intake") for #199.
- Add this plan to [docs/README.md](README.md) beside the earlier phase documents if they are indexed by then.

## Owner decisions (recommended answers)

| ID | Question | Recommended |
|---|---|---|
| F1 | Water in the totals strip before plain water exists (#198) | Show it from the same summary and rules; it counts water as each logged item's source states it, so the footnote says "Water counts what each source states." Plain water joins it in #198 without a format change |
| F2 | "Save changes" when nothing changed | Disabled with "No changes to save", so an untouched edit cannot write a version |
| F3 | Which nutrients get per-entry "unknown" flags | Energy, protein, carbohydrates and fat (the strip without water, which many sources omit); others appear only in the saved entry. Energy unknown also hides the row's kcal figure |
| F4 | Where Done goes after Log from Add food | Back to the screen that opened Add food; when that is the Food Log, select the entry's reporting day so a backdated entry is visible |
| F5 | The "Past 7 days" list | Remove it; the date picker covers it. `FoodIntakeDayPreview` stays until Home (#199) decides |
| F6 | Opening a removed entry | Not openable in this phase; Restore only. A read-only removed view can follow if asked for |
| F7 | Persist the selected day across launches | No; Food Log restores to today, avoiding a stale past day after midnight |
| F8 | Saved entry as push or sheet | Push, per the wireframe; the sheet and its blank-sheet risk go away |

## Deferrals

| Item | Reason |
|---|---|
| Removing an entry for good | Records are append-only; a hard delete needs a contract and changes archive semantics |
| Changing the food (identity or source) from the saved entry beyond today's correction sheet | Re-resolution has strict identity rules (#198 and confirmation reuse rules); a new route needs its own contract |
| Food-log entries in the Daily JSON export | #97 owns it; this phase changes no export |
| Fibre or other nutrients in the strip, nutrient focus views | #145 |
| Mixed meals and recipe components in totals | `unsupportedMixture` stays a failure state until a component contract exists |
| A restorable saved-entry route with an identifier | `AppRoute` is a raw-value enum; associated values would change the persisted navigation format |
| Totals across several days or trends | #147 |

## Risks

- **Blank saved entry (#165):** the detail loads read-only content separately from the edit model, so a re-verification failure leaves content and a reason instead of an empty view; first presentation and reopen are tested and retested on a device.
- **Totals that disagree:** the saved entry's nutrition comes from the same single-contribution summary as the Food Log, never a second scaling path.
- **Stale actions:** remove and restore pass the displayed head version; a concurrent edit yields "Entry unchanged" and a reload, never a silent overwrite.
- **Midnight and time zones:** "today", next-day bounds and Return to today use the injected calendar and clock and reload on significant time change.
- **Home regression:** `FoodIntakeHomeView` keeps only its Home branch; its render tests stay green until #199 replaces it.
- **Accessibility:** totals stack at accessibility sizes; "+" is spoken as "at least"; rows, Restore and day buttons keep 44 pt targets; flags are text, never colour alone.
