import Foundation
@testable import PastedLabelAITextEvalCore
import XCTest

/// Scorer v5 (docs/pasted-label-ai-text-v1.md revision 15): two or more %RI columns paired in
/// printed order (D31), and a lone `*` as a class marker (D32). Synthetic fixtures only.
private func v(_ number: String, _ unit: String, outside: Bool? = nil) -> TranscriptionShapes.Value {
    .init(comparator: "=", number: number, unit: unit, outsideTable: outside)
}

final class ScorerV5Tests: XCTestCase {
    typealias R = ReferenceAmountColumnTests
    typealias M = NotDeclaredMarkerTests

    func testTheVersionNamesBothRules() {
        XCTAssertEqual(PastedLabelAITextScorer.version,
                       "pasted-label-ai-text-scorer-v6 (rules of uk-fresh-scorer-v2; RI amount columns and unrecognised rows not printed fields; two or more %RI columns paired in printed order; a lone * a class marker; field counts only printed fields)")
    }

    // MARK: D31: two or more %RI columns

    /// `Per 100g`, then two %RI columns (per 100 g and per serving, say), each percent only.
    static func twoPercent() -> EvalCase {
        R.ukCase(columns: [.init(heading: "Per 100g", basis: "per_100g"), .init(heading: "%RI per 100g", basis: "reference_intake"),
                           .init(heading: "%RI per serving", basis: "reference_intake")],
                 rows: [.init(label: "Fat", nutrient: "fat", values: [v("5", "g"), v("7", "%"), v("2", "%")]),
                        .init(label: "Salt", nutrient: "salt", values: [v("1.5", "g"), v("25", "%"), v("8", "%")])])
    }

    static let threeHeaders = [ConfirmTable.Header(id: "h1", basis: "per_100g"), .init(id: "h2", basis: "reference_intake"),
                               .init(id: "h3", basis: "reference_intake")]
    static let amounts = [R.cell("fat", "h1", "5", "g"), R.cell("salt", "h1", "1.5", "g")]

    func testTwoPercentColumnsArePairedInPrintedOrder() {
        let cells = Self.amounts + [R.cell("fat", "h2", "7", "%"), R.cell("fat", "h3", "2", "%"), R.cell("salt", "h2", "25", "%"),
                                    R.cell("salt", "h3", "8", "%")]
        let result = R.score(Self.twoPercent(), cells, headers: Self.threeHeaders)
        XCTAssertEqual(result.fieldsPrinted, 6)
        XCTAssertEqual(result.fieldsCorrect, 6, "\(result.wrong)")
        XCTAssertEqual(result.wrong, [])
        XCTAssertTrue(result.exactMatch)
    }

    func testACellIsCorrectOnlyInItsPairedColumn() {
        // The app's columns read the other way round: each value is right for the other column.
        let swapped = Self.amounts + [R.cell("fat", "h2", "2", "%"), R.cell("fat", "h3", "7", "%"), R.cell("salt", "h2", "8", "%"),
                                      R.cell("salt", "h3", "25", "%")]
        let result = R.score(Self.twoPercent(), swapped, headers: Self.threeHeaders)
        XCTAssertEqual(result.fieldsCorrect, 2)
        XCTAssertEqual(result.fieldsWrong, 4)
        XCTAssertEqual(result.wrongSilent, 4, "wrong values with no attention are silent")
        XCTAssertTrue(result.silentErrorTable)
    }

    func testUnequalPercentColumnCountsStayAmbiguous() {
        // One app %RI column against the key's two.
        let one = R.score(Self.twoPercent(), Self.amounts + [R.cell("fat", "h2", "7", "%")],
                          headers: Array(Self.threeHeaders.prefix(2)))
        XCTAssertEqual(one.fieldsCorrect, 2)
        XCTAssertEqual(one.wrong, ["fat h2: no single transcribed row and column"])
        // Three app %RI columns against the key's two.
        let headers = Self.threeHeaders + [.init(id: "h4", basis: "reference_intake")]
        let three = R.score(Self.twoPercent(), Self.amounts + [R.cell("fat", "h2", "7", "%"), R.cell("fat", "h3", "2", "%"),
                                                              R.cell("fat", "h4", "2", "%")], headers: headers)
        XCTAssertEqual(three.fieldsCorrect, 2)
        XCTAssertEqual(three.fieldsWrong, 3)
    }

    func testOnlyAppHeadersHoldingPercentagesArePaired() {
        // A reference-intake header the app shows no percentage under is not one of the pair, so
        // the two that hold percentages still pair with the key's two.
        let headers = [ConfirmTable.Header(id: "h1", basis: "per_100g"), .init(id: "h0", basis: "reference_intake")]
            + Array(Self.threeHeaders.dropFirst())
        let cells = Self.amounts + [R.cell("fat", "h2", "7", "%"), R.cell("salt", "h3", "8", "%")]
        let result = R.score(Self.twoPercent(), cells, headers: headers)
        XCTAssertEqual(result.fieldsCorrect, 4, "\(result.wrong)")
    }

