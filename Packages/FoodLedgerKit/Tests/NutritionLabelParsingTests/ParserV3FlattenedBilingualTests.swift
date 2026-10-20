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

/// One column per serving, the template on one line, the given separator between rows.
private func flat(_ separator: String, prefix: String = "每份 ", rows: [String]? = nil) -> String {
    let body = rows ?? ["熱量 121大卡", "蛋白質 3.1公克", "脂肪 4.3公克", "飽和脂肪 1.5公克", "反式脂肪 0.1公克", "碳水化合物 18.7公克", "糖 6.8公克",
                        "鈉 61毫克"]
    return preamble + prefix + body.joined(separator: separator) + "\n"
}

private let template: [(String, String)] = [("energy_kcal", "121"), ("protein", "3.1"), ("fat", "4.3"), ("saturates", "1.5"),
                                            ("trans_fat", "0.1"), ("carbohydrate", "18.7"), ("sugars", "6.8"), ("sodium", "61")]

// MARK: 3.4: flattened lines read when the segmentation is unambiguous

@Test func test1AFlattenedLineReadsInEachSeparatorFamily() {
    for separator in [" / ", "，", "、", ", ", "；", " ", "/"] {
        let candidate = parse(flat(separator))
        #expect(!candidate.declined, "\(separator): \(candidate.declineReasons)")
        for (nutrient, expected) in template {
            #expect(value(candidate, nutrient) == expected, "\(separator) \(nutrient)")
        }
        #expect(candidate.warnings.isEmpty, "\(separator): \(candidate.warnings)")
        #expect(candidate.language == .traditionalChinese)
        #expect(candidate.servingSize?.decimalText == "30")
    }
    // The basis stuck to the first label, sub-rows in brackets (classified by the alias table,
    // never by position), and a sentence ending with 。.
    let sentence = parse(preamble + "每份熱量121大卡、蛋白質3.1公克、脂肪4.3公克（飽和脂肪1.5公克／反式脂肪0.1公克）、碳水化合物18.7公克（糖6.8公克）、鈉61毫克。\n")
    #expect(!sentence.declined, "\(sentence.declineReasons)")
    for (nutrient, expected) in template { #expect(value(sentence, nutrient) == expected, "\(nutrient)") }
    #expect(sentence.cells.first { $0.nutrient == "saturates" }?.parentRowID == "fat")
    #expect(sentence.cells.first { $0.nutrient == "sugars" }?.parentRowID == "carbohydrate")
    // A basis phrase, a dash, then items separated by `/`.
    let dashed = parse(preamble + "每100公克 - 熱量 389大卡/蛋白質 7.4公克/脂肪 12.6公克/飽和脂肪 4.2公克/反式脂肪 0.2公克/碳水化合物 64.1公克/糖 21.8公克/鈉 1187毫克\n")
    #expect(!dashed.declined, "\(dashed.declineReasons)")
    #expect(value(dashed, "sodium", .per100g) == "1187")
    // A header line, then two values per row separated by ` / `.
    let twoColumns = parse(preamble + "每份 / 每100毫升\n熱量 50大卡 / 100大卡、蛋白質 1.0公克 / 2.0公克、脂肪 1.5公克 / 3.0公克、飽和脂肪 0.5公克 / 1.0公克、"
        + "反式脂肪 0公克 / 0公克、碳水化合物 6.5公克 / 13.0公克、糖 6.0公克 / 12.0公克、鈉 20毫克 / 40毫克\n")
    #expect(!twoColumns.declined, "\(twoColumns.declineReasons)")
    #expect(value(twoColumns, "carbohydrate", .per100ml) == "13.0")
    #expect(value(twoColumns, "carbohydrate", .perServing) == "6.5")
    // The item column heading, the bases and the rows, separated only by spaces.
    let spaced = parse(preamble + "項目 每份 每100毫升 熱量 50大卡 100大卡 蛋白質 1.0公克 2.0公克 脂肪 1.5公克 3.0公克 飽和脂肪 0.5公克 1.0公克 "
        + "反式脂肪 0公克 0公克 碳水化合物 6.5公克 13.0公克 糖 6.0公克 12.0公克 鈉 20毫克 40毫克\n")
    #expect(!spaced.declined, "\(spaced.declineReasons)")
    #expect(value(spaced, "sodium", .per100ml) == "40")
    #expect(spaced.headers.map(\.printedText) == ["每份", "每100毫升"])
    // A unit stuck to the next label is well-formed (what follows the unit is a label).
    let stuck = parse(preamble + "每份 熱量121大卡蛋白質3.1公克脂肪4.3公克飽和脂肪1.5公克反式脂肪0.1公克碳水化合物18.7公克糖6.8公克鈉61毫克\n")
    #expect(!stuck.declined, "\(stuck.declineReasons)")
    for (nutrient, expected) in template { #expect(value(stuck, nutrient) == expected, "stuck \(nutrient)") }
    // Serving and pack phrases on the line itself, before the first row.
    let sameLine = parse("營養標示 每一份量30公克 本包裝含8份 每份 熱量 121大卡，蛋白質 3.1公克，脂肪 4.3公克，飽和脂肪 1.5公克，反式脂肪 0.1公克，"
        + "碳水化合物 18.7公克，糖 6.8公克，鈉 61毫克\n")
    #expect(!sameLine.declined, "\(sameLine.declineReasons)")
    #expect(sameLine.servingSize?.decimalText == "30")
    #expect(sameLine.servingsPerPack?.decimalText == "8")
    #expect(value(sameLine, "sodium") == "61")
}

@Test func flattenedLinesKeepTheirTitleDecorationAndTitleBracketOutOfTheRows() {
    // A decorated title, a colon, the basis, a dash, then the rows separated by `/`.
    let decorated = parse("◎營養標示：每100公克-熱量389大卡/蛋白質7.4公克/脂肪12.6公克/飽和脂肪4.2公克/反式脂肪0.2公克/碳水化合物64.1公克/糖21.8公克/鈉1187毫克\n")
    #expect(!decorated.declined, "\(decorated.declineReasons)")
    #expect(value(decorated, "energy_kcal", .per100g) == "389")
    #expect(value(decorated, "sodium", .per100g) == "1187")
    // A title with a bracket naming the energy row, then the serving and pack phrases, the item
    // heading and the bases, all on one line with the rows.
    let titled = parse("營養標示(熱量)\t每一份量 250 毫升 本包裝含 7.4 份 項目 每份 每100毫升 熱量 160 大卡 64 大卡 蛋白質 8.0 公克 3.2 公克 "
        + "脂肪 9.0 公克 3.6 公克 　飽和脂肪 6.0 公克 2.4 公克 　反式脂肪 0 公克 0 公克 碳水化合物 12.5 公克 5.0 公克 　糖 12.5 公克 5.0 公克 "
        + "鈉 110 毫克 44 毫克 鈣 250 毫克 100 毫克\n")
    #expect(!titled.declined, "\(titled.declineReasons)")
    #expect(titled.servingSize?.decimalText == "250")
    #expect(titled.servingsPerPack?.decimalText == "7.4")
    #expect(value(titled, "fat", .per100ml) == "3.6")
    #expect(titled.cells.contains { $0.nutrient == "unrecognised" && $0.printedLabel == "鈣" })
    // A bracket holding a digit is never part of the title: it is a stray number.
    #expect(parse("營養標示(2)\t每份 熱量 160大卡 蛋白質 8.0公克 脂肪 9.0公克 碳水化合物 12.5公克 鈉 110毫克\n").declineReasons == ["flattened_table_ambiguous"])
}

/// PR 3 review (low): a bound word stuck to a flattened label is never part of the label, and its
/// row is never read as exact; 其中 before an exact alias names the row.
@Test func flattenedLabelsDropStuckBoundWordsAndTheOfWhichPrefix() {
    let header = preamble + "每份 每100公克 "
    let rows = ["熱量 121大卡 403大卡", "蛋白質 3.1公克 10.2公克", "脂肪 4.3公克 14.4公克", "飽和脂肪 1.5公克 5.0公克", "反式脂肪 0公克 0公克",
                "碳水化合物 18.7公克 62.3公克", "糖 6.8公克 22.7公克", "鈉 50毫克 167毫克"]
    for (original, stuck, label) in [("鈉 50毫克 167毫克", "鈉超過50毫克 167毫克", "鈉"), ("糖 6.8公克 22.7公克", "糖未滿0.5公克 1.7公克", "糖"),
                                     ("鈉 50毫克 167毫克", "鈉以下50毫克 167毫克", "鈉")] {
        let candidate = parse(header + rows.map { $0 == original ? stuck : $0 }.joined(separator: "，") + "\n")
        #expect(!candidate.cells.contains { $0.printedLabel.contains(label) && $0.printedLabel != label }, "\(stuck)")
        #expect(!candidate.cells.contains { $0.printedLabel == label }, "\(stuck): \(candidate.cells.map(\.printedText))")
        #expect(unread(candidate, "unexplained_bound") == [label], "\(stuck): \(candidate.warnings)")
    }
    let ofWhich = parse(header + rows.map { $0.hasPrefix("飽和脂肪") ? "其中飽和脂肪 2公克 6.7公克" : $0 }.joined(separator: "，") + "\n")
    #expect(value(ofWhich, "saturates") == "2")
    #expect(value(ofWhich, "saturates", .per100g) == "6.7")
    #expect(ofWhich.cells.first { $0.nutrient == "saturates" }?.parentRowID == "fat")
    // Only an exact alias after 其中: anything else stays an unrecognised row.
    #expect(FlattenedLine.normalisedLabel("其中不飽和脂肪") == "其中不飽和脂肪")
}

@Test func aRecognisedLabelPrintedAgainstItsNumberReadsAsIfSpaced() {
    #expect(ParseStateV3.spacedLabel("熱量51大卡") == "熱量 51大卡")
    #expect(ParseStateV3.spacedLabel("飽和脂肪0.3公克") == "飽和脂肪 0.3公克")
    #expect(ParseStateV3.spacedLabel("不飽和脂肪0公克") == "不飽和脂肪 0公克", "a not-stored row stays its own row")
    #expect(ParseStateV3.spacedLabel("其中飽和脂肪3公克") == "其中飽和脂肪3公克", "never a prefix or substring")
    #expect(ParseStateV3.spacedLabel("每100公克") == "每100公克")
    let stuck = parse("營養標示\n每一份量30公克\n本包裝含8份\n每份\n熱量120大卡\n蛋白質3.0公克\n脂肪4.5公克\n不飽和脂肪2.0公克\n飽和脂肪1.5公克\n反式脂肪0公克\n"
        + "碳水化合物18.0公克\n糖6.0公克\n鈉60毫克\n")
    #expect(!stuck.declined, "\(stuck.declineReasons)")
    #expect(value(stuck, "saturates") == "1.5")
    #expect(stuck.cells.first { $0.printedLabel == "不飽和脂肪" }?.nutrient == "unrecognised")
}

/// Reader v3 test 1: every digit run outside a well-formed value, serving, pack or basis token
/// makes its row unread, or declines `flattened_table_ambiguous` outside a row.
@Test func test1EveryDigitRunBelongsToAWellFormedTokenOrItsRowIsUnread() {
    func rows(replacing original: String, with replacement: String) -> [String] {
        ["熱量 121大卡", "蛋白質 3.1公克", "脂肪 4.3公克", "飽和脂肪 1.5公克", "反式脂肪 0.1公克", "碳水化合物 18.7公克", "糖 6.8公克", "鈉 1203毫克"]
            .map { $0 == original ? replacement : $0 }
    }
    // Thousands separators in every form: the leading group is a malformed token of its own, so a
    // one-column row has two tokens and the segmentation fails.
    for separated in ["鈉 1,203毫克", "鈉 1，203毫克", "鈉 1 203毫克"] {
        let candidate = parse(flat(" / ", rows: rows(replacing: "鈉 1203毫克", with: separated)))
        #expect(candidate.declineReasons == ["flattened_table_ambiguous"], "\(separated): \(candidate.declineReasons) \(candidate.cells.map(\.printedText))")
    }
    // Inside a two-column row (the leading group and the value fill the two columns), the row is
    // not read; the other rows read.
    let header = preamble + "每份 每100公克\n"
    let two = ["熱量 121大卡 403大卡", "蛋白質 3.1公克 10.2公克", "脂肪 4.3公克 14.4公克", "飽和脂肪 1.5公克 5.6公克", "反式脂肪 0.1公克 0.3公克",
               "碳水化合物 18.7公克 62.3公克", "糖 6.8公克 22.7公克"]
    for separated in ["鈉 1,203毫克", "鈉 1，203毫克", "鈉 1 203毫克"] {
        let candidate = parse(header + (two + [separated]).joined(separator: "、") + "\n")
        #expect(!candidate.declined, "\(separated): \(candidate.declineReasons)")
        #expect(!candidate.cells.contains { $0.nutrient == "sodium" }, "\(separated)")
        #expect(unread(candidate, "malformed_value") == ["鈉"], "\(separated): \(candidate.warnings)")
        #expect(value(candidate, "sugars", .per100g) == "22.7")
    }
    for (name, row) in [("two decimal points", "脂肪 4.3.1公克"), ("no unit", "脂肪 4.3"), ("full-width digits", "脂肪 ４.３公克"),
                        ("two values with no separator", "脂肪 4.3公克1公克"), ("more than", "脂肪 >4.3公克"), ("at least", "脂肪 4.3公克以上"),
                        ("a unit followed by a digit", "脂肪 4.3公克5")] {
        let candidate = parse(flat("，", rows: rows(replacing: "脂肪 4.3公克", with: row)))
        #expect(!candidate.cells.contains { $0.nutrient == "fat" }, "\(name): \(candidate.cells.map(\.printedText))")
        if !candidate.declined {
            #expect(unread(candidate, "malformed_value") == ["脂肪"], "\(name): \(candidate.warnings)")
            #expect(value(candidate, "protein") == "3.1", "\(name)")
        }
    }
    // A stray number between rows, a `%` outside any row, and a number before the first label.
    for (name, text) in [("stray number", flat("，", rows: rows(replacing: "脂肪 4.3公克", with: "脂肪 4.3公克，7"))),
                         ("stray value", flat("，", rows: rows(replacing: "脂肪 4.3公克", with: "脂肪 4.3公克 500公克"))),
                         ("percent outside a row", flat("，", rows: rows(replacing: "脂肪 4.3公克", with: "脂肪 4.3公克 6%"))),
                         ("number before the first label", flat("，", prefix: "每份 12 "))] {
        #expect(parse(text).declineReasons == ["flattened_table_ambiguous"], "\(name): \(parse(text).declineReasons)")
    }
    // `%` on some rows only: no reference header printed, or not on every row.
    let percentOnSome = flat("，", rows: rows(replacing: "鈉 1203毫克", with: "鈉 1203毫克 50%"))
    #expect(parse(percentOnSome).declineReasons == ["flattened_table_ambiguous"])
    let referenceHeader = preamble + "每份 每日參考值百分比 熱量 121大卡 6%，蛋白質 3.1公克 5%，脂肪 4.3公克 7%，飽和脂肪 1.5公克 8%，反式脂肪 0.1公克 *，"
        + "碳水化合物 18.7公克 6%，糖 6.8公克 *，鈉 61毫克 3%\n"
    let reference = parse(referenceHeader)
    #expect(!reference.declined, "\(reference.declineReasons)")
    #expect(reference.cells.first { $0.nutrient == "sodium" && $0.basis == .referenceIntake }?.decimalText == "3")
    #expect(value(reference, "sodium") == "61")
    let missingPercent = parse(referenceHeader.replacingOccurrences(of: "蛋白質 3.1公克 5%", with: "蛋白質 3.1公克"))
    #expect(missingPercent.declineReasons == ["flattened_table_ambiguous"])
    let percentFirst = parse(referenceHeader.replacingOccurrences(of: "蛋白質 3.1公克 5%", with: "蛋白質 5% 3.1公克"))
    #expect(percentFirst.declineReasons == ["flattened_table_ambiguous"])
    // An unknown row with the right count is an unrecognised row (read but not used); with the
    // wrong count the line declines.
    let unknown = parse(flat("，", rows: rows(replacing: "糖 6.8公克", with: "糖 6.8公克，膽固醇 13毫克")))
    #expect(!unknown.declined)
    #expect(unknown.cells.contains { $0.nutrient == "unrecognised" && $0.printedLabel == "膽固醇" })
    #expect(parse(flat("，", rows: rows(replacing: "糖 6.8公克", with: "糖 6.8公克，膽固醇 13毫克 5毫克"))).declineReasons == ["flattened_table_ambiguous"])
    // A Latin word that is not a unit is not part of a clean flattened table.
    #expect(parse(flat("，", rows: rows(replacing: "糖 6.8公克", with: "糖 Sugars 6.8公克"))).declineReasons == ["flattened_table_ambiguous"])
    // No value is ever bound from a declined or unread row.
    #expect(FlattenedLine.read("熱量 1公克", existingHeaders: [.perServing]) == .notFlattened)
}

@Test func aFlattenedLineThatIsTwoPanelsOrMixedWithOtherLayoutsDeclines() {
    // A basis phrase after the first label: a second panel on the same line.
    let secondBasis = parse(flat("，").replacingOccurrences(of: "，鈉", with: "，每100公克 鈉"))
    #expect(secondBasis.declineReasons == ["multiple_panels"])
    // A flattened line beside inline rows matches no single layout.
    let mixed = parse(flat("，") + "膳食纖維 2.0公克\n")
    #expect(mixed.declineReasons == ["layout_ambiguous"])
    // Two flattened lines without a basis of their own (the table split over two lines).
    let split = parse(preamble + "每份\n熱量 121大卡，蛋白質 3.1公克，脂肪 4.3公克，飽和脂肪 1.5公克\n反式脂肪 0.1公克，碳水化合物 18.7公克，糖 6.8公克，鈉 61毫克\n")
    #expect(split.declineReasons == ["layout_ambiguous"])
    // Without a basis phrase anywhere, the basis is not guessed (3.3 until PR 4).
    #expect(parse(flat("，", prefix: "")).declineReasons == ["no_basis_header"])
}

// MARK: 3.7, decision 8: two complete panels

@Test func twoCompletePanelsDeclineWithTheirOwnCode() {
    let one = "每份 熱量 121大卡，蛋白質 3.1公克，脂肪 4.3公克，飽和脂肪 1.5公克，反式脂肪 0.1公克，碳水化合物 18.7公克，糖 6.8公克，鈉 61毫克"
    let other = "每份 熱量 135大卡，蛋白質 2.9公克，脂肪 5.1公克，飽和脂肪 2.2公克，反式脂肪 0公克，碳水化合物 19.4公克，糖 8.1公克，鈉 48毫克"
    let flavours = parse(preamble + "原味\n" + one + "\n可可口味\n" + other + "\n")
    #expect(flavours.declineReasons == [NutritionLabelTextParserV3.multipleCompletePanelsCode], "\(flavours.declineReasons)")
    #expect(flavours.cells.isEmpty)
    // Two multi-line panels, each with its own title.
    let table = "營養標示\n每一份量30公克\n本包裝含8份\n每份 每100公克\n熱量 120大卡 400大卡\n蛋白質 3.0公克 10.0公克\n脂肪 4.5公克 15.0公克\n"
        + "飽和脂肪 1.5公克 5.0公克\n反式脂肪 0公克 0公克\n碳水化合物 18.0公克 60.0公克\n糖 6.0公克 20.0公克\n鈉 60毫克 200毫克\n"
    #expect(parse(table + table).declineReasons == [NutritionLabelTextParserV3.multipleCompletePanelsCode])
    // Journey QA of #283: heading lines (flavour names) before each multi-line panel's title.
    let panel = "營養標示\n每100公克\n熱量 400大卡\n蛋白質 8公克\n脂肪 12公克\n飽和脂肪 4公克\n反式脂肪 0公克\n碳水化合物 62公克\n糖 20公克\n鈉 300毫克\n"
    #expect(parse("原味\n" + panel + "辣味\n" + panel.replacingOccurrences(of: "400大卡", with: "410大卡")).declineReasons
        == [NutritionLabelTextParserV3.multipleCompletePanelsCode])
    #expect(NutritionLabelTextParserV3.headingStart(["原味", "營養標示", "熱量 1大卡", "辣味", "", "營養標示"], before: 5) == 3)
    #expect(NutritionLabelTextParserV3.headingStart(["營養標示", "熱量 1大卡", "鈉", "營養標示"], before: 3) == 3, "a row label is never a heading")
    // A heading line before a single panel's title does not start a panel.
    let headed = parse("原味\n" + panel)
    #expect(!headed.declined, "\(headed.declineReasons)")
    // A second header with no rows after it is not a complete panel: the plain decline stays.
    #expect(parse(table + "每份 每100公克\n").declineReasons == ["multiple_panels"])
    // Each panel alone reads.
    #expect(!parse(preamble + one + "\n").declined)
}

// MARK: 3.5: basis printed only in the energy line (test 14)

/// Decision 23 (owner, 20 October 2026: ask the user). A basis printed only inside the energy
/// line is never read as the column's basis: the table has no basis header and declines
/// `no_basis_header` as today, carrying the bracket as printed in a `basis_hint` warning for the
/// basis-choice sheet of PR 4 (a hint, never preselected). Nothing is bound.
@Test func test14ABasisPrintedOnlyInTheEnergyLineIsAHintNeverABasis() {
    let body = "熱量 45大卡(每100毫升)\n蛋白質 1.2公克\n脂肪 1.5公克\n>>飽和脂肪 0.9公克\n>>反式脂肪 0公克\n碳水化合物 6.4公克\n>>糖 6.1公克\n鈉 38毫克\n"
    let hinted = parse("營養標示\n" + body)
    #expect(hinted.declineReasons == ["no_basis_header"])
    #expect(hinted.cells.isEmpty)
    #expect(hinted.headers.isEmpty)
    #expect(hinted.warnings == ["basis_hint: energy_line: (每100毫升)"])
    #expect(LabelDeclineGate.validationErrors(hinted).isEmpty, "a declined candidate may carry the hint")
    // The label printed against its number, a bullet and `>>` sub-row markers: the same hint.
    let stuck = parse("營養標示\n\n▲熱量45大卡(每100毫升)\n蛋白質1.2公克\n脂肪1.5公克\n　>>飽和脂肪0.9公克\n　>>反式脂肪0公克\n碳水化合物6.4公克\n　>>糖6.1公克\n鈉38毫克")
    #expect(stuck.declineReasons == ["no_basis_header"])
    #expect(stuck.warnings == ["basis_hint: energy_line: (每100毫升)"])
    // Without the bracket the table declines the same way, with no hint.
    let plain = parse("營養標示\n" + body.replacingOccurrences(of: "(每100毫升)", with: ""))
    #expect(plain.declineReasons == ["no_basis_header"])
    #expect(plain.warnings.isEmpty)
    // A basis phrase on a later row, on a first row that is not energy, or more than one, declines.
    #expect(parse("營養標示\n" + body.replacingOccurrences(of: "鈉 38毫克", with: "鈉 38毫克(每份)")).declineReasons == ["multiple_panels"])
    #expect(parse("營養標示\n蛋白質 1.2公克(每100毫升)\n熱量 45大卡\n脂肪 1.5公克\n").declineReasons == ["multiple_panels"])
    #expect(parse("營養標示\n熱量 45大卡(每100毫升)(每份)\n蛋白質 1.2公克\n").declineReasons == ["multiple_panels"])
    // With a header line printed, a bracket on the energy row is a second basis.
    #expect(parse("營養標示\n每份\n熱量 45大卡(每100毫升)\n蛋白質 1.2公克\n").declineReasons == ["multiple_panels"])
}

/// PR 3 review: the bracket inside the energy label (`熱量(每100毫升) 45大卡`) is the same case. The
/// line is a row, never a header line, so energy is never dropped silently: with no header line
/// it is the hint and `no_basis_header`; with a header line naming the same basis the bracket
/// repeats it and the row reads; with another basis it declines.
@Test func anEnergyBasisBracketInsideTheLabelNeverDropsTheEnergyRow() {
    let rest = "蛋白質 1.2公克\n脂肪 1.5公克\n飽和脂肪 0.9公克\n反式脂肪 0公克\n碳水化合物 6.4公克\n糖 6.1公克\n鈉 38毫克\n"
    // Journey QA of #283: both bracket positions on a first energy row, without a title too.
    for line in ["熱量(每100公克) 400大卡", "熱量 400大卡(每100公克)"] {
        let qa = parse(line + "\n蛋白質 8公克\n脂肪 12公克\n飽和脂肪 4公克\n反式脂肪 0公克\n碳水化合物 62公克\n糖 20公克\n鈉 300毫克\n")
        #expect(qa.declineReasons == ["no_basis_header"], "\(line)")
        #expect(qa.warnings == ["basis_hint: energy_line: (每100公克)"], "\(line)")
    }
    let first = parse("營養標示\n熱量(每100毫升) 45大卡\n" + rest)
    #expect(first.declineReasons == ["no_basis_header"])
    #expect(first.warnings == ["basis_hint: energy_line: (每100毫升)"])
    let headed = parse("營養標示\n每100毫升\n熱量(每100毫升) 45大卡\n" + rest)
    #expect(!headed.declined, "\(headed.declineReasons)")
    #expect(value(headed, "energy_kcal", .per100ml) == "45")
    #expect(headed.wouldMarkReady)
    #expect(parse("營養標示\n每份\n熱量(每100毫升) 45大卡\n" + rest).declineReasons == ["multiple_panels"])
    // Never ready with energy silently missing.
    for text in [first, headed] where !text.declined {
        #expect(text.cells.contains { $0.nutrient == "energy_kcal" })
    }
}

/// The case behind decision 23: a per 100 g bracket over values that are really per serving.
/// Under the earlier wording of 3.5 it was read per 100 g with no check able to see it; now it is
/// never read without the user's choice.
@Test func test14APer100BracketOverPerServingValuesIsNeverReadWithoutTheUsersChoice() {
    for energy in ["熱量 400大卡(每100公克)", "熱量 120大卡(每100公克)"] {
        let candidate = parse(preamble + energy + "\n蛋白質 3.0公克\n脂肪 4.5公克\n飽和脂肪 1.5公克\n反式脂肪 0公克\n碳水化合物 18.0公克\n糖 6.0公克\n鈉 60毫克\n")
        #expect(candidate.declineReasons == ["no_basis_header"], "\(energy)")
        #expect(candidate.cells.isEmpty)
        #expect(candidate.warnings == ["basis_hint: energy_line: (每100公克)"])
    }
}

// MARK: 3.6: bilingual tables (test 16)

private let bilingual = """
營養標示 Nutrition Facts
每一份量 Serving Size 30公克
本包裝含8份 (8 Servings Per Package)
每份 Per Serving 每100公克 Per 100g
熱量 Calories 121(kcal)大卡 403(kcal)大卡
蛋白質 Protein 3.1(g)公克 10.2(g)公克
脂肪 Total Fat 4.3(g)公克 14.4(g)公克
飽和脂肪 Saturated Fat 1.5(g)公克 5.6(g)公克
反式脂肪 Trans Fat 0.1(g)公克 0.3(g)公克
碳水化合物 Total Carbohydrate 18.7(g)公克 62.3(g)公克
糖 Sugars 6.8(g)公克 22.7(g)公克
鈉 Sodium 61(mg)毫克 203(mg)毫克

"""

@Test func test16ABilingualTableReadsByItsChineseLabelsAndIsTaiwan() {
    let candidate = parse(bilingual)
    #expect(!candidate.declined, "\(candidate.declineReasons)")
    #expect(candidate.language == .traditionalChinese, "the Chinese labels decide; the US title words do not route it to US")
    #expect(LabelFormatInference.infer(candidate) == .taiwan)
    #expect(candidate.cells.count == 16)
    #expect(value(candidate, "fat", .per100g) == "14.4")
    #expect(candidate.cells.first { $0.nutrient == "fat" && $0.basis == .per100g }?.printedText == "14.4(g)公克", "printed as printed")
    #expect(candidate.cells.first { $0.nutrient == "fat" }?.canonicalUnit == "g")
    #expect(candidate.headers.map(\.basis) == [.perServing, .per100g])
    #expect(candidate.warnings.isEmpty, "\(candidate.warnings)")
    // An unknown gloss is ignored; the unit pair is one value when both units agree.
    let unknownGloss = parse(bilingual.replacingOccurrences(of: "糖 Sugars", with: "糖 Sugar content"))
    #expect(value(unknownGloss, "sugars") == "6.8")
}

@Test func test16AConflictingGlossOrUnitPairLeavesTheRowUnread() {
    let gloss = parse(bilingual.replacingOccurrences(of: "脂肪 Total Fat", with: "脂肪 Protein"))
    #expect(!gloss.declined)
    #expect(!gloss.cells.contains { $0.nutrient == "fat" })
    #expect(unread(gloss, "gloss_conflict") == ["脂肪 Protein"])
    #expect(value(gloss, "protein") == "3.1")
    let bracketed = parse(bilingual.replacingOccurrences(of: "糖 Sugars", with: "糖(Sodium)"))
    #expect(unread(bracketed, "gloss_conflict") == ["糖(Sodium)"])
    let pair = parse(bilingual.replacingOccurrences(of: "4.3(g)公克", with: "4.3(mg)公克"))
    #expect(!pair.cells.contains { $0.nutrient == "fat" })
    #expect(unread(pair, "unit_pair_mismatch") == ["脂肪 Total Fat"])
    let energy = parse(bilingual.replacingOccurrences(of: "121(kcal)大卡", with: "121(kJ)大卡"))
    #expect(!energy.cells.contains { $0.nutrient.hasPrefix("energy") })
}

@Test func test16AConflictingEnglishHeaderDeclines() {
    #expect(parse(bilingual.replacingOccurrences(of: "每份 Per Serving 每100公克 Per 100g", with: "每份 Per 100g 每100公克 Per Serving"))
        .declineReasons == ["multiple_panels"])
    #expect(parse(bilingual.replacingOccurrences(of: "每份 Per Serving 每100公克 Per 100g", with: "每份(Per 100ml)  每100公克(Per 100g)"))
        .declineReasons == ["multiple_panels"])
    // A header with bracketed English bases and a bracketed weight is a header line, never a row.
    let bracketed = parse(bilingual.replacingOccurrences(of: "每份 Per Serving 每100公克 Per 100g", with: "每份(Amount Per Serving)\t 每100公克(100g)"))
    #expect(!bracketed.declined, "\(bracketed.declineReasons)")
    #expect(bracketed.headers.map(\.basis) == [.perServing, .per100g])
    // An English part naming no basis is ignored.
    let plain = parse(bilingual.replacingOccurrences(of: "每份 Per Serving 每100公克 Per 100g", with: "每份 Amount  每100公克 Amount"))
    #expect(!plain.declined, "\(plain.declineReasons)")
    #expect(plain.headers.map(\.basis) == [.perServing, .per100g])
}

