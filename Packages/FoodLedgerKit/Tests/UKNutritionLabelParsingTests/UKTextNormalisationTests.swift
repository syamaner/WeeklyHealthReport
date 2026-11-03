@testable import NutritionLabelParsing
@testable import UKNutritionLabelParsing
import XCTest

/// Contract tests 1, 2 and 10 of `docs/pasted-nutrition-label-uk-english-v1-p2.md`: each rule's
/// positive cases (parser v3 misreads or leaves them unread before; they read after), the shapes
/// that must stay unchanged, the normaliser's properties, and the copied vocabulary's parity.
/// Every text is synthetic.
final class UKTextNormalisationTests: XCTestCase {
    private let v3 = NutritionLabelTextParserV3()
    private let uk = NutritionLabelTextParserUK()

    static let rows = "Fat\t12g\nof which saturates\t5g\nCarbohydrate\t50g\nof which sugars\t20g\nFibre\t3g\nProtein\t8g\nSalt\t0.5g"

    private func basis(_ candidate: LabelCaptureCandidate) -> [LabelBasis] { candidate.headers.map(\.basis) }
    private func nutrients(_ candidate: LabelCaptureCandidate) -> Set<String> { Set(candidate.cells.map(\.nutrient)) }

    // MARK: N1

    func testN1ReadsGramAndMillilitreSpellingsAsPer100WhereV3ReadPerServing() {
        for header in ["Typical values\tper 100gm", "Typical values\tPer 100gms", "Typical values\tper 100 grams", "Typical values\tPER 100 GRAMMES"] {
            let text = "\(header)\nEnergy\t1520kJ\n\t362kcal\n" + Self.rows
            XCTAssertEqual(basis(v3.parse(text, inputSHA256: "x")), [.perServing], header)
            XCTAssertEqual(basis(uk.parse(text, inputSHA256: "x")), [.per100g], header)
        }
        let liquid = "Typical values\tPer 100mls\nEnergy\t180kJ\n\t43kcal\n" + Self.rows
        XCTAssertEqual(basis(uk.parse(liquid, inputSHA256: "x")), [.per100ml])
    }

    func testN1LeavesOtherLinesAndDigitBoundariesAlone() {
        for line in ["Contains 100gm of oats", "Per 1100gm", "per 100gmx", "Per 100g", "Per 30g serving"] {
            XCTAssertEqual(UKTextNormalisation.lines(line), [line], line)
        }
    }

    // MARK: N2

    func testN2MovesALabelUnitOntoBareNumbersThatV3Declines() {
        let text = "Typical values\tPer 100g\tPer 30g\nEnergy kJ\t1520\t456\nEnergy KCAL\t362\t109\nFat\t12g\t3.6g\nof which saturates\t5g\t1.5g\n"
            + "Carbohydrate\t50g\t15g\nof which sugars\t20g\t6g\nFibre\t3g\t0.9g\nProtein\t8g\t2.4g\nSalt\t0.5g\t0.15g"
        XCTAssertTrue(v3.parse(text, inputSHA256: "x").declined)
        XCTAssertEqual(UKTextNormalisation.lines("Energy kJ\t1520\t456"), ["Energy\t1520kJ\t456kJ"])
        XCTAssertEqual(UKTextNormalisation.lines("Protein (μg) <5 | 7"), ["Protein <5μg | 7μg"])
        let read = uk.parse(text, inputSHA256: "x")
        XCTAssertFalse(read.declined, "\(read.declineReasons)")
        XCTAssertEqual(read.cells.first { $0.nutrient == "energy_kcal" && $0.basis == .perServing }?.decimalText, "109")
    }

    func testN2LeavesEveryOtherShapeUnchanged() {
        for line in ["Energy kJ 1520 / kcal 362", "Energy kJ\t1520/362", "Salt (g) 0.1 Tr", "Fat (g) 3.4 5%", "Fat g 3.4g 1.0",
                     "(kcal) 362", "Energy (cal)\t182", "Energy kJ kcal\t1520", "8400kJ / 2000kcal", "Protein (g)\t9.8\t35.8",
                     "熱量 200大卡", "營養標示 Energy kcal 387"] {
            XCTAssertEqual(UKTextNormalisation.lines(line), [line], line)
        }
    }

    // MARK: N5 (P2b)

    func testN5DropsAnEnergyLabelUnitThatEveryValueRepeats() {
        XCTAssertEqual(UKTextNormalisation.lines("Energy kJ\t1520 kJ\t456 kJ"), ["Energy\t1520 kJ\t456 kJ"])
        XCTAssertEqual(UKTextNormalisation.lines("Energy kcal: 362 kcal"), ["Energy: 362 kcal"])
        XCTAssertEqual(UKTextNormalisation.lines("Energy kJ: 328 kJ"), ["Energy: 328 kJ"])
        XCTAssertEqual(UKTextNormalisation.lines("Typical values Energy kJ 1520 kJ"), ["Typical values", "Energy 1520 kJ"])
        let text = "per 100 g\nEnergy kJ\t1520 kJ\nEnergy kcal\t362 kcal\n" + Self.rows
        XCTAssertFalse(nutrients(v3.parse(text, inputSHA256: "x")).contains("energy_kj"))
        let read = uk.parse(text, inputSHA256: "x")
        XCTAssertEqual(read.cells.first { $0.nutrient == "energy_kj" }?.decimalText, "1520")
        XCTAssertEqual(read.cells.first { $0.nutrient == "energy_kcal" }?.decimalText, "362")
    }

