import FoodLedgerDomain
import XCTest

/// The golden numeral table of docs/food-list-lexical-v4.md (#222). nil means ambiguous: no
/// amount and an `ambiguousNumber` notice.
final class FoodListLexicalV4Tests: XCTestCase {
    /// (numeral, full-stop-decimal, comma-decimal, unspecified)
    static let separatorTable: [(String, Double?, Double?, Double?)] = [
        ("150", 150, 150, 150),
        ("1.5", 1.5, 1.5, 1.5),
        ("0.25", 0.25, 0.25, 0.25),
        (".5", 0.5, 0.5, 0.5),
        ("1.500", 1.5, nil, nil),
        ("0.175", 0.175, nil, nil),
        ("1.5000", 1.5, 1.5, 1.5),
        ("1,5", nil, 1.5, nil),
        ("1,50", nil, 1.5, nil),
        ("1,500", 1500, 1.5, nil),
        ("12,345", 12345, 12.345, nil),
        ("1,5000", nil, 1.5, nil),
        ("1,000,000", 1_000_000, nil, nil),
        ("1,000.5", 1000.5, nil, nil),
        ("12,34,567", nil, nil, nil),
        ("1.000.000", nil, nil, nil),
        ("1.500,5", nil, nil, nil),
        ("1 500", nil, nil, nil),
        ("1\u{00A0}500", nil, nil, nil),
        ("1\u{202F}500", nil, nil, nil)
    ]

    /// (numeral, value in every convention)
    static let fractionTable: [(String, Double?)] = [
        ("1/2", 0.5), ("3/4", 0.75), ("½", 0.5), ("1/0", nil), ("1.5/2", nil), ("1,5/2", nil)
    ]

    func testSeparatorTableInLeadingAndTrailingPositions() throws {
        for (numeral, fullStop, comma, unspecified) in Self.separatorTable {
            for (convention, expected) in [(NumeralConvention.fullStopDecimal, fullStop), (.commaDecimal, comma), (.unspecified, unspecified)] {
                XCTAssertEqual(FoodListParser.number(numeral, convention: convention), expected, "\(numeral) \(convention)")
                for text in ["\(numeral) g rice", "rice \(numeral) g"] {
                    let line = try XCTUnwrap(FoodListParser.parse(text, convention: convention).first)
                    let label = "\(text) \(convention)"
                    XCTAssertEqual(line.quantity, expected, label)
                    XCTAssertEqual(line.query, "rice", label)
                    XCTAssertEqual(line.grammarVersion, "food-list-lexical-v4", label)
                    XCTAssertEqual(line.numeralConvention, convention, label)
                    if expected == nil {
                        XCTAssertEqual(line.notices, [.ambiguousNumber], label)
                    } else {
                        XCTAssertEqual(line.unit, .grams, label)
                        XCTAssertEqual(line.notices, [], label)
                        XCTAssertEqual(FoodListParser.amountNumeral(of: line), numeral, label)
                    }
                }
            }
        }
    }

    func testFractionsDoNotDependOnTheConvention() throws {
        for (numeral, expected) in Self.fractionTable {
            for convention in NumeralConvention.allCases {
                XCTAssertEqual(FoodListParser.number(numeral, convention: convention), expected, "\(numeral) \(convention)")
                let line = try XCTUnwrap(FoodListParser.parse("\(numeral) g rice", convention: convention).first)
                XCTAssertEqual(line.quantity, expected, "\(numeral) \(convention)")
                XCTAssertEqual(line.notices.contains(.ambiguousNumber), expected == nil, "\(numeral) \(convention)")
            }
        }
    }

