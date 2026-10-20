import Foundation
import Testing
@testable import NutritionLabelParsing

// Parser v3, PR 1 of `docs/pasted-nutrition-label-reader-v3.md` section 8: lines before the table
// (3.1), the alias table (section 4), the Taiwan unit rule (3.9), layout precedence and gate input
// coverage (3.0); reader v3 tests 4, 6 and 13. Every fixture is synthetic: invented values and
// names, modelled on layout shapes only.

private let hash = String(repeating: "0", count: 64)
private func parse(_ text: String) -> LabelCaptureCandidate {
    NutritionLabelTextParserV3().parse(text, inputSHA256: hash)
}
private func cell(_ candidate: LabelCaptureCandidate, _ nutrient: String, _ basis: LabelBasis = .per100g) -> LabelCell? {
    candidate.cells.first { $0.nutrient == nutrient && $0.basis == basis }
}

/// A synthetic two-column Taiwan table body (official template order).
private let rows = """
每份 每100公克
熱量 120大卡 400大卡
蛋白質 3.0公克 10.0公克
脂肪 4.5公克 15.0公克
飽和脂肪 1.5公克 5.0公克
反式脂肪 0公克 0公克
碳水化合物 18.0公克 60.0公克
糖 6.0公克 20.0公克
鈉 60毫克 200毫克
"""
private let servingLines = "每一份量30公克\n本包裝含8份\n"
private func label(_ before: String = "營養標示\n" + servingLines, body: String = rows) -> String { before + body }

// MARK: Version

@Test func parserV3NamesItsVersionAndAliasTable() {
    #expect(NutritionLabelTextParserV3.version == "nutrition-label-text-parser-v3")
    #expect(NutritionLabelTextParserV3.aliasVersion == "taiwan-row-aliases-v1")
    #expect(NutritionLabelTextParser.version == "nutrition-label-text-parser-v2", "parser v2 stays the frozen evaluation reference")
    let candidate = parse(label())
    #expect(!candidate.declined)
    #expect(candidate.cells.count == 16)
    #expect(candidate.wouldMarkReady)
    #expect(candidate == NutritionLabelTextParser().parse(label(), inputSHA256: hash), "a plain table reads exactly as v2")
}

// MARK: 3.1 rule 1 and 2: titles and rule lines

@Test func decoratedTitlesAndRuleLinesCarryNoValueAndDoNotStartTheRows() {
    let titles = ["★營養標示★", "☆營養標示", "◎營養標示◎", "●營養標示", "▲營養標示", "■營養標示■", "◆營養標示◆", "【營養標示】", "[營養標示]",
                  "===營養標示===", "= 營養標示 =", "營養標示 Nutrition Facts", "營養標示：", "營養標示（大卡）", "【營養成分】", "營養標示(熱量單位)"]
    for title in titles {
        let candidate = parse(label(title + "\n" + servingLines))
        #expect(!candidate.declined, "\(title): \(candidate.declineReasons)")
        #expect(candidate.cells.count == 16, "\(title)")
        #expect(!candidate.cells.contains { $0.printedLabel.contains("營養") }, "\(title) is never a row")
        // Parser v2 starts the rows at the decorated title, so the real header is a second panel.
        if !NutritionLabelTextParser.language(of: title).isMixed, !Patterns.title.contains(title) {
            #expect(NutritionLabelTextParser().parse(label(title + "\n" + servingLines), inputSHA256: hash).declined, "\(title) (v2)")
        }
    }
    for rule in ["=====", "-----", "─────", "_____", "*****", "= = = =", "———".replacingOccurrences(of: "—", with: "-")] {
        let candidate = parse(label("營養標示\n" + rule + "\n" + servingLines))
        #expect(!candidate.declined, "\(rule)")
        #expect(candidate.cells.count == 16, "\(rule)")
    }
}

@Test func aTitleBracketWithABasisOrANumberIsNotATitle() {
    #expect(!ParseStateV3.isTitle("營養標示（每100公克）"))
    #expect(!ParseStateV3.isTitle("營養標示(30公克)"))
    #expect(!ParseStateV3.isTitle("營養標示 每份"))
    #expect(ParseStateV3.isTitle("營養標示（大卡）"))
    #expect(!ParseStateV3.isTitle("營養標示（大卡）（公克）"), "one bracketed group only")
}

// MARK: 3.1 rule 3: serving label variants and the split serving line (test 4)

@Test func theServingLabelTakesADigitOne() {
    let candidate = parse(label("營養標示\n每1份量30公克\n本包裝含8份\n"))
    #expect(candidate.servingSize == LabelServingSize(printedText: "每1份量30公克", decimalText: "30", unit: "公克", canonicalUnit: "g"))
}

