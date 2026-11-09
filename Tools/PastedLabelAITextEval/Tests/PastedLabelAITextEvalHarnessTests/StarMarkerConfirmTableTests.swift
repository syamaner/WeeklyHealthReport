import FoodLabelTextAIReading
import FoodLedgerApplication
import Foundation
@testable import PastedLabelAITextEvalCore
@testable import PastedLabelAITextEvalHarness
import XCTest

/// The harness's Confirm table shows a lone `*` in a %RI column as printed (mapping v4, D32), and the
/// two-basis header decline reaches the score (D33). Synthetic text only.
final class StarMarkerConfirmTableTests: XCTestCase {
    static func answer(header: String = "Per 100g", sugars: (String, String)) -> Data {
        Data("""
        {"declined": false, "decline_reasons": [], "language": "en", "serving_size_text": "unknown", "servings_per_pack_text": "unknown",
         "headers": [{"header_id": "h1", "printed_text": "\(header)", "basis": "per_100g"}, {"header_id": "h2", "printed_text": "%RI", "basis": "reference_intake"}],
         "rows": [
          {"printed_label": "Fat", "nutrient": "fat", "parent_nutrient": "none", "values": [{"header_id": "h1", "printed_text": "5g"}, {"header_id": "h2", "printed_text": "7%"}]},
          {"printed_label": "of which sugars", "nutrient": "sugars", "parent_nutrient": "none", "values": [{"header_id": "h1", "printed_text": "\(sugars.0)"}, {"header_id": "h2", "printed_text": "\(sugars.1)"}]},
          {"printed_label": "Protein", "nutrient": "protein", "parent_nutrient": "none", "values": [{"header_id": "h1", "printed_text": "3g"}, {"header_id": "h2", "printed_text": "6%"}]},
          {"printed_label": "Salt", "nutrient": "salt", "parent_nutrient": "none", "values": [{"header_id": "h1", "printed_text": "0.5g"}, {"header_id": "h2", "printed_text": "8%"}]}
         ]}
        """.utf8)
    }

    static func text(header: String = "Per 100g", sugars: String) -> String {
        "Typical values\t\(header)\t%RI\nFat\t5g\t7%\nof which sugars\t\(sugars)\nProtein\t3g\t6%\nSalt\t0.5g\t8%\n"
    }

    static func reading(header: String = "Per 100g", printed: String, sugars: (String, String), answerHeader: String? = nil) -> PastedLabelAITextReadingResult {
        PastedLabelAITextReader().reading(text: text(header: header, sugars: printed), textSHA256: String(repeating: "ef", count: 32),
                                          answer: answer(header: answerHeader ?? header, sugars: sugars))
    }

    func testAFoundStarInTheReferenceIntakeColumnIsShownAsPrinted() throws {
        let reading = Self.reading(printed: "10g\t*", sugars: ("10g", "*"))
        XCTAssertEqual(reading.outcome, .reachedConfirm, "\(reading.declineReasons)")
        let table = try XCTUnwrap(ScoreCommand.confirmTable(reading))
        let star = try XCTUnwrap(table.cells.first { $0.nutrient == "sugars" && $0.headerID == "h2" })
        XCTAssertEqual([star.comparator, star.decimalText, star.canonicalUnit], ["=", "*", ""])
        XCTAssertFalse(star.needsAttention)
        XCTAssertEqual(table.attentionItems, 0)
        XCTAssertFalse(table.cells.contains { $0.decimalText == "0" })
    }

    func testAStarInAProductColumnIsNeverShown() throws {
        let reading = Self.reading(printed: "*\t*", sugars: ("*", "*"))
        let table = try XCTUnwrap(ScoreCommand.confirmTable(reading))
        XCTAssertFalse(table.cells.contains { $0.decimalText == "*" }, "\(table.cells)")
        XCTAssertEqual(reading.values.first { $0.nutrient == "sugars" && $0.headerID == "h1" }?.read, .notRead(.unreadable))
    }

    func testAStarFootnoteOnANumberIsNeverAMarker() throws {
        let footnoted = try XCTUnwrap(ScoreCommand.confirmTable(Self.reading(printed: "10g\t7%*", sugars: ("10g", "7%*"))))
        XCTAssertFalse(footnoted.cells.contains { $0.decimalText == "*" || $0.decimalText == "7%*" })
        let table = try XCTUnwrap(ScoreCommand.confirmTable(Self.reading(printed: "10g\t7%*", sugars: ("10g", "7%"))))
        let cell = try XCTUnwrap(table.cells.first { $0.nutrient == "sugars" && $0.headerID == "h2" })
        XCTAssertEqual([cell.decimalText, cell.canonicalUnit], ["7", "%"])
    }

    func testATwoBasisHeaderDeclinesWithItsReason() {
        for (printed, claimed) in [("per 100g/ml", "per 100g/ml"), ("per 100g/ml", "per 100g"), ("per 100g / 100ml", "per 100g / 100ml")] {
            let reading = Self.reading(header: printed, printed: "10g\t3%", sugars: ("10g", "3%"), answerHeader: claimed)
            XCTAssertEqual(reading.outcome, .declined, claimed)
            XCTAssertEqual(reading.declineReasons, ["vocabulary:two_basis_header"], claimed)
        }
        let single = Self.reading(printed: "10g\t3%", sugars: ("10g", "3%"))
        XCTAssertEqual(single.outcome, .reachedConfirm, "\(single.declineReasons)")
    }
}
