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


    func testUnrequestedPartWordsArePenalisedOnlyWhenPresentAndUnrequested() {
        let query = "150 g grilled chicken", food = "grilled chicken"
        let skin = GenericFoodRankingPolicy.preference(name: "Chicken, skin, roasted/grilled, moist", food: food, requestedText: query)
        let meat = GenericFoodRankingPolicy.preference(name: "Chicken, breast, grilled without skin, meat only", food: food, requestedText: query)
        XCTAssertTrue(GenericFoodRankingPolicy.prefers(meat, over: skin))
        XCTAssertFalse(GenericFoodRankingPolicy.prefers(skin, over: meat))
        for part in ["skin", "fat", "giblets", "liver"] {
            let plain = GenericFoodRankingPolicy.preference(name: "Meat, cooked", food: "meat", requestedText: "meat")
            let withPart = GenericFoodRankingPolicy.preference(name: "Meat, \(part), cooked", food: "meat", requestedText: "meat")
            XCTAssertTrue(GenericFoodRankingPolicy.prefers(plain, over: withPart), part)
            // A part the user named is never penalised.
            let named = GenericFoodRankingPolicy.preference(name: "Meat, \(part), cooked", food: "meat \(part)", requestedText: "meat \(part)")
            XCTAssertEqual(named, GenericFoodRankingPolicy.preference(name: "Meat, cooked", food: "meat \(part)", requestedText: "meat \(part)"), part)
        }
    }

    /// True when `name` is ranked as presenting the part: the same name with the
    /// part word replaced by a neutral word is preferred only if the penalty applies.
    private func countsPart(_ name: String, food: String = "food", part: String) -> Bool {
        let candidate = GenericFoodRankingPolicy.preference(name: name, food: food, requestedText: food)
        let neutral = name.replacingOccurrences(of: "\\b\(part)\\b", with: "qqq", options: [.regularExpression, .caseInsensitive])
        let reference = GenericFoodRankingPolicy.preference(name: neutral, food: food, requestedText: food)
        return GenericFoodRankingPolicy.prefers(reference, over: candidate)
    }

    func testNegatedQualifiedOrWeighingBasisPartWordsAreNotParts() {
        for (name, part) in [("Food, without skin, cooked", "skin"), ("Food, no skin, cooked", "skin"),
                             ("Food, excluding skin, cooked", "skin"),
                             ("Food, low fat, cooked", "fat"), ("Food, reduced fat, cooked", "fat"),
                             ("Food, fat free, cooked", "fat"), ("Food, 2% fat, cooked", "fat"),
                             ("Food, medium fat, cooked", "fat"), ("Food, high fat, cooked", "fat"),
                             ("Food, higher fat, cooked", "fat"), ("Food, extra lean and fat", "fat"),
                             ("Food, fat trimmed, cooked", "fat"), ("Food, trimmed to 0\" fat, cooked", "fat"),
                             ("Food, cooked, weighed with skin", "skin"),
                             ("Fish, fillets weighed with bones and skin", "skin"),
                             ("Food, skin and breading removed, fried", "skin")] {
            XCTAssertFalse(countsPart(name, part: part), name)
        }
    }

    func testAnimalPartPositionsCountAndProduceSkinDoesNot() {
        for (name, part) in [("Food, skin, roasted", "skin"), ("Food, fat, cooked", "fat"), ("Liver, food, raw", "liver"),
                             ("Food, whole, roasted, meat and skin", "skin"), ("Food, separable lean and fat, cooked", "fat"),
                             ("Food, separable fat, cooked", "fat"), ("Food, broilers, skin only, cooked", "skin"),
                             ("Food, skin (drumsticks and thighs), cooked", "skin")] {
            XCTAssertTrue(countsPart(name, part: part), name)
        }
        // Produce skin is part of the eaten food, never an unrequested animal part.
        for name in ["Apples, raw, with skin", "Apples, eating, raw, flesh and skin", "Potatoes, baked, flesh and skin",
                     "Plums, average, raw, includes skin", "Chicken, breast, grilled with skin, meat only"] {
            let food = name.split(separator: ",")[0].lowercased()
            XCTAssertFalse(countsPart(name, food: food, part: "skin"), name)
        }
        let apple = "apple", withSkin = GenericFoodRankingPolicy.preference(name: "Apples, raw, with skin", food: apple, requestedText: apple)
        let withoutSkin = GenericFoodRankingPolicy.preference(name: "Apples, raw, without skin", food: apple, requestedText: apple)
        XCTAssertFalse(GenericFoodRankingPolicy.prefers(withoutSkin, over: withSkin))
    }

    func testPartPenaltyFollowsSpecialisationsAndPrecedesFormsAndOrdinaryBonuses() {
        let specialised = GenericFoodRankingPolicy.preference(name: "Food, dried", food: "food", requestedText: "food")
        let part = GenericFoodRankingPolicy.preference(name: "Food, skin", food: "food", requestedText: "food")
        XCTAssertTrue(GenericFoodRankingPolicy.prefers(part, over: specialised))
        let wholeWithPart = GenericFoodRankingPolicy.preference(name: "Food, skin, whole", food: "food", requestedText: "food")
        let sliced = GenericFoodRankingPolicy.preference(name: "Food, sliced", food: "food", requestedText: "food")
        XCTAssertTrue(GenericFoodRankingPolicy.prefers(sliced, over: wholeWithPart))
    }

}