    func testOnePercentColumnIsReadAsInV4() {
        // `%RI` (percent) and `RI` (amounts): the one percentage column is R1's, whatever the app's order.
        let headers = [ConfirmTable.Header(id: "h1", basis: "per_100g"), .init(id: "h2", basis: "reference_intake"),
                       .init(id: "h3", basis: "reference_intake")]
        let result = R.score(R.fixture(), R.readable.filter { $0.headerID == "h1" } + [R.cell("fat", "h3", "7", "%")], headers: headers)
        XCTAssertEqual(result.fieldsCorrect, 5, "\(result.wrong)")
        XCTAssertEqual(result.fieldsReferenceAmounts, 4)
    }

    // MARK: D32: a lone `*` is a class marker

    /// `Per 100g` and `%RI`, whose sugars and fibre cells print a lone `*`.
    static func starred() -> EvalCase {
        R.ukCase(columns: [.init(heading: "Per 100g", basis: "per_100g"), .init(heading: "%RI", basis: "reference_intake")],
                 rows: [.init(label: "Fat", nutrient: "fat", values: [v("5", "g"), v("7", "%")]),
                        .init(label: "of which sugars", nutrient: "sugars", values: [v("10", "g"), v("*", "", outside: true)]),
                        .init(label: "Fibre", nutrient: "fibre", values: [v("3", "g"), v("*", "", outside: true)])])
    }

    static let starAmounts = [R.cell("fat", "h1", "5", "g"), R.cell("sugars", "h1", "10", "g"), R.cell("fibre", "h1", "3", "g"),
                              R.cell("fat", "h2", "7", "%")]

    func testAPercentColumnWithStarsStaysAPercentColumn() {
        let result = R.score(Self.starred(), Self.starAmounts + [M.marker("sugars", "h2", "*"), M.marker("fibre", "h2", "*")],
                             headers: M.headers)
        XCTAssertEqual(result.fieldsPrinted, 6, "the stars and the percentage are printed fields")
        XCTAssertEqual(result.fieldsReferenceAmounts, 0, "under v4 the column was an amount column")
        XCTAssertEqual(result.fieldsCorrect, 6, "\(result.wrong)")
        XCTAssertTrue(result.exactMatch)
        XCTAssertTrue(PastedLabelAITextScorer.isPercentColumn(Self.starred().expected, 1))
    }

    func testAStarMatchesOnlyAShownStar() {
        for (shown, unit) in [("0", "%"), ("-", ""), ("Trace", "")] {
            let cell = shown == "0" ? R.cell("sugars", "h2", "0", unit) : M.marker("sugars", "h2", shown)
            let result = R.score(Self.starred(), Self.starAmounts + [cell, M.marker("fibre", "h2", "*")], headers: M.headers)
            XCTAssertEqual(result.fieldsWrong, 1, shown)
            XCTAssertEqual(result.printedNotCorrect, 1, shown)
        }
        // A shown star against the key's number or dash is wrong.
        let number = R.score(Self.starred(), Self.starAmounts.filter { $0.nutrient != "fat" || $0.headerID == "h1" } + [M.marker("fat", "h2", "*")],
                             headers: M.headers)
        XCTAssertEqual(number.wrong.filter { $0.hasPrefix("fat h2") }.count, 1)
        let dash = R.score(M.fixture(), M.numbers + [M.marker("sugars", "h2", "*")], headers: M.headers)
        XCTAssertEqual(dash.wrong, ["sugars h2: read =* "])
    }

    func testAColumnOfStarsAloneIsNotAPercentColumn() {
        // R1 needs at least one percentage, so a column of class markers alone is still not one.
        let stars = R.ukCase(columns: [.init(heading: "Per 100g", basis: "per_100g"), .init(heading: "%RI", basis: "reference_intake")],
                             rows: [.init(label: "Fat", nutrient: "fat", values: [v("5", "g"), v("*", "", outside: true)])])
        XCTAssertFalse(PastedLabelAITextScorer.isPercentColumn(stars.expected, 1))
    }

    func testAStarAttachedToANumberIsNotAMarker() {
        XCTAssertFalse(PastedLabelAITextScorer.isStarMarker(v("7*", "%", outside: true)))
        XCTAssertFalse(PastedLabelAITextScorer.isStarMarker(v("**", "", outside: true)))
        XCTAssertTrue(PastedLabelAITextScorer.isStarMarker(v("*", "", outside: true)))
        XCTAssertTrue(PastedLabelAITextScorer.isStarMarker(v("*", "")))
    }
}
