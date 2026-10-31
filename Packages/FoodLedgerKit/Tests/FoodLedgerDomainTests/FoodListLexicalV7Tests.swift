import FoodLedgerDomain
import XCTest

/// The golden tables of docs/food-list-lexical-v7.md (#359): the v6 container rule, widened to
/// the other containers and household measures (`HouseholdContainerRule.listMeasurePatternV7`).
/// Each gets the `householdMeasure` notice and no amount under every numeral convention, and
/// leaves the search query. Every other line parses exactly as `food-list-lexical-v6`, which
/// stays frozen as `parseV6`.
final class FoodListLexicalV7Tests: XCTestCase {
    /// (line, query after the measure phrase is removed). Each has no amount and no unit.
    static let measureTable: [(String, String)] = [
        // The v6 containers still leave the query.
        ("2 mugs of tea", "tea"), ("2 mugs tea", "tea"), ("a pot of yoghurt", "yoghurt"), ("1 cup rice", "rice"),
        // Household measures that v6 recognised but kept in the query.
        ("2 slices of bread", "bread"), ("1 slice toast", "toast"), ("2 scoops protein powder", "protein powder"),
        ("a scoop of ice cream", "ice cream"), ("2 tbsp olive oil", "olive oil"), ("1 tsp sugar", "sugar"),
        ("1 teaspoon of salt", "salt"), ("2 tsp. sugar", "sugar"), ("1 tbsp. olive oil", "olive oil"), ("2 tablespoons honey", "honey"), ("a portion of chips", "chips"),
        ("2 portions of rice", "rice"), ("2 packets of crisps", "crisps"), ("a packet of crisps", "crisps"),
        ("1 packet soup", "soup"), ("a spoon of sugar", "sugar"), ("1 table spoon of honey", "honey"),
        // Containers and measures that v6 did not know (several read as a count).
        ("a bottle of water", "water"), ("2 bottles of water", "water"), ("2 jars of honey", "honey"),
        ("2 jars honey", "honey"), ("a tub of ice cream", "ice cream"), ("a can of coke", "coke"),
        ("a tin of tomatoes", "tomatoes"), ("a carton of juice", "juice"), ("a bowl of porridge", "porridge"),
        ("a bag of crisps", "crisps"), ("a sachet of oats", "oats"), ("a plate of pasta", "pasta"),
        ("1 serving of rice", "rice"), ("a dollop of cream", "cream"), ("a spoonful of sugar", "sugar"),
        ("2 teaspoonfuls of sugar", "sugar"), ("2 tea spoons sugar", "sugar"), ("2 x bottles of water", "water"),
        ("two slices of toast", "toast"), ("- 2 slices of bread", "bread"), ("2 SLICES OF BREAD", "BREAD"),
        // With no amount, "of" must follow.
        ("mugs of tea", "tea"), ("slices of bread", "bread"), ("jars of honey", "honey"), ("bottles of water", "water"),
        ("Bowl of porridge", "porridge"), ("spoons of sugar", "sugar"),
        // A mass or volume next to a measure could measure either, so it is withheld, as in search.
        ("250 ml mug of milk", "milk"), ("500 ml bottle of water", "water"), ("500 ml of bottle of water", "water"),
        ("400 g tin of tomatoes", "tomatoes"), ("500 g tub of yoghurt", "yoghurt"), ("30 g slice of cheese", "cheese"),
        ("bottle of water 500 ml", "water"), ("slice of cheese 30 g", "cheese")
    ]