@Test func test4ASplitServingLineIsJoinedBeforeTheFirstRowOutsideStackedTables() {
    let candidate = parse(label("營養標示\n每一份量\n30公克\n本包裝含8份\n"))
    #expect(!candidate.declined)
    #expect(candidate.servingSize == LabelServingSize(printedText: "每一份量 30公克", decimalText: "30", unit: "公克", canonicalUnit: "g"))
    #expect(candidate.warnings == ["serving_line_joined"])
    #expect(!candidate.wouldMarkReady)
    #expect(cell(candidate, "energy_kcal", .perServing)?.servingConversion == "30公克")
    // The pack line too, with its own join.
    let pack = parse(label("營養標示\n每一份量30公克\n本包裝含\n8份\n"))
    #expect(pack.servingsPerPack == LabelServingsPerPack(printedText: "本包裝含 8份", decimalText: "8", approximate: false))
    #expect(pack.warnings == ["serving_line_joined: servings_per_pack"])
    let about = parse(label("營養標示\n每一份量30公克\n本包裝含\n約8份\n"))
    #expect(about.servingsPerPack?.approximate == true)
    // Trimmed and joined by exactly one ASCII space.
    let spaced = parse(label("營養標示\n每一份量：  \n  30 公克  \n本包裝含8份\n"))
    #expect(spaced.servingSize?.printedText == "每一份量： 30 公克")
    #expect(spaced.servingSize?.decimalText == "30")
}

@Test func test4ASplitServingLineIsNotJoinedAfterTheFirstRowInAStackedTableOrBeforeOtherText() {
    // After the first row: the serving size is not read and its quantity is never bound to a row.
    let afterRow = parse("營養標示\n本包裝含8份\n每份 每100公克\n熱量 120大卡 400大卡\n每一份量\n30公克\n蛋白質 3.0公克 10.0公克\n")
    #expect(!afterRow.declined)
    #expect(afterRow.servingSize == nil)
    #expect(!afterRow.cells.contains { $0.decimalText == "30" }, "the moved quantity is not a value")
    #expect(afterRow.cells.count == 4)
    // The quantity line is not the next non-empty line.
    let interrupted = parse(label("營養標示\n每一份量\n本包裝含8份\n30公克\n"))
    #expect(interrupted.servingSize == nil)
    // A quantity with anything else on its line.
    let notAlone = parse(label("營養標示\n每一份量\n30公克（約2片）\n本包裝含8份\n"))
    #expect(notAlone.servingSize == nil)
    // A stacked table: the join is refused and the serving size is not read.
    let stacked = parse("營養標示\n每一份量\n30公克\n本包裝含8份\n每100公克\n熱量\n400大卡\n蛋白質\n10.0公克\n脂肪\n15.0公克\n")
    #expect(!stacked.declined)
    #expect(stacked.servingSize == nil)
    #expect(!stacked.warnings.contains("serving_line_joined"))
    #expect(cell(stacked, "protein")?.decimalText == "10.0")
}

@Test func test4AMovedServingQuantityLeavesTheServingSizeNotRead() {
    // Moved to the end of a one-column table: it never becomes a value of the last row.
    let end = parse("營養標示\n每一份量\n本包裝含8份\n每100公克\n熱量 400大卡\n蛋白質 10.0公克\n鈉 200毫克\n30公克\n")
    #expect(end.servingSize == nil)
    #expect(end.declined || !end.cells.contains { $0.decimalText == "30" })
    // Moved between the header and the rows.
    let middle = parse("營養標示\n每一份量\n本包裝含8份\n每100公克\n30公克\n熱量 400大卡\n")
    #expect(middle.servingSize == nil)
    #expect(middle.declined)
}

// MARK: 3.1 rule 4: pack lines

@Test func packLineVariantsAreRead() {
    let cases: [(String, String, Bool)] = [("本包裝含8份", "8", false), ("本包裝包含8份", "8", false), ("本包裝 8 份", "8", false),
                                           ("本包裝含約8份", "8", true), ("本包裝包含 約 2.5 份", "2.5", true), ("本包裝含0份", "0", false)]
    for (line, number, approximate) in cases {
        let candidate = parse(label("營養標示\n每一份量30公克\n\(line)\n"))
        #expect(!candidate.declined, "\(line)")
        #expect(candidate.servingsPerPack == LabelServingsPerPack(printedText: line, decimalText: number, approximate: approximate), "\(line)")
        #expect(candidate.cells.count == 16, "\(line)")
    }
}

@Test func aServingAndPackLineIsCutAtThePackPhrase() {
    let cases: [(String, String?, String, Bool)] = [
        ("每一份量30公克，本包裝含8份", "30", "8", false), ("每一份量30公克 本包裝含約8份", "30", "8", true),
        ("每1份量 30 公克／本包裝包含 8 份", "30", "8", false), ("每一份量1片，本包裝含8份(240公克)", nil, "8", false),
        ("Serving size 30g, servings per container about 8", "30", "8", true)
    ]
    for (line, size, pack, approximate) in cases {
        let candidate = parse(label("營養標示\n\(line)\n"))
        #expect(candidate.servingSize?.printedText == line, "\(line)")
        #expect(candidate.servingSize?.decimalText == size, "\(line): the pack phrase is never the serving size")
        #expect(candidate.servingsPerPack == LabelServingsPerPack(printedText: line, decimalText: pack, approximate: approximate), "\(line)")
    }
    #expect(ParseStateV3.cutAtPackPhrase("30公克，本包裝含約8份") == "30公克")
    #expect(ParseStateV3.cutAtPackPhrase("30公克 / servings per pack 8") == "30公克")
    #expect(ParseStateV3.cutAtPackPhrase("30公克（約2片）") == "30公克（約2片）")
}

