import FoodLedgerDomain
import XCTest

/// The golden tables of docs/food-list-lexical-v6.md (#353): a household container (cups, mugs,
/// glasses, pots and packs) gets the `householdMeasure` notice and no amount under every numeral
/// convention, and leaves the search query under the rule search uses (`HouseholdContainerRule`).
/// Every other line parses exactly as `food-list-lexical-v5`, which stays frozen.
final class FoodListLexicalV6Tests: XCTestCase {
    /// (line, query after the container phrase is removed). Each has no amount and no unit.
    static let containerTable: [(String, String)] = [
        // Cups and mugs leave the query with or without "of".
        ("2 mugs of tea", "tea"),
        ("2 mugs tea", "tea"),
        ("a mug of coffee", "coffee"),
        ("1 mug coffee", "coffee"),
        ("2 x mugs of tea", "tea"),
        ("two mugs of hot chocolate", "hot chocolate"),
        ("2 MUGS OF TEA", "TEA"),
        ("- 2 mugs of tea", "tea"),
        ("a cup of tea", "tea"),
        ("2 cups of tea", "tea"),
        ("1 cup rice", "rice"),
        ("half cup rice", "rice"),
        ("½ cup pepper sauce", "pepper sauce"),
        // Glasses, pots and packs leave it only before "of", as in search.
        ("a glass of milk", "milk"),
        ("2 glasses of milk", "milk"),
        ("a pot of yoghurt", "yoghurt"),
        ("2 pots of yoghurt", "yoghurt"),
        ("a pack of crisps", "crisps"),
        ("2 packs of crisps", "crisps"),
        // No amount: the line names a container rather than omitting an amount.
        ("mugs of tea", "tea"),
        ("Mug of tea", "tea"),
        ("cup of tea", "tea"),
        ("glass of milk", "milk"),
        ("pots of yoghurt", "yoghurt"),
        // A mass or volume before a container could measure either, so it is withheld, as in search.
        ("250 ml mug of milk", "milk"),
        ("250 ml mug milk", "milk"),
        ("250 ml of mug of milk", "milk"),
        ("68 g Mug Shot pasta", "Shot pasta"),
        ("300ml glass of milk", "milk"),
        ("330 ml glasses of water", "water"),
        ("200 g pot of yoghurt", "yoghurt"),
        ("150 g cup of rice", "rice"),
        ("mug of milk 250 ml", "milk"),
        ("glass of milk 300ml", "milk")
    ]

    /// Lines that look like containers but are not: they parse exactly as v5.
    static let unchangedFromV5: [String] = [
        // A mug cake or cup cake is a food in its own right.
        "a mug cake", "1 mug cake", "2 mug cakes", "2 mugs cakes", "mug cake", "200 g mug cake", "a cup cake",
        // Glasses, pots and packs without "of" may start a food name.
        "a pot noodle", "2 pots noodles", "2 glasses noodles", "2 packs crisps", "200 g pot noodle",
        "glass noodles", "200 g glass noodles", "pack choi 100 g", "Half pack large fries",
        // Words that only contain a unit, and containers with no food after them.
        "2 cupcakes", "potatoes 200 g", "2 potatoes", "packed lunch", "2 mugs", "a mug of", "cups",
        // Containers elsewhere in the line, and the other household measures.
        "tea 2 mugs", "milk 250 ml mug", "rice with a cup of peas", "2 tbsp olive oil", "1 slice toast",
        "a packet of crisps", "2 scoops protein powder",
        // A count unit before a container keeps the written count, as v5 did.
        "2 pieces mug of tea", "1 piece Pot of yoghurt",
        "150 g boiled rice", "250 ml milk", "a banana"
    ]

