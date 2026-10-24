import Foundation
import FoodLedgerApplication
import FoodLedgerDomain
import FoodLedgerPresentation
import FoodLedgerTestSupport
import XCTest

/// Owner decisions A and F (13 October 2026): Save as favourite from what was logged, and the
/// Favourites screen's water confirmation and "Add Water to quick add".
@MainActor
final class FavouriteSavingPresentationTests: XCTestCase {
    private final class FakeStore: FavouriteSaving {
        var active: Set<LogItemVersionID> = []
        var failures = 0
        private(set) var saves = 0
        let now = Date(timeIntervalSince1970: 1_791_800_000)

        func projection() throws -> FavouritesProjection {
            let versions = try active.sorted { $0.rawValue < $1.rawValue }.enumerated().map { index, id in
                try FavouriteVersion(favouriteVersionID: LedgerID(String(format: "00000000-0000-0000-0000-%012x", index + 1)),
                    favouriteID: LedgerID(String(format: "00000000-0000-0000-0000-%012x", index + 101)), ordinal: VersionOrdinal(1),
                    binding: .savedEntry(id), label: LedgerText("Synthetic"), defaultAmount: FavouriteAmount(value: 150, unit: .grams),
                    state: .active, createdAt: now)
            }
            let entries = versions.map { FavouriteEntry(favouriteID: $0.favouriteID, createdAt: now) }
            return try FavouritesProjection(records: FavouriteMutation(favourites: entries, favouriteVersions: versions))
        }

        private(set) var savedIDs: [LogItemVersionID] = []

        func saveFavourite(logItemVersionID: LogItemVersionID) throws -> FavouriteVersion {
            saves += 1
            savedIDs.append(logItemVersionID)
            if failures > 0 { failures -= 1; throw FoodLedgerStoreError.integrityFailure("synthetic") }
            active.insert(logItemVersionID)
            return try XCTUnwrap(projection().activeFavourite(boundTo: logItemVersionID))
        }

        /// Versions with the same food, source, preparation and amount as an active favourite's (#308).
        var sameSource: [LogItemVersionID: LogItemVersionID] = [:]
        private(set) var matchReads = 0

        func activeFavourites(matching logItemVersionIDs: [LogItemVersionID]) throws -> [LogItemVersionID: FavouriteVersion] {
            matchReads += 1
            let projection = try projection()
            var result: [LogItemVersionID: FavouriteVersion] = [:]
            for id in logItemVersionIDs {
                result[id] = projection.activeFavourite(boundTo: id) ?? sameSource[id].flatMap { projection.activeFavourite(boundTo: $0) }
            }
            return result
        }
    }

    /// #308: after a re-log, the new entry from the same food and source reads "Already a
    /// favourite" and is never offered or saved again.
    func testRelogOfAFavouriteStaysAlreadyAFavourite() throws {
        let store = FakeStore()
        let original = try id(10), relog = try id(11), other = try id(12)
        store.active = [original]
        store.sameSource = [relog: original]
        let model = FavouriteSaveModel(store: store)
        model.refresh([relog, other])
        XCTAssertEqual(store.matchReads, 1, "one read per refresh, not one per row")
        XCTAssertEqual(model.state(for: relog), .alreadyFavourite)
        XCTAssertEqual(model.state(for: other), .available)
        model.save(relog)
        XCTAssertEqual(store.saves, 0, "no duplicate favourite")
        // A row refreshed before the favourite existed still writes nothing once it does.
        let stale = FavouriteSaveModel(store: store)
        store.active = []
        stale.refresh([relog])
        XCTAssertEqual(stale.state(for: relog), .available)
        store.active = [original]
        stale.save(relog)
        XCTAssertEqual(stale.state(for: relog), .alreadyFavourite)
        XCTAssertEqual(store.saves, 0)
    }

    private func id(_ value: Int) throws -> LogItemVersionID {
        try LedgerID(String(format: "00000000-0000-0000-0000-%012x", 900 + value))
    }

