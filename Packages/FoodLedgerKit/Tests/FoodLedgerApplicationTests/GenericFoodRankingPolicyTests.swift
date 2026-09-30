import FoodLedgerApplication
import XCTest

final class GenericFoodRankingPolicyTests: XCTestCase {
    func testDirectNamesBeatParentheticalOnlyMentionsWithoutAssumingFoodOrSpecies() {
        for term in ["sirloin", "shank", "apple", "lentil"] {
            let direct = GenericFoodRankingPolicy.preference(name: "Named food, \(term), cooked", food: term, requestedText: term)
            let incidental = GenericFoodRankingPolicy.preference(name: "Another food, whole (includes \(term)), cooked", food: term, requestedText: term)
            XCTAssertTrue(GenericFoodRankingPolicy.prefers(direct, over: incidental))
            XCTAssertFalse(GenericFoodRankingPolicy.prefers(incidental, over: direct))
            let nested = GenericFoodRankingPolicy.preference(name: "Another food, whole (includes (part of) \(term)), cooked", food: term, requestedText: term)
            XCTAssertTrue(GenericFoodRankingPolicy.prefers(direct, over: nested))
        }
        let repeated = GenericFoodRankingPolicy.preference(name: "Named food, sirloin (sirloin), cooked", food: "sirloin", requestedText: "sirloin")
        let plain = GenericFoodRankingPolicy.preference(name: "Named food, sirloin, cooked", food: "sirloin", requestedText: "sirloin")
        XCTAssertEqual(repeated, plain)
    }

    func testWholeRepresentationPreferenceIsSourceAndFoodNeutral() {
        for food in ["egg", "milk", "grain"] {
            let whole = GenericFoodRankingPolicy.preference(name: "\(food), whole", food: food, requestedText: food)
            let partial = GenericFoodRankingPolicy.preference(name: "\(food), white", food: food, requestedText: food)
            XCTAssertTrue(GenericFoodRankingPolicy.prefers(whole, over: partial))
        }
    }
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