@Test func aPrintedPackCountOfZeroIsReadAsPrinted() {
    let candidate = parse(label("營養標示\n每一份量30公克\n本包裝含0份\n"))
    #expect(candidate.servingsPerPack?.decimalText == "0")
}

// MARK: 3.1 rule 5: row markers

@Test func leadingRowMarkersAreRemovedAndCountAsIndentation() {
    for marker in [">>", ">", "•", "·", "▲", "●", "-", "*"] {
        // `-` and `*` are markers only straight before a Han character; the others may take a space.
        let spaced = marker == "-" || marker == "*" ? marker : marker + " "
        let body = rows.replacingOccurrences(of: "\n糖 ", with: "\n\(marker)糖 ").replacingOccurrences(of: "\n飽和脂肪 ", with: "\n\(spaced)飽和脂肪 ")
        let candidate = parse(label(body: body))
        #expect(!candidate.declined, "\(marker): \(candidate.declineReasons)")
        #expect(candidate.cells.count == 16, "\(marker)")
        #expect(cell(candidate, "sugars")?.printedLabel == "糖", "\(marker)")
        #expect(cell(candidate, "saturates")?.parentRowID == "fat", "\(marker)")
    }
    // A marker on every row never makes a top-level Taiwan row a child: the alias table names parents.
    let bulleted = rows.split(separator: "\n").enumerated().map { $0.offset == 0 ? String($0.element) : "• " + $0.element }
    let everyRow = parse(label(body: bulleted.joined(separator: "\n")))
    #expect(everyRow.cells.count == 16)
    #expect(everyRow.cells.filter { ["energy_kcal", "protein", "fat", "carbohydrate", "sodium"].contains($0.nutrient) }.allSatisfy { $0.parentRowID == nil })
    #expect(cell(everyRow, "sugars")?.parentRowID == "carbohydrate")
    // An unrecognised row after a marker is indented under the last top-level row.
    let indented = parse(label(body: rows + "\n▲膽固醇 0毫克 0毫克"))
    #expect(indented.cells.first { $0.printedLabel == "膽固醇" }?.parentRowID == "sodium")
    // A footnote that starts with * is still a footnote, never a row.
    let footnote = parse(label(body: rows + "\n*參考值未訂定"))
    #expect(footnote.cells.count == 16)
    #expect(footnote.wouldMarkReady)
    // - and * only before a Han character.
    #expect(ParseStateV3.markedRow("-30公克") == nil)
    #expect(ParseStateV3.markedRow("*Fat 3g") == nil)
}

// MARK: Section 4: taiwan-row-aliases-v1

@Test func aliasesNameTheAcidFormsAndTheVoluntaryBracket() {
    let body = """
    每份 每100公克
    熱量 120大卡 400大卡
    蛋白質 3.0公克 10.0公克
    脂肪 4.5公克 15.0公克
    飽和脂肪酸 1.5公克 5.0公克
    反式脂肪酸 0公克 0公克
    碳水化合物 18.0公克 60.0公克
    糖 6.0公克 20.0公克
    添加糖 2.0公克 6.0公克
    膳食纖維(自願標示者) 1.0公克 3.0公克
    鈉 60毫克 200毫克
    """
    let candidate = parse(label(body: body))
    #expect(!candidate.declined)
    #expect(candidate.warnings.isEmpty, "\(candidate.warnings)")
    #expect(cell(candidate, "saturates")?.printedLabel == "飽和脂肪酸")
    #expect(cell(candidate, "saturates")?.parentRowID == "fat")
    #expect(cell(candidate, "trans_fat")?.printedLabel == "反式脂肪酸")
    #expect(cell(candidate, "added_sugars")?.parentRowID == "sugars")
    #expect(cell(candidate, "sugars")?.decimalText == "20.0", "添加糖 is never sugars")
    #expect(cell(candidate, "fibre")?.printedLabel == "膳食纖維(自願標示者)")
    #expect(cell(candidate, "fibre")?.parentRowID == "carbohydrate")
    // Parser v2 left the acid forms and the bracket unrecognised.
    let v2 = NutritionLabelTextParser().parse(label(body: body), inputSHA256: hash)
    #expect(v2.warnings.filter { $0.hasPrefix("unrecognised_row") }.count == 4)
    for printed in ["膳食纖維（自願標示者）", "膳食纖維(自願標示)", "膳食纖維（自願標示)", "膳食 纖維 (自願標示者)"] {
        #expect(TaiwanRowAliases.entry(printed)?.row == .nutrient("fibre"), "\(printed)")
    }
}

