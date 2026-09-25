import FoodLedgerDomain
import XCTest

final class FoodListParserTests: XCTestCase {
    func testUnitAliasesAndExplicitMetricScaling() throws {
        let cases: [(String, Double, QuantityUnit, String)] = [
            ("75 gram oats", 75, .grams, "oats"), ("75 grams oats", 75, .grams, "oats"),
            ("75 gr oats", 75, .grams, "oats"), ("75g oats", 75, .grams, "oats"),
            ("0.25 kg pears", 250, .grams, "pears"), ("1/2 l milk", 500, .millilitres, "milk"),
            ("125 ML milk", 125, .millilitres, "milk"), ("5,2 gr seeds", 5.2, .grams, "seeds"),
            ("12 grms oats", 12, .grams, "oats"), ("2 pretzels", 2, .count, "pretzels")
        ]
        for (text, amount, unit, query) in cases {
            let line = try XCTUnwrap(FoodListParser.parse(text).first)
            XCTAssertEqual(line.quantity, amount, text)
            XCTAssertEqual(line.unit, unit, text)
            XCTAssertEqual(line.query, query, text)
        }
    }

    func testBlankSeparatorsDoNotMergeDuplicateEntriesAndRawTextIsPreserved() throws {
        let parsed = try FoodListParser.parse(" 250 ml water \r\n\r\n250 ml water\n")
        XCTAssertEqual(parsed.map(\.lineNumber), [1, 3])
        XCTAssertEqual(parsed.map(\.original), [" 250 ml water ", "250 ml water"])
        XCTAssertEqual(parsed.map(\.quantity), [250, 250])
    }

    func testAmbiguousAmountsNeverBecomeConsumedGrams() throws {
        for text in ["1,000 g rice", "1 mug coffee 18 g grounds", "2 x 500 g yoghurt", "12 mg zinc", "2 cups soup", "0 g rice", "-3 g rice"] {
            let line = try XCTUnwrap(FoodListParser.parse(text).first)
            XCTAssertNil(line.quantity, text)
            XCTAssertFalse(line.notices.isEmpty, text)
        }
        XCTAssertNil(FoodListParser.number("nan"))
        XCTAssertNil(FoodListParser.number("inf"))
        XCTAssertNil(FoodListParser.number("1/0"))
    }

    func testModifiersBrandsAndTyposRemainVisible() throws {
        let lines = try FoodListParser.parse("180 grams cooked weight chicken breast\n90 g avacado\n120 g BrandExample yoghurt 8% fat\n45 g homemade nut mix\n1 vitamin D3 tablet\n80 g mackerel")
        XCTAssertEqual(lines[0].preparation, .cooked)
        XCTAssertEqual(lines[0].query, "cooked chicken breast")
        XCTAssertEqual(lines[1].query, "avacado")
        XCTAssertEqual(lines[2].query, "BrandExample yoghurt 8% fat")
        XCTAssertEqual(lines[2].quantity, 120)
        XCTAssertTrue(lines[3].notices.contains(.recipe))
        XCTAssertTrue(lines[4].notices.contains(.supplement))
        XCTAssertNil(lines[5].preparation)
        let conflict = try XCTUnwrap(FoodListParser.parse("80 g raw then cooked fish").first)
        XCTAssertNil(conflict.preparation)
        XCTAssertTrue(conflict.notices.contains(.conflictingPreparation))
    }

    func testInputLimitsDoNotSilentlyTruncate() {
        XCTAssertThrowsError(try FoodListParser.parse(" \n\t"))
        XCTAssertThrowsError(try FoodListParser.parse(String(repeating: "x", count: 30_001)))
        XCTAssertThrowsError(try FoodListParser.parse(Array(repeating: "rice", count: 201).joined(separator: "\n")))
    }

    func testBulletsCountsFractionsAndMealContext() throws {
        let rows = try FoodListParser.parse("Breakfast:\n08:10 - 08:45\n• 1x pear\nHalf avocado\nHalf pack large fries\nLater\n£7.40\nI had lunch at a restaurant.\n18 grams of protein powder\n125 gram milk\n15 grams (dry) seeds")
        for index in [0, 1, 5, 6, 7] { XCTAssertEqual(rows[index].notices, [.contextLine]) }
        XCTAssertEqual(rows[2].quantity, 1)
        XCTAssertEqual(rows[2].query, "pear")
        XCTAssertEqual(rows[2].unit, .count)
        XCTAssertEqual(rows[3].quantity, 0.5)
        XCTAssertEqual(rows[3].query, "avocado")
        XCTAssertNil(rows[4].quantity)
        XCTAssertTrue(rows[4].notices.contains(.householdMeasure))
        XCTAssertEqual(rows[8].query, "protein powder")
        XCTAssertEqual(rows[9].unit, .grams)
        XCTAssertEqual(rows[10].query, "(dry) seeds")
    }

    func testFuzzyUnitSpellingIsFlaggedWithoutChangingItsMeaning() throws {
        let row = try XCTUnwrap(FoodListParser.parse("75 graams cereal").first)
        XCTAssertNil(row.quantity)
        XCTAssertNil(row.unit)
        XCTAssertTrue(row.notices.contains(.possibleUnitTypo))
        XCTAssertEqual(row.query, "graams cereal")
        let pack = try XCTUnwrap(FoodListParser.parse("2x350g soup").first)
        XCTAssertNil(pack.quantity)
        XCTAssertTrue(pack.notices.contains(.multipleAmounts))
        XCTAssertEqual(FoodListParser.suggestedQuery("ripe avacado"), "ripe avocado")
        XCTAssertNil(FoodListParser.suggestedQuery("BrandExample milk"))
        XCTAssertEqual(try FoodListParser.parse("70 g avacado").first?.query, "avacado")
    }
}