    /// Lines that look like measures but are not: they parse exactly as v6.
    static let unchangedFromV6: [String] = [
        // Food names that start with a guarded unit, or a cake.
        "a mug cake", "2 mug cakes", "200 g mug cake", "a pot noodle", "2 packs crisps", "200 g glass noodles",
        "a bottle gourd", "2 bottles gourd", "200 g bottle gourd",
        // Whole words only.
        "a bagel", "2 bagels", "canned tuna 100 g", "tinned peas", "2 platefuls of pasta", "servingware",
        "sliced bread", "2 sliced apples", "potatoes 200 g", "packed lunch", "cupcakes", "spoonbread",
        // A measure with no food after it, and measures later in the line.
        "2 slices", "a jar of", "1 slice", "tea 2 mugs", "bread 2 slices", "rice with a slice of lemon",
        // Counts and plain amounts.
        "3 pieces of cheese", "2 pieces cheese", "150 g boiled rice", "250 ml milk", "a banana", "2 eggs",
        // A count unit before a measure keeps the written count, as in v6.
        "2 pieces slice of cake",
        // Lines without an amount and without "of" that v6 left alone.
        "slice bread", "jar honey", "pot noodle"
    ]

    /// Lines whose parse changes from v6, pinned against `parseV6` so each change stays
    /// deliberate: v7 drops an amount or a unit word, and never adds an amount.
    static let changedFromV6: [(line: String, v6Quantity: Double?, v6Unit: QuantityUnit?, v6Query: String, v6Notices: [FoodListNotice], v7Query: String, v7Notices: [FoodListNotice])] = [
        // Counts that v6 read from a container it did not know.
        ("a bottle of water", 1, .count, "bottle of water", [], "water", [.householdMeasure]),
        ("2 bottles of water", 2, .count, "bottles of water", [], "water", [.householdMeasure]),
        ("2 jars honey", 2, .count, "jars honey", [], "honey", [.householdMeasure]),
        ("a can of coke", 1, .count, "can of coke", [], "coke", [.householdMeasure]),
        ("a tin of tomatoes", 1, .count, "tin of tomatoes", [], "tomatoes", [.householdMeasure]),
        ("a tub of ice cream", 1, .count, "tub of ice cream", [], "ice cream", [.householdMeasure]),
        ("a bowl of porridge", 1, .count, "bowl of porridge", [], "porridge", [.householdMeasure]),
        ("a carton of juice", 1, .count, "carton of juice", [], "juice", [.householdMeasure]),
        ("a bag of crisps", 1, .count, "bag of crisps", [], "crisps", [.householdMeasure]),
        ("a sachet of oats", 1, .count, "sachet of oats", [], "oats", [.householdMeasure]),
        ("a plate of pasta", 1, .count, "plate of pasta", [], "pasta", [.householdMeasure]),
        ("1 serving of rice", 1, .count, "serving of rice", [], "rice", [.householdMeasure]),
        ("a dollop of cream", 1, .count, "dollop of cream", [], "cream", [.householdMeasure]),
        ("a spoonful of sugar", 1, .count, "spoonful of sugar", [], "sugar", [.householdMeasure]),
        ("2 tea spoons sugar", 2, .count, "tea spoons sugar", [], "sugar", [.householdMeasure]),
        // A mass or volume that v6 kept next to a container it did not know.
        ("500 ml bottle of water", 500, .millilitres, "bottle of water", [], "water", [.householdMeasure]),
        ("400 g tin of tomatoes", 400, .grams, "tin of tomatoes", [], "tomatoes", [.householdMeasure]),
        ("30 g slice of cheese", 30, .grams, "slice of cheese", [], "cheese", [.householdMeasure]),
        // Household measures that v6 recognised, with no amount, but kept in the query.
        ("2 slices of bread", nil, nil, "slices of bread", [.householdMeasure], "bread", [.householdMeasure]),
        ("2 scoops protein powder", nil, nil, "scoops protein powder", [.householdMeasure], "protein powder", [.householdMeasure]),
        ("2 tbsp olive oil", nil, nil, "tbsp olive oil", [.householdMeasure], "olive oil", [.householdMeasure]),
        ("a portion of chips", nil, nil, "portion of chips", [.householdMeasure], "chips", [.householdMeasure]),
        ("2 packets of crisps", nil, nil, "packets of crisps", [.householdMeasure], "crisps", [.householdMeasure]),
        ("1 table spoon of honey", nil, nil, "table spoon of honey", [.householdMeasure], "honey", [.householdMeasure]),
        // No amount: v6 gave missingQuantity and kept the measure.
        ("slices of bread", nil, nil, "slices of bread", [.missingQuantity], "bread", [.householdMeasure]),
        ("jars of honey", nil, nil, "jars of honey", [.missingQuantity], "honey", [.householdMeasure]),
        // No amount and no "of": v6 removed a cup or mug; v7 keeps the name, so "cup noodles" stays.
        ("cup noodles", nil, nil, "noodles", [.householdMeasure], "cup noodles", [.missingQuantity]),
        ("mugs tea", nil, nil, "tea", [.householdMeasure], "mugs tea", [.missingQuantity]),
        ("cup tea", nil, nil, "tea", [.householdMeasure], "cup tea", [.missingQuantity])
    ]

