import FoodLedgerDomain
import XCTest

final class FoodQuantityValidationTests: XCTestCase {
    func testCountRequiresExactImmutableConversion() throws {
        let count = try PositiveQuantity(value: 2, unit: .count)
        XCTAssertThrowsError(try FoodQuantityCalculator.direct(entered: count, conversion: nil)) {
            XCTAssertEqual($0 as? FoodQuantityValidationError, .missingConversion)
        }
        let conversion = try QuantityConversionVersion(
            quantityConversionVersionID: id(1, QuantityConversionVersionTag.self),
            ordinal: VersionOrdinal(1),
            sourceQuantity: count,
            convertedQuantity: PositiveQuantity(value: 80, unit: .grams),
            methodVersion: LedgerText("slice_weight_v1"),
            createdAt: Date(timeIntervalSince1970: 1)
        )
        XCTAssertEqual(
            try FoodQuantityCalculator.direct(entered: count, conversion: conversion),
            try PositiveQuantity(value: 80, unit: .grams)
        )
    }

    func testPlateSubtractionRejectsMissingInvalidAndNonPositiveWeights() throws {
        let total = try PositiveQuantity(value: 100, unit: .grams)
        XCTAssertThrowsError(try FoodQuantityCalculator.subtractPlate(total: total, emptyPlate: nil)) {
            XCTAssertEqual($0 as? FoodQuantityValidationError, .missingPlateWeight)
        }
        let plate = try PlateWeightVersion(
            plateWeightVersionID: id(2, PlateWeightVersionTag.self),
            plateID: id(3, PlateTag.self),
            ordinal: VersionOrdinal(1),
            emptyWeight: PositiveQuantity(value: 100, unit: .grams),
            createdAt: Date(timeIntervalSince1970: 1)
        )
        XCTAssertThrowsError(try FoodQuantityCalculator.subtractPlate(total: total, emptyPlate: plate)) {
            XCTAssertEqual($0 as? FoodQuantityValidationError, .nonPositiveEdibleQuantity)
        }
        XCTAssertThrowsError(try FoodQuantityCalculator.subtractPlate(
            total: PositiveQuantity(value: 120, unit: .millilitres),
            emptyPlate: plate
        )) {
            XCTAssertEqual($0 as? FoodQuantityValidationError, .invalidPlateUnit)
        }
    }

    private func id<Tag>(_ value: Int, _ tag: Tag.Type) throws -> LedgerID<Tag> {
        try LedgerID(String(format: "00000000-0000-0000-0000-%012x", value))
    }
}
