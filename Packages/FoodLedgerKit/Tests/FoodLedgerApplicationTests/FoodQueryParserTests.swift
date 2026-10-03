import XCTest
@testable import FoodLedgerApplication

final class FoodQueryParserTests: XCTestCase {
    func testHalfPepperFormsCaptureOnlyAnItemCount() {
        for input in ["half a green pepper", "½ yellow pepper", "1/2 orange pepper", "0.5 bell pepper"] {
            let parsed = FoodQueryParser.parse(input)
            XCTAssertEqual(parsed.route, .search, input)
            XCTAssertEqual(parsed.quantity?.value, 0.5, input)
            XCTAssertEqual(parsed.quantity?.unit, "count", input)
            XCTAssertEqual(parsed.original, input)
            XCTAssertFalse(parsed.food?.contains("half") == true)
        }
        for input in ["half green pepper soup", "half cup pepper sauce", "half a pack peppers", "half green pepper and cheese", "half green pepper 80g", "about half green pepper", "⅓ green pepper", "2½ green pepper 40g"] {
            let parsed = FoodQueryParser.parse(input)
            XCTAssertNotEqual(parsed.route, .search, input)
            XCTAssertNil(parsed.quantity, input)
        }
        for input in ["0 green pepper", "−½ yellow pepper"] {
            XCTAssertEqual(FoodQueryParser.parse(input).route, .reject, input)
            XCTAssertNil(FoodQueryParser.parse(input).quantity, input)
        }
    }

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

    func testNegatedPreparationRemainsInRetrievalEvidence() {
        for phrase in ["not roasted", "not   roasted", "never boiled", "non-roasted", "not pan fried"] {
            let text = "47g hazelnuts \(phrase)"
            let parsed = FoodQueryParser.parse(text)
            XCTAssertNil(parsed.attributes["preparation"], text)
            XCTAssertEqual(parsed.quantity?.value, 47, text)
            XCTAssertEqual(parsed.original, text)
            XCTAssertTrue(parsed.food?.contains(phrase.replacingOccurrences(of: "   ", with: " ")) == true, text)
        }
        let raw = FoodQueryParser.parse("87g raw lentils not cooked")
        XCTAssertEqual(raw.route, .search)
        XCTAssertEqual(raw.attributes["preparation"], "raw")
        XCTAssertTrue(raw.food?.contains("not cooked") == true)
        let cooked = FoodQueryParser.parse("97g boiled peas not raw")
        XCTAssertEqual(cooked.attributes["preparation"], "boiled")
        XCTAssertTrue(cooked.food?.contains("not raw") == true)
        let repeated = FoodQueryParser.parse("107g roasted almonds not roasted")
        XCTAssertEqual(repeated.attributes["preparation"], "roasted")
        XCTAssertTrue(repeated.food?.contains("not roasted") == true)
        let negatedBasis = FoodQueryParser.parse("117g lentils not cooked weight")
        XCTAssertNil(negatedBasis.attributes["weight_basis"])
        XCTAssertNil(negatedBasis.attributes["preparation"])
    }

    func testMeasuredSliceDescriptorsDoNotInventAHouseholdConversion() {
        for text in ["73g smoked ham slices", "112 grams cheese slice"] {
            let parsed = FoodQueryParser.parse(text)
            XCTAssertEqual(parsed.route, .search, text)
            XCTAssertEqual(parsed.quantity?.unit, "g", text)
            XCTAssertEqual(parsed.original, text)
        }
        for text in ["two slices cheese", "120ml cheese slice", "about 73g ham slices", "73g ham 2 slices", "73g ham slices 35g cheese", "0g ham slice", "73g ham slice and cheese"] {
            let parsed = FoodQueryParser.parse(text)
            XCTAssertNotEqual(parsed.route, .search, text)
            XCTAssertNil(parsed.quantity, text)
        }
    }

    func testBreadConjunctionIsBoundedAndWordOrderSymmetric() {
        for grains in ["rye and wheat", "wheat and rye", "rye and wholemeal", "wholemeal and rye"] {
            for kind in ["bread", "sourdough", "sourdough bread"] {
                let text = "81g \(grains) \(kind)"
                let parsed = FoodQueryParser.parse(text)
                XCTAssertEqual(parsed.route, .search, text)
                XCTAssertEqual(parsed.food, "\(grains) \(kind)", text)
                XCTAssertEqual(parsed.quantity?.value, 81, text)
            }
        }
        for text in ["81g wheat bread and rye bread", "81g rye and wheat bread with cheese", "81g rye and milk", "81g wheat and rye 24g cheese"] {
            XCTAssertNotEqual(FoodQueryParser.parse(text).route, .search, text)
        }
    }

}
