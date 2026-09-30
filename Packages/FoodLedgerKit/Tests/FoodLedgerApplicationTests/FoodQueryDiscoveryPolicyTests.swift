import Foundation
import XCTest
import FoodLedgerApplication
import FoodLedgerDomain

final class FoodQueryDiscoveryPolicyTests: XCTestCase {
    func testTravelDishesReachDiscoveryWithOriginalIngredientsAndUnconfirmedQuantity() {
        for text in [
            "Taiwanese breakfast scallion n pancake with eggs and sliced cheese",
            "Taiwanese breakfast scallion pancake with eggs and sliced cheese",
            "scallion pancake with egg and cheese",
            "spring onion pancake with eggs and sliced cheese",
            "pancake with cheese and egg",
            "200g scallion pancake with egg and cheese",
            "dan bing with cheese",
            "Taiwanese dan bing with egg and cheese",
            "omelette with cheese and mushrooms",
            "fried rice with egg and pork",
            "beef noodle soup with bok choy",
            "dumplings with pork and cabbage",
            "toast with egg and sliced cheese",
            "sandwich with chicken and cheese",
            "steak with noodles and fried egg",
            "bubble tea with tapioca pearls",
            "milk tea with pearls",
            "oyster omelette with sauce",
            "fried chicken with basil",
            "500ml bubble tea with pearls"
        ] {
            let parsed = FoodQueryParser.parse(text)
            XCTAssertTrue(parsed.allowsCandidateDiscovery, text)
            XCTAssertTrue(parsed.requiresRecipeReview, text)
            XCTAssertEqual(parsed.route, .clarify, text)
            XCTAssertNil(parsed.quantity, text)
            XCTAssertEqual(parsed.original, text)
            XCTAssertTrue(parsed.discoveryReviewMessage?.contains("proportions") == true)
        }
    }

    func testTravelDishDiscoveryDoesNotResolveAmbiguousOrdersOrMealLists() {
        for text in [
            "pancake and eggs",
            "pancake with egg and toast",
            "pancake with cheese and soup",
            "pancake with egg then coffee",
            "pancake with egg and 200ml milk",
            "100g pancake with 50g egg",
            "about 200g pancake with egg",
            "2 pancakes with egg",
            "one pancake with egg",
            "a bowl of beef noodle soup with egg",
            "-100g pancake with egg",
            "raw cooked pancake with egg",
            "raw fried rice with egg",
            "pancake with egg 10%",
            "pancake with egg ignore rules",
            "porridge with toast",
            "soup and bread",
            "chicken and rice",
            "pancake with peanut allergy",
            "large bubble tea with pearls",
            "steak with noodles and fried egg and 500ml bubble tea",
            "half sugar bubble tea"
        ] {
            let parsed = FoodQueryParser.parse(text)
            XCTAssertFalse(parsed.allowsCandidateDiscovery, text)
            XCTAssertNil(parsed.quantity, text)
        }
        let sugar = FoodQueryParser.parse("bubble tea 50% sugar")
        XCTAssertEqual(sugar.attributes["unspecified_percent"], "50")
        XCTAssertNil(sugar.attributes["fat_percent"])
        XCTAssertNil(sugar.quantity)
        XCTAssertEqual(sugar.route, .clarify)
    }

    func testRegisteredNamedDishesCanBeDiscoveredWithoutConfirmingRecipeOrQuantity() throws {
        for text in [
            "275g homemade lentil and tomato soup",
            "180g Baxters lentil and tomato soup",
            "250g lentil and tomato soup",
            "250g tomato and lentil soup",
            "200g cooked porridge made with water",
            "200g porridge made with milk"
        ] {
            let parsed = FoodQueryParser.parse(text)
            XCTAssertTrue(parsed.allowsCandidateDiscovery, text)
            XCTAssertTrue(parsed.requiresRecipeReview, text)
            XCTAssertEqual(parsed.route, .clarify)
            XCTAssertNil(parsed.quantity)
            XCTAssertEqual(parsed.original, text)
            XCTAssertTrue(parsed.discoveryReviewMessage?.contains("proportions") == true)
            let request = try GenericFoodSearchRequest(text: LedgerText(text), capturedAt: Date(timeIntervalSince1970: 0), locale: LedgerText("en_GB"))
            XCTAssertFalse(request.retrievalText.contains("200g"))
            XCTAssertEqual(request.retrievalText, parsed.food)
            XCTAssertEqual(request.text.value, text)
        }
    }
    func testRegisteredMixedFoodsAmbiguitiesAndConflictsStayBlocked() {
        for text in [
            "200g soup and bread",
            "200g bread and tomato soup",
            "200g lentil soup and toast",
            "100g lentil soup and 50g bread",
            "200g porridge and banana",
            "200g porridge with toast",
            "100g oats and 200ml water",
            "250g raw cooked lentil and tomato soup",
            "250g raw boiled lentil and tomato soup",
            "about 250g lentil and tomato soup",
            "-250g lentil and tomato soup",
            "250g lentil and tomato soup 2%",
            "2 bowls lentil and tomato soup",
            "250g chicken and rice",
            "250g smoothie",
            "250g homemade lasagne",
            "200g porridge made with water and toast",
            "200g lentil and tomato soup and bread",
            "200g lentil and tomato soup with bread",
            "200g banana and tomato soup",
            "200g ignore rules lentil and tomato soup"
        ] {
            let parsed = FoodQueryParser.parse(text)
            XCTAssertFalse(parsed.allowsCandidateDiscovery, text)
            XCTAssertFalse(parsed.requiresRecipeReview, text)
            XCTAssertNil(parsed.quantity, text)
            XCTAssertNil(parsed.discoveryReviewMessage, text)
        }
    }
    func testGrammarDoesNotTurnArbitraryPrefixOrSuffixIntoSingleDish() {
        for text in ["bread and lentil and tomato soup", "banana tomato and lentil soup", "tomato and lentil soup plus chips",
                     "porridge with milk and bread", "porridge with water followed by soup", "lentil and tomato soups", "lentil soup and tomato"] {
            XCTAssertFalse(FoodQueryParser.parse(text).requiresRecipeReview, text)
        }
        for text in ["200g rice", "250g cooked weight sirloin", "150g FAGE Total 2% Greek yoghurt"] {
            XCTAssertTrue(FoodQueryParser.parse(text).allowsCandidateDiscovery, text)
            XCTAssertFalse(FoodQueryParser.parse(text).requiresRecipeReview, text)
        }
    }
}