    func testSaveShowsSavedAndARepeatWritesNothing() throws {
        let store = FakeStore()
        let model = FavouriteSaveModel(store: store)
        let entry = try id(1)
        model.refresh([entry])
        XCTAssertEqual(model.state(for: entry), .available)
        XCTAssertEqual(FavouriteSaveText.title(model.state(for: entry)), "Save as favourite")
        model.save(entry)
        XCTAssertEqual(model.state(for: entry), .saved)
        XCTAssertEqual(FavouriteSaveText.title(.saved), "Saved as favourite")
        model.save(entry)
        XCTAssertEqual(store.saves, 1, "one tap writes at most one favourite")
        model.refresh([entry])
        XCTAssertEqual(model.state(for: entry), .saved, "a refresh keeps the saved wording")
    }

    func testAlreadyAFavouriteIsShownAndNotSavedAgain() throws {
        let store = FakeStore()
        let entry = try id(2), other = try id(3)
        store.active = [entry]
        let model = FavouriteSaveModel(store: store)
        model.refresh([entry, other])
        XCTAssertEqual(model.state(for: entry), .alreadyFavourite)
        XCTAssertEqual(FavouriteSaveText.title(.alreadyFavourite), "Already a favourite")
        XCTAssertEqual(model.state(for: other), .available)
        model.save(entry)
        XCTAssertEqual(store.saves, 0)
        // Removed elsewhere: the control becomes available again.
        store.active = []
        model.refresh([entry])
        XCTAssertEqual(model.state(for: entry), .available)
    }

    func testFailureSaysFavouriteNotSavedAndTryAgainSaves() throws {
        let store = FakeStore()
        store.failures = 1
        let model = FavouriteSaveModel(store: store)
        let entry = try id(4)
        model.save(entry)
        XCTAssertEqual(model.state(for: entry), .failed)
        XCTAssertEqual(FavouriteSaveText.title(.failed), "Favourite not saved")
        XCTAssertEqual(FavouriteSaveText.tryAgain, "Try again")
        model.refresh([entry])
        XCTAssertEqual(model.state(for: entry), .failed, "the failure stays until Try again")
        model.save(entry)
        XCTAssertEqual(model.state(for: entry), .saved)
        XCTAssertEqual(store.saves, 2)
    }

    /// Review question 1: a recent row showing an older version (the entry was edited elsewhere
    /// while the list was open) pins the entry's current version, read at tap time; the row shows
    /// the result. A removed entry fails and writes nothing.
    func testRecentRowPinsTheCurrentVersionReadAtTapTime() throws {
        let store = FakeStore()
        let shown = try id(10), current = try id(11)
        let logItemID: LogItemID = try LedgerID("00000000-0000-0000-0000-000000000777")
        var head: LogItemVersionID? = current
        var reads = 0
        let model = FavouriteSaveModel(store: store) { requested in
            XCTAssertEqual(requested, logItemID)
            reads += 1
            return head
        }
        model.refresh([shown])
        model.save(shown, logItemID: logItemID)
        XCTAssertEqual(reads, 1, "read at tap time")
        XCTAssertEqual(store.savedIDs, [current], "never the older version the row shows")
        XCTAssertEqual(model.state(for: shown), .saved)
        XCTAssertEqual(model.state(for: current), .saved)
        model.save(shown, logItemID: logItemID)
        XCTAssertEqual(store.saves, 1, "a saved row writes nothing more")

        // Current version already a favourite: shown as such, nothing written.
        let other = try id(12), otherCurrent = try id(13)
        store.active.insert(otherCurrent)
        head = otherCurrent
        model.save(other, logItemID: logItemID)
        XCTAssertEqual(model.state(for: other), .alreadyFavourite)
        XCTAssertEqual(store.saves, 1)

        // Removed meanwhile: fails, nothing written.
        let removed = try id(14)
        head = nil
        model.save(removed, logItemID: logItemID)
        XCTAssertEqual(model.state(for: removed), .failed)
        XCTAssertEqual(store.saves, 1)

        // Unchanged head: saves the shown version.
        let same = try id(15)
        head = same
        model.save(same, logItemID: logItemID)
        XCTAssertEqual(store.savedIDs.last, same)
    }