@Test func aliasMatchingIsExactSoSubstringTrapsNeverBindAStoredRow() {
    for trap in TaiwanRowAliases.recognisedNotStored + ["飽和脂肪酸類", "糖類", "醣類", "總糖", "其他飽和脂肪", "反式脂肪(酸)", "鈉含量", "鈉(自願標示者)x",
                                                         "脂肪(其他)", "膳食纖維(自願標示者)(自願標示者)", "糖(自願標示者)"] {
        let entry = TaiwanRowAliases.entry(trap)
        if trap == "糖(自願標示者)" {
            #expect(entry?.row == .nutrient("sugars"), "the voluntary bracket is removed from any label")
            continue
        }
        #expect(entry == nil, "\(trap) must never match a row")
        let candidate = parse(label(body: rows + "\n\(trap) 1.0公克 2.0公克"))
        let bound = candidate.cells.filter { $0.printedLabel == trap }
        #expect(bound.allSatisfy { $0.nutrient == "unrecognised" }, "\(trap)")
    }
    #expect(TaiwanRowAliases.entry("醣類") == nil, "held out until seen in real text (decision 9)")
}

// MARK: 3.9: Taiwan unit rule

@Test func aMandatoryTaiwanRowInAnOffTemplateUnitIsNotRead() {
    let cases: [(String, String, String)] = [
        ("鈉 60毫克 200毫克", "鈉 0.06公克 0.2公克", "sodium"),
        ("糖 6.0公克 20.0公克", "糖 6000毫克 20000毫克", "sugars"),
        ("蛋白質 3.0公克 10.0公克", "蛋白質 3.0微克 10.0微克", "protein"),
        ("熱量 120大卡 400大卡", "熱量 120 Cal 400 Cal", "energy_kcal"),
        ("反式脂肪 0公克 0公克", "反式脂肪 0毫克 0毫克", "trans_fat")
    ]
    for (from, to, nutrient) in cases {
        let candidate = parse(label(body: rows.replacingOccurrences(of: from, with: to)))
        #expect(!candidate.declined, "\(to)")
        let rowLabel = String(to.split(separator: " ")[0])
        #expect(candidate.warnings.contains("row_not_read: unit_off_template: \(rowLabel)"), "\(to): \(candidate.warnings)")
        #expect(!candidate.cells.contains { $0.printedLabel == rowLabel }, "\(to)")
        #expect(cell(candidate, nutrient) == nil)
        #expect(candidate.cells.count == 14, "only the off-template row is unread")
        #expect(!candidate.wouldMarkReady)
    }
    // Energy is read in kcal or kJ (v1 decision 6): kJ only, kcal and kJ on one row, or on two.
    for body in [rows.replacingOccurrences(of: "熱量 120大卡 400大卡", with: "熱量 502 kJ 1674 kJ"),
                 rows.replacingOccurrences(of: "熱量 120大卡 400大卡", with: "熱量 120大卡 502 kJ 400大卡 1674 kJ"),
                 rows.replacingOccurrences(of: "熱量 120大卡 400大卡", with: "熱量 120大卡 400大卡\n502 kJ 1674 kJ")] {
        let candidate = parse(label(body: body))
        #expect(!candidate.declined, "\(body)")
        #expect(candidate.warnings.isEmpty, "\(candidate.warnings)")
        #expect(cell(candidate, "energy_kj")?.decimalText == "1674")
        #expect(cell(candidate, "energy_kcal")?.decimalText == (body.contains("大卡") ? "400" : nil))
        #expect(candidate == NutritionLabelTextParser().parse(label(body: body), inputSHA256: hash), "as parser v2 reads it")
    }
    // Optional rows keep v2's unit sets; English rows are not Taiwan rows.
    let fibre = parse(label(body: rows + "\n膳食纖維 500毫克 1500毫克"))
    #expect(cell(fibre, "fibre")?.canonicalUnit == "mg")
    #expect(fibre.warnings.isEmpty)
    let english = parse("Typical values\tPer 100g\nEnergy\t1500kJ\nSodium\t0.4g\nFat\t3g\n")
    #expect(cell(english, "sodium")?.canonicalUnit == "g")
    // A unit outside the row's allowed set still declines, as in v2.
    #expect(parse(label(body: rows.replacingOccurrences(of: "鈉 60毫克 200毫克", with: "鈉 60大卡 200大卡"))).declineReasons == ["unrecognised_unit"])
}

// MARK: 3.0: layout precedence (test 13)

