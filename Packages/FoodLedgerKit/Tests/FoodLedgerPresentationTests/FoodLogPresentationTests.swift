import Foundation
import FoodLedgerApplication
import FoodLedgerDomain
import FoodLedgerPresentation
import FoodLedgerTestSupport
import XCTest

/// Phase 4 (#197): Food Log and saved entry orchestration, Confirm edit mode and copy.
@MainActor
final class FoodLogPresentationTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London")!
        return calendar
    }
    private let locale = Locale(identifier: "en_GB")

    // MARK: Food Log view model

    func testLoadsTodayThenShowsEntriesAndKnownMinimum() async throws {
        let world = try World(now: now, calendar: calendar)
        _ = try world.save(grams: 150)
        let model = FoodLogViewModel(store: world.store, now: { [now] in now }, calendar: calendar)
        XCTAssertEqual(model.phase, .loading)
        XCTAssertTrue(model.isToday)
        XCTAssertFalse(model.canMoveForward)
        await model.load()
        guard case let .loaded(day) = model.phase else { return XCTFail("loaded") }
        XCTAssertEqual(day.entries.count, 1)
        let fat = try XCTUnwrap(day.totals?.first { $0.key == .fatTotal })
        XCTAssertEqual(FoodLogText.total(fat, locale: locale), "Unknown")
        let energy = try XCTUnwrap(day.totals?.first { $0.key == .energyConsumed })
        XCTAssertEqual(FoodLogText.total(energy, locale: locale), "300 kcal")
    }

    func testEmptyDayHasNoTotalsAndDayNavigationReloads() async throws {
        let world = try World(now: now, calendar: calendar)
        let model = FoodLogViewModel(store: world.store, now: { [now] in now }, calendar: calendar)
        await model.load()
        guard case let .loaded(day) = model.phase else { return XCTFail("loaded") }
        XCTAssertNil(day.totals)
        let calls = world.store.dayCalls
        await model.previousDay()
        XCTAssertEqual(world.store.dayCalls, calls + 1, "a day change reloads once")
        XCTAssertFalse(model.isToday)
        XCTAssertTrue(model.canMoveForward)
        await model.nextDay()
        XCTAssertTrue(model.isToday)
        await model.nextDay()
        XCTAssertTrue(model.isToday, "never past today")
        await model.choose(now.addingTimeInterval(5 * 86_400))
        XCTAssertTrue(model.isToday, "a future date is clamped to today")
    }

    func testFailuresMapToTheirStates() async {
        for (error, expected) in [(FoodIntakeProjectionError.competingVersions, FoodLogViewModel.Failure.competingVersions),
                                  (.unsupportedMixture, .mixedMeal), (.missingReference, .unreadable)] {
            let store = ScriptedStore(dayError: error)
            let model = FoodLogViewModel(store: store, now: { [now] in now }, calendar: calendar)
            await model.load()
            XCTAssertEqual(model.phase, .failed(expected))
        }
    }

    func testRemoveNeedsConfirmationRemovesOnceAndRestoreBringsItBack() async throws {
        let world = try World(now: now, calendar: calendar)
        _ = try world.save(grams: 150)
        let model = FoodLogViewModel(store: world.store, now: { [now] in now }, calendar: calendar)
        await model.load()
        guard case let .loaded(day) = model.phase, let entry = day.entries.first else { return XCTFail("entry") }
        model.requestRemoval(entry)
        XCTAssertEqual(world.store.removeCalls, 0, "nothing is removed before confirmation")
        async let first: Void = model.confirmRemoval(entry)
        async let second: Void = model.confirmRemoval(entry)
        _ = await (first, second)
        XCTAssertEqual(world.store.removeCalls, 1, "a double tap removes once")
        guard case let .loaded(after) = model.phase else { return XCTFail("loaded") }
        XCTAssertTrue(after.entries.isEmpty)
        XCTAssertNil(after.totals)
        XCTAssertEqual(after.removed.count, 1)
        await model.restore(try XCTUnwrap(after.removed.first))
        guard case let .loaded(restored) = model.phase else { return XCTFail("loaded") }
        XCTAssertEqual(restored.entries.count, 1)
        XCTAssertNil(model.changeAlert)
    }

    func testStaleRemovalShowsEntryUnchangedAndReloads() async throws {
        let world = try World(now: now, calendar: calendar)
        let saved = try world.save(grams: 150)
        let model = FoodLogViewModel(store: world.store, now: { [now] in now }, calendar: calendar)
        await model.load()
        guard case let .loaded(day) = model.phase, let entry = day.entries.first else { return XCTFail("entry") }
        let outcome = await world.store.remove(saved.logItem.logItemID, expected: saved.logItemVersion.logItemVersionID)
        XCTAssertEqual(outcome, .applied)
        model.requestRemoval(entry)
        await model.confirmRemoval(entry)
        XCTAssertEqual(model.changeAlert, .changedElsewhere)
        XCTAssertEqual(FoodLogText.changeAlert(.changedElsewhere), "This entry changed elsewhere. The log has been refreshed.")
        guard case let .loaded(reloaded) = model.phase else { return XCTFail("loaded") }
        XCTAssertEqual(reloaded.removed.count, 1)
    }

    func testFocusDaySelectsThatDay() async throws {
        let world = try World(now: now, calendar: calendar)
        let model = FoodLogViewModel(store: world.store, now: { [now] in now }, calendar: calendar)
        await model.showDay("2023-11-13")
        XCTAssertEqual(model.selectedKey, "2023-11-13")
        await model.showDay("2030-01-01")
        XCTAssertEqual(model.selectedKey, model.navigation.todayKey)
    }

    /// D9: the alert's dismissal clears the pending entry before the Remove task runs; the
    /// removal must still be written for the captured entry.
    func testRemovalIsWrittenWhenDismissalClearsThePendingEntryFirst() async throws {
        let world = try World(now: now, calendar: calendar)
        _ = try world.save(grams: 150)
        let model = FoodLogViewModel(store: world.store, now: { [now] in now }, calendar: calendar)
        await model.load()
        guard case let .loaded(day) = model.phase, let entry = day.entries.first else { return XCTFail("entry") }
        model.requestRemoval(entry)
        let captured = try XCTUnwrap(model.pendingRemoval, "presenting captures the entry")
        model.cancelRemoval()  // the isPresented binding setter, which SwiftUI calls before the action's task
        XCTAssertNil(model.pendingRemoval)
        await model.confirmRemoval(captured)
        XCTAssertEqual(world.store.removeCalls, 1)
        guard case let .loaded(after) = model.phase else { return XCTFail("loaded") }
        XCTAssertTrue(after.entries.isEmpty, "the removal was written")
        XCTAssertEqual(after.removed.map(\.logItemID), [entry.logItemID])
    }

    // MARK: Saved entry view model

    func testSavedEntryFirstPresentationAndReopenBothLoad() async throws {
        let world = try World(now: now, calendar: calendar)
        let saved = try world.save(grams: 150)
        for _ in 0..<2 {
            let model = SavedFoodEntryViewModel(logItemID: saved.logItem.logItemID, store: world.store) { try world.editModel(saved.logItem.logItemID) }
            XCTAssertEqual(model.phase, .loading)
            await model.load()
            XCTAssertEqual(model.phase, .loaded, "never blank")
            XCTAssertEqual(model.detail?.name, "Fixture food")
        }
    }

    func testSavedEntryMissingFailedRetryAndEditUnavailable() async throws {
        let missing = SavedFoodEntryViewModel(logItemID: try LedgerID("00000000-0000-0000-0000-000000000abc"),
                                              store: ScriptedStore()) { nil }
        await missing.load()
        XCTAssertEqual(missing.phase, .missing)

        let failing = ScriptedStore(entryError: CocoaError(.fileReadUnknown))
        let failed = SavedFoodEntryViewModel(logItemID: try LedgerID("00000000-0000-0000-0000-000000000abc"), store: failing) { nil }
        await failed.load()
        XCTAssertEqual(failed.phase, .failed)

        let world = try World(now: now, calendar: calendar)
        let saved = try world.save(grams: 150)
        let model = SavedFoodEntryViewModel(logItemID: saved.logItem.logItemID, store: world.store) { throw CocoaError(.fileReadUnknown) }
        await model.load()
        XCTAssertNil(model.beginEdit())
        XCTAssertTrue(model.editUnavailable)
        XCTAssertEqual(model.phase, .loaded, "read-only content stays")
    }

    /// #347: the pinned line beside a disabled Log says the same thing at every size for the same
    /// state. An unchanged reopened entry reads "No changes to save" at the default size and AX5;
    /// "Not ready to log" is only for a requirement that blocks Log. `canLog` is unchanged.
    func testPinnedLineMatchesTheBarAtEverySize() throws {
        let world = try World(now: now, calendar: calendar)
        let saved = try world.save(grams: 120)
        let edit = try XCTUnwrap(world.editModel(saved.logItem.logItemID))
        XCTAssertFalse(edit.canLog)
        XCTAssertEqual(edit.blockedReason, FoodConfirmationViewModel.noChangesReason)
        XCTAssertTrue(edit.isBlockedOnlyByNoChanges)
        for isAccessibilitySize in [false, true] {
            XCTAssertEqual(FoodConfirmationView.pinnedReason(isAccessibilitySize: isAccessibilitySize,
                                                             blockedOnlyByNoChanges: edit.isBlockedOnlyByNoChanges),
                           "No changes to save", "accessibility size \(isAccessibilitySize)")
        }
        edit.send(.setQuantity(150, .grams))
        XCTAssertTrue(edit.canLog)
        XCTAssertFalse(edit.isBlockedOnlyByNoChanges, "a changed entry is not blocked")

        let state = try world.newState(grams: 0)
        let blocked = FoodConfirmationViewModel(state: state, now: { [now] in now }, calendar: calendar) { _ in
            throw CocoaError(.fileWriteUnknown)
        }
        XCTAssertFalse(blocked.canLog)
        XCTAssertEqual(blocked.requirements, [.amountMissing])
        XCTAssertFalse(blocked.isBlockedOnlyByNoChanges)
        XCTAssertEqual(FoodConfirmationView.pinnedReason(isAccessibilitySize: false, blockedOnlyByNoChanges: blocked.isBlockedOnlyByNoChanges),
                       FoodConfirmationView.pinnedBlockedReason)
        XCTAssertEqual(FoodConfirmationView.pinnedReason(isAccessibilitySize: true, blockedOnlyByNoChanges: blocked.isBlockedOnlyByNoChanges),
                       "Not ready to log")
    }

    func testRemoveFromSavedEntryAndEditReloadsHistory() async throws {
        let world = try World(now: now, calendar: calendar)
        let saved = try world.save(grams: 120)
        let model = SavedFoodEntryViewModel(logItemID: saved.logItem.logItemID, store: world.store) { try world.editModel(saved.logItem.logItemID) }
        await model.load()
        let edit = try XCTUnwrap(model.beginEdit())
        XCTAssertEqual(edit.logButtonTitle, "Save changes")
        XCTAssertFalse(edit.canLog)
        XCTAssertEqual(edit.blockedReason, "No changes to save")
        edit.send(.setQuantity(150, .grams))
        XCTAssertTrue(edit.canLog)
        XCTAssertNil(edit.blockedReason)
        edit.log()
        XCTAssertNotNil(edit.savedResult)
        await model.finishEdit()
        XCTAssertEqual(model.detail?.history.count, 2)
        XCTAssertEqual(model.detail.map { FoodLogText.history($0.history[0].kind, now: now, calendar: calendar, locale: locale) },
                       "Amount changed 120 g to 150 g")

        await model.confirmRemoval()
        XCTAssertTrue(model.didRemove)
        XCTAssertEqual(world.store.removeCalls, 1)
    }

    /// Owner decision D: the Food Log's Add food carries a past day (never today) and its footnote
    /// says When starts there, or that the day is beyond the 7-day window.
    func testAddFoodCarriesAPastDayAndExplainsWhen() async throws {
        let world = try World(now: now, calendar: calendar)
        let model = FoodLogViewModel(store: world.store, now: { [now] in now }, calendar: calendar)
        XCTAssertNil(model.addFoodDayKey)
        XCTAssertNil(model.addFoodFootnote)
        await model.previousDay()
        XCTAssertEqual(model.addFoodDayKey, model.selectedKey)
        XCTAssertNotNil(model.addFoodWhen.occurredAt)
        XCTAssertEqual(model.addFoodFootnote, "New foods start on this day at the current time. You can change When before logging.")
        XCTAssertTrue(model.canAddFoodForSelectedDay)
        for _ in 0..<7 { await model.previousDay() }
        XCTAssertEqual(model.addFoodWhen, .beyondBackdatingWindow)
        XCTAssertFalse(model.canAddFoodForSelectedDay)
        XCTAssertNil(model.addFoodFootnote, "no 'logged for now' footnote: Add food is not offered")
        XCTAssertEqual(FoodLogText.whenNotice(.beyondBackdatingWindow), "Entries can be logged up to 7 days back.")
        XCTAssertNil(FoodLogText.whenNotice(.now))
        XCTAssertEqual(FoodLogText.listImportNote(entryDay: "2026-10-10"), "List items are logged for now.")
        XCTAssertNil(FoodLogText.listImportNote(entryDay: nil))
    }

    /// Owner decision, 14 October 2026: day 7 back still offers Add food, prefilled on that day;
    /// day 8 back replaces it with the window text, and Return to today selects today.
    func testAddFoodIsReplacedBeyondTheBackdatingWindow() async throws {
        let london = Self.zone("Europe/London")
        let clock = Clock(Self.instant("2026-10-14T08:42:17Z")) // 09:42:17 BST
        let world = try World(now: clock.now, calendar: london)
        let model = FoodLogViewModel(store: world.store, now: { clock.now }, calendar: london)
        XCTAssertTrue(model.canAddFoodForSelectedDay, "today")
        XCTAssertNil(model.addFoodFootnote)

        await model.showDay("2026-10-07")
        XCTAssertTrue(model.canAddFoodForSelectedDay, "day 7 back")
        XCTAssertEqual(model.addFoodDayKey, "2026-10-07")
        XCTAssertEqual(model.addFoodWhen, .day(Self.instant("2026-10-07T08:42:17Z")))
        XCTAssertEqual(model.addFoodFootnote, FoodLogText.pastDayFootnote)

        await model.showDay("2026-10-06")
        XCTAssertFalse(model.canAddFoodForSelectedDay, "day 8 back")
        XCTAssertNil(model.addFoodFootnote)
        XCTAssertEqual(FoodLogText.addFoodBeyondWindow, "Entries can be logged up to 7 days back.")
        await model.returnToToday()
        XCTAssertTrue(model.isToday)
        XCTAssertEqual(model.selectedKey, "2026-10-14")
        XCTAssertTrue(model.canAddFoodForSelectedDay)
    }

    /// The window follows the injected clock: a day that is 7 back at 23:59:59 is 8 back at local
    /// midnight, and at exactly midnight day 7 back starts on the window's first instant.
    func testAddFoodWindowBoundaryAtLocalMidnight() async throws {
        let london = Self.zone("Europe/London")
        let clock = Clock(Self.instant("2026-10-14T22:59:59Z")) // 23:59:59 BST on 14 October
        let world = try World(now: clock.now, calendar: london)
        let model = FoodLogViewModel(store: world.store, now: { clock.now }, calendar: london)
        await model.showDay("2026-10-07")
        XCTAssertTrue(model.canAddFoodForSelectedDay)
        clock.now = Self.instant("2026-10-14T23:00:00Z") // 00:00:00 BST on 15 October
        XCTAssertFalse(model.canAddFoodForSelectedDay, "now 8 days back")
        XCTAssertNil(model.addFoodFootnote)
        await model.showDay("2026-10-08")
        XCTAssertTrue(model.canAddFoodForSelectedDay)
        XCTAssertEqual(model.addFoodWhen, .day(Self.instant("2026-10-07T23:00:00Z")), "the window's first instant")
    }

    /// Across a clock change: New York leaves daylight saving on 1 November 2026, a 25-hour day.
    /// At 00:30 EST on 8 November that day is 7 back and still offered; 31 October is not.
    func testAddFoodWindowAcrossADaylightSavingChange() async throws {
        let newYork = Self.zone("America/New_York")
        let clock = Clock(Self.instant("2026-11-08T05:30:00Z")) // 00:30 EST
        let world = try World(now: clock.now, calendar: newYork)
        let model = FoodLogViewModel(store: world.store, now: { clock.now }, calendar: newYork)
        await model.showDay("2026-11-01")
        XCTAssertTrue(model.canAddFoodForSelectedDay)
        XCTAssertEqual(model.addFoodWhen, .day(Self.instant("2026-11-01T04:30:00Z")), "00:30 EDT on the change day")
        await model.showDay("2026-10-31")
        XCTAssertFalse(model.canAddFoodForSelectedDay)
        XCTAssertNil(model.addFoodFootnote)
    }

    private final class Clock: @unchecked Sendable {
        var now: Date
        init(_ now: Date) { self.now = now }
    }

    private static func zone(_ identifier: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: identifier)!
        return calendar
    }

    private static func instant(_ text: String) -> Date {
        ISO8601DateFormatter().date(from: text)!
    }

    func testNewEntryKeepsLogTitle() throws {
        let world = try World(now: now, calendar: calendar)
        let model = FoodConfirmationViewModel(state: try world.newState(grams: 150), now: { [now] in now }, calendar: calendar) { _ in
            throw CocoaError(.fileWriteUnknown)
        }
        XCTAssertEqual(model.logButtonTitle, "Log 300 kcal")
        XCTAssertTrue(model.hasChangesToSave)
    }

    /// The mL-on-a-per-100 g warning applies only while mL drives nutrition; a measured gram
    /// weight replaces it, so the "no nutrition" copy and button title are not shown then.
    func testVolumeWarningIsHiddenWhenMeasuredWeightDrivesNutrition() throws {
        let world = try World(now: now, calendar: calendar)
        let model = FoodConfirmationViewModel(state: try world.newState(grams: 150), now: { [now] in now }, calendar: calendar) { _ in
            throw CocoaError(.fileWriteUnknown)
        }
        model.send(.setQuantity(200, .millilitres))
        XCTAssertTrue(try XCTUnwrap(model.quantityBasisWarning).contains("has no nutrition"))
        XCTAssertEqual(model.logButtonTitle, "Log without nutrition")
        model.send(.beginDirectWeight)
        XCTAssertNil(model.quantityBasisWarning)
        XCTAssertNil(model.unitBasisMismatch)
        XCTAssertNotEqual(model.logButtonTitle, "Log without nutrition")
        XCTAssertEqual(FoodConfirmationView.evidenceCount(1), "1 saved item")
        XCTAssertEqual(FoodConfirmationView.evidenceCount(3), "3 saved items")
    }

    /// The Log button and Confirm's nutrition use the shared display format: whole kcal (half
    /// away from zero) and grams to one decimal, as the saved entry and Food Log show them.
    func testLogTitleAndConsumedNutritionUseSharedDisplayFormat() throws {
        let world = try World(now: now, calendar: calendar)
        let model = FoodConfirmationViewModel(state: try world.newState(grams: 129.75), now: { [now] in now }, calendar: calendar) { _ in
            throw CocoaError(.fileWriteUnknown)
        }
        XCTAssertEqual(model.logButtonTitle, "Log 260 kcal", "259.5 kcal rounds like the Food Log row")
        // A positive energy below half a kcal is never "Log 0 kcal".
        let tiny = FoodConfirmationViewModel(state: try world.newState(grams: 0.2), now: { [now] in now }, calendar: calendar) { _ in
            throw CocoaError(.fileWriteUnknown)
        }
        XCTAssertEqual(tiny.logButtonTitle, "Log less than 1 kcal", "0.4 kcal")
        XCTAssertEqual(tiny.nutritionReview.mainRows.first { $0.key == .energyConsumed }?.value, "Less than 1 kcal")
        for row in model.nutritionReview.mainRows where row.value != FoodNutritionReviewPresentation.unknownValue {
            let number = row.value.split(separator: " ").first.map(String.init) ?? ""
            let decimals = number.split(separator: ".").dropFirst().first?.count ?? 0
            XCTAssertLessThanOrEqual(decimals, row.key == .energyConsumed ? 0 : 1, row.value)
        }
    }

    // MARK: Review fixes (#211)

    /// Fix 3: after midnight or a time-zone change, a log showing "today" moves to the new
    /// today; a past day stays where it is.
    func testRefreshAfterMidnightAndTimeZoneChangeReanchorsOnlyWhenTodayWasShown() async throws {
        final class Box: @unchecked Sendable { var now: Date; init(_ now: Date) { self.now = now } }
        let world = try World(now: now, calendar: calendar)
        let beforeMidnight = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-10-11T23:50:00Z"))
        let clock = Box(beforeMidnight)
        let model = FoodLogViewModel(store: world.store, now: { clock.now }, calendar: calendar)
        await model.load()
        XCTAssertEqual(model.selectedKey, "2026-10-12", "23:50 UTC is 00:50 BST")
        clock.now = beforeMidnight.addingTimeInterval(24 * 3600)
        await model.refreshAfterTimeChange()
        XCTAssertEqual(model.selectedKey, "2026-10-13", "today was shown, so the log follows the new today")

        await model.previousDay()
        clock.now = clock.now.addingTimeInterval(24 * 3600)
        await model.refreshAfterTimeChange()
        XCTAssertEqual(model.selectedKey, "2026-10-12", "a past day stays selected")

        // A time-zone change: the same instant, a calendar that now reads Auckland time.
        final class CalendarBox: @unchecked Sendable { var calendar: Calendar; init(_ calendar: Calendar) { self.calendar = calendar } }
        let zone = CalendarBox(calendar)
        let instant = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-10-11T12:00:00Z"))
        let zoned = FoodLogViewModel(store: world.store, now: { instant }, calendarProvider: { zone.calendar })
        await zoned.load()
        XCTAssertEqual(zoned.selectedKey, "2026-10-11", "13:00 in London")
        zone.calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Pacific/Auckland"))
        await zoned.refreshAfterTimeChange()
        XCTAssertEqual(zoned.selectedKey, "2026-10-12", "01:00 on 12 October in Auckland: today moved, so the log follows")
    }

    /// Fix 1: a time change across days names both days.
    func testCrossDayTimeChangeNamesTheDays() throws {
        let today = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-10-11T11:40:00Z"))
        let yesterday = today.addingTimeInterval(-86_400)
        let sameDay = FoodLogText.history(.changed(amount: nil, time: .init(from: today.addingTimeInterval(-3600), to: today)),
                                          now: today, calendar: calendar, locale: locale)
        XCTAssertEqual(sameDay, "Time changed 11:40 to 12:40")
        let crossDay = FoodLogText.history(.changed(amount: nil, time: .init(from: today, to: yesterday)),
                                           now: today, calendar: calendar, locale: locale)
        XCTAssertEqual(crossDay, "Time changed today, 12:40 to yesterday, 12:40")
        XCTAssertEqual(FoodLogText.history(.weightDetailsChanged, now: today, calendar: calendar, locale: locale), "Weight details changed")
    }

    /// Fix 8: a removal on a later day says which day.
    func testRemovedLineUsesTheRelativeDayWhenNotTheSameDay() throws {
        let occurred = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-10-10T10:00:00Z"))
        func removed(after seconds: TimeInterval) throws -> FoodLogDayContent.RemovedEntry {
            .init(logItemID: try LedgerID("00000000-0000-0000-0000-000000000abc"),
                  logItemVersionID: try LedgerID("00000000-0000-0000-0000-000000000abd"), occurredAt: occurred,
                  name: "Fixture food", quantity: try PositiveQuantity(value: 150, unit: .grams),
                  removedAt: occurred.addingTimeInterval(seconds))
        }
        let today = occurred.addingTimeInterval(86_400 + 120)
        XCTAssertEqual(FoodLogText.removedLine(try removed(after: 3600), now: today, calendar: calendar, locale: locale),
                       "Removed 12:00 · not in totals")
        XCTAssertEqual(FoodLogText.removedLine(try removed(after: 86_400 + 60), now: today, calendar: calendar, locale: locale),
                       "Removed today, 11:01 · not in totals")
    }

    /// Fix 2: totals whose known values include estimates are labelled, on screen and spoken.
    func testEstimatedTotalsAreLabelled() {
        let estimated = FoodIntakeSummaryProbe.total(key: .protein, amount: 10, incomplete: 0, augmented: true)
        XCTAssertTrue(estimated.includesEstimates)
        XCTAssertEqual(FoodLogText.totalCaption(estimated), "Includes estimates")
        XCTAssertEqual(FoodLogText.totalAccessibility(estimated, locale: locale), "Protein, 10 grams, includes estimates")
        let measured = FoodIntakeSummaryProbe.total(key: .protein, amount: 10, incomplete: 0)
        XCTAssertNil(FoodLogText.totalCaption(measured))
        XCTAssertNil(FoodLogText.totalCaption(FoodIntakeSummaryProbe.total(key: .protein, amount: nil, incomplete: 1)))
    }

    /// Journey QA D5 to D7: one time format, a short strip label, and "Estimated" only beside augmented values.
    func testSharedTimeShortStripLabelAndAugmentedOnlyMarker() throws {
        let earlyMorning = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-10-10T23:18:00Z"))
        XCTAssertEqual(FoodLogText.time(earlyMorning, calendar: calendar, locale: locale), "00:18")
        XCTAssertEqual(FoodLogText.stripLabel(.carbohydrates), "Carbs")
        XCTAssertEqual(FoodLogText.label(.carbohydrates), "Carbohydrates")
        let estimated = FoodIntakeSummaryProbe.total(key: .protein, amount: 10, incomplete: 0, augmented: true)
        XCTAssertEqual(FoodLogText.nutrient(estimated, augmented: true, locale: locale), "10 g · Estimated")
        XCTAssertEqual(FoodLogText.nutrient(estimated, augmented: false, locale: locale), "10 g")
        let measuredEnergy = FoodIntakeSummaryProbe.total(key: .energyConsumed, amount: 200, incomplete: 0)
        XCTAssertEqual(FoodLogText.nutrient(measuredEnergy, augmented: false, locale: locale), "200 kcal")
    }

    /// Review fix 5: exactly one exit after a save, whatever the host.
    func testConfirmExitsBeforeAndAfterSave() {
        XCTAssertEqual(FoodConfirmationView.exitTitles(isSaved: false, showsCancelButton: true, completionTitle: "Done"), ["Cancel"])
        XCTAssertEqual(FoodConfirmationView.exitTitles(isSaved: false, showsCancelButton: false, completionTitle: "Done"), [])
        for title in ["Done", "Next line"] {
            for cancel in [true, false] {
                XCTAssertEqual(FoodConfirmationView.exitTitles(isSaved: true, showsCancelButton: cancel, completionTitle: title), [title])
            }
        }
        XCTAssertEqual(ListConfirmationHost.toolbarTitles(isSaved: false), ["Back to list"])
        XCTAssertEqual(ListConfirmationHost.toolbarTitles(isSaved: true), [])
    }

    // MARK: Copy

    /// #308: the "+" footnote only when a figure shows "+", as on Home.
    func testTotalsFootnoteOnlyWhenAFigureShowsPlus() {
        func total(_ key: NutrientKey, _ amount: Double?, incomplete: Int = 0) -> FoodIntakeTotal {
            FoodIntakeSummaryProbe.total(key: key, amount: amount, incomplete: incomplete)
        }
        let complete = [total(.energyConsumed, 300), total(.protein, 12)]
        XCTAssertNil(FoodLogText.totalsFootnote(complete, plainWater: nil))
        XCTAssertNil(FoodLogText.totalsFootnote(complete + [total(.fatTotal, nil, incomplete: 1)], plainWater: nil),
                     "a wholly unknown total reads Unknown, with no +")
        XCTAssertEqual(FoodLogText.totalsFootnote(complete + [total(.fatTotal, 4, incomplete: 1)], plainWater: nil),
                       FoodLogText.totalsFootnote)
        XCTAssertEqual(FoodLogText.totalsFootnote(complete, plainWater: total(.water, 250, incomplete: 1)), FoodLogText.totalsFootnote,
                       "plain water as a known minimum shows +")
    }

    /// #308: Source details say why a value is unknown in plain words, never the raw identifier.
    func testUnknownNutrientReasonsArePlainLanguage() {
        let reasons: [UnknownReason] = [.notDeclared, .noCompatibleSource, .missingConversion, .conflictingEvidence]
        XCTAssertEqual(FoodLogText.unknownNutrient(.notDeclared), "Unknown, not stated by the source")
        for reason in reasons {
            let text = FoodLogText.unknownNutrient(reason)
            XCTAssertTrue(text.hasPrefix("Unknown, "), text)
            XCTAssertFalse(text.contains(reason.rawValue) || text.contains(String(describing: reason)) || text.contains("("), text)
        }
    }

    /// #308: changing a pasted label's basis keeps the amount and unit, and the Change sheet says so.
    func testBasisChangeSheetExplainsTheKeptUnit() {
        XCTAssertNil(PastedLabelBasisSheetView.basisChangeNote(fromChange: false), "no amount exists on the first sheet")
        let note = PastedLabelBasisSheetView.basisChangeNote(fromChange: true)
        XCTAssertEqual(note, PastedLabelText.basisChangeKeepsAmount)
        XCTAssertTrue(note?.contains("grams for per 100 g") == true)
        XCTAssertTrue(note?.contains("millilitres for per 100 mL") == true)
    }

    func testTotalsAndFlagsGoldenStrings() throws {
        func total(_ key: NutrientKey, _ amount: Double?, incomplete: Int = 0) -> FoodIntakeTotal {
            FoodIntakeSummaryProbe.total(key: key, amount: amount, incomplete: incomplete)
        }
        XCTAssertEqual(FoodLogText.total(total(.energyConsumed, 1240), locale: locale), "1,240 kcal", "#308: energy carries its unit")
        XCTAssertEqual(FoodLogText.total(total(.energyConsumed, 1240, incomplete: 1), locale: locale), "1,240 kcal+")
        XCTAssertEqual(FoodLogText.total(total(.protein, 68), locale: locale), "68 g")
        XCTAssertEqual(FoodLogText.total(total(.fatTotal, 41, incomplete: 1), locale: locale), "41 g+")
        XCTAssertEqual(FoodLogText.total(total(.fatTotal, nil, incomplete: 2), locale: locale), "Unknown")
        XCTAssertEqual(FoodLogText.totalAccessibility(total(.fatTotal, 41, incomplete: 1), locale: locale), "Fat, at least 41 grams")
        XCTAssertEqual(FoodLogText.totalAccessibility(total(.energyConsumed, nil), locale: locale), "Energy, unknown")
        XCTAssertEqual(FoodLogText.amount(try PositiveQuantity(value: 150, unit: .grams), locale: locale), "150 g")
        XCTAssertEqual(FoodLogText.amount(try PositiveQuantity(value: 1, unit: .count), locale: locale), "1 piece")
        XCTAssertEqual(FoodLogText.kcal(247.5, locale: locale), "248")
        XCTAssertEqual(FoodLogText.removedHeader(1), "Removed · 1 entry")
        XCTAssertEqual(FoodLogText.removedLine(removedAt: "11:02"), "Removed 11:02 · not in totals")
        XCTAssertEqual(FoodLogText.notCalculableReason(.unitMismatch(basis: .per100Grams, unit: .millilitres)),
                       "The source gives values per 100 g; this entry is in mL.")
        XCTAssertEqual(FoodLogText.notCalculableReason(.unknownBasis), "The source does not say what amount its values are for.")
    }

    func testEntryFlagsShowEstimateOnceAndEnergyUnknownAsText() async throws {
        let world = try World(now: now, calendar: calendar)
        _ = try world.save(grams: 150)
        _ = try world.save(grams: 200, unit: .millilitres)
        let model = FoodLogViewModel(store: world.store, now: { [now] in now }, calendar: calendar)
        await model.load()
        guard case let .loaded(day) = model.phase else { return XCTFail("loaded") }
        let gram = try XCTUnwrap(day.entries.first { $0.quantity.unit == .grams })
        let volume = try XCTUnwrap(day.entries.first { $0.quantity.unit == .millilitres })
        XCTAssertEqual(FoodLogText.flags(gram), "Carbohydrates unknown · Fat unknown")
        XCTAssertEqual(FoodLogText.entryEnergy(gram, locale: locale), "300 kcal")
        XCTAssertEqual(FoodLogText.entryEnergy(volume, locale: locale), "Energy unknown")
        XCTAssertFalse(FoodLogText.flags(volume).contains("Estimate"))
        XCTAssertTrue(FoodLogText.entryAccessibility(volume, time: "12:40", locale: locale).contains("Energy unknown"))
        XCTAssertEqual(FoodLogText.total(try XCTUnwrap(day.totals?.first { $0.key == .energyConsumed }), locale: locale), "300 kcal+")
    }
}

