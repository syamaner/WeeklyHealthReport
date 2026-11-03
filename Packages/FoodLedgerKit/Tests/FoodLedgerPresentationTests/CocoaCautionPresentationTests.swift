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
        XCTAssertEqual(try caution("dark chocolate nfs 50%",
            "Candies, chocolate, dark, NFS (45-59% cacao solids 90%; 60-69% cacao solids 5%; 70-85% cacao solids 5%)"), "No single cocoa band")
        XCTAssertNil(try caution("dark chocolate", "Chocolate, plain"))
    }
}

private final class CautionIDs: LedgerIDGenerating, @unchecked Sendable {
    private var value = 1
    func makeID<Tag>(_ tag: Tag.Type) throws -> LedgerID<Tag> {
        defer { value += 1 }
        return try LedgerID(String(format: "00000000-0000-0000-0000-%012x", value))
    }
}
