import Foundation
import Testing
@testable import NutritionLabelParsing

// Parser v3, PR 2 of `docs/pasted-nutrition-label-reader-v3.md` section 8: the stacked layout's
// sequence rule and template order (3.2), partial reading (3.8) and `too_little_read` (3.7);
// reader v3 tests 3 and 15, and test 6 on rows a stacked deviation leaves unread. Every fixture is
// synthetic: invented values, no names.

private let hash = String(repeating: "0", count: 64)
private func parse(_ text: String) -> LabelCaptureCandidate {
    NutritionLabelTextParserV3().parse(text, inputSHA256: hash)
}
private func value(_ candidate: LabelCaptureCandidate, _ nutrient: String, _ basis: LabelBasis = .per100g) -> String? {
    candidate.cells.first { $0.nutrient == nutrient && $0.basis == basis }?.decimalText
}
private func unread(_ candidate: LabelCaptureCandidate, _ reason: String) -> [String] {
    candidate.warnings.compactMap { $0.hasPrefix("row_not_read: \(reason): ") ? String($0.dropFirst("row_not_read: \(reason): ".count)) : nil }
}

private let head = "營養標示\n每一份量30公克\n本包裝含8份\n每份\n每100公克\n"
/// Label, then one value per column, in the official template order.
private let template: [(String, String, String)] = [
    ("熱量", "121大卡", "403大卡"), ("蛋白質", "3.1公克", "10.2公克"), ("脂肪", "4.3公克", "14.4公克"),
    ("飽和脂肪", "1.5公克", "5.6公克"), ("反式脂肪", "0.1公克", "0.3公克"), ("碳水化合物", "18.7公克", "62.3公克"),
    ("糖", "6.8公克", "22.7公克"), ("鈉", "61毫克", "203毫克"),
]
private func stacked(_ rows: [(String, String, String)] = template) -> String {
    head + rows.map { "\($0.0)\n\($0.1)\n\($0.2)" }.joined(separator: "\n") + "\n"
}

// MARK: 3.2: the regular sequence

@Test func test3ARegularStackedTableReadsInFull() {
    let candidate = parse(stacked())
    #expect(!candidate.declined, "\(candidate.declineReasons)")
    #expect(candidate.cells.count == 16)
    #expect(candidate.warnings.isEmpty, "\(candidate.warnings)")
    #expect(value(candidate, "sodium") == "203")
    #expect(value(candidate, "protein", .perServing) == "3.1")
}

@Test func test3OptionalRowsMayStandBetweenMandatoryRows() {
    var rows = template
    rows.insert(("膳食纖維", "2.9公克", "9.7公克"), at: 6)
    rows.insert(("膽固醇", "5毫克", "13毫克"), at: 3)
    rows.insert(("添加糖", "1.1公克", "3.6公克"), at: 9)
    let candidate = parse(stacked(rows))
    #expect(!candidate.declined)
    #expect(unread(candidate, "stacked_sequence").isEmpty, "\(candidate.warnings)")
    #expect(value(candidate, "fibre") == "9.7")
    #expect(value(candidate, "added_sugars") == "3.6")
    #expect(value(candidate, "sodium") == "203")
}

@Test func test3AnOutOfOrderMandatoryLabelIsTheFirstDeviation() {
    // Sugars and sodium exchanged, each label with its own values: sodium reads (its values
    // follow it); sugars comes after a row it should precede, so it (and every row after it) is
    // not read.
    var rows = template
    rows.swapAt(6, 7)
    let candidate = parse(stacked(rows))
    #expect(!candidate.declined)
    #expect(value(candidate, "sodium") == "203")
    #expect(value(candidate, "carbohydrate") == "62.3")
    #expect(unread(candidate, "stacked_sequence") == ["糖"])
    #expect(candidate.cells.count == 14)
    // A repeated mandatory row is a deviation too, and the duplicate rule then leaves the first
    // fat row unread as well.
    var repeated = template
    repeated.insert(("脂肪", "4.3公克", "14.4公克"), at: 7)
    let twice = parse(stacked(repeated))
    #expect(unread(twice, "stacked_sequence") == ["脂肪", "鈉"])
    #expect(value(twice, "fat") == nil)
    #expect(value(twice, "sodium") == nil)
    #expect(value(twice, "sugars") == "22.7")
    #expect(twice.warnings.contains("row_not_read: duplicate_row: 脂肪"))
}

