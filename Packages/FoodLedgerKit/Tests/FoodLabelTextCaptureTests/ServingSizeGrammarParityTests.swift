import Foundation
import FoodLedgerApplication
@testable import NutritionLabelParsing
import XCTest

/// `pasted-label-serving-v2` locates the recorded serving quantity with the application's copy of
/// the parser v2 serving-size grammar (decision 10: the application never imports the parser).
/// This pins the copy to the parser: byte-identical patterns, and on a fixture set the policy
/// binds exactly the quantity the parser recorded (contract section 6.3). Synthetic lines only.
final class ServingSizeGrammarParityTests: XCTestCase {
    func testThePatternsAreByteIdenticalToTheParser() {
        XCTAssertEqual(PastedLabelServingSizeGrammar.labelPattern, Patterns.servingSize.expression.pattern)
        XCTAssertEqual(PastedLabelServingSizeGrammar.parenthesisedPattern, Patterns.parenthesised.expression.pattern)
        XCTAssertEqual(PastedLabelServingSizeGrammar.quantityPattern, Patterns.servingQuantity.expression.pattern)
    }

    /// Every v2 fixture line, built from the parser's own reading (realistic `decimal_text` and
    /// `unit`), with whether the policy treats it as approximate (contract section 6.3, test 50).
    func testV2FixtureLinesAreClassifiedFromTheParsersOwnReading() throws {
        let cases: [(String, Bool)] = [
            ("每一份量30公克", false), ("每一份量30公克，本包裝含約10份", false), ("每一份量 30 公克（約2片）", false),
            ("每一份量30公克(约2片)", false), ("Serving size 30g (about 2 biscuits)", false), ("Serving size 30g (approx. 3 pieces)", false),
            ("Serving size 30g – 2 biscuits", false), ("Serving size 30g ~ 2 pieces", false), ("Serving size 1 bar (30g)", false),
            ("Serving size 30g (surrounded)", false),
            ("Serving size about 30g", true), ("每一份量约30公克", true), ("每一份量〜30公克", true), ("每一份量≒30公克", true),
            ("Serving size ±30g", true), ("Serving size 25-30g", true), ("Serving size 25–30 g", true), ("每一份量25至30公克", true),
            ("每一份量25～30公克", true), ("Serving size 30g-35g", true), ("每一份量30公克至35公克", true),
            ("Serving size 3 gummies (approx. 3g)", true), ("Serving size 30g approx.", true), ("Serving size 30g (approx.)", true),
            ("Serving size 30 g approximately", true), ("Serving size 30g 約", true), ("每一份量 30 公克（約30公克）", true),
            ("Serving size 30g (approx. 28g)", true), ("Serving size 30g (approx. 28 grams)", true), ("每一份量 30 公克（約2）", true),
            ("Serving size 30 g ± 2 g", true), ("Serving size 30g±2", true), ("Serving size 30g ± 2%", true),
            ("Serving size 30 g ± 2 grams", true), ("Serving size 30 g ±", true), ("Serving size 30g-35 grams", true),
            ("Serving size 30 g - 35 g", true), ("Serving size 30g, approx.", true), ("每一份量30公克，約", true),
            ("Serving size 30g (2 biscuits) approx.", true), ("Serving size 30g (about 1 ounce)", true),
            ("Serving size 30g (approx. 28 gm)", true), ("Serving size 30g (about 2 fl oz)", true),
            ("每一份量25－30公克", true), ("每一份量30公克－35公克", true), ("Serving size 25—30g", true), ("Serving size 25−30g", true),
            ("Serving size 25‐30g", true), ("Serving size 25‑30g", true), ("Serving size 25 to 30 g", true), ("每一份量25到30公克", true),
            ("Serving size 30g +/- 2g", true), ("每一份量30公克／約", true), ("Serving size 30g (2 biscuits) (approx.)", true),
            ("每一份量30公克（2片）（約）", true), ("Serving size 2 biscuits (30g) approx.", true), ("每一份量2片（30公克）約", true),
            ("每一份量30公克 左右", true), ("Serving size 30g (about 1/4 cup)", true), ("Serving size 30g (about 1 tbsp)", false),
            ("Serving size 2 tomatoes 30g", false),
            // #277: ranges elsewhere on the line, the remaining dashes, OCR 一 and ー between
            // digits, and the remaining words and marks.
            ("Serving size 2-3 biscuits (30g)", true), ("每一份量2-3片（30公克）", true), ("Serving size 1 bar - 30g", true),
            ("Serving size 1 bar – 40g", true), ("Serving size 1 to 2 biscuits (30g)", true),
            ("Serving size 25‒30g", true), ("Serving size 25―30g", true), ("每一份量25﹣30公克", true), ("Serving size 25⁓30g", true),
            ("每一份量25﹏30公克", true), ("Serving size 25─30g", true), ("每一份量25一30公克", true), ("每一份量25ー30公克", true),
            ("每一份量25 一 30公克", true), ("Serving size 30g‒35g", true), ("Serving size 30g ― 35 g", true), ("Serving size 25 TO 30 g", true),
            ("Serving size 30g approximate", true), ("Serving size approximate 30g", true), ("Serving size ca. 30g", true),
            ("Serving size ca 30g", true), ("Serving size 30g ca.", true), ("Serving size 30g (ca.)", true), ("Serving size c. 30g", true),
            ("Serving size c.30g", true), ("Serving size 30g +- 2g", true), ("Serving size 30g+-2", true), ("每一份量30公克 上下", true),
            ("每一份量 30 公克 上下", true),
            // Kept exact: whole-word "to", 一/ー not between digits, bare "c", "c." not before a number.
            ("Serving size 1 potato 30g", false), ("Serving size 2 tortillas 60g", false), ("每一份量 30 公克（約2片）", false),
            ("每一份量30公克（2片）", false), ("Serving size 30 g", false), ("每一份量40公克", false), ("Serving size 1 c (30g)", false),
            ("Serving size 1 c. (30g)", false), ("Serving size 30g (ca. 2 biscuits)", false), ("Serving size 30g ― 2 biscuits", false),
            ("Serving size 1 can (330ml)", false)
        ]
        for (line, approximate) in cases {
            let rest = try XCTUnwrap(Patterns.servingSize.firstMatch(in: line)?[1] ?? nil, line)
            let parsed = ParseState.servingSize(printed: line, quantityText: rest)
            XCTAssertNotNil(parsed.decimalText, "the parser reads a quantity: \(line)")
            let size = PastedLabelManifest.Candidate.ServingSize(printedText: parsed.printedText, decimalText: parsed.decimalText,
                                                                 unit: parsed.unit, canonicalUnit: parsed.canonicalUnit)
            let segment = try XCTUnwrap(PastedLabelServingPolicy.servingSegment(size), line)
            XCTAssertEqual(PastedLabelServingPolicy.approximate(segment), approximate, "\(line) → \(segment)")
        }
    }