    /// Review question 2: Try again is pressed while the alert dismisses; the retry runs only
    /// after the dismissal, and a second failure presents the alert again.
    func testRetryAlertRunsAfterDismissalAndRepresentsOnASecondFailure() {
        var alert = FavouriteRetryAlert()
        XCTAssertFalse(alert.isPresented)
        alert.finished(.failed)
        XCTAssertTrue(alert.isPresented)
        alert.tryAgain()
        XCTAssertTrue(alert.isPresented, "still dismissing")
        XCTAssertFalse(alert.takeRetry(), "no retry while the alert is up")
        alert.dismissed()
        XCTAssertTrue(alert.takeRetry())
        XCTAssertFalse(alert.takeRetry(), "consumed once")
        alert.finished(.failed)
        XCTAssertTrue(alert.isPresented, "a second failure presents the alert again")
        alert.dismissed()
        XCTAssertFalse(alert.takeRetry(), "Cancel runs nothing")
        alert.finished(.saved)
        XCTAssertFalse(alert.isPresented)
    }

    /// Journey QA: Add food's swipe hint shows only while a row can still be saved.
    func testAddFoodSwipeHintOnlyWhileARowCanBeSaved() throws {
        func recent(_ number: Int, version: LogItemVersionID?, water: Bool = false) throws -> FoodRecentRelogItem {
            FoodRecentRelogItem(item: FoodRecentItem(logItemID: try LedgerID(String(format: "00000000-0000-0000-0000-%012x", 600 + number)),
                sourceReleaseID: try ExternalIdentifier("fixture:release"), recordID: try ExternalIdentifier("fixture:\(number)"),
                occurredAt: Date(timeIntervalSince1970: 1_791_800_000), lastAmount: try PositiveQuantity(value: 150, unit: .grams), energyKcal: 90),
                name: "Food \(number)", isEstimate: false, logItemVersionID: version, isPlainWater: water)
        }
        let store = FakeStore()
        let saved = try id(20), open = try id(21)
        store.active = [saved]
        let model = FavouriteSaveModel(store: store)
        let favourite = try recent(1, version: saved), available = try recent(2, version: open)
        let water = try recent(3, version: try id(22), water: true), unpinnable = try recent(4, version: nil)
        model.refresh([saved, open])
        XCTAssertTrue(AddFoodView.showsSaveHint([favourite, available, water, unpinnable], model: model))
        XCTAssertFalse(AddFoodView.showsSaveHint([favourite, water, unpinnable], model: model),
                       "already a favourite, plain water and unpinnable rows cannot be saved")
        XCTAssertFalse(AddFoodView.showsSaveHint([], model: model))
        model.save(open)
        XCTAssertFalse(AddFoodView.showsSaveHint([favourite, available], model: model), "hidden once the last row is saved")
    }

    func testFromWhatYouLoggedOffersOnlyPinnableNonWaterFoods() throws {
        func recent(_ number: Int, version: LogItemVersionID?, water: Bool) throws -> FoodRecentRelogItem {
            FoodRecentRelogItem(item: FoodRecentItem(logItemID: try LedgerID(String(format: "00000000-0000-0000-0000-%012x", 500 + number)),
                sourceReleaseID: try ExternalIdentifier("fixture:release"), recordID: try ExternalIdentifier("fixture:\(number)"),
                occurredAt: Date(timeIntervalSince1970: 1_791_800_000), lastAmount: try PositiveQuantity(value: 150, unit: .grams), energyKcal: 90),
                name: "Food \(number)", isEstimate: false, logItemVersionID: version, isPlainWater: water)
        }
        let items = [try recent(1, version: try id(5), water: false), try recent(2, version: try id(6), water: true),
                     try recent(3, version: nil, water: false)]
        XCTAssertEqual(FavouriteFromLoggedView.offered(items).map(\.name), ["Food 1"])
        XCTAssertEqual(FavouriteFromLoggedView.title, "From what you\u{2019}ve logged")
    }

