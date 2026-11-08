import FoodLedgerApplication
import XCTest

/// Star markers in the scan and `pasted-label-text-locate-v4`, and two-basis headers in
/// `pasted-label-ai-text-vocabulary-v2` and v3 (docs/pasted-label-ai-text-v1.md 4.3 item 12 and 4.4,
/// revision 15, D32 and D33). Synthetic text only.
final class PastedLabelTextStarMarkerTests: XCTestCase {
    typealias Locator = PastedLabelTextLocator
    typealias T = PastedLabelTextLocatorTests
    typealias Vocabulary = PastedLabelAITextVocabulary

    func markers(_ text: String) -> [String] { PastedLabelTextScan(text).markers.map(\.text) }

    // MARK: Scan

    func testALoneStarIsAMarker() {
        XCTAssertEqual(markers("Sugars\t10g\t*\nFibre 3g *"), ["*", "*"])
        XCTAssertEqual(PastedLabelTextScan("Sugars\t10g\t*").markers.map(\.isStar), [true])
        XCTAssertEqual(PastedLabelTextScan("Fat\t5g\t-*").markers.map(\.isStar), [false], "a dash keeps its footnote star (D30)")
    }

    func testAStarAttachedToANumberOrHeadingOrWordIsNotAMarker() {
        // A footnote on a number is part of its token; on a heading it is glued to a letter.
        XCTAssertEqual(markers("Sugars\t10g\t7%*"), [])
        XCTAssertEqual(markers("Typical values\tPer 100g\tRI*\t%RI**"), [])
        // A footnote line, two stars and a star with a dagger are not lone stars.
        XCTAssertEqual(markers("* Reference intake of an average adult\n*Reference intake"), [])
        XCTAssertEqual(markers("Sugars\t10g\t**\nFibre\t3g\t*†"), [])
        // The value tokens are unchanged.
        XCTAssertEqual(PastedLabelTextScan("Sugars 10g * 7%*").tokens.map(\.decimalText), ["10", "7"])
    }

    func testTheStarMarkerIsTheGrammarsAndOnlyForReferenceIntake() {
        XCTAssertEqual(PastedLabelAITextValueGrammar.notDeclaredStar, "*")
        XCTAssertEqual(PastedLabelAITextValueGrammar.notDeclaredMarker("*", inReferenceIntakeColumn: true), "*")
        XCTAssertNil(PastedLabelAITextValueGrammar.notDeclaredMarker("*", inReferenceIntakeColumn: false))
        XCTAssertNil(PastedLabelAITextValueGrammar.notDeclaredMarker("7%*", inReferenceIntakeColumn: true))
        XCTAssertNil(PastedLabelAITextValueGrammar.notDeclaredMarker("**", inReferenceIntakeColumn: true))
        XCTAssertEqual(PastedLabelAITextValueGrammar.notDeclaredMarker("-*", inReferenceIntakeColumn: false), "-", "D30 unchanged")
        XCTAssertFalse(PastedLabelAITextValueGrammar.isNotDeclaredMarker("*"), "the D30 lists are unchanged")
    }

    // MARK: Locator v4

    func testAStarInTheReferenceIntakeColumnIsFound() {
        let text = "Typical values\tPer 100g\t%RI\nFat\t5g\t7%\nSugars\t10g\t*\nSalt\t0.5g\t8%*\n"
        let result = Locator.locate(text: text, headers: [T.per100, T.referenceIntake],
                                    rows: [T.row("Fat", [("h1", "5g"), ("h3", "7%")]), T.row("Sugars", [("h1", "10g"), ("h3", "*")]),
                                           T.row("Salt", [("h1", "0.5g"), ("h3", "8%*")])])
        XCTAssertEqual(result.values[3].status, .found(T.scalars("*", in: text)))
        XCTAssertTrue(result.values.allSatisfy { !$0.needsAttention }, "\(result.values)")
        XCTAssertEqual(Locator.version, "pasted-label-text-locate-v4")
    }

