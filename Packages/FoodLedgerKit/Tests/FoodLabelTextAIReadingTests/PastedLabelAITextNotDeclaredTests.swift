import FoodLabelTextAIReading
import FoodLedgerApplication
import Foundation
import XCTest

/// Not-declared markers (docs/pasted-label-ai-text-v1.md revision 14, D30; mapping v3, locator v3),
/// on synthetic texts only: a printed dash, `Trace` or `Tr` that the locator finds at its row and
/// column is not declared. It is never a cell, never zero and never a stored value, and on its own it
/// no longer keeps the table from being ready. A marker the text does not print there stays not read.
final class PastedLabelAITextNotDeclaredTests: XCTestCase {
    let reader = PastedLabelAITextReader()

    static let text = """
    Typical values\tPer 100g\tPer serving (40g)\tRI*
    Energy\t1046kJ / 250kcal\t418kJ / 100kcal\t5%
    Fat\t9.5g\t3.8g\t5%
    of which saturates\t3.2g\t1.3g\t7%
    Carbohydrate\t30g\t12g\t-
    of which sugars\tTrace\tTrace\t-
    Protein\t8.1g\t-\t-
    Salt\t0.75g\t0.30g\t5%
    """

    static let headers = [("h1", "Per 100g", "per_100g"), ("h2", "Per serving (40g)", "per_serving"), ("h3", "RI*", "reference_intake")]

    static func rows(sugars: [(String, String)] = [("h1", "Trace"), ("h2", "Trace"), ("h3", "-")],
                     protein: [(String, String)] = [("h1", "8.1g"), ("h2", "-"), ("h3", "-")],
                     fat: [(String, String)] = [("h1", "9.5g"), ("h2", "3.8g"), ("h3", "5%")]) -> [(String, String, [(String, String)])] {
        [("Energy", "energy_kj", [("h1", "1046kJ"), ("h2", "418kJ")]), ("Energy", "energy_kcal", [("h1", "250kcal"), ("h2", "100kcal"), ("h3", "5%")]),
         ("Fat", "fat", fat), ("of which saturates", "saturates", [("h1", "3.2g"), ("h2", "1.3g"), ("h3", "7%")]),
         ("Carbohydrate", "carbohydrate", [("h1", "30g"), ("h2", "12g"), ("h3", "-")]), ("of which sugars", "sugars", sugars),
         ("Protein", "protein", protein), ("Salt", "salt", [("h1", "0.75g"), ("h2", "0.30g"), ("h3", "5%")])]
    }

    func read(_ text: String = text, rows: [(String, String, [(String, String)])] = rows()) -> PastedLabelAITextReadingResult {
        let answer = PastedLabelAITextReaderTests.answer(serving: "Per serving (40g)", headers: Self.headers, rows: rows)
        return reader.reading(text: text, textSHA256: PastedLabelAITextReaderTests.sha, answer: Data(answer.utf8))
    }

    func value(_ result: PastedLabelAITextReadingResult, _ nutrient: String, _ header: String) -> PastedLabelAITextReadingResult.Value? {
        result.values.first { $0.nutrient == nutrient && $0.headerID == header }
    }

    /// Dash and `Trace`, in product-amount columns and in the %RI column, are found and not declared,
    /// and a table whose only gaps are markers is ready, with no attention item.
    func testMarkersFoundInTheTextAreNotDeclaredAndTheTableIsReady() throws {
        let result = read()
        XCTAssertEqual(result.outcome, .reachedConfirm, "\(result.declineReasons)")
        let candidate = try XCTUnwrap(result.candidate)
        for (nutrient, header) in [("sugars", "h1"), ("sugars", "h2"), ("sugars", "h3"), ("protein", "h2"), ("protein", "h3"), ("carbohydrate", "h3")] {
            let marker = try XCTUnwrap(value(result, nutrient, header), "\(nutrient) \(header)")
            XCTAssertEqual(marker.read, .notRead(.notDeclared), "\(nutrient) \(header)")
            XCTAssertEqual(marker.reasons, [], "\(nutrient) \(header): needs no entry")
            XCTAssertNotNil(marker.locator.range, "\(nutrient) \(header): found where printed")
        }
        XCTAssertEqual(value(result, "sugars", "h1")?.printedText, "Trace", "shown as printed")
        XCTAssertEqual(value(result, "protein", "h2")?.printedText, "-", "shown as printed")
        XCTAssertTrue(candidate.wouldMarkReady, "markers are the only gaps")
        XCTAssertEqual(result.attentionItemCount, 0, "\(result.values.filter(\.needsAttention).map { "\($0.nutrient) \($0.headerID) \($0.reasons)" })")
        XCTAssertTrue(candidate.warnings.contains("value_not_declared: protein h2 '-'"), "\(candidate.warnings)")
        // The product amounts beside the markers are still read and found without attention.
        XCTAssertEqual(value(result, "protein", "h1")?.read, .cell(rowID: "protein"))
        XCTAssertEqual(value(result, "protein", "h1")?.reasons, [])
    }