    func testVersionsAreFrozen() {
        XCTAssertEqual(FoodListParser.version, "food-list-lexical-v7")
        XCTAssertEqual(FoodListParser.v7Version, "food-list-lexical-v7")
        XCTAssertEqual(FoodListParser.v6Version, "food-list-lexical-v6")
        XCTAssertEqual(FoodListParser.v5Version, "food-list-lexical-v5")
        XCTAssertEqual(FoodListParser.v4Version, "food-list-lexical-v4")
        XCTAssertEqual(FoodListParser.legacyVersion, "food-list-lexical-v3")
    }

    /// Every measure line has no amount or unit and the household-measure notice, and its query is
    /// the food, in every convention. A household measure never produces an amount.
    func testMeasuresHaveNoAmountAndLeaveTheQueryInEveryConvention() throws {
        for (text, query) in Self.measureTable {
            for convention in NumeralConvention.allCases {
                let line = try XCTUnwrap(FoodListParser.parse(text, convention: convention).first)
                let label = "\(text) \(convention)"
                XCTAssertNil(line.quantity, label)
                XCTAssertNil(line.unit, label)
                XCTAssertEqual(line.notices, [.householdMeasure], label)
                XCTAssertEqual(line.query, query, label)
                XCTAssertEqual(line.original, text, label)
                XCTAssertEqual(line.grammarVersion, "food-list-lexical-v7", label)
                XCTAssertTrue(line.isV7, label)
                XCTAssertFalse(line.isV6, label)
                XCTAssertTrue(line.readsNumeralConvention, label)
                XCTAssertEqual(line.numeralConvention, convention, label)
                XCTAssertNil(FoodListParser.amountNumeral(of: line), label)
            }
        }
    }

    /// An ambiguous numeral before a measure keeps v4's notice before `householdMeasure`.
    func testAmbiguousNumeralBeforeAMeasure() throws {
        let fullStop = try XCTUnwrap(FoodListParser.parse("1,5 slices of bread", convention: .fullStopDecimal).first)
        XCTAssertEqual(fullStop.notices, [.ambiguousNumber, .householdMeasure])
        XCTAssertNil(fullStop.quantity)
        XCTAssertEqual(fullStop.query, "bread")
        let comma = try XCTUnwrap(FoodListParser.parse("1,5 slices of bread", convention: .commaDecimal).first)
        XCTAssertEqual(comma.notices, [.householdMeasure])
        XCTAssertNil(comma.quantity)
        XCTAssertEqual(comma.query, "bread")
    }