    func testAStarIsNeverAProductAmount() {
        // The text prints a lone star under Per 100g: it is not a cell, so the row is short of a cell.
        let text = "Typical values\tPer 100g\t%RI\nFat\t5g\t7%\nSugars\t*\t*\n"
        let result = Locator.locate(text: text, headers: [T.per100, T.referenceIntake],
                                    rows: [T.row("Fat", [("h1", "5g"), ("h3", "7%")]), T.row("Sugars", [("h1", "*"), ("h3", "*")])])
        XCTAssertNotEqual(result.values[2].status, .found(T.scalars("*", in: text)))
        XCTAssertTrue(result.values[2].needsAttention)
        // A product column alone: a star the model claims is never found.
        let amounts = Locator.locate(text: "Per 100g\tPer serving\nSugars\t10g\t*\n", headers: [T.per100, T.perServing],
                                     rows: [T.row("Sugars", [("h1", "10g"), ("h2", "*")])])
        XCTAssertNotEqual(amounts.values[1].status.range, T.scalars("*", in: "Per 100g\tPer serving\nSugars\t10g\t*\n"))
        XCTAssertTrue(amounts.values[1].needsAttention)
    }

    func testAStarTheTextDoesNotPrintThereIsNotFound() {
        let text = "Typical values\tPer 100g\t%RI\nFat\t5g\t7%\nSugars\t10g\t3%\n"
        let result = Locator.locate(text: text, headers: [T.per100, T.referenceIntake],
                                    rows: [T.row("Fat", [("h1", "5g"), ("h3", "7%")]), T.row("Sugars", [("h1", "10g"), ("h3", "*")])])
        XCTAssertEqual(result.values[3].status, .notFound)
    }

    func testABlockWithAStarLocatesItsAmountsAsBefore() {
        // Dash markers and stars together: the dash fills its amount column, the star the %RI one.
        let text = "Typical values\tPer 100g\tPer serving\t%RI\nSugars\tTrace\t-\t*\nFat\t5g\t2g\t7%\n"
        let result = Locator.locate(text: text, headers: [T.per100, T.perServing, T.referenceIntake],
                                    rows: [T.row("Sugars", [("h1", "Trace"), ("h2", "-"), ("h3", "*")]),
                                           T.row("Fat", [("h1", "5g"), ("h2", "2g"), ("h3", "7%")])])
        XCTAssertEqual(result.values.prefix(3).map(\.status), [.found(T.scalars("Trace", in: text)), .found(T.scalars("-", in: text)),
                                                               .found(T.scalars("*", in: text))])
        XCTAssertTrue(result.values.allSatisfy { !$0.needsAttention })
    }

    // MARK: Vocabulary v2 (D33)

    func testHeadersNamingTwoBases() {
        for header in ["per 100g/ml", "Per 100 g/ml", "100g/100ml", "per 100g / 100ml", "Typical values per 100g/ml", "per 100ml/g",
                       "每100公克/毫升", "per 100g per 100ml"] {
            XCTAssertTrue(Vocabulary.namesTwoBases(header: header), header)
            XCTAssertNil(Vocabulary.basis(forHeader: header), header)
            XCTAssertEqual(Vocabulary.checkHeader(printedText: header, basis: "per_100g"), .unknown, header)
        }
        XCTAssertEqual(Vocabulary.version, "pasted-label-ai-text-vocabulary-v3")
    }

    func testSingleBasisAndReferenceIntakeHeadersAreUnchanged() {
        for (header, basis) in [("per 100g", "per_100g"), ("Per 100 g", "per_100g"), ("per 100ml", "per_100ml"), ("per 30g serving", "per_serving"),
                                ("%RI per 100g/ml", "reference_intake"), ("%Reference Intake Per 100 g/ml", "reference_intake"),
                                ("每100公克", "per_100g"), ("100g/100g", "per_100g")] {
            XCTAssertFalse(Vocabulary.namesTwoBases(header: header), header)
            XCTAssertEqual(Vocabulary.basis(forHeader: header), basis, header)
        }
    }

