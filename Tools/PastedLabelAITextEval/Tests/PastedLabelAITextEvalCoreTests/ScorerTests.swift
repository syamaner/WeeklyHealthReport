import Foundation
@testable import PastedLabelAITextEvalCore
import XCTest

/// `pasted-label-ai-text-scorer-v1` (docs/pasted-label-ai-text-v1.md 5.2.1 and 5.3): the frozen
/// scorer's exact comparison, and the per-label counts, on synthetic tables.
final class ScorerTests: XCTestCase {
    static var ukCase: EvalCase {
        try! EvalCaseConverter.convert(EvalCaseConverterTests.uk, metadata: .init(set: .ukV1Fresh, tier: "A", copyMethod: "m",
                                                                                   textSHA256: String(repeating: "ab", count: 32)))
    }

    // The UK fixture: Per 100g (energy_kj 1046 kJ, energy_kcal 250 kcal, salt <0.01 g), %RI (energy_kcal 13%),
    // and an unheaded third column (salt Trace).
    static let headers = [ConfirmTable.Header(id: "h1", basis: "per_100g"), .init(id: "h2", basis: "reference_intake")]

    static func cell(_ nutrient: String, _ header: String, _ comparator: String, _ number: String, _ unit: String, attention: Bool = false,
                     label: String = "x") -> ConfirmTable.Cell {
        .init(rowID: nutrient, nutrient: nutrient, printedLabel: label, headerID: header, comparator: comparator, decimalText: number,
              canonicalUnit: unit, needsAttention: attention)
    }

    func score(_ cells: [ConfirmTable.Cell], attention: Int = 0) -> LabelScore {
        PastedLabelAITextScorer.score(Self.ukCase, outcome: "reached_confirm", declineReasons: [], failure: nil,
                                      table: ConfirmTable(headers: Self.headers, cells: cells, servingSize: nil, servingsPerPack: nil, attentionItems: attention))
    }

    func testAllCorrectButOneFieldNotRead() {
        let result = score([Self.cell("energy_kj", "h1", "=", "1046", "kJ"), Self.cell("energy_kcal", "h1", "=", "250", "kcal"),
                            Self.cell("salt", "h1", "<", "0.01", "g"), Self.cell("energy_kcal", "h2", "=", "13", "%")])
        XCTAssertEqual(result.fieldsPrinted, 5, "four values and the Trace marker")
        XCTAssertEqual(result.fieldsShown, 4)
        XCTAssertEqual(result.fieldsCorrect, 4)
        XCTAssertEqual(result.fieldsWrong, 0)
        XCTAssertEqual(result.printedNotCorrect, 1)
        XCTAssertFalse(result.exactMatch, "the Trace field was not read")
        XCTAssertFalse(result.noEdit)
        XCTAssertFalse(result.silentErrorTable)
        XCTAssertEqual(result.fieldF1, 2 * 1 * 0.8 / 1.8, accuracy: 1e-12)
    }

    func testWrongValuesFlaggedAndSilent() {
        let result = score([Self.cell("energy_kj", "h1", "=", "1046", "kJ"),
                            Self.cell("energy_kcal", "h1", "=", "25", "kcal", attention: true),
                            Self.cell("salt", "h1", "=", "0.01", "g"),
                            Self.cell("energy_kcal", "h2", "=", "13", "g")], attention: 1)
        XCTAssertEqual(result.fieldsCorrect, 1)
        XCTAssertEqual(result.fieldsWrong, 3)
        XCTAssertEqual(result.wrongFlagged, 1)
        XCTAssertEqual(result.wrongSilent, 2, "a lost bound and a wrong unit carry no attention")
        XCTAssertTrue(result.silentErrorTable)
        XCTAssertEqual(result.byNutrient["energy_kcal"]?.wrong, 2)
        XCTAssertEqual(result.namedScores["silent_error_table"], 1)
    }

    func testAValueNotPrintedOrInAnUnknownColumnIsWrong() {
        let result = score([Self.cell("fibre", "h1", "=", "3", "g"), Self.cell("salt", "h9", "<", "0.01", "g")])
        XCTAssertEqual(result.fieldsWrong, 2)
        XCTAssertEqual(result.wrong.count, 2)
    }

    func testCommaRules() {
        let value = TranscriptionShapes.Value(comparator: "=", number: "0,5", unit: "g", outsideTable: true)
        let read = Self.cell("salt", "h1", "=", "0.5", "g")
        XCTAssertTrue(PastedLabelAITextScorer.same(read, as: value, printedLabel: "Salt", inReferenceColumn: false, schema: .uk))
        let thousands = TranscriptionShapes.Value(comparator: "=", number: "1,046", unit: "kJ", outsideTable: true)
        XCTAssertFalse(PastedLabelAITextScorer.same(Self.cell("energy_kj", "h1", "=", "1046", "kJ"), as: thousands, printedLabel: "Energy",
                                                    inReferenceColumn: false, schema: .uk), "the frozen rule: a three-digit comma is unparsable")
        // R3: a unit printed only in the row label, in an amount column.
        let bare = TranscriptionShapes.Value(comparator: "=", number: "5", unit: "", outsideTable: true)
        XCTAssertTrue(PastedLabelAITextScorer.same(Self.cell("fat", "h1", "=", "5", "g"), as: bare, printedLabel: "Fat (g)", inReferenceColumn: false, schema: .uk))
        XCTAssertFalse(PastedLabelAITextScorer.same(Self.cell("fat", "h1", "=", "5", "g"), as: bare, printedLabel: "Fat (g)", inReferenceColumn: true, schema: .uk))
    }

    func testDeclinedAndFailedLabelsScoreNothing() {
        for outcome in ["declined", "failed"] {
            let result = PastedLabelAITextScorer.score(Self.ukCase, outcome: outcome, declineReasons: ["x"], failure: nil, table: nil)
            XCTAssertEqual(result.fieldsShown, 0)
            XCTAssertEqual(result.printedNotCorrect, 5)
            XCTAssertEqual(result.fieldF1, 0)
            XCTAssertFalse(result.exactMatch)
        }
    }
}
