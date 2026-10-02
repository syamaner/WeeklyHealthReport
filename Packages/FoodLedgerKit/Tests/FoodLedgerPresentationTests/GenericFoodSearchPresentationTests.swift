import FoodLedgerApplication
import FoodLedgerDomain
import FoodLedgerTestSupport
import FoodLedgerPresentation
import XCTest

@MainActor
final class GenericFoodSearchPresentationTests: XCTestCase {
    func testHalfItemCountAndHouseholdDiscoveryKeepQuantityReview() throws {
        let spy = SearchSpy()
        let model = GenericFoodSearchViewModel(searcher: spy, locale: try LedgerText("en_GB"))
        model.query = "half a green pepper"
        model.search()
        XCTAssertEqual(spy.callCount, 1)
        XCTAssertEqual(spy.lastRequest?.retrievalText, "green pepper")
        XCTAssertEqual(model.parsedQuery?.quantity?.value, 0.5)
        XCTAssertEqual(model.parsedQuery?.quantity?.unit, "count")
        model.query = "half a cup pepper sauce"
        model.search()
        XCTAssertEqual(spy.callCount, 2)
        XCTAssertNil(model.parsedQuery?.quantity)
        XCTAssertNil(model.interpretation?.quantitySuggestion)
    }

    func testCookingDescriptorHandoffRetainsMethodAndRejectsConflictingState() throws {
        let spy = SearchSpy()
        let model = GenericFoodSearchViewModel(searcher: spy, locale: try LedgerText("en_GB"))
        for (query, method) in [("90g roasted lamb", "roasted"), ("90g boiled carrots", "boiled"), ("90g pan-fried beef", "pan-fried")] {
            model.query = query
            model.search()
            XCTAssertEqual(spy.lastRequest?.identity.preparation?.kind, .cooked)
            XCTAssertTrue(spy.lastRequest?.retrievalText.contains(method) == true)
            XCTAssertEqual(spy.lastRequest?.text.value, query)
            let calls = spy.callCount
            model.preparationFilter = .raw
            model.search()
            XCTAssertEqual(spy.callCount, calls)
            model.preparationFilter = nil
            model.search(identity: GenericFoodIdentityQuery(preparation: try PreparationState(kind: .raw)))
            XCTAssertEqual(spy.callCount, calls)
        }
    }

    func testWebDiscoveryIsOfferedOnlyAfterCompletedOfflineSearch() throws {
        let search = SearchSpy()
        let model = GenericFoodSearchViewModel(searcher: search, locale: try LedgerText("en_GB"))
        XCTAssertFalse(model.canOfferWebDiscovery)
        model.query = "Greek yoghurt 10% fat"
        XCTAssertFalse(model.canOfferWebDiscovery)
        let evidence = try CaptureEvidence(evidenceID: LedgerID("00000000-0000-0000-0000-000000000011"),
            kind: .genericSearch, capturedAt: Date(), locale: LedgerText("en_GB"),
            captureMethod: LedgerText("typed_generic_food_search"), captureMethodVersion: LedgerText("test-v1"),
            originalPayload: .text(LedgerText(model.query)))
        search.outcome = .noResult(GenericFoodNoResultRoute(evidence: evidence, suggestedQueries: []))
        model.search()
        XCTAssertTrue(model.canOfferWebDiscovery)
        model.query = "whole milk"
        XCTAssertFalse(model.canOfferWebDiscovery)
        model.search()
        XCTAssertTrue(model.canOfferWebDiscovery)
        model.decline()
        XCTAssertFalse(model.canOfferWebDiscovery)
    }

