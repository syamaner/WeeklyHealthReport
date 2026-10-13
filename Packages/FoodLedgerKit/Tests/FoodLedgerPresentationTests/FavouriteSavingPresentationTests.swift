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

        func saveFavourite(logItemVersionID: LogItemVersionID) throws -> FavouriteVersion {
            saves += 1
            if failures > 0 { failures -= 1; throw FoodLedgerStoreError.integrityFailure("synthetic") }
            active.insert(logItemVersionID)
            return try XCTUnwrap(projection().activeFavourite(boundTo: logItemVersionID))
        }
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
