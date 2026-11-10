import Foundation
import FoodGenericSearch
import FoodLedgerApplication
import FoodLedgerDomain
import FoodLedgerPresentation
import XCTest

/// cocoa-percent-policy-v1 (#382): the short row caution comes from the policy; presentation shows it.
final class CocoaCautionPresentationTests: XCTestCase {
    func testRowCautionsShowTheCocoaBand() throws {
        let ids = CautionIDs()
        let search = CompositeGenericFoodSearch(sources: [try CoFIDGenericFoodSearch(ids: ids), try USDAGenericFoodSearch(ids: ids)], ids: ids)
        func caution(_ query: String, _ name: String) throws -> String? {
            let request = GenericFoodSearchRequest(text: try LedgerText(query), capturedAt: Date(timeIntervalSince1970: 1_700_000_000), locale: try LedgerText("en_GB"))
            guard case let .confirmation(route) = try search.search(request) else { XCTFail(query); return nil }
            let match = try XCTUnwrap(route.matches.first { $0.candidate.name.value == name }, "\(query): \(name)")
            return FoodSearchResultText.caution(query: request.parsedQuery, candidate: match.candidate, requestedPreparation: nil, isRecipe: false)
        }
        XCTAssertEqual(try caution("dark chocolate 85%", "Chocolate, dark, 70-85% cacao solids"), "70 to 85% cocoa")
        XCTAssertEqual(try caution("90% dark chocolate", "Chocolate, dark, 70-85% cacao solids"), "70 to 85% cocoa · requested 90%")
        XCTAssertEqual(try caution("dark chocolate 100%", "Baking chocolate, unsweetened, squares"), "100% cocoa estimate · baking chocolate")
        XCTAssertEqual(try caution("dark chocolate 85%", "Baking chocolate, unsweetened, squares"), "100% cocoa estimate · requested 85%")
        XCTAssertEqual(try caution("dark chocolate 85%", "Chocolate, dark, with crème or mint fondant centres"), "Cocoa % not stated")
        let nfs = "Candies, chocolate, dark, NFS (45-59% cacao solids 90%; 60-69% cacao solids 5%; 70-85% cacao solids 5%)"
        let rangeRequest = GenericFoodSearchRequest(text: try LedgerText("70-85% dark chocolate"), capturedAt: Date(timeIntervalSince1970: 1_700_000_000), locale: try LedgerText("en_GB"))
        guard case let .confirmation(range) = try search.search(rangeRequest) else { return XCTFail("range query") }
        let blend = try XCTUnwrap(range.matches.first { $0.candidate.name.value == nfs })
        XCTAssertEqual(FoodSearchResultText.caution(query: FoodQueryParser.parse("dark chocolate 50%"), candidate: blend.candidate,
                                                    requestedPreparation: nil, isRecipe: false), "No single cocoa band")
        XCTAssertNil(try caution("dark chocolate", "Chocolate, plain"))
    }

    func testTheChocolateInterpretationIsShownOnce() {
        XCTAssertEqual(FoodSearchResultText.interpretationNote(FoodQueryParser.parse("100% cacao")), "Searched as chocolate with 100% cocoa.")
        XCTAssertEqual(FoodSearchResultText.interpretationNote(FoodQueryParser.parse("dark 90% cocoa")), "Searched as chocolate with 90% cocoa.")
        XCTAssertNil(FoodSearchResultText.interpretationNote(FoodQueryParser.parse("dark chocolate 85%")))
        XCTAssertNil(FoodSearchResultText.interpretationNote(nil))
    }

    /// #391: the Best matches split keeps cocoa-admitted rows, so the screen shows the ranked order.
    @MainActor
    func testBestMatchesKeepTheCocoaRankedOrder() throws {
        let ids = CautionIDs()
        let model = try GenericFoodSearchViewModel(searcher: CompositeGenericFoodSearch(
            sources: [try CoFIDGenericFoodSearch(ids: ids), try USDAGenericFoodSearch(ids: ids)], ids: ids), locale: LedgerText("en_GB"))
        func close(_ query: String) -> [String] {
            model.query = query; model.search()
            return model.closeMatches.map(\.candidate.name.value)
        }
        let estimate = "Baking chocolate, unsweetened, squares", band = "Chocolate, dark, 70-85% cacao solids"
        XCTAssertEqual(close("dark chocolate 100%").prefix(2), [estimate, band])
        XCTAssertEqual(close("90% dark chocolate").prefix(2), [band, estimate])
        XCTAssertEqual(close("99% dark chocolate").prefix(2), [band, estimate])
        XCTAssertEqual(close("dark chocolate 85%").first, band)
        XCTAssertEqual(close("100% cacao").first, estimate)
        for query in ["dark chocolate 100%", "90% dark chocolate"] {
            _ = close(query)
            let order = model.bestMatches.map(\.searchID), closeIDs = Set(model.closeMatches.map(\.searchID))
            XCTAssertEqual(model.closeMatches.map(\.searchID), order.filter(closeIDs.contains), "grouping keeps the ranked order: \(query)")
            XCTAssertEqual(Set((model.closeMatches + model.otherMatches).map(\.searchID)), Set(order), query)
            XCTAssertFalse(model.closeMatches.contains { $0.candidate.name.value.lowercased().contains("milk") }, query)
        }
        // #452: the comma and spaced phrasings keep the cocoa ranking and its Best matches split.
        for query in ["dark chocolate, 90%", "90 % dark chocolate", "95 per cent dark chocolate", "dark chocolate, 95%"] {
            XCTAssertEqual(close(query).prefix(2), [band, estimate], query)
            XCTAssertNil(model.interpretation?.quantitySuggestion, query)
        }
        XCTAssertEqual(close("dark chocolate, 70%").first, band)
        XCTAssertEqual(close("dark chocolate, 100%").first, estimate)
        // Without a cocoa percentage the #308 name rule alone decides.
        XCTAssertFalse(close("dark chocolate").contains(estimate))
        XCTAssertFalse(close("baking chocolate").isEmpty)
    }
}

private final class CautionIDs: LedgerIDGenerating, @unchecked Sendable {
    private var value = 1
    func makeID<Tag>(_ tag: Tag.Type) throws -> LedgerID<Tag> {
        defer { value += 1 }
        return try LedgerID(String(format: "00000000-0000-0000-0000-%012x", value))
    }
}
