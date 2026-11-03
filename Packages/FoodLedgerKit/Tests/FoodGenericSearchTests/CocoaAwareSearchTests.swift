import Foundation
import FoodGenericSearch
import FoodLedgerApplication
import FoodLedgerDomain
import XCTest

/// Cocoa-aware generic search v1 (#382, docs/cocoa-aware-search-v1.md) over the bundled
/// CoFID 2021 and USDA corpora. Synthetic query text only.
final class CocoaAwareSearchTests: XCTestCase {
    private static let usda170273 = "usda-legacy:2018-04-01:sha256:0fe8ae486a2c8eb42cb96413f058deb51863a46c8fb8eeb4b1fb45006dd338ef:fdc:170273"
    private static let usda167568 = CocoaPercentPolicy.estimate100RecordID

    private func request(_ text: String) throws -> GenericFoodSearchRequest {
        GenericFoodSearchRequest(text: try LedgerText(text), capturedAt: Date(timeIntervalSince1970: 1_700_000_000), locale: try LedgerText("en_GB"))
    }
    private func matches(_ search: any GenericFoodSearching, _ text: String) throws -> [GenericFoodMatch] {
        guard case let .confirmation(route) = try search.search(request(text)) else { return [] }
        XCTAssertEqual(FoodConfirmationState(input: route.confirmation).decision, .undecided, "Nothing is selected automatically")
        return route.matches
    }
    private func composite(_ ids: CocoaIDs = CocoaIDs()) throws -> CompositeGenericFoodSearch {
        CompositeGenericFoodSearch(sources: [try CoFIDGenericFoodSearch(ids: ids), try USDAGenericFoodSearch(ids: ids)], ids: ids)
    }

    func testVersionsAdvance() {
        XCTAssertEqual(CompositeGenericFoodSearch.version, "composite-generic-ranking-v10")
        XCTAssertEqual(GenericFoodRankingPolicy.version, "generic-representation-ranking-v9")
        XCTAssertEqual(CoFIDGenericFoodSearch.matcherVersion, "cofid-generic-ranking-v15")
        XCTAssertEqual(USDAGenericFoodSearch.matcherVersion, "usda-generic-ranking-v16")
    }

    func testCompositeFirstResultsMatchTheFrozenExpectations() throws {
        let search = try composite()
        let expectations: [(String, String)] = [
            ("dark chocolate 70%", "Chocolate, dark, 70-85% cacao solids"),
            ("dark chocolate 85%", "Chocolate, dark, 70-85% cacao solids"),
            ("90% dark chocolate", "Chocolate, dark, 70-85% cacao solids"),
            ("99% dark chocolate", "Chocolate, dark, 70-85% cacao solids"),
            ("dark chocolate 100%", "Baking chocolate, unsweetened, squares"),
            ("100% cacao", "Baking chocolate, unsweetened, squares"),
            ("85% cocoa chocolate", "Chocolate, dark, 70-85% cacao solids"),
            ("chocolate 85% cocoa solids", "Chocolate, dark, 70-85% cacao solids"),
            ("dark chocolate 85 per cent", "Chocolate, dark, 70-85% cacao solids"),
            ("dark chocolate 40%", "Chocolate, plain"),
            ("dark chocolate 30%", "Chocolate, plain"),
            ("mint dark chocolate", "Chocolate, dark, with crème or mint fondant centres"),
            ("plain chocolate", "Chocolate, plain")
        ]
        for (query, first) in expectations {
            XCTAssertEqual(try matches(search, query).first?.candidate.name.value, first, query)
        }
        XCTAssertEqual(try matches(search, "99% dark chocolate").dropFirst().first?.candidate.name.value, "Baking chocolate, unsweetened, squares")
        let fifty = try matches(search, "dark chocolate 50%").prefix(2).map(\.candidate.name.value)
        XCTAssertEqual(Set(fifty), ["Chocolate, plain", "Chocolate, dark, 45- 59% cacao solids"])
        let cocoaChocolate = try matches(search, "85% cocoa chocolate").prefix(3).map(\.candidate.name.value)
        XCTAssertFalse(cocoaChocolate.contains { $0.lowercased().contains("cocoa mix") || $0.lowercased().contains("beverage") }, "\(cocoaChocolate)")
        let dark = try matches(search, "dark chocolate").map(\.candidate.name.value)
        XCTAssertTrue(dark.contains("Chocolate, plain"), "UK name equivalence")
        XCTAssertNotEqual(dark.first, "Chocolate, dark, with crème or mint fondant centres")
        XCTAssertTrue(try matches(search, "salmon chocolate").isEmpty)
    }

    func testEachSourceAloneKeepsTheTargetRowInsideItsOwnCut() throws {
        let ids = CocoaIDs()
        let usda = try USDAGenericFoodSearch(ids: ids), cofid = try CoFIDGenericFoodSearch(ids: ids)
        for (query, record) in [("100% cacao", Self.usda167568), ("dark chocolate 100%", Self.usda167568), ("90% dark chocolate", Self.usda170273)] {
            XCTAssertEqual(try matches(usda, query).first?.candidate.candidate.recordID.value, record, query)
        }
        for query in ["100% cacao", "dark chocolate 40%", "dark chocolate"] {
            XCTAssertTrue(try matches(cofid, query).contains { $0.candidate.name.value == "Chocolate, plain" }, query)
        }
        XCTAssertEqual(try matches(cofid, "dark chocolate 40%").first?.candidate.name.value, "Chocolate, plain")
    }