    /// Other notices after the amount still apply, and a second amount is still caught.
    func testOtherNoticesStillApply() throws {
        let grounds = try XCTUnwrap(FoodListParser.parse("a scoop of coffee 18 g grounds", convention: .fullStopDecimal).first)
        XCTAssertNil(grounds.quantity)
        XCTAssertNil(grounds.unit)
        XCTAssertEqual(grounds.notices, [.householdMeasure, .multipleAmounts, .preparationInput])
        XCTAssertEqual(grounds.query, "coffee 18 g grounds")
        let homemade = try XCTUnwrap(FoodListParser.parse("a bowl of homemade soup", convention: .fullStopDecimal).first)
        XCTAssertEqual(homemade.notices, [.householdMeasure, .recipe])
        XCTAssertEqual(homemade.query, "homemade soup")
        let vitamin = try XCTUnwrap(FoodListParser.parse("2 scoops of vitamin powder", convention: .fullStopDecimal).first)
        XCTAssertEqual(vitamin.notices, [.householdMeasure, .supplement])
        let boiled = try XCTUnwrap(FoodListParser.parse("a bowl of boiled rice", convention: .fullStopDecimal).first)
        XCTAssertEqual(boiled.preparation, .cooked)
        XCTAssertEqual(boiled.query, "boiled rice")
    }

    /// Lines that are not measures, the v6 tables, the v5 vague table and the v4 corpus parse
    /// exactly as v6 apart from the grammar version.
    func testEveryOtherLineMatchesV6() throws {
        var lines = Self.unchangedFromV6 + FoodListLexicalV5Tests.vagueTable.map(\.0)
        lines += FoodListLexicalV6Tests.containerTable.map(\.0).filter { !["mugs tea", "cup tea"].contains($0) }
        lines += FoodListLexicalV6Tests.unchangedFromV5.filter {
            !["2 tbsp olive oil", "1 slice toast", "a packet of crisps", "2 scoops protein powder"].contains($0)
        }
        lines += FoodListLexicalV4Tests.separatorTable.flatMap { ["\($0.0) g rice", "rice \($0.0) g"] }
        lines += FoodListLexicalV4Tests.fractionTable.map { "\($0.0) g rice" }
        lines += ["1 1/2 l milk", "2x350g soup", "2 x 500 g yoghurt", "£7.40", "08:10 - 08:45", "Breakfast:",
                  "12 mg zinc", "75 graams cereal", "Dash water 330 ml", "180 grams cooked weight chicken breast"]
        for text in lines {
            for convention in NumeralConvention.allCases {
                let v6 = try XCTUnwrap(FoodListParser.parseV6(text, convention: convention).first)
                let v7 = try XCTUnwrap(FoodListParser.parse(text, convention: convention).first)
                let label = "\(text) \(convention)"
                XCTAssertEqual(v6.grammarVersion, "food-list-lexical-v6", label)
                XCTAssertEqual(v7.grammarVersion, "food-list-lexical-v7", label)
                XCTAssertEqual(v7.lineNumber, v6.lineNumber, label)
                XCTAssertEqual(v7.original, v6.original, label)
                XCTAssertEqual(v7.query, v6.query, label)
                XCTAssertEqual(v7.quantity, v6.quantity, label)
                XCTAssertEqual(v7.unit, v6.unit, label)
                XCTAssertEqual(v7.preparation, v6.preparation, label)
                XCTAssertEqual(v7.notices, v6.notices, label)
                XCTAssertEqual(v7.numeralConvention, v6.numeralConvention, label)
                XCTAssertEqual(FoodListParser.amountNumeral(of: v7), FoodListParser.amountNumeral(of: v6), label)
            }
        }
    }

    /// Each changed line, against its v6 parse. v7 never has an amount where v6 had none.
    func testLinesWhoseParseChangesFromV6() throws {
        for change in Self.changedFromV6 {
            for convention in NumeralConvention.allCases {
                let label = "\(change.line) \(convention)"
                let v6 = try XCTUnwrap(FoodListParser.parseV6(change.line, convention: convention).first)
                XCTAssertEqual(v6.quantity, change.v6Quantity, label)
                XCTAssertEqual(v6.unit, change.v6Unit, label)
                XCTAssertEqual(v6.query, change.v6Query, label)
                XCTAssertEqual(v6.notices, change.v6Notices, label)
                let v7 = try XCTUnwrap(FoodListParser.parse(change.line, convention: convention).first)
                XCTAssertNil(v7.quantity, label)
                XCTAssertNil(v7.unit, label)
                XCTAssertEqual(v7.query, change.v7Query, label)
                XCTAssertEqual(v7.notices, change.v7Notices, label)
            }
        }
    }