@Test func test16AboutInEitherLanguageMakesThePackApproximateAndTheBracketNeverBinds() {
    let about = parse(bilingual.replacingOccurrences(of: "本包裝含8份 (8 Servings Per Package)", with: "本包裝含8份 (about 8 servings)"))
    #expect(about.servingsPerPack?.decimalText == "8")
    #expect(about.servingsPerPack?.approximate == true)
    let chinese = parse(bilingual.replacingOccurrences(of: "本包裝含8份 (8 Servings Per Package)", with: "本包裝含約8份 (8 servings)"))
    #expect(chinese.servingsPerPack?.approximate == true)
    let exact = parse(bilingual.replacingOccurrences(of: "本包裝含8份 (8 Servings Per Package)", with: "本包裝含8份 (8 servings)"))
    #expect(exact.servingsPerPack?.approximate == false)
    // An English bracket never supplies the serving size: when it prints another quantity the
    // serving size is not read at all (PR 3 review: never pick one of two quantities).
    let bracket = parse(bilingual.replacingOccurrences(of: "每一份量 Serving Size 30公克", with: "每一份量30公克 (about 25g)"))
    #expect(bracket.servingSize?.decimalText == nil)
    #expect(bracket.warnings.contains("bilingual_quantity_conflict: serving_size"))
    let agreeing = parse(bilingual.replacingOccurrences(of: "每一份量 Serving Size 30公克", with: "每一份量30公克 (Serving size 30g)"))
    #expect(agreeing.servingSize?.decimalText == "30")
    let onlyEnglish = parse(bilingual.replacingOccurrences(of: "每一份量 Serving Size 30公克", with: "每一份量1包 (about 30g)"))
    #expect(onlyEnglish.servingSize?.decimalText == nil)
}

