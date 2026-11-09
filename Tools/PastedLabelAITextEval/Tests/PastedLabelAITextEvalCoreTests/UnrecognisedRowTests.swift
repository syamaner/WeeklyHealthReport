import Foundation
@testable import PastedLabelAITextEvalCore
import XCTest

/// Scorer v4 (D29, docs/pasted-label-ai-text-v1.md): values on a row the transcription records as
/// nutrient `other` are not printed fields, because the app keeps such a row as unrecognised and
/// never logs it. A value in a reference-intake amount column is counted under D28 first. Every
/// cell shown at Confirm is still scored. Synthetic fixtures only.
private func v(_ number: String, _ unit: String) -> TranscriptionShapes.Value {
    .init(comparator: "=", number: number, unit: unit, outsideTable: nil)
}

final class UnrecognisedRowTests: XCTestCase {
    /// `Per 100g` and `RI` (amounts); fat, and two rows outside the app's nutrients.
    static func fixture() -> EvalCase {
        ReferenceAmountColumnTests.ukCase(
            columns: [.init(heading: "Per 100g", basis: "per_100g"), .init(heading: "RI", basis: "reference_intake")],
            rows: [
                .init(label: "Fat", nutrient: "fat", values: [v("5", "g"), v("70", "g")]),
                .init(label: "Vitamin C", nutrient: "other", values: [v("12", "mg"), v("80", "mg")]),
                .init(label: "Calcium", nutrient: "other", values: [v("120", "mg"), nil]),
            ])
    }

    static let headers = [ConfirmTable.Header(id: "h1", basis: "per_100g")]

    func testUnrecognisedRowsAreNotPrintedFields() {
        let result = ReferenceAmountColumnTests.score(Self.fixture(), [], headers: Self.headers)
        XCTAssertEqual(result.fieldsPrinted, 1, "five values less two RI amounts and two unrecognised-row values")
        XCTAssertEqual(result.fieldsReferenceAmounts, 2, "the Vitamin C RI amount is counted under D28 first")
        XCTAssertEqual(result.fieldsUnrecognisedRows, 2)
        XCTAssertEqual(result.namedScores["fields_unrecognised_rows"], 2)
        XCTAssertNil(result.byNutrient["other"])
        XCTAssertEqual(result.printedNotCorrect, 1)
    }

    func testATableWithItsProductAmountsReadIsExactAndNoEdit() {
        let result = ReferenceAmountColumnTests.score(Self.fixture(), [ReferenceAmountColumnTests.cell("fat", "h1", "5", "g")],
                                                      headers: Self.headers)
        XCTAssertEqual(result.fieldsCorrect, 1)
        XCTAssertEqual(result.printedNotCorrect, 0)
        XCTAssertTrue(result.exactMatch, "no unrecognised row needs entering")
        XCTAssertTrue(result.noEdit)
    }

    func testAShownCellIsStillScored() {
        let wrongFat = ReferenceAmountColumnTests.cell("fat", "h1", "50", "g")
        let result = ReferenceAmountColumnTests.score(Self.fixture(), [wrongFat], headers: Self.headers)
        XCTAssertEqual(result.fieldsWrong, 1)
        XCTAssertEqual(result.wrongSilent, 1)
        XCTAssertTrue(result.silentErrorTable, "silent-error scoring is unchanged")
        XCTAssertFalse(result.exactMatch)
    }

    func testDeclinedCountsOnlyTheKeptFields() {
        let result = PastedLabelAITextScorer.score(Self.fixture(), outcome: "declined", declineReasons: ["model:x"], failure: nil, table: nil)
        XCTAssertEqual(result.fieldsPrinted, 1)
        XCTAssertEqual(result.printedNotCorrect, 1)
        XCTAssertEqual(result.fieldsUnrecognisedRows, 2)
    }

    func testTheCountRoundTripsInJSON() throws {
        let result = ReferenceAmountColumnTests.score(Self.fixture(), [], headers: Self.headers)
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(result)) as? [String: Any]
        XCTAssertEqual(json?["fields_unrecognised_rows"] as? Int, 2)
        XCTAssertEqual(try JSONDecoder().decode(LabelScore.self, from: JSONEncoder().encode(result)), result)
    }
}