    // MARK: Favourites screen (F)

    private struct Clock: LedgerClock { let value: Date; func now() -> Date { value } }
    private final class IDs: LedgerIDGenerating, @unchecked Sendable {
        private var value = 0
        func makeID<Tag>(_ tag: Tag.Type) throws -> LedgerID<Tag> {
            value += 1
            return try LedgerID(String(format: "00000000-0000-0000-0000-%012x", value))
        }
    }

    private func favourites() throws -> FavouritesService {
        let store = InMemoryFoodLedgerStore()
        let ids = IDs(), now = Date(timeIntervalSince1970: 1_791_800_000)
        let ledger = FoodLedgerService(actorID: try LedgerID("00000000-0000-0000-0000-00000000a000"), committer: store,
            clock: Clock(value: now), encoder: FoundationCanonicalJSONEncoder(), digester: SHA256Digester())
        let confirmations = FoodConfirmationService(ledger: ledger, reader: store, clock: Clock(value: now), ids: ids, digester: SHA256Digester())
        return try FavouritesService(ledger: ledger, reader: store, confirmations: confirmations, clock: Clock(value: now),
                                     ids: ids, digester: SHA256Digester())
    }

    func testWaterRemovalIsConfirmedAndWaterCanBeAddedBack() throws {
        let model = FavouritesViewModel(store: try favourites())
        model.reload()
        let water = try XCTUnwrap(model.today.first)
        XCTAssertEqual(water.item, .builtInWater)
        XCTAssertFalse(model.canAddWater)
        XCTAssertEqual(FavouritesViewModel.removalTitle(water), "Remove Water from quick add?")
        XCTAssertTrue(FavouritesViewModel.removalMessage(water).contains("Add Water to quick add"))
        XCTAssertTrue(FavouritesViewModel.removalMessage(water).hasPrefix("Water will no longer appear in quick add."))
        model.remove(water)
        XCTAssertTrue(model.today.isEmpty)
        XCTAssertTrue(model.canAddWater)
        XCTAssertEqual(FavouritesViewModel.addWaterTitle, "Add Water to quick add")
        model.addWater()
        XCTAssertNil(model.changeFailure)
        XCTAssertFalse(model.canAddWater)
        XCTAssertEqual(model.today.map(\.title), ["Water"])
        XCTAssertEqual(model.today.first?.detail, "250 mL · plain water")
        XCTAssertEqual(FavouritesViewModel.removalTitle(try XCTUnwrap(model.today.first)), "Remove Water from quick add?",
                       "the stored water favourite is confirmed the same way")
    }

    func testOtherFavouritesKeepTheGeneralRemovalText() throws {
        let version = try FavouriteVersion(favouriteVersionID: LedgerID("00000000-0000-0000-0000-000000000001"),
            favouriteID: LedgerID("00000000-0000-0000-0000-000000000001"), ordinal: VersionOrdinal(1),
            binding: .savedEntry(LedgerID("00000000-0000-0000-0000-000000000001")), label: LedgerText("Greek yoghurt"),
            defaultAmount: FavouriteAmount(value: 150, unit: .grams), state: .active, createdAt: Date(timeIntervalSince1970: 0))
        let row = FavouriteRow(id: "x", item: .favourite(version), title: "Greek yoghurt", detail: "150 g", isUnverifiable: false)
        XCTAssertEqual(FavouritesViewModel.removalTitle(row), "Remove this favourite?")
        XCTAssertEqual(FavouritesViewModel.removalMessage(row), "Entries you have already logged stay in your Food Log.")
        XCTAssertEqual(FavouritesView.logNowHeader, "Log now and save favourite")
    }
}
