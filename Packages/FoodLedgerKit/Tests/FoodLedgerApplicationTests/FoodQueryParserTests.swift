import XCTest
@testable import FoodLedgerApplication

final class FoodQueryParserTests: XCTestCase {
    func testRawOrUncookedWithCookingMethodRequiresClarification() {
        for raw in ["raw", "uncooked"] {
            for method in ["cooked", "roast", "roasted", "boiled", "grilled", "broiled", "fried", "baked", "steamed", "braised", "poached", "stewed"] {
                for query in ["160g \(raw) \(method) cod", "160g \(method) \(raw) cod"] {
                    let parsed = FoodQueryParser.parse(query)
                    XCTAssertEqual(parsed.route, .clarify, query)
                    XCTAssertNil(parsed.quantity, query)
                    XCTAssertTrue(parsed.reasons.contains("conflicting_preparation"), query)
                    XCTAssertEqual(parsed.original, query)
                }
            }
        }
    }

    func testUncookedDoesNotMatchCookedAndMethodsRemainRetrievalTerms() {
        let uncooked = FoodQueryParser.parse("175g uncooked quinoa")
        XCTAssertEqual(uncooked.route, .search)
        XCTAssertEqual(uncooked.attributes["preparation"], "raw")
        XCTAssertEqual(uncooked.food, "quinoa")
        XCTAssertEqual(uncooked.quantity?.value, 175)
        for method in ["steamed", "grilled", "braised", "poached"] {
            let parsed = FoodQueryParser.parse("165g \(method) cod")
            XCTAssertEqual(parsed.route, .search)
            XCTAssertEqual(parsed.food, "\(method) cod")
            XCTAssertEqual(parsed.quantity?.value, 165)
        }
        XCTAssertEqual(FoodQueryParser.parse("100g raw strawberries").route, .search)
    }

    func testLiteralPercentageDiscoveryDoesNotResolveMeaningOrQuantity() {
        for text in ["150g FAGE Total 2% Greek yoghurt", "200g Acme 2.5% yoghurt", "Acme 0% yoghurt"] {
            let parsed = FoodQueryParser.parse(text)
            XCTAssertTrue(parsed.allowsCandidateDiscovery, text)
            XCTAssertEqual(parsed.route, .clarify)
            XCTAssertEqual(parsed.reasons, ["percentage_meaning_unknown"])
            XCTAssertNil(parsed.quantity); XCTAssertNil(parsed.attributes["fat_percent"])
            XCTAssertEqual(parsed.original, text)
        }
    }
    func testLiteralPercentageNeverBypassesOtherClarification() {
        for text in ["0g Fage 2% yoghurt", "-1g Fage 2% yoghurt", "Fage 2% or 5% yoghurt", "Fage 2% less yoghurt",
                     "100g Fage 2% yoghurt and honey", "about 100g Fage 2% yoghurt", "bowl Fage 2% yoghurt",
                     "100g Fage 2% yoghurt 200g", "101% yoghurt", "-2% yoghurt", "2% 2% yoghurt"] {
            XCTAssertFalse(FoodQueryParser.parse(text).allowsCandidateDiscovery, text)
        }
        XCTAssertTrue(FoodQueryParser.parse("100g rice").allowsCandidateDiscovery)
    }

    func testQuantityAndVariantAreSeparatedAndOriginalRetained() {
        let input = "200g Greek youghurt 10% fat"
        let p = FoodQueryParser.parse(input)
        XCTAssertEqual(p.original, input)
        XCTAssertEqual(p.food, "greek yoghurt")
        XCTAssertEqual(p.attributes["fat_percent"], "10")
        XCTAssertEqual(p.quantity?.value, 200)
        XCTAssertEqual(p.quantity?.unit, "g")
        XCTAssertEqual(p.route, .search)
    }
    func testConversionsDoNotCrossMassVolumeOrCount() {
        XCTAssertEqual(FoodQueryParser.parse("0.25kg rice").quantity?.value, 250)
        XCTAssertEqual(FoodQueryParser.parse("0.3l milk").quantity?.unit, "ml")
        XCTAssertEqual(FoodQueryParser.parse("2 eggs").quantity?.unit, "count")
        XCTAssertNil(FoodQueryParser.parse("2 eggs 100g").quantity)
        XCTAssertNil(FoodQueryParser.parse("one mug coffee 15g grounds").quantity)
    }
    func testPercentKindsAndIdentityRemainDistinct() {
        XCTAssertEqual(FoodQueryParser.parse("20g 90% dark chocolate").attributes["cocoa_percent"], "90")
        XCTAssertEqual(FoodQueryParser.parse("100% peanut butter").attributes["ingredient_percent"], "100")
        XCTAssertNotEqual(FoodQueryParser.parse("Greek-style yoghurt").food, FoodQueryParser.parse("Greek yoghurt").food)
        XCTAssertEqual(FoodQueryParser.parse("80g Acme yoghurt", recognisedBrands: ["Acme"]).attributes["brand"], "Acme")
    }
    func testAmbiguityNeverPrefills() {
        for q in ["-1g rice", "0g milk", "200g or 300g rice", "100g rice 200g", "raw cooked chicken", "0% fat 10% fat yoghurt", "200g yoghurt and 20g honey", "12:30", "half roast chicken", "a scoop protein powder", "one serving kefir"] {
            let p = FoodQueryParser.parse(q)
            XCTAssertNotEqual(p.route, .search, q)
            XCTAssertNil(p.quantity, q)
        }
        XCTAssertEqual(FoodQueryParser.parse("40g avocado without skin or stone").route, .search)
    }
    func testUnsupportedFractionsAndBoundsNeverPrefill() {
        for input in ["⅓ banana", "⅔ apple", "⅛ avocado", "≤100g rice", "≥200ml milk", "<80g pasta", "≈150g yoghurt"] {
            let parsed = FoodQueryParser.parse(input)
            XCTAssertEqual(parsed.original, input)
            XCTAssertEqual(parsed.route, .clarify, input)
            XCTAssertNil(parsed.quantity, input)
        }
    }
    func testExactUnicodeAndMixedQuantitiesRemainSupported() {
        for (input, value, unit) in [("１２０ｇ rice", 120.0, "g"), ("1 1/2 bananas", 1.5, "count"), ("1½ litres milk", 1500.0, "ml")] {
            let parsed = FoodQueryParser.parse(input)
            XCTAssertEqual(parsed.route, .search, input)
            XCTAssertEqual(parsed.quantity?.value, value, input)
            XCTAssertEqual(parsed.quantity?.unit, unit, input)
        }
        XCTAssertEqual(FoodQueryParser.parse("−100g rice").route, .reject)
    }

}
