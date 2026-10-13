import Foundation
@testable import FoodGenericSearch
import FoodLedgerApplication
import FoodLedgerDomain
import XCTest

/// food-lexical-terms-v9 through the actual bundled adapters (docs/food-lexical-terms-v9.md).
final class LexicalPluralRetrievalTests: XCTestCase {
    private let capturedAt = Date(timeIntervalSince1970: 1700000000)

    private func request(_ text: String) throws -> GenericFoodSearchRequest {
        GenericFoodSearchRequest(text: try LedgerText(text), capturedAt: capturedAt, locale: try LedgerText("en_GB"))
    }

    private func names(_ source: any GenericFoodSearching, _ text: String) throws -> [String] {
        guard case let .confirmation(route) = try source.search(request(text)) else { return [] }
        XCTAssertEqual(route.confirmation.evidence.first?.originalPayload, .text(try LedgerText(text)))
        XCTAssertEqual(FoodConfirmationState(input: route.confirmation).decision, .undecided, "Nothing is selected automatically")
        return route.matches.map { $0.candidate.name.value }
    }

    func testMatcherVersionsAdvanceWithTheLexicalPolicy() {
        XCTAssertEqual(CoFIDGenericFoodSearch.matcherVersion, "cofid-generic-ranking-v14")
        XCTAssertEqual(USDAGenericFoodSearch.matcherVersion, "usda-generic-ranking-v15")
        XCTAssertEqual(TFDAGenericFoodSearch.matcherVersion, "tfda-reviewed-ranking-v2")
        XCTAssertEqual(FoodLexicalPlurals.version, "food-lexical-terms-v9")
    }

    func testTFDAReviewedAliasesFoldPlurals() throws {
        // The reviewed alias is "dried wheat noodles"; v8 needed the plural spelling.
        let tfda = try TFDAGenericFoodSearch(ids: LexicalReplayIDs())
        for text in ["dried wheat noodle", "dried wheat noodles"] {
            guard case let .confirmation(route) = try tfda.search(request(text)) else { return XCTFail(text) }
            XCTAssertTrue(route.matches.contains { $0.candidate.name.value.hasPrefix("Wheat noodles, dried") }, "\(text) \(route.matches.map(\.candidate.name.value))")
        }
    }

    func testLiveSourceIdentityKeepsLiteralTerms() throws {
        // Manufacturer pages keep food-lexical-terms-v8: a singular query does not
        // match a name that only spells the plural.
        XCTAssertNil(ManufacturerSourcePageIdentity.score(query: try FoodSearchRemoteQuery(foodTerms: "walnut"), name: "Walnuts, halves"))
        XCTAssertNotNil(ManufacturerSourcePageIdentity.score(query: try FoodSearchRemoteQuery(foodTerms: "walnuts"), name: "Walnuts, halves"))
        XCTAssertEqual(GenericFoodSearchTerms.literalTokens("Walnuts, halves"), ["walnuts", "halves"])
        // The pancake form check is literal only when the caller says so.
        XCTAssertTrue(GenericFoodSearchTerms.acceptsFoodForm(name: "Pancake batters", query: ["pancake"], literal: true))
        XCTAssertFalse(GenericFoodSearchTerms.acceptsFoodForm(name: "Pancake batters", query: ["pancake"], literal: false))
    }

    func testTypoSuggestionsKeepTheUsersOwnWordsAndSourceSpellings() throws {
        let usda = try USDAGenericFoodSearch(ids: LexicalReplayIDs())
        guard case let .noResult(route) = try usda.search(request("fench fries")) else { return XCTFail("fench fries") }
        XCTAssertTrue(route.suggestedQueries.contains("french fries"), "\(route.suggestedQueries)")
        XCTAssertFalse(route.suggestedQueries.contains { $0.split(separator: " ").contains("fry") }, "\(route.suggestedQueries)")
        XCTAssertEqual(route.evidence.originalPayload, .text(try LedgerText("fench fries")))
    }

    func testCandidateNotesCompareLiteralTerms() throws {
        // Notes keep food-lexical-terms-v8 terms: "styles" is not folded to "style",
        // so the Greek-style caution is unchanged by plural folding.
        let cofid = try CoFIDGenericFoodSearch(ids: LexicalReplayIDs())
        guard case let .confirmation(route) = try cofid.search(request("Greek-style yoghurt")),
              let styled = route.matches.first(where: { $0.candidate.name.value.lowercased().contains("style") }) else { return XCTFail() }
        let note = FoodQueryCandidateAssessment.note(query: FoodQueryParser.parse("Greek styles yoghurt"), candidate: styled.candidate)
        XCTAssertTrue(note?.contains("Tentative alternative") == true, note ?? "nil")
    }

    func testPluralQueriesFindPluralAndSingularSourceNames() throws {
        let ids = LexicalReplayIDs()
        let cofid = try CoFIDGenericFoodSearch(ids: ids), usda = try USDAGenericFoodSearch(ids: ids)
        XCTAssertEqual(try names(cofid, "almonds").first, "Almonds, whole kernels")
        XCTAssertTrue(try names(usda, "almonds").contains("Nuts, almonds"))
        // Either number reaches names spelt in the other; among names that are not the
        // primary food, one spelt in the query's own number comes first.
        XCTAssertTrue(try names(usda, "walnut").contains("Nuts, walnuts, english"))
        XCTAssertTrue(try names(usda, "walnuts").contains("Oil, walnut"))
        XCTAssertEqual(try names(usda, "walnuts").first, "Nuts, walnuts, english")
        XCTAssertEqual(try names(usda, "walnut").first, "Oil, walnut")
        for query in ["walnuts", "cashews", "hazelnuts", "pistachios", "peanuts", "lentils", "chickpeas", "tomatoes", "potatoes"] {
            let found = try names(cofid, query) + names(usda, query)
            XCTAssertFalse(found.isEmpty, query)
        }
    }

    func testListLineWithAVaguePortionSearchesItsFoodWithoutAnAmount() throws {
        let line = try XCTUnwrap(FoodListParser.parse("a handful of almonds", convention: .fullStopDecimal).first)
        XCTAssertEqual(line.query, "almonds")
        XCTAssertNil(line.quantity)
        let ids = LexicalReplayIDs()
        let cofid = try CoFIDGenericFoodSearch(ids: ids), usda = try USDAGenericFoodSearch(ids: ids)
        let composite = CompositeGenericFoodSearch(sources: [cofid, usda], ids: ids)
        let found = try names(composite, line.query)
        XCTAssertEqual(found.first, "Almonds, whole kernels")
        XCTAssertTrue(found.contains("Nuts, almonds"))
    }

    func testWordsThatOnlyLookPluralStillFindThemselves() throws {
        let ids = LexicalReplayIDs()
        let cofid = try CoFIDGenericFoodSearch(ids: ids), usda = try USDAGenericFoodSearch(ids: ids)
        for word in ["hummus", "couscous", "asparagus", "molasses"] {
            let found = try names(cofid, word) + names(usda, word)
            XCTAssertFalse(found.isEmpty, word)
            XCTAssertTrue(found.allSatisfy { $0.lowercased().contains(word) }, word)
        }
    }
}

private final class LexicalReplayIDs: LedgerIDGenerating, @unchecked Sendable {
    private var value = 1
    func makeID<Tag>(_ tag: Tag.Type) throws -> LedgerID<Tag> {
        defer { value += 1 }
        return try LedgerID(String(format: "00000000-0000-0000-0000-%012x", value))
    }
}
