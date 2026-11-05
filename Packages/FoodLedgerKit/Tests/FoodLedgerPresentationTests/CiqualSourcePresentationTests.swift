import Foundation
import FoodGenericSearch
import FoodLedgerApplication
import FoodLedgerDomain
import FoodLedgerPresentation
import FoodLedgerTestSupport
import XCTest

/// Ciqual surfaces landing in #384 C2 (docs/ciqual-2025-admission-v1.md section 7, D8): the
/// "French reference" family, the search row label and Confirm's source line.
@MainActor
final class CiqualSourcePresentationTests: XCTestCase {
    func testFamilyRowAndConfirmLabels() throws {
        XCTAssertEqual(FoodSearchResultText.family(.frenchReference), "French reference")
        XCTAssertEqual(FoodSearchResultText.confirmSourceName(family: .frenchReference, isGenericEstimate: true), "French reference · estimate")
        XCTAssertNil(FoodSearchResultText.confirmSourceName(family: .frenchReference, isGenericEstimate: false))
        // VoiceOver reads commas, never the middle dot (section 7).
        XCTAssertEqual(FoodSearchResultText.spokenSourceLine("French reference · estimate"), "French reference, estimate")
        XCTAssertEqual(FoodSearchResultText.spokenSourceLine("US reference · estimate · cooked"), "US reference, estimate, cooked")
        XCTAssertEqual(FoodSearchResultText.summaryLine(.init(family: .frenchReference, preparation: .unknown, energy: .basisOnly(.per100Grams))),
                       "French reference · per 100 g")
        // Earlier families keep their words.
        XCTAssertEqual(FoodSearchResultText.family(.ukReference), "UK reference")
        XCTAssertEqual(FoodSearchResultText.family(.usReference), "US reference")
        XCTAssertEqual(FoodSearchResultText.family(.taiwanReference), "Taiwan reference")
    }

    func testSearchRowReadsCiqualOnDeviceAndTheSummaryIsFrenchReference() throws {
        let ids = RandomLedgerIDGenerator()
        let composite = CompositeGenericFoodSearch(sources: [try CoFIDGenericFoodSearch(ids: ids), try USDAGenericFoodSearch(ids: ids)],
                                                   regionalSources: [try TFDAGenericFoodSearch(ids: ids)],
                                                   referenceSources: [try CiqualGenericFoodSearch(ids: ids)], ids: ids)
        let search = try GenericFoodSearchViewModel(searcher: composite, locale: LedgerText("en_GB"))
        search.query = "dark chocolate 70%"; search.search()
        guard case let .results(route) = search.phase,
              let match = route.matches.first(where: { $0.candidate.candidate.recordID.value.hasSuffix(":alim:31074") }) else { return XCTFail() }
        XCTAssertEqual(search.sourceLabel(for: match), "Ciqual · on device")
        XCTAssertEqual(FoodSearchResultSummary(candidate: match.candidate, releases: route.confirmation.sourceReleases, amount: nil).family, .frenchReference)
        XCTAssertEqual(FoodSearchResultSummary.family(candidate: match.candidate.candidate, releases: route.confirmation.sourceReleases), .frenchReference)
        let usda = try XCTUnwrap(route.matches.first { $0.candidate.candidate.recordID.value.hasPrefix("usda") })
        XCTAssertEqual(search.sourceLabel(for: usda), "USDA · on device")
    }

    // MARK: Developer tools (#384 C3, section 7, D5, A7)

    private static let release = "ciqual:2025-11-19:sha256:\(CiqualGenericFoodSearch.sourceManifestSHA256)"
    private static func record(_ code: String) -> String { "\(release):alim:\(code)" }

    private func ciqualSearch(_ query: String, ciqual: CiqualGenericFoodSearch) throws -> (GenericFoodSearchViewModel, GenericFoodConfirmationRoute) {
        let search = try GenericFoodSearchViewModel(searcher: ciqual, locale: LedgerText("en_GB"), recordDetails: ciqual)
        search.query = query; search.search()
        guard case let .results(route) = search.phase else { throw CiqualSearchError.invalidCorpus }
        return (search, route)
    }

