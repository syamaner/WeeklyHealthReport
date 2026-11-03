import Foundation
import FoodGenericSearch
import FoodLedgerApplication
import FoodLedgerDomain
import XCTest

/// label-estimate-compatibility-v1 (#383, docs/label-estimate-merge-v1.md rule 3) over the
/// bundled CoFID 2021 and USDA rows. Synthetic query text only.
final class LabelEstimateCompatibilityTests: XCTestCase {
    private func rows(_ text: String) throws -> [PopulatedFoodCandidate] {
        let ids = CompatibilityIDs()
        let search = CompositeGenericFoodSearch(sources: [try CoFIDGenericFoodSearch(ids: ids), try USDAGenericFoodSearch(ids: ids)], ids: ids)
        let request = GenericFoodSearchRequest(text: try LedgerText(text), capturedAt: Date(timeIntervalSince1970: 1_700_000_000), locale: try LedgerText("en_GB"))
        guard case let .confirmation(route) = try search.search(request) else { return [] }
        return route.matches.map(\.candidate)
    }
    private func row(_ name: String, from query: String) throws -> PopulatedFoodCandidate {
        try XCTUnwrap(try rows(query).first { $0.name.value == name }, name)
    }
    private func compatible(_ p: Double, among candidates: [PopulatedFoodCandidate]) -> [String] {
        Set(candidates.filter { LabelEstimateCompatibility.isCompatible($0, cocoaPercent: p) }.map(\.name.value)).sorted()
    }

    func testCompatibilityFollowsTheOwnerDecision() throws {
        XCTAssertEqual(LabelEstimateCompatibility.version, "label-estimate-compatibility-v1")
        let band = try row("Chocolate, dark, 70-85% cacao solids", from: "dark chocolate 85%")
        let estimate = try row("Baking chocolate, unsweetened, squares", from: "dark chocolate 100%")
        XCTAssertEqual(band.candidate.recordID.value, LabelEstimateCompatibility.nearestBandRecordID)
        let pool = try rows("dark chocolate 85%") + rows("dark chocolate 100%") + rows("dark chocolate 50%") + rows("70-85% dark chocolate")
        func check(_ p: Double) -> Bool { LabelEstimateCompatibility.isCompatible(band, cocoaPercent: p) }
        XCTAssertTrue(check(70)); XCTAssertTrue(check(85)); XCTAssertTrue(check(85.5)); XCTAssertTrue(check(86))
        XCTAssertTrue(check(99)); XCTAssertTrue(check(99.5)); XCTAssertFalse(check(100)); XCTAssertFalse(check(69))
        XCTAssertTrue(LabelEstimateCompatibility.isCompatible(estimate, cocoaPercent: 100))
        XCTAssertFalse(LabelEstimateCompatibility.isCompatible(estimate, cocoaPercent: 99.5), "the 100% estimate is for 100% only")
        XCTAssertEqual(compatible(90, among: pool), ["Chocolate, dark, 70-85% cacao solids"])
        XCTAssertEqual(compatible(100, among: pool), ["Baking chocolate, unsweetened, squares"])
        XCTAssertEqual(compatible(40, among: pool), ["Chocolate, plain"])
        XCTAssertEqual(Set(compatible(50, among: pool)), ["Chocolate, plain", "Chocolate, dark, 45- 59% cacao solids"])
        XCTAssertEqual(compatible(30, among: pool), [], "no band holds 30%; nothing is offered")
    }

    func testBlendsUnbandedRowsAndInvalidPercentagesAreRefused() throws {
        let blend = try row("Candies, chocolate, dark, NFS (45-59% cacao solids 90%; 60-69% cacao solids 5%; 70-85% cacao solids 5%)", from: "70-85% dark chocolate")
        let mint = try row("Chocolate, dark, with crème or mint fondant centres", from: "dark chocolate 85%")
        let band = try row("Chocolate, dark, 70-85% cacao solids", from: "dark chocolate 85%")
        for p in [45.0, 70, 85, 90, 100] {
            XCTAssertFalse(LabelEstimateCompatibility.isCompatible(blend, cocoaPercent: p), "blend at \(p)")
            XCTAssertFalse(LabelEstimateCompatibility.isCompatible(mint, cocoaPercent: p), "unbanded at \(p)")
        }
        for p in [0.0, 101, 85.55, .nan] {
            XCTAssertFalse(LabelEstimateCompatibility.isCompatible(band, cocoaPercent: p), "invalid \(p)")
        }
    }

    func testOnlyBundledGenericRowsQualify() throws {
        let band = try row("Chocolate, dark, 70-85% cacao solids", from: "dark chocolate 85%")
        // The same name and record ID with label provenance, as a personal-library row would carry.
        let entries = try band.candidate.nutrients.entries.map { entry -> NutrientEntry in
            guard case let .augmented(exact) = entry.value else { return entry }
            let provenance = exact.provenance.map {
                NutrientProvenance(sourceKind: .exactProductDataset, sourceID: $0.sourceID, sourceReleaseID: $0.sourceReleaseID, recordID: $0.recordID)
            }
            return try NutrientEntry(key: entry.key, value: .augmented(try ExactNutrientValue(amount: exact.amount, unit: exact.unit,
                                                                                              sourceValue: exact.sourceValue, provenance: provenance)))
        }
        let personal = try PopulatedFoodCandidate(
            candidate: try ProviderNeutralCandidate(sourceReleaseID: band.candidate.sourceReleaseID, recordID: band.candidate.recordID,
                                                    identity: band.candidate.identity, edibleQuantity: band.candidate.edibleQuantity,
                                                    nutrients: try NutrientSet(entries: entries)),
            name: band.name, brand: nil, variant: band.variant, barcode: nil, itemClass: band.itemClass)
        XCTAssertTrue(LabelEstimateCompatibility.isCompatible(band, cocoaPercent: 80))
        XCTAssertFalse(LabelEstimateCompatibility.isCompatible(personal, cocoaPercent: 80))
    }

    func testAMilkChocolateRowIsNeverCompatible() throws {
        for candidate in try rows("milk chocolate") where candidate.name.value.lowercased().contains("milk") {
            for p in [30.0, 40, 50] {
                XCTAssertFalse(LabelEstimateCompatibility.isCompatible(candidate, cocoaPercent: p), candidate.name.value)
            }
        }
    }
}

private final class CompatibilityIDs: LedgerIDGenerating, @unchecked Sendable {
    private var value = 1
    func makeID<Tag>(_ tag: Tag.Type) throws -> LedgerID<Tag> {
        defer { value += 1 }
        return try LedgerID(String(format: "00000000-0000-0000-0000-%012x", value))
    }
}
