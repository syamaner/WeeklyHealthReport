import Foundation
import FoodGenericSearch
import FoodLedgerApplication
import FoodLedgerDomain
import XCTest

/// `CiqualGenericFoodSearch` (#384 C2, docs/ciqual-2025-admission-v1.md sections 1, 3 and 4):
/// load and hash check, release, projection of every value, eligibility and family mapping.
final class CiqualGenericFoodSearchTests: XCTestCase {
    private static let corpusURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent("Sources/FoodGenericSearch/Resources/ciqual-2025-generic-v1.json")
    private static let releaseID = "ciqual:2025-11-19:sha256:3134f8dc9feb3e17e4d297fdc42f7711eff41af3210facb5d24c35194fa0d847"

    private func request(_ text: String) throws -> GenericFoodSearchRequest {
        GenericFoodSearchRequest(text: try LedgerText(text), capturedAt: Date(timeIntervalSince1970: 1_700_000_000), locale: try LedgerText("en_GB"))
    }
    private func route(_ search: CiqualGenericFoodSearch, _ text: String) throws -> GenericFoodConfirmationRoute? {
        guard case let .confirmation(route) = try search.search(request(text)) else { return nil }
        return route
    }
    private func corpusRecords() throws -> [[String: Any]] {
        let corpus = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: Self.corpusURL)) as? [String: Any])
        return try XCTUnwrap(corpus["records"] as? [[String: Any]])
    }

    func testTheCorpusIsHashCheckedAndTheReleaseCarriesBothHashesAndTheAttribution() throws {
        XCTAssertEqual(CiqualGenericFoodSearch.corpusSHA256, CiqualCorpusPinTests.corpusSHA256)
        XCTAssertEqual(CiqualGenericFoodSearch.sourceManifestSHA256, CiqualCorpusPinTests.sourceManifestSHA256)
        let search = try CiqualGenericFoodSearch(ids: RandomLedgerIDGenerator())
        XCTAssertEqual(search.recordCount, 29)
        let release = try XCTUnwrap(try route(search, "dark chocolate")?.confirmation.sourceReleases.first)
        XCTAssertEqual(release.sourceReleaseID.value, "\(Self.releaseID):projection:\(CiqualGenericFoodSearch.corpusSHA256)")
        XCTAssertEqual(release.sourceID.value, "ciqual")
        XCTAssertEqual(release.artifactHash.value, CiqualGenericFoodSearch.sourceManifestSHA256)
        XCTAssertEqual(release.manifestHash.value, CiqualGenericFoodSearch.corpusSHA256)
        XCTAssertEqual(release.releasedAt, ISO8601DateFormatter().date(from: "2025-11-19T00:00:00Z"))
        XCTAssertEqual(release.licence.value, "Etalab Open Licence 2.0 · https://www.etalab.gouv.fr/licence-ouverte-open-licence/")
        XCTAssertEqual(release.attribution.value, "Anses. 2025. Table de composition nutritionnelle des aliments Ciqual 2025. https://doi.org/10.57745/RDMHWY. Reviewed projection of the chocolate group; English names as published by Anses; no Anses endorsement.")
        // One changed byte is refused.
        var data = try Data(contentsOf: Self.corpusURL)
        data[data.count - 2] = data[data.count - 2] == 0x20 ? 0x0A : 0x20
        let altered = FileManager.default.temporaryDirectory.appendingPathComponent("ciqual-altered-\(UUID().uuidString).json")
        try data.write(to: altered)
        defer { try? FileManager.default.removeItem(at: altered) }
        XCTAssertThrowsError(try CiqualGenericFoodSearch(corpusURL: altered, ids: RandomLedgerIDGenerator())) {
            XCTAssertEqual($0 as? CiqualSearchError, .hashMismatch)
        }
    }

    /// Every projected value equals its corpus value: exact decimals, open upper bounds,
    /// unknowns with their reason; never zero for an unknown and never exact for a bound.
    func testEveryRecordProjectsItsCorpusValuesWithProvenance() throws {
        let search = try CiqualGenericFoodSearch(ids: RandomLedgerIDGenerator())
        var states: [String: Int] = [:]
        for record in try corpusRecords() {
            let code = try XCTUnwrap(record["alimCode"] as? String), name = try XCTUnwrap(record["name"] as? String)
            let recordID = "\(Self.releaseID):alim:\(code)"
            let found = try XCTUnwrap(try route(search, name), name)
            let candidate = try XCTUnwrap(found.matches.first { $0.candidate.candidate.recordID.value == recordID }?.candidate, name)
            XCTAssertEqual(candidate.name.value, name, "the English name as published")
            XCTAssertEqual(candidate.variant?.value, "Ciqual · French composition estimate · per 100 g")
            XCTAssertFalse(candidate.variant?.value.contains("%") ?? true)
            XCTAssertEqual(candidate.candidate.identity.servingBasis, .per100Grams)
            XCTAssertEqual(candidate.candidate.edibleQuantity, .known(try PositiveQuantity(value: 100, unit: .grams), conversionVersionID: nil))
            XCTAssertEqual(candidate.itemClass, .food)
            let encoded = String(decoding: try JSONEncoder().encode(candidate), as: UTF8.self)
            XCTAssertFalse(encoded.contains(try XCTUnwrap(record["frenchName"] as? String)), "the French name is corpus-only (\(code))")
            let values = try XCTUnwrap(record["nutrients"] as? [String: [String: Any]])
            for entry in candidate.candidate.nutrients.entries {
                let source = try XCTUnwrap(values[entry.key.rawValue], "\(code) \(entry.key)")
                let state = try XCTUnwrap(source["state"] as? String)
                states[state, default: 0] += 1
                switch (state, entry.value) {
                case let ("exact", .augmented(exact)):
                    XCTAssertEqual(exact.amount, Double(try XCTUnwrap(source["value"] as? String)), "\(code) \(entry.key)")
                    XCTAssertEqual(exact.unit, entry.key.canonicalUnit)
                    try assertProvenance(exact.provenance, code: code, source: source, recordID: recordID)
                case let ("bounded", .bounded(bounds)):
                    XCTAssertNil(bounds.lower); XCTAssertFalse(bounds.upperClosed); XCTAssertEqual(bounds.origin, .augmented)
                    XCTAssertEqual(bounds.upper, Double(try XCTUnwrap(source["upper"] as? String)), "\(code) \(entry.key)")
                    guard case let .bounded(original) = bounds.sourceValue else { return XCTFail("\(code) \(entry.key)") }
                    XCTAssertNil(original.lower); XCTAssertEqual(original.upper, bounds.upper); XCTAssertFalse(original.upperClosed)
                    try assertProvenance(bounds.provenance, code: code, source: source, recordID: recordID)
                case let ("unknown", .unknown(reason)):
                    XCTAssertEqual(reason.rawValue, source["reason"] as? String, "\(code) \(entry.key)")
                default:
                    XCTFail("\(code) \(entry.key): corpus \(state), projected \(entry.value)")
                }
            }
        }
        XCTAssertEqual(states, ["exact": 737, "bounded": 48, "unknown": 346], "the audit's 1,131 values (C1 Reproduce)")
    }

    private func assertProvenance(_ provenance: [NutrientProvenance], code: String, source: [String: Any], recordID: String) throws {
        let only = try XCTUnwrap(provenance.first)
        XCTAssertEqual(provenance.count, 1)
        XCTAssertEqual(only.sourceKind, .genericCompositionDataset)
        XCTAssertEqual(only.sourceID.value, "ciqual")
        XCTAssertEqual(only.recordID?.value, recordID)
        XCTAssertEqual(only.responseHash?.value, "8c46a9032ece4eab4ffccc9dfcb0c490ec2f416aa664cc1ee013b241c6bdd4af")
        let literal = try XCTUnwrap(source["literal"] as? String), constCode = try XCTUnwrap(source["constCode"] as? String)
        let confidence = try XCTUnwrap(source["confidence"] as? String)
        XCTAssertEqual(only.manifestReference?.value,
                       "compo_2025_11_03.xml;alim=\(code);const=\(constCode);literal=\(literal);confidence=\(confidence);projection=\(CiqualGenericFoodSearch.corpusSHA256)")
    }

    /// The architecture gate's 31074 checks, sodium as published and no salt key.
    func testThe70PercentBarProjection() throws {
        let search = try CiqualGenericFoodSearch(ids: RandomLedgerIDGenerator())
        let bar = try XCTUnwrap(try route(search, "dark chocolate 70%")?.matches.first?.candidate)
        XCTAssertEqual(bar.candidate.recordID.value, "\(Self.releaseID):alim:31074")
        func value(_ key: NutrientKey) -> NutrientValue { bar.candidate.nutrients.entries.first { $0.key == key }!.value }
        func exact(_ key: NutrientKey) -> Double? { if case let .augmented(v) = value(key) { return v.amount }; return nil }
        XCTAssertEqual(exact(.iron), 11)
        XCTAssertEqual(exact(.magnesium), 200)
        XCTAssertEqual(exact(.vitaminE), 0.67)
        XCTAssertEqual(exact(.vitaminB12), 0, "a declared zero stays zero")
        XCTAssertEqual(exact(.energyConsumed), 591)
        XCTAssertNotNil(exact(.sodium), "sodium as published (10110)")
        guard case let .bounded(selenium) = value(.selenium) else { return XCTFail("selenium is an open upper bound") }
        XCTAssertEqual(selenium.upper, 20); XCTAssertNil(selenium.lower); XCTAssertEqual(selenium.unit, .micrograms)
        for key in [NutrientKey.biotinB7, .chromium, .molybdenum, .caffeine] { XCTAssertEqual(value(key), .unknown(.notDeclared), "\(key)") }
        XCTAssertEqual(value(.water), .unknown(.missingConversion))
        XCTAssertEqual(value(.vitaminA), .unknown(.noCompatibleSource), "A3")
        XCTAssertNil(NutrientKey(rawValue: "salt"), "the catalogue has no salt key; sodium is never derived from salt")
        if case let .augmented(iron) = value(.iron) {
            XCTAssertEqual(iron.provenance.first?.manifestReference?.value,
                           "compo_2025_11_03.xml;alim=31074;const=10260;literal=11;confidence=A;projection=\(CiqualGenericFoodSearch.corpusSHA256)")
        }
        XCTAssertTrue(LabelEstimateCompatibility.isCompatible(bar, cocoaPercent: 70), "bundled generic provenance with a record ID")
        XCTAssertFalse(LabelEstimateCompatibility.isCompatible(bar, cocoaPercent: 69.5))
    }

    /// Eligibility follows the USDA rules: every meaningful word in the English name; French is
    /// not searched; milk and white rows are never admitted by the cocoa exception.
    func testEligibilityFollowsTheUSDARules() throws {
        let search = try CiqualGenericFoodSearch(ids: RandomLedgerIDGenerator())
        XCTAssertNil(try route(search, "chocolat noir"), "French names are not searched")
        XCTAssertNil(try route(search, "salmon chocolate"))
        XCTAssertNil(try route(search, "plain chocolate"), "CoFID's UK name equivalence does not apply")
        let dark = try XCTUnwrap(try route(search, "dark chocolate 70%")).matches.map(\.candidate.name.value)
        XCTAssertTrue(dark.allSatisfy { $0.lowercased().contains("dark") && $0.lowercased().contains("chocolate") }, "\(dark)")
        XCTAssertLessThanOrEqual(dark.count, 10)
        let milk = try XCTUnwrap(try route(search, "milk chocolate")).matches.map(\.candidate.name.value)
        XCTAssertTrue(milk.contains("Milk chocolate, bar"))
        XCTAssertEqual(FoodConfirmationState(input: try XCTUnwrap(try route(search, "milk chocolate")).confirmation).decision, .undecided)
        guard case let .noResult(miss) = try search.search(request("zzzz chocolate")) else { return XCTFail() }
        XCTAssertEqual(miss.suggestedQueries, [], "a reference-only source adds no suggestions")
    }

    func testFamilyMappingAndLabels() {
        XCTAssertEqual(FoodSearchResultSummary.family("ciqual"), .frenchReference)
        XCTAssertEqual(FoodSearchResultSummary.family("cofid"), .ukReference)
        XCTAssertEqual(FoodSearchResultSummary.family("usda-legacy"), .usReference)
        XCTAssertEqual(FoodSearchResultSummary.family("tfda-taiwan"), .taiwanReference)
        XCTAssertEqual(FoodSearchResultSummary.family("ciqual-other"), .otherSource, "the mapping is exact")
    }
}
