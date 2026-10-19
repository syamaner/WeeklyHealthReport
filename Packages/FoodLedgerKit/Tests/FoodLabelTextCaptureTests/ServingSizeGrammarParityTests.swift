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
