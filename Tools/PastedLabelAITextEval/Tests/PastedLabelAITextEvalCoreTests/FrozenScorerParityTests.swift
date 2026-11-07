import Foundation
@testable import PastedLabelAITextEvalCore
import XCTest

/// Parity with the frozen scorer (`UKFreshSet.expected`, `same` and rules R1 to R3 in
/// `Packages/FoodLedgerKit/Tests/FoodLabelTextCaptureTests/UKFreshSet/UKFreshSetProtocol.swift`,
/// and the negative cases of `docs/pasted-nutrition-label-uk-english-v2-p3.md` section 2). The test
/// target cannot be imported, so each expected outcome below is the one the frozen code path gives,
/// copied with the path it follows.
final class FrozenScorerParityTests: XCTestCase {
    static let sha = String(repeating: "ab", count: 32)

    static func v(_ number: String, _ unit: String, _ comparator: String = "=", outside: Bool? = nil) -> TranscriptionShapes.Value {
        .init(comparator: comparator, number: number, unit: unit, outsideTable: outside)
    }

    /// Per 100g, two reference-intake columns (`%RI` percent-only, and an `RI` amount column), and
    /// rows that exercise R1 to R3 and the unrecognised-row rules.
    static var evalCase: EvalCase {
        let columns: [TranscriptionShapes.Column] = [.init(heading: "Per 100g", basis: "per_100g"), .init(heading: "%RI", basis: "reference_intake"),
                                                     .init(heading: "RI", basis: "reference_intake")]
        let rows: [TranscriptionShapes.Row] = [
            .init(label: "Energy", nutrient: "energy_kj", values: [v("1046", "kJ"), v("13", "%"), v("8400", "kJ")]),
            .init(label: "Energy", nutrient: "energy_kcal", values: [v("250", "kcal"), nil, v("2000", "kcal")]),
            .init(label: "Fat (g)", nutrient: "fat", values: [v("5", "", outside: true), v("7", "%"), v("70", "g")]),
            .init(label: "Salt", nutrient: "salt", values: [v("Trace", ""), v("-", ""), v("6", "g")]),
            .init(label: "Polyols", nutrient: "other", values: [v("2", "g"), nil, nil]),
            .init(label: "Polyols", nutrient: "other", values: [v("20", "mg"), nil, nil]),
            .init(label: "Starch (g) (mg)", nutrient: "other", values: [v("3", "", outside: true), nil, nil]),
        ]
        return try! EvalCase(labelID: "parity", set: .ukV1Fresh, tier: "A", copyMethod: "synthetic", textSHA256: sha,
                             expected: .init(panel: "uk_declaration", servingSize: nil, servingsPerPack: nil, columns: columns, rows: rows, notes: []),
                             source: .init(schema: TranscriptionShapes.UKTranscription.schema, sha256: sha))
    }

    static let headers: [ConfirmTable.Header] = [.init(id: "h1", basis: "per_100g"), .init(id: "h2", basis: "reference_intake")]

    static func cell(_ nutrient: String, _ header: String, _ number: String, _ unit: String, label: String = "x", comparator: String = "=") -> ConfirmTable.Cell {
        .init(rowID: nutrient, nutrient: nutrient, printedLabel: label, headerID: header, comparator: comparator, decimalText: number, canonicalUnit: unit,
              needsAttention: false)
    }

    func correct(_ cell: ConfirmTable.Cell, alongside others: [ConfirmTable.Cell] = []) -> Bool {
        let result = PastedLabelAITextScorer.score(Self.evalCase, outcome: "reached_confirm", declineReasons: [], failure: nil,
                                                   table: .init(headers: Self.headers, cells: [cell] + others, servingSize: nil, servingsPerPack: nil,
                                                                attentionItems: 0))
        return result.byNutrient[cell.nutrient]?.correct == 1 && !result.wrong.contains { $0.hasPrefix("\(cell.rowID) \(cell.headerID)") }
    }