@Test func test13LayoutPrecedenceIsAClosedOrderedListOfPredicates() {
    typealias L = LabelLayout.Line
    #expect(LabelLayout.precedence == [.inline, .stacked])
    let inline: [L] = [.labelWithValues(secondLabel: false), .labelWithValues(secondLabel: false), .valuesOnly, .labelOnly, .labelWithValues(secondLabel: false)]
    let stacked: [L] = [.labelOnly, .valuesOnly, .valuesOnly, .labelOnly, .valuesOnly]
    let mixed: [L] = [.labelWithValues(secondLabel: false), .labelOnly, .valuesOnly]
    let twoRowsOnALine: [L] = [.labelWithValues(secondLabel: true)]
    #expect(LabelLayout.classify(inline) == .inline)
    #expect(LabelLayout.classify(stacked) == .stacked)
    #expect(LabelLayout.classify(mixed) == nil, "matches neither predicate")
    #expect(LabelLayout.classify(twoRowsOnALine) == nil)
    #expect(LabelLayout.classify([.valuesOnly]) == nil)
    for layout in LabelLayout.allCases {
        #expect(!(LabelLayout.matches(layout, inline) && LabelLayout.matches(layout, stacked)))
    }
    // More than one match declines too: the classifier only accepts exactly one.
    #expect(LabelLayout.precedence.filter { LabelLayout.matches($0, inline) }.count == 1)
}

@Test func test13BodiesThatAreNotExactlyOneLayoutDeclineLayoutAmbiguous() {
    let mixed = parse(label(body: rows.replacingOccurrences(of: "蛋白質 3.0公克 10.0公克", with: "蛋白質\n3.0公克\n10.0公克")))
    #expect(mixed.declineReasons == ["layout_ambiguous"])
    let twoRows = parse(label(body: rows.replacingOccurrences(of: "蛋白質 3.0公克 10.0公克\n脂肪 4.5公克 15.0公克",
                                                              with: "蛋白質 3.0公克 10.0公克 脂肪 4.5公克 15.0公克")))
    #expect(twoRows.declineReasons == ["layout_ambiguous"])
    let english = parse("Typical values\tPer 100g\nEnergy 1500kJ Fat 3g Protein 2g\n")
    #expect(english.declineReasons == ["layout_ambiguous"])
    // The kJ and kcal continuation stays inline; a stacked body reads as in parser v2.
    let continued = parse("Typical values\tPer 100g\nEnergy\t1500kJ\n355kcal\nFat\t3g\n")
    #expect(!continued.declined)
    #expect(continued.cells.count == 3)
    let stacked = parse(label(body: "每份\n熱量\n120大卡\n蛋白質\n3.0公克\n鈉\n60毫克"))
    #expect(!stacked.declined)
    #expect(stacked.cells.map(\.decimalText) == ["120", "3.0", "60"])
    // A body with no values at all has no table, as in v2.
    #expect(parse(label(body: "每份 每100公克\n熱量\n蛋白質")).declineReasons == ["no_table"])
}

// MARK: Review of #280: "more than", repeated rows, bullets, Han between values, joins, pack lines

/// Mutation fixtures (7.2). Class (b), content-changing: a value printed as "more than" (`>3公克`)
/// is not a value the reader can hold, so its row is never bound (oracle: not read, or declined).
/// Class (a), structure-only: a `>` marker before a row label is indentation and the row reads.
@Test func aMoreThanValueIsNeverReadAsExact() {
    for mark in [">", ">>", "≥", "＞", "> ", "超過", "大於"] {
        let stacked = parse(label(body: "每份\n熱量\n120大卡\n蛋白質\n3.0公克\n脂肪\n\(mark)3公克\n鈉\n\(mark)1000毫克"))
        #expect(cell(stacked, "fat", .perServing) == nil, "stacked \(mark): \(stacked.cells.map(\.printedText))")
        #expect(cell(stacked, "sodium", .perServing) == nil, "stacked \(mark)")
        #expect(!stacked.cells.contains { $0.decimalText == "3" || $0.decimalText == "1000" }, "stacked \(mark)")
        for body in [rows.replacingOccurrences(of: "鈉 60毫克 200毫克", with: "鈉 60毫克\n\(mark)200毫克"),
                     rows.replacingOccurrences(of: "鈉 60毫克 200毫克", with: "鈉 60毫克 \(mark)200毫克"),
                     rows.replacingOccurrences(of: "鈉 60毫克 200毫克", with: "鈉 \(mark)60毫克 200毫克")] {
            let inline = parse(label(body: body))
            #expect(!inline.cells.contains { $0.nutrient == "sodium" }, "inline \(mark): \(inline.cells.filter { $0.nutrient == "sodium" })")
            #expect(!inline.cells.contains { $0.decimalText == "200" && $0.comparator == .equal }, "inline \(mark)")
        }
    }
    let warned = parse(label(body: rows.replacingOccurrences(of: "鈉 60毫克 200毫克", with: "鈉 60毫克 >200毫克")))
    #expect(warned.warnings.contains("row_not_read: malformed_value: 鈉"))
    #expect(warned.cells.count == 14)
    // Class (a): `>` before a label is a row marker; the row reads as printed.
    let marker = parse(label(body: rows.replacingOccurrences(of: "\n脂肪 ", with: "\n> 脂肪 ")))
    #expect(cell(marker, "fat")?.decimalText == "15.0")
    #expect(cell(marker, "fat")?.comparator == .equal)
    #expect(ParseStateV3.markedRow(">3公克") == nil)
    #expect(ParseStateV3.markedRow(">> 3公克") == nil)
}

