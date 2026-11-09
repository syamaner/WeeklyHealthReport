import FoodLedgerDomain
import XCTest

/// The golden tables of docs/food-list-lexical-v5.md (#140, decision B3): vague portion words get
/// the `householdMeasure` notice and no amount under every numeral convention; every other line
/// parses exactly as `food-list-lexical-v4`, which stays frozen. v5 is itself frozen as
/// `FoodListParser.parseV5` since `food-list-lexical-v6` (#353).
final class FoodListLexicalV5Tests: XCTestCase {
    /// (line, query after the vague portion phrase is removed)
    static let vagueTable: [(String, String)] = [
        ("a handful of almonds", "almonds"),
        ("handful of almonds", "almonds"),
        ("A Handful Of Almonds", "Almonds"),
        ("2 handfuls of almonds", "almonds"),
        ("two handfuls almonds", "almonds"),
        ("half a handful of oats", "oats"),
        // Nothing after the phrase: the line after its leading amount, never an empty query.
        ("a handful", "handful"),
        ("a handful of", "handful of"),
        ("pinch", "pinch"),
        ("- a handful of blueberries", "blueberries"),
        ("a pinch of salt", "salt"),
        ("pinch salt", "salt"),
        ("2 pinches of salt", "salt"),
        ("a dash of milk", "milk"),
        ("dash of soy sauce", "soy sauce"),
        ("a splash of milk", "milk"),
        ("2 splashes of oat milk", "oat milk"),
        ("a drizzle of olive oil", "olive oil"),
        ("drizzle honey", "honey"),
        ("a bit of cheese", "cheese"),
        ("bits of chocolate", "chocolate"),
        ("a few strawberries", "strawberries"),
        ("few grapes", "grapes")
    ]

    func testVersionsAreFrozen() {
        XCTAssertEqual(FoodListParser.version, "food-list-lexical-v7", "v5 is frozen as parseV5 (#353), v6 as parseV6 (#359)")
        XCTAssertEqual(FoodListParser.v5Version, "food-list-lexical-v5")
        XCTAssertEqual(FoodListParser.v4Version, "food-list-lexical-v4")
        XCTAssertEqual(FoodListParser.legacyVersion, "food-list-lexical-v3")
    }

    /// Every vague portion line has no amount or unit and the household-measure notice, never a
    /// missing-quantity or count reading, under every convention.
    func testVaguePortionsHaveNoAmountInEveryConvention() throws {
        for (text, query) in Self.vagueTable {
            for convention in NumeralConvention.allCases {
                let line = try XCTUnwrap(FoodListParser.parseV5(text, convention: convention).first)
                let label = "\(text) \(convention)"
                XCTAssertNil(line.quantity, label)
                XCTAssertNil(line.unit, label)
                XCTAssertEqual(line.notices, [.householdMeasure], label)
                XCTAssertEqual(line.query, query, label)
                XCTAssertEqual(line.original, text, label)
                XCTAssertEqual(line.grammarVersion, "food-list-lexical-v5", label)
                XCTAssertEqual(line.numeralConvention, convention, label)
                XCTAssertNil(FoodListParser.amountNumeral(of: line), label)
            }
        }
    }

    /// The v4 golden numerals before a vague word: no amount in any convention, with the number
    /// format notice as well wherever v4 finds the numeral ambiguous.
    func testVaguePortionsAfterEveryV4NumeralForm() throws {
        let numerals = FoodListLexicalV4Tests.separatorTable.map(\.0) + FoodListLexicalV4Tests.fractionTable.map(\.0)
        for numeral in numerals {
            for word in ["handfuls of", "pinches", "bits of"] {
                let text = "\(numeral) \(word) nuts"
                for convention in NumeralConvention.allCases {
                    let line = try XCTUnwrap(FoodListParser.parseV5(text, convention: convention).first)
                    let label = "\(text) \(convention)"
                    let ambiguous = FoodListParser.number(numeral, convention: convention) == nil
                    XCTAssertNil(line.quantity, label)
                    XCTAssertNil(line.unit, label)
                    XCTAssertEqual(line.notices, ambiguous ? [.ambiguousNumber, .householdMeasure] : [.householdMeasure], label)
                    XCTAssertEqual(line.query, "nuts", label)
                }
            }
        }
    }

