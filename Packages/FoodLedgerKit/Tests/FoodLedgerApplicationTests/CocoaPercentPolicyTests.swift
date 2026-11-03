import FoodLedgerApplication
import XCTest

/// cocoa-percent-policy-v1 (#382, docs/cocoa-aware-search-v1.md): pure band reading,
/// eligibility exceptions and tier keys. Synthetic names only.
final class CocoaPercentPolicyTests: XCTestCase {
    private let estimateID = CocoaPercentPolicy.estimate100RecordID

    func testDeclaredBandsAreReadFromNamesAndDescriptionsOnly() {
        func band(_ name: String, _ description: String? = nil) -> CocoaPercentPolicy.Band? {
            CocoaPercentPolicy.band(name: name, description: description, recordID: nil)
        }
        XCTAssertEqual(CocoaPercentPolicy.version, "cocoa-percent-policy-v1")
        XCTAssertEqual(band("Chocolate, dark, 45- 59% cacao solids"), .declared(lower: 45, upper: 59))
        XCTAssertEqual(band("Chocolate, dark, 70-85% cacao solids"), .declared(lower: 70, upper: 85))
        XCTAssertEqual(band("Chocolate, dark, 70\u{2013}85% cocoa solids"), .declared(lower: 70, upper: 85))
        XCTAssertEqual(band("Chocolate, plain", "6 bars, 3 brands; 36-50% cocoa solids"), .declared(lower: 36, upper: 50))
        XCTAssertEqual(band("Dark chocolate, 70% cocoa, bar"), .declared(lower: 70, upper: 70))
        XCTAssertEqual(band("Chocolate, dark, 85% cacao solids"), .declared(lower: 85, upper: 85))
        // A parenthesised blend is not a band.
        XCTAssertEqual(band("Candies, chocolate, dark, NFS (45-59% cacao solids 90%; 60-69% cacao solids 5%; 70-85% cacao solids 5%)"), .blend)
        // Invalid or ambiguous readings give no band.
        XCTAssertNil(band("Chocolate, dark, 85-70% cacao solids"))
        XCTAssertNil(band("Chocolate, dark, 120% cocoa"))
        XCTAssertNil(band("Chocolate, dark, 70% cocoa", "85% cocoa solids"))
        XCTAssertNil(band("Chocolate, dark, with crème or mint fondant centres", "10 samples, 8 products"))
        XCTAssertNil(band("Milk, 2% fat"))
        // Agreeing name and description are one band.
        XCTAssertEqual(band("Chocolate, dark, 70% cocoa", "70% cocoa solids"), .declared(lower: 70, upper: 70))
    }

    func testOnlyTheApprovedRecordIsTheHundredPercentEstimate() {
        XCTAssertEqual(CocoaPercentPolicy.band(name: "Baking chocolate, unsweetened, squares", description: nil, recordID: estimateID), .estimate100)
        let release = estimateID.replacingOccurrences(of: ":fdc:167568", with: "")
        for other in ["167567", "167999"] {
            XCTAssertNil(CocoaPercentPolicy.band(name: "Baking chocolate, unsweetened, liquid", description: nil, recordID: "\(release):fdc:\(other)"))
        }
        // The name alone never earns the estimate.
        XCTAssertNil(CocoaPercentPolicy.band(name: "Baking chocolate, unsweetened, squares", description: nil, recordID: "other:fdc:167568"))
    }

    func testEligibilityExceptionsAreClosed() {
        func admits(_ query: String, _ name: String, _ description: String? = nil, id: String? = nil) -> Bool {
            let parsed = FoodQueryParser.parse(query)
            let terms = Set(GenericFoodRankingPolicy.terms(parsed.food ?? ""))
            return CocoaPercentPolicy.admits(name: name, description: description, recordID: id, query: parsed, foodTerms: terms)
        }
        XCTAssertTrue(admits("dark chocolate 100%", "Baking chocolate, unsweetened, squares", id: estimateID))
        XCTAssertTrue(admits("100% cacao", "Chocolate, plain", "36-50% cocoa solids"))
        XCTAssertTrue(admits("plain chocolate 70% cocoa solids", "Chocolate, dark, 70-85% cacao solids"))
        // A chocolate type the user did not name is never admitted by the exception.
        XCTAssertFalse(admits("dark chocolate 30%", "Chocolate, milk, 30% cocoa"))
        XCTAssertFalse(admits("dark chocolate 30%", "Chocolate, white, 30% cocoa"))
        // Blends, unbanded rows and other foods are not admitted.
        XCTAssertFalse(admits("dark chocolate 85%", "Candies, chocolate, dark, NFS (45-59% cacao solids 90%)"))
        XCTAssertFalse(admits("dark chocolate 85%", "Chocolate, fancy and filled"))
        XCTAssertFalse(admits("mint dark chocolate 70%", "Chocolate, dark, 70-85% cacao solids"))
        XCTAssertFalse(admits("85% cocoa", "Cocoa powder, 85% cocoa"))
        // Without a cocoa percentage only the UK name equivalence applies.
        XCTAssertTrue(admits("dark chocolate", "Chocolate, plain", "36-50% cocoa solids"))
        XCTAssertFalse(admits("dark chocolate", "Chocolate, dark, 70-85% cacao solids"))
        XCTAssertFalse(admits("salmon chocolate", "Chocolate, plain"))
        XCTAssertFalse(admits("chocolate", "Chocolate, plain"))
    }

