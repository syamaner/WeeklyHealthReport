import FoodLedgerDomain
import XCTest

/// `isScalable` exposes the summary's existing predicate (#197) without changing its outputs.
final class FoodIntakeScalingPredicateTests: XCTestCase {
    private func nutrients() throws -> NutrientSet {
        let value = try ExactNutrientValue(amount: 10, unit: .grams,
            sourceValue: .exact(SourceExactNutrientValue(amount: 10, unit: LedgerText("g"), basis: .per100Grams)),
            provenance: [NutrientProvenance(sourceKind: .exactProductDataset, sourceID: ExternalIdentifier("synthetic"),
                sourceReleaseID: ExternalIdentifier("synthetic:v1"), recordID: ExternalIdentifier("test"))])
        return try NutrientSet(entries: NutrientKey.allCases.map {
            try NutrientEntry(key: $0, value: $0 == .protein ? .measured(value) : .unknown(.notDeclared))
        })
    }

    func testPredicateAgreesWithTheSummaryForEveryBasisAndUnit() throws {
        let set = try nutrients()
        let bases: [ResolutionBasis] = [.per100Grams, .per100Millilitres,
            .perServing(try PositiveQuantity(value: 30, unit: .grams)), .perUnit(try PositiveQuantity(value: 1, unit: .count)),
            .named(try LedgerText("slice"), try PositiveQuantity(value: 40, unit: .grams)), .unknown]
        for basis in bases {
            for unit in [QuantityUnit.grams, .millilitres, .count] {
                let contribution = FoodIntakeContribution(quantity: try PositiveQuantity(value: 50, unit: unit), basis: basis, nutrients: set)
                let protein = FoodIntakeSummary(contributions: [contribution]).totals.first { $0.key == .protein }
                XCTAssertEqual(contribution.isScalable, protein?.knownAmount != nil, "\(basis) \(unit)")
            }
        }
    }

    func testUnitMismatchAndUnknownBasisAreBothKnownMinimumsInADayTotal() throws {
        let set = try nutrients()
        let mismatch = FoodIntakeContribution(quantity: try PositiveQuantity(value: 200, unit: .millilitres), basis: .per100Grams, nutrients: set)
        let unknown = FoodIntakeContribution(quantity: try PositiveQuantity(value: 200, unit: .grams), basis: .unknown, nutrients: set)
        let known = FoodIntakeContribution(quantity: try PositiveQuantity(value: 100, unit: .grams), basis: .per100Grams, nutrients: set)
        XCTAssertFalse(mismatch.isScalable)
        XCTAssertFalse(unknown.isScalable)
        let protein = try XCTUnwrap(FoodIntakeSummary(contributions: [known, mismatch, unknown]).totals.first { $0.key == .protein })
        XCTAssertEqual(protein.knownAmount, 10)
        XCTAssertEqual(protein.incompleteContributions, 2)
        XCTAssertEqual(FoodIntakeSummary.version, "food-intake-summary-v3")
    }
}