    func testRecognisedCellsAndTheExactComparison() {
        // `same`: comparator, number and canonical unit all equal.
        XCTAssertTrue(correct(Self.cell("energy_kj", "h1", "1046", "kJ")))
        XCTAssertFalse(correct(Self.cell("energy_kj", "h1", "1046", "kcal")), "another unit")
        XCTAssertFalse(correct(Self.cell("energy_kj", "h1", "1046", "kJ", comparator: "<")), "another comparator")
        XCTAssertFalse(correct(Self.cell("energy_kj", "h1", "1047", "kJ")), "another number")
        // A class marker matches only a read marker; any number, 0 included, is wrong.
        XCTAssertTrue(correct(Self.cell("salt", "h1", "trace", "")))
        XCTAssertFalse(correct(Self.cell("salt", "h1", "0", "g")))
    }

    func testR1ThePercentColumnAmongReferenceColumns() {
        // Two reference-intake columns; the header matches the one percent-only column (%RI).
        XCTAssertTrue(correct(Self.cell("fat", "h2", "7", "%")))
        XCTAssertFalse(correct(Self.cell("fat", "h2", "70", "g")), "the reader's reference cell holds an amount")
    }

    func testR2TheEnergyPercentagePrintedOnce() {
        // The kcal row prints nothing under %RI; the kJ row's 13% is compared.
        XCTAssertTrue(correct(Self.cell("energy_kcal", "h2", "13", "%")))
        XCTAssertFalse(correct(Self.cell("energy_kcal", "h2", "12", "%")), "the partner holds a different percentage")
        XCTAssertFalse(correct(Self.cell("energy_kcal", "h2", "13", "%"), alongside: [Self.cell("energy_kj", "h2", "13", "%")]),
                       "the reader bound the partner cell too")
        // A dash on the own row with no energy partner: not an energy row, so the dash is compared.
        XCTAssertFalse(correct(Self.cell("salt", "h2", "6", "%")))
    }

    func testR2PositionFollowsTheSameCondition() {
        // A correct R2 cell counts against the partner's printed field, so nothing is double counted.
        let position = PastedLabelAITextScorer.position(Self.evalCase, table: .init(headers: Self.headers, cells: [Self.cell("energy_kcal", "h2", "13", "%")],
                                                                                     servingSize: nil, servingsPerPack: nil, attentionItems: 0),
                                                        cell: Self.cell("energy_kcal", "h2", "13", "%"), schema: .uk)
        XCTAssertEqual(position, [0, 1])
    }

    func testR3AUnitPrintedOnlyInTheRowLabel() {
        XCTAssertTrue(correct(Self.cell("fat", "h1", "5", "g")))
        XCTAssertFalse(correct(Self.cell("fat", "h1", "5", "mg")), "a read unit other than the named one")
    }

    func testUnrecognisedCellsNamesOnlyAndDisambiguationByUnit() {
        // Two `Polyols` rows: the one whose value in the column has the cell's unit.
        XCTAssertTrue(correct(Self.cell("unrecognised", "h1", "2", "g", label: "Polyols")))
        XCTAssertTrue(correct(Self.cell("unrecognised", "h1", "20", "mg", label: "Polyols")))
        XCTAssertFalse(correct(Self.cell("unrecognised", "h1", "2", "µg", label: "Polyols")), "no row has that unit: ambiguous")
        // The cell's own label names a unit that is not the cell's: ambiguous (namesOnly).
        XCTAssertFalse(correct(Self.cell("unrecognised", "h1", "2", "g", label: "Polyols (mg)")))
        // A transcribed label naming two units agrees with no single-unit cell: the row is dropped.
        XCTAssertFalse(correct(Self.cell("unrecognised", "h1", "3", "g", label: "Starch")))
        XCTAssertEqual(PastedLabelAITextScorer.expected(Self.evalCase, table: .init(headers: Self.headers, cells: [], servingSize: nil,
                                                                                     servingsPerPack: nil, attentionItems: 0),
                                                        cell: Self.cell("unrecognised", "h1", "3", "g", label: "Starch"), schema: .uk), .ambiguous)
    }
}