    func testN5LeavesEveryOtherEnergyLineUnchanged() {
        XCTAssertNil(UKTextNormalisation.dropRedundantEnergyUnit("Energy kJ 1520"), "N2's case is not N5's")
        for line in ["Energy kJ 1520 kcal", "Energy kJ 1520kJ 18%", "Energy kJ / kcal 1069kJ / 254kcal",
                     "Energy kJ 1520 kJ 362 kcal", "Energy kcal 1520 kJ", "Energy kJ 1520 kJ 362", "Energy per 100g kJ 1520 kJ",
                     "Energy kJ 1520 kJ Energy kJ 456 kJ", "Energy kJ kcal 1520 kJ", "Protein g 8g", "Energy cal 182 cal",
                     "熱量 kJ 200 kJ"] {
            XCTAssertEqual(UKTextNormalisation.lines(line), [line], line)
        }
    }

    func testN5BindsStackedEnergyAndNeverReadsAThousandsCommaAsADecimal() {
        let stacked = uk.parse("per 100 g\nEnergy kJ 1520 kJ\n362 kcal\n" + Self.rows, inputSHA256: "x")
        XCTAssertEqual(stacked.cells.first { $0.nutrient == "energy_kj" }?.decimalText, "1520")
        XCTAssertFalse(stacked.cells.contains { $0.unit == "kJ" && $0.decimalText == "362" })
        let comma = uk.parse("per 100 g\nEnergy kJ 1,520 kJ\nEnergy kcal 362 kcal\n" + Self.rows, inputSHA256: "x")
        XCTAssertFalse(comma.cells.contains { $0.decimalText == "1.52" })
        let reference = uk.parse("Typical values\tper 100 g\t%RI\nEnergy kJ\t1520 kJ\t18%\nEnergy kcal\t362 kcal\t18%\n" + Self.rows, inputSHA256: "x")
        XCTAssertFalse(reference.cells.contains { $0.unit == "%" && $0.basis != .referenceIntake })
    }

    // MARK: N3

    func testN3RestoresSubRowMarkersV3DoesNotRecognise() {
        XCTAssertEqual(UKTextNormalisation.lines("of which \u{2014} Saturates\t5g"), ["of which Saturates\t5g"])
        XCTAssertEqual(UKTextNormalisation.lines("of which are saturates\t5g"), ["of which saturates\t5g"])
        XCTAssertEqual(UKTextNormalisation.lines("_of which sugars\t20g"), ["of which sugars\t20g"])
        XCTAssertEqual(UKTextNormalisation.lines("Fat\t12g\n(of Which Saturates)\t5g"), ["Fat\t12g", "of which Saturates\t5g"])
        let text = "Typical values\tPer 100g\nEnergy\t1520kJ\n\t362kcal\nFat\t12g\nof which \u{2014} saturates\t5g\nCarbohydrate\t50g\n"
            + "_of which sugars\t20g\nFibre\t3g\nProtein\t8g\nSalt\t0.5g"
        XCTAssertFalse(nutrients(v3.parse(text, inputSHA256: "x")).contains("saturates"))
        let read = uk.parse(text, inputSHA256: "x")
        XCTAssertTrue(nutrients(read).isSuperset(of: ["saturates", "sugars"]), "\(read.declineReasons)")
    }

    func testN3NeverReparentsATopLevelRowOrAUnit() {
        for text in ["Energy\t1520kJ\n(kcal) 362", "Carbohydrate 50g\n(Fibre) 3g", "Fat 12g\n(Energy) 3", "Carbohydrate 50g\n(saturates) 5g",
                     "Fat 12g\n(sugars) 2g"] {
            XCTAssertEqual(UKTextNormalisation.lines(text), text.components(separatedBy: "\n"), text)
        }
        // The nearest top-level row above, not the line above, is the parent.
        XCTAssertEqual(UKTextNormalisation.lines("Carbohydrate 50g\nof which sugars 20g\n(starch) 30g").last, "of which starch 30g")
    }

    // MARK: N4

    func testN4SplitsATitleGluedToTheFirstEnergyRow() {
        XCTAssertEqual(UKTextNormalisation.lines("Average nutritional information Energy\t1520kJ"), ["Average nutritional information", "Energy\t1520kJ"])
        let text = "Per 100g\nTypical values Energy\t1520kJ\n\t362kcal\n" + Self.rows
        XCTAssertFalse(nutrients(v3.parse(text, inputSHA256: "x")).contains("energy_kj"))
        XCTAssertTrue(nutrients(uk.parse(text, inputSHA256: "x")).contains("energy_kj"))
        for line in ["Typical values per 100g", "Nutrition Energetics 5", "Nutritional information", "Typical valuesEnergy 5kJ"] {
            XCTAssertEqual(UKTextNormalisation.lines(line), [line], line)
        }
    }

