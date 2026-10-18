import Foundation
import Testing
@testable import NutritionLabelParsing

// Review fixes on PR #265: skipped states as hard declines, the fullwidth-digit limit of parser
// v2, table self-checks and conversion operand length. All fixtures are synthetic.

@Test func fullwidthDigitsFailValidationAndAreAHardDecline() throws {
    // Parser v2 matches `\d`, so fullwidth digits reach `decimal_text`; gate v2's schema allows
    // ASCII digits only, so the candidate is `failed_candidate`. A known parser v2 limit (contract
    // section 1); normalising fullwidth digits is follow-on parser work, not changed here.
    let text = """
    營養標示
    每一份量100公克
    本包裝含5份
    　　　　　　每100公克
    熱量　　　１５０大卡
    蛋白質　　11公克
    脂肪　　　8.8公克
    　飽和脂肪　1.2公克
    　反式脂肪　0公克
    碳水化合物　67公克
    　糖　　　9.1公克
    鈉　　　　8毫克
    """
    let candidate = NutritionLabelTextParser().parse(text, inputSHA256: String(repeating: "0", count: 64))
    #expect(!candidate.declined)
    #expect(candidate.cells.contains { $0.decimalText == "１５０" })
    #expect(!LabelDeclineGate.validationErrors(candidate).isEmpty)
    let (gated, report) = LabelDeclineGate.apply(candidate, format: .taiwan)
    #expect(gated == candidate)
    #expect(report.skipped == .failedCandidate)
    #expect(report.flags.isEmpty)
    #expect(report.hardDeclineCodes == ["unreadable_table"])
    #expect(!report.isUsable)
}

@Test func skippedStatesSplitIntoHardDeclinesAndFlags() {
    let declined = LabelCaptureCandidate.declined(route: "A", inputSHA256: String(repeating: "0", count: 64), language: .english, reasons: ["no_table"])
    let already = LabelDeclineGate.apply(declined, format: .uk).report
    #expect(already.skipped == .alreadyDeclined)
    #expect(already.hardDeclineCodes.isEmpty) // the parser's own reasons stand
    #expect(!already.isUsable)
    let none = LabelDeclineGate.apply(nil, format: .uk).report
    #expect(none.hardDeclineCodes == ["unreadable_table"])
    #expect(!none.isUsable)
}

@Test func tablesFailTheirSelfChecksInsteadOfLoadingWrongData() throws {
    let simplified = String(decoding: try LabelGateTables.resourceData(LabelDeclineGate.simplifiedOnlyTableResource), as: UTF8.self)
    let markers = String(decoding: try LabelGateTables.resourceData(LabelDeclineGate.markerClassesTableResource), as: UTF8.self)
    _ = try LabelGateTables(simplifiedOnlyText: simplified, markerClassesText: markers)
    var lines = simplified.split(separator: "\n").map(String.init)
    lines.swapAt(0, 1)
    #expect(throws: LabelGateTables.TableError.self) { try LabelGateTables(simplifiedOnlyText: lines.joined(separator: "\n"), markerClassesText: markers) }
    lines.swapAt(0, 1)
    #expect(throws: LabelGateTables.TableError.self) { try LabelGateTables(simplifiedOnlyText: (["0041"] + lines).joined(separator: "\n"), markerClassesText: markers) }
    #expect(throws: LabelGateTables.TableError.self) { try LabelGateTables(simplifiedOnlyText: lines.dropLast().joined(separator: "\n"), markerClassesText: markers) }
    let otherPattern = markers.replacingOccurrences(of: "caplets?", with: "capsules?")
    #expect(throws: LabelGateTables.TableError.self) { try LabelGateTables(simplifiedOnlyText: simplified, markerClassesText: otherPattern) }
    let noFold = markers.split(separator: "\n").filter { !$0.hasPrefix("fold 0073 ") }.joined(separator: "\n")
    #expect(throws: LabelGateTables.TableError.self) { try LabelGateTables(simplifiedOnlyText: simplified, markerClassesText: noFold) }
    #expect(LabelGateTables.shared != nil)
}

@Test func conversionOperandsLongerThanDecimalPrecisionAreRejected() {
    let longest = String(repeating: "1", count: 38)
    #expect(PastedLabelConversions.convert(.kjToKcal, operandText: longest, sourceHeaderID: "h", sourceRowID: "r") != nil)
    #expect(PastedLabelConversions.convert(.kjToKcal, operandText: longest + "1", sourceHeaderID: "h", sourceRowID: "r") == nil)
    #expect(PastedLabelConversions.convert(.kjToKcal, operandText: "0.000" + longest, sourceHeaderID: "h", sourceRowID: "r") != nil)
}