@Test func test3LabelsAfterOrBeforeTheirValuesStopTheReading() {
    let regular = template.prefix(6).map { "\($0.0)\n\($0.1)\n\($0.2)" }.joined(separator: "\n")
    // The text layer prints the last two rows' values, then both labels: the values overflow the
    // carbohydrate row, which is the first deviation.
    let after = parse(head + regular + "\n6.8公克\n22.7公克\n61毫克\n203毫克\n糖\n鈉\n")
    #expect(unread(after, "stacked_sequence") == ["碳水化合物", "糖", "鈉"])
    #expect(value(after, "carbohydrate") == nil)
    #expect(value(after, "sugars") == nil)
    #expect(value(after, "trans_fat") == "0.3")
    #expect(!after.cells.contains { $0.decimalText == "6.8" || $0.decimalText == "61" })
    // A label block before its value block: a label followed directly by another label.
    let before = parse(head + regular + "\n糖\n鈉\n6.8公克\n22.7公克\n61毫克\n203毫克\n")
    #expect(unread(before, "stacked_sequence") == ["糖", "鈉"])
    #expect(value(before, "carbohydrate") == "62.3")
    // A label at the end with no values.
    let trailing = parse(stacked() + "膳食纖維\n")
    #expect(unread(trailing, "stacked_sequence") == ["膳食纖維"])
    #expect(value(trailing, "sodium") == "203")
    // Values after the last label.
    let extra = parse(stacked() + "9.9公克\n")
    #expect(unread(extra, "stacked_sequence") == ["鈉"])
    #expect(!extra.cells.contains { $0.decimalText == "9.9" })
}

@Test func test3ARowWithMoreOrFewerValuesThanColumnsIsADeviation() {
    // A dropped value: the next row's label follows after one value line.
    let dropped = parse(stacked().replacingOccurrences(of: "碳水化合物\n18.7公克\n62.3公克", with: "碳水化合物\n18.7公克"))
    #expect(unread(dropped, "stacked_sequence") == ["碳水化合物", "糖", "鈉"])
    #expect(value(dropped, "trans_fat") == "0.3")
    #expect(value(dropped, "carbohydrate", .perServing) == nil)
    #expect(!dropped.cells.contains { $0.decimalText == "6.8" })
    // Two values on one value line.
    let paired = parse(stacked().replacingOccurrences(of: "碳水化合物\n18.7公克\n62.3公克", with: "碳水化合物\n18.7公克 62.3公克"))
    #expect(unread(paired, "stacked_sequence").first == "碳水化合物")
    // A wrapped label that is not a recognised row is a label followed by a label.
    let wrapped = parse(stacked().replacingOccurrences(of: "糖\n6.8公克", with: "某某\n成分\n6.8公克"))
    #expect(unread(wrapped, "stacked_sequence").first == "某某 成分")
    // A wrapped recognised label is one label.
    let saturates = parse(stacked().replacingOccurrences(of: "飽和脂肪\n", with: "飽和\n脂肪\n"))
    #expect(unread(saturates, "stacked_sequence").isEmpty, "\(saturates.warnings)")
    #expect(value(saturates, "saturates") == "5.6")
}

@Test func test3EnergyInKilojoulesAndKilocaloriesAndStarredReferenceIntakesAreRegular() {
    // Energy printed in kJ and kcal, one value per line, grouped by unit as parser v2 groups it.
    let energy = parse(stacked().replacingOccurrences(of: "熱量\n121大卡\n403大卡", with: "熱量\n506kJ\n1686kJ\n121大卡\n403大卡"))
    #expect(unread(energy, "stacked_sequence").isEmpty, "\(energy.warnings)")
    #expect(value(energy, "energy_kcal") == "403")
    #expect(value(energy, "energy_kj") == "1686")
    // Three energy values for two columns is a deviation.
    let odd = parse(stacked().replacingOccurrences(of: "熱量\n121大卡\n403大卡", with: "熱量\n506kJ\n121大卡\n403大卡"))
    #expect(odd.declineReasons == ["too_little_read"], "the first row deviates, so nothing is read")
    #expect(ParseStateV3.stackedValuesAreRegular(RowDraftV3(label: "熱量", indented: false, values: [], labelLineHadValues: false, lines: [],
                                                            valueLines: [["kJ"], ["kcal"], ["kcal"]]), amountColumns: 2, referenceColumns: 0) == false)
    // A reference-intake column: `%` on its own line, or `*` for a row without a percentage.
    let reference = parse("營養標示\n每一份量30公克\n本包裝含8份\n每份\n每日參考值百分比\n熱量\n121大卡\n6%\n蛋白質\n3.1公克\n5%\n脂肪\n4.3公克\n7%\n"
                          + "反式脂肪\n0.1公克\n*\n碳水化合物\n18.7公克\n6%\n糖\n6.8公克\n*\n鈉\n61毫克\n3%\n")
    #expect(!reference.declined, "\(reference.declineReasons)")
    #expect(unread(reference, "stacked_sequence").isEmpty, "\(reference.warnings)")
    #expect(value(reference, "sodium", .perServing) == "61")
    #expect(value(reference, "sodium", .referenceIntake) == "3")
    #expect(value(reference, "sugars", .referenceIntake) == nil)
}

