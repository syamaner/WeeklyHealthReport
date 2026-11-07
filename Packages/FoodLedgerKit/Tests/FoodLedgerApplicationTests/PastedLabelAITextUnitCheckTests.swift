import FoodLedgerApplication
import XCTest

/// The unit-check vectors of contract test 9 (docs/pasted-label-ai-text-v1.md 4.2, D10 and D16):
/// a model's unit for a bare number is accepted only when the text states it for the values.
final class PastedLabelAITextUnitCheckTests: XCTestCase {
    typealias Check = PastedLabelAITextUnitCheck
    typealias Locator = PastedLabelTextLocator

    /// Locates `label` and `header` in `text` and checks `printed` with `unit`.
    func outcome(_ text: String, header: String, label: String, printed: String, unit: String?) -> Check.Outcome {
        let headers = [Locator.Header(id: "h1", printedText: header, basis: "per_100g")]
        let rows = [Locator.Row(printedLabel: label, values: [Locator.Value(headerID: "h1", printedText: printed)])]
        let located = Locator.locate(text: text, headers: headers, rows: rows)
        return Check.check(text: text, rows: rows, units: [[unit]], located: located)[0]
    }

    func testUnitOnlyHeaderTokensStateTheUnit() {
        XCTAssertEqual(outcome("Per 100 g (g)\nFat 5", header: "Per 100 g (g)", label: "Fat", printed: "5", unit: "g"), .statedInHeader)
        XCTAssertEqual(outcome("g\nFat 5", header: "g", label: "Fat", printed: "5", unit: "g"), .statedInHeader)
        XCTAssertEqual(outcome("mg\nSodium 400", header: "mg", label: "Sodium", printed: "400", unit: "mg"), .statedInHeader)
        XCTAssertEqual(outcome("mg\nSodium 400", header: "mg", label: "Sodium", printed: "400", unit: "g"), .notStated)
    }

    func testUnitOnlyRowLabelTokensStateTheUnit() {
        XCTAssertEqual(outcome("Per 100g\nFat (g) 5", header: "Per 100g", label: "Fat", printed: "5", unit: "g"), .statedInRowLabel)
        XCTAssertEqual(outcome("Per 100g\nEnergy kJ/kcal 1046", header: "Per 100g", label: "Energy", printed: "1046", unit: "kJ"), .statedInRowLabel)
        XCTAssertEqual(outcome("每100公克\n蛋白質(公克) 3.2", header: "每100公克", label: "蛋白質", printed: "3.2", unit: "g"), .statedInRowLabel,
                       "公克 and g are the same canonical unit")
    }

    func testRowLabelUnitTakesPrecedenceOverHeaderUnit() {
        XCTAssertEqual(outcome("(g)\nSodium (mg) 400", header: "(g)", label: "Sodium", printed: "400", unit: "mg"), .statedInRowLabel)
        XCTAssertEqual(outcome("(g)\nSodium (mg) 400", header: "(g)", label: "Sodium", printed: "400", unit: "g"), .notStated)
    }

    func testBasisQuantityInAHeaderNeverStatesAUnit() {
        XCTAssertEqual(outcome("per 100 g\nFat 5", header: "per 100 g", label: "Fat", printed: "5", unit: "g"), .notStated)
        XCTAssertEqual(outcome("100g\nFat 5", header: "100g", label: "Fat", printed: "5", unit: "g"), .notStated)
        XCTAssertEqual(outcome("per 30 g serving\nFat 5", header: "per 30 g serving", label: "Fat", printed: "5", unit: "g"), .notStated)
    }

    func testUnitAfterADigitIsNeverUnitOnly() {
        XCTAssertEqual(outcome("per100 g\nSodium 400", header: "per100 g", label: "Sodium", printed: "400", unit: "g"), .notStated)
        XCTAssertEqual(outcome("每100 公克\n鈉 400", header: "每100 公克", label: "鈉", printed: "400", unit: "公克"), .notStated)
    }

    func testBracketedUnitAfterADigitIsTheBasisQuantity() {
        XCTAssertEqual(outcome("Per 100 (g)\nFat 5", header: "Per 100 (g)", label: "Fat", printed: "5", unit: "g"), .notStated)
        XCTAssertEqual(outcome("每100（公克）\n脂肪 5", header: "每100（公克）", label: "脂肪", printed: "5", unit: "公克"), .notStated)
        XCTAssertEqual(outcome("Per 100 [g]\nFat 5", header: "Per 100 [g]", label: "Fat", printed: "5", unit: "g"), .notStated)
        XCTAssertEqual(outcome("Per 100 g (g)\nFat 5", header: "Per 100 g (g)", label: "Fat", printed: "5", unit: "g"), .statedInHeader,
                       "a bracketed unit after a word still states the unit")
    }

    func testBareNumberWithoutAUnitIsMissingAndNeverAValue() {
        // Review F9: `.missing` is not an attention item only because the mapping leaves the value
        // unread (a not-read cell, never zero); A2's text mapping enforces that.
        let missing = outcome("Per 100g\nFat 5", header: "Per 100g", label: "Fat", printed: "5", unit: nil)
        XCTAssertEqual(missing, .missing)
        XCTAssertFalse(missing.needsAttention)
        XCTAssertEqual(outcome("Per 100g\nFat 5", header: "Per 100g", label: "Fat", printed: "5", unit: ""), .missing, "an empty unit is no unit")
    }

    func testUnitInsideAWordStatesNothing() {
        XCTAssertEqual(outcome("Per 100g\nOmega 5", header: "Per 100g", label: "Omega", printed: "5", unit: "g"), .notStated)
    }

    func testPrintedUnitsMissingUnitsAndNonValues() {
        XCTAssertEqual(outcome("Per 100g\nFat 5g", header: "Per 100g", label: "Fat", printed: "5g", unit: nil), .printed)
        XCTAssertEqual(outcome("Per 100g\nFat 5g", header: "Per 100g", label: "Fat", printed: "5g", unit: "g"), .printed)
        XCTAssertEqual(outcome("Per 100g\nFat 5g", header: "Per 100g", label: "Fat", printed: "5g", unit: "mg"), .conflict)
        XCTAssertEqual(outcome("Per 100g\nFat 5", header: "Per 100g", label: "Fat", printed: "5", unit: nil), .missing)
        XCTAssertEqual(outcome("(g)\nFat 5", header: "(g)", label: "Fat", printed: "5", unit: "grams"), .notStated, "outside the closed table")
        XCTAssertEqual(outcome("Per 100g\nFat trace", header: "Per 100g", label: "Fat", printed: "trace", unit: "g"), .notAValue)
    }

    func testAHeaderNotLocatedStatesNothing() {
        XCTAssertEqual(outcome("(g)\n(g)\nFat 5", header: "(g)", label: "Fat", printed: "5", unit: "g"), .notStated)
    }

    func testAttentionOutcomes() {
        XCTAssertEqual(Check.Outcome.allCases.filter(\.needsAttention), [.notStated, .conflict])
        XCTAssertEqual(Check.mappingVersion, "pasted-label-ai-text-mapping-v1")
    }
}
