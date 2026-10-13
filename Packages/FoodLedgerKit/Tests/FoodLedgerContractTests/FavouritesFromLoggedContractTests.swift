import Foundation
import FoodLedgerApplication
import FoodLedgerDomain
import FoodLedgerTestSupport
import XCTest

/// Owner decisions A and F (13 October 2026), on the in-memory and GRDB stores: Save as favourite
/// from a saved entry or a recent food through the existing `save_favourite_v1` path, and the Q7
/// amendment's "Add Water to quick add" after the water item was removed.
final class FavouritesFromLoggedContractTests: XCTestCase {
    private func recents(_ context: QuickAddContext) throws -> [FoodRecentRelogItem] {
        FoodRecentItemsService(reader: context.harness.reader, confirmations: context.confirmations)
            .items(records: try context.records(), now: LedgerFixtures.clock.now(), calendar: QuickAddFixtures.london)
    }

    private func favouriteRecords(_ context: QuickAddContext) throws -> FavouriteMutation {
        try XCTUnwrap(context.harness.committer as? any FavouriteReading).favouriteRecords()
    }

    // MARK: A. Save as favourite from what was logged

    /// A recent food pins its current version: after a re-time the head moved, and the favourite
    /// binds the new head, not the original. Saving writes no log record and is idempotent.
    func testRecentFoodPinsTheCurrentVersionAndSavingIsIdempotent() throws {
        for context in try QuickAddFixtures.contexts() {
            defer { context.harness.cleanup() }
            let saved = try context.logExact(81)
            var state = try XCTUnwrap(context.confirmations.reopen(logItemID: saved.logItem.logItemID))
            FoodConfirmationReducer.reduce(state: &state, action: .setOccurredAt(LedgerFixtures.date.addingTimeInterval(-1_800)))
            let edited = try context.confirmations.save(state, operationID: context.ids.makeID(OperationTag.self))
            let recent = try XCTUnwrap(try recents(context).first, context.harness.name)
            XCTAssertEqual(recent.logItemVersionID, edited.logItemVersion.logItemVersionID, "the current version, not the original")
            XCTAssertNotEqual(recent.logItemVersionID, saved.logItemVersion.logItemVersionID)
            XCTAssertFalse(recent.isPlainWater)

            let logsBefore = try context.records().logItemVersions
            let operationsBefore = try context.operations().count
            let favourite = try context.favourites.saveFavourite(logItemVersionID: try XCTUnwrap(recent.logItemVersionID))
            XCTAssertEqual(favourite.binding, .savedEntry(edited.logItemVersion.logItemVersionID))
            XCTAssertEqual(try context.records().logItemVersions, logsBefore, "Saving a favourite writes no log record")
            XCTAssertEqual(try context.operations().count, operationsBefore + 1)
            XCTAssertEqual(try context.operations().last { $0.operationType == .saveFavourite }?.operationType, .saveFavourite)

            // Already a favourite: the projection says so and a repeat writes nothing.
            XCTAssertEqual(try context.favourites.projection().activeFavourite(boundTo: edited.logItemVersion.logItemVersionID), favourite)
            XCTAssertEqual(try context.favourites.saveFavourite(logItemVersionID: edited.logItemVersion.logItemVersionID), favourite)
            XCTAssertEqual(try context.operations().count, operationsBefore + 1, context.harness.name)
        }
    }

    /// A saved entry's detail carries the current version and whether it is plain water; a removal
    /// version is never pinned.
    func testSavedEntryDetailPinsTheCurrentProductVersionOnly() throws {
        for context in try QuickAddFixtures.contexts() {
            defer { context.harness.cleanup() }
            let saved = try context.logExact(82)
            let detail = SavedFoodEntryDetail(stored: try XCTUnwrap(context.harness.reader.foodConfirmation(logItemID: saved.logItem.logItemID)),
                                              isEstimate: false, history: [])
            XCTAssertEqual(detail.logItemVersionID, saved.logItemVersion.logItemVersionID)
            XCTAssertFalse(detail.isPlainWater)
            let water = try context.logWater(250)
            let waterDetail = SavedFoodEntryDetail(stored: try XCTUnwrap(context.harness.reader.foodConfirmation(logItemID: water.logItem.logItemID)),
                                                   isEstimate: false, history: [])
            XCTAssertTrue(waterDetail.isPlainWater, "plain water has its own quick add item")
            XCTAssertEqual(try recents(context).first { $0.item.logItemID == water.logItem.logItemID }?.isPlainWater, true)

            let removal = try context.management.remove(logItemID: saved.logItem.logItemID, expectedVersion: saved.logItemVersion.logItemVersionID,
                reason: LedgerText("Synthetic"), operationID: context.ids.makeID(OperationTag.self))
            XCTAssertNil(try context.harness.reader.foodConfirmation(logItemID: saved.logItem.logItemID), "a removed entry has no detail")
            XCTAssertFalse(try recents(context).contains { $0.item.logItemID == saved.logItem.logItemID }, "nor a recent row")
            XCTAssertThrowsError(try context.favourites.saveFavourite(logItemVersionID: removal.logItemVersionID), context.harness.name)
        }
    }

