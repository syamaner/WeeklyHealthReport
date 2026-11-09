import Foundation
@testable import PastedLabelAITextEvalCore
import XCTest

/// Scorer v6 (D37, docs/pasted-label-ai-text-v1.md revision 23): the field counts agree with the
/// printed-field exclusions of v3 and v4. A correct cell that is not a printed field (an
/// unrecognised row, a reference-intake amount column, or a second correct cell for a field
/// already read) is counted in `fieldsCorrectNotPrinted` and left out of `fieldsShown` and
/// `fieldsCorrect`, so recall never exceeds 1. Wrong cells, silent errors, exact match and no
/// edit are as in v5. Synthetic fixtures only.
final class ScorerV6Tests: XCTestCase {
    typealias R = ReferenceAmountColumnTests

    static func unrecognised(_ label: String, _ number: String, _ unit: String, attention: Bool = false) -> ConfirmTable.Cell {
        .init(rowID: "u-\(label)", nutrient: "unrecognised", printedLabel: label, headerID: "h1", comparator: "=", decimalText: number,
              canonicalUnit: unit, needsAttention: attention)
    }

    func testAnUnrecognisedRowReadCorrectlyIsNotACorrectField() {
        let result = R.score(UnrecognisedRowTests.fixture(), [R.cell("fat", "h1", "5", "g"), Self.unrecognised("Vitamin C", "12", "mg")],
                             headers: UnrecognisedRowTests.headers)
        XCTAssertEqual(result.wrong, [])
        XCTAssertEqual(result.fieldsPrinted, 1)
        XCTAssertEqual(result.fieldsCorrect, 1, "only fat is a printed field")
        XCTAssertEqual(result.fieldsCorrectNotPrinted, 1)
        XCTAssertEqual(result.fieldsShown, 1)
        XCTAssertEqual(result.fieldF1, 1)
        XCTAssertEqual(result.byNutrient["unrecognised"]?.correct ?? 0, 0)
        XCTAssertEqual(result.byNutrient["unrecognised"]?.shown ?? 0, 0)
        XCTAssertTrue(result.exactMatch)
        XCTAssertTrue(result.noEdit)
    }

    func testRecallNeverExceedsOne() {
        // Up to v5 this table counted 3 correct against 1 printed field.
        let result = R.score(UnrecognisedRowTests.fixture(), [R.cell("fat", "h1", "5", "g"), Self.unrecognised("Vitamin C", "12", "mg"),
                                                              Self.unrecognised("Calcium", "120", "mg")],
                             headers: UnrecognisedRowTests.headers)
        XCTAssertLessThanOrEqual(result.fieldsCorrect, result.fieldsPrinted)
        XCTAssertLessThanOrEqual(result.fieldsCorrect, result.fieldsShown)
        XCTAssertEqual(result.fieldsCorrectNotPrinted, 2)
        XCTAssertEqual(result.fieldsShown + result.fieldsCorrectNotPrinted, 3, "every shown cell is accounted for")
    }

    func testAWrongUnrecognisedCellStaysShownAndWrong() {
        let result = R.score(UnrecognisedRowTests.fixture(), [R.cell("fat", "h1", "5", "g"), Self.unrecognised("Vitamin C", "13", "mg")],
                             headers: UnrecognisedRowTests.headers)
        XCTAssertEqual(result.fieldsWrong, 1)
        XCTAssertEqual(result.wrongSilent, 1)
        XCTAssertTrue(result.silentErrorTable, "silent-error scoring is unchanged")
        XCTAssertEqual(result.fieldsShown, 2, "a wrong cell always counts against precision")
        XCTAssertEqual(result.fieldsCorrect, 1)
        XCTAssertEqual(result.byNutrient["unrecognised"]?.shown, 1)
        XCTAssertEqual(result.byNutrient["unrecognised"]?.wrong, 1)
        XCTAssertFalse(result.exactMatch)
    }

    func testASecondCorrectCellForTheSameFieldCountsOnce() {
        let fat = R.cell("fat", "h1", "5", "g")
        let result = R.score(UnrecognisedRowTests.fixture(), [fat, fat], headers: UnrecognisedRowTests.headers)
        XCTAssertEqual(result.fieldsCorrect, 1)
        XCTAssertEqual(result.fieldsCorrectNotPrinted, 1)
        XCTAssertEqual(result.byNutrient["fat"]?.correct, 1)
        XCTAssertEqual(result.byNutrient["fat"]?.printed, 1)
    }

    func testTheNewCountIsANamedScoreAndRoundTrips() throws {
        let result = R.score(UnrecognisedRowTests.fixture(), [R.cell("fat", "h1", "5", "g"), Self.unrecognised("Vitamin C", "12", "mg")],
                             headers: UnrecognisedRowTests.headers)
        XCTAssertEqual(result.namedScores["fields_correct_not_printed"], 1)
        XCTAssertEqual(result.namedScores["fields_correct"], 1)
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(result)) as? [String: Any]
        XCTAssertEqual(json?["fields_correct_not_printed"] as? Int, 1)
        XCTAssertEqual(try JSONDecoder().decode(LabelScore.self, from: JSONEncoder().encode(result)), result)
    }

    func testAnEndedLabelCountsNothingShown() {
        let result = PastedLabelAITextScorer.score(UnrecognisedRowTests.fixture(), outcome: "declined", declineReasons: ["model:x"], failure: nil, table: nil)
        XCTAssertEqual(result.fieldsCorrectNotPrinted, 0)
        XCTAssertEqual(result.fieldsShown, 0)
    }

    func testTheVersionNamesTheChange() {
        XCTAssertTrue(PastedLabelAITextScorer.version.hasPrefix("pasted-label-ai-text-scorer-v6 "))
        XCTAssertTrue(PastedLabelAITextScorer.version.hasSuffix("; field counts only printed fields)"))
    }
}
