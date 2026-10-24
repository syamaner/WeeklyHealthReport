import FoodLedgerDomain
import XCTest

/// Pasted nutrition label v1, PR 2 domain contract tests (`docs/pasted-nutrition-label-v1.md`
/// section 8.4): tests 29 (aggregation) and 47 (derivation predicate), and the
/// `pasted-label-identity-v1` constants.
final class PastedLabelDomainTests: XCTestCase {
    private static let releaseID = "pasted-label:" + String(repeating: "a", count: 64)

    private func transform(_ id: String, _ version: String) throws -> NutrientTransform {
        NutrientTransform(transformID: try LedgerText(id), transformVersion: try LedgerText(version))
    }

    private func provenance(_ kind: ProvenanceSourceKind, transforms: [NutrientTransform] = []) throws -> NutrientProvenance {
        NutrientProvenance(sourceKind: kind, sourceID: try ExternalIdentifier("pasted-nutrition-label"),
                           sourceReleaseID: try ExternalIdentifier(Self.releaseID), transforms: transforms)
    }

    /// Energy 370.5 kcal per 100 g: printed, calculated from 1550 kJ, or corrected by the user.
    private func energy(_ origin: String) throws -> NutrientSet {
        let value: ExactNutrientValue
        switch origin {
        case "calculated":
            value = try ExactNutrientValue(amount: 370.5, unit: .kilocalories,
                sourceValue: .exact(SourceExactNutrientValue(amount: 1550, unit: LedgerText("kJ"), basis: .per100Grams)),
                provenance: [provenance(.userVerifiedPanel, transforms: [transform("kj_to_kcal_v1", "pasted-label-conversions-v1")])])
        case "corrected":
            value = try ExactNutrientValue(amount: 370.5, unit: .kilocalories,
                sourceValue: .exact(SourceExactNutrientValue(amount: 370.5, unit: LedgerText("kcal"), basis: .per100Grams)),
                provenance: [provenance(.manualDeclaration)])
        default:
            value = try ExactNutrientValue(amount: 370.5, unit: .kilocalories,
                sourceValue: .exact(SourceExactNutrientValue(amount: 370.5, unit: LedgerText("kcal"), basis: .per100Grams)),
                provenance: [provenance(.userVerifiedPanel)])
        }
        return try NutrientSet(entries: NutrientKey.allCases.map {
            try NutrientEntry(key: $0, value: $0 == .energyConsumed ? .measured(value) : .unknown(.notDeclared))
        })
    }

    private func day(_ origins: [String]) throws -> FoodIntakeTotal {
        let contributions = try origins.map {
            FoodIntakeContribution(quantity: try PositiveQuantity(value: 200, unit: .grams), basis: .per100Grams, nutrients: try energy($0))
        }
        return try XCTUnwrap(FoodIntakeSummary(contributions: contributions).totals.first { $0.key == .energyConsumed })
    }

    // MARK: 47. Derivation predicate

    func test47CalculatedTransformIsTrueForExactlyTheTwoAllowListedPairs() throws {
        XCTAssertEqual(NutrientDerivation.calculatedTransforms, [
            .init(transformID: "kj_to_kcal_v1", transformVersion: "pasted-label-conversions-v1"),
            .init(transformID: "salt_to_sodium_v1", transformVersion: "pasted-label-conversions-v1")
        ], "The append-only v1 entries are pinned")
        XCTAssertTrue(NutrientDerivation.calculatedTransform(try transform("kj_to_kcal_v1", "pasted-label-conversions-v1")))
        XCTAssertTrue(NutrientDerivation.calculatedTransform(try transform("salt_to_sodium_v1", "pasted-label-conversions-v1")))
        for (id, version) in [("mass-g-to-mg", "v1"), ("kj_to_kcal_v1", "v1"), ("salt_to_sodium_v1", "pasted-label-conversions-v2"),
                              ("kj_to_kcal_v2", "pasted-label-conversions-v1"), ("mass-g-to-mg", "pasted-label-conversions-v1"),
                              ("KJ_TO_KCAL_V1", "pasted-label-conversions-v1")] {
            XCTAssertFalse(NutrientDerivation.calculatedTransform(try transform(id, version)), "\(id) \(version)")
        }
        // An allow-listed pair that also names a quantity conversion is not an approved shape.
        let withConversion = NutrientTransform(transformID: try LedgerText("kj_to_kcal_v1"),
            transformVersion: try LedgerText("pasted-label-conversions-v1"),
            quantityConversionVersionID: try QuantityConversionVersionID("00000000-0000-0000-0000-000000000001"))
        XCTAssertFalse(NutrientDerivation.calculatedTransform(withConversion))
        XCTAssertTrue(NutrientDerivation.isCalculated(try energy("calculated").entries[0].value))
        XCTAssertFalse(NutrientDerivation.isCalculated(try energy("printed").entries[0].value))
        XCTAssertFalse(NutrientDerivation.isCalculated(try energy("corrected").entries[0].value))
        XCTAssertFalse(NutrientDerivation.isCalculated(.unknown(.notDeclared)))
    }

    // MARK: 29. Aggregation (food-intake-summary-v3 rule, pinned at v4 since #287)

    func test29SummaryVersionGolden() {
        XCTAssertEqual(FoodIntakeSummary.version, "food-intake-summary-v4")
    }

    func test29CalculatedContributionSetsIncludesEstimates() throws {
        let total = try day(["printed", "calculated"])
        XCTAssertTrue(total.includesEstimates)
        XCTAssertEqual(total.knownAmount, 1482)
        XCTAssertEqual(total.incompleteContributions, 0)
    }