    /// An "about" pack line is read as printed and approximate, never dropped (final journey QA).
    /// "30公克左右" (no space): the parser's letter lookahead rejects "公克左", so no quantity is
    /// read and v2 never offers servings for it; with a space the 左右 tail makes it approximate.
    func testZuoYouWithoutASpaceReadsNoQuantity() {
        let parsed = ParseState.servingSize(printed: "每一份量30公克左右", quantityText: "30公克左右")
        XCTAssertNil(parsed.decimalText)
        let size = PastedLabelManifest.Candidate.ServingSize(printedText: parsed.printedText, decimalText: parsed.decimalText,
                                                             unit: parsed.unit, canonicalUnit: parsed.canonicalUnit)
        XCTAssertEqual(PastedLabelServingPolicy.exactness(size), .unmatched)
    }

    /// "30公克上下" (no space): as for 左右, the parser's letter lookahead rejects "公克上", so no
    /// quantity is read and v2 never offers servings; with a space the 上下 tail makes it approximate.
    func testShangXiaWithoutASpaceReadsNoQuantity() {
        let parsed = ParseState.servingSize(printed: "每一份量30公克上下", quantityText: "30公克上下")
        XCTAssertNil(parsed.decimalText)
        let size = PastedLabelManifest.Candidate.ServingSize(printedText: parsed.printedText, decimalText: parsed.decimalText,
                                                             unit: parsed.unit, canonicalUnit: parsed.canonicalUnit)
        XCTAssertEqual(PastedLabelServingPolicy.exactness(size), .unmatched)
    }

