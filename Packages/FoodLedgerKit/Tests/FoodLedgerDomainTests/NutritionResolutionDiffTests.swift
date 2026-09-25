import FoodLedgerDomain
import XCTest

final class NutritionResolutionDiffTests: XCTestCase {
    func testNoOpStillContainsAll39Entries() throws {
        let original = try nutrients(.unknown(.notDeclared))
        let diff = NutritionResolutionDiff(before: original, after: original)
        XCTAssertTrue(diff.isUnchanged)
        XCTAssertEqual(diff.entries.map(\.key), NutrientKey.allCases)
        XCTAssertEqual(diff.entries.count, 39)
    }

    func testStateAndProvenanceChangesDoNotDisappearWhenAmountIsEqual() throws {
        let exact = try exactValue(release: "synthetic-v1")
        let newer = try exactValue(release: "synthetic-v2")
        let measured = try nutrients(.measured(exact))
        let augmented = try nutrients(.augmented(exact))
        XCTAssertEqual(NutritionResolutionDiff(before: measured, after: augmented).changes.map(\.key), [.protein])
        XCTAssertEqual(try NutritionResolutionDiff(before: augmented, after: nutrients(.augmented(newer))).changes.map(\.key), [.protein])
        XCTAssertEqual(try NutritionResolutionDiff(before: measured, after: nutrients(.unknown(.noCompatibleSource))).changes.map(\.key), [.protein])
    }

    func testOpenClosedBoundsAndUnknownReasonsRemainVisible() throws {
        let first = try nutrients(.bounded(bounds(upper: 5, closed: false)))
        let changed = try nutrients(.bounded(bounds(upper: 5, closed: true)))
        XCTAssertEqual(NutritionResolutionDiff(before: first, after: changed).changes.count, 1)
        XCTAssertEqual(try NutritionResolutionDiff(before: first, after: nutrients(.bounded(bounds(upper: 7, closed: false)))).changes.count, 1)
        XCTAssertEqual(try NutritionResolutionDiff(before: nutrients(.unknown(.notDeclared)), after: nutrients(.unknown(.noCompatibleSource))).changes.count, 1)
    }

    private func nutrients(_ value: NutrientValue) throws -> NutrientSet {
        try NutrientSet(entries: NutrientKey.allCases.map { try NutrientEntry(key: $0, value: $0 == .protein ? value : .unknown(.notDeclared)) })
    }

    private func provenance(_ release: String) throws -> NutrientProvenance {
        try NutrientProvenance(sourceKind: .exactProductDataset, sourceID: ExternalIdentifier("synthetic"), sourceReleaseID: ExternalIdentifier(release), recordID: ExternalIdentifier("sample"))
    }

    private func exactValue(release: String) throws -> ExactNutrientValue {
        try ExactNutrientValue(amount: 5, unit: .grams, sourceValue: .exact(SourceExactNutrientValue(amount: 5, unit: LedgerText("g"), basis: .per100Grams)), provenance: [provenance(release)])
    }

    private func bounds(upper: Double, closed: Bool) throws -> NutrientBounds {
        try NutrientBounds(lower: 0, upper: upper, lowerClosed: true, upperClosed: closed, origin: .augmented, unit: .grams,
            sourceValue: .bounded(SourceBoundedNutrientValue(lower: 0, upper: upper, lowerClosed: true, upperClosed: closed, unit: LedgerText("g"), basis: .per100Grams)),
            provenance: [provenance("synthetic-v2")])
    }
}