    func testDeveloperToolsLinesFor31074ShowReleaseHashesCodesLiteralsAndTheFrenchName() throws {
        let ids = RandomLedgerIDGenerator()
        let ciqual = try CiqualGenericFoodSearch(ids: ids)
        let composite = CompositeGenericFoodSearch(sources: [try CoFIDGenericFoodSearch(ids: ids), try USDAGenericFoodSearch(ids: ids)],
                                                   regionalSources: [try TFDAGenericFoodSearch(ids: ids)],
                                                   referenceSources: [ciqual], ids: ids)
        let search = try GenericFoodSearchViewModel(searcher: composite, locale: LedgerText("en_GB"), recordDetails: ciqual)
        search.query = "dark chocolate 70%"; search.search()
        let lines = search.diagnosticLines
        let start = try XCTUnwrap(lines.firstIndex(of: "Record: \(Self.record("31074"))"))
        let block = Array(lines[start...].prefix(45))
        let corpus = CiqualGenericFoodSearch.corpusSHA256
        XCTAssertEqual(lines[start - 1], "Source: \(Self.release):projection:\(corpus)")
        XCTAssertEqual(Array(block[1...5]), [
            "French name (Developer tools only, not searched or saved): Chocolat noir 70 % de cacao environ, de dégustation, tablette",
            "Source manifest SHA-256: \(CiqualGenericFoodSearch.sourceManifestSHA256)",
            "Corpus SHA-256: \(corpus)",
            "Attribution: Anses. 2025. Table de composition nutritionnelle des aliments Ciqual 2025. https://doi.org/10.57745/RDMHWY. Reviewed projection of the chocolate group; English names as published by Anses; no Anses endorsement.",
            "Licence: Etalab Open Licence 2.0 · https://www.etalab.gouv.fr/licence-ouverte-open-licence/"
        ])
        XCTAssertTrue(block.contains("Iron: literal 11 · Ciqual confidence A · source code 389 · constituent 10260 · reference compo_2025_11_03.xml;alim=31074;const=10260;literal=11;confidence=A;projection=\(corpus)"))
        XCTAssertTrue(block.contains("Energy: literal 591 · Ciqual confidence D, calculated, not analysed · source code 444 · constituent 328 · reference compo_2025_11_03.xml;alim=31074;const=328;literal=591;confidence=D;projection=\(corpus)"))
        // A "< n" row keeps its literal beside the stored open bound's reference.
        XCTAssertTrue(block.contains("Chloride: literal < 20 · Ciqual confidence A · source code 389 · constituent 10170 · reference compo_2025_11_03.xml;alim=31074;const=10170;literal=< 20;confidence=A;projection=\(corpus)"))
        XCTAssertTrue(block.contains { $0.hasPrefix("Water: literal 0,9 · Ciqual confidence A · source code 389 · constituent 400 · stays unknown (missing_conversion)") })
        // 35 mapped constituents for 39 keys: the four keys with no constituent have no line.
        XCTAssertEqual(ciqual.details(recordID: try ExternalIdentifier(Self.record("31074")))?.values.count, 35)
        // Other sources have no details and gain no lines.
        let usda = try XCTUnwrap(lines.firstIndex { $0.hasPrefix("Record: usda") })
        XCTAssertFalse(lines[usda + 1].hasPrefix("French name"))
    }

    func testTracesStayUnknownAndMinAndMaxAreLiteralsNeverBounds() throws {
        let ciqual = try CiqualGenericFoodSearch(ids: RandomLedgerIDGenerator())
        let (biscuitSearch, _) = try ciqualSearch("chocolate bar with biscuit", ciqual: ciqual)
        XCTAssertTrue(biscuitSearch.diagnosticLines.contains(
            "Vitamin D: literal traces · Ciqual confidence A · source code 432 · constituent 52100 · stays unknown (no_compatible_source)"))

        let (search, route) = try ciqualSearch("chocolate bar chocolate-coated without biscuit", ciqual: ciqual)
        let match = try XCTUnwrap(route.matches.first { $0.candidate.candidate.recordID.value == Self.record("31001") })
        let corpus = CiqualGenericFoodSearch.corpusSHA256
        XCTAssertTrue(search.diagnosticLines.contains(
            "Calcium: literal 99,8 · Ciqual confidence A · source code 162 · constituent 10200 · min 73,5 · max 126 (spread of source data, not a bound) · reference compo_2025_11_03.xml;alim=31001;const=10200;literal=99,8;confidence=A;projection=\(corpus)"))
        // The stored value is the exact mean, never a bound from min or max.
        let calcium = try XCTUnwrap(match.candidate.candidate.nutrients.entries.first { $0.key == .calcium }?.value)
        guard case let .augmented(exact) = calcium else { return XCTFail("min/max never make calcium a bound") }
        XCTAssertEqual(exact.amount, 99.8)
        for entry in route.matches.flatMap(\.candidate.candidate.nutrients.entries) {
            if case let .bounded(bounds) = entry.value {
                XCTAssertNil(bounds.lower, "only \"< n\" rows are bounds, and never with a lower bound")
            }
        }
    }

    func testAMissingReleaseIsShownRatherThanDroppedSilently() throws {
        let ciqual = try CiqualGenericFoodSearch(ids: RandomLedgerIDGenerator())
        let (_, route) = try ciqualSearch("dark chocolate 70%", ciqual: ciqual)
        let candidate = try XCTUnwrap(route.matches.first { $0.candidate.candidate.recordID.value == Self.record("31074") }).candidate.candidate
        let details = try XCTUnwrap(ciqual.details(recordID: candidate.recordID))
        let lines = GenericSourceDetailsText.lines(details, nutrients: candidate.nutrients, release: nil)
        XCTAssertTrue(lines.contains("Release details: not found for this record's source release"))
        XCTAssertFalse(lines.contains { $0.hasPrefix("Attribution:") })
    }

    func testTheFrenchNameIsNeverSearchedNorInACandidate() throws {
        let ciqual = try CiqualGenericFoodSearch(ids: RandomLedgerIDGenerator())
        let (_, route) = try ciqualSearch("dark chocolate 70%", ciqual: ciqual)
        let french = "Chocolat noir 70 % de cacao environ, de dégustation, tablette"
        for match in route.matches {
            let details = try XCTUnwrap(ciqual.details(recordID: match.candidate.candidate.recordID))
            XCTAssertNotEqual(match.candidate.name.value, details.originalName)
            XCTAssertFalse(match.candidate.variant?.value.contains(details.originalName) ?? false)
            XCTAssertFalse(String(describing: match.candidate).contains(details.originalName), "no candidate field carries the French name")
        }
        XCTAssertFalse(String(describing: route.confirmation).contains(french))
        // A French-only query finds nothing: the French name is not searched.
        let search = try GenericFoodSearchViewModel(searcher: ciqual, locale: LedgerText("fr_FR"), recordDetails: ciqual)
        search.query = "chocolat noir dégustation tablette"; search.search()
        if case let .results(other) = search.phase {
            XCTAssertFalse(other.matches.contains { $0.candidate.candidate.recordID.value == Self.record("31074") })
        }
    }
}