/// PR 3 review (medium): a serving or pack line holding Chinese and English quantities that
/// disagree, in either order and bracketed or not, is not read; the English quantity is never
/// bound. Agreeing quantities read as before.
@Test func aBilingualServingOrPackLineWithDisagreeingQuantitiesIsNotRead() {
    for line in ["Serving size 25g 每一份量 30公克", "每一份量 30公克 Serving size 25g", "每一份量30公克 (Serving size 25g)", "Serving size 30g 每一份量 30毫升"] {
        let candidate = parse(bilingual.replacingOccurrences(of: "每一份量 Serving Size 30公克", with: line))
        #expect(candidate.servingSize?.decimalText == nil, "\(line): \(String(describing: candidate.servingSize))")
        #expect(candidate.warnings.contains("bilingual_quantity_conflict: serving_size"), "\(line)")
        #expect(value(candidate, "fat", .per100g) == "14.4", "the table still reads")
    }
    for line in ["Serving size 30g 每一份量 30公克", "每一份量 30公克 (Serving size 30g)"] {
        let candidate = parse(bilingual.replacingOccurrences(of: "每一份量 Serving Size 30公克", with: line))
        #expect(candidate.servingSize?.decimalText == "30", "\(line)")
        #expect(!candidate.warnings.contains { $0.hasPrefix("bilingual_quantity_conflict") })
    }
    for line in ["Servings per package: 3 本包裝含 2份", "本包裝含2份 (3 Servings Per Package)", "本包裝含2份 Servings per package 3"] {
        let candidate = parse(bilingual.replacingOccurrences(of: "本包裝含8份 (8 Servings Per Package)", with: line))
        #expect(candidate.servingsPerPack == nil, "\(line): \(String(describing: candidate.servingsPerPack))")
        #expect(candidate.warnings.contains("bilingual_quantity_conflict: servings_per_pack"), "\(line)")
    }
    let agreeing = parse(bilingual.replacingOccurrences(of: "本包裝含8份 (8 Servings Per Package)", with: "Servings per package: 8 本包裝含 8份"))
    #expect(agreeing.servingsPerPack?.decimalText == "8")
    // English with no Chinese count on a Chinese line: the Chinese phrase decides, so not read.
    let englishOnly = parse(bilingual.replacingOccurrences(of: "本包裝含8份 (8 Servings Per Package)", with: "Servings per package: 8 本包裝"))
    #expect(englishOnly.servingsPerPack == nil)
}