// MARK: - Fixtures

/// Builds `FoodIntakeTotal` values through the public summary, so golden strings use real inputs.
enum FoodIntakeSummaryProbe {
    static func total(key: NutrientKey, amount: Double?, incomplete: Int, augmented: Bool = false) -> FoodIntakeTotal {
        var contributions: [FoodIntakeContribution] = []
        let unit: QuantityUnit = .grams
        if let amount {
            let nutrients = try! NutrientSet(entries: NutrientKey.allCases.map { entryKey in
                guard entryKey == key else { return try NutrientEntry(key: entryKey, value: .unknown(.notDeclared)) }
                let value = try ExactNutrientValue(amount: amount, unit: entryKey.canonicalUnit,
                    sourceValue: .exact(SourceExactNutrientValue(amount: amount, unit: LedgerText(entryKey.canonicalUnit.rawValue), basis: .per100Grams)),
                    provenance: [NutrientProvenance(sourceKind: .exactProductDataset, sourceID: ExternalIdentifier("synthetic"),
                        sourceReleaseID: ExternalIdentifier("synthetic:v1"), recordID: ExternalIdentifier("probe"))])
                return try NutrientEntry(key: entryKey, value: augmented ? .augmented(value) : .measured(value))
            })
            contributions.append(FoodIntakeContribution(quantity: try! PositiveQuantity(value: 100, unit: unit), basis: .per100Grams, nutrients: nutrients))
        }
        for _ in 0..<incomplete {
            contributions.append(FoodIntakeContribution(quantity: try! PositiveQuantity(value: 100, unit: unit), basis: .unknown, nutrients: nil))
        }
        return FoodIntakeSummary(contributions: contributions).totals.first { $0.key == key }!
    }
}

