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

    /// v4 (#287): an overflow keeps v3's amount and incomplete count and adds only the flag.
    func testOverflowSetsTheV4FlagAndKeepsTheV3Fields() throws {
        let large = FoodIntakeContribution(
            quantity: try PositiveQuantity(value: Double.greatestFiniteMagnitude, unit: .grams),
            basis: .per100Grams, nutrients: try nutrients(Double.greatestFiniteMagnitude))
        let small = FoodIntakeContribution(
            quantity: try PositiveQuantity(value: 100, unit: .grams), basis: .per100Grams, nutrients: try nutrients(8))
        let protein = try XCTUnwrap(FoodIntakeSummary(contributions: [small, large]).totals.first { $0.key == .protein })
        XCTAssertEqual(protein, FoodIntakeTotal(key: .protein, knownAmount: nil, incompleteContributions: 2,
                                                includesEstimates: true, overflowed: true),
                       "the fixture's protein is augmented, so the v3 estimate flag stays set")
        XCTAssertEqual(FoodIntakeSummary.version, "food-intake-summary-v6")
    }

    func testNothingKnownIsNotAnOverflow() throws {
        let empty = FoodIntakeSummary(contributions: [])
        XCTAssertTrue(empty.totals.allSatisfy { !$0.overflowed && $0.knownAmount == nil && $0.incompleteContributions == 0 })
        let unknownBasis = FoodIntakeSummary(contributions: [FoodIntakeContribution(
            quantity: try PositiveQuantity(value: 100, unit: .grams), basis: .unknown, nutrients: try nutrients(8))])
        let protein = try XCTUnwrap(unknownBasis.totals.first { $0.key == .protein })
        XCTAssertFalse(protein.overflowed)
        XCTAssertNil(protein.knownAmount)
        XCTAssertEqual(protein.incompleteContributions, 1)
    }

    // MARK: v5 (#304): plain water makes no nutrient known

    /// Synthetic plain water as the reference defines it: water 100 mL and the macros exactly 0
    /// per 100 mL, sodium (a mineral) unknown.
    private func water(_ millilitres: Double, unit: QuantityUnit = .millilitres) throws -> FoodIntakeContribution {
        let provenance = NutrientProvenance(sourceKind: .appReferenceDefinition, sourceID: try ExternalIdentifier("synthetic.reference"),
                                            sourceReleaseID: try ExternalIdentifier("synthetic.reference:water-v1"),
                                            recordID: try ExternalIdentifier("water"))
        let exact: [NutrientKey: Double] = [.water: 100, .energyConsumed: 0, .protein: 0, .carbohydrates: 0, .fatTotal: 0, .fiber: 0]
        let set = try NutrientSet(entries: NutrientKey.allCases.map { key in
            guard let amount = exact[key] else { return try NutrientEntry(key: key, value: .unknown(.notDeclared)) }
            return try NutrientEntry(key: key, value: .measured(ExactNutrientValue(amount: amount, unit: key.canonicalUnit,
                sourceValue: .exact(SourceExactNutrientValue(amount: amount, unit: LedgerText(key.canonicalUnit.rawValue), basis: .per100Millilitres)),
                provenance: [provenance])))
        })
        return FoodIntakeContribution(quantity: try PositiveQuantity(value: millilitres, unit: unit), basis: .per100Millilitres,
                                      nutrients: set, isPlainWater: true)
    }

    /// A food with energy 200 kcal and protein 10 g per 100 g and every other nutrient unknown.
    private func food(_ grams: Double, quantityIsEstimate: Bool = false) throws -> FoodIntakeContribution {
        let provenance = NutrientProvenance(sourceKind: .manualDeclaration, sourceID: try ExternalIdentifier("synthetic"),
                                            sourceReleaseID: try ExternalIdentifier("synthetic:v1"))
        let set = try NutrientSet(entries: NutrientKey.allCases.map { key in
            let known: [NutrientKey: Double] = [.energyConsumed: 200, .protein: 10]
            guard let amount = known[key] else { return try NutrientEntry(key: key, value: .unknown(.notDeclared)) }
            return try NutrientEntry(key: key, value: .measured(ExactNutrientValue(amount: amount, unit: key.canonicalUnit,
                sourceValue: .exact(SourceExactNutrientValue(amount: amount, unit: LedgerText(key.canonicalUnit.rawValue), basis: .per100Grams)),
                provenance: [provenance])))
        })
        return FoodIntakeContribution(quantity: try PositiveQuantity(value: grams, unit: .grams), basis: .per100Grams,
                                      nutrients: set, quantityIsEstimate: quantityIsEstimate)
    }

    private func total(_ summary: FoodIntakeSummary, _ key: NutrientKey) throws -> FoodIntakeTotal {
        try XCTUnwrap(summary.totals.first { $0.key == key })
    }

    /// The #304 journey: a food whose carbohydrates are unknown, then 250 mL water. Carbohydrates
    /// stay unknown (never "0 g+"), and water is not a food entry.
    func testWaterNeverMakesAnUnknownNutrientKnownOrZero() throws {
        let summary = FoodIntakeSummary(contributions: [try food(150, quantityIsEstimate: true), try water(250)])
        for key in [NutrientKey.carbohydrates, .fatTotal, .fiber] {
            let total = try total(summary, key)
            XCTAssertNil(total.knownAmount, "\(key) stays unknown")
            XCTAssertEqual(total.incompleteContributions, 1, "\(key): only the food is incomplete")
        }
        XCTAssertEqual(summary.itemCount, 2)
        XCTAssertEqual(summary.foodItemCount, 1, "plain water is not a food entry")
        XCTAssertEqual(try total(summary, .water).knownAmount, 250, "the water nutrient still includes plain water")
    }

    func testKnownFoodPlusWaterKeepsTheKnownTotalUnchanged() throws {
        let alone = FoodIntakeSummary(contributions: [try food(150)])
        let withWater = FoodIntakeSummary(contributions: [try food(150), try water(250)])
        for key in [NutrientKey.energyConsumed, .protein, .carbohydrates] {
            XCTAssertEqual(try total(withWater, key), try total(alone, key), "\(key)")
        }
        XCTAssertEqual(try total(withWater, .energyConsumed).knownAmount, 300)
        XCTAssertEqual(try total(withWater, .energyConsumed).incompleteContributions, 0)
        let sodium = try total(withWater, .sodium)
        XCTAssertNil(sodium.knownAmount)
        XCTAssertEqual(sodium.incompleteContributions, 2, "water's unknown minerals stay incomplete (Q1)")
    }

    func testWaterOnlyDayHasNoKnownNutrientAndNoFoodEntry() throws {
        let summary = FoodIntakeSummary(contributions: [try water(250), try water(500, unit: .grams)])
        XCTAssertEqual(summary.itemCount, 2)
        XCTAssertEqual(summary.foodItemCount, 0)
        for key in [NutrientKey.energyConsumed, .protein, .carbohydrates, .fatTotal, .fiber] {
            let total = try total(summary, key)
            XCTAssertNil(total.knownAmount, "\(key) is not 0 on a water-only day")
            XCTAssertEqual(total.incompleteContributions, 0, "\(key): water is no contribution, even unscalable")
            XCTAssertFalse(total.includesEstimates)
        }
        let water = try total(summary, .water)
        XCTAssertEqual(water.knownAmount, 250)
        XCTAssertEqual(water.incompleteContributions, 1, "water edited to grams cannot be scaled")
        XCTAssertEqual(try total(summary, .sodium).incompleteContributions, 2)
    }

    /// Only the day aggregation reads the flag: a plain water entry on its own still states 0 kcal.
    func testUnflaggedWaterEntryKeepsItsOwnExactZeros() throws {
        let entry = try water(250)
        let unflagged = FoodIntakeContribution(quantity: entry.quantity, basis: entry.basis, nutrients: entry.nutrients)
        let summary = FoodIntakeSummary(contributions: [unflagged])
        XCTAssertEqual(try total(summary, .energyConsumed).knownAmount, 0)
        XCTAssertEqual(summary.foodItemCount, 1)
    }
}