/// Re-review of #280: a "more than" mark split from its value across lines (after the label, or on
/// a line of its own) still makes the row unread, stacked and inline, Chinese and English.
@Test func aMoreThanMarkSplitAcrossLinesIsNeverReadAsExact() {
    let stackedHead = "營養標示\n每一份量30公克\n本包裝含8份\n每份\n熱量\n120大卡\n蛋白質\n3.0公克\n"
    for tail in ["鈉 超過\n1000毫克", "鈉\n超過\n1000毫克", "鈉\n>\n1000毫克", "鈉 >\n1000毫克", "鈉 ＞\n1000毫克", "鈉\n≥\n1000毫克"] {
        let candidate = parse(stackedHead + tail)
        #expect(!candidate.cells.contains { $0.nutrient == "sodium" }, "\(tail): \(candidate.cells.map(\.printedText))")
        #expect(!candidate.cells.contains { $0.decimalText == "1000" }, "\(tail)")
        #expect(!candidate.wouldMarkReady, "\(tail)")
        if !candidate.declined { #expect(candidate.warnings.contains("row_not_read: malformed_value: 鈉"), "\(tail): \(candidate.warnings)") }
    }
    for tail in ["Sodium more than\n1000mg", "Sodium\nmore than\n1000mg", "Sodium >\n1000mg"] {
        let candidate = parse("Per 100g\nEnergy\n1500kJ\nProtein\n2g\n" + tail)
        #expect(!candidate.cells.contains { $0.nutrient == "sodium" }, "\(tail): \(candidate.cells.map(\.printedText))")
        #expect(!candidate.wouldMarkReady, "\(tail)")
    }
    for line in ["鈉 超過 60毫克 200毫克", "鈉 60毫克 超過200毫克", "鈉 > 60毫克 > 200毫克", "鈉 60毫克以上 200毫克以上"] {
        let candidate = parse(label(body: rows.replacingOccurrences(of: "鈉 60毫克 200毫克", with: line)))
        #expect(!candidate.cells.contains { $0.nutrient == "sodium" }, "\(line)")
        #expect(candidate.cells.count == 14, "\(line)")
    }
}

/// Bound words (reader v3 PR 1 re-review): ≦ and a trailing 以下 are "at most", 未滿 is "less
/// than"; a trailing 以上 ("at least") cannot be held, so the row is not read. Bounds stay bounds.
@Test func boundWordsStayBoundsAndAtLeastIsNotRead() {
    let cases: [(String, LabelComparator, String)] = [
        ("鈉 5 毫克 以下 10 毫克 以下", .lessOrEqual, "10 毫克 以下"), ("鈉 ≦5毫克 ≦10毫克", .lessOrEqual, "≦10毫克"),
        ("鈉 未滿 5毫克 未滿 10毫克", .less, "未滿 10毫克"), ("鈉 5毫克以下 10毫克以下", .lessOrEqual, "10毫克以下")
    ]
    for (line, comparator, printed) in cases {
        let candidate = parse(label(body: rows.replacingOccurrences(of: "鈉 60毫克 200毫克", with: line)))
        #expect(!candidate.declined, "\(line): \(candidate.declineReasons)")
        #expect(candidate.warnings.isEmpty, "\(line): \(candidate.warnings)")
        #expect(cell(candidate, "sodium")?.comparator == comparator, "\(line)")
        #expect(cell(candidate, "sodium")?.decimalText == "10", "\(line)")
        #expect(cell(candidate, "sodium")?.printedText == printed, "\(line)")
    }
    let atLeast = parse(label(body: rows.replacingOccurrences(of: "鈉 60毫克 200毫克", with: "鈉 5 毫克 以上 10 毫克 以上")))
    #expect(cell(atLeast, "sodium") == nil)
    #expect(atLeast.warnings.contains("row_not_read: malformed_value: 鈉"))
}

@Test func aServingSizeOrPackCountPrintedAsMoreThanIsNotRead() {
    for line in ["每一份量 超過30公克", "每一份量30公克以上", "每一份量 >30公克", "Serving size more than 30g"] {
        let candidate = parse(label("營養標示\n\(line)\n本包裝含8份\n"))
        #expect(candidate.servingSize?.decimalText == nil, "\(line)")
        #expect(!candidate.cells.contains { $0.servingConversion == "30公克" || $0.servingConversion == "30g" }, "\(line)")
    }
    for line in ["本包裝含超過8份", "本包裝含8份以上", "本包裝 > 8 份", "Servings per container more than 8"] {
        let candidate = parse(label("營養標示\n每一份量30公克\n\(line)\n"))
        #expect(!candidate.declined, "\(line): \(candidate.declineReasons)")
        #expect(candidate.servingsPerPack == nil, "\(line)")
        #expect(candidate.cells.count == 16, "\(line)")
    }
    #expect(parse(label("營養標示\n每一份量30公克，本包裝含8份以上\n")).servingsPerPack == nil)
}

@Test func knownEnglishTopLevelRowsIgnoreBullets() {
    let candidate = parse("Typical values\tPer 100g\nCarbohydrate\t50g\n• Sugars\t5g\n• Fat\t10g\n• Protein\t2g\n")
    #expect(cell(candidate, "sugars")?.parentRowID == "carbohydrate")
    #expect(cell(candidate, "fat")?.parentRowID == nil)
    #expect(cell(candidate, "protein")?.parentRowID == nil)
}

/// Two rows binding the same nutrient and column (a `*` row before the real one): the reader
/// never picks one; both are not read, so the row is flagged on Confirm (G3).
@Test func duplicateRowsAreBothUnread() {
    let candidate = parse(label("營養標示\n每一份量30公克\n本包裝含8份\n", body: "每份\n熱量 120大卡\n*鈉 50毫克\n鈉 2000毫克"))
    #expect(!candidate.declined, "\(candidate.declineReasons)")
    #expect(!candidate.cells.contains { $0.nutrient == "sodium" })
    #expect(candidate.warnings.filter { $0.hasPrefix("row_not_read: duplicate_row: 鈉") }.count == 2)
    #expect(cell(candidate, "energy_kcal", .perServing)?.decimalText == "120")
}

@Test func aStarredLineRepeatingAReadRowIsAFootnote() {
    for footnote in ["*鈉 2000毫克", "*鈉每日參考值2000毫克", "*熱量 2000大卡"] {
        let candidate = parse(label(body: rows + "\n" + footnote))
        #expect(!candidate.declined, "\(footnote): \(candidate.declineReasons)")
        #expect(candidate.cells.count == 16, "\(footnote)")
        #expect(cell(candidate, "sodium")?.decimalText == "200", "\(footnote)")
        #expect(cell(candidate, "energy_kcal")?.decimalText == "400", "\(footnote)")
    }
}

@Test func bulletsOnEnglishRowsNeverChainRowsUnderEachOther() {
    let bulleted = parse("Typical values\tPer 100g\n• Energy\t1500kJ\n• Fat\t3g\n• Saturates\t1g\n• Carbohydrate\t10g\n• Sugars\t5g\n• Protein\t2g\n")
    #expect(!bulleted.declined)
    #expect(bulleted.cells.allSatisfy { $0.parentRowID == nil }, "\(bulleted.cells.map { ($0.nutrient, $0.parentRowID ?? "-") })")
    // After a marker-free top-level row, a marker is indentation.
    let mixed = parse("Typical values\tPer 100g\nFat\t3g\n• Saturates\t1g\nCarbohydrate\t10g\n• Sugars\t5g\n")
    #expect(cell(mixed, "saturates")?.parentRowID == "fat")
    #expect(cell(mixed, "sugars")?.parentRowID == "carbohydrate")
}

@Test func hanTextBetweenValuesIsTwoRowsAndDeclines() {
    for gap in ["其中飽和脂肪", "不飽和脂肪", "飽和", "約"] {
        let text = label(body: rows.replacingOccurrences(of: "脂肪 4.5公克 15.0公克", with: "脂肪 4.5公克 \(gap) 1.5公克"))
        #expect(parse(text).declineReasons == ["layout_ambiguous"], "\(gap)")
        #expect(ParseStateV3.hasHanBetweenValues("脂肪 4.5公克 \(gap) 1.5公克"))
    }
    // Parser v2 is unchanged: it binds the second value to the per 100 g column.
    let v2 = NutritionLabelTextParser().parse(label(body: rows.replacingOccurrences(of: "脂肪 4.5公克 15.0公克",
                                                                                    with: "脂肪 4.5公克 其中飽和脂肪 1.5公克")), inputSHA256: hash)
    #expect(v2.cells.first { $0.nutrient == "fat" && $0.basis == .per100g }?.decimalText == "1.5")
    // Han text after the last value is not a second row (a voluntary note).
    #expect(!ParseStateV3.hasHanBetweenValues("鈉 60毫克 200毫克 自願"))
}

@Test func joinedServingAndPackLinesCarryOneWarning() {
    let candidate = parse(label("營養標示\n每一份量\n30公克\n本包裝含\n8份\n"))
    #expect(candidate.servingSize?.decimalText == "30")
    #expect(candidate.servingsPerPack?.decimalText == "8")
    #expect(candidate.warnings == ["serving_line_joined", "serving_line_joined: servings_per_pack"], "one warning per joined line")
}

@Test func boundServingAndPackLinesAreScannedForMarkers() {
    #expect(parse(label("營養標示\n每一份量30公克\n本包裝含8份（營養補充品）\n")).declineReasons == ["not_a_food_nutrition_panel"])
    #expect(parse(label("營養標示\n每一份量30公克（營養補充品）\n本包裝含8份\n")).declineReasons == ["not_a_food_nutrition_panel"])
}

// MARK: 3.0: gate input coverage (test 6)

@Test func test6AMarkerOrScriptInAConsumedButUnboundLineDeclinesWithTheGatesCode() throws {
    let simplified = try #require(["这", "们", "说", "过", "时", "个", "们"].first { character in
        character.unicodeScalars.allSatisfy(LabelDeclineGate.isSimplifiedOnly) && !NutritionLabelTextParser.hasUnsupportedScript(character)
    })
    let inline = label()
    let stacked = label(body: "每份\n熱量\n120大卡\n蛋白質\n3.0公克\n鈉\n60毫克")
    for (layout, text) in [("inline", inline), ("stacked", stacked)] {
        #expect(!parse(text).declined, "\(layout)")
        let unboundLines = [
            ("title bracket", text.replacingOccurrences(of: "營養標示\n", with: "營養標示（營養補充品）\n")),
            ("footnote", text + "\n*本品為營養補充品"),
            ("rule line then footnote", text + "\n=====\n＊營養補充說明"),
            ("header segment", text.replacingOccurrences(of: "每份", with: "營養補充  每份"))
        ]
        for (name, marked) in unboundLines {
            #expect(parse(marked).declineReasons == ["not_a_food_nutrition_panel"], "\(layout) \(name): \(parse(marked).declineReasons)")
        }
        let script = [
            ("title bracket", text.replacingOccurrences(of: "營養標示\n", with: "營養標示（\(simplified)）\n")),
            ("footnote", text + "\n*\(simplified)項"),
            ("row without values", text + "\n\(simplified)項")
        ]
        for (name, marked) in script {
            #expect(parse(marked).declineReasons == ["unsupported_script"], "\(layout) \(name): \(parse(marked).declineReasons)")
            // Parser v2 never looked at these lines.
            #expect(NutritionLabelTextParser().parse(marked, inputSHA256: hash).declineReasons != ["unsupported_script"], "\(name)")
        }
    }
    // The parser calls the gate's own functions; the gate itself is unchanged.
    #expect(LabelDeclineGate.version == "label-capture-decline-gate-v2")
    #expect(ParseStateV3.coverageDeclines(["營養補充\(simplified)"]) == ["unsupported_script", "not_a_food_nutrition_panel"])
}