    /// A v7 line encodes with its own version and the v6 form; stored v3 to v6 lines decode and
    /// re-encode byte-identically and are never re-parsed; an unknown version keeps the v3 reading.
    func testEncodingAndStoredLinesKeepTheirVersion() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let v7 = try XCTUnwrap(FoodListParser.parse("a bottle of water", convention: .fullStopDecimal).first)
        let v7JSON = #"{"grammarVersion":"food-list-lexical-v7","lineNumber":1,"notices":["householdMeasure"],"numeralConvention":"full_stop_decimal","original":"a bottle of water","query":"water"}"#
        XCTAssertEqual(String(decoding: try encoder.encode(v7), as: UTF8.self), v7JSON)
        XCTAssertTrue(v7.isV7)
        XCTAssertFalse(v7.isV6)
        XCTAssertEqual(v7.effectiveGrammarVersion, "food-list-lexical-v7")

        let stored = [
            #"{"grammarVersion":"food-list-lexical-v6","lineNumber":1,"notices":[],"numeralConvention":"full_stop_decimal","original":"a bottle of water","quantity":1,"query":"bottle of water","unit":"count"}"#,
            #"{"grammarVersion":"food-list-lexical-v5","lineNumber":1,"notices":[],"numeralConvention":"full_stop_decimal","original":"a pot of yoghurt","quantity":1,"query":"pot of yoghurt","unit":"count"}"#,
            #"{"grammarVersion":"food-list-lexical-v4","lineNumber":1,"notices":[],"numeralConvention":"comma_decimal","original":"1,5 l milk","quantity":1500,"query":"milk","unit":"mL"}"#,
            #"{"lineNumber":1,"notices":["householdMeasure"],"original":"2 slices of bread","query":"slices of bread"}"#
        ]
        XCTAssertEqual(String(decoding: try encoder.encode(try XCTUnwrap(
            FoodListParser.parseV6("a bottle of water", convention: .fullStopDecimal).first)), as: UTF8.self), stored[0])
        XCTAssertEqual(String(decoding: try encoder.encode(try XCTUnwrap(
            FoodListParser.parseV4("1,5 l milk", convention: .commaDecimal).first)), as: UTF8.self), stored[2])
        XCTAssertEqual(String(decoding: try encoder.encode(try XCTUnwrap(
            FoodListParser.parse("2 slices of bread").first)), as: UTF8.self), stored[3])
        for json in stored {
            let line = try JSONDecoder().decode(ParsedFoodListLine.self, from: Data(json.utf8))
            XCTAssertEqual(String(decoding: try encoder.encode(line), as: UTF8.self), json, "never re-parsed")
            XCTAssertFalse(line.isV7, json)
        }
        let storedV6 = try JSONDecoder().decode(ParsedFoodListLine.self, from: Data(stored[0].utf8))
        XCTAssertTrue(storedV6.isV6)
        XCTAssertTrue(storedV6.readsNumeralConvention)
        XCTAssertEqual(storedV6.quantity, 1, "a restored v6 line keeps its own parse")

        let unknown = try JSONDecoder().decode(ParsedFoodListLine.self, from: Data(
            v7JSON.replacingOccurrences(of: "food-list-lexical-v7", with: "food-list-lexical-v8").utf8))
        XCTAssertFalse(unknown.readsNumeralConvention, "only the frozen v4 to v7 identifiers read a convention")
        XCTAssertFalse(unknown.isV7)
        XCTAssertEqual(unknown.effectiveGrammarVersion, "food-list-lexical-v8")
    }
}

