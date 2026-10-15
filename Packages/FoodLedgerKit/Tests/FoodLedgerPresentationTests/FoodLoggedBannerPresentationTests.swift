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
        let model = FoodLoggedBannerModel(store: RecordingRemover(outcome: .applied), sleep: { _ in })
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
        XCTAssertEqual(FoodLoggedBanner.announcement(try XCTUnwrap(model.content)), "Logged · 57 kcal. Undo available.")
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

    private static func notice(message: String = "Logged · 57 kcal") throws -> FoodLoggedNotice {
        FoodLoggedNotice(logItemID: try LogItemID("00000000-0000-0000-0000-000000000001"),
                         logItemVersionID: try LogItemVersionID("00000000-0000-0000-0000-000000000002"), message: message)
    }

    private static func never() async {
        try? await Task.sleep(for: .seconds(3600))
    }
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