// MARK: Non-regression helper (test 12) on synthetic pairs

@Test func test12TheAllowListExplainsEachRuleAndNothingElse() {
    let acid = label(body: rows.replacingOccurrences(of: "飽和脂肪 ", with: "飽和脂肪酸 "))
    let verdict = NonRegression.explain(v2: NutritionLabelTextParser().parse(acid, inputSHA256: hash), v3: parse(acid))
    #expect(verdict.items == [.aliasNamesRow])
    #expect(verdict.unexplained.isEmpty)
    let grams = label(body: rows.replacingOccurrences(of: "鈉 60毫克 200毫克", with: "鈉 0.06公克 0.2公克"))
    let unit = NonRegression.explain(v2: NutritionLabelTextParser().parse(grams, inputSHA256: hash), v3: parse(grams))
    #expect(unit.items == [.unitOffTemplate, .newWarnings])
    #expect(unit.unexplained.isEmpty)
    let mixed = label(body: rows.replacingOccurrences(of: "蛋白質 3.0公克 10.0公克", with: "蛋白質\n3.0公克\n10.0公克"))
    let lost = NonRegression.explain(v2: NutritionLabelTextParser().parse(mixed, inputSHA256: hash), v3: parse(mixed))
    #expect(!lost.unexplained.isEmpty, "a table v2 read and v3 declines is never on the allow-list")
    let gap = label(body: rows.replacingOccurrences(of: "脂肪 4.5公克 15.0公克", with: "脂肪 4.5公克 其中飽和脂肪 1.5公克"))
    let twoRows = NonRegression.explain(v2: NutritionLabelTextParser().parse(gap, inputSHA256: hash), v3: parse(gap), text: gap)
    #expect(twoRows.items == [.hanBetweenValues])
    #expect(twoRows.unexplained.isEmpty)
    for bound in ["鈉 5 毫克 以下 10 毫克 以下", "鈉 5 毫克 以上 10 毫克 以上", "鈉 60毫克 200毫克\n*鈉 50毫克 120毫克"] {
        let text = label(body: rows.replacingOccurrences(of: "鈉 60毫克 200毫克", with: bound))
        let verdict = NonRegression.explain(v2: NutritionLabelTextParser().parse(text, inputSHA256: hash), v3: parse(text), text: text)
        #expect(verdict.unexplained.isEmpty, "\(bound): \(verdict.unexplained)")
    }
    let boundVerdict = label(body: rows.replacingOccurrences(of: "鈉 60毫克 200毫克", with: "鈉 5 毫克 以下 10 毫克 以下"))
    #expect(NonRegression.explain(v2: NutritionLabelTextParser().parse(boundVerdict, inputSHA256: hash), v3: parse(boundVerdict),
                                  text: boundVerdict).items == [.boundsAndDuplicates])
    let titled = label("【營養標示】\n" + servingLines)
    let read = NonRegression.explain(v2: NutritionLabelTextParser().parse(titled, inputSHA256: hash), v3: parse(titled))
    #expect(!read.unexplained.isEmpty, "a case v2 declined and v3 reads needs the truth oracle")
}

private extension LabelLanguage {
    var isMixed: Bool { self == .mixed }
}
