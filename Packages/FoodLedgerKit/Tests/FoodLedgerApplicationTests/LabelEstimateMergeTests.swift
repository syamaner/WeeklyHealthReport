import FoodLedgerApplication
import FoodLedgerDomain
import XCTest

/// label-estimate-merge-v1 (#383, docs/label-estimate-merge-v1.md rule 4). Synthetic sets only.
final class LabelEstimateMergeTests: XCTestCase {
    private func provenance(_ kind: ProvenanceSourceKind, record: String? = nil) throws -> NutrientProvenance {
        NutrientProvenance(sourceKind: kind, sourceID: try ExternalIdentifier(kind == .genericCompositionDataset ? "usda" : "label"),
                           sourceReleaseID: try ExternalIdentifier(kind == .genericCompositionDataset ? "usda-rel" : "label-rel"),
                           recordID: try record.map { try ExternalIdentifier($0) })
    }
    private func exact(_ key: NutrientKey, _ amount: Double, _ kind: ProvenanceSourceKind) throws -> ExactNutrientValue {
        try ExactNutrientValue(amount: amount, unit: key.canonicalUnit,
                               sourceValue: .exact(SourceExactNutrientValue(amount: amount, unit: LedgerText(key.canonicalUnit.rawValue), basis: .per100Grams)),
                               provenance: [provenance(kind, record: kind == .genericCompositionDataset ? "fdc:1" : nil)])
    }
    /// A set where `values` are known and every other key is unknown for `reason`.
    private func set(_ values: [NutrientKey: NutrientValue], reason: UnknownReason = .notDeclared) throws -> NutrientSet {
        try NutrientSet(entries: NutrientKey.allCases.map { try NutrientEntry(key: $0, value: values[$0] ?? .unknown(reason)) })
    }
    private func label(_ values: [NutrientKey: Double], bounded: [NutrientKey: Double] = [:]) throws -> NutrientSet {
        var entries: [NutrientKey: NutrientValue] = [:]
        for (key, amount) in values { entries[key] = .measured(try exact(key, amount, .userVerifiedPanel)) }
        for (key, upper) in bounded {
            entries[key] = .bounded(try NutrientBounds(lower: nil, upper: upper, lowerClosed: false, upperClosed: false, origin: .measured,
                unit: key.canonicalUnit, sourceValue: .bounded(SourceBoundedNutrientValue(lower: nil, upper: upper, lowerClosed: false,
                    upperClosed: false, unit: LedgerText(key.canonicalUnit.rawValue), basis: .per100Grams)),
                provenance: [provenance(.userVerifiedPanel)]))
        }
        return try set(entries)
    }
    private func generic(_ values: [NutrientKey: Double]) throws -> NutrientSet {
        var entries: [NutrientKey: NutrientValue] = [:]
        for (key, amount) in values { entries[key] = .augmented(try exact(key, amount, .genericCompositionDataset)) }
        return try set(entries, reason: .noCompatibleSource)
    }
    private func entry(_ set: NutrientSet, _ key: NutrientKey) -> NutrientValue { set.entries.first { $0.key == key }!.value }

    func testLabelValuesWinAndGenericValuesFillOnlyUnknownKeys() throws {
        XCTAssertEqual(LabelEstimateMerge.version, "label-estimate-merge-v1")
        let labelSet = try label([.energyConsumed: 598, .fatTotal: 42, .sodium: 0], bounded: [.sugar: 0.5])
        let genericSet = try generic([.energyConsumed: 600, .fatTotal: 43, .sugar: 24, .sodium: 20, .iron: 11.9, .magnesium: 228])
        let result = try XCTUnwrap(try LabelEstimateMerge.merge(label: labelSet, labelBasis: .per100Grams, generic: genericSet, genericBasis: .per100Grams))
        XCTAssertEqual(entry(result.nutrients, .energyConsumed), entry(labelSet, .energyConsumed), "a printed value is never overwritten")
        XCTAssertEqual(entry(result.nutrients, .fatTotal), entry(labelSet, .fatTotal))
        XCTAssertEqual(entry(result.nutrients, .sodium), entry(labelSet, .sodium), "a printed zero stays")
        XCTAssertEqual(entry(result.nutrients, .sugar), entry(labelSet, .sugar), "a printed bound stays")
        XCTAssertEqual(entry(result.nutrients, .iron), entry(genericSet, .iron), "provenance copied verbatim at the same basis")
        XCTAssertEqual(result.filledKeys, [.iron, .magnesium], "catalogue order")
        // Keys neither source has stay unknown with the label's reason.
        XCTAssertEqual(entry(result.nutrients, .zinc), .unknown(.notDeclared))
        XCTAssertEqual(result.nutrients.entries.map(\.key), NutrientKey.allCases)
        XCTAssertTrue(result.nutrients.entries.allSatisfy { $0.conflictCandidates.isEmpty })
    }