    func testTheEstimateRecordStillHasItsApprovedName() throws {
        let row = try matches(USDAGenericFoodSearch(ids: CocoaIDs()), "baking chocolate").first { $0.candidate.candidate.recordID.value == Self.usda167568 }
        XCTAssertEqual(row?.candidate.name.value, "Baking chocolate, unsweetened, squares")
    }

    func testOrderingIsAPermutationOfTheSourceRowsWithUnchangedNutrients() throws {
        let ids = CocoaIDs()
        let cofid = try CoFIDGenericFoodSearch(ids: ids), usda = try USDAGenericFoodSearch(ids: ids)
        let search = CompositeGenericFoodSearch(sources: [cofid, usda], ids: ids)
        for query in ["dark chocolate 85%", "100% cacao", "dark chocolate"] {
            let combined = try matches(search, query).map(\.candidate.candidate)
            let separate = try (matches(cofid, query) + matches(usda, query)).map(\.candidate.candidate)
            XCTAssertEqual(combined.count, separate.count, query)
            for candidate in combined {
                let source = try XCTUnwrap(separate.first { $0.recordID == candidate.recordID }, query)
                XCTAssertEqual(candidate.nutrients, source.nutrients, query)
                XCTAssertEqual(candidate.identity, source.identity, query)
            }
        }
    }

    func testRegionalRowsStayLastEvenWhenTheyHoldTheBand() throws {
        // USDA as a deferred regional source: its banded rows follow every CoFID row.
        let ids = CocoaIDs()
        let search = CompositeGenericFoodSearch(sources: [try CoFIDGenericFoodSearch(ids: ids)],
                                                regionalSources: [try USDAGenericFoodSearch(ids: ids)], ids: ids)
        for query in ["dark chocolate 85%", "100% cacao", "dark chocolate 40%"] {
            let usdaFlags = try matches(search, query).map { $0.candidate.candidate.recordID.value.hasPrefix("usda") }
            XCTAssertEqual(usdaFlags, usdaFlags.sorted { !$0 && $1 }, query)
            XCTAssertEqual(usdaFlags.first, false, query)
        }
    }

    func testNotesCoverEveryBandCase() throws {
        let search = try composite()
        func note(_ query: String, _ name: String) throws -> String? {
            let parsed = FoodQueryParser.parse(query)
            let match = try XCTUnwrap(try matches(search, query).first { $0.candidate.name.value == name }, "\(query): \(name)")
            return FoodQueryCandidateAssessment.note(query: parsed, candidate: match.candidate)
        }
        XCTAssertEqual(try note("dark chocolate 85%", "Chocolate, dark, 70-85% cacao solids"), "Source covers 70 to 85% cocoa.")
        XCTAssertEqual(try note("90% dark chocolate", "Chocolate, dark, 70-85% cacao solids"),
                       "Source covers 70 to 85% cocoa; you asked for 90%. Estimate only.")
        XCTAssertEqual(try note("dark chocolate 100%", "Baking chocolate, unsweetened, squares"),
                       "US unsweetened baking chocolate, used as a 100% cocoa estimate. It is not your bar; compare the label.")
        XCTAssertEqual(try note("dark chocolate 85%", "Baking chocolate, unsweetened, squares"),
                       "US unsweetened baking chocolate, a 100% cocoa estimate; you asked for 85%. Estimate only.")
        XCTAssertEqual(try note("dark chocolate 85%", "Chocolate, dark, with crème or mint fondant centres"),
                       "Cocoa percentage not stated by this source; you asked for 85%.")
        XCTAssertEqual(try note("dark chocolate 40%", "Chocolate, plain"), "Source covers 36 to 50% cocoa.")
        let nfs = "Candies, chocolate, dark, NFS (45-59% cacao solids 90%; 60-69% cacao solids 5%; 70-85% cacao solids 5%)"
        XCTAssertEqual(try note("dark chocolate nfs 50%", nfs), "No single cocoa band from this source; you asked for 50%.")
        for match in try matches(search, "100% cacao") {
            XCTAssertTrue(FoodQueryCandidateAssessment.note(query: FoodQueryParser.parse("100% cacao"), candidate: match.candidate)?
                .hasPrefix("Searched as chocolate with 100% cocoa.") == true, match.candidate.name.value)
        }
        for match in try matches(search, "dark chocolate") {
            XCTAssertNil(CocoaPercentPolicy.note(query: FoodQueryParser.parse("dark chocolate"), candidate: match.candidate))
        }
    }

    func testStoredEarlierMatcherVersionsStillRoundTrip() throws {
        for version in ["cofid-generic-ranking-v14", "usda-generic-ranking-v15", "composite-generic-ranking-v9"] {
            let metadata = try CandidateMatchMetadata(methodVersion: LedgerText(version), score: 0.5,
                materialDifferences: [LedgerText("Search terms: chocolate dark")], libraryAliases: [LedgerText("food:name:dark chocolate")])
            let encoded = try JSONEncoder().encode(metadata)
            let decoded = try JSONDecoder().decode(CandidateMatchMetadata.self, from: encoded)
            XCTAssertEqual(decoded, metadata, version)
            XCTAssertEqual(try JSONEncoder().encode(decoded), encoded, version)
        }
    }
}

private final class CocoaIDs: LedgerIDGenerating, @unchecked Sendable {
    private var value = 1
    func makeID<Tag>(_ tag: Tag.Type) throws -> LedgerID<Tag> {
        defer { value += 1 }
        return try LedgerID(String(format: "00000000-0000-0000-0000-%012x", value))
    }
}
