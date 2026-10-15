import Foundation
import FoodLedgerApplication
import FoodLedgerDomain
import FoodLedgerPresentation
import XCTest

/// Owner decision, 15 October 2026: Log closes Confirm and the destination shows a banner with
/// Undo. Undo writes one remove through `FoodLogStore`; it is gone after the visible duration,
/// after dismissal and after navigation.
@MainActor
final class FoodLoggedBannerPresentationTests: XCTestCase {
    func testMessageVariants() {
        XCTAssertEqual(FoodLoggedText.message(figure: "260 kcal", withoutNutrition: false, savedFavourite: false), "Logged · 260 kcal")
        XCTAssertEqual(FoodLoggedText.message(figure: nil, withoutNutrition: false, savedFavourite: false), "Logged")
        XCTAssertEqual(FoodLoggedText.message(figure: nil, withoutNutrition: true, savedFavourite: false), "Logged without nutrition")
        XCTAssertEqual(FoodLoggedText.message(figure: "260 kcal", withoutNutrition: false, savedFavourite: true),
                       "Logged and saved as favourite · 260 kcal")
        XCTAssertEqual(FoodLoggedText.message(figure: nil, withoutNutrition: true, savedFavourite: true),
                       "Logged without nutrition and saved as favourite")
        XCTAssertEqual(FoodLoggedText.detail(savedFavourite: true), "Undo removes the entry. The favourite stays.")
        XCTAssertNil(FoodLoggedText.detail(savedFavourite: false))
        XCTAssertEqual(FoodLoggedText.outcome(.applied), "Entry removed")
        for text in [FoodLoggedText.unchanged, FoodLoggedText.notRemoved, FoodLoggedText.undoHint, FoodLoggedText.favouriteStays] {
            XCTAssertFalse(text.contains("\u{2014}"), "no em dash")
        }
    }

    func testUndoWritesExactlyOneRemoveAndOffersNoFurtherUndo() async throws {
        let store = RecordingRemover(outcome: .applied)
        let model = FoodLoggedBannerModel(store: store, sleep: { _ in await Self.never() })
        let notice = try Self.notice()
        model.show(notice)
        XCTAssertEqual(model.content, .logged(notice))
        XCTAssertTrue(model.content?.offersUndo == true)
        async let first: Void = model.undo()
        async let second: Void = model.undo()
        _ = await (first, second)
        await model.undo()
        XCTAssertEqual(store.removes.count, 1, "one Undo, one remove")
        XCTAssertEqual(store.removes.first?.0, notice.logItemID)
        XCTAssertEqual(store.removes.first?.1, notice.logItemVersionID)
        XCTAssertEqual(model.content, .result("Entry removed"))
        XCTAssertFalse(model.content?.offersUndo == true, "no further Undo")
        XCTAssertEqual(model.removals, 1)
    }

    func testUndoOutcomesOtherThanAppliedSayNothingWasRemoved() async throws {
        for (outcome, text) in [(FoodLogChangeOutcome.changedElsewhere, FoodLoggedText.unchanged), (.notSaved, FoodLoggedText.notRemoved)] {
            let model = FoodLoggedBannerModel(store: RecordingRemover(outcome: outcome), sleep: { _ in await Self.never() })
            model.show(try Self.notice())
            await model.undo()
            XCTAssertEqual(model.content, .result(text))
            XCTAssertEqual(model.removals, 0)
        }
    }

    func testUndoIsUnavailableAfterTheVisibleDuration() async throws {
        let store = RecordingRemover(outcome: .applied)
        let model = FoodLoggedBannerModel(store: store, sleep: { _ in await Self.never() })
        model.show(try Self.notice())
        model.expire(generation: model.currentGeneration)
        XCTAssertNil(model.content)
        await model.undo()
        XCTAssertTrue(store.removes.isEmpty)
    }

    func testTheDefaultTimerHidesTheBanner() async throws {
        let model = FoodLoggedBannerModel(store: RecordingRemover(outcome: .applied), sleep: { _ in }, announce: { _ in })
        model.show(try Self.notice())
        for _ in 0..<50 where model.content != nil { await Task.yield() }
        XCTAssertNil(model.content)
        XCTAssertEqual(FoodLoggedBannerModel.visibleDuration, .seconds(5))
    }

    func testVoiceOverKeepsTheBannerUntilDismissed() async throws {
        let store = RecordingRemover(outcome: .applied)
        let model = FoodLoggedBannerModel(store: store, sleep: { _ in await Self.never() })
        model.keepsUntilDismissed = true
        model.show(try Self.notice())
        model.expire(generation: model.currentGeneration)
        XCTAssertNotNil(model.content, "kept while VoiceOver runs")
        XCTAssertEqual(FoodLoggedBannerModel.announcement(try XCTUnwrap(model.content)), "Logged · 57 kcal. Undo available.")
        model.dismiss()
        XCTAssertNil(model.content)
        await model.undo()
        XCTAssertTrue(store.removes.isEmpty)
    }