    /// The range Confirm shows is the serving size's own, from the parser's own reading (#277).
    func testOnlyTheServingSizesOwnRangeIsReported() throws {
        typealias R = PastedLabelServingPolicy.PrintedRange
        let cases: [(String, R?)] = [
            ("Serving size 2-3 biscuits (30g)", nil), ("每一份量2-3片（30公克）", nil), ("Serving size 1 bar - 30g", nil),
            ("Serving size 1 bar – 40g", nil), ("Serving size 1 to 2 biscuits (30g)", nil),
            ("Serving size 25-30g", R(low: "25", high: "30")), ("Serving size 25 g – 30 g", R(low: "25", high: "30")),
            ("每一份量25公克至30公克", R(low: "25", high: "30")), ("Serving size 30g-35g", R(low: "30", high: "35")),
            ("每一份量25一30公克", R(low: "25", high: "30")), ("Serving size 2-3 biscuits (25-30g)", R(low: "25", high: "30"))
        ]
        for (line, own) in cases {
            let rest = try XCTUnwrap(Patterns.servingSize.firstMatch(in: line)?[1] ?? nil, line)
            let parsed = ParseState.servingSize(printed: line, quantityText: rest)
            let size = PastedLabelManifest.Candidate.ServingSize(printedText: parsed.printedText, decimalText: parsed.decimalText,
                                                                 unit: parsed.unit, canonicalUnit: parsed.canonicalUnit)
            XCTAssertEqual(PastedLabelServingPolicy.exactness(size), .range(own: own), line)
        }
    }

    func testAnApproximatePackLineIsReadAsApproximate() {
        for line in ["本包裝含約10份", "本包裝含 約 10 份"] {
            let text = "營養標示\n每一份量30公克\n\(line)\n每份 每100公克\n熱量 111大卡 370大卡\n"
            let pack = NutritionLabelTextParser().parse(text, inputSHA256: "synthetic").servingsPerPack
            XCTAssertEqual(pack?.decimalText, "10", line)
            XCTAssertEqual(pack?.approximate, true, line)
        }
    }

    func testThePolicyBindsTheQuantityTheParserRecorded() throws {
        let lines = [
            "每一份量30公克", "每一份量 30 公克", "每份量250毫升", "每一份量30公克，本包裝含約10份", "每一份量 30 公克（約2片）",
            "Serving size 30g", "Serving size: 30 g", "Portion size 250ml", "Serving size 1 bar (30g)", "Serving size 3 gummies (approx. 3g)",
            "Serving size 30g (about 2 biscuits)", "Serving size 25-30g", "Serving size 25–30 g", "Serving size 30g-35g", "Serving size 30g ± 2g",
            "Serving size 30g±2", "Serving size 30g – 2 biscuits", "Serving size 30g ~ 2 pieces", "Serving size 2 cups (480 mL) about",
            "Serving size 30gummies 30g", "Serving size 1 cup (240ml) 30g", "每一份量25至30公克", "Serving size about 30g"
        ]
        var bound = 0
        for line in lines {
            let rest = try XCTUnwrap(Patterns.servingSize.firstMatch(in: line)?[1] ?? nil, line)
            let parsed = ParseState.servingSize(printed: line, quantityText: rest)
            let size = PastedLabelManifest.Candidate.ServingSize(printedText: parsed.printedText, decimalText: parsed.decimalText,
                                                                 unit: parsed.unit, canonicalUnit: parsed.canonicalUnit)
            guard parsed.decimalText != nil else {
                XCTAssertNil(PastedLabelServingPolicy.servingSegment(size), line)
                continue
            }
            // The segment ends at the parser's quantity: its last characters are that quantity
            // (or a tolerance or word tail written straight after it), never another number.
            let segment = try XCTUnwrap(PastedLabelServingPolicy.servingSegment(size), "the policy finds the parser's quantity: \(line)")
            XCTAssertTrue(segment.contains(try XCTUnwrap(parsed.decimalText)), line)
            bound += 1
            // A different recorded quantity on the same line is never bound.
            let other = PastedLabelManifest.Candidate.ServingSize(printedText: parsed.printedText, decimalText: "999",
                                                                  unit: parsed.unit, canonicalUnit: parsed.canonicalUnit)
            XCTAssertNil(PastedLabelServingPolicy.servingSegment(other), line)
        }
        XCTAssertGreaterThan(bound, 15)
        // The bracketed quantity wins, as in the parser.
        let cup = ParseState.servingSize(printed: "Serving size 1 cup (240ml) 30g", quantityText: "1 cup (240ml) 30g")
        XCTAssertEqual(cup.decimalText, "240")
        XCTAssertEqual(PastedLabelServingPolicy.servingSegment(.init(printedText: cup.printedText, decimalText: cup.decimalText,
                                                                     unit: cup.unit, canonicalUnit: cup.canonicalUnit)), "1 cup (240ml")
        // The letter lookahead: "30gummies" is not a quantity, so the parser records 30 g later.
        let gummies = ParseState.servingSize(printed: "Serving size 30gummies 30g", quantityText: "30gummies 30g")
        XCTAssertEqual(PastedLabelServingPolicy.servingSegment(.init(printedText: gummies.printedText, decimalText: gummies.decimalText,
                                                                     unit: gummies.unit, canonicalUnit: gummies.canonicalUnit)), "30gummies 30g")
    }
}
