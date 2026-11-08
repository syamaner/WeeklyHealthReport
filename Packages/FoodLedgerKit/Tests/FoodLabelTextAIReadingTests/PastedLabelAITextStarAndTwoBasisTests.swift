import FoodLabelTextAIReading
import FoodLedgerApplication
import Foundation
import XCTest

/// Revision 15 on synthetic texts only: a lone `*` in a %RI column is not declared (D32, mapping v4),
/// and a header naming two bases declines the reply (D33, vocabulary v2).
final class PastedLabelAITextStarAndTwoBasisTests: XCTestCase {
    let reader = PastedLabelAITextReader()

    static let text = """
    Typical values\tPer 100g\t%RI
    Energy\t1046kJ / 250kcal\t13%
    Fat\t9.5g\t14%
    of which saturates\t3.2g\t*
    Carbohydrate\t30g\t12%*
    of which sugars\t5g\t*
    Protein\t8.1g\t16%
    Salt\t0.75g\t13%

    * Reference value not set
    """

    static let headers = [("h1", "Per 100g", "per_100g"), ("h3", "%RI", "reference_intake")]

    static func rows(saturates: [(String, String)] = [("h1", "3.2g"), ("h3", "*")],
                     carbohydrate: [(String, String)] = [("h1", "30g"), ("h3", "12%")]) -> [(String, String, [(String, String)])] {
        [("Energy", "energy_kj", [("h1", "1046kJ")]), ("Energy", "energy_kcal", [("h1", "250kcal"), ("h3", "13%")]),
         ("Fat", "fat", [("h1", "9.5g"), ("h3", "14%")]), ("of which saturates", "saturates", saturates),
         ("Carbohydrate", "carbohydrate", carbohydrate), ("of which sugars", "sugars", [("h1", "5g"), ("h3", "*")]),
         ("Protein", "protein", [("h1", "8.1g"), ("h3", "16%")]), ("Salt", "salt", [("h1", "0.75g"), ("h3", "13%")])]
    }

    func read(_ text: String = text, headers: [(String, String, String)] = headers,
              rows: [(String, String, [(String, String)])] = rows()) -> PastedLabelAITextReadingResult {
        let answer = PastedLabelAITextReaderTests.answer(headers: headers, rows: rows)
        return reader.reading(text: text, textSHA256: PastedLabelAITextReaderTests.sha, answer: Data(answer.utf8))
    }

    func value(_ result: PastedLabelAITextReadingResult, _ nutrient: String, _ header: String) -> PastedLabelAITextReadingResult.Value? {
        result.values.first { $0.nutrient == nutrient && $0.headerID == header }
    }

    // MARK: D32: star markers

    func testALoneStarInTheReferenceIntakeColumnIsNotDeclared() throws {
        let result = read()
        XCTAssertEqual(result.outcome, .reachedConfirm, "\(result.declineReasons)")
        let candidate = try XCTUnwrap(result.candidate)
        for nutrient in ["saturates", "sugars"] {
            let star = try XCTUnwrap(value(result, nutrient, "h3"))
            XCTAssertEqual(star.read, .notRead(.notDeclared), nutrient)
            XCTAssertEqual(star.printedText, "*", "\(nutrient): shown as printed")
            XCTAssertEqual(star.reasons, [], "\(nutrient): needs no entry")
        }
        XCTAssertFalse(candidate.cells.contains { $0.decimalText == "0" || $0.printedText == "*" }, "never zero, never a cell")
        XCTAssertTrue(candidate.wouldMarkReady)
        XCTAssertEqual(result.attentionItemCount, 0, "\(result.values.filter(\.needsAttention).map { "\($0.nutrient) \($0.headerID) \($0.reasons)" })")
        XCTAssertTrue(candidate.warnings.contains("value_not_declared: saturates h3 '*'"), "\(candidate.warnings)")
        XCTAssertEqual(PastedLabelAITextWireMapping.version, "pasted-label-ai-text-mapping-v4")
    }

    func testAStarFootnoteOnANumberIsNotAMarker() throws {
        // The model copies `12%*` with its footnote: never a marker (read as before D32).
        let footnoted = read(rows: Self.rows(carbohydrate: [("h1", "30g"), ("h3", "12%*")]))
        XCTAssertNotEqual(value(footnoted, "carbohydrate", "h3")?.read, .notRead(.notDeclared))
        XCTAssertNil(PastedLabelAITextValueGrammar.notDeclaredMarker("12%*", inReferenceIntakeColumn: true))
        // The model gives `12%`: the text's `12%*` is that number, found with its footnote.
        let result = read(rows: Self.rows(carbohydrate: [("h1", "30g"), ("h3", "12%")]))
        let carbohydrate = try XCTUnwrap(result.candidate?.cells.first { $0.nutrient == "carbohydrate" && $0.headerID == "h3" })
        XCTAssertEqual([carbohydrate.decimalText, carbohydrate.canonicalUnit], ["12", "%"])
        XCTAssertEqual(value(result, "carbohydrate", "h3")?.reasons, [])
    }

