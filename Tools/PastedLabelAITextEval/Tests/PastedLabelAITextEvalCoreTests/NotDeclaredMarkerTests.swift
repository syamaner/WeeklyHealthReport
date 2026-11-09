import Foundation
@testable import PastedLabelAITextEvalCore
import XCTest

/// Not-declared markers at Confirm (D30, docs/pasted-label-ai-text-v1.md): from mapping v3 the app
/// shows a dash, `Trace` or `Tr` that the text prints at its row and column as not declared, and the
/// harness passes it as a cell holding the printed marker. `pasted-label-ai-text-scorer-v4` already
/// compares a transcribed class marker only with a shown marker (`same`), so no scorer change is
/// needed: a marker against the key's marker is correct, while a marker against a number and a
/// number against a marker stay wrong. Synthetic fixtures only.
private func v(_ number: String, _ unit: String) -> TranscriptionShapes.Value {
    .init(comparator: "=", number: number, unit: unit, outsideTable: nil)
}

final class NotDeclaredMarkerTests: XCTestCase {
    typealias R = ReferenceAmountColumnTests

    /// `Per 100g` and `%RI`: markers in a product-amount column and in the %RI column.
    static func fixture() -> EvalCase {
        R.ukCase(columns: [.init(heading: "Per 100g", basis: "per_100g"), .init(heading: "%RI", basis: "reference_intake")],
                 rows: [.init(label: "Fat", nutrient: "fat", values: [v("5", "g"), v("7", "%")]),
                        .init(label: "of which sugars", nutrient: "sugars", values: [v("Trace", ""), v("-", "")]),
                        .init(label: "Fibre", nutrient: "fibre", values: [v("-", ""), v("-", "")]),
                        .init(label: "Protein", nutrient: "protein", values: [v("3", "g"), v("6", "%")])])
    }

    static let headers = [ConfirmTable.Header(id: "h1", basis: "per_100g"), .init(id: "h2", basis: "reference_intake")]
    static let numbers = [R.cell("fat", "h1", "5", "g"), R.cell("fat", "h2", "7", "%"), R.cell("protein", "h1", "3", "g"), R.cell("protein", "h2", "6", "%")]

    /// A shown marker, as the harness builds it: the printed marker, `=`, no unit.
    static func marker(_ nutrient: String, _ header: String, _ printed: String, attention: Bool = false) -> ConfirmTable.Cell {
        .init(rowID: nutrient, nutrient: nutrient, printedLabel: "x", headerID: header, comparator: "=", decimalText: printed,
              canonicalUnit: "", needsAttention: attention)
    }

    static let markers = [marker("sugars", "h1", "Trace"), marker("sugars", "h2", "-"), marker("fibre", "h1", "-"), marker("fibre", "h2", "-")]

    func score(_ cells: [ConfirmTable.Cell]) -> LabelScore { R.score(Self.fixture(), cells, headers: Self.headers) }

    func testMarkersAgainstTheKeysMarkersAreCorrectAndNeedNoEdit() {
        let result = score(Self.numbers + Self.markers)
        XCTAssertEqual(result.fieldsPrinted, 8, "markers are printed fields")
        XCTAssertEqual(result.fieldsCorrect, 8)
        XCTAssertEqual(result.fieldsWrong, 0)
        XCTAssertEqual(result.printedNotCorrect, 0)
        XCTAssertTrue(result.exactMatch)
        XCTAssertTrue(result.noEdit)
        XCTAssertFalse(result.silentErrorTable)
        XCTAssertEqual(result.byNutrient["sugars"]?.correct, 2)
    }

    func testMarkersNotShownStillNeedAnEdit() {
        let result = score(Self.numbers)
        XCTAssertEqual(result.printedNotCorrect, 4)
        XCTAssertFalse(result.noEdit)
        XCTAssertFalse(result.silentErrorTable)
    }

    func testAMarkerWhereTheKeyHasANumberIsWrong() {
        let result = score([R.cell("fat", "h2", "7", "%"), Self.marker("fat", "h1", "-")] + Array(Self.numbers.dropFirst(2)) + Self.markers)
        XCTAssertEqual(result.fieldsWrong, 1)
        XCTAssertEqual(result.wrong, ["fat h1: read =- "])
        XCTAssertEqual(result.wrongSilent, 1, "an unflagged marker over a printed number is a silent error")
        XCTAssertTrue(result.silentErrorTable)
        XCTAssertFalse(result.noEdit)
        let flagged = score([R.cell("fat", "h2", "7", "%"), Self.marker("fat", "h1", "-", attention: true)] + Array(Self.numbers.dropFirst(2)))
        XCTAssertEqual(flagged.wrongFlagged, 1)
    }

    func testANumberWhereTheKeyHasAMarkerIsWrong() {
        for (number, unit) in [("0", "g"), ("0", ""), ("0.1", "g")] {
            let cells = Self.numbers + [R.cell("sugars", "h1", number, unit)] + Array(Self.markers.dropFirst())
            let result = score(cells)
            XCTAssertEqual(result.fieldsWrong, 1, number + unit)
            XCTAssertEqual(result.printedNotCorrect, 1, number + unit)
            XCTAssertFalse(result.noEdit, number + unit)
        }
    }

    /// The frozen rule's marker class is unchanged: any marker matches any transcribed marker.
    func testTheMarkerClassIsTheFrozenOne() {
        let result = score(Self.numbers + [Self.marker("sugars", "h1", "Tr"), Self.marker("sugars", "h2", "\u{2013}")] + Array(Self.markers.dropFirst(2)))
        XCTAssertEqual(result.fieldsCorrect, 8)
        XCTAssertEqual(PastedLabelAITextScorer.version.hasPrefix("pasted-label-ai-text-scorer-v5 "), true, "no scorer change for D30; v5 adds D31 and D32")
    }
}
