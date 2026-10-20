import Foundation
import Testing
@testable import NutritionLabelParsing

// Reader v3 section 8.4 (PR 4): the parser's unheaded shape and its reads with asserted bases,
// and `label-arithmetic-checks-v2`. Contract tests 10, 12, 17, 18, 23 and 9 of 8.4.15 at the
// parser. Every fixture is synthetic (`UnheadedTableFixtures`).

private let hash = String(repeating: "0", count: 64)
private let parser = NutritionLabelTextParserV3()
private typealias U = UnheadedTableFixtures

private func shape(_ text: String) -> NutritionLabelTextParserV3.UnheadedShape? { parser.unheadedShape(text, inputSHA256: hash) }
private func read(_ text: String, _ bases: [LabelBasis]) -> LabelCaptureCandidate {
    parser.parse(text, inputSHA256: hash, assertedBases: bases)
}

// MARK: 8.4.1: the shape, only for an unheaded table

@Test func everyInScopeLayoutHasAnUnheadedShapeWithItsColumnCount() {
    for fixture in U.inScope {
        let declined = parser.parse(fixture.text, inputSHA256: hash)
        #expect(declined.declineReasons == ["no_basis_header"], "\(fixture.name): \(declined.declineReasons)")
        // The declined candidate keeps today's shape: nothing read.
        #expect(declined.cells.isEmpty && declined.headers.isEmpty && declined.servingSize == nil && declined.servingsPerPack == nil,
                "\(fixture.name)")
        let found = shape(fixture.text)
        #expect(found?.amountColumnCount == fixture.columns, "\(fixture.name): \(String(describing: found))")
    }
}

@Test func theShapeCarriesTheServingSizePackCountReferenceColumnAndHint() throws {
    let one = try #require(shape(U.inline1))
    #expect(one.servingSize?.decimalText == "30")
    #expect(one.servingSize?.canonicalUnit == "g")
    #expect(one.servingsPerPack?.decimalText == "8")
    #expect(!one.referenceColumnPrinted)
    #expect(one.energyLineHint == nil)
    let reference = try #require(shape(U.referenceHeader))
    #expect(reference.referenceColumnPrinted)
    let hinted = try #require(shape(U.energyLine))
    #expect(hinted.energyLineHint == .init(printedText: "(每100毫升)", basis: .per100ml))
    #expect(hinted.servingSize == nil)
    let noServing = try #require(shape(U.twoColumnsNoServing))
    #expect(noServing.amountColumnCount == 2)
    #expect(noServing.servingSize == nil)
    // Every option declines too_little_read: the shape still exists (the application declines).
    #expect(shape(U.tooLittle)?.amountColumnCount == 1)
}

/// Test 12: mixed tables, in every layout, have no shape, so no sheet.
@Test func mixedTablesHaveNoShapeInAnyLayout() {
    for fixture in U.mixed {
        let declined = parser.parse(fixture.text, inputSHA256: hash)
        #expect(declined.declined, "\(fixture.name)")
        #expect(shape(fixture.text) == nil, "\(fixture.name): \(declined.declineReasons)")
        #expect(read(fixture.text, [.perServing, .per100g]).declineReasons == ["asserted_bases_mismatch"], "\(fixture.name)")
    }
    #expect(shape(U.referenceNotLast) == nil, "a percentage before an amount: no sheet")
    // 8.4.16 (narrowing, review of #284): percentages with no printed reference header bind to no
    // column, so such a table has no shape and keeps today's decline.
    let percentNoHeader = U.serving + ["熱量 120大卡 6%", "蛋白質 3.0公克 5%", "脂肪 4.5公克 8%", "飽和脂肪 1.5公克 8%", "反式脂肪 0公克 *",
                                       "碳水化合物 18.0公克 6%", "糖 6.0公克 *", "鈉 60毫克 3%"].joined(separator: "\n") + "\n"
    #expect(parser.parse(percentNoHeader, inputSHA256: hash).declineReasons == ["no_basis_header"])
    #expect(shape(percentNoHeader) == nil)
    // A table with printed headers, or any other decline, has no shape.
    #expect(shape(U.serving + "每份\n" + U.rows1.joined(separator: "\n")) == nil)
    #expect(shape("營養標示\n每份\n熱量 120大卡\n蛋白質 3.0公克 1.0公克\n") == nil)
}

