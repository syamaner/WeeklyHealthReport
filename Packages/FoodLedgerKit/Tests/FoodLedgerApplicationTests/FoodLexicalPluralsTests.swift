import FoodLedgerApplication
import XCTest

/// food-lexical-terms-v9: pure, deterministic plural folding (docs/food-lexical-terms-v9.md).
final class FoodLexicalPluralsTests: XCTestCase {
    func testRulesFoldRegularPlurals() {
        let cases = [
            // -s
            "almonds": "almond", "walnuts": "walnut", "cashews": "cashew", "hazelnuts": "hazelnut",
            "peanuts": "peanut", "lentils": "lentil", "chickpeas": "chickpea", "olives": "olive",
            "kiwis": "kiwi", "pies": "pie", "oats": "oat", "brussels": "brussel",
            // -es after ss, x, ch, sh, zz
            "glasses": "glass", "mixes": "mix", "peaches": "peach", "sandwiches": "sandwich", "radishes": "radish",
            // -oes, including o-words
            "tomatoes": "tomato", "potatoes": "potato", "mangoes": "mango", "pistachios": "pistachio",
            // -ies -> -y
            "berries": "berry", "blueberries": "blueberry", "cherries": "cherry", "anchovies": "anchovy",
            // -es elsewhere loses only the s
            "cheeses": "cheese", "sauces": "sauce", "grapes": "grape", "dates": "date",
        ]
        for (plural, singular) in cases { XCTAssertEqual(FoodLexicalPlurals.singular(plural), singular, plural) }
    }

    func testExceptionsWinOverRules() {
        let cases = [
            "leaves": "leaf", "loaves": "loaf", "halves": "half", "calves": "calf",
            "cookies": "cookie", "brownies": "brownie", "smoothies": "smoothie", "chillies": "chilli",
            "quiches": "quiche", "brioches": "brioche", "mousses": "mousse", "sloes": "sloe", "roes": "roe",
            "molasses": "molasses", "haggis": "haggis", "christmas": "christmas", "madras": "madras",
            "greens": "greens", "sweets": "sweets", "crisps": "crisps",
        ]
        for (word, expected) in cases { XCTAssertEqual(FoodLexicalPlurals.singular(word), expected, word) }
        // Only listed -ves words change their f; knives is not food and is not listed.
        XCTAssertEqual(FoodLexicalPlurals.singular("knives"), "knive")
    }

    func testWordsThatOnlyLookPluralAreUnchanged() {
        for word in ["hummus", "couscous", "asparagus", "citrus", "swiss", "bass", "grass", "cress",
                     "watercress", "molasses", "haggis", "gas", "its", "bus", "egg", "rice", "tomato"] {
            XCTAssertEqual(FoodLexicalPlurals.singular(word), word, word)
        }
    }

    func testNonASCIIAndNumericTermsAreUnchanged() {
        for word in ["香蕉", "芭樂", "100s", "b12s", "cafés", "s", "es"] {
            XCTAssertEqual(FoodLexicalPlurals.singular(word), word, word)
        }
    }

    func testFoldingIsIdempotentAndExceptionValuesAreFixedPoints() {
        let words = ["almonds", "berries", "tomatoes", "glasses", "peaches", "leaves", "cookies", "kiwis",
                     "molasses", "hummus", "quiches", "crosscuts", "boxes", "sardines", "pancreas"]
        for word in words {
            let once = FoodLexicalPlurals.singular(word)
            XCTAssertEqual(FoodLexicalPlurals.singular(once), once, word)
        }
        for value in FoodLexicalPlurals.exceptions.values {
            XCTAssertEqual(FoodLexicalPlurals.singular(value), value, value)
        }
        XCTAssertEqual(FoodLexicalPlurals.version, "food-lexical-terms-v9")
    }

    func testRetrievalTermsFoldQueryAndSourceNamesSymmetrically() {
        XCTAssertEqual(GenericFoodRankingPolicy.terms("Almonds, whole kernels"), ["almond", "whole", "kernel"])
        XCTAssertEqual(GenericFoodRankingPolicy.terms("Nuts, almonds"), ["nut", "almond"])
        XCTAssertEqual(GenericFoodRankingPolicy.terms("a handful of almonds"), ["handful", "almond"])
        XCTAssertEqual(GenericFoodRankingPolicy.terms("Hummus, commercial"), ["hummus", "commercial"])
        // Folding runs before the closed v8 equivalents, so plural and singular agree.
        XCTAssertEqual(GenericFoodRankingPolicy.terms("roasts"), GenericFoodRankingPolicy.terms("roast"))
        XCTAssertEqual(GenericFoodRankingPolicy.terms("Garbanzos"), ["chickpea"])
        // Literal terms keep food-lexical-terms-v8 behaviour for live-source admission.
        XCTAssertEqual(GenericFoodRankingPolicy.literalTerms("Almonds, whole kernels"), ["almonds", "whole", "kernels"])
        XCTAssertEqual(GenericFoodRankingPolicy.literalTerms("2 eggs"), ["2", "egg"])
    }

    func testSameNumberMatchPrecedesFoldedMatchAfterThePrimaryName() {
        XCTAssertEqual(GenericFoodRankingPolicy.version, "generic-representation-ranking-v8")
        func preference(_ name: String, _ text: String) -> GenericFoodRankingPolicy.Preference {
            GenericFoodRankingPolicy.preference(name: name, food: text, requestedText: text)
        }
        // Neither name is the primary food; the plural spelling wins over a singular modifier.
        XCTAssertTrue(GenericFoodRankingPolicy.prefers(preference("Nuts, walnuts, english", "walnuts"), over: preference("Oil, walnut", "walnuts")))
        XCTAssertTrue(GenericFoodRankingPolicy.prefers(preference("Nuts, hazelnuts or filberts", "hazelnuts"), over: preference("SILK Hazelnut Creamer", "hazelnuts")))
        // The parser may hand on "almond" for "almonds"; the original text decides the number.
        let almonds = GenericFoodRankingPolicy.preference(name: "Nuts, almonds", food: "almond", requestedText: "almonds")
        let milk = GenericFoodRankingPolicy.preference(name: "Almond milk, unsweetened, plain, refrigerated", food: "almond", requestedText: "almonds")
        XCTAssertTrue(GenericFoodRankingPolicy.prefers(almonds, over: milk))
        // A primary-name match still comes first, whatever the number.
        XCTAssertTrue(GenericFoodRankingPolicy.prefers(preference("Guavas, common, raw", "guava"), over: preference("Guava sauce, cooked", "guava")))
        XCTAssertTrue(GenericFoodRankingPolicy.prefers(preference("Almonds, whole kernels", "almond"), over: preference("Nuts, almond butter, plain", "almond")))
    }

    func testPluralPartWordStillCountsAsRequestedWhenNamedInEitherForm() {
        for requested in ["chicken giblets", "chicken giblet"] {
            // The part position counts giblets as present; named giblets are requested
            // whichever number the user typed, so the position alone must not demote it.
            let partPosition = GenericFoodRankingPolicy.preference(name: "Chicken, giblets, raw", food: requested, requestedText: requested)
            let otherPosition = GenericFoodRankingPolicy.preference(name: "Chicken, raw, giblets", food: requested, requestedText: requested)
            XCTAssertFalse(GenericFoodRankingPolicy.prefers(otherPosition, over: partPosition), requested)
        }
    }
}
