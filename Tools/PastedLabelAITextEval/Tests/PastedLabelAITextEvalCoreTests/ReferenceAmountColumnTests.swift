import Foundation
@testable import PastedLabelAITextEvalCore
import XCTest

/// Scorer v3 (D28, docs/pasted-label-ai-text-v1.md): a reference-intake column that is not a
/// percentage column under R1 is a reference-intake amount column, and its values are not printed
/// fields. The comparison rules are unchanged. Synthetic fixtures only.
private func v(_ number: String, _ unit: String, _ comparator: String = "=", outside: Bool? = nil) -> TranscriptionShapes.Value {
    .init(comparator: comparator, number: number, unit: unit, outsideTable: outside)
}

final class ReferenceAmountColumnTests: XCTestCase {
    static let sha = String(repeating: "ab", count: 32)

    static func ukCase(columns: [TranscriptionShapes.Column], rows: [TranscriptionShapes.Row]) -> EvalCase {
        try! EvalCase(labelID: "ri-synthetic", set: .ukV1Fresh, tier: "A", copyMethod: "synthetic", textSHA256: sha,
                      expected: .init(panel: "uk_declaration", servingSize: nil, servingsPerPack: nil, columns: columns, rows: rows, notes: []),
                      source: .init(schema: TranscriptionShapes.UKTranscription.schema, sha256: sha))
    }

    /// `Per 100g`, `%RI` (percent only) and `RI` (amounts).
    static func fixture(saltDash: Bool = true) -> EvalCase {
        ukCase(columns: [.init(heading: "Per 100g", basis: "per_100g"), .init(heading: "%RI", basis: "reference_intake"),
                         .init(heading: "RI", basis: "reference_intake")],
               rows: [
                   .init(label: "Energy", nutrient: "energy_kj", values: [v("1046", "kJ"), v("13", "%"), v("8400", "kJ")]),
                   .init(label: "Energy", nutrient: "energy_kcal", values: [v("250", "kcal"), nil, v("2000", "kcal")]),
                   .init(label: "Fat", nutrient: "fat", values: [v("5", "g"), v("7", "%"), v("70", "g")]),
                   .init(label: "Salt", nutrient: "salt", values: [v("0.01", "g", "<"), saltDash ? v("-", "") : nil, v("6", "g")]),
               ])
    }

    static let headers = [ConfirmTable.Header(id: "h1", basis: "per_100g"), .init(id: "h2", basis: "reference_intake")]

    static func cell(_ nutrient: String, _ header: String, _ number: String, _ unit: String, comparator: String = "=") -> ConfirmTable.Cell {
        .init(rowID: nutrient, nutrient: nutrient, printedLabel: "x", headerID: header, comparator: comparator, decimalText: number,
              canonicalUnit: unit, needsAttention: false)
    }

    static func score(_ evalCase: EvalCase, _ cells: [ConfirmTable.Cell], headers: [ConfirmTable.Header] = headers) -> LabelScore {
        PastedLabelAITextScorer.score(evalCase, outcome: "reached_confirm", declineReasons: [], failure: nil,
                                      table: .init(headers: headers, cells: cells, servingSize: nil, servingsPerPack: nil, attentionItems: 0))
    }

    static let readable = [cell("energy_kj", "h1", "1046", "kJ"), cell("energy_kcal", "h1", "250", "kcal"), cell("fat", "h1", "5", "g"),
                           cell("salt", "h1", "0.01", "g", comparator: "<"), cell("fat", "h2", "7", "%"), cell("energy_kcal", "h2", "13", "%")]

    func testTheAmountColumnIsNotPrintedFields() {
        let result = Self.score(Self.fixture(), [])
        XCTAssertEqual(result.fieldsPrinted, 7, "eleven values less the four RI amounts")
        XCTAssertEqual(result.fieldsReferenceAmounts, 4)
        XCTAssertEqual(result.byNutrient["energy_kj"]?.printed, 2)
        XCTAssertEqual(result.byNutrient["salt"]?.printed, 2)
        XCTAssertEqual(result.namedScores["fields_reference_amounts"], 4)
        XCTAssertEqual(result.printedNotCorrect, 7)
    }

    func testEveryKeptFieldReadIsExact() {
        let withDash = Self.score(Self.fixture(), Self.readable)
        XCTAssertEqual(withDash.fieldsCorrect, 6, "the kcal %RI cell is correct through R2, against the kJ row's 13 %")
        XCTAssertEqual(withDash.fieldsWrong, 0)
        XCTAssertEqual(withDash.printedNotCorrect, 1, "the salt dash under %RI was not read")
        XCTAssertFalse(withDash.exactMatch)

        let withoutDash = Self.score(Self.fixture(saltDash: false), Self.readable)
        XCTAssertEqual(withoutDash.fieldsPrinted, 6)
        XCTAssertEqual(withoutDash.printedNotCorrect, 0)
        XCTAssertTrue(withoutDash.exactMatch, "no RI amount needs entering")
        XCTAssertTrue(withoutDash.noEdit)
    }

