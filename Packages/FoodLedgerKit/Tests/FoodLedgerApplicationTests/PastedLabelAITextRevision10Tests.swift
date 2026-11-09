import FoodLedgerApplication
import XCTest

/// Revision 10 of docs/pasted-label-ai-text-v1.md (A3): the bracket rule and the text-only kcal
/// spellings of the value grammar, and the text route's format step. Synthetic text only.
final class PastedLabelAITextRevision10Tests: XCTestCase {
    typealias Grammar = PastedLabelAITextValueGrammar

    func testTheBracketRuleDropsOnlyTheLabelsOwnOuterBrackets() {
        XCTAssertEqual(Grammar.unbracketed("(3.5g)"), .init(open: "(", core: "3.5g", close: ")"))
        XCTAssertEqual(Grammar.unbracketed("4.8g)"), .init(open: nil, core: "4.8g", close: ")"))
        XCTAssertEqual(Grammar.unbracketed("(4.8g"), .init(open: "(", core: "4.8g", close: nil))
        XCTAssertEqual(Grammar.unbracketed("\u{FF08}3.5公克\u{FF09}"), .init(open: "\u{FF08}", core: "3.5公克", close: "\u{FF09}"))
        for unchanged in ["3.5g", "5 g (g)", "5 g\u{FF08}g\u{FF09}", "250kcal (kcal)", "(5g) (2g)", "()", "(", "(3.5g\u{FF09}", ""] {
            XCTAssertFalse(Grammar.unbracketed(unchanged).isBracketed, unchanged)
            XCTAssertEqual(Grammar.unbracketed(unchanged).core, unchanged)
        }
    }

    func testTheTextOnlyKcalSpellingsExtendThePhotoListWithoutChangingIt() {
        XCTAssertEqual(Grammar.textOnlyValueUnits, ["Kcal", "kCal", "KCal", "KCAL"])
        XCTAssertEqual(Grammar.textValueUnits, Grammar.valueUnits + Grammar.textOnlyValueUnits)
        for unit in Grammar.textOnlyValueUnits { XCTAssertEqual(Grammar.canonicalUnit(unit), "kcal", unit) }
        XCTAssertNil(Grammar.canonicalUnit("Cal"), "`Cal` stays outside the closed table")
        XCTAssertFalse(Grammar.textValueUnits.contains("Cal"))
        XCTAssertEqual(Set(Grammar.unitsLongestFirst), Set(Grammar.textValueUnits))
    }

    func testTheTokenScanReadsTheKcalSpellings() {
        let scan = PastedLabelTextScan("Energy 1500kJ / 360kCal 90KCAL")
        XCTAssertEqual(scan.tokens.map(\.canonicalUnit), ["kJ", "kcal", "kcal"])
        XCTAssertEqual(PastedLabelTextScan("Energy 30Cal").tokens.count, 0)
    }

    // MARK: Format step

    func testAMixedAnswerWithTheTaiwanTitleIsTaiwan() {
        XCTAssertEqual(PastedLabelAITextFormat.version, "pasted-label-ai-text-format-v1")
        XCTAssertTrue(PastedLabelAITextFormat.mixedIsTaiwan(language: "mixed", text: "營養標示 500ML\n每100毫升\n熱量 Calories 20大卡"))
    }

    /// The unsafe neighbours stay ambiguous: no Taiwan title, a simplified-script title, or a
    /// language other than `mixed`.
    func testOtherwiseTheFormatStepChangesNothing() {
        XCTAssertFalse(PastedLabelAITextFormat.mixedIsTaiwan(language: "mixed", text: "每100毫升\n熱量 Calories 20大卡"))
        XCTAssertFalse(PastedLabelAITextFormat.mixedIsTaiwan(language: "mixed", text: "营养成分表\n每100毫升\n能量 80千焦"))
        XCTAssertFalse(PastedLabelAITextFormat.mixedIsTaiwan(language: "unknown", text: "營養標示\n每100毫升"))
        XCTAssertFalse(PastedLabelAITextFormat.mixedIsTaiwan(language: "en", text: "營養標示\nPer 100ml"))
    }
}