    /// What v5 changes: the frozen v4 grammar reads an article or number before a vague word as
    /// a definite count. That reading stays reproducible for stored v4 lines.
    func testFrozenV4StillReadsVagueWordsAsCounts() throws {
        let line = try XCTUnwrap(FoodListParser.parseV4("a handful of almonds", convention: .fullStopDecimal).first)
        XCTAssertEqual(line.quantity, 1)
        XCTAssertEqual(line.unit, .count)
        XCTAssertEqual(line.query, "handful of almonds")
        XCTAssertEqual(line.grammarVersion, "food-list-lexical-v4")
        let few = try XCTUnwrap(FoodListParser.parseV4("a few strawberries", convention: .commaDecimal).first)
        XCTAssertEqual(few.quantity, 1)
        XCTAssertEqual(few.unit, .count)
    }

    /// Every other line, the whole v4 golden corpus included, parses exactly as v4 apart from the
    /// grammar version: words that only begin like a vague word, and a vague word after an amount,
    /// are not vague portions.
    func testNonVagueLinesMatchV4() throws {
        var lines = FoodListLexicalV4Tests.separatorTable.flatMap { ["\($0.0) g rice", "rice \($0.0) g"] }
        lines += FoodListLexicalV4Tests.fractionTable.map { "\($0.0) g rice" }
        lines += [
            "1 1/2 cups tea", "100-150 g rice", "1–2 apples", "2x350g soup", "2 x 500 g yoghurt", "half avocado",
            "£7.40", "08:10 - 08:45", "Breakfast:", "2 pretzels", "1/2 l milk", "½ yellow pepper", "0 g rice",
            "-3 g rice", "12 mg zinc", "75 graams cereal", "2 cups soup", ",5 g rice", "a banana",
            "180 grams cooked weight chicken breast", "1 mug coffee 18 g grounds", "nan g rice", "rice",
            "dashi 200 ml", "2 dashi stock cubes", "bitter lemon 330 ml", "a bitter orange", "2 biscuits",
            "pinchos 100 g", "Dash water 330 ml", "fewer crisps", "rice with a handful of peas",
            "almonds 30 g", "2 tbsp olive oil", "1 slice toast"
        ]
        for text in lines {
            for convention in NumeralConvention.allCases {
                let v4 = try XCTUnwrap(FoodListParser.parseV4(text, convention: convention).first)
                let v5 = try XCTUnwrap(FoodListParser.parseV5(text, convention: convention).first)
                let label = "\(text) \(convention)"
                XCTAssertEqual(v5.grammarVersion, "food-list-lexical-v5", label)
                XCTAssertEqual(v5.lineNumber, v4.lineNumber, label)
                XCTAssertEqual(v5.original, v4.original, label)
                XCTAssertEqual(v5.query, v4.query, label)
                XCTAssertEqual(v5.quantity, v4.quantity, label)
                XCTAssertEqual(v5.unit, v4.unit, label)
                XCTAssertEqual(v5.preparation, v4.preparation, label)
                XCTAssertEqual(v5.notices, v4.notices, label)
                XCTAssertEqual(v5.numeralConvention, v4.numeralConvention, label)
                XCTAssertEqual(FoodListParser.amountNumeral(of: v5), FoodListParser.amountNumeral(of: v4), label)
            }
        }
    }