    /// Q1: "1,500" groups only under full-stop-decimal; kg and L still scale.
    func testGroupedAmountsScaleWithTheirUnit() throws {
        let english = try XCTUnwrap(FoodListParser.parse("1,500 kg rice", convention: .fullStopDecimal).first)
        XCTAssertEqual(english.quantity, 1_500_000)
        let german = try XCTUnwrap(FoodListParser.parse("1,500 kg Reis", convention: .commaDecimal).first)
        XCTAssertEqual(german.quantity, 1500)
        let litres = try XCTUnwrap(FoodListParser.parse("1,5 l milk", convention: .commaDecimal).first)
        XCTAssertEqual(litres.quantity, 1500)
        XCTAssertEqual(litres.unit, .millilitres)
    }

    /// Forms outside the separator rules parse exactly as in v3 under every convention.
    func testConventionIndependentLinesMatchV3() throws {
        let lines = [
            "1 1/2 cups tea", "100-150 g rice", "1–2 apples", "2x350g soup", "2 x 500 g yoghurt", "half avocado",
            "£7.40", "08:10 - 08:45", "Breakfast:", "2 pretzels", "1/2 l milk", "½ yellow pepper", "0 g rice",
            "-3 g rice", "12 mg zinc", "75 graams cereal", "2 cups soup", ",5 g rice", "a banana",
            "180 grams cooked weight chicken breast", "1 mug coffee 18 g grounds", "nan g rice", "rice"
        ]
        for text in lines {
            let legacy = try XCTUnwrap(FoodListParser.parse(text).first)
            for convention in NumeralConvention.allCases {
                let line = try XCTUnwrap(FoodListParser.parse(text, convention: convention).first)
                let label = "\(text) \(convention)"
                XCTAssertEqual(line.quantity, legacy.quantity, label)
                XCTAssertEqual(line.unit, legacy.unit, label)
                XCTAssertEqual(line.query, legacy.query, label)
                XCTAssertEqual(line.preparation, legacy.preparation, label)
                XCTAssertEqual(line.notices, legacy.notices, label)
            }
        }
    }

    /// The frozen v3 grammar, its version and its encoding are unchanged; the shared v3 numeral
    /// rule (receipts, inventory) still reads "1,500" as ambiguous and "1.500" as 1.5.
    func testV3GrammarAndEncodingAreFrozen() throws {
        XCTAssertEqual(FoodListParser.version, "food-list-lexical-v4")
        XCTAssertEqual(FoodListParser.legacyVersion, "food-list-lexical-v3")
        let legacy = try XCTUnwrap(FoodListParser.parse("1.500 g rice").first)
        XCTAssertEqual(legacy.quantity, 1.5)
        XCTAssertNil(legacy.grammarVersion)
        XCTAssertNil(legacy.numeralConvention)
        XCTAssertEqual(legacy.effectiveGrammarVersion, "food-list-lexical-v3")
        XCTAssertNil(FoodListParser.number("1,500"))
        XCTAssertEqual(FoodListParser.number("1.500"), 1.5)
        XCTAssertEqual(FoodListParser.number("1,5000"), 1.5)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let v3JSON = #"{"lineNumber":1,"notices":[],"original":"150 g rice","quantity":150,"query":"rice","unit":"g"}"#
        XCTAssertEqual(String(decoding: try encoder.encode(try XCTUnwrap(FoodListParser.parse("150 g rice").first)), as: UTF8.self), v3JSON)
        let decoded = try JSONDecoder().decode(ParsedFoodListLine.self, from: Data(v3JSON.utf8))
        XCTAssertNil(decoded.grammarVersion)
        XCTAssertEqual(String(decoding: try encoder.encode(decoded), as: UTF8.self), v3JSON, "a v3 line re-encodes byte-identically")

        let v4 = try XCTUnwrap(FoodListParser.parse("150 g rice", convention: .commaDecimal).first)
        XCTAssertEqual(
            String(decoding: try encoder.encode(v4), as: UTF8.self),
            #"{"grammarVersion":"food-list-lexical-v4","lineNumber":1,"notices":[],"numeralConvention":"comma_decimal","original":"150 g rice","quantity":150,"query":"rice","unit":"g"}"#
        )
        XCTAssertEqual(try JSONDecoder().decode(ParsedFoodListLine.self, from: try encoder.encode(v4)), v4)
    }
}