// MARK: 8.4.2: reads with asserted bases

@Test func anAssertedReadHasAssertedHeadersWithEmptyTextAndNoConversion() {
    let one = read(U.inline1, [.per100g])
    #expect(!one.declined, "\(one.declineReasons)")
    #expect(one.headers.map(\.headerID) == ["header_1"])
    #expect(one.headers.map(\.basis) == [.per100g])
    #expect(one.headers.allSatisfy { $0.printedText.isEmpty && $0.servingConversion == nil })
    #expect(one.cells.allSatisfy { $0.headerID == "header_1" && $0.basis == .per100g && $0.servingConversion == "not_applicable" })
    let two = read(U.inline2, [.perServing, .per100g])
    #expect(two.headers.map(\.headerID) == ["header_1", "header_2"])
    #expect(two.headers.map(\.basis) == [.perServing, .per100g])
    // A per-serving column's cells carry the serving size, as for a printed header with none.
    #expect(two.cells.filter { $0.headerID == "header_1" }.allSatisfy { $0.servingConversion == "30公克" })
    // The printed reference header keeps its text and takes the next ID.
    let reference = read(U.referenceHeader, [.per100g])
    #expect(!reference.declined, "\(reference.declineReasons)")
    #expect(reference.headers.map(\.headerID) == ["header_1", "header_2"])
    #expect(reference.headers.map(\.basis) == [.per100g, .referenceIntake])
    #expect(reference.headers[1].printedText == "每日參考值百分比")
    #expect(reference.cells.contains { $0.headerID == "header_2" && $0.canonicalUnit == "%" })
}

@Test func everyInScopeFixtureReadsUnderEachOfItsColumnCountsBases() {
    for fixture in U.inScope {
        let bases: [LabelBasis] = fixture.columns == 1 ? [.per100g] : [.perServing, .per100g]
        let candidate = read(fixture.text, bases)
        #expect(!candidate.declined, "\(fixture.name): \(candidate.declineReasons)")
        #expect(candidate.cells.contains { $0.nutrient == "energy_kcal" }, "\(fixture.name)")
    }
}

@Test func anAssertedReadDeclinesWhenTheBasesDoNotFit() {
    #expect(read(U.inline1, [.perServing, .per100g]).declineReasons == ["asserted_bases_mismatch"], "count differs")
    #expect(read(U.inline2, [.per100g]).declineReasons == ["asserted_bases_mismatch"], "count differs")
    #expect(read(U.inline1, [.referenceIntake]).declineReasons == ["asserted_bases_mismatch"], "never reference intake")
    #expect(read(U.inline1, []).declineReasons == ["asserted_bases_mismatch"])
    let printed = U.serving + "每份\n" + U.rows1.joined(separator: "\n") + "\n"
    #expect(read(printed, [.per100g]).declineReasons == ["asserted_bases_mismatch"], "an amount header was printed")
}

/// Test 17: reads under different options differ only in the headers' basis and the cells'
/// header ID, basis and serving conversion; the declined candidate's warnings stay the hint alone.
@Test func assertedReadsDifferOnlyInBasisHeaderIDAndServingConversion() {
    for fixture in U.inScope {
        let options: [[LabelBasis]] = fixture.columns == 1 ? [[.perServing], [.per100g], [.per100ml]]
            : [[.perServing, .per100g], [.perServing, .per100ml]]
        let reads = options.map { read(fixture.text, $0) }
        guard let first = reads.first else { continue }
        for other in reads.dropFirst() {
            #expect(other.servingSize == first.servingSize && other.servingsPerPack == first.servingsPerPack, "\(fixture.name)")
            #expect(other.warnings == first.warnings && other.language == first.language, "\(fixture.name)")
            #expect(other.headers.map { [$0.headerID, $0.printedText] } == first.headers.map { [$0.headerID, $0.printedText] }, "\(fixture.name)")
            #expect(other.headers.map(\.servingConversion) == first.headers.map(\.servingConversion), "\(fixture.name)")
            let strip: (LabelCell) -> [String?] = { [$0.rowID, $0.parentRowID, $0.nutrient, $0.printedLabel, $0.printedText,
                                                    $0.comparator.rawValue, $0.decimalText, $0.unit, $0.canonicalUnit] }
            #expect(other.cells.map(strip) == first.cells.map(strip), "\(fixture.name)")
        }
    }
    let declined = parser.parse(U.energyLine, inputSHA256: hash)
    #expect(declined.warnings == ["basis_hint: energy_line: (每100毫升)"])
    #expect(parser.parse(U.inline1, inputSHA256: hash).warnings.isEmpty)
}