    func testNavigationAwayRemovesUndoButTheClosingNavigationDoesNot() async throws {
        let store = RecordingRemover(outcome: .applied)
        let model = FoodLoggedBannerModel(store: store, sleep: { _ in await Self.never() })
        var path = ["foodLog"]
        model.location = { AnyHashable(path) }
        model.show(try Self.notice())
        model.navigated(to: AnyHashable(["foodLog"]))
        XCTAssertNotNil(model.content, "the path Log closed to")
        path = ["foodLog", "addFood"]
        model.navigated(to: AnyHashable(path))
        XCTAssertNil(model.content)
        await model.undo()
        XCTAssertTrue(store.removes.isEmpty)
    }

    func testAnOlderTimerDoesNotHideANewerBanner() throws {
        let model = FoodLoggedBannerModel(store: RecordingRemover(outcome: .applied), sleep: { _ in await Self.never() })
        model.show(try Self.notice())
        let older = model.currentGeneration
        model.show(try Self.notice(message: "Logged"))
        model.expire(generation: older)
        XCTAssertEqual(model.content?.message, "Logged")
    }

    // MARK: Review fixes (PR #240)

    /// A sheet closed over a registered screen: the banner belongs to that screen, and anything
    /// pushed over it (a saved entry, a search result) dismisses it.
    func testLeavingTheScreenStillShowingDismissesTheBanner() async throws {
        let store = RecordingRemover(outcome: .applied)
        let model = FoodLoggedBannerModel(store: store, sleep: { _ in await Self.never() }, announce: { _ in })
        let home = UUID(), pushed = UUID()
        model.screenAppeared(home)
        model.show(try Self.notice())
        model.screenAppeared(pushed)
        XCTAssertNotNil(model.content, "a push appearing first is not yet leaving")
        model.screenDisappeared(home)
        XCTAssertNil(model.content)
        await model.undo()
        XCTAssertTrue(store.removes.isEmpty, "no Undo over another screen")
    }

    /// Confirm popping back: the destination appears after `show`, takes the banner, and opening
    /// a saved entry from it (a push outside the navigation path) dismisses the banner.
    func testTheDestinationThatAppearsAfterLogTakesTheBanner() throws {
        let model = FoodLoggedBannerModel(store: RecordingRemover(outcome: .applied), sleep: { _ in await Self.never() },
                                          announce: { _ in })
        let foodLog = UUID(), search = UUID(), savedEntry = UUID()
        model.screenAppeared(foodLog)
        model.screenDisappeared(foodLog) // Add food pushed over the Food Log
        model.screenAppeared(search)
        model.screenDisappeared(search) // Confirm pushed over search results
        model.show(try Self.notice())
        model.screenAppeared(foodLog)
        model.screenDisappeared(search) // torn down after the pop: not the banner's screen
        XCTAssertNotNil(model.content)
        model.screenAppeared(savedEntry)
        model.screenDisappeared(foodLog)
        XCTAssertNil(model.content, "opening a saved entry dismisses the banner")
    }

    func testOnlyLoggedAndTheOutcomeAreAnnouncedAfterTheDelay() async throws {
        let sleeps = Recorder<Duration>()
        let announced = Recorder<String>()
        let model = FoodLoggedBannerModel(store: RecordingRemover(outcome: .applied),
                                          sleep: { duration in await sleeps.append(duration) },
                                          announce: { announced.values.append($0) })
        model.keepsUntilDismissed = true
        model.show(try Self.notice())
        XCTAssertTrue(announced.values.isEmpty, "not before the delay")
        for _ in 0..<50 { await Task.yield() }
        XCTAssertEqual(announced.values, ["Logged · 57 kcal. Undo available."])
        await model.undo()
        for _ in 0..<50 { await Task.yield() }
        XCTAssertEqual(announced.values, ["Logged · 57 kcal. Undo available.", "Entry removed."])
        XCTAssertNil(FoodLoggedBannerModel.announcement(.removing(try Self.notice())), "Undo in progress is not announced")
        XCTAssertEqual(sleeps.values.filter { $0 == FoodLoggedBannerModel.announcementDelay }.count, 2)
        XCTAssertGreaterThan(FoodLoggedBannerModel.announcementDelay, .zero)
    }