/// PR 3 re-review (block): full-width digits never defeat the conflict check, an English quantity
/// in any unit counts, a number that cannot be parsed makes the line not read, and the bilingual
/// pack rule applies to a pack phrase inside a serving line.
@Test func fullWidthDigitsAndEnglishUnitsNeverLetTheEnglishQuantityBind() {
    for line in ["每一份量 ３０公克 (Serving size 25g)", "每一份量 ３０公克 (about 25g)", "每一份量 30公克 (Serving size ２５g)",
                 "Serving size 25g 每一份量 ３０公克", "每一份量 30公克 (Serving size 25 grams)", "每一份量 30公克 (Serving size 1 oz)",
                 "每一份量 ３０公克 (Serving size ３０g)"] {
        let candidate = parse(bilingual.replacingOccurrences(of: "每一份量 Serving Size 30公克", with: line))
        #expect(candidate.servingSize?.decimalText == nil, "\(line): \(String(describing: candidate.servingSize))")
    }
    // Agreeing spellings of grams still read.
    let grams = parse(bilingual.replacingOccurrences(of: "每一份量 Serving Size 30公克", with: "每一份量 30公克 (Serving size 30 grams)"))
    #expect(grams.servingSize?.decimalText == "30")
    // Full-width digits are never bound as a serving size or pack count, bilingual or not.
    let full = "每份\n熱量 120大卡\n蛋白質 3.0公克\n脂肪 4.5公克\n飽和脂肪 1.5公克\n反式脂肪 0公克\n碳水化合物 18.0公克\n糖 6.0公克\n鈉 60毫克\n"
    let wideServing = parse(preamble.replacingOccurrences(of: "每一份量30公克", with: "每一份量３０公克") + full)
    #expect(!wideServing.declined)
    #expect(wideServing.servingSize?.decimalText == nil)
    let widePack = parse(preamble.replacingOccurrences(of: "本包裝含8份", with: "本包裝含８份") + full)
    #expect(!widePack.declined)
    #expect(widePack.servingsPerPack == nil)
    for line in ["本包裝含2份 (３ Servings Per Package)", "本包裝含２份 (2 Servings Per Package)"] {
        #expect(parse(bilingual.replacingOccurrences(of: "本包裝含8份 (8 Servings Per Package)", with: line)).servingsPerPack == nil, "\(line)")
    }
    // A pack phrase inside a bilingual serving line follows the same rule.
    let inServing = parse(bilingual.replacingOccurrences(of: "每一份量 Serving Size 30公克\n本包裝含8份 (8 Servings Per Package)",
                                                       with: "每一份量 30公克 Serving size 30g 本包裝含 2份 Servings per package 3"))
    #expect(inServing.servingSize?.decimalText == "30")
    #expect(inServing.servingsPerPack == nil)
    #expect(inServing.warnings.contains("bilingual_quantity_conflict: servings_per_pack"))
    #expect(ParseStateV3.asciiDecimal("３０") == 30)
    #expect(ParseStateV3.asciiDecimal("3,0") == nil)
}

