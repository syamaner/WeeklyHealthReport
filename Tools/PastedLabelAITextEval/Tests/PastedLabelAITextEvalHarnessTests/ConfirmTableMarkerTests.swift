import FoodLabelTextAIReading
import FoodLedgerApplication
import Foundation
@testable import PastedLabelAITextEvalCore
@testable import PastedLabelAITextEvalHarness
import XCTest

/// The harness's Confirm table shows a not-declared marker as printed (mapping v3, D30), never as a
/// number, and only where the shipped reader found it. Synthetic text only.
final class ConfirmTableMarkerTests: XCTestCase {
    static let text = "Typical values\tPer 100g\t%RI*\nFat\t5g\t7%\nof which sugars\tTrace\t-\nProtein\t3g\t6%\nSalt\t0.5g\t8%\n"

    static func answer(sugars: String) -> Data {
        Data("""
        {"declined": false, "decline_reasons": [], "language": "en", "serving_size_text": "unknown", "servings_per_pack_text": "unknown",
         "headers": [{"header_id": "h1", "printed_text": "Per 100g", "basis": "per_100g"}, {"header_id": "h2", "printed_text": "%RI*", "basis": "reference_intake"}],
         "rows": [
          {"printed_label": "Fat", "nutrient": "fat", "parent_nutrient": "none", "values": [{"header_id": "h1", "printed_text": "5g"}, {"header_id": "h2", "printed_text": "7%"}]},
          {"printed_label": "of which sugars", "nutrient": "sugars", "parent_nutrient": "none", "values": [{"header_id": "h1", "printed_text": "\(sugars)"}, {"header_id": "h2", "printed_text": "-"}]},
          {"printed_label": "Protein", "nutrient": "protein", "parent_nutrient": "none", "values": [{"header_id": "h1", "printed_text": "3g"}, {"header_id": "h2", "printed_text": "6%"}]},
          {"printed_label": "Salt", "nutrient": "salt", "parent_nutrient": "none", "values": [{"header_id": "h1", "printed_text": "0.5g"}, {"header_id": "h2", "printed_text": "8%"}]}
         ]}
        """.utf8)
    }

    func table(sugars: String) throws -> ConfirmTable {
        let reading = PastedLabelAITextReader().reading(text: Self.text, textSHA256: String(repeating: "ef", count: 32), answer: Self.answer(sugars: sugars))
        XCTAssertEqual(reading.outcome, .reachedConfirm, "\(reading.declineReasons)")
        return try XCTUnwrap(ScoreCommand.confirmTable(reading))
    }

    func testAFoundMarkerIsShownAsPrintedWithNoAttention() throws {
        let table = try table(sugars: "Trace")
        let sugars = table.cells.filter { $0.nutrient == "sugars" }
        XCTAssertEqual(sugars.map(\.decimalText), ["Trace", "-"])
        XCTAssertEqual(sugars.map(\.canonicalUnit), ["", ""])
        XCTAssertEqual(sugars.map(\.comparator), ["=", "="])
        XCTAssertEqual(sugars.map(\.needsAttention), [false, false])
        XCTAssertFalse(table.cells.contains { $0.decimalText == "0" })
        XCTAssertEqual(table.attentionItems, 0)
    }

    func testAMarkerTheTextDoesNotPrintThereIsNotShown() throws {
        // The text prints `Trace` where the model claims a dash: not the same marker, so not read.
        let table = try table(sugars: "-")
        XCTAssertEqual(table.cells.filter { $0.nutrient == "sugars" }.map(\.headerID), ["h2"], "only the %RI dash the text prints")
    }
}