/// A real in-memory ledger behind the Food Log port, counting calls.
@MainActor
private final class World {
    let store: CountingStore
    private let confirmations: FoodConfirmationService
    private let ids = PresentationIDs()
    private let now: Date
    private let calendar: Calendar
    private var evidence = 100

    init(now: Date, calendar: Calendar) throws {
        self.now = now
        self.calendar = calendar
        struct Clock: LedgerClock { let value: Date; func now() -> Date { value } }
        let ledgerStore = InMemoryFoodLedgerStore()
        let ledger = FoodLedgerService(actorID: try LedgerID("00000000-0000-0000-0000-000000000999"), committer: ledgerStore,
            clock: Clock(value: now), encoder: FoundationCanonicalJSONEncoder(), digester: SHA256Digester())
        confirmations = FoodConfirmationService(ledger: ledger, reader: ledgerStore, clock: Clock(value: now), ids: ids,
                                                digester: SHA256Digester(), calendar: calendar)
        store = CountingStore(service: FoodLogReadingService(ledger: ledger, archive: ledgerStore, confirmationReader: ledgerStore,
            history: ArchiveFoodLogHistoryReader(archive: ledgerStore), confirmations: confirmations,
            clock: Clock(value: now), ids: ids))
    }

    func newState(grams: Double, unit: QuantityUnit = .grams) throws -> FoodConfirmationState {
        evidence += 1
        let evidenceID: EvidenceID = try LedgerID(String(format: "00000000-0000-0000-0000-%012x", evidence))
        let releaseID = try ExternalIdentifier("synthetic:food-log-v1")
        let captured = try CaptureEvidence(evidenceID: evidenceID, kind: .synthetic, capturedAt: now, locale: LedgerText("en_GB"),
            captureMethod: LedgerText("presentation_fixture"), captureMethodVersion: LedgerText("v1"),
            originalPayload: .text(LedgerText("food log \(evidence)")))
        let release = SourceRelease(sourceReleaseID: releaseID, sourceID: try ExternalIdentifier("physical_package"), releasedAt: now,
            artifactHash: try SHA256Digest(String(repeating: "a", count: 64)), schemaVersion: try LedgerText("v1"),
            pipelineVersion: try LedgerText("v1"), licence: try LedgerText("fixture"), attribution: try LedgerText("fixture"),
            manifestHash: try SHA256Digest(String(repeating: "b", count: 64)))
        let identity = try DecisiveIdentity(preparation: PreparationState(kind: .asSold), bone: .notApplicable, skin: .notApplicable,
            drained: .notApplicable, packingMedium: .named(LedgerText("none")), fortification: .unfortified, servingBasis: .per100Grams)
        let provenance = NutrientProvenance(sourceKind: .manualDeclaration, sourceID: try ExternalIdentifier("physical_package"),
            sourceReleaseID: releaseID, evidenceID: evidenceID, capturedAt: now)
        let known: [NutrientKey: Double] = [.energyConsumed: 200, .protein: 10]
        let nutrients = try NutrientSet(entries: NutrientKey.allCases.map { key in
            guard let amount = known[key] else { return try NutrientEntry(key: key, value: .unknown(.notDeclared)) }
            return try NutrientEntry(key: key, value: .measured(ExactNutrientValue(amount: amount, unit: key.canonicalUnit,
                sourceValue: .exact(SourceExactNutrientValue(amount: amount, unit: LedgerText(key.canonicalUnit.rawValue), basis: .per100Grams)),
                provenance: [provenance])))
        })
        let hundred = try PositiveQuantity(value: 100, unit: .grams)
        let candidate = try PopulatedFoodCandidate(candidate: ProviderNeutralCandidate(sourceReleaseID: releaseID,
            recordID: ExternalIdentifier("record:\(evidence)"), identity: identity, edibleQuantity: .known(hundred, conversionVersionID: nil),
            nutrients: nutrients, evidenceIDs: [evidenceID]), name: try LedgerText("Fixture food"), itemClass: .food)
        let input = try PopulatedFoodConfirmation(evidence: [captured], sourceReleases: [release], candidates: [candidate],
            expectedIdentity: identity, expectedEdibleQuantity: .known(hundred, conversionVersionID: nil))
        var state = FoodConfirmationState(input: input)
        state.decision = .accepted
        state.quantity = FoodQuantityDraft(value: grams, unit: unit)
        return state
    }

