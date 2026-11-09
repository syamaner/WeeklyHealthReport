import FoodLedgerApplication
import XCTest

/// `pasted-label-ai-text-vocabulary-v1` (docs/pasted-label-ai-text-v1.md 4.4, D11): agreement,
/// mismatch and unknown labels and headers. Synthetic words only.
final class PastedLabelAITextVocabularyTests: XCTestCase {
    typealias Vocabulary = PastedLabelAITextVocabulary

    func testVersion() { XCTAssertEqual(Vocabulary.version, "pasted-label-ai-text-vocabulary-v3") }

    func testRowLabelsAgree() {
        let cases: [(String, String)] = [
            ("Energy", "energy_kj"), ("Energy", "energy_kcal"), ("Energy (kJ)", "energy_kj"), ("Energy kJ/kcal", "energy_kcal"),
            ("Fat", "fat"), ("of which saturates", "saturates"), ("- of which Saturates", "saturates"), ("Saturated fat", "saturates"),
            ("Carbohydrate", "carbohydrate"), ("of which sugars", "sugars"), ("Fibre (g)", "fibre"), ("Protein", "protein"),
            ("Salt*", "salt"), ("Sodium", "sodium"), ("Mono-unsaturates", "unrecognised"),
            ("熱量", "energy_kcal"), ("蛋白質", "protein"), ("脂肪", "fat"), ("\u{3000}飽和脂肪", "saturates"), ("反式脂肪", "trans_fat"),
            ("碳水化合物", "carbohydrate"), ("糖", "sugars"), ("鈉", "sodium"), ("膳食纖維（公克）", "fibre")
        ]
        for (label, nutrient) in cases {
            XCTAssertEqual(Vocabulary.checkRow(printedLabel: label, nutrient: nutrient), .agrees, "\(label) is \(nutrient)")
        }
    }

    func testTrailingPunctuationBeforeAUnitGroupIsDropped() {
        for (label, nutrient) in [("Fat: (g)", "fat"), ("Fat:", "fat"), ("Fat - (g)", "fat"), ("脂肪：", "fat"), ("脂肪：（公克）", "fat"),
                                  ("Salt -", "salt"), ("Protein (g):", "protein")] {
            XCTAssertEqual(Vocabulary.checkRow(printedLabel: label, nutrient: nutrient), .agrees, label)
        }
        XCTAssertEqual(Vocabulary.checkRow(printedLabel: "Fat (total)", nutrient: "fat"), .unknown, "a bracket that is not a unit group stays")
    }

    func testRowLabelMismatchIsAttention() {
        XCTAssertEqual(Vocabulary.checkRow(printedLabel: "Salt", nutrient: "sodium"), .mismatch)
        XCTAssertEqual(Vocabulary.checkRow(printedLabel: "of which sugars", nutrient: "fibre"), .mismatch)
        XCTAssertEqual(Vocabulary.checkRow(printedLabel: "Saturates", nutrient: "fat"), .mismatch)
        XCTAssertEqual(Vocabulary.checkRow(printedLabel: "飽和脂肪", nutrient: "fat"), .mismatch)
        XCTAssertEqual(Vocabulary.checkRow(printedLabel: "Energy", nutrient: "protein"), .mismatch)
    }

    func testUnknownRowLabelIsAttention() {
        for label in ["Vitamin C", "Calcium", "Typical values", "", "Fats and oils", "鈣"] {
            XCTAssertEqual(Vocabulary.checkRow(printedLabel: label, nutrient: "fat"), .unknown, label)
        }
        XCTAssertEqual(Vocabulary.checkRow(printedLabel: "Vitamin C", nutrient: "unrecognised"), .unknown,
                       "the model calling a row unrecognised does not make the label known")
    }

    func testHeaders() {
        let cases: [(String, String)] = [
            ("Per 100g", "per_100g"), ("per 100 g", "per_100g"), ("Typical values per 100g (as sold)", "per_100g"), ("100ml", "per_100ml"),
            ("Per serving", "per_serving"), ("Per 30g serving", "per_serving"), ("Per portion", "per_serving"), ("%RI*", "reference_intake"),
            ("% RI per serving", "reference_intake"), ("Reference Intake", "reference_intake"), ("每100公克", "per_100g"),
            ("每100毫升", "per_100ml"), ("每份", "per_serving"), ("每日參考值百分比", "reference_intake")
        ]
        for (header, basis) in cases {
            XCTAssertEqual(Vocabulary.checkHeader(printedText: header, basis: basis), .agrees, "\(header) is \(basis)")
        }
        XCTAssertEqual(Vocabulary.checkHeader(printedText: "Per 100g", basis: "per_serving"), .mismatch)
        XCTAssertEqual(Vocabulary.checkHeader(printedText: "每份", basis: "per_100g"), .mismatch)
        XCTAssertEqual(Vocabulary.checkHeader(printedText: "Per serving (100g)", basis: "per_serving"), .unknown, "two bases is unknown")
        XCTAssertEqual(Vocabulary.checkHeader(printedText: "Typical values", basis: "per_100g"), .unknown)
        XCTAssertEqual(Vocabulary.checkHeader(printedText: "Per 1/2 pack", basis: "per_serving"), .unknown)
    }

    func testOnlyAPerServingPhraseNamesTheBasis() {
        for header in ["Per serving", "per portion", "Per 30g serving", "Per 30 g serving", "Serving (30g)", "Portion (150 g)", "每份", "每一份"] {
            XCTAssertEqual(Vocabulary.checkHeader(printedText: header, basis: "per_serving"), .agrees, header)
        }
        for header in ["Serving suggestions", "Serving", "Each serving", "Portion", "Serving suggestion: 2 slices"] {
            XCTAssertEqual(Vocabulary.checkHeader(printedText: header, basis: "per_serving"), .unknown, header)
        }
    }

    func testQuantityHeadersAreNotABasis() {
        for header in ["Serving size", "Serving Size: 30g", "Portion size", "Servings per pack", "Servings per package: 4", "Portions per pack",
                       "每份重量", "每份重量30公克", "本包裝含8份", "份量"] {
            XCTAssertEqual(Vocabulary.checkHeader(printedText: header, basis: "per_serving"), .unknown, header)
        }
        for header in ["Per serving", "Per serving (30g)", "Per 30g serving", "Per portion", "每份", "每一份"] {
            XCTAssertEqual(Vocabulary.checkHeader(printedText: header, basis: "per_serving"), .agrees, header)
        }
    }
}
