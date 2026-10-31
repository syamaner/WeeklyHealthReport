import Foundation
import FoodLedgerApplication
import FoodLedgerDomain
@testable import FoodLedgerPresentation
import SwiftUI
import XCTest

/// #357: the two timing edges of the "Logged" banner. An Undo tap the system delivered before the
/// visible duration ended is applied even when the timeout runs before the remove, a press held
/// across the end waits for the lift, and the banner's area takes taps before it has slid in.
/// Undo still removes exactly the logged version, once.
@MainActor
final class FoodLoggedBannerTimingTests: XCTestCase {
    /// The tap's action moves the banner to `.removing` before the timeout task can run, so the
    /// timeout no longer hides it and the remove completes.
    func testAnUndoTapAppliesWhenTheTimeoutRunsBeforeTheRemove() async throws {
        let removal = TimingGate()
        let store = GatedRemover(gate: removal)
        let model = FoodLoggedBannerModel(store: store, sleep: { _ in await TimingGate.never() }, announce: { _ in })
        let notice = try Self.notice()
        model.show(notice)

        let undo = try XCTUnwrap(model.startUndo(), "Undo is offered")
        XCTAssertEqual(model.content, .removing(notice), "set by the tap itself, before any await")
        model.expire(generation: model.currentGeneration)
        XCTAssertEqual(model.content, .removing(notice), "the timeout after the tap does not hide it")
        XCTAssertNil(model.startUndo(), "a second tap starts nothing")

        removal.release()
        await undo.value
        XCTAssertEqual(model.content, .result(FoodLoggedText.removed))
        XCTAssertEqual(store.removes.count, 1, "one remove")
        XCTAssertEqual(store.removes.first?.0, notice.logItemID)
        XCTAssertEqual(store.removes.first?.1, notice.logItemVersionID, "exactly the logged version")
        XCTAssertEqual(model.removals, 1)
        XCTAssertNil(model.startUndo(), "no Undo on the result")
        await model.undo()
        XCTAssertEqual(store.removes.count, 1, "a later tap writes nothing")
    }

    /// A finger that went down on Undo before the end keeps the banner until it lifts; the tap's
    /// action on the lift then applies.
    func testTheTimeoutWaitsForAPressThatBeganBeforeIt() async throws {
        let removal = TimingGate()
        removal.release()
        let store = GatedRemover(gate: removal)
        let model = FoodLoggedBannerModel(store: store, sleep: { _ in await TimingGate.never() }, announce: { _ in })
        let notice = try Self.notice()
        model.show(notice)

        model.undoPressChanged(true)
        model.expire(generation: model.currentGeneration)
        XCTAssertEqual(model.content, .logged(notice), "kept while the finger is down")
        let undo = try XCTUnwrap(model.startUndo(), "the lift delivers the tap")
        model.undoPressChanged(false)
        await undo.value
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(model.content, .result(FoodLoggedText.removed), "the deferred timeout does not hide the outcome")
        XCTAssertEqual(store.removes.count, 1)
    }

    /// A press dragged off Undo (or cancelled) after the end hides the banner once it lifts and
    /// writes nothing; a press without a timeout leaves the banner as it was.
    func testAPressLiftedWithoutATapHidesTheBannerAfterTheEnd() async throws {
        let removal = TimingGate()
        let store = GatedRemover(gate: removal)
        let model = FoodLoggedBannerModel(store: store, sleep: { _ in await TimingGate.never() }, announce: { _ in })
        let notice = try Self.notice()
        model.show(notice)

        model.undoPressChanged(true)
        model.undoPressChanged(false)
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(model.content, .logged(notice), "no timeout yet, so nothing changes")

        model.undoPressChanged(true)
        model.expire(generation: model.currentGeneration)
        XCTAssertNotNil(model.content)
        model.undoPressChanged(false)
        for _ in 0..<20 { await Task.yield() }
        XCTAssertNil(model.content, "the deferred timeout applies after the lift")
        await model.undo()
        XCTAssertTrue(store.removes.isEmpty)
    }

    /// A deferred timeout belongs to its banner: a newer banner shown while the finger was down
    /// keeps its own duration.
    func testADeferredTimeoutDoesNotHideANewerBanner() async throws {
        let model = FoodLoggedBannerModel(store: GatedRemover(gate: TimingGate()), sleep: { _ in await TimingGate.never() },
                                          announce: { _ in })
        model.show(try Self.notice())
        model.undoPressChanged(true)
        model.expire(generation: model.currentGeneration)
        model.show(try Self.notice(message: "Logged"))
        model.undoPressChanged(false)
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(model.content?.message, "Logged")
    }

    /// The lift's report may arrive before the tap's action in the same turn: the deferred
    /// timeout waits for the next turn, so the action still applies.
    func testATapDeliveredJustAfterTheLiftReportStillApplies() async throws {
        let removal = TimingGate()
        removal.release()
        let store = GatedRemover(gate: removal)
        let model = FoodLoggedBannerModel(store: store, sleep: { _ in await TimingGate.never() }, announce: { _ in })
        let notice = try Self.notice()
        model.show(notice)
        model.undoPressChanged(true)
        model.expire(generation: model.currentGeneration)
        model.undoPressChanged(false)
        XCTAssertEqual(model.content, .logged(notice), "the deferred timeout has not run yet")
        let undo = try XCTUnwrap(model.startUndo())
        await undo.value
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(model.content, .result(FoodLoggedText.removed))
        XCTAssertEqual(store.removes.count, 1)
    }