    func testVersionsAreFrozen() {
        XCTAssertEqual(FoodListParser.version, "food-list-lexical-v7", "v6 is frozen as parseV6 (#359)")
        XCTAssertEqual(FoodListParser.v6Version, "food-list-lexical-v6")
        XCTAssertEqual(FoodListParser.v5Version, "food-list-lexical-v5")
        XCTAssertEqual(FoodListParser.v4Version, "food-list-lexical-v4")
        XCTAssertEqual(FoodListParser.legacyVersion, "food-list-lexical-v3")
    }

    /// Every container line has no amount or unit and the household-measure notice, and its
    /// query is the food. A container never produces an amount, in any convention.
    func testContainersHaveNoAmountAndLeaveTheQueryInEveryConvention() throws {
        for (text, query) in Self.containerTable {
            for convention in NumeralConvention.allCases {
                let line = try XCTUnwrap(FoodListParser.parseV6(text, convention: convention).first)
                let label = "\(text) \(convention)"
                XCTAssertNil(line.quantity, label)
                XCTAssertNil(line.unit, label)
                XCTAssertEqual(line.notices, [.householdMeasure], label)
                XCTAssertEqual(line.query, query, label)
                XCTAssertEqual(line.original, text, label)
                XCTAssertEqual(line.grammarVersion, "food-list-lexical-v6", label)
                XCTAssertTrue(line.isV6, label)
                XCTAssertTrue(line.readsNumeralConvention, label)
                XCTAssertEqual(line.numeralConvention, convention, label)
                XCTAssertNil(FoodListParser.amountNumeral(of: line), label)
            }
        }
    }

    /// An ambiguous numeral before a container keeps v4's notice before `householdMeasure`.
    func testAmbiguousNumeralBeforeAContainer() throws {
        let fullStop = try XCTUnwrap(FoodListParser.parseV6("1,5 mugs of tea", convention: .fullStopDecimal).first)
        XCTAssertEqual(fullStop.notices, [.ambiguousNumber, .householdMeasure])
        XCTAssertNil(fullStop.quantity)
        XCTAssertEqual(fullStop.query, "tea")
        let comma = try XCTUnwrap(FoodListParser.parseV6("1,5 mugs of tea", convention: .commaDecimal).first)
        XCTAssertEqual(comma.notices, [.householdMeasure])
        XCTAssertNil(comma.quantity)
        XCTAssertEqual(comma.query, "tea")
    }

    /// Other notices after the amount still apply, and a second amount is still caught.
    func testOtherNoticesStillApply() throws {
        for text in ["2 mugs of coffee 18 g grounds", "1 mug coffee 18 g grounds"] {
            let grounds = try XCTUnwrap(FoodListParser.parseV6(text, convention: .fullStopDecimal).first)
            XCTAssertNil(grounds.quantity, text)
            XCTAssertNil(grounds.unit, text)
            XCTAssertEqual(grounds.notices, [.householdMeasure, .multipleAmounts, .preparationInput], text)
            XCTAssertEqual(grounds.query, "coffee 18 g grounds", text)
        }
        let homemade = try XCTUnwrap(FoodListParser.parseV6("a mug of homemade soup", convention: .fullStopDecimal).first)
        XCTAssertEqual(homemade.notices, [.householdMeasure, .recipe])
        XCTAssertEqual(homemade.query, "homemade soup")
        let boiled = try XCTUnwrap(FoodListParser.parseV6("a cup of boiled rice", convention: .fullStopDecimal).first)
        XCTAssertEqual(boiled.preparation, .cooked)
        XCTAssertEqual(boiled.query, "boiled rice")
    }