    func test29PrintedOnlyDayIsUnchanged() throws {
        let total = try day(["printed", "printed"])
        XCTAssertEqual(total, FoodIntakeTotal(key: .energyConsumed, knownAmount: 1482, incompleteContributions: 0, includesEstimates: false))
    }

    func test29CorrectedAndEnteredValuesDoNotSetIncludesEstimates() throws {
        // Decision 13: user-asserted values are shown per value, not flagged as estimates.
        XCTAssertFalse(try day(["corrected", "printed"]).includesEstimates)
    }

    func test29UnitTransformThatIsNotACalculationDoesNotSetIncludesEstimates() throws {
        let value = try ExactNutrientValue(amount: 400, unit: .milligrams,
            sourceValue: .exact(SourceExactNutrientValue(amount: 0.4, unit: LedgerText("g"), basis: .per100Grams)),
            provenance: [NutrientProvenance(sourceKind: .exactProductDataset, sourceID: ExternalIdentifier("open_food_facts"),
                sourceReleaseID: ExternalIdentifier("off:v1"), recordID: ExternalIdentifier("1"), transforms: [transform("mass-g-to-mg", "v1")])])
        let set = try NutrientSet(entries: NutrientKey.allCases.map {
            try NutrientEntry(key: $0, value: $0 == .sodium ? .measured(value) : .unknown(.notDeclared))
        })
        let sodium = FoodIntakeSummary(contributions: [FoodIntakeContribution(
            quantity: try PositiveQuantity(value: 100, unit: .grams), basis: .per100Grams, nutrients: set)]).totals.first { $0.key == .sodium }
        XCTAssertEqual(sodium?.knownAmount, 400)
        XCTAssertEqual(sodium?.includesEstimates, false)
    }

    func test29CalculatedBoundStaysAKnownMinimum() throws {
        let bound = try NutrientBounds(lower: nil, upper: 4, lowerClosed: false, upperClosed: false, origin: .measured, unit: .milligrams,
            sourceValue: .bounded(SourceBoundedNutrientValue(lower: nil, upper: 0.01, lowerClosed: false, upperClosed: false,
                unit: LedgerText("g_salt"), basis: .per100Grams)),
            provenance: [provenance(.userVerifiedPanel, transforms: [transform("salt_to_sodium_v1", "pasted-label-conversions-v1")])])
        let set = try NutrientSet(entries: NutrientKey.allCases.map {
            try NutrientEntry(key: $0, value: $0 == .sodium ? .bounded(bound) : .unknown(.notDeclared))
        })
        let sodium = FoodIntakeSummary(contributions: [FoodIntakeContribution(
            quantity: try PositiveQuantity(value: 100, unit: .grams), basis: .per100Grams, nutrients: set)]).totals.first { $0.key == .sodium }
        XCTAssertNil(sodium?.knownAmount, "A bound is never an exact total")
        XCTAssertEqual(sodium?.incompleteContributions, 1)
    }

    // MARK: pasted-label-identity-v1

    func testIdentityMappingConstantsAreExactlyAsApproved() throws {
        XCTAssertEqual(PastedLabelIdentity.version, "pasted-label-identity-v1")
        XCTAssertEqual(PastedLabelIdentity.basisStateNotSupported, "basis_state_not_supported")
        let basis = ResolutionBasis.per100Grams
        for (answer, fortification, itemClass) in [(PastedLabelIdentity.FortificationAnswer.yes, FortificationState.fortified, ItemClass.fortifiedFood),
                                                   (.no, .unfortified, .food), (.unanswered, .unknown, .food)] {
            let identity = try PastedLabelIdentity.identity(fortification: answer, servingBasis: basis)
            XCTAssertEqual(identity.preparation, try PreparationState(kind: .asSold))
            XCTAssertEqual(identity.bone, .notApplicable)
            XCTAssertEqual(identity.skin, .notApplicable)
            XCTAssertEqual(identity.drained, .notApplicable)
            XCTAssertEqual(identity.packingMedium, .named(try LedgerText("as sold")))
            XCTAssertEqual(identity.fortification, fortification)
            XCTAssertEqual(identity.declaredFortificants, [])
            XCTAssertEqual(identity.servingBasis, basis)
            XCTAssertEqual(PastedLabelIdentity.itemClass(answer), itemClass)
        }
        let serving = ResolutionBasis.perServing(try PositiveQuantity(value: 30, unit: .grams))
        XCTAssertEqual(try PastedLabelIdentity.identity(fortification: .no, servingBasis: serving).servingBasis, serving)
    }

    func testIdentityMappingLeavesOnlyFortificationOpenWhenUnanswered() throws {
        let expected = try PastedLabelIdentity.identity(fortification: .unanswered, servingBasis: .per100Grams)
        XCTAssertEqual(IdentityCompatibility.contradictions(between: expected, and: expected, expectedEdibleQuantity: .unknown, candidateEdibleQuantity: .unknown)
            .filter { $0 != .edibleQuantity }, [.fortification])
        let answered = try PastedLabelIdentity.identity(fortification: .no, servingBasis: .per100Grams)
        XCTAssertEqual(IdentityCompatibility.contradictions(between: answered, and: answered, expectedEdibleQuantity: .unknown, candidateEdibleQuantity: .unknown)
            .filter { $0 != .edibleQuantity }, [])
    }
}
