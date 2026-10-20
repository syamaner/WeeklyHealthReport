import Foundation
import FoodLedgerApplication
@testable import NutritionLabelParsing
import XCTest

/// `pasted-label-serving-v3` locates the recorded serving quantity with the application's copy of
/// parser v3's serving-size grammar (v1 decision 10: the application never imports the parser).
/// Reader v3 section 5.6, test 5: the four pattern strings are byte-identical to parser v3's, and on
/// the extended fixture set (joined lines, 每1份量, bilingual lines with and without an English
/// "about", serving and pack on one line with 約 in the pack phrase only and in the serving value)
/// the policy binds exactly the quantity parser v3 recorded. Synthetic lines only.
final class ServingSizeGrammarV3ParityTests: XCTestCase {
    private typealias P = PastedLabelServingPolicy
    private let v3 = PastedLabelSource.parserVersionV3

    func testThePatternsAreByteIdenticalToParserV3() {
        XCTAssertEqual(PastedLabelServingSizeGrammarV3.labelPattern, PatternsV3.servingSize.expression.pattern)
        XCTAssertEqual(PastedLabelServingSizeGrammarV3.parenthesisedPattern, Patterns.parenthesised.expression.pattern)
        XCTAssertEqual(PastedLabelServingSizeGrammarV3.quantityPattern, Patterns.servingQuantity.expression.pattern)
        XCTAssertEqual(PastedLabelServingSizeGrammarV3.packPhrasePattern, PatternsV3.packPhrase.expression.pattern)
        XCTAssertEqual(NutritionLabelTextParserV3.version, v3)
        // The v2 copy is unchanged and still pinned to parser v2.
        XCTAssertEqual(PastedLabelServingSizeGrammar.labelPattern, Patterns.servingSize.expression.pattern)
    }

    /// Each line through parser v3's own serving-size reading, then the policy: it binds exactly
    /// the recorded quantity (never `unmatched` when the parser read one) and reads it as listed.
    func testThePolicyBindsTheQuantityParserV3RecordedOnTheExtendedFixtures() throws {
        let cases: [(String, P.Exactness)] = [
            ("每一份量30公克", .exact), ("每1份量30公克", .exact), ("每1份量 30 公克", .exact), ("每份量250毫升", .exact),
            ("每一份量30公克，本包裝含約10份", .exact), ("每1份量30公克 本包裝含約8份", .exact), ("每一份量30公克／本包裝包含8份", .exact),
            ("每一份量30公克、本包裝 8 份", .exact), ("每一份量約30公克，本包裝含8份", .approximate), ("每1份量約30公克 本包裝含約8份", .approximate),
            ("每一份量 30 公克（約2片）", .exact), ("每一份量30公克～約2片", .exact), ("每一份量30公克～（2片）", .exact),
            ("每一份量30公克 (Serving size 30g)", .exact), ("每一份量 30公克 Serving Size 30 g", .exact),
            ("每一份量30公克 (Serving size about 30g)", .approximate), ("每一份量30公克（約2片）Serving size 30g about 2 pieces", .approximate),
            ("每一份量1片，本包裝含8份(240公克)", .unmatched), ("Serving size 30g, servings per container about 8", .exact),
            ("Serving size 25 grams - 30g", .range(own: .init(low: "25", high: "30"))), ("Serving size 30g - 2", .range(own: nil))
        ]
        for (line, expected) in cases {
            let rest = try XCTUnwrap(PatternsV3.servingSize.firstMatch(in: line)?[1] ?? nil, line)
            let parsed = ParseStateV3.servingSize(printed: line, value: rest)
            let size = PastedLabelManifest.Candidate.ServingSize(printedText: parsed.printedText, decimalText: parsed.decimalText,
                                                                 unit: parsed.unit, canonicalUnit: parsed.canonicalUnit)
            if parsed.decimalText == nil {
                XCTAssertEqual(expected, .unmatched, "the parser reads no quantity: \(line)")
                XCTAssertNil(P.locatedV3(size), line)
                continue
            }
            let located = try XCTUnwrap(P.locatedV3(size), "the policy binds the recorded quantity: \(line)")
            let number = (located.value as NSString).substring(with: located.number)
            XCTAssertEqual(number, parsed.decimalText, line)
            XCTAssertEqual(P.exactness(size, parserVersion: v3), expected, line)
        }
    }

    /// A joined serving line: the policy reads the candidate's stored printed text (label line,
    /// one ASCII space, quantity line) and never re-joins from the pasted text.
    func testAJoinedServingLineIsReadFromItsStoredPrintedText() throws {
        for (text, printed) in [("營養標示\n每一份量\n30公克\n本包裝含8份\n每份\n熱量 120大卡\n蛋白質 3公克\n脂肪 4公克\n碳水化合物 18公克\n鈉 60毫克\n", "每一份量 30公克"),
                                ("營養標示\n每1份量：\n  250毫升 \n本包裝含4份\n每100毫升\n熱量 40大卡\n蛋白質 3公克\n脂肪 4公克\n碳水化合物 18公克\n鈉 60毫克\n", "每1份量： 250毫升")] {
            let candidate = NutritionLabelTextParserV3().parse(text, inputSHA256: "synthetic")
            let serving = try XCTUnwrap(candidate.servingSize, text)
            XCTAssertEqual(serving.printedText, printed)
            XCTAssertTrue(candidate.warnings.contains("serving_line_joined"))
            let size = PastedLabelManifest.Candidate.ServingSize(printedText: serving.printedText, decimalText: serving.decimalText,
                                                                 unit: serving.unit, canonicalUnit: serving.canonicalUnit)
            XCTAssertEqual(P.exactness(size, parserVersion: v3), .exact, printed)
        }
    }
}