/// Test 18 and decision 24: the asserted read's serving size and pack count equal the shape's,
/// and the hint stays in its warnings, last.
@Test func theAssertedReadMatchesTheShapeAndKeepsTheHintLast() throws {
    for fixture in U.inScope {
        let found = try #require(shape(fixture.text), "\(fixture.name)")
        let candidate = read(fixture.text, fixture.columns == 1 ? [.per100ml] : [.perServing, .per100ml])
        #expect(candidate.servingSize == found.servingSize, "\(fixture.name)")
        #expect(candidate.servingsPerPack == found.servingsPerPack, "\(fixture.name)")
    }
    let hinted = read(U.energyLine, [.per100g])
    #expect(hinted.warnings.last == "basis_hint: energy_line: (每100毫升)")
    #expect(hinted.warnings.filter { $0.hasPrefix("basis_hint") }.count == 1)
    #expect(hinted.cells.first { $0.nutrient == "energy_kcal" }?.decimalText == "45", "the bracket is never a header and the row reads")
}

// MARK: 8.4.4: label-arithmetic-checks-v2

private func cell(_ nutrient: String, _ basis: String, _ unit: String, _ decimal: String, _ comparator: String = "=") -> LabelArithmeticCell {
    LabelArithmeticCell(nutrient: nutrient, basis: basis, canonicalUnit: unit, comparator: comparator, decimalText: decimal,
                        parentRowID: nil, unit: unit, printedText: decimal + unit)
}
private func table(_ cells: [LabelArithmeticCell], serving: (String, String)? = nil) -> LabelArithmeticTable {
    LabelArithmeticTable(jurisdiction: "taiwan", declined: false,
                         servingSize: serving.map { .init(decimalText: $0.0, canonicalUnit: $0.1) }, servingsPerPack: nil, cells: cells)
}
private func plausibility(_ table: LabelArithmeticTable, _ basis: String) -> (macronutrients: LabelCheckStatus, energy: LabelCheckStatus) {
    let checks = LabelArithmeticChecksV2.check(table, amountBases: [basis]).checks.filter { $0.name == "basis_plausibility" }
    return (checks.first { $0.nutrient == "macronutrients" }?.status ?? .notCheckable, checks.first { $0.nutrient == "energy" }?.status ?? .notCheckable)
}
private func macros(_ basis: String, _ protein: String?, _ fat: String?, _ carbohydrate: String?, comparators: [String] = ["=", "=", "="]) -> [LabelArithmeticCell] {
    zip(["protein", "fat", "carbohydrate"], zip([protein, fat, carbohydrate], comparators)).compactMap { nutrient, pair in
        pair.0.map { cell(nutrient, basis, "g", $0, pair.1) }
    }
}

