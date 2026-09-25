import FoodLedgerDomain
import XCTest

final class ReceiptParserTests: XCTestCase {
    func testCountPackAndPriceStaySeparate() throws {
        let line = try XCTUnwrap(ReceiptParser.parse("2 x Meadow yoghurt 4 x 125 gr £3.50").first)
        XCTAssertEqual(line.purchaseCount, 2)
        XCTAssertEqual(line.unitsPerPack, 4)
        XCTAssertEqual(line.packAmount, 125)
        XCTAssertEqual(line.packUnit, .grams)
        XCTAssertEqual(line.priceText, "£3.50")
        XCTAssertEqual(line.description, "Meadow yoghurt")
    }

    func testDecimalCommaAndUnitVariants() throws {
        for unit in ["gram", "grams", "gr", "g"] {
            let line = try XCTUnwrap(ReceiptParser.parse("Nuts 125,5 \(unit) 2,75").first)
            XCTAssertEqual(line.packAmount, 125.5)
            XCTAssertEqual(line.packUnit, .grams)
            XCTAssertNil(line.purchaseCount)
            XCTAssertEqual(line.priceText, "2,75")
        }
        XCTAssertEqual(try ReceiptParser.parse("Milk 1.5 litres")[0].packAmount, 1500)
    }

    func testAdjustmentsAndOrdersNeverProposePositiveAcquisition() throws {
        for input in ["RETURN milk 1 l -1.50", "Ordered rice 2 kg", "Substitution pears 500 g", "Not delivered oats 1 kg", "Discount nuts -0.50", "VAT 0.35", "Total 12.99"] {
            let line = try ReceiptParser.parse(input)[0]
            XCTAssertNotEqual(line.kind, .product, input)
            XCTAssertNil(line.purchaseCount)
            XCTAssertNil(line.packAmount)
        }
    }

    func testAmbiguityAndDuplicateLinesArePreserved() throws {
        let input = "\n  APPLES  \r\nAPPLES\nFish 500 g drained 350 g\nLoose carrots 0.750 kg @ 1.25/kg"
        let lines = try ReceiptParser.parse(input)
        XCTAssertEqual(lines.map(\.lineNumber), [2, 3, 4, 5])
        XCTAssertEqual(lines[0].original, "  APPLES  ")
        XCTAssertNil(lines[0].packAmount)
        XCTAssertNil(lines[2].packAmount)
        XCTAssertEqual(lines[3].kind, .requiresReview)
        XCTAssertNil(lines[3].packAmount)
    }

    func testEmptyOversizedAndAmbiguousNumbersFailClosed() throws {
        XCTAssertThrowsError(try ReceiptParser.parse(" \n"))
        XCTAssertThrowsError(try ReceiptParser.parse(String(repeating: "x", count: ReceiptParser.maximumCharacters + 1)))
        XCTAssertNil(try ReceiptParser.parse("Rice 1,000 g")[0].packAmount)
        XCTAssertNil(try ReceiptParser.parse("Mystery 7 zz £2.10")[0].packAmount)
    }
}