@Test func test3MixedInlineAndStackedBodiesDeclineLayoutAmbiguous() {
    let mixed = parse(stacked().replacingOccurrences(of: "脂肪\n4.3公克\n14.4公克", with: "脂肪 4.3公克 14.4公克"))
    #expect(mixed.declineReasons == ["layout_ambiguous"])
    // The inline kJ and kcal continuation stays inline (3.2 rule 5).
    let continued = parse("營養標示\n每一份量30公克\n本包裝含8份\n每100公克\n熱量 1686kJ\n403大卡\n蛋白質 10.2公克\n脂肪 14.4公克\n碳水化合物 62.3公克\n鈉 203毫克\n")
    #expect(!continued.declined, "\(continued.declineReasons)")
    #expect(value(continued, "energy_kcal") == "403")
}

@Test func test6ARowLeftUnreadByAStackedDeviationIsStillGateScanned() throws {
    let simplified = try #require(["这", "们", "说"].first { $0.unicodeScalars.allSatisfy(LabelDeclineGate.isSimplifiedOnly) })
    let after = template.prefix(6).map { "\($0.0)\n\($0.1)\n\($0.2)" }.joined(separator: "\n")
    // The marker or script sits in a row the deviation leaves unread.
    let marker = parse(head + after + "\n6.8公克\n22.7公克\n糖\n營養補充\n鈉\n61毫克\n203毫克\n")
    #expect(marker.declineReasons == ["not_a_food_nutrition_panel"], "\(marker.declineReasons)")
    let script = parse(head + after + "\n糖\n鈉\n6.8公克\n\(simplified)項\n22.7公克\n")
    #expect(script.declineReasons == ["unsupported_script"], "\(script.declineReasons)")
}

@Test func duplicatesCountRowsAfterAStackedDeviation() {
    // A sodium row unread after the deviation still makes a later sodium row unread.
    let text = head + template.prefix(6).map { "\($0.0)\n\($0.1)\n\($0.2)" }.joined(separator: "\n") + "\n糖\n鈉\n6.8公克\n22.7公克\n鈉\n61毫克\n203毫克\n"
    let candidate = parse(text)
    #expect(value(candidate, "sodium") == nil)
    #expect(value(candidate, "sodium", .perServing) == nil)
}

// MARK: 3.7: too little read (test 15)

@Test func test15TooLittleReadCountsMandatoryRowsWithACellInTheStoredColumn() {
    func inline(_ rows: [(String, String, String)], header: String = "每份 每100公克") -> String {
        "營養標示\n每一份量30公克\n本包裝含8份\n\(header)\n" + rows.map { "\($0.0) \($0.1) \($0.2)" }.joined(separator: "\n") + "\n"
    }
    // Five of eight read: not declined. Four: declined.
    #expect(!parse(inline(Array(template.prefix(5)))).declined)
    #expect(parse(inline(Array(template.prefix(4)))).declineReasons == ["too_little_read"])
    // Optional and not-stored rows never count.
    let optional = Array(template.prefix(4)) + [("膳食纖維", "2.9公克", "9.7公克"), ("添加糖", "1.1公克", "3.6公克"), ("膽固醇", "5毫克", "13毫克")]
    #expect(parse(inline(optional)).declineReasons == ["too_little_read"])
    // A row printed but not read does not count (here three rows in an off-template unit).
    var offTemplate = template
    for index in [1, 2, 3, 4] { offTemplate[index].1 = offTemplate[index].1.replacingOccurrences(of: "公克", with: "毫克")
                                offTemplate[index].2 = offTemplate[index].2.replacingOccurrences(of: "公克", with: "毫克") }
    #expect(parse(inline(offTemplate)).declineReasons == ["too_little_read"])
    // A stacked table that stops early: only the rows before the first deviation count.
    var early = template
    early.swapAt(2, 3)
    early.swapAt(0, 1)
    #expect(parse(stacked(early)).declineReasons == ["too_little_read"])
    // Energy counts in kJ (a cell in the stored column; its calculated kcal is not a cell).
    let kilojoules = [("熱量", "506kJ", "1686kJ")] + Array(template[1..<5])
    let kj = parse(inline(kilojoules))
    #expect(!kj.declined, "\(kj.declineReasons)")
    // Only the stored column counts: a row with a percentage only has no cell in it.
    let percentOnly = parse("營養標示\n每一份量30公克\n本包裝含8份\n每份 每日參考值百分比\n熱量 121大卡 6%\n蛋白質 3.1公克 5%\n脂肪 4.3公克 7%\n"
                            + "碳水化合物 18.7公克 6%\n鈉 3%\n")
    #expect(percentOnly.declineReasons == ["too_little_read"], "\(percentOnly.declineReasons)")
    // English tables are outside the Taiwan count.
    #expect(!parse("Per 100g\nEnergy 1500kJ\nFat 3g\n").declined)
    // The rule's constants.
    #expect(ParseStateV3.tooLittleReadMinimum == 5)
    #expect(TaiwanRowAliases.templateKeys.count == 8)
}