    /// A marker is never zero and never a stored value: no cell, no conversion and no check holds it.
    func testAMarkerIsNeverZeroAndNeverAStoredValue() throws {
        let result = read()
        let candidate = try XCTUnwrap(result.candidate)
        XCTAssertFalse(candidate.cells.contains { $0.nutrient == "sugars" }, "Trace is never a cell")
        XCTAssertFalse(candidate.cells.contains { $0.nutrient == "protein" && $0.headerID != "h1" }, "the dash is never a cell")
        XCTAssertFalse(candidate.cells.contains { $0.decimalText == "0" || PastedLabelAITextValueGrammar.isNotDeclaredMarker($0.decimalText) })
        XCTAssertFalse(result.conversions.contains { $0.nutrient == "sugars" || $0.operandText.contains("Trace") || $0.operandText == "-" })
        XCTAssertEqual(result.values.filter { $0.read == .notRead(.notDeclared) }.compactMap(\.read.rowID), [], "never a cell row")
    }

    /// `Tr` and the other dashes, in any letter case for the words, are markers too.
    func testTrAndEveryDashAreMarkers() throws {
        for (printed, header) in [("Tr", "h1"), ("TRACE", "h1"), ("\u{2013}", "h2"), ("\u{2014}", "h2")] {
            let text = header == "h1"
                ? Self.text.replacingOccurrences(of: "of which sugars\tTrace\tTrace", with: "of which sugars\t\(printed)\tTrace")
                : Self.text.replacingOccurrences(of: "Protein\t8.1g\t-", with: "Protein\t8.1g\t\(printed)")
            let rows = header == "h1"
                ? Self.rows(sugars: [("h1", printed), ("h2", "Trace"), ("h3", "-")])
                : Self.rows(protein: [("h1", "8.1g"), ("h2", printed), ("h3", "-")])
            let result = read(text, rows: rows)
            let nutrient = header == "h1" ? "sugars" : "protein"
            XCTAssertEqual(value(result, nutrient, header)?.read, .notRead(.notDeclared), printed)
            XCTAssertTrue(result.candidate?.wouldMarkReady ?? false, printed)
        }
    }

    /// A dash the text does not print at that row and column stays a not-read value the user enters.
    func testAMarkerTheTextDoesNotPrintThereStaysNotRead() throws {
        // The text prints 3.8g where the model claims a dash.
        let claimed = read(rows: Self.rows(fat: [("h1", "9.5g"), ("h2", "-"), ("h3", "5%")]))
        XCTAssertEqual(value(claimed, "fat", "h2")?.read, .notRead(.unreadable))
        XCTAssertFalse(claimed.candidate?.wouldMarkReady ?? true, "a left-out amount")
        XCTAssertFalse(claimed.candidate?.cells.contains { $0.nutrient == "fat" && $0.headerID == "h2" } ?? true)
        // The text prints a dash on the protein row, but in the other column from the model's.
        let moved = read(rows: Self.rows(protein: [("h1", "-"), ("h2", "8.1g"), ("h3", "-")]))
        XCTAssertEqual(value(moved, "protein", "h1")?.read, .notRead(.unreadable))
        XCTAssertNotEqual(value(moved, "protein", "h2")?.reasons, [], "the moved value is under attention")
        XCTAssertFalse(moved.candidate?.wouldMarkReady ?? true)
        // A different marker from the one printed is not the same marker.
        let other = read(rows: Self.rows(sugars: [("h1", "-"), ("h2", "Trace"), ("h3", "-")]))
        XCTAssertEqual(value(other, "sugars", "h1")?.read, .notRead(.unreadable))
        XCTAssertFalse(other.candidate?.wouldMarkReady ?? true)
        // A dash in the text that the model reads as a number is not that number.
        let number = read(rows: Self.rows(protein: [("h1", "8.1g"), ("h2", "0g"), ("h3", "-")]))
        XCTAssertEqual(value(number, "protein", "h2")?.locator, .notFound)
        XCTAssertNotEqual(value(number, "protein", "h2")?.reasons, [], "a number where the text prints a dash is attention")
    }

    /// The mapping alone: a marker is not a left-out amount, and `unknown` still is.
    func testTheMappingCountsAMarkerAsNoLeftOutAmount() throws {
        let wire = try XCTUnwrap(PastedLabelAITextWire.decode(Data(PastedLabelAITextReaderTests.answer(
            serving: "Per serving (40g)", headers: Self.headers, rows: Self.rows()).utf8)))
        let mapped = PastedLabelAITextWireMapping.map(wire, text: Self.text, inputSHA256: PastedLabelAITextReaderTests.sha)
        XCTAssertTrue(mapped.candidate.wouldMarkReady)
        XCTAssertEqual(mapped.values.filter { $0.read == .notRead(.notDeclared) }.count, 6)
        XCTAssertEqual(PastedLabelAITextWireMapping.version, "pasted-label-ai-text-mapping-v3")
        let unknown = try XCTUnwrap(PastedLabelAITextWire.decode(Data(PastedLabelAITextReaderTests.answer(
            serving: "Per serving (40g)", headers: Self.headers, rows: Self.rows(protein: [("h1", "8.1g"), ("h2", "unknown"), ("h3", "-")])).utf8)))
        XCTAssertFalse(PastedLabelAITextWireMapping.map(unknown, text: Self.text, inputSHA256: PastedLabelAITextReaderTests.sha).candidate.wouldMarkReady)
    }
}