    func testACellAgainstAnAmountStaysWrong() {
        // R1 still picks the percent column: 70 % against the printed 7 %.
        let r1 = Self.score(Self.fixture(), [Self.cell("fat", "h2", "70", "%")])
        XCTAssertEqual(r1.fieldsWrong, 1)
        XCTAssertEqual(r1.wrong, ["fat h2: read =70 %"])

        // Only an RI amount column: the cell is compared with the amount and is wrong, not "read, but not printed".
        let amountsOnly = Self.ukCase(columns: [.init(heading: "Per 100g", basis: "per_100g"), .init(heading: "RI", basis: "reference_intake")],
                                      rows: [.init(label: "Fat", nutrient: "fat", values: [v("5", "g"), v("70", "g")])])
        let result = Self.score(amountsOnly, [Self.cell("fat", "h2", "70", "%")])
        XCTAssertEqual(result.fieldsPrinted, 1, "the per 100g amount only")
        XCTAssertEqual(result.fieldsReferenceAmounts, 1)
        XCTAssertEqual(result.fieldsWrong, 1)
        XCTAssertEqual(result.wrongSilent, 1)
        XCTAssertEqual(result.wrong, ["fat h2: read =70 %"])
        XCTAssertFalse(result.wrong.contains { $0.contains("not printed") })
    }

    func testAMixedColumnIsExcludedWhole() {
        // A mixed RI column (a percentage and an amount) and an empty RI column: neither is a percent
        // column under R1, so a cell on the reference-intake header has no single column.
        let mixed = Self.ukCase(columns: [.init(heading: "Per 100g", basis: "per_100g"), .init(heading: "RI", basis: "reference_intake"),
                                          .init(heading: "GDA", basis: "reference_intake")],
                                rows: [.init(label: "Energy", nutrient: "energy_kj", values: [v("1046", "kJ"), v("13", "%"), nil]),
                                       .init(label: "Fat", nutrient: "fat", values: [v("5", "g"), v("70", "g"), nil])])
        let result = Self.score(mixed, [Self.cell("energy_kj", "h2", "13", "%")])
        XCTAssertEqual(result.fieldsPrinted, 2)
        XCTAssertEqual(result.fieldsReferenceAmounts, 2)
        XCTAssertEqual(result.fieldsWrong, 1)
        XCTAssertEqual(result.wrong, ["energy_kj h2: no single transcribed row and column"])
    }

    func testAPercentageWithNoUnitMakesTheColumnAnAmountColumn() {
        // `13` with no unit (outside_table) is not a `%` value, so R1 does not hold and the column is excluded whole.
        let unitless = Self.ukCase(columns: [.init(heading: "Per 100g", basis: "per_100g"), .init(heading: "%RI", basis: "reference_intake")],
                                   rows: [.init(label: "Energy", nutrient: "energy_kj", values: [v("1046", "kJ"), v("13", "", outside: true)]),
                                          .init(label: "Fat", nutrient: "fat", values: [v("5", "g"), v("7", "%")])])
        let result = Self.score(unitless, [Self.cell("energy_kj", "h2", "13", "%")])
        XCTAssertEqual(result.fieldsPrinted, 2)
        XCTAssertEqual(result.fieldsReferenceAmounts, 2)
        XCTAssertEqual(result.fieldsWrong, 1, "no unit in a reference-intake column never matches")
    }

    func testATaiwanPercentColumnIsKept() throws {
        let file = Data("""
        {"schema": "reader-v3-fresh-transcription-v1", "label_id": "tw-ri-synthetic",
         "columns": [{"heading": "每100公克", "basis": "per_100g"}, {"heading": "每日參考值百分比", "basis": "reference_intake"}],
         "rows": [
           {"label": "熱量", "nutrient": "energy_kcal", "values": [{"comparator": "=", "number": "500", "unit": "大卡"}, {"comparator": "=", "number": "25", "unit": "%"}]},
           {"label": "脂肪", "nutrient": "fat", "values": [{"comparator": "=", "number": "10", "unit": "公克"}, {"comparator": "=", "number": "17", "unit": "%"}]}
         ],
         "notes": ["synthetic"]}
        """.utf8)
        let evalCase = try EvalCaseConverter.fromTaiwan(file, metadata: .init(set: .taiwanV3Fresh, tier: nil, copyMethod: "synthetic", textSHA256: Self.sha))
        let result = Self.score(evalCase, [Self.cell("fat", "h2", "17", "%")])
        XCTAssertEqual(result.fieldsPrinted, 4)
        XCTAssertEqual(result.fieldsReferenceAmounts, 0)
        XCTAssertEqual(result.fieldsCorrect, 1)
    }

    func testDeclinedAndFailedCountOnlyTheKeptFields() {
        for outcome in ["declined", "failed"] {
            let result = PastedLabelAITextScorer.score(Self.fixture(), outcome: outcome, declineReasons: ["x"], failure: nil, table: nil)
            XCTAssertEqual(result.fieldsPrinted, 7)
            XCTAssertEqual(result.printedNotCorrect, result.fieldsPrinted)
            XCTAssertEqual(result.fieldsReferenceAmounts, 4)
            XCTAssertEqual(result.namedScores["fields_reference_amounts"], 4)
        }
    }

    func testTheCountRoundTripsAsJSON() throws {
        let result = Self.score(Self.fixture(), Self.readable)
        let json = try JSONSerialization.jsonObject(with: try JSONEncoder().encode(result)) as? [String: Any]
        XCTAssertEqual(json?["fields_reference_amounts"] as? Int, 4)
        XCTAssertEqual(try JSONDecoder().decode(LabelScore.self, from: try JSONEncoder().encode(result)), result)
    }
}
