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
    func testDerivativeFoodHeadsRequireAnExplicitRequestForThatFood() {
        for (name, query) in [("Rolls, hamburger or hot dog, wheat", "hot dog"),
                              ("Pickle relish, hot dog", "hot dog"),
                              ("Banana bread, homemade", "banana"),
                              ("Buns, chicken filling", "chicken")] {
            XCTAssertFalse(GenericFoodRankingPolicy.allowsDerivativeFoodName(name, query: query))
        }
        for (name, query) in [("Rolls, hamburger or hot dog, wheat", "hot dog rolls"),
                              ("Pickle relish, hot dog", "hot dog relish"),
                              ("Banana bread, homemade", "banana bread"),
                              ("Breadfruit, raw", "breadfruit"),
                              ("Chicken, breaded", "chicken"),
                              ("Seeds, pumpkin seeds, raw", "pumpkin seed")] {
            XCTAssertTrue(GenericFoodRankingPolicy.allowsDerivativeFoodName(name, query: query))
        }
    }

    func testSeedMorphologyPreservesProcessingAndOtherIdentityWords() {
        XCTAssertEqual(GenericFoodRankingPolicy.terms("pumpkin seeds"), GenericFoodRankingPolicy.terms("pumpkin seed"))
        XCTAssertEqual(GenericFoodRankingPolicy.terms("sesame seeds, toasted"), ["sesame", "seed", "toasted"])
        XCTAssertNotEqual(GenericFoodRankingPolicy.terms("fresh seed"), GenericFoodRankingPolicy.terms("dried seed"))
        XCTAssertNotEqual(GenericFoodRankingPolicy.terms("dry seed"), GenericFoodRankingPolicy.terms("dried seed"))
    }

    func testRoastAndSliceMorphologyRetainsMethodAndFormConstraints() {
        XCTAssertEqual(GenericFoodRankingPolicy.terms("roast lamb slices"), GenericFoodRankingPolicy.terms("roasted lamb sliced"))
        XCTAssertEqual(GenericFoodRankingPolicy.terms("roast lamb slice"), GenericFoodRankingPolicy.terms("roast lamb slices"))
        XCTAssertNotEqual(GenericFoodRankingPolicy.terms("roast lamb sliced"), GenericFoodRankingPolicy.terms("roast lamb"))
        XCTAssertNotEqual(GenericFoodRankingPolicy.terms("roast lamb"), GenericFoodRankingPolicy.terms("grilled lamb"))
        XCTAssertNotEqual(GenericFoodRankingPolicy.terms("unroasted seed"), GenericFoodRankingPolicy.terms("roasted seed"))
        XCTAssertTrue(GenericFoodRankingPolicy.terms("not roasted lamb").contains("not"))
    }

    func testUnrequestedFormPrecedesWholeRepresentationBonus() {
        for food in ["cheese", "grain", "fruit"] {
            let simple = GenericFoodRankingPolicy.preference(name: food, food: food, requestedText: food)
            let processed = GenericFoodRankingPolicy.preference(name: "\(food), whole, crumbled", food: food, requestedText: food)
            XCTAssertTrue(GenericFoodRankingPolicy.prefers(simple, over: processed))
            XCTAssertFalse(GenericFoodRankingPolicy.prefers(processed, over: simple))
        }
    }

    func testDistributionProgrammeAnnotationIsRankingMetadataOnly() {
        let plain = GenericFoodRankingPolicy.preference(name: "Pear, raw", food: "pear", requestedText: "pear")
        let annotated = GenericFoodRankingPolicy.preference(name: "Pear, raw (Includes foods for USDA's Food Distribution Program)", food: "pear", requestedText: "pear")
        XCTAssertEqual(plain, annotated)
        let meaningful = GenericFoodRankingPolicy.preference(name: "Pear, raw (peeled)", food: "pear", requestedText: "pear")
        XCTAssertNotEqual(plain, meaningful)
        XCTAssertTrue(GenericFoodRankingPolicy.prefers(plain, over: meaningful))
    }

    func testExplicitFormAvoidsUnrequestedDescriptorPenalty() {
        let implicit = GenericFoodRankingPolicy.preference(name: "Grain, whole, crumbled", food: "grain", requestedText: "grain")
        let explicit = GenericFoodRankingPolicy.preference(name: "Grain, whole, crumbled", food: "grain whole crumbled", requestedText: "grain whole crumbled")
        XCTAssertTrue(GenericFoodRankingPolicy.prefers(explicit, over: implicit))
    }

}
