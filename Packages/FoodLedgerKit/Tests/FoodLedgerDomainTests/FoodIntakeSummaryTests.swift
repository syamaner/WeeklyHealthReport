import FoodLedgerDomain
import XCTest

final class FoodIntakeSummaryTests: XCTestCase {
    private func nutrients(_ amount: Double) throws -> NutrientSet {
        let value = try ExactNutrientValue(amount: amount, unit: .grams,
            sourceValue: .exact(SourceExactNutrientValue(amount: amount, unit: LedgerText("g"), basis: .per100Grams)),
            provenance: [NutrientProvenance(sourceKind: .exactProductDataset, sourceID: ExternalIdentifier("synthetic"), sourceReleaseID: ExternalIdentifier("synthetic:v1"), recordID: ExternalIdentifier("test"))])
        return try NutrientSet(entries: NutrientKey.allCases.map {
            try NutrientEntry(key: $0, value: $0 == .protein ? .augmented(value) : .unknown(.notDeclared))
        })
    }

    func testQuantityScalingAndUnknownContributionsNeverBecomeCompleteZero() throws {
        let summary = FoodIntakeSummary(contributions: [
            FoodIntakeContribution(quantity: try PositiveQuantity(value: 250, unit: .grams), basis: .per100Grams, nutrients: try nutrients(8)),
            FoodIntakeContribution(quantity: try PositiveQuantity(value: 100, unit: .grams), basis: .per100Grams, nutrients: nil)
        ])
        let protein = try XCTUnwrap(summary.totals.first { $0.key == .protein })
        XCTAssertEqual(protein.knownAmount, 20)
        XCTAssertEqual(protein.incompleteContributions, 1)
        XCTAssertTrue(protein.includesEstimates)
        let energy = try XCTUnwrap(summary.totals.first { $0.key == .energyConsumed })
        XCTAssertNil(energy.knownAmount)
        XCTAssertEqual(energy.incompleteContributions, 2)
    }

    func testEmptyAndIncompatibleUnitDaysRetainNoData() throws {
        XCTAssertEqual(FoodIntakeSummary(contributions: []).itemCount, 0)
        XCTAssertTrue(FoodIntakeSummary(contributions: []).totals.allSatisfy { $0.knownAmount == nil })
        let incompatible = FoodIntakeSummary(contributions: [FoodIntakeContribution(
            quantity: try PositiveQuantity(value: 250, unit: .millilitres), basis: .per100Grams, nutrients: try nutrients(8))])
        XCTAssertTrue(incompatible.totals.allSatisfy { $0.knownAmount == nil && $0.incompleteContributions == 1 })
    }

    func testBoundedContributionDoesNotBecomeAnExactTotal() throws {
        let bounds = try NutrientBounds(lower: 1, upper: 2, lowerClosed: true, upperClosed: true,
            origin: .measured, unit: .grams,
            sourceValue: .bounded(SourceBoundedNutrientValue(lower: 1, upper: 2, lowerClosed: true, upperClosed: true,
                unit: LedgerText("g"), basis: .per100Grams)),
            provenance: [NutrientProvenance(sourceKind: .manualDeclaration, sourceID: ExternalIdentifier("synthetic"), sourceReleaseID: ExternalIdentifier("synthetic:v1"))])
        let values = try NutrientSet(entries: NutrientKey.allCases.map {
            try NutrientEntry(key: $0, value: $0 == .protein ? .bounded(bounds) : .unknown(.notDeclared))
        })
        let total = FoodIntakeSummary(contributions: [FoodIntakeContribution(
            quantity: try PositiveQuantity(value: 100, unit: .grams), basis: .per100Grams, nutrients: values)])
            .totals.first { $0.key == .protein }
        XCTAssertNil(total?.knownAmount)
        XCTAssertEqual(total?.incompleteContributions, 1)
    }

    func testExplicitPortionBasisAndOverflowFailClosed() throws {
        let summary = FoodIntakeSummary(contributions: [FoodIntakeContribution(
            quantity: try PositiveQuantity(value: 150, unit: .grams),
            basis: .perServing(try PositiveQuantity(value: 50, unit: .grams)), nutrients: try nutrients(8))])
        XCTAssertEqual(summary.totals.first { $0.key == .protein }?.knownAmount, 24)
        let overflow = FoodIntakeSummary(contributions: [FoodIntakeContribution(
            quantity: try PositiveQuantity(value: Double.greatestFiniteMagnitude, unit: .grams),
            basis: .per100Grams, nutrients: try nutrients(Double.greatestFiniteMagnitude))])
        XCTAssertNil(overflow.totals.first { $0.key == .protein }?.knownAmount)
        XCTAssertEqual(overflow.totals.first { $0.key == .protein }?.incompleteContributions, 1)
    }
}
