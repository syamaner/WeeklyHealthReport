import Foundation
import FoodGenericSearch
import FoodLedgerApplication
import FoodLedgerDomain
import XCTest

/// composite-generic-ranking-v9: Taiwan rows follow UK and US rows by source unless promoted.
final class RegionalSourceOrderTests: XCTestCase {
    private func request(_ text: String) throws -> GenericFoodSearchRequest {
        try .init(text: LedgerText(text), capturedAt: Date(timeIntervalSince1970: 1_700_000_000), locale: LedgerText("en_GB"))
    }
    private func names(_ search: any GenericFoodSearching, _ text: String) throws -> [(name: String, taiwan: Bool)] {
        guard case let .confirmation(route) = try search.search(request(text)) else { return [] }
        XCTAssertEqual(route.confirmation.evidence.first?.originalPayload, .text(try LedgerText(text)))
        XCTAssertEqual(route.confirmation.evidence.first?.captureMethodVersion.value, CompositeGenericFoodSearch.version)
        return route.matches.map { ($0.candidate.name.value, $0.candidate.candidate.recordID.value.hasPrefix("tfda:")) }
    }

    func testPolicyPromotesTaiwanOnlyForMarketNamedTaiwanOrChineseCharacters() {
        XCTAssertEqual(CompositeGenericFoodSearch.version, "composite-generic-ranking-v9")
        XCTAssertTrue(RegionalSourceOrderPolicy.promotesTaiwan(query: "120 g banana", marketIsTaiwan: true))
        for query in ["Taiwan banana", "taiwanese beef noodles", "香蕉", "120g 芭樂", "banana 台灣"] {
            XCTAssertTrue(RegionalSourceOrderPolicy.promotesTaiwan(query: query, marketIsTaiwan: false), query)
        }
        for query in ["120 g banana", "Thai banana", "taiwanbanana", "バナナ", "guava", ""] {
            XCTAssertFalse(RegionalSourceOrderPolicy.promotesTaiwan(query: query, marketIsTaiwan: false), query)
        }
    }

    func testTaiwanRowsFollowUKAndUSRowsUnlessPromoted() throws {
        let ids = RandomLedgerIDGenerator()
        let cofid = try CoFIDGenericFoodSearch(ids: ids), usda = try USDAGenericFoodSearch(ids: ids), tfda = try TFDAGenericFoodSearch(ids: ids)
        var marketIsTaiwan = false
        let composite = CompositeGenericFoodSearch(sources: [cofid, usda], regionalSources: [tfda], promotesRegional: { request in
            RegionalSourceOrderPolicy.promotesTaiwan(query: request.text.value, marketIsTaiwan: marketIsTaiwan)
        }, ids: ids)
        for query in ["120 g banana", "guava", "rice"] {
            let deferred = try names(composite, query)
            let firstTaiwan = try XCTUnwrap(deferred.firstIndex { $0.taiwan }, query)
            XCTAssertGreaterThan(firstTaiwan, 0, query)
            XCTAssertTrue(deferred[firstTaiwan...].allSatisfy(\.taiwan), query)
        }
        let banana = try names(composite, "120 g banana")
        XCTAssertEqual(banana.first?.name, "Bananas, raw")
        XCTAssertLessThan(try XCTUnwrap(banana.firstIndex { $0.name == "Bananas, flesh only" }),
                          try XCTUnwrap(banana.firstIndex { $0.taiwan }))
        // Promotion restores v8 interleaving, identical to listing TFDA as an ordinary source.
        marketIsTaiwan = true
        let interleaved = CompositeGenericFoodSearch(sources: [cofid, usda, tfda], ids: ids)
        for query in ["120 g banana", "guava", "rice"] {
            XCTAssertEqual(try names(composite, query).map(\.name), try names(interleaved, query).map(\.name), query)
            XCTAssertEqual(try names(composite, query).first?.taiwan, true, query)
        }
        marketIsTaiwan = false
        XCTAssertEqual(try names(composite, "香蕉").first?.taiwan, true)
        // Without regional sources, v9 is the v8 two-source composite.
        let twoSource = CompositeGenericFoodSearch(sources: [cofid, usda], ids: ids)
        XCTAssertFalse(try names(twoSource, "120 g banana").contains { $0.taiwan })
    }
}