    /// Lines that are not containers, the v5 vague table and the v5 non-vague corpus parse exactly
    /// as v5 apart from the grammar version.
    func testEveryOtherLineMatchesV5() throws {
        var lines = Self.unchangedFromV5 + FoodListLexicalV5Tests.vagueTable.map(\.0)
        lines += FoodListLexicalV4Tests.separatorTable.flatMap { ["\($0.0) g rice", "rice \($0.0) g"] }
        lines += FoodListLexicalV4Tests.fractionTable.map { "\($0.0) g rice" }
        lines += ["1 1/2 l milk", "2x350g soup", "2 x 500 g yoghurt", "£7.40", "08:10 - 08:45", "Breakfast:",
                  "12 mg zinc", "75 graams cereal", "Dash water 330 ml", "180 grams cooked weight chicken breast"]
        for text in lines {
            for convention in NumeralConvention.allCases {
                let v5 = try XCTUnwrap(FoodListParser.parseV5(text, convention: convention).first)
                let v6 = try XCTUnwrap(FoodListParser.parseV6(text, convention: convention).first)
                let label = "\(text) \(convention)"
                XCTAssertEqual(v5.grammarVersion, "food-list-lexical-v5", label)
                XCTAssertEqual(v6.grammarVersion, "food-list-lexical-v6", label)
                XCTAssertEqual(v6.lineNumber, v5.lineNumber, label)
                XCTAssertEqual(v6.original, v5.original, label)
                XCTAssertEqual(v6.query, v5.query, label)
                XCTAssertEqual(v6.quantity, v5.quantity, label)
                XCTAssertEqual(v6.unit, v5.unit, label)
                XCTAssertEqual(v6.preparation, v5.preparation, label)
                XCTAssertEqual(v6.notices, v5.notices, label)
                XCTAssertEqual(v6.numeralConvention, v5.numeralConvention, label)
                XCTAssertEqual(FoodListParser.amountNumeral(of: v6), FoodListParser.amountNumeral(of: v5), label)
            }
        }
    }

    /// The lines whose parse changes from v5, pinned so the change stays deliberate: v5 read some
    /// as a count or kept the explicit volume, and kept the container in the query.
    func testLinesWhoseParseChangesFromV5() throws {
        for (text, v5Quantity, v5Unit, v5Query) in [
            ("2 mugs of tea", nil, nil, "mugs of tea"), ("a pot of yoghurt", 1, QuantityUnit.count, "pot of yoghurt"),
            ("2 glasses of milk", 2, .count, "glasses of milk"), ("250 ml mug of milk", 250, .millilitres, "mug of milk"),
            ("mugs of tea", nil, nil, "mugs of tea")
        ] as [(String, Double?, QuantityUnit?, String)] {
            let v5 = try XCTUnwrap(FoodListParser.parseV5(text, convention: .fullStopDecimal).first)
            XCTAssertEqual(v5.quantity, v5Quantity, text)
            XCTAssertEqual(v5.unit, v5Unit, text)
            XCTAssertEqual(v5.query, v5Query, text)
            let v6 = try XCTUnwrap(FoodListParser.parseV6(text, convention: .fullStopDecimal).first)
            XCTAssertNil(v6.quantity, text)
            XCTAssertNil(v6.unit, text)
            XCTAssertEqual(v6.notices, [.householdMeasure], text)
        }
    }

    /// A v6 line encodes with its own version and the v5 form; stored v5 lines decode and re-encode
    /// byte-identically and are never re-parsed; an unknown version keeps the v3 reading.
    func testEncodingAndStoredLinesKeepTheirVersion() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let v6 = try XCTUnwrap(FoodListParser.parseV6("2 mugs of tea", convention: .fullStopDecimal).first)
        let v6JSON = #"{"grammarVersion":"food-list-lexical-v6","lineNumber":1,"notices":["householdMeasure"],"numeralConvention":"full_stop_decimal","original":"2 mugs of tea","query":"tea"}"#
        XCTAssertEqual(String(decoding: try encoder.encode(v6), as: UTF8.self), v6JSON)
        XCTAssertTrue(v6.isV6)
        XCTAssertFalse(v6.isV5)
        XCTAssertFalse(v6.isV4)
        XCTAssertEqual(v6.effectiveGrammarVersion, "food-list-lexical-v6")