    func testParsedQuantityRetainsOriginalAndAmbiguityDoesNotCallSearcher() throws {
        let search = SearchSpy()
        let model = GenericFoodSearchViewModel(searcher: search, locale: try LedgerText("en_GB"))
        model.query = "200g Greek youghurt 10% fat"
        model.search()
        XCTAssertEqual(search.lastRequest?.text.value, model.query)
        XCTAssertEqual(search.lastRequest?.retrievalText, "greek yoghurt")
        XCTAssertEqual(model.parsedQuery?.quantity?.value, 200)
        let calls = search.callCount
        model.query = "one mug coffee 15g grounds"
        model.search()
        XCTAssertEqual(search.callCount, calls)
        XCTAssertNil(model.parsedQuery?.quantity)
    }

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

    func testExplicitSuggestionRetainsOriginalEvidenceAndPreparationFilter() throws {
        let spy = SearchSpy()
        let model = GenericFoodSearchViewModel(searcher: spy, locale: try LedgerText("en_GB"))
        let evidence = try CaptureEvidence(evidenceID: LedgerID("00000000-0000-0000-0000-000000000001"), kind: .genericSearch, capturedAt: Date(), locale: LedgerText("en_GB"), captureMethod: LedgerText("typed_generic_food_search"), captureMethodVersion: LedgerText("test-v1"), originalPayload: .text(LedgerText("chiken breast")))
        let route = GenericFoodNoResultRoute(evidence: evidence, suggestedQueries: ["chicken breast"])
        model.preparationFilter = .raw
        spy.outcome = .noResult(route)
        model.query = "chiken breast"
        model.search()
        model.searchSuggestion("chicken breast", from: route)
        XCTAssertEqual(spy.lastRequest?.text.value, "chicken breast")
        XCTAssertEqual(spy.lastRequest?.additionalEvidence, [evidence])
        XCTAssertEqual(spy.lastRequest?.identity.preparation?.kind, .raw)
        model.searchSuggestion("turkey", from: route)
        XCTAssertEqual(spy.callCount, 2)
    }

    func testDeclineMovesToExplicitNoSelectionState() throws {
        let model = GenericFoodSearchViewModel(
            searcher: SearchSpy(),
            locale: try LedgerText("en_GB")
        )

        model.decline()

        XCTAssertEqual(model.phase, .declined)
    }
    func testMeasuredAndCompoundDiscoveryKeepsUnresolvedAmountsOutOfConfirmation() throws {
        let spy = SearchSpy()
        let model = GenericFoodSearchViewModel(searcher: spy, locale: try LedgerText("en_GB"), now: { Date(timeIntervalSince1970: 0) })
        for text in ["73g smoked ham slices", "81g wholemeal and rye sourdough"] {
            let count = spy.callCount
            model.query = text
            model.search()
            XCTAssertEqual(spy.callCount, count + 1, text)
            XCTAssertEqual(spy.lastRequest?.text.value, text)
            XCTAssertEqual(spy.lastRequest?.retrievalText, model.parsedQuery?.food)
            if text.contains(" and ") {
                XCTAssertTrue(model.interpretation?.needsCompositionReview == true)
                XCTAssertNil(model.parsedQuery?.quantity)
            } else { XCTAssertEqual(model.parsedQuery?.quantity?.unit, "g") }
        }
        for text in ["2 slices ham", "about 73g ham slices", "81g bread 24g cheese"] {
            let count = spy.callCount
            model.query = text
            model.search()
            XCTAssertEqual(spy.callCount, count + 1, text)
            XCTAssertNil(model.parsedQuery?.quantity, text)
        }
        XCTAssertNil(model.confirmation(at: 0))
    }

}

private final class SearchSpy: GenericFoodSearching, @unchecked Sendable {
    var outcome: GenericFoodSearchOutcome?
    private(set) var callCount = 0
    private(set) var lastRequest: GenericFoodSearchRequest?

    func search(_ request: GenericFoodSearchRequest) throws -> GenericFoodSearchOutcome {
        lastRequest = request
        callCount += 1
        if let outcome { return outcome }
        throw SearchError.unexpectedCall
    }

    private enum SearchError: Error {
        case unexpectedCall
    }
}
