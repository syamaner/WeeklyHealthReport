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
}