        let v5JSON = #"{"grammarVersion":"food-list-lexical-v5","lineNumber":1,"notices":[],"numeralConvention":"full_stop_decimal","original":"a pot of yoghurt","quantity":1,"query":"pot of yoghurt","unit":"count"}"#
        XCTAssertEqual(String(decoding: try encoder.encode(try XCTUnwrap(
            FoodListParser.parseV5("a pot of yoghurt", convention: .fullStopDecimal).first)), as: UTF8.self), v5JSON)
        let storedV5 = try JSONDecoder().decode(ParsedFoodListLine.self, from: Data(v5JSON.utf8))
        XCTAssertEqual(String(decoding: try encoder.encode(storedV5), as: UTF8.self), v5JSON, "never re-parsed")
        XCTAssertTrue(storedV5.isV5)
        XCTAssertFalse(storedV5.isV6)
        XCTAssertTrue(storedV5.readsNumeralConvention)
        XCTAssertEqual(storedV5.quantity, 1, "a restored v5 line keeps its own parse")

        let unknown = try JSONDecoder().decode(ParsedFoodListLine.self, from: Data(
            v6JSON.replacingOccurrences(of: "food-list-lexical-v6", with: "food-list-lexical-v8").utf8))
        XCTAssertFalse(unknown.readsNumeralConvention, "only the frozen v4 to v7 identifiers read a convention")
        XCTAssertFalse(unknown.isV6)
    }
}

/// The shared container rule (#335, #353) that search and the list grammar both use.
final class HouseholdContainerRuleTests: XCTestCase {
    func testGuards() {
        for unit in ["cup", "cups", "mug", "mugs", "Mug"] {
            XCTAssertTrue(HouseholdContainerRule.leavesFoodText(unit: unit, followedByOf: false, rest: "tea"), unit)
            XCTAssertTrue(HouseholdContainerRule.leavesFoodText(unit: unit, followedByOf: true, rest: "tea"), unit)
            XCTAssertFalse(HouseholdContainerRule.leavesFoodText(unit: unit, followedByOf: false, rest: "cake"), unit)
            XCTAssertFalse(HouseholdContainerRule.leavesFoodText(unit: unit, followedByOf: false, rest: "Cakes with cream"), unit)
            XCTAssertTrue(HouseholdContainerRule.leavesFoodText(unit: unit, followedByOf: false, rest: "cakey tea"), unit)
        }
        for unit in ["pot", "pots", "glass", "glasses", "bottle", "bottles", "pack", "packs"] {
            XCTAssertFalse(HouseholdContainerRule.leavesFoodText(unit: unit, followedByOf: false, rest: "noodles"), unit)
            XCTAssertTrue(HouseholdContainerRule.leavesFoodText(unit: unit, followedByOf: true, rest: "yoghurt"), unit)
        }
        // Other household units are not guarded by this rule.
        XCTAssertTrue(HouseholdContainerRule.leavesFoodText(unit: "slices", followedByOf: false, rest: "toast"))
    }

    func testLeadingListContainer() throws {
        for unit in HouseholdContainerRule.listContainerUnits {
            let match = try XCTUnwrap(HouseholdContainerRule.leadingListContainer(in: "\(unit) of tea"), unit)
            XCTAssertEqual(match.unit, unit)
            XCTAssertEqual(match.phrase, "\(unit) of ")
            XCTAssertEqual(match.rest, "tea")
        }
        for text in ["cupcakes", "potatoes", "packed lunch", "mugwort tea", "glassful of water", "mug cake", "cups cakes",
                     "pot noodle", "glasses noodles", "packs crisps", "mugs", "mug of", "mug of 2", "bottle of water",
                     "jar of honey", "tea in a mug", ""] {
            XCTAssertNil(HouseholdContainerRule.leadingListContainer(in: text), text)
        }
        XCTAssertEqual(HouseholdContainerRule.leadingListContainer(in: "Mugs Of Tea")?.rest, "Tea")
    }
}