/// Test 9: the golden vectors of 8.4.4. Per 100 g fails above 102 g of macronutrients and above
/// 918 kcal (3,840.912 kJ); per 100 ml above 153 g; per serving of 25 g above 25.5 g and 230 kcal.
@Test func checksV2GoldenVectors() {
    let g = "per_100g"
    #expect(plausibility(table(macros(g, "30", "20", "40")), g).macronutrients == .pass)          // 90
    #expect(plausibility(table(macros(g, "60", "30", "20")), g).macronutrients == .fail)          // 110
    #expect(plausibility(table(macros(g, "0.5", "99.9", "0.5", comparators: ["<", "=", "<"])), g).macronutrients == .pass)  // 100.9
    #expect(plausibility(table(macros(g, "2.5", "99", "1", comparators: ["=", "=", "<"])), g).macronutrients == .fail)       // 102.5
    #expect(plausibility(table(macros(g, nil, "103", nil)), g).macronutrients == .fail, "the partial sum is over")
    #expect(plausibility(table(macros(g, nil, "40", nil)), g).macronutrients == .notCheckable, "never pass on missing rows")
    #expect(plausibility(table(macros(g, "1", "1", "100")), g).macronutrients == .pass)          // 102 is within
    #expect(plausibility(table([cell("energy_kcal", g, "kcal", "918")]), g).energy == .pass)
    #expect(plausibility(table([cell("energy_kcal", g, "kcal", "919")]), g).energy == .fail)
    #expect(plausibility(table([cell("energy_kj", g, "kJ", "3850")]), g).energy == .fail)
    #expect(plausibility(table([cell("energy_kj", g, "kJ", "3840")]), g).energy == .pass)
    #expect(plausibility(table(macros(g, "1", "1", "1")), g).energy == .notCheckable, "no energy row")
    let ml = "per_100ml"
    #expect(plausibility(table(macros(ml, "0", "0", "140")), ml).macronutrients == .pass)
    #expect(plausibility(table(macros(ml, "0", "0", "160")), ml).macronutrients == .fail)
    #expect(plausibility(table([cell("energy_kcal", ml, "kcal", "830")]), ml).energy == .pass)
    let s = "per_serving"
    #expect(plausibility(table(macros(s, "0", "0", "30"), serving: ("25", "g")), s).macronutrients == .fail)
    #expect(plausibility(table(macros(s, "0", "0", "20"), serving: ("25", "g")), s).macronutrients == .pass)
    #expect(plausibility(table([cell("energy_kcal", s, "kcal", "230")], serving: ("25", "g")), s).energy == .pass)
    #expect(plausibility(table([cell("energy_kcal", s, "kcal", "231")], serving: ("25", "g")), s).energy == .fail)
    let perServingMl = plausibility(table(macros(s, "0", "0", "900") + [cell("energy_kcal", s, "kcal", "9000")], serving: ("250", "ml")), s)
    #expect(perServingMl.macronutrients == .notCheckable && perServingMl.energy == .notCheckable, "per serving in ml")
    let noServing = plausibility(table(macros(s, "0", "0", "900")), s)
    #expect(noServing.macronutrients == .notCheckable)
    // A failure is a warning code of v1's form; a pass adds nothing.
    let failing = LabelArithmeticChecksV2.check(table(macros(g, "60", "30", "20")), amountBases: [g])
    #expect(failing.warnings.contains("the chosen basis gives values no food has"))
}

/// Test 23: v1's checks in v1's order, then per basis in column order, macronutrients then energy.
@Test func checksV2KeepV1ChecksAndOrderThePlausibilityChecks() {
    let cells = macros("per_serving", "3", "4.5", "18") + macros("per_100g", "10", "15", "60")
        + [cell("energy_kcal", "per_serving", "kcal", "120"), cell("energy_kcal", "per_100g", "kcal", "400")]
    let t = table(cells, serving: ("30", "g"))
    let v1 = LabelArithmeticChecks.check(t).checks
    let v2 = LabelArithmeticChecksV2.check(t, amountBases: ["per_serving", "per_100g"]).checks
    #expect(Array(v2.prefix(v1.count)) == v1)
    #expect(v2.dropFirst(v1.count).map { "\($0.name):\($0.basis ?? ""):\($0.nutrient ?? "")" } == [
        "basis_plausibility:per_serving:macronutrients", "basis_plausibility:per_serving:energy",
        "basis_plausibility:per_100g:macronutrients", "basis_plausibility:per_100g:energy"
    ])
    #expect(LabelArithmeticChecksV2.version == "label-arithmetic-checks-v2")
    #expect(LabelArithmeticChecks.version == "label-arithmetic-checks-v1")
}