    func save(grams: Double, unit: QuantityUnit = .grams) throws -> StoredFoodConfirmation {
        try confirmations.save(try newState(grams: grams, unit: unit), operationID: ids.makeID(OperationTag.self))
    }

    func editModel(_ id: LogItemID) throws -> FoodConfirmationViewModel? {
        guard let state = try confirmations.reopen(logItemID: id) else { return nil }
        let confirmations = confirmations, ids = ids, now = now
        return FoodConfirmationViewModel(state: state, now: { now }, calendar: calendar) { state in
            try confirmations.save(state, operationID: ids.makeID(OperationTag.self))
        }
    }
}

private final class CountingStore: FoodLogStore, @unchecked Sendable {
    let service: FoodLogReadingService
    private(set) var dayCalls = 0
    private(set) var removeCalls = 0
    init(service: FoodLogReadingService) { self.service = service }
    func day(_ reportingDate: String) async throws -> FoodLogDayContent {
        dayCalls += 1
        return try service.day(reportingDate: reportingDate)
    }
    func savedEntry(_ id: LogItemID) async throws -> SavedFoodEntryDetail? { try service.savedEntry(id) }
    func remove(_ id: LogItemID, expected: LogItemVersionID) async -> FoodLogChangeOutcome {
        removeCalls += 1
        return service.remove(id, expected: expected)
    }
    func restore(_ id: LogItemID, expected: LogItemVersionID) async -> FoodLogChangeOutcome { service.restore(id, expected: expected) }
}

private struct ScriptedStore: FoodLogStore {
    var dayError: Error?
    var entryError: Error?
    func day(_ reportingDate: String) async throws -> FoodLogDayContent {
        throw dayError ?? FoodIntakeProjectionError.missingReference
    }
    func savedEntry(_ id: LogItemID) async throws -> SavedFoodEntryDetail? {
        if let entryError { throw entryError }
        return nil
    }
    func remove(_ id: LogItemID, expected: LogItemVersionID) async -> FoodLogChangeOutcome { .notSaved }
    func restore(_ id: LogItemID, expected: LogItemVersionID) async -> FoodLogChangeOutcome { .notSaved }
}

private final class PresentationIDs: LedgerIDGenerating, @unchecked Sendable {
    private let lock = NSLock()
    private var value = 20_000
    func makeID<Tag>(_ tag: Tag.Type) throws -> LedgerID<Tag> {
        lock.lock(); defer { lock.unlock() }
        value += 1
        return try LedgerID(String(format: "00000000-0000-0000-0000-%012x", value))
    }
}
