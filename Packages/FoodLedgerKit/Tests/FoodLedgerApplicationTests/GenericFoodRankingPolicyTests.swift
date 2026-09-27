import FoodLedgerApplication
import XCTest

final class GenericFoodRankingPolicyTests: XCTestCase {
    func testRepresentationPreferenceAppliesIdenticallyAcrossFoodNames() {
        for food in ["oats", "lentils", "potato", "beans", "bread", "beef", "fish", "tomato"] {
            let ordinary = GenericFoodRankingPolicy.preference(name: "\(food), plain, average", food: food, requestedText: food)
            let specialised = GenericFoodRankingPolicy.preference(name: "\(food), dried, sweetened", food: food, requestedText: food)
            XCTAssertTrue(GenericFoodRankingPolicy.prefers(ordinary,over:specialised),food)
            XCTAssertFalse(GenericFoodRankingPolicy.prefers(specialised,over:ordinary),food)
        }
    }
    func testPrimaryFoodBeatsIngredientMentionAndExplicitWordsRemoveSpecialisationPenalty() {
        let primary = GenericFoodRankingPolicy.preference(name:"Apple, raw",food:"apple",requestedText:"apple")
        let ingredient = GenericFoodRankingPolicy.preference(name:"Cake, apple, plain",food:"apple",requestedText:"apple")
        XCTAssertTrue(GenericFoodRankingPolicy.prefers(primary,over:ingredient))
        let generic = GenericFoodRankingPolicy.preference(name:"Rice, red, raw",food:"rice",requestedText:"rice")
        let explicit = GenericFoodRankingPolicy.preference(name:"Rice, red, raw",food:"red rice",requestedText:"red rice")
        XCTAssertTrue(GenericFoodRankingPolicy.prefers(explicit,over:generic))
        XCTAssertFalse(GenericFoodRankingPolicy.prefers(primary,over:primary))
    }
}
