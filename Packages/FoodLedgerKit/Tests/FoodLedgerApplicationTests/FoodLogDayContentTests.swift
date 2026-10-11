import Foundation
import FoodLedgerApplication
import FoodLedgerDomain
import XCTest

final class FoodLogDayContentTests: XCTestCase {
    private typealias F = FoodLogFixtures

    private func content(_ logs: [LogItemVersion], estimates: Set<LogItemID> = []) throws -> FoodLogDayContent {
        var records = try F.records()
        records.logItemVersions = logs
        let projection = try FoodIntakeProjection(records: records, reportingDate: F.day)
        return FoodLogDayContent(projection: projection, reportingDate: F.day, estimates: estimates)
    }

    func testStripHasFourNutrientsAndNeverWater() throws {
        let day = try content([F.log(800, version: 801, product: 13, resolution: 15)])
        XCTAssertEqual(FoodLogDayContent.stripKeys, [.energyConsumed, .protein, .carbohydrates, .fatTotal])
        XCTAssertEqual(try XCTUnwrap(day.totals).map(\.key), FoodLogDayContent.stripKeys)
        XCTAssertFalse(FoodLogDayContent.stripKeys.contains(.water))
    }

    func testKnownMinimumWhenOneEntryLacksANutrientAndUnknownWhenNoneHasIt() throws {
        let day = try content([
            F.log(800, version: 801, product: 13, resolution: 15, occurredAt: F.date),
            F.log(810, version: 811, occurredAt: F.date.addingTimeInterval(60))
        ])
        let totals = try XCTUnwrap(day.totals)
        let fat = try XCTUnwrap(totals.first { $0.key == .fatTotal })
        XCTAssertEqual(fat.knownAmount, 7.5)
        XCTAssertEqual(fat.incompleteContributions, 1, "a known minimum")
        let protein = try XCTUnwrap(totals.first { $0.key == .protein })
        XCTAssertEqual(protein.knownAmount, 30)
        XCTAssertEqual(protein.incompleteContributions, 0)

        let unknownFat = try content([F.log(810, version: 811)])
        XCTAssertNil(try XCTUnwrap(unknownFat.totals).first { $0.key == .fatTotal }?.knownAmount, "unknown, never zero")
    }

    func testEmptyDayHasNoTotals() throws {
        let day = try content([])
        XCTAssertNil(day.totals)
        XCTAssertTrue(day.entries.isEmpty)
        XCTAssertTrue(day.removed.isEmpty)
    }

    func testRemovedOnlyDayHasNoTotalsAndListsRemovedRowsWithRemovalTime() throws {
        let removedAt = F.date.addingTimeInterval(3600)
        let day = try content([
            F.log(800, version: 801),
            F.log(800, version: 802, ordinal: 2, supersedes: 801, removed: 801, createdAt: removedAt)
        ])
        XCTAssertNil(day.totals)
        XCTAssertTrue(day.entries.isEmpty)
        XCTAssertEqual(day.removed.count, 1)
        XCTAssertEqual(day.removed.first?.removedAt, removedAt)
        XCTAssertEqual(day.removed.first?.name, "Fixture food")
    }

    func testRemovedRowsAreListedButExcludedFromTotals() throws {
        let day = try content([
            F.log(800, version: 801, product: 13, resolution: 15),
            F.log(810, version: 811),
            F.log(810, version: 812, ordinal: 2, supersedes: 811, removed: 811)
        ])
        XCTAssertEqual(day.entries.map(\.name), ["Oats"])
        XCTAssertEqual(day.removed.map(\.name), ["Fixture food"])
        XCTAssertEqual(try XCTUnwrap(day.totals).first { $0.key == .protein }?.knownAmount, 15)
    }

    func testPerEntryUnknownKeysEstimateAndEnergy() throws {
        let estimateID: LogItemID = try F.id(810, LogItemTag.self)
        let day = try content([
            F.log(800, version: 801, product: 13, resolution: 15),
            F.log(810, version: 811, occurredAt: F.date.addingTimeInterval(60)),
            F.log(820, version: 821, unit: .millilitres, occurredAt: F.date.addingTimeInterval(120))
        ], estimates: [estimateID])
        XCTAssertEqual(day.entries[0].unknownKeys, [])
        XCTAssertEqual(day.entries[0].energyKcal, 300)
        XCTAssertFalse(day.entries[0].isEstimate)
        XCTAssertEqual(day.entries[1].unknownKeys, [.fatTotal])
        XCTAssertTrue(day.entries[1].isEstimate)
        // mL against per 100 g cannot be scaled: every strip nutrient is unknown, energy included.
        XCTAssertEqual(day.entries[2].unknownKeys, FoodLogDayContent.stripKeys)
        XCTAssertNil(day.entries[2].energyKcal)
        let energy = try XCTUnwrap(day.totals?.first { $0.key == .energyConsumed })
        XCTAssertEqual(energy.incompleteContributions, 1)
    }

    func testEntriesOrderByTimeThenLogItemID() throws {
        let day = try content([
            F.log(820, version: 821, occurredAt: F.date),
            F.log(800, version: 801, product: 13, resolution: 15, occurredAt: F.date.addingTimeInterval(60)),
            F.log(810, version: 811, occurredAt: F.date)
        ])
        XCTAssertEqual(day.entries.map(\.logItemID.rawValue), [
            try F.id(810, LogItemTag.self).rawValue, try F.id(820, LogItemTag.self).rawValue, try F.id(800, LogItemTag.self).rawValue
        ])
    }
}
