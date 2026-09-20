import Foundation
import FoodLedgerDomain
import XCTest

final class DomainValidationTests: XCTestCase {
    func testCatalogueContainsExactlyThirtyNineOrderedKeys() {
        XCTAssertEqual(NutrientKey.allCases.count, 39)
        XCTAssertEqual(NutrientKey.allCases.first, .energyConsumed)
        XCTAssertEqual(NutrientKey.allCases.last, .caffeine)
    }

    func testQuantitiesRejectNonFiniteNonPositiveAndInvalidDecodedValues() throws {
        XCTAssertThrowsError(try PositiveQuantity(value: .infinity, unit: .grams))
        XCTAssertThrowsError(try PositiveQuantity(value: 0, unit: .grams))
        XCTAssertThrowsError(try NonNegativeQuantity(value: -1, unit: .millilitres))
        XCTAssertThrowsError(try JSONDecoder().decode(
            PositiveQuantity.self,
            from: Data(#"{"value":0,"unit":"g"}"#.utf8)
        ))
    }

    func testBoundsCannotBecomeExactOrMalformed() throws {
        let provenance = try makeProvenance()
        XCTAssertThrowsError(try NutrientBounds(
            lower: nil,
            upper: nil,
            lowerClosed: false,
            upperClosed: false,
            origin: .measured,
            unit: .grams,
            sourceValue: sourceBounds(lower: 0, upper: 1),
            provenance: [provenance]
        ))
        XCTAssertThrowsError(try NutrientBounds(
            lower: 1,
            upper: 1,
            lowerClosed: true,
            upperClosed: true,
            origin: .measured,
            unit: .grams,
            sourceValue: sourceBounds(lower: 0, upper: 1),
            provenance: [provenance]
        ))
        let bounded = try NutrientEntry(
            key: .sugar,
            value: .bounded(NutrientBounds(
                lower: 0,
                upper: 0.5,
                lowerClosed: true,
                upperClosed: false,
                origin: .measured,
                unit: .grams,
                sourceValue: sourceBounds(lower: 0, upper: 0.5),
                provenance: [provenance]
            ))
        )
        guard case let .bounded(interval) = bounded.value else { return XCTFail() }
        XCTAssertEqual(interval.upper, 0.5)
        XCTAssertFalse(interval.upperClosed)
    }

    func testExactValuesRequireCanonicalUnitAndProvenance() throws {
        XCTAssertThrowsError(try ExactNutrientValue(
            amount: 1,
            unit: .grams,
            sourceValue: sourceExact(amount: 1, unit: "g"),
            provenance: []
        ))
        let exact = try ExactNutrientValue(
            amount: 1,
            unit: .milligrams,
            sourceValue: sourceExact(amount: 1, unit: "mg"),
            provenance: [makeProvenance()]
        )
        XCTAssertThrowsError(try NutrientEntry(key: .protein, value: .measured(exact)))
        XCTAssertThrowsError(try ExactNutrientValue(
            amount: 1,
            unit: .grams,
            sourceValue: sourceBounds(lower: 0, upper: 1),
            provenance: [makeProvenance()]
        ))
        let incompleteGeneric = NutrientProvenance(
            sourceKind: .genericCompositionDataset,
            sourceID: try ExternalIdentifier("cofid"),
            sourceReleaseID: try ExternalIdentifier("cofid:2026")
        )
        let augmented = try ExactNutrientValue(
            amount: 1,
            unit: .grams,
            sourceValue: sourceExact(amount: 1, unit: "g"),
            provenance: [incompleteGeneric]
        )
        XCTAssertThrowsError(try NutrientEntry(key: .protein, value: .augmented(augmented)))
    }

    func testNutrientSetRejectsMissingDuplicateAndWrongOrder() throws {
        let entries = try NutrientKey.allCases.map {
            try NutrientEntry(key: $0, value: .unknown(.notDeclared))
        }
        XCTAssertNoThrow(try NutrientSet(entries: entries))
        XCTAssertThrowsError(try NutrientSet(entries: Array(entries.dropLast())))
        var wrong = entries
        wrong.swapAt(0, 1)
        XCTAssertThrowsError(try NutrientSet(entries: wrong))
        var duplicate = entries
        duplicate[1] = duplicate[0]
        XCTAssertThrowsError(try NutrientSet(entries: duplicate))
    }

    func testConflictMustRemainEffectiveUnknownWithCandidates() throws {
        let exact = try ExactNutrientValue(
            amount: 1,
            unit: .grams,
            sourceValue: sourceExact(amount: 1, unit: "g"),
            provenance: [makeProvenance()]
        )
        let augmentedProvenance = try NutrientProvenance(
            sourceKind: .genericCompositionDataset,
            sourceID: ExternalIdentifier("cofid"),
            sourceReleaseID: ExternalIdentifier("cofid:2026"),
            recordID: ExternalIdentifier("row:1")
        )
        let augmentedExact = try ExactNutrientValue(
            amount: 1,
            unit: .grams,
            sourceValue: sourceExact(amount: 1, unit: "g"),
            provenance: [augmentedProvenance]
        )
        XCTAssertThrowsError(try NutrientEntry(
            key: .protein,
            value: .measured(exact),
            status: .conflict,
            conflictCandidates: [.measured(exact), .augmented(augmentedExact)]
        ))
        XCTAssertNoThrow(try NutrientEntry(
            key: .protein,
            value: .unknown(.conflictingEvidence),
            status: .conflict,
            conflictCandidates: [.measured(exact), .augmented(augmentedExact)]
        ))
        let wrongUnit = try ExactNutrientValue(
            amount: 1,
            unit: .milligrams,
            sourceValue: sourceExact(amount: 1, unit: "mg"),
            provenance: [augmentedProvenance]
        )
        XCTAssertThrowsError(try NutrientEntry(
            key: .protein,
            value: .unknown(.conflictingEvidence),
            status: .conflict,
            conflictCandidates: [.measured(exact), .augmented(wrongUnit)]
        ))
    }

    func testHardIdentityContradictionCannotBeSelected() throws {
        let expected = try identity(drained: .drained)
        let candidate = try ProviderNeutralCandidate(
            sourceReleaseID: try ExternalIdentifier("fixture:v1"),
            recordID: try ExternalIdentifier("row:1"),
            identity: try identity(drained: .undrained),
            edibleQuantity: .known(
                try PositiveQuantity(value: 100, unit: .grams),
                conversionVersionID: nil
            ),
            nutrients: try allUnknown()
        )
        XCTAssertThrowsError(try CandidateDecision(
            candidateDecisionID: id(41, CandidateDecisionTag.self),
            candidate: candidate,
            expectedIdentity: expected,
            expectedEdibleQuantity: .known(
                try PositiveQuantity(value: 100, unit: .grams),
                conversionVersionID: nil
            ),
            requestedOutcome: .selected,
            createdAt: Date(timeIntervalSince1970: 0)
        )) { error in
            guard case let .hardIdentityContradiction(reasons) = error as? FoodLedgerValidationError else {
                return XCTFail("\(error)")
            }
            XCTAssertTrue(reasons.contains(.drained))
        }
    }

    func testUnknownIdentityAndQuantityCannotBeSelected() throws {
        let candidate = try ProviderNeutralCandidate(
            sourceReleaseID: try ExternalIdentifier("fixture:v1"),
            recordID: try ExternalIdentifier("row:1"),
            identity: try DecisiveIdentity(
                preparation: PreparationState(kind: .unknown),
                bone: .unknown,
                skin: .unknown,
                drained: .unknown,
                packingMedium: .unknown,
                fortification: .unknown,
                servingBasis: .unknown
            ),
            edibleQuantity: .unknown,
            nutrients: try allUnknown()
        )
        XCTAssertThrowsError(try CandidateDecision(
            candidateDecisionID: id(42, CandidateDecisionTag.self),
            candidate: candidate,
            expectedIdentity: try identity(drained: .drained),
            expectedEdibleQuantity: .known(
                try PositiveQuantity(value: 100, unit: .grams),
                conversionVersionID: nil
            ),
            requestedOutcome: .selected,
            createdAt: Date(timeIntervalSince1970: 0)
        )) { error in
            guard case let .hardIdentityContradiction(reasons) = error as? FoodLedgerValidationError else {
                return XCTFail("\(error)")
            }
            XCTAssertTrue(reasons.contains(.preparation))
            XCTAssertTrue(reasons.contains(.edibleQuantity))
        }
    }

    func testProductVersionsRequireEvidenceOrAssertion() throws {
        XCTAssertThrowsError(try ProductVersion(
            productVersionID: id(1, ProductVersionTag.self),
            productID: id(2, ProductTag.self),
            ordinal: VersionOrdinal(1),
            name: LedgerText("No evidence"),
            itemClass: .food,
            packFacts: PackFacts(),
            identity: identity(drained: .notApplicable),
            evidenceIDs: [],
            assertionIDs: [],
            createdAt: Date(timeIntervalSince1970: 0)
        ))
    }

    private func makeProvenance() throws -> NutrientProvenance {
        NutrientProvenance(
            sourceKind: .userVerifiedPanel,
            sourceID: try ExternalIdentifier("physical_package"),
            sourceReleaseID: try ExternalIdentifier("package:fixture")
        )
    }

    private func allUnknown() throws -> NutrientSet {
        try NutrientSet(entries: NutrientKey.allCases.map {
            try NutrientEntry(key: $0, value: .unknown(.notDeclared))
        })
    }

    private func identity(drained: DrainedState) throws -> DecisiveIdentity {
        try DecisiveIdentity(
            preparation: PreparationState(kind: .asSold),
            bone: .notApplicable,
            skin: .notApplicable,
            drained: drained,
            packingMedium: .named(LedgerText("none")),
            fortification: .unfortified,
            servingBasis: .per100Grams
        )
    }

    private func sourceExact(amount: Double, unit: String) throws -> SourceNutrientValue {
        .exact(try SourceExactNutrientValue(
            amount: amount,
            unit: LedgerText(unit),
            basis: .per100Grams
        ))
    }

    private func sourceBounds(lower: Double?, upper: Double?) throws -> SourceNutrientValue {
        .bounded(try SourceBoundedNutrientValue(
            lower: lower,
            upper: upper,
            lowerClosed: true,
            upperClosed: false,
            unit: LedgerText("g"),
            basis: .per100Grams
        ))
    }

    private func id<Tag>(_ number: Int, _ tag: Tag.Type) throws -> LedgerID<Tag> {
        try LedgerID(String(format: "00000000-0000-0000-0000-%012x", number))
    }
}