    /// The banner and the shield share a bottom-aligned stack, so a shorter outcome card stays
    /// pinned to the bottom of the logged layout rather than centred in it.
    func testTheOutcomeCardIsBottomPinnedInsideTheShield() async throws {
        let removal = TimingGate()
        removal.release()
        let model = FoodLoggedBannerModel(store: GatedRemover(gate: removal), sleep: { _ in await TimingGate.never() },
                                          announce: { _ in })
        model.show(try Self.notice())
        await model.undo()
        let alignment = try XCTUnwrap(Self.first(Alignment.self, in: FoodLoggedBanner(model: model).body))
        XCTAssertEqual(alignment, .bottom)
    }

    /// A press left behind by a banner that went away mid-press (navigation, a dismissal) does
    /// not hold the next banner past its duration.
    func testAPressLeftByAnEarlierBannerDoesNotHoldTheNextOne() throws {
        let model = FoodLoggedBannerModel(store: GatedRemover(gate: TimingGate()), sleep: { _ in await TimingGate.never() },
                                          announce: { _ in })
        model.show(try Self.notice())
        model.undoPressChanged(true)
        model.dismiss()
        model.show(try Self.notice(message: "Logged"))
        model.expire(generation: model.currentGeneration)
        XCTAssertNil(model.content, "the new banner times out")

        model.show(try Self.notice())
        model.undoPressChanged(true)
        model.show(try Self.notice(message: "Logged"))
        model.expire(generation: model.currentGeneration)
        XCTAssertNil(model.content, "a newer banner starts without the older press")
    }

    /// The shield keeps the logged banner's layout after Undo, so the area where Undo was stays
    /// covered while the shorter outcome shows; it goes with the banner.
    func testTheShieldKeepsTheLoggedLayoutAfterUndo() async throws {
        let removal = TimingGate()
        removal.release()
        let model = FoodLoggedBannerModel(store: GatedRemover(gate: removal), sleep: { _ in await TimingGate.never() },
                                          announce: { _ in })
        let notice = try Self.notice()
        model.show(notice)
        await model.undo()
        XCTAssertEqual(model.content, .result(FoodLoggedText.removed))
        let shield = try XCTUnwrap(Self.first(FoodLoggedBannerTapShield.self, in: FoodLoggedBanner(model: model).body))
        XCTAssertEqual(shield.content, .logged(notice))
        model.dismiss()
        XCTAssertNil(model.shieldLayout)
        XCTAssertNil(Self.first(FoodLoggedBannerTapShield.self, in: FoodLoggedBanner(model: model).body))
    }

    /// From the moment the banner is set, its area has a shield that is not under the slide-in
    /// transition, sits under the banner and is hidden from VoiceOver; the banner's Undo is the
    /// one the model starts.
    func testTheBannerAreaHasATapShieldFromTheMomentItIsShown() throws {
        let model = FoodLoggedBannerModel(store: GatedRemover(gate: TimingGate()), sleep: { _ in await TimingGate.never() },
                                          announce: { _ in })
        XCTAssertNil(Self.first(FoodLoggedBannerTapShield.self, in: FoodLoggedBanner(model: model).body))
        let notice = try Self.notice()
        model.show(notice)
        let body = FoodLoggedBanner(model: model).body
        let shield = try XCTUnwrap(Self.first(FoodLoggedBannerTapShield.self, in: body), "present without waiting for the transition")
        XCTAssertEqual(shield.content, .logged(notice), "the same layout as the banner")
        let banner = try XCTUnwrap(Self.first(FoodLoggedBannerContent.self, in: body))
        let undo = try XCTUnwrap(Mirror(reflecting: banner).descendant("undo") as? () -> Void)
        undo()
        XCTAssertEqual(model.content, .removing(notice), "the button's tap starts Undo synchronously")
    }

    private static func notice(message: String = "Logged · 57 kcal") throws -> FoodLoggedNotice {
        FoodLoggedNotice(logItemID: try LogItemID("00000000-0000-0000-0000-000000000001"),
                         logItemVersionID: try LogItemVersionID("00000000-0000-0000-0000-000000000002"), message: message)
    }

    private static func first<T>(_ type: T.Type, in value: Any, depth: Int = 0) -> T? {
        if let match = value as? T { return match }
        guard depth < 40 else { return nil }
        for child in Mirror(reflecting: value).children {
            if let match = first(type, in: child.value, depth: depth + 1) { return match }
        }
        return nil
    }
}

@MainActor
private final class TimingGate {
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
    nonisolated static func never() async { try? await Task.sleep(for: .seconds(3600)) }
}

@MainActor
private final class GatedRemover: FoodLogStore {
    let gate: TimingGate
    private(set) var removes: [(LogItemID, LogItemVersionID)] = []
    init(gate: TimingGate) { self.gate = gate }
    nonisolated func day(_ reportingDate: String) async throws -> FoodLogDayContent { throw FoodIntakeProjectionError.missingReference }
    nonisolated func savedEntry(_ id: LogItemID) async throws -> SavedFoodEntryDetail? { nil }
    func remove(_ id: LogItemID, expected: LogItemVersionID) async -> FoodLogChangeOutcome {
        removes.append((id, expected))
        await gate.wait()
        return .applied
    }
    nonisolated func restore(_ id: LogItemID, expected: LogItemVersionID) async -> FoodLogChangeOutcome { .notSaved }
}
