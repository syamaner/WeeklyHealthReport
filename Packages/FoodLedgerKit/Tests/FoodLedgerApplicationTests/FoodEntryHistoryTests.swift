import Foundation
import FoodLedgerApplication
import FoodLedgerDomain
import XCTest

final class FoodEntryHistoryTests: XCTestCase {
    private typealias F = FoodLogFixtures

    private func q(_ value: Double, _ unit: QuantityUnit = .grams) throws -> PositiveQuantity {
        try PositiveQuantity(value: value, unit: unit)
    }

    private func at(_ minutes: Double) -> Date { F.date.addingTimeInterval(minutes * 60) }

    func testLoggedThenAmountChangedNewestFirst() throws {
        let events = FoodEntryHistory.events(versions: [
            try F.log(800, version: 801, value: 120, createdAt: at(0)),
            try F.log(800, version: 802, ordinal: 2, supersedes: 801, value: 150, createdAt: at(5))
        ], conversions: [])
        XCTAssertEqual(events.map(\.at), [at(5), at(0)])
        XCTAssertEqual(events.last?.kind, .logged)
        XCTAssertEqual(events.first?.kind, .changed(amount: .init(from: try q(120), to: try q(150), edibleFrom: nil, edibleTo: nil), time: nil))
    }

    func testTimeChangedAndAmountAndTimeTogether() throws {
        let events = FoodEntryHistory.events(versions: [
            try F.log(800, version: 801, occurredAt: at(0)),
            try F.log(800, version: 802, ordinal: 2, supersedes: 801, occurredAt: at(30)),
            try F.log(800, version: 803, ordinal: 3, supersedes: 802, value: 200, occurredAt: at(40))
        ], conversions: [])
        XCTAssertEqual(events[1].kind, .changed(amount: nil, time: .init(from: at(0), to: at(30))))
        XCTAssertEqual(events[0].kind, .changed(amount: .init(from: try q(150), to: try q(200), edibleFrom: nil, edibleTo: nil),
                                                time: .init(from: at(30), to: at(40))))
    }

    func testConvertedAmountUsesConversionSourceQuantities() throws {
        let first = try QuantityConversionVersion(quantityConversionVersionID: F.id(901, QuantityConversionVersionTag.self),
            ordinal: VersionOrdinal(1), sourceQuantity: q(1, .count), convertedQuantity: q(240, .millilitres),
            methodVersion: LedgerText("fixture"), sourceReleaseID: nil, evidenceID: nil, createdAt: F.date)
        let second = try QuantityConversionVersion(quantityConversionVersionID: F.id(902, QuantityConversionVersionTag.self),
            ordinal: VersionOrdinal(2), supersedesQuantityConversionVersionID: first.quantityConversionVersionID,
            sourceQuantity: q(2, .count), convertedQuantity: q(480, .millilitres),
            methodVersion: LedgerText("fixture"), sourceReleaseID: nil, evidenceID: nil, createdAt: F.date)
        let events = FoodEntryHistory.events(versions: [
            try F.log(800, version: 801, value: 240, unit: .millilitres, conversion: 901),
            try F.log(800, version: 802, ordinal: 2, supersedes: 801, value: 480, unit: .millilitres, conversion: 902)
        ], conversions: [first, second])
        XCTAssertEqual(events[0].kind, .changed(amount: .init(from: try q(1, .count), to: try q(2, .count),
            edibleFrom: try q(240, .millilitres), edibleTo: try q(480, .millilitres)), time: nil))
    }

    func testCorrectionWithQuantityChangeIsOneCorrectedEvent() throws {
        let events = FoodEntryHistory.events(versions: [
            try F.log(800, version: 801),
            try F.log(800, version: 802, ordinal: 2, supersedes: 801, product: 13, resolution: 15, value: 100)
        ], conversions: [])
        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(events[0].kind, .corrected(amount: .init(from: try q(150), to: try q(100), edibleFrom: nil, edibleTo: nil), time: nil))
    }

    func testReresolutionIsNutritionUpdated() throws {
        let events = FoodEntryHistory.events(versions: [
            try F.log(800, version: 801),
            try F.log(800, version: 802, ordinal: 2, supersedes: 801, resolution: 15)
        ], conversions: [])
        XCTAssertEqual(events[0].kind, .nutritionUpdated)
    }

    func testRemovedRestoredThenEdited() throws {
        let events = FoodEntryHistory.events(versions: [
            try F.log(800, version: 801),
            try F.log(800, version: 802, ordinal: 2, supersedes: 801, removed: 801),
            try F.log(800, version: 803, ordinal: 3, supersedes: 802),
            try F.log(800, version: 804, ordinal: 4, supersedes: 803, value: 175)
        ], conversions: [])
        XCTAssertEqual(events.map(\.kind), [
            .changed(amount: .init(from: try q(150), to: try q(175), edibleFrom: nil, edibleTo: nil), time: nil),
            .restored, .removed, .logged
        ])
    }

    /// Classification is structural: a reason claiming a removal does not make one.
    func testMisleadingCorrectionReasonIsIgnored() throws {
        let original = try F.log(800, version: 801)
        let edited = try LogItemVersion(logItemVersionID: F.id(802, LogItemVersionTag.self), logItemID: original.logItemID,
            ordinal: VersionOrdinal(2), supersedesLogItemVersionID: original.logItemVersionID, occurredAt: original.occurredAt,
            reportingDate: original.reportingDate, composition: original.composition, edibleQuantity: q(160),
            originalResolutionVersionID: original.originalResolutionVersionID,
            effectiveResolutionVersionID: original.effectiveResolutionVersionID,
            correctionReason: LedgerText("Removed by user from Food Log"), createdAt: F.date)
        let events = FoodEntryHistory.events(versions: [original, edited], conversions: [])
        XCTAssertEqual(events[0].kind, .changed(amount: .init(from: try q(150), to: try q(160), edibleFrom: nil, edibleTo: nil), time: nil))
    }
}