/// PR 3 re-review of `089fdf36`: a serving quantity is never cut down to the digits after a
/// separator or another numeral; an English pack count before the Chinese phrase on a serving
/// line is compared, and its "about" is kept; gr, grs and cc are grams and millilitres.
@Test func aServingOrPackNumberIsNeverCutAndEveryCountOnTheServingLineIsCompared() {
    let table = "每份\n熱量 120大卡\n蛋白質 3.0公克\n脂肪 4.5公克\n飽和脂肪 1.5公克\n反式脂肪 0公克\n碳水化合物 18.0公克\n糖 6.0公克\n鈉 60毫克\n"
    for line in ["每一份量 2．5公克", "每一份量30．5公克", "Serving size 30,5g", "每一份量30，5公克", "Portion size 37,5g", "每一份量3²0公克"] {
        let candidate = parse("營養標示\n" + line + "\n" + table)
        #expect(!candidate.declined, "\(line): \(candidate.declineReasons)")
        #expect(candidate.servingSize?.decimalText == nil, "\(line): \(String(describing: candidate.servingSize))")
        #expect(!candidate.cells.contains { $0.servingConversion.hasPrefix("5") || $0.servingConversion.hasPrefix("0") }, "\(line)")
    }
    #expect(parse("營養標示\n每一份量30.5公克\n" + table).servingSize?.decimalText == "30.5", "an ASCII decimal point still reads")
    let oddPack = parse("營養標示\n本包裝含2，5份\n" + table)
    #expect(!oddPack.declined)
    #expect(oddPack.servingsPerPack == nil)
    let englishPack = parse("Serving size 30g\nServings per container 2,5\nPer serving\nEnergy 120kcal\n")
    #expect(!englishPack.declined)
    #expect(englishPack.servingsPerPack == nil)
    for line in ["每一份量30公克 (Serving size 30g, about 3 servings per container) 本包裝含2份", "每一份量 30公克，3 servings per container，本包裝含 2份"] {
        let candidate = parse(bilingual.replacingOccurrences(of: "每一份量 Serving Size 30公克\n本包裝含8份 (8 Servings Per Package)", with: line))
        #expect(candidate.servingsPerPack == nil, "\(line): \(String(describing: candidate.servingsPerPack))")
        #expect(candidate.warnings.contains("bilingual_quantity_conflict: servings_per_pack"), "\(line)")
    }
    let about = parse(bilingual.replacingOccurrences(of: "每一份量 Serving Size 30公克\n本包裝含8份 (8 Servings Per Package)",
                                                    with: "每一份量30公克 (Serving size 30g, about 2 servings per container) 本包裝含2份"))
    #expect(about.servingsPerPack?.decimalText == "2")
    #expect(about.servingsPerPack?.approximate == true)
    for line in ["每一份量 30公克 (Serving size 30 gr)", "每一份量 30公克 (Serving size 30 grs)"] {
        #expect(parse(bilingual.replacingOccurrences(of: "每一份量 Serving Size 30公克", with: line)).servingSize?.decimalText == "30", "\(line)")
    }
    #expect(parse(bilingual.replacingOccurrences(of: "每一份量 Serving Size 30公克", with: "每一份量 250毫升 (250 cc)")).servingSize?.decimalText == "250")
    #expect(parse(bilingual.replacingOccurrences(of: "每一份量 Serving Size 30公克", with: "每一份量 250毫升 (200 cc)")).servingSize?.decimalText == nil)
}

