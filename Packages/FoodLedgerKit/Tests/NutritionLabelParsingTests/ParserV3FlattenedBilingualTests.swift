import Foundation
import Testing
@testable import NutritionLabelParsing

// Parser v3, PR 3 of `docs/pasted-nutrition-label-reader-v3.md` section 8: one-line (flattened)
// tables (3.4), the basis printed only in the energy line (3.5), bilingual Chinese and English
// tables (3.6), the complete-panels decline (3.7, decision 8) and layout precedence with the
// flattened layout (3.0); reader v3 tests 1, 13, 14 and 16, and the review items carried over from
// PR 2. Every fixture is synthetic: invented values and names, modelled on layout shapes only.

private let hash = String(repeating: "0", count: 64)
private func parse(_ text: String) -> LabelCaptureCandidate {
    NutritionLabelTextParserV3().parse(text, inputSHA256: hash)
}
private func value(_ candidate: LabelCaptureCandidate, _ nutrient: String, _ basis: LabelBasis = .perServing) -> String? {
    candidate.cells.first { $0.nutrient == nutrient && $0.basis == basis }?.decimalText
}
private func unread(_ candidate: LabelCaptureCandidate, _ reason: String) -> [String] {
    candidate.warnings.compactMap { $0.hasPrefix("row_not_read: \(reason): ") ? String($0.dropFirst("row_not_read: \(reason): ".count)) : nil }
}
private let preamble = "營養標示\n每一份量30公克\n本包裝含8份\n"

// MARK: Carried over from the review and journey QA of PR 2

@Test func aWrappedTaiwanLabelKeepsTheCommaRule() {
    let body = "每份 每100公克\n熱量 120大卡 400大卡\n蛋白質 3.0公克 10.0公克\n脂肪 4.5公克 15.0公克\n飽和脂肪 1.5公克 5.0公克\n反式脂肪 0公克 0公克\n"
        + "碳水化\n合物 1,5公克 5,0公克\n糖 6.0公克 20.0公克\n鈉 60毫克 200毫克\n"
    let candidate = parse(preamble + body)
    #expect(!candidate.cells.contains { $0.nutrient == "carbohydrate" }, "\(candidate.cells.map(\.printedText))")
    #expect(unread(candidate, "ambiguous_number") == ["碳水化 合物"], "\(candidate.warnings)")
}

@Test func aCutNumberIsNeverShownAsALabel() {
    let base = preamble + "每份\n熱量 120大卡\n蛋白質 3.0公克\n脂肪 4.5公克\n飽和脂肪 1.5公克\n反式脂肪 0公克\n碳水化合物 18.0公克\n糖 6.0公克\n鈉 60毫克\n"
    for text in [base.replacingOccurrences(of: "熱量 120大卡\n", with: "熱量 120大卡\n502千焦\n"),
                 base.replacingOccurrences(of: "熱量 120大卡\n", with: "熱量 502千焦\n")] {
        let candidate = parse(text)
        #expect(!candidate.cells.contains { $0.nutrient.hasPrefix("energy") }, "\(candidate.cells.map(\.printedText))")
        #expect(unread(candidate, "malformed_value") == ["熱量"], "\(candidate.warnings)")
        for warning in candidate.warnings where warning.hasPrefix("row_not_read: ") {
            let label = warning.split(separator: ":").last.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
            #expect(label.first?.isNumber != true, "a number is never a label: \(warning)")
        }
        #expect(value(candidate, "protein") == "3.0")
    }
}

@Test func anEnglishFromPhraseIsNotADuplicateOfItsFirstWord() {
    let candidate = parse("Typical values\tPer 100g\nEnergy 1500kJ\nEnergy from fat 200kJ\nFat 3g\nCarbohydrate 50g\nProtein 7g\nSalt 0.5g\n")
    #expect(!candidate.declined, "\(candidate.declineReasons)")
    #expect(value(candidate, "energy_kj", .per100g) == "1500")
    #expect(unread(candidate, "duplicate_row").isEmpty, "\(candidate.warnings)")
    #expect(candidate.warnings.contains("unrecognised_row: Energy from fat"))
    // A real duplicate still is one.
    #expect(unread(parse("Typical values\tPer 100g\nEnergy 1500kJ\nEnergy 1400kJ\nFat 3g\n"), "duplicate_row") == ["Energy", "Energy"])
}

@Test func aDailyValueSuffixIsAReferenceCellNotALabel() {
    // (A line holding "% DV" or "Daily Value" is a header phrase, as in parser v2; the suffix
    // forms below reach the row rules.)
    let candidate = parse("Per serving\t% DV\nEnergy 200kcal\nFat 3g\n5% (DV)\nSodium 140mg\n6% of DV\nProtein 3g\n2% (DV)\n")
    #expect(unread(candidate, "value_before_label").isEmpty, "\(candidate.warnings)")
    #expect(candidate.cells.first { $0.nutrient == "sodium" && $0.basis == .referenceIntake }?.decimalText == "6")
    #expect(candidate.cells.first { $0.nutrient == "fat" && $0.basis == .referenceIntake }?.decimalText == "5")
    for line in ["5% DV", "5% 每日參考值百分比", "5%（每日參考值）", "5% Daily Value", "5% NRV"] {
        #expect(ParseStateV3.labelAfterValues(line, values: ParseStateV3.valueMatches(line)) == nil, "\(line)")
    }
    // A label after a gram value is still a label, and after a percentage a nutrient is one too.
    #expect(ParseStateV3.labelAfterValues("5g DV", values: ParseStateV3.valueMatches("5g DV")) == "DV")
    #expect(ParseStateV3.labelAfterValues("5% 鈉", values: ParseStateV3.valueMatches("5% 鈉")) == "鈉")
}

@Test func aTableWhoseRowsWereAllUnreadDeclinesTooLittleReadInEveryLanguage() {
    let english = parse("Typical values\tPer 100g\nEnergy 400kcal\n> 6mg Sodium\nProtein 3g\n")
    #expect(english.declineReasons == ["too_little_read"], "\(english.declineReasons)")
    #expect(parse("Typical values\tPer 100g\nCholesterol\n").declineReasons == ["no_table"])
}
