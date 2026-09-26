import FoodLedgerApplication
import FoodLedgerDomain
import FoodLedgerPresentation
import XCTest

@MainActor
final class GenericFoodSearchPresentationTests: XCTestCase {
    func testBlankQueryFailsWithoutCallingSearch() throws {
        let search = SearchSpy()
        let model = GenericFoodSearchViewModel(
            searcher: search,
            locale: try LedgerText("en_GB")
        )

        model.search()

        XCTAssertEqual(model.phase, .failed("Enter a food name before searching."))
        XCTAssertEqual(search.callCount, 0)
    }

    func testPreparationFilterIsSentAndExplicitIdentityIsPreserved() throws {
        let search = SearchSpy()
        let model = GenericFoodSearchViewModel(searcher: search, locale: try LedgerText("en_GB"))
        model.query = "Beef"
        model.preparationFilter = .raw
        model.search()
        XCTAssertEqual(search.lastRequest?.identity.preparation?.kind, .raw)
        model.search(identity: GenericFoodIdentityQuery(preparation: try PreparationState(kind: .cooked)))
        XCTAssertEqual(search.lastRequest?.identity.preparation?.kind, .cooked)
        model.preparationFilter = nil
        model.search()
        XCTAssertNil(search.lastRequest?.identity.preparation)
    }

    func testDeclineMovesToExplicitNoSelectionState() throws {
        let model = GenericFoodSearchViewModel(
            searcher: SearchSpy(),
            locale: try LedgerText("en_GB")
        )

        model.decline()

        XCTAssertEqual(model.phase, .declined)
    }
}

private final class SearchSpy: GenericFoodSearching, @unchecked Sendable {
    private(set) var callCount = 0
    private(set) var lastRequest: GenericFoodSearchRequest?

    func search(_ request: GenericFoodSearchRequest) throws -> GenericFoodSearchOutcome {
        lastRequest = request
        callCount += 1
        throw SearchError.unexpectedCall
    }

    private enum SearchError: Error {
        case unexpectedCall
    }
}