    // MARK: F. Add Water to quick add (Q7 amendment)

    func testAddWaterIsANoOpWhileWaterIsOffered() throws {
        for context in try QuickAddFixtures.contexts() {
            defer { context.harness.cleanup() }
            XCTAssertFalse(try context.favourites.projection().canAddWater, "the built-in item is shown")
            try context.favourites.addWaterToQuickAdd()
            XCTAssertEqual(try favouriteRecords(context), FavouriteMutation(), "nothing written while built in")
            try context.favourites.saveBuiltInWater(label: LedgerText("Water"), millilitres: 330)
            let records = try favouriteRecords(context)
            XCTAssertFalse(try context.favourites.projection().canAddWater, "an active water favourite exists")
            try context.favourites.addWaterToQuickAdd()
            XCTAssertEqual(try favouriteRecords(context), records, "nothing written while active \(context.harness.name)")
        }
    }

    /// Removing water and adding it back continues the one plain water chain with a new active
    /// version (revise_favourite_v1), keeping its label and amount; it can be removed and re-added
    /// again, and a repeat writes nothing. The built-in item stays hidden throughout.
    func testWaterCanBeReAddedAfterRemovalOnOneChain() throws {
        for context in try QuickAddFixtures.contexts() {
            defer { context.harness.cleanup() }
            try context.favourites.saveBuiltInWater(label: LedgerText("Big glass"), millilitres: 500)
            let water = try XCTUnwrap(context.favourites.projection().favourites.first)
            try context.favourites.remove(water.favouriteID)
            XCTAssertTrue(try context.favourites.projection().canAddWater, context.harness.name)
            XCTAssertFalse(try context.favourites.projection().showsBuiltInWater)

            let logsBefore = try context.records().logItemVersions
            try context.favourites.addWaterToQuickAdd()
            var projection = try context.favourites.projection()
            XCTAssertFalse(projection.canAddWater)
            XCTAssertFalse(projection.showsBuiltInWater, "no second Water item")
            XCTAssertEqual(projection.quickAddItems.count, 1)
            let readded = try XCTUnwrap(projection.favourites.first)
            XCTAssertEqual(readded.favouriteID, water.favouriteID, "the same chain")
            XCTAssertEqual(readded.ordinal.value, 3)
            XCTAssertEqual(readded.state, .active)
            XCTAssertEqual(readded.label.value, "Big glass")
            XCTAssertEqual(readded.defaultAmount, try FavouriteAmount(value: 500, unit: .millilitres))
            XCTAssertEqual(readded.binding, .reference(.plainWaterV1))
            XCTAssertEqual(try context.operations().last?.operationType, .reviseFavourite)
            XCTAssertEqual(try context.records().logItemVersions, logsBefore, "no log record")

            let records = try favouriteRecords(context)
            try context.favourites.addWaterToQuickAdd()
            XCTAssertEqual(try favouriteRecords(context), records, "a repeat writes nothing")
            XCTAssertEqual(records.favourites.count, 1, "never a second chain")

            try context.favourites.remove(water.favouriteID)
            try context.favourites.addWaterToQuickAdd()
            projection = try context.favourites.projection()
            XCTAssertEqual(projection.favourites.map(\.ordinal.value), [5])
            XCTAssertEqual(try favouriteRecords(context).favourites.count, 1, context.harness.name)
            // The built-in guards still hold: the built-in item cannot be saved, removed or arranged again.
            XCTAssertThrowsError(try context.favourites.removeBuiltInWater()) {
                XCTAssertEqual($0 as? FavouritesServiceError, .builtInWaterAlreadySaved)
            }
        }
    }

    /// Removing the built-in item directly (its first record is a removed version) can also be undone.
    func testRemovedBuiltInWaterCanBeAddedBack() throws {
        for context in try QuickAddFixtures.contexts() {
            defer { context.harness.cleanup() }
            try context.favourites.removeBuiltInWater()
            XCTAssertEqual(try context.favourites.projection().quickAddItems, [])
            XCTAssertTrue(try context.favourites.projection().canAddWater)
            try context.favourites.addWaterToQuickAdd()
            let projection = try context.favourites.projection()
            XCTAssertEqual(projection.favourites.map(\.label.value), [PlainWaterReference.name], context.harness.name)
            XCTAssertEqual(projection.favourites.first?.defaultAmount.value, QuickAddItem.builtInWaterMillilitres)
            XCTAssertEqual(projection.favourites.first?.supersedesFavouriteVersionID,
                           try favouriteRecords(context).favouriteVersions.first { $0.state == .removed }?.favouriteVersionID)
            // Quick add from the re-added item is the plain water reference, as before.
            let preparation = try context.favourites.prepare(try XCTUnwrap(projection.quickAddItems.first))
            XCTAssertTrue(preparation.isPlainWater)
        }
    }
}