    /// The locator's span for a header: its single whole-word occurrence, or nil (4.3 item 4).
    func located(_ header: String, in text: String) -> Range<Int>? {
        let occurrences = header.isEmpty ? [] : PastedLabelTextScan(text).wholeWordOccurrences(of: header)
        return occurrences.count == 1 ? occurrences[0] : nil
    }

    func namesTwoBases(_ header: String, in text: String) -> Bool {
        Vocabulary.namesTwoBases(header: header, located: located(header, in: text), in: text)
    }

    func testAShortenedHeaderNamesTwoBasesWhereTheTextGoesOn() {
        XCTAssertTrue(namesTwoBases("per 100g", in: "Nutrition per 100g/ml\nFat 5g\n"))
        XCTAssertTrue(namesTwoBases("per 100g", in: "Typical values per 100g / 100ml\nFat 5g\n"))
        XCTAssertTrue(namesTwoBases("PER 100 G", in: "PER 100 G/ML\nFat 5g\n"))
        // A genuine two-basis heading declines on its own printed text, located or not.
        XCTAssertTrue(namesTwoBases("per 100g/ml", in: "Nutrition per 100g/ml\nFat 5g\n"))
        XCTAssertTrue(Vocabulary.namesTwoBases(header: "per 100g/ml", located: nil, in: ""))
        // Two printed columns, a slash elsewhere, or the same unit after the slash are not two bases.
        XCTAssertFalse(namesTwoBases("per 100g", in: "Typical values\tper 100g\tper 100ml\nFat\t5g\t5g\n"))
        XCTAssertFalse(namesTwoBases("per 100g", in: "Typical values per 100g\nEnergy 1046kJ/250kcal\n"))
        XCTAssertFalse(namesTwoBases("%RI", in: "Typical values\tper 100g\t%RI per 100g/ml\n"))
        // The same words inside a reference-intake heading are read with that heading.
        XCTAssertFalse(namesTwoBases("Per 100g", in: "Typical values\tPer 100g\t%RI per 100g/ml\n"))
        XCTAssertFalse(namesTwoBases("Per 100g", in: "Typical values  Per 100g  %RI per 100g/ml\n"))
        XCTAssertFalse(namesTwoBases("", in: "per 100g/ml"))
    }

    // MARK: Vocabulary v3 (revision 20)

    func testOnlyTheLocatedHeadingIsReadAgainstTheText() {
        // A footnote that prints `per 100g/ml` under a `Per 100g` heading reads normally: the
        // heading is located once, and its own occurrence does not continue with `/ml`.
        let footnote = "Typical values\tPer 100g\nFat\t5g\n\n* values per 100g/ml are typical\n"
        XCTAssertNotNil(located("Per 100g", in: footnote))
        XCTAssertFalse(namesTwoBases("Per 100g", in: footnote))
        // The shortened heading the D33 work handled still declines: the located cell goes on with `/ml`.
        let shortened = "Typical values\tPer 100g/ml\nFat\t5g\n\n* values per 100g are typical\n"
        XCTAssertTrue(namesTwoBases("Per 100g", in: shortened))
        // A header that is not located exactly once is read from its own text alone; its column is
        // already under attention (4.3 item 4), and the other occurrence never declines.
        let repeated = "Typical values per 100g\nFat 5g\n\nValues per 100g/ml are typical\n"
        XCTAssertNil(located("per 100g", in: repeated))
        XCTAssertFalse(namesTwoBases("per 100g", in: repeated))
        // An out-of-range span reads nothing beyond the header's own text.
        XCTAssertFalse(Vocabulary.namesTwoBases(header: "per 100g", located: 0..<999, in: "per 100g/ml"))
        XCTAssertFalse(Vocabulary.namesTwoBases(header: "per 100g", located: nil, in: "per 100g/ml"))
    }
}