    /// A v5 line encodes with its own version; stored v3 and v4 lines decode and re-encode
    /// byte-identically and keep their version, recognised by frozen identifiers.
    func testEncodingAndStoredLinesKeepTheirVersion() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let v5 = try XCTUnwrap(FoodListParser.parseV5("a handful of almonds", convention: .fullStopDecimal).first)
        let v5JSON = #"{"grammarVersion":"food-list-lexical-v5","lineNumber":1,"notices":["householdMeasure"],"numeralConvention":"full_stop_decimal","original":"a handful of almonds","query":"almonds"}"#
        XCTAssertEqual(String(decoding: try encoder.encode(v5), as: UTF8.self), v5JSON)
        XCTAssertTrue(v5.isV5)
        XCTAssertFalse(v5.isV4)
        XCTAssertTrue(v5.readsNumeralConvention)
        XCTAssertEqual(v5.effectiveGrammarVersion, "food-list-lexical-v5")

        let v4JSON = #"{"grammarVersion":"food-list-lexical-v4","lineNumber":1,"notices":[],"numeralConvention":"full_stop_decimal","original":"a handful of almonds","quantity":1,"query":"handful of almonds","unit":"count"}"#
        XCTAssertEqual(String(decoding: try encoder.encode(try XCTUnwrap(
            FoodListParser.parseV4("a handful of almonds", convention: .fullStopDecimal).first)), as: UTF8.self), v4JSON)
        let storedV4 = try JSONDecoder().decode(ParsedFoodListLine.self, from: Data(v4JSON.utf8))
        XCTAssertEqual(String(decoding: try encoder.encode(storedV4), as: UTF8.self), v4JSON, "never re-parsed")
        XCTAssertTrue(storedV4.isV4)
        XCTAssertFalse(storedV4.isV5)
        XCTAssertTrue(storedV4.readsNumeralConvention)
        XCTAssertEqual(storedV4.quantity, 1, "a restored v4 line keeps its own parse")
        XCTAssertEqual(storedV4.effectiveGrammarVersion, "food-list-lexical-v4")

        let v3JSON = #"{"lineNumber":1,"notices":[],"original":"a handful of almonds","quantity":1,"query":"handful of almonds","unit":"count"}"#
        let storedV3 = try JSONDecoder().decode(ParsedFoodListLine.self, from: Data(v3JSON.utf8))
        XCTAssertEqual(String(decoding: try encoder.encode(storedV3), as: UTF8.self), v3JSON)
        XCTAssertFalse(storedV3.readsNumeralConvention)
        XCTAssertEqual(storedV3.effectiveGrammarVersion, "food-list-lexical-v3")

        let unknown = try JSONDecoder().decode(ParsedFoodListLine.self, from: Data(
            v4JSON.replacingOccurrences(of: "food-list-lexical-v4", with: "food-list-lexical-v8").utf8))
        XCTAssertFalse(unknown.readsNumeralConvention, "only the frozen v4 to v7 identifiers read a convention")
    }

    /// Receipts (`receipt-lexical-v1`) share only the frozen v3 numeral rule and are unaffected.
    func testReceiptsAreUnaffected() throws {
        XCTAssertEqual(ReceiptParser.version, "receipt-lexical-v1")
        let lines = try ReceiptParser.parse("Handful nuts 200g 1.99\n2 x Pinch salt 1.00")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        XCTAssertEqual(String(decoding: try encoder.encode(lines), as: UTF8.self), Self.receiptSnapshot)
    }

    /// Receipt output for the lines above, pinned from the unchanged `receipt-lexical-v1` code.
    static let receiptSnapshot = #"[{"description":"Handful nuts","kind":"product","lineNumber":1,"notices":["Review the printed product, pack and purchase amount.","Printed price retained separately; currency is not guessed.","Measured amount may describe a pack or variable-weight purchase; confirm its meaning."],"original":"Handful nuts 200g 1.99","packAmount":200,"packUnit":"g","priceText":"1.99"},{"description":"Pinch salt","kind":"product","lineNumber":2,"notices":["Review the printed product, pack and purchase amount.","Printed price retained separately; currency is not guessed."],"original":"2 x Pinch salt 1.00","priceText":"1.00","purchaseCount":2}]"#
}