/// The v7 additions to the shared rule (#359), used by the list grammar and search.
final class HouseholdMeasureRuleV7Tests: XCTestCase {
    func testMeasureLeavesFoodText() {
        // With an amount, the v6 guards apply unchanged.
        XCTAssertTrue(HouseholdContainerRule.measureLeavesFoodText(unit: "mugs", followedByOf: false, rest: "tea", afterAmount: true))
        XCTAssertFalse(HouseholdContainerRule.measureLeavesFoodText(unit: "mug", followedByOf: false, rest: "cake", afterAmount: true))
        XCTAssertFalse(HouseholdContainerRule.measureLeavesFoodText(unit: "bottle", followedByOf: false, rest: "gourd", afterAmount: true))
        XCTAssertTrue(HouseholdContainerRule.measureLeavesFoodText(unit: "bottle", followedByOf: true, rest: "water", afterAmount: true))
        XCTAssertTrue(HouseholdContainerRule.measureLeavesFoodText(unit: "slices", followedByOf: false, rest: "toast", afterAmount: true))
        // With no amount, "of" must follow, and the cake exception still holds.
        XCTAssertFalse(HouseholdContainerRule.measureLeavesFoodText(unit: "cup", followedByOf: false, rest: "noodles", afterAmount: false))
        XCTAssertFalse(HouseholdContainerRule.measureLeavesFoodText(unit: "slice", followedByOf: false, rest: "bread", afterAmount: false))
        XCTAssertTrue(HouseholdContainerRule.measureLeavesFoodText(unit: "mugs", followedByOf: true, rest: "tea", afterAmount: false))
        XCTAssertFalse(HouseholdContainerRule.measureLeavesFoodText(unit: "mug", followedByOf: true, rest: "cake", afterAmount: false))
    }

    func testLeadingListMeasure() throws {
        for unit in ["cup", "mugs", "glasses", "pot", "packs", "packet", "bottles", "jar", "tubs", "can", "tins", "carton",
                     "bowls", "bag", "sachets", "plate", "slices", "scoop", "portions", "serving", "dollops", "spoon",
                     "spoonfuls", "teaspoon", "tablespoons", "teaspoonful", "tea spoons", "table spoon", "tsp", "tbsps"] {
            let match = try XCTUnwrap(HouseholdContainerRule.leadingListMeasure(in: "\(unit) of sugar", afterAmount: false), unit)
            XCTAssertEqual(match.unit, unit)
            XCTAssertEqual(match.phrase, "\(unit) of ")
            XCTAssertEqual(match.rest, "sugar")
        }
        for text in ["2 slices", "slices", "a jar of", "jar of", "slice of 2", "bagel", "canned tuna", "tinned peas",
                     "platefuls of pasta", "servingware", "sliced bread", "spoonbread", "bottle gourd", "pot noodle",
                     "mug cake", "cup noodles", "slice bread", "piece of cake", "pieces of cheese", ""] {
            XCTAssertNil(HouseholdContainerRule.leadingListMeasure(in: text, afterAmount: false), text)
        }
        XCTAssertNil(HouseholdContainerRule.leadingListMeasure(in: "slices", afterAmount: true))
        XCTAssertNil(HouseholdContainerRule.leadingListMeasure(in: "bottle gourd", afterAmount: true))
        XCTAssertEqual(HouseholdContainerRule.leadingListMeasure(in: "slice bread", afterAmount: true)?.rest, "bread")
        XCTAssertEqual(HouseholdContainerRule.leadingListMeasure(in: "cup noodles", afterAmount: true)?.rest, "noodles")
        XCTAssertEqual(HouseholdContainerRule.leadingListMeasure(in: "Slices Of Bread", afterAmount: false)?.rest, "Bread")
    }
}