    func testGenericValuesAreScaledToTheLabelBasisWithANamedTransform() throws {
        let serving = ResolutionBasis.perServing(try PositiveQuantity(value: 25, unit: .grams))
        let result = try XCTUnwrap(try LabelEstimateMerge.merge(label: try label([.energyConsumed: 150]), labelBasis: serving,
                                                                generic: try generic([.iron: 12]), genericBasis: .per100Grams))
        guard case let .augmented(iron) = entry(result.nutrients, .iron) else { return XCTFail("iron is an estimate") }
        XCTAssertEqual(iron.amount, 3, accuracy: 1e-9)
        XCTAssertEqual(iron.provenance.first?.transforms.map(\.transformID.value), [LabelEstimateMerge.basisTransformID])
        XCTAssertEqual(iron.provenance.first?.recordID?.value, "fdc:1")
    }

    func testABasisWithoutAGramMassOffersNoMerge() throws {
        let labelSet = try label([.energyConsumed: 150]), genericSet = try generic([.iron: 12])
        XCTAssertNil(try LabelEstimateMerge.merge(label: labelSet, labelBasis: .per100Millilitres, generic: genericSet, genericBasis: .per100Grams))
        XCTAssertNil(try LabelEstimateMerge.merge(label: labelSet, labelBasis: .unknown, generic: genericSet, genericBasis: .per100Grams))
        XCTAssertNil(try LabelEstimateMerge.merge(label: labelSet, labelBasis: .perUnit(try PositiveQuantity(value: 1, unit: .count)),
                                                  generic: genericSet, genericBasis: .per100Grams))
        XCTAssertNil(try LabelEstimateMerge.merge(label: labelSet, labelBasis: .per100Grams, generic: genericSet,
                                                  genericBasis: .perServing(try PositiveQuantity(value: 40, unit: .grams))))
    }

    func testTheMergeIsDeterministic() throws {
        let labelSet = try label([.energyConsumed: 598]), genericSet = try generic([.iron: 11.9, .zinc: 3.3])
        let first = try LabelEstimateMerge.merge(label: labelSet, labelBasis: .per100Grams, generic: genericSet, genericBasis: .per100Grams)
        let second = try LabelEstimateMerge.merge(label: labelSet, labelBasis: .per100Grams, generic: genericSet, genericBasis: .per100Grams)
        XCTAssertEqual(first, second)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        XCTAssertEqual(try encoder.encode(first?.nutrients), try encoder.encode(second?.nutrients))
    }

    func testCocoaPercentPrefillAndValidation() {
        typealias C = LabelEstimateCompatibility
        XCTAssertEqual(C.prefill(name: "Dark chocolate 85% cocoa", pastedText: nil)?.value, 85)
        XCTAssertEqual(C.prefill(name: "Dark chocolate 85% cocoa", pastedText: nil)?.origin, .name)
        XCTAssertEqual(C.prefill(name: "Dark chocolate", pastedText: "Ingredients: cocoa mass, sugar. Cocoa solids: 70% minimum")?.value, 70)
        XCTAssertEqual(C.prefill(name: "Dark chocolate", pastedText: "Cocoa solids 70% minimum")?.origin, .pastedText)
        XCTAssertNil(C.prefill(name: "Dark chocolate 70-85% cocoa solids", pastedText: nil), "a range is not a pre-fill")
        XCTAssertNil(C.prefill(name: "Dark chocolate", pastedText: "Cocoa solids 70%. Milk solids 14%. Cocoa solids 85%"), "two values")
        XCTAssertNil(C.prefill(name: "Dark chocolate", pastedText: nil))
        XCTAssertNil(C.prefill(name: "Dark chocolate", pastedText: "contains 30% cocoa butter"), "an ingredient percentage")
        XCTAssertTrue(C.isValidPercent(85.5))
        XCTAssertFalse(C.isValidPercent(85.55))
        XCTAssertFalse(C.isValidPercent(0))
        XCTAssertFalse(C.isValidPercent(101))
        XCTAssertTrue(C.offersEstimate(name: "Dark Chocolate 85%", basis: .per100Grams))
        XCTAssertFalse(C.offersEstimate(name: "Milk Chocolate 40%", basis: .per100Grams))
        XCTAssertFalse(C.offersEstimate(name: "White chocolate", basis: .per100Grams))
        XCTAssertFalse(C.offersEstimate(name: "Oat bar", basis: .per100Grams))
        XCTAssertFalse(C.offersEstimate(name: "Dark chocolate", basis: .per100Millilitres))
    }
}
