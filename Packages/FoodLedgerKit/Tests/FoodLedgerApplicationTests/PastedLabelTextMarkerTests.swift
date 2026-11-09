import FoodLedgerApplication
import XCTest

/// Not-declared markers in the scan and `pasted-label-text-locate-v3` (docs/pasted-label-ai-text-v1.md
/// 4.3 item 11, revision 14, D30). Synthetic text only.
final class PastedLabelTextMarkerTests: XCTestCase {
    typealias Locator = PastedLabelTextLocator
    typealias T = PastedLabelTextLocatorTests

    func markers(_ text: String) -> [String] { PastedLabelTextScan(text).markers.map(\.text) }

    // MARK: Scan

    func testMarkersStandAloneBetweenBoundaries() {
        XCTAssertEqual(markers("Fat\t-\t2g\nSugars Trace TR tr*\nFibre \u{2013} \u{2014}"), ["-", "Trace", "TR", "tr", "\u{2013}", "\u{2014}"])
        // Never inside a word or a number, never a list dash before a label, never a word that goes on.
        XCTAssertEqual(markers("Semi-skimmed -5g 5-10g Tracer Traces"), [])
        XCTAssertEqual(markers("- of which sugars 5g\n\u{2013} Fibre 2g"), [])
        XCTAssertEqual(markers("Trace elements 2mg"), [])
        // A minus sign and other dashes outside the closed list are not markers.
        XCTAssertEqual(markers("Fat \u{2212} \u{2012}"), [])
        // A marker never changes the value tokens.
        XCTAssertEqual(PastedLabelTextScan("Fat 5g - 2g").tokens.map(\.decimalText), ["5", "2"])
    }

    func testTheMarkerListsAreClosed() {
        XCTAssertEqual(PastedLabelAITextValueGrammar.notDeclaredDashes, ["-", "\u{2013}", "\u{2014}"])
        XCTAssertEqual(PastedLabelAITextValueGrammar.notDeclaredWords, ["trace", "tr"])
        for marker in ["-", "\u{2013}", "\u{2014}", "Trace", "trace", "TRACE", "Tr", "tr"] {
            XCTAssertTrue(PastedLabelAITextValueGrammar.isNotDeclaredMarker(marker), marker)
        }
        for other in ["0", "0g", "nil", "n/a", "\u{2212}", "- ", "(-)", "<0.1g", "Traces"] {
            XCTAssertFalse(PastedLabelAITextValueGrammar.isNotDeclaredMarker(other), other)
        }
        XCTAssertEqual(PastedLabelAITextValueGrammar.notDeclaredMarker("Trace*"), "Trace")
        XCTAssertNil(PastedLabelAITextValueGrammar.notDeclaredMarker("0g"))
    }

    // MARK: Locator v3

    func testAMarkerInAnAmountColumnIsFoundAndKeepsTheRowAligned() {
        let text = "Typical values\tPer 100g\tPer serving\nFat\t5g\t-\nSugars\tTrace\t1.2g\n"
        let result = Locator.locate(text: text, headers: [T.per100, T.perServing],
                                    rows: [T.row("Fat", [("h1", "5g"), ("h2", "-")]), T.row("Sugars", [("h1", "Trace"), ("h2", "1.2g")])])
        XCTAssertEqual(result.values.map(\.status), [.found(T.scalars("5g", in: text)), .found(T.scalars("-", in: text)),
                                                     .found(T.scalars("Trace", in: text)), .found(T.scalars("1.2g", in: text))])
        XCTAssertTrue(result.values.allSatisfy { !$0.needsAttention }, "a marker fills its column, so no fewer-cells attention")
        XCTAssertEqual(Locator.version, "pasted-label-text-locate-v4")
    }

    func testAMarkerInTheReferenceIntakeColumnIsFound() {
        let text = "Typical values\tPer 100g\t%RI\nFat\t5g\t7%\nFibre\t3g\t-\nSugars\tTrace\t-\n"
        let result = Locator.locate(text: text, headers: [T.per100, T.referenceIntake],
                                    rows: [T.row("Fat", [("h1", "5g"), ("h3", "7%")]), T.row("Fibre", [("h1", "3g"), ("h3", "-")]),
                                           T.row("Sugars", [("h1", "Trace"), ("h3", "-")])])
        XCTAssertEqual(result.values.map(\.status), [.found(T.scalars("5g", in: text)), .found(T.scalars("7%", in: text)),
                                                     .found(T.scalars("3g", in: text)), .found(T.scalars("-", in: text)),
                                                     .found(T.scalars("Trace", in: text)), .found(T.scalars("-", in: text, nth: 2))])
        XCTAssertTrue(result.values.allSatisfy { !$0.needsAttention })
    }

    func testAMarkerMatchesOnlyTheSameMarkerInItsOwnColumn() {
        let text = "Typical values\tPer 100g\tPer serving\nFat\t5g\t-\n"
        // The model swaps the columns: neither value is found where it says.
        let swapped = Locator.locate(text: text, headers: [T.per100, T.perServing], rows: [T.row("Fat", [("h1", "-"), ("h2", "5g")])])
        XCTAssertEqual(swapped.values.map(\.status), [.notFound, .notFound])
        // A number where the text prints a dash, and a dash the text does not print.
        let number = Locator.locate(text: text, headers: [T.per100, T.perServing], rows: [T.row("Fat", [("h1", "5g"), ("h2", "0g")])])
        XCTAssertEqual(number.values[1].status, .notFound)
        let printed = "Typical values\tPer 100g\tPer serving\nFat\t5g\t2g\n"
        let claimed = Locator.locate(text: printed, headers: [T.per100, T.perServing], rows: [T.row("Fat", [("h1", "5g"), ("h2", "-")])])
        XCTAssertEqual(claimed.values[1].status, .notFound)
        // Another marker, or another letter case, is not the printed marker.
        for other in ["Trace", "\u{2013}"] {
            let result = Locator.locate(text: text, headers: [T.per100, T.perServing], rows: [T.row("Fat", [("h1", "5g"), ("h2", other)])])
            XCTAssertEqual(result.values[1].status, .notFound, other)
        }
        let cased = Locator.locate(text: "Per 100g\nSugars\tTrace\n", headers: [T.per100], rows: [T.row("Sugars", [("h1", "trace")])])
        XCTAssertEqual(cased.values[0].status, .notFound)
    }

    func testABlockWithoutMarkersIsLocatedAsUnderV2() {
        // Fewer cells than headers with no marker stays block attention.
        let text = "Typical values\tPer 100g\tPer serving\nFat\t5g\n"
        let result = Locator.locate(text: text, headers: [T.per100, T.perServing], rows: [T.row("Fat", [("h1", "5g"), ("h2", "unknown")])])
        XCTAssertTrue(result.values[0].attention.contains(.fewerCellsThanHeaders))
        // A list dash before a row label is not a cell of the row above.
        let listed = "Per 100g\nCarbohydrate 30g\n- of which sugars 5g\n"
        let rows = [T.row("Carbohydrate", [("h1", "30g")]), T.row("of which sugars", [("h1", "5g")])]
        XCTAssertTrue(Locator.locate(text: listed, headers: [T.per100], rows: rows).values.allSatisfy { !$0.needsAttention })
    }
}
