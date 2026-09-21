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

    func search(_ request: GenericFoodSearchRequest) throws -> GenericFoodSearchOutcome {
        callCount += 1
        throw SearchError.unexpectedCall
    }

    private enum SearchError: Error {
        case unexpectedCall
    }
}