    func testTierKeysFollowTheSpecifiedOrder() {
        let bands: [CocoaPercentPolicy.Band?] = [
            nil, .declared(lower: 45, upper: 59), .declared(lower: 60, upper: 69), .declared(lower: 70, upper: 85),
            .estimate100, .blend, .declared(lower: 36, upper: 50)
        ]
        func order(_ value: Double) -> [Int] {
            let keys = CocoaPercentPolicy.tierKeys(bands, requested: value)
            return bands.indices.sorted { keys[$0] == keys[$1] ? $0 < $1 : keys[$0] < keys[$1] }
        }
        XCTAssertEqual(order(85), [3, 2, 4, 1, 6, 0, 5], "70 to 85 contains 85; then nearest by distance")
        XCTAssertEqual(order(90), [3, 4, 2, 1, 6, 0, 5], "86 to 99: the greatest band below first")
        XCTAssertEqual(order(99), [3, 4, 2, 1, 6, 0, 5])
        XCTAssertEqual(order(100), [4, 3, 2, 1, 6, 0, 5])
        XCTAssertEqual(order(50), [1, 6, 2, 3, 4, 0, 5], "both bands containing 50 keep their order")
        XCTAssertEqual(order(30).first, 6, "below every band: the nearest band first")
    }

    func testImpliedChocolateIsDetectedFromTheOriginalText() {
        XCTAssertTrue(CocoaPercentPolicy.impliesChocolate(FoodQueryParser.parse("100% cacao")))
        XCTAssertTrue(CocoaPercentPolicy.impliesChocolate(FoodQueryParser.parse("dark 90% cocoa")))
        XCTAssertFalse(CocoaPercentPolicy.impliesChocolate(FoodQueryParser.parse("85% cocoa chocolate")))
        XCTAssertFalse(CocoaPercentPolicy.impliesChocolate(FoodQueryParser.parse("dark chocolate 85%")))
        XCTAssertEqual(CocoaPercentPolicy.noResultNote(query: FoodQueryParser.parse("100% cacao")), "Searched as chocolate with 100% cocoa.")
        XCTAssertNil(CocoaPercentPolicy.noResultNote(query: FoodQueryParser.parse("dark chocolate 85%")))
    }

    func testParserV11CocoaAndPerCentRules() {
        XCTAssertEqual(FoodQueryParser.version, "food-query-parser-v11")
        let searches: [(String, String, [String: String])] = [
            ("100% cacao", "chocolate", ["cocoa_percent": "100"]),
            ("dark 90% cocoa", "dark chocolate", ["cocoa_percent": "90"]),
            ("85% cocoa chocolate", "chocolate", ["cocoa_percent": "85"]),
            ("cocoa solids 85% chocolate", "chocolate", ["cocoa_percent": "85"]),
            ("dark chocolate 85 per cent", "dark chocolate", ["cocoa_percent": "85"]),
            ("10 per cent fat yoghurt", "yoghurt", ["fat_percent": "10"])
        ]
        for (query, food, attributes) in searches {
            let parsed = FoodQueryParser.parse(query)
            XCTAssertEqual(parsed.route, .search, query)
            XCTAssertEqual(parsed.food, food, query)
            XCTAssertEqual(parsed.attributes, attributes, query)
        }
        for query in ["100% cocoa powder", "100% cacao paste", "70% cocoa beans", "85% cacao bar", "85% hot cocoa"] {
            let parsed = FoodQueryParser.parse(query)
            XCTAssertEqual(parsed.route, .clarify, query)
            XCTAssertNil(parsed.attributes["cocoa_percent"], query)
        }
        XCTAssertTrue(FoodQueryParser.parse("10 per cent less fat yoghurt").reasons.contains("relative_percentage"))
        XCTAssertTrue(FoodQueryParser.parse("dark chocolate 70% cocoa 85% cocoa").reasons.contains("conflicting_variants"))
        XCTAssertEqual(FoodQueryParser.parse("cocoa solids 90").reasons, ["unresolved_number"])
    }
}
