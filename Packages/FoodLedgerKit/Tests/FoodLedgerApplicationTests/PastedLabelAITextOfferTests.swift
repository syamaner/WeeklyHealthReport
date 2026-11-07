import FoodLedgerApplication
import XCTest

/// Contract test 12 (docs/pasted-label-ai-text-v1.md 4.6, D15): only the closed set of layout
/// and format declines offers Read with AI; and the attention reasons of
/// `pasted-label-ai-text-attention-v1` (4.8), with every v1 reason carried across unchanged.
final class PastedLabelAITextOfferTests: XCTestCase {
    typealias Offer = PastedLabelAITextOffer
    let text = "Per 100g\nFat 5g"

    func testTaiwanLayoutDeclinesAreOffered() {
        for code in Offer.taiwanLayoutCodes.sorted() {
            XCTAssertTrue(Offer.isOffered(declineCodes: [code], format: Offer.taiwanFormat, pastedText: text), code)
        }
        XCTAssertTrue(Offer.isOffered(declineCodes: ["count_mismatch", "too_little_read"], format: Offer.taiwanFormat, pastedText: text))
    }

    func testUKLayoutNotSupportedIsOffered() {
        XCTAssertTrue(Offer.isOffered(declineCodes: ["layout_not_supported"], format: Offer.ukFormat, pastedText: text))
    }

    func testEverythingElseIsNotOffered() {
        let refused: [([String], String?, String)] = [
            (["basis_state_not_supported"], Offer.taiwanFormat, text),
            (["count_mismatch", "basis_state_not_supported"], Offer.taiwanFormat, text),
            (["layout_not_supported", "basis_state_not_supported"], Offer.ukFormat, text),
            (["layout_not_supported", "not_a_food_nutrition_panel"], Offer.ukFormat, text),
            (["count_mismatch"], Offer.ukFormat, text),
            (["layout_not_supported"], Offer.taiwanFormat, text),
            (["text_too_long"], nil, text),
            (["unreadable_table"], nil, text),
            (["unreadable_table"], Offer.taiwanFormat, text),
            (["unsupported_script"], Offer.taiwanFormat, text),
            (["unsupported_language"], Offer.taiwanFormat, text),
            (["not_a_food_nutrition_panel"], Offer.taiwanFormat, text),
            (["multiple_complete_panels"], Offer.taiwanFormat, text),
            (["multiple_panels"], Offer.taiwanFormat, text),
            (["no_table"], Offer.taiwanFormat, text),
            (["asserted_bases_mismatch"], Offer.taiwanFormat, text),
            (["format_ambiguous"], "format_ambiguous", text),
            (["layout_not_supported"], "us_nutrition_facts", text),
            ([], Offer.taiwanFormat, text),
            (["count_mismatch"], Offer.taiwanFormat, "  \n "),
            (["count_mismatch"], Offer.taiwanFormat, String(repeating: "a", count: 8_001))
        ]
        for (codes, format, pasted) in refused {
            XCTAssertFalse(Offer.isOffered(declineCodes: codes, format: format, pastedText: pasted), "\(codes) \(format ?? "nil")")
        }
    }

    func testEveryLayoutCodeIsAFrozenHardDecline() {
        for code in Offer.taiwanLayoutCodes.sorted() {
            XCTAssertNotNil(PastedLabelCodes.mapping[code], code)
            XCTAssertEqual(PastedLabelCodes.classify(code).kind, .hardDecline, code)
        }
    }

    // MARK: Attention reasons

    func testAttentionReasonsComposeV1Unchanged() {
        typealias Reason = PastedLabelAITextAttention.Reason
        XCTAssertEqual(PastedLabelAITextAttention.version, "pasted-label-ai-text-attention-v1")
        XCTAssertEqual(PastedLabelAITextAttention.composedVersion, "label-photo-attention-v1")
        for reason in LabelPhotoAttention.Reason.allCases { XCTAssertEqual(Reason(reason).rawValue, reason.rawValue) }
        XCTAssertEqual(Reason.allCases.map(\.rawValue), ["not_found", "ambiguous", "gate_flag", "check_failed", "unit_not_stated",
                                                         "vocabulary_mismatch", "label_unknown"])
        XCTAssertEqual(Array(Reason.allCases.prefix(LabelPhotoAttention.Reason.allCases.count)).map(\.rawValue),
                       LabelPhotoAttention.Reason.allCases.map(\.rawValue))
    }

    func testCheckOutcomesMapToReasons() {
        typealias Locator = PastedLabelTextLocator
        let text = "Per 100g Per serving\nFat 5g\nSalt 0.5g 0.25g"
        let headers = [Locator.Header(id: "h1", printedText: "Per 100g", basis: "per_100g"),
                       Locator.Header(id: "h2", printedText: "Per serving", basis: "per_serving")]
        let rows = [Locator.Row(printedLabel: "Fat", values: [Locator.Value(headerID: "h1", printedText: "5g")]),
                    Locator.Row(printedLabel: "Salt", values: [Locator.Value(headerID: "h1", printedText: "0.5g"), Locator.Value(headerID: "h2", printedText: "9g")])]
        let reasons = Locator.locate(text: text, headers: headers, rows: rows).values.map(PastedLabelAITextAttention.reason)
        XCTAssertEqual(reasons, [.ambiguous, nil, .notFound])
        XCTAssertEqual(PastedLabelAITextAttention.reason(PastedLabelAITextUnitCheck.Outcome.notStated), .unitNotStated)
        XCTAssertNil(PastedLabelAITextAttention.reason(PastedLabelAITextUnitCheck.Outcome.statedInHeader))
        XCTAssertEqual(PastedLabelAITextAttention.reason(PastedLabelAITextVocabulary.Verdict.mismatch), .vocabularyMismatch)
        XCTAssertEqual(PastedLabelAITextAttention.reason(PastedLabelAITextVocabulary.Verdict.unknown), .labelUnknown)
        XCTAssertNil(PastedLabelAITextAttention.reason(PastedLabelAITextVocabulary.Verdict.agrees))
        XCTAssertEqual(PastedLabelAITextAttention.ordered([.labelUnknown, .notFound, .notFound]), [.notFound, .labelUnknown])
    }
}