    func testUndoDuringTheAnnouncementDelayIsNotAnnouncedAsLogged() async throws {
        let delay = Gate()
        let removal = Gate()
        let announced = Recorder<String>()
        let announcementDelay = FoodLoggedBannerModel.announcementDelay
        let model = FoodLoggedBannerModel(store: SuspendingRemover(gate: removal),
                                          sleep: { duration in
                                              if duration == announcementDelay { await delay.wait() } else { await Self.never() }
                                          },
                                          announce: { announced.values.append($0) })
        model.show(try Self.notice())
        let undo = Task { await model.undo() }
        for _ in 0..<50 { await Task.yield() }
        delay.release()
        for _ in 0..<50 { await Task.yield() }
        XCTAssertTrue(announced.values.isEmpty, "Undo is already running, so Undo available is not spoken")
        removal.release()
        await undo.value
        for _ in 0..<50 { await Task.yield() }
        XCTAssertEqual(announced.values, ["Entry removed."])
    }

    func testAccessibilityTextSizesKeepTheBannerForTenSeconds() async throws {
        let sleeps = Recorder<Duration>()
        let model = FoodLoggedBannerModel(store: RecordingRemover(outcome: .applied),
                                          sleep: { duration in await sleeps.append(duration) }, announce: { _ in })
        XCTAssertEqual(model.visibleDuration, .seconds(5))
        model.usesAccessibilityTextSize = true
        XCTAssertEqual(model.visibleDuration, .seconds(10))
        model.show(try Self.notice())
        for _ in 0..<50 { await Task.yield() }
        XCTAssertTrue(sleeps.values.contains(.seconds(10)))
        XCTAssertFalse(sleeps.values.contains(.seconds(5)))
    }

    func testVoiceOverSeesOneElementWithUndoAndDismissActions() throws {
        let logged = FoodLoggedBannerModel.Content.logged(FoodLoggedNotice(
            logItemID: try LogItemID("00000000-0000-0000-0000-000000000001"),
            logItemVersionID: try LogItemVersionID("00000000-0000-0000-0000-000000000002"),
            message: "Logged and saved as favourite · 57 kcal", detail: FoodLoggedText.favouriteStays))
        XCTAssertEqual(FoodLoggedBannerContent.accessibilityLabel(logged),
                       "Logged and saved as favourite · 57 kcal. Undo removes the entry. The favourite stays.")
        XCTAssertEqual(FoodLoggedBannerContent.accessibilityActionNames(logged), ["Undo", "Dismiss"])
        XCTAssertEqual(FoodLoggedBannerContent.accessibilityActionNames(.result(FoodLoggedText.removed)), ["Dismiss"])
    }

    private static func notice(message: String = "Logged · 57 kcal") throws -> FoodLoggedNotice {
        FoodLoggedNotice(logItemID: try LogItemID("00000000-0000-0000-0000-000000000001"),
                         logItemVersionID: try LogItemVersionID("00000000-0000-0000-0000-000000000002"), message: message)
    }

    private static func never() async {
        try? await Task.sleep(for: .seconds(3600))
    }
}

@MainActor
private final class Recorder<Value: Sendable>: Sendable {
    var values: [Value] = []
    func append(_ value: Value) { values.append(value) }
}

private final class RecordingRemover: FoodLogStore, @unchecked Sendable {
    let outcome: FoodLogChangeOutcome
    private(set) var removes: [(LogItemID, LogItemVersionID)] = []
    init(outcome: FoodLogChangeOutcome) { self.outcome = outcome }
    func day(_ reportingDate: String) async throws -> FoodLogDayContent { throw FoodIntakeProjectionError.missingReference }
    func savedEntry(_ id: LogItemID) async throws -> SavedFoodEntryDetail? { nil }
    func remove(_ id: LogItemID, expected: LogItemVersionID) async -> FoodLogChangeOutcome {
        removes.append((id, expected))
        return outcome
    }
    func restore(_ id: LogItemID, expected: LogItemVersionID) async -> FoodLogChangeOutcome { .notSaved }
}

@MainActor
private final class Gate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { waiters.append($0) }
    }
    func release() {
        isOpen = true
        waiters.forEach { $0.resume() }
        waiters = []
    }
}

private final class SuspendingRemover: FoodLogStore, @unchecked Sendable {
    let gate: Gate
    init(gate: Gate) { self.gate = gate }
    func day(_ reportingDate: String) async throws -> FoodLogDayContent { throw FoodIntakeProjectionError.missingReference }
    func savedEntry(_ id: LogItemID) async throws -> SavedFoodEntryDetail? { nil }
    func remove(_ id: LogItemID, expected: LogItemVersionID) async -> FoodLogChangeOutcome {
        await gate.wait()
        return .applied
    }
    func restore(_ id: LogItemID, expected: LogItemVersionID) async -> FoodLogChangeOutcome { .notSaved }
}