    // MARK: Properties (test 2)

    /// Digit runs, separators and every comparator of the value pattern.
    static let digitRuns = try! NSRegularExpression(pattern: #"[0-9]+|[.,]|less than|<=|≤|≦|＜|<|少於|未滿"#)
    static let unitRuns = try! NSRegularExpression(pattern: "(?<![\\p{L}])(" + UKVocabulary.unitTokens.joined(separator: "|") + ")(?![\\p{L}])")

    private func tokens(_ text: String) -> [String] {
        Self.digitRuns.matches(in: text, range: NSRange(text.startIndex..., in: text)).map { String(text[Range($0.range, in: text)!]) }.sorted()
    }

    private func units(_ text: String) -> [String] {
        Self.unitRuns.matches(in: text, range: NSRange(text.startIndex..., in: text)).map { String(text[Range($0.range, in: text)!]) }
    }

    /// Unit tokens are preserved, apart from N1's respelling (no token before, `g` or `ml` after)
    /// and N2's copy of the label unit onto each number (one more token per number, all the label's).
    func testNormalisationKeepsUnitTokensApartFromN1AndN2() {
        let cases = ["Energy kJ\t1520\t456", "Protein (μg) <5 | 7", "Fat\t12g\n(of Which Saturates)\t5g", "of which are sugars 3g",
                     "Average nutritional information Energy\t1520kJ", "Fat (g) 3.4 5%", Self.rows]
        for text in cases {
            let before = units(text), after = units(UKTextNormalisation.normalise(text))
            if let n2 = UKTextNormalisation.moveLabelUnit(text), !text.contains("\n") {
                XCTAssertEqual(after, units(n2), text)
                XCTAssertEqual(Set(after), Set(before), text)
            } else {
                XCTAssertEqual(after.sorted(), before.sorted(), text)
            }
        }
    }

    /// A bare-number reference intake column under an N2 label unit never binds as an amount.
    func testN2NeverBindsABareReferenceIntakeColumnAsAnAmount() {
        for header in ["%RI", "% RI", "%Reference intake", "%RI*"] {
            let text = "Typical values\tPer 100g\tPer 30g\t\(header)\nEnergy kJ\t1520\t456\t5\nEnergy kcal\t362\t109\t5\n"
                + "Fat g\t12\t3.6\t5\nof which saturates\t5g\t1.5g\t8%\nCarbohydrate\t50g\t15g\t6%\nof which sugars\t20g\t6g\t7%\n"
                + "Protein\t8g\t2.4g\t5%\nSalt\t0.5g\t0.15g\t3%"
            let read = uk.parse(text, inputSHA256: "x")
            // The only bare 5s are the reference intake cells (saturates prints 5g as an amount).
            XCTAssertTrue(read.declined || !read.cells.contains { $0.decimalText == "5" && $0.nutrient != "saturates" && $0.basis != .referenceIntake },
                          "\(header) \(read.declineReasons)")
        }
    }

    func testNormalisationKeepsEveryNumberSeparatorAndComparatorAndTheLanguage() {
        let texts = UKGuardCases.all + [Self.rows, "Typical values\tper 100gm\nEnergy kJ\t1520\t456", "營養標示\n每100公克\n熱量 200大卡"]
        for text in texts {
            let normalised = UKTextNormalisation.normalise(text)
            XCTAssertEqual(tokens(normalised), tokens(text), text)
            XCTAssertEqual(NutritionLabelTextParser.language(of: normalised), NutritionLabelTextParser.language(of: text), text)
            let fired = normalised != text
            if !fired { XCTAssertEqual(normalised, text) }
        }
    }

    // MARK: Vocabulary parity (test 10)

    func testCopiedVocabularyMatchesParserV3() {
        XCTAssertEqual(UKVocabulary.valuePattern, PatternsV3.value.expression.pattern)
        XCTAssertEqual(UKVocabulary.headerPhrasePattern, Patterns.headerPhrase.expression.pattern)
        for unit in UKVocabulary.unitTokens {
            XCTAssertNotNil(PatternsV3.value.firstMatch(in: "5" + unit)?[3].flatMap { $0 == unit ? $0 : nil }, unit)
        }
        for label in UKVocabulary.energyLabels { XCTAssertEqual(RowClassifierV3.classify(label)?.key, "energy", label) }
        for (name, parent) in UKVocabulary.subRowParents {
            let match = RowClassifierV3.classify("of which " + name)
            XCTAssertTrue(match == nil || match?.fixedParent == parent || match?.fixedParent == nil, name)
        }
        for (prefix, row) in UKVocabulary.topLevelRows where row != "energy" && row != "sodium" && row != "salt" {
            XCTAssertNotNil(RowClassifierV3.classify(prefix), prefix)
        }
    }
}
