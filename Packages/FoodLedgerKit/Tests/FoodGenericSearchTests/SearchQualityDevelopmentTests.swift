import Foundation
import FoodGenericSearch
import FoodLedgerApplication
import FoodLedgerDomain
import XCTest

/// Public/synthetic development queries, not independent acceptance labels.
final class SearchQualityDevelopmentTests: XCTestCase {
    private func request(_ text: String, preparation: PreparationKind? = nil) throws -> GenericFoodSearchRequest {
        GenericFoodSearchRequest(text: try LedgerText(text), identity: GenericFoodIdentityQuery(preparation: try preparation.map { try PreparationState(kind: $0) }), capturedAt: Date(timeIntervalSince1970: 1700000000), locale: try LedgerText("en_GB"))
    }

    func testPrimaryFoodRanksAheadOfIngredientMentionsInBothSources() throws {
        for source in [try CoFIDGenericFoodSearch(ids: QualityIDs()) as any GenericFoodSearching, try USDAGenericFoodSearch(ids: QualityIDs())] {
            for query in ["apple", "banana", "egg", "milk", "salmon", "tomato"] {
                guard case let .confirmation(route) = try source.search(request(query)) else { return XCTFail(query) }
                let first = try XCTUnwrap(route.matches.first).candidate.name.value.lowercased()
                XCTAssertFalse(["sauce", "bread", "chocolate", "creme", "fishcake", "chutney"].contains { first.contains($0) }, first)
                XCTAssertTrue(route.matches.allSatisfy { (0...1).contains($0.candidate.candidate.matchMetadata!.score) })
            }
        }
    }

    func testTyposSuggestExplicitSearchAndNeverSelectANutritionRecord() throws {
        let ids = QualityIDs()
        let source = try CompositeGenericFoodSearch(sources: [CoFIDGenericFoodSearch(ids: ids), USDAGenericFoodSearch(ids: ids)], ids: ids)
        for (query, suggestion) in [("chiken breast", "chicken breast"), ("bananna", "banana"), ("yoghrt", "yoghurt")] {
            guard case let .noResult(route) = try source.search(request(query, preparation: .raw)) else { return XCTFail("No silent correction") }
            XCTAssertTrue(route.suggestedQueries.contains(suggestion))
            XCTAssertEqual(route.evidence.originalPayload, .text(try LedgerText(query)))
            // Correction still has to satisfy the original hard preparation constraint.
            if case let .confirmation(corrected) = try source.search(request(suggestion, preparation: .raw)) {
                XCTAssertTrue(corrected.matches.allSatisfy { $0.candidate.candidate.identity.preparation.kind == .raw })
            }
        }
        for query in ["salmon chocolate", "chicken zzqx", "and with the", "zzzzqqqq"] {
            guard case let .noResult(route) = try source.search(request(query)) else { return XCTFail(query) }
            XCTAssertTrue(route.suggestedQueries.isEmpty, query)
        }
    }

    func testSourceInterleavingAndEquivalentNamesRetainWholeRecords() throws {
        let ids = QualityIDs()
        let source = try CompositeGenericFoodSearch(sources: [CoFIDGenericFoodSearch(ids: ids), USDAGenericFoodSearch(ids: ids)], ids: ids)
        guard case let .confirmation(route) = try source.search(request("apple")) else { return XCTFail("apple") }
        XCTAssertEqual(route.matches[0].candidate.candidate.sourceReleaseID.value.hasPrefix("cofid"), true)
        XCTAssertEqual(route.matches[1].candidate.candidate.sourceReleaseID.value.hasPrefix("usda"), true)
        XCTAssertEqual(route.confirmation.expectedIdentity, route.matches[0].candidate.candidate.identity)
        for pair in [("chickpeas", "chick peas"), ("courgette", "zucchini")] {
            guard case let .confirmation(a) = try source.search(request(pair.0)), case let .confirmation(b) = try source.search(request(pair.1)) else { return XCTFail("Missing equivalent") }
            XCTAssertEqual(a.matches.map { $0.candidate.candidate.recordID }, b.matches.map { $0.candidate.candidate.recordID })
        }
    }

    func testDevelopmentReport() throws {
        let ids = QualityIDs()
        let search = try CompositeGenericFoodSearch(sources: [CoFIDGenericFoodSearch(ids: ids), USDAGenericFoodSearch(ids: ids)], ids: ids)
        let queries = ["apple", "apples", "banana", "eggs", "potatoes", "sweet potato", "sweet potatoes", "tomatoes", "chickpeas", "chick peas", "lentils", "salmon", "tuna", "chicken breast", "skinless chicken breast", "ribeye", "rib eye", "rib-eye", "sirloin steak", "minced beef", "olive oil", "brown rice", "porridge oats", "oats", "milk", "greek yoghurt", "greek yogurt", "courgette", "zucchini", "aubergine", "eggplant", "cottage cheese", "wholemeal bread", "baked beans", "chicken curry", "Fish & Chips", "Fiash and Chips", "chiken breast", "bananna", "yoghrt", "salmon chocolate", "chicken zzqx", "and with the", "zzzzqqqq"]
        var rows: [[String: Any]] = []
        for query in queries {
            let request = GenericFoodSearchRequest(text: try LedgerText(query), capturedAt: Date(timeIntervalSince1970: 1700000000), locale: try LedgerText("en_GB"))
            switch try search.search(request) {
            case let .confirmation(route):
                XCTAssertEqual(route.confirmation.evidence.first?.originalPayload, .text(try LedgerText(query)))
                rows.append(["query": query, "names": route.matches.map { $0.candidate.name.value }, "records": route.matches.map { $0.candidate.candidate.recordID.value }, "sources": route.matches.map { $0.candidate.candidate.sourceReleaseID.value }, "suggestions": []])
            case let .noResult(route):
                XCTAssertEqual(route.evidence.originalPayload, .text(try LedgerText(query)))
                rows.append(["query": query, "names": [], "records": [], "sources": [], "suggestions": route.suggestedQueries])
            }
        }
        if let path = ProcessInfo.processInfo.environment["WHR_SEARCH_QUALITY_REPORT"] {
            let data = try JSONSerialization.data(withJSONObject: ["version": "search-development-v3", "independentAcceptance": false, "rows": rows], options: [.prettyPrinted, .sortedKeys])
            try data.write(to: URL(fileURLWithPath: path))
        }
    }
}

private final class QualityIDs: LedgerIDGenerating, @unchecked Sendable {
    private var value = 1
    func makeID<Tag>(_ tag: Tag.Type) throws -> LedgerID<Tag> {
        defer { value += 1 }
        return try LedgerID(String(format: "00000000-0000-0000-0000-%012x", value))
    }
}
