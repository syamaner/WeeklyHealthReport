import Foundation
import XCTest
import FoodLedgerApplication
import FoodLedgerDomain

final class FoodQueryDiscoveryPolicyTests: XCTestCase {
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