    func testAStarTheTextDoesNotPrintThereStaysNotRead() {
        // The model claims a star where the text prints 12%*.
        let result = read(rows: Self.rows(carbohydrate: [("h1", "30g"), ("h3", "*")]))
        XCTAssertEqual(value(result, "carbohydrate", "h3")?.read, .notRead(.unreadable))
        XCTAssertFalse(result.candidate?.cells.contains { $0.nutrient == "carbohydrate" && $0.headerID == "h3" } ?? true)
    }

    func testALoneStarInAProductColumnIsUnreadable() {
        let text = Self.text.replacingOccurrences(of: "of which saturates\t3.2g\t*", with: "of which saturates\t*\t*")
        let result = read(text, rows: Self.rows(saturates: [("h1", "*"), ("h3", "*")]))
        XCTAssertEqual(value(result, "saturates", "h1")?.read, .notRead(.unreadable))
        XCTAssertNotEqual(value(result, "saturates", "h3")?.read, .notRead(.notDeclared), "the row's columns do not match")
        XCTAssertFalse(result.candidate?.wouldMarkReady ?? true, "a left-out amount")
        XCTAssertFalse(result.candidate?.cells.contains { $0.printedText == "*" } ?? true)
    }

    // MARK: D33: two-basis headers

    static let twoBasisText = """
    Nutrition Information per 100g/ml
    Energy\t1046kJ / 250kcal
    Fat\t9.5g
    of which saturates\t3.2g
    Carbohydrate\t30g
    of which sugars\t5g
    Protein\t8.1g
    Salt\t0.75g
    """

    static let amountRows: [(String, String, [(String, String)])] = [
        ("Energy", "energy_kj", [("h1", "1046kJ")]), ("Energy", "energy_kcal", [("h1", "250kcal")]), ("Fat", "fat", [("h1", "9.5g")]),
        ("of which saturates", "saturates", [("h1", "3.2g")]), ("Carbohydrate", "carbohydrate", [("h1", "30g")]),
        ("of which sugars", "sugars", [("h1", "5g")]), ("Protein", "protein", [("h1", "8.1g")]), ("Salt", "salt", [("h1", "0.75g")])]

    func testATwoBasisHeaderDeclinesWhateverBasisTheModelGives() {
        for (printed, basis) in [("per 100g/ml", "per_100g"), ("per 100g/ml", "per_100ml"), ("Nutrition Information per 100g/ml", "per_100g"),
                                 ("per 100g", "per_100g")] {
            let result = read(Self.twoBasisText, headers: [("h1", printed, basis)], rows: Self.amountRows)
            XCTAssertEqual(result.outcome, .declined, "\(printed) \(basis)")
            XCTAssertEqual(result.declineReasons, [PastedLabelAITextVocabulary.twoBasisDecline], "\(printed) \(basis)")
            XCTAssertNil(result.gate, "declined before the gate")
        }
        XCTAssertEqual(PastedLabelAITextVocabulary.twoBasisDecline, "vocabulary:two_basis_header")
        XCTAssertEqual(PastedLabelAITextReader.versions.vocabulary, "pasted-label-ai-text-vocabulary-v2")
    }

    func testASingleBasisHeaderIsUnchanged() {
        let text = Self.twoBasisText.replacingOccurrences(of: "per 100g/ml", with: "per 100g")
        let result = read(text, headers: [("h1", "per 100g", "per_100g")], rows: Self.amountRows)
        XCTAssertEqual(result.outcome, .reachedConfirm, "\(result.declineReasons)")
        XCTAssertEqual(result.values.first?.reasons, [])
    }

    func testAReferenceIntakeHeadingNamingBothBasesIsNotDeclined() {
        let text = "Typical values\tper 100g\t%RI per 100g/ml\nEnergy\t1046kJ / 250kcal\t13%\nFat\t9.5g\t14%\nof which saturates\t3.2g\t16%\n"
            + "Carbohydrate\t30g\t12%\nof which sugars\t5g\t6%\nProtein\t8.1g\t16%\nSalt\t0.75g\t13%\n"
        let rows = Self.amountRows.map { row in (row.0, row.1, row.2 + (row.1 == "energy_kj" ? [] : [("h3", "1%")])) }
        let result = read(text, headers: [("h1", "per 100g", "per_100g"), ("h3", "%RI per 100g/ml", "reference_intake")], rows: rows)
        XCTAssertNotEqual(result.declineReasons, [PastedLabelAITextVocabulary.twoBasisDecline])
        XCTAssertEqual(result.outcome, .reachedConfirm, "\(result.declineReasons)")
    }
}