/// PR 3 re-review (block): a basis bracket on a row repeats the printed header only when it adds
/// no quantity, or a quantity equal to the header's serving conversion and the serving size.
@Test func aRowBasisBracketWithAnotherServingQuantityDeclines() {
    let rest = "蛋白質 3.0公克\n脂肪 4.5公克\n飽和脂肪 1.5公克\n反式脂肪 0公克\n碳水化合物 18.0公克\n糖 6.0公克\n鈉 60毫克\n"
    #expect(parse("營養標示\n每份(30公克)\n熱量 120大卡(每份25公克)\n" + rest).declineReasons == ["multiple_panels"])
    #expect(parse("營養標示\n每一份量30公克\n每份\n熱量 120大卡(每份25公克)\n" + rest).declineReasons == ["multiple_panels"])
    let same = parse("營養標示\n每一份量30公克\n每份(30公克)\n熱量 120大卡(每份30公克)\n" + rest)
    #expect(!same.declined, "\(same.declineReasons)")
    #expect(value(same, "energy_kcal") == "120")
    // Without a printed serving quantity to compare with, the bracket's quantity is not trusted.
    #expect(parse("營養標示\n每份\n熱量 120大卡(每份30公克)\n" + rest).declineReasons == ["multiple_panels"])
    let plain = parse("營養標示\n每份\n熱量 120大卡(每份)\n" + rest)
    #expect(!plain.declined, "\(plain.declineReasons)")
}

@Test func aBilingualTextWithLatinOutsideItsAllowedPlacesStaysMixed() {
    let note = parse(bilingual + "Made in a factory that also handles milk\n")
    #expect(note.language == .mixed)
    let englishRow = parse(bilingual.replacingOccurrences(of: "鈉 Sodium", with: "Sodium"))
    #expect(englishRow.language == .mixed)
}

// MARK: 3.0: gate input coverage for the new layouts (test 6)

@Test func test6AMarkerOrScriptInAnUnboundLineOfTheNewLayoutsDeclines() throws {
    let simplified = try #require(["这", "们", "说", "过", "时", "个"].first { character in
        character.unicodeScalars.allSatisfy(LabelDeclineGate.isSimplifiedOnly) && !NutritionLabelTextParser.hasUnsupportedScript(character)
    })
    let energyLine = "營養標示\n熱量 45大卡(每100毫升)\n蛋白質 1.2公克\n脂肪 1.5公克\n飽和脂肪 0.9公克\n反式脂肪 0公克\n碳水化合物 6.4公克\n糖 6.1公克\n鈉 38毫克\n"
    for (layout, text) in [("flattened", flat("，")), ("bilingual", bilingual), ("energy line", energyLine)] {
        #expect(parse(text).declineReasons == (layout == "energy line" ? ["no_basis_header"] : []), "\(layout): \(parse(text).declineReasons)")
        #expect(parse(text + "*本品為營養補充品\n").declineReasons == ["not_a_food_nutrition_panel"], "\(layout)")
        #expect(parse(text + "*\(simplified)項\n").declineReasons == ["unsupported_script"], "\(layout)")
    }
    // The flattened line itself is gate-scanned (its heading words are consumed unbound).
    #expect(parse(flat("，", prefix: "營養補充 每份 ")).declineReasons.contains("not_a_food_nutrition_panel"))
    // A bilingual gloss is consumed unbound: it is scanned too.
    #expect(parse(bilingual.replacingOccurrences(of: "Total Fat", with: "Total Fat Dietary Supplement")).declineReasons == ["not_a_food_nutrition_panel"])
}

// MARK: 3.0: layout precedence with the flattened layout (test 13)

@Test func test13TheFlattenedLayoutIsTheThirdPredicate() {
    typealias L = LabelLayout.Line
    #expect(LabelLayout.precedence == [.inline, .stacked, .flattened])
    #expect(LabelLayout.classify([.flattened]) == .flattened)
    #expect(LabelLayout.classify([.labelOnly, .flattened, .labelOnly]) == .flattened)
    #expect(LabelLayout.classify([.flattened, .flattened]) == nil)
    #expect(LabelLayout.classify([.flattened, .labelWithValues(secondLabel: false)]) == nil)
    #expect(LabelLayout.classify([.flattened, .valuesOnly, .labelOnly]) == nil, "never stacked")
    for lines: [L] in [[.flattened], [.labelWithValues(secondLabel: false)], [.labelOnly, .valuesOnly]] {
        #expect(LabelLayout.precedence.filter { LabelLayout.matches($0, lines) }.count == 1)
    }
}

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
