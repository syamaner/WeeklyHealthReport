import Foundation
import NutritionLabelParsing
@testable import UKNutritionLabelParsing
import XCTest

/// Synthetic texts for UK reader v2 (`docs/pasted-nutrition-label-uk-english-v2-p1.md`), shaped
/// like the development causes C1 to C7 and C9. No real label text or value.
enum UKV2Cases {
    static let heading = "Typical values\tPer 100g\tPer 30g serving"
    static let body = [
        "Energy\t1500kJ / 360kcal\t450kJ / 108kcal", "Fat\t12.0g\t3.6g", "of which saturates\t4.0g\t1.2g",
        "Carbohydrate\t50.0g\t15.0g", "of which sugars\t20.0g\t6.0g", "Fibre\t3.0g\t0.9g", "Protein\t8.0g\t2.4g", "Salt\t0.50g\t0.15g",
    ]
    static let plain = ([heading] + body).joined(separator: "\n")

    static func text(_ lines: [String]) -> String { lines.joined(separator: "\n") }

    // S1 and S6-free count lines (C1, C6).
    static let countBefore = text(["Nutrition", ". Contains 3 Servings", heading] + body)
    static let packCountBefore = text(["NUTRITION INFORMATION", "150G PACK (3-4 SERVINGS PER PACK)", heading] + body)
    static let countAfter = text([heading] + body + ["Approximately 14 servings per pack\t\t\t"])
    static let packSizeOnly = text(["150g pack", heading] + body)
    static let countInside = text([heading] + body.prefix(2) + ["Contains 4 servings"] + body.dropFirst(2))

    // S2 (C3).
    static let vitamins = text([heading] + body + ["Vitamins and Minerals", "Typical values\tPer 100g\tPer 30g serving\t% NRV per 40g serving",
                                                   "Vitamin C\t35mg\t10.5mg\t13%", "Iron\t4.5mg\t1.4mg\t10%", "*NRV = Nutrient Reference Value"])
    static let vitaminsThenSodium = text([heading] + body + ["Vitamins & Minerals:", "Vitamin C\t35mg\t10.5mg", "Sodium\t0.2g\t0.06g"])

    // S3 (C7).
    static let per100Body = ["Energy\t1500kJ / 360kcal", "Fat\t12.0g", "of which saturates\t4.0g", "Carbohydrate\t50.0g",
                             "of which sugars\t20.0g", "Protein\t8.0g", "Salt\t0.50g"]
    static let servingBody = ["Energy\t1500kj / 360kCal"] + per100Body.dropFirst()
    static let stacked = text(["Nutritional Information", "Per 100g:"] + per100Body + ["Per Serving:"] + servingBody)
    static let stackedServingFirst = text(["Nutritional Information", "Per Serving:"] + servingBody + ["Per 100g:"] + per100Body)
    static let stackedDifferent = text(["Nutritional Information", "Per 100g:"] + per100Body + ["Per Serving:"]
        + servingBody.map { $0.replacingOccurrences(of: "12.0g", with: "3.6g") })
    static let stackedUnclear = text(["Nutritional Information", "Per pack:"] + per100Body + ["Per Serving:"] + servingBody)

    // S4 and S7 (C2).
    static let riHeading = "Typical Values\tPer 100g\tPer bar (15g)\t%RI*\tRI*"
    static let riBody = [
        "Energy\t2050kJ / 490kcal\t310kJ / 74kcal\t3%\t8400kJ / 2000kcal", "Fat\t20.0g\t2.6g\t4%\t70g", "Saturates\t10.0g\t1.3g\t7%\t20g",
        "Carbohydrate\t60.0g\t7.8g\t3%\t260g", "Sugars\t25.0g\t3.3g\t4%\t90g", "Fibre\t3.0g\t0.4g\t\t", "Protein\t6.0g\t0.8g\t2%\t50g",
        "Salt\t0.20g\t0.03g\t1%\t6g",
    ]
    static let referenceColumn = text(["Nutrition information", riHeading] + riBody
        + ["*Reference intake of an average adult (8400 kJ / 2000 kcal)\t\t-\t-\t"])
    static let referenceColumnRagged = text([riHeading] + riBody.prefix(1) + ["480kcal\t62kcal"] + riBody.dropFirst())
    static let riFootnote = text(["Typical values\tPer 100ml\tPer 200ml serving\t%RI"]
        + ["Energy\t180kJ / 43kcal\t360kJ / 86kcal\t4%", "Fat\t<0.5g\t<0.7g\t<1%", "Saturates\t<0.2g\t<0.2g\t<1%",
           "Carbohydrate\t9.0g\t18.0g\t7%", "Sugars\t8.5g\t17.0g\t19%", "Protein\t0.7g\t1.4g\t3%", "Salt\t0.07g\t0.14g\t2%"]
        + ["RI= Reference intake of an average adult (8400 kJ / 2000 kcal)", "", "This pack contains approx. 5 servings"])

    // S5 and N6 (C5).
    static let countCell = text(["This pack contains 12 servings\tPer 100g\tPer Slice 36g"] + body)
    static let noPer = text(["Typical Values\t100 ml\t250 ml serving"] + [
        "Energy\t180kJ / 43kcal\t450kJ / 108kcal", "Fat\t1.5g\t3.8g", "of which saturates\t1.0g\t2.5g", "Carbohydrate\t4.7g\t11.8g",
        "of which sugars\t4.7g\t11.8g", "Protein\t3.4g\t8.5g", "Salt\t0.10g\t0.25g",
    ])

    // N7 (C4), with S6's restated basis line.
    static let c4Pairs = ["Energy kJ", "180", "Energy kcal", "43", "Fat", "1.5g", "of which saturates", "1.0g", "Carbohydrate", "4.7g",
                          "of which sugars", "4.7g", "Protein", "3.4g", "Salt", "0.10g"]
    static let c4Safari = text(["Typical values\t", "Per 100ml"] + c4Pairs)
    static let c4Scripted = text(["Nutritional Values", "", "Typical values per 100ml", "", "Typical values\t", "Per 100ml", ""]
        + c4Pairs.flatMap { [$0, ""] })
    static let c4TwoLabels = text(["Typical values\t", "Per 100ml"] + ["Energy kJ", "Energy kcal"] + c4Pairs.dropFirst(2))
    static let c4TwoValues = text(["Typical values\t", "Per 100ml"] + ["Energy kJ", "180", "43"] + c4Pairs.dropFirst(2))
    static let c4TwoCells = text(["Typical values\t", "Per 100ml"] + ["Energy kJ", "180\t200"] + c4Pairs.dropFirst(2))
    static let c4Reference = text(["Typical values\t", "%RI"] + c4Pairs)
    static let c4Comparator = text(["Typical values\t", "Per 100ml"] + c4Pairs.dropLast(1) + ["<0.01g"])
    static let c4Trace = text(["Typical values\t", "Per 100ml"] + c4Pairs.dropLast(1) + ["Trace"])
    static let c4WithCount = text([". Contains 5 Servings", "Typical values\t", "Per 100ml"] + c4Pairs)
    static let c4WithVitamins = text(["Typical values\t", "Per 100ml"] + c4Pairs + ["Vitamins", "Vitamin D", "1.2µg"])
    static let c4Prepared = text(["Typical values\t", "(airfried) Per 100g"] + c4Pairs)

    // N4 with S2: a title glued to the first row.
    static let gluedWithVitamins = text(["Typical values\tPer 100g\tPer 30g serving",
                                         "Typical values Energy\t1500kJ / 360kcal\t450kJ / 108kcal"] + body.dropFirst()
        + ["Vitamins", "Vitamin C\t35mg\t10.5mg"])

    // Gate re-check of amendment 1: forms and negatives.
    static let countForms = [". Contains 6 portions", "This loaf contains 18 slices\t-\t-", ". approximately 9", "Contains approx. 7 servings"]
        .map { text(["Nutrition", $0, heading] + body) }
    static let countNegatives = ["Serves 4", "Contains 4 servings of fruit"].map { text(["Nutrition", $0, heading] + body) }
    static let titledHeadings = ["Nutritional data\tPer 100g\tPer 30g serving", "Table of nutritional information\tPer 100g\tPer 30g serving"]
        .map { text([$0] + body) }
    static let tableOfVitamins = text([heading] + body + ["", "Table of Vitamins and Minerals Information",
                                                         "Typical values\tPer 100g\tPer 30g serving\t% NRV", "Vitamin D (NRV)\t4.0µg\t1.2µg\t24%"])
    static let referenceColumnUntabbed = text([riHeading] + riBody.prefix(1) + ["Fat 20.0g 2.6g 4% 70g"] + riBody.dropFirst(2))
    static let c4OtherBasis = text(["Typical values per 100g", "Typical values\t", "Per 100ml"] + c4Pairs)
    static let footnoteWithValue = text([heading] + body + ["* Reference intake of an average adult (8400 kJ / 2000 kcal); fat 70g"])
    static let footnoteBeforeLastRow = text([heading] + body.dropLast() + ["RI= Reference intake of an average adult (8400 kJ / 2000 kcal)"]
        + body.suffix(1))
    static let oneBar = text(["Typical values\tPer 100g\tOne bar (25g)"] + body)
    static let fractionBag = text(["Typical values\tPer 100g\t1/6 of a bag (30g)"] + body)
    static let fractionNoWeight = text(["Typical values\tPer 100g\t1/6 of a bag"] + body)
    static let c4Duplicate = text(["Typical values\t", "Per 100ml"] + c4Pairs.prefix(4) + ["Fat", "1.5g", "Fat", "1.6g"] + c4Pairs.dropFirst(6))

    // I1 (C9 compound words) and its negatives.
    static func headed(_ heading: String) -> String { text([heading] + body) }

    static let positives = [countBefore, packCountBefore, countAfter, vitamins, stacked, stackedServingFirst, referenceColumn, riFootnote,
                            countCell, noPer, c4Safari, c4Scripted, c4Comparator, c4WithCount, c4WithVitamins, gluedWithVitamins]
    static let all = positives + [plain, packSizeOnly, countInside, vitaminsThenSodium, stackedDifferent, stackedUnclear,
                                  referenceColumnRagged, c4TwoLabels, c4TwoValues, c4TwoCells, c4Reference, c4Prepared, c4Trace]
        + countForms + countNegatives + titledHeadings + [tableOfVitamins, referenceColumnUntabbed, c4OtherBasis, footnoteWithValue,
                                                          footnoteBeforeLastRow, oneBar, fractionBag, fractionNoWeight, c4Duplicate]
}

final class UKReaderV2RuleTests: XCTestCase {
    let parser = NutritionLabelTextParserUK()

    func parse(_ text: String) -> LabelCaptureCandidate { parser.parse(text, inputSHA256: "synthetic") }
    func rules(_ text: String) -> [String] { parser.setAside(text).map(\.rule.rawValue) }
    func headers(_ text: String) -> [String] { parse(text).headers.map(\.printedText) }
    func bases(_ text: String) -> [LabelBasis] { parse(text).headers.map(\.basis) }

    func assertReads(_ text: String, _ message: String, file: StaticString = #filePath, line: UInt = #line) {
        let candidate = parse(text)
        XCTAssertFalse(candidate.declined, "\(message): \(candidate.declineReasons)", file: file, line: line)
    }

    // MARK: Test 1, per rule

    func testTheBaseTableReadsAndNothingIsSetAside() {
        assertReads(UKV2Cases.plain, "plain")
        XCTAssertEqual(rules(UKV2Cases.plain), [])
    }

    func testEachPositiveCaseNeededAV2RuleBeforeParserV3CouldReadIt() {
        let v3 = NutritionLabelTextParserV3()
        for (index, text) in UKV2Cases.positives.enumerated() {
            assertReads(text, "positive \(index)")
            let prepared = NutritionLabelTextParserUK.prepare(text)
            XCTAssertTrue(!prepared.region.setAside.isEmpty || prepared.n7Pairs != nil || prepared.lines != text.components(separatedBy: "\n"),
                          "positive \(index) fired no rule")
            XCTAssertTrue(v3.parse(text, inputSHA256: "synthetic").declined, "positive \(index) reads without a v2 rule")
        }
    }

    func testS1SetsCountLinesAsideBeforeAndAfterTheTableOnly() {
        XCTAssertEqual(rules(UKV2Cases.countBefore), ["S1"])
        XCTAssertEqual(rules(UKV2Cases.packCountBefore), ["S1"])
        XCTAssertEqual(rules(UKV2Cases.countAfter), ["S1"])
        for text in [UKV2Cases.countBefore, UKV2Cases.packCountBefore, UKV2Cases.countAfter] {
            XCTAssertNil(parse(text).servingsPerPack, "S1 never sets the servings per pack")
        }
        XCTAssertEqual(rules(UKV2Cases.packSizeOnly), [], "a pack size alone is kept")
        XCTAssertEqual(parse(UKV2Cases.countInside).declineReasons, [UKReadingGuard.regionInconsistent], "G4 takes precedence")
    }

    func testS2SetsAFollowingVitaminsTableAsideAndReportsItsRows() {
        XCTAssertEqual(Set(rules(UKV2Cases.vitamins)), ["S2"])
        let candidate = parse(UKV2Cases.vitamins)
        XCTAssertFalse(candidate.declined)
        let reported = candidate.warnings.filter { $0.hasPrefix("row_not_read: \(UKSetAsideReport.reason): ") }
        XCTAssertEqual(reported, ["row_not_read: uk_set_aside: Vitamin C", "row_not_read: uk_set_aside: Iron"],
                       "rows with values are reported; the footnote without one is not")
        XCTAssertFalse(candidate.cells.contains { $0.printedLabel.hasPrefix("Vitamin") })
        XCTAssertEqual(parse(UKV2Cases.vitaminsThenSodium).declineReasons, [UKTableRegion.rowsAfterTable])
    }

    func testS3KeepsThePer100TableOfIdenticalStackedTablesWhicheverComesFirst() {
        for text in [UKV2Cases.stacked, UKV2Cases.stackedServingFirst] {
            XCTAssertEqual(bases(text), [.per100g])
            XCTAssertTrue(rules(text).allSatisfy { $0 == "S3" } && !rules(text).isEmpty)
        }
        XCTAssertTrue(parse(UKV2Cases.stackedDifferent).declined, "any difference declines")
        XCTAssertEqual(rules(UKV2Cases.stackedDifferent), [])
        XCTAssertEqual(rules(UKV2Cases.stackedUnclear), [], "bases that cannot be told apart do not trigger S3")
    }

    func testS4SetsAReferenceValueColumnAsideAndKeepsThePercentColumn() {
        let candidate = parse(UKV2Cases.referenceColumn)
        XCTAssertFalse(candidate.declined, "\(candidate.declineReasons)")
        XCTAssertEqual(candidate.headers.map(\.basis), [.per100g, .perServing, .referenceIntake])
        XCTAssertFalse(candidate.cells.contains { ["8400", "2000", "70", "260", "90", "50", "6"].contains($0.decimalText) && $0.basis != .referenceIntake })
        XCTAssertTrue(candidate.cells.filter { $0.basis == .referenceIntake }.allSatisfy { $0.printedText.hasSuffix("%") })
        XCTAssertEqual(rules(UKV2Cases.referenceColumnRagged).filter { $0 == "S4" }, [], "ragged rows: nothing set aside")
        XCTAssertTrue(parse(UKV2Cases.referenceColumnRagged).declined)
    }

    func testS7SetsTheReferenceIntakeFootnoteAside() {
        XCTAssertEqual(rules(UKV2Cases.riFootnote), ["S7", "S1"], "set-aside entries are in line order")
        assertReads(UKV2Cases.riFootnote, "footnote")
    }

    func testS5AndN6ReadAHeadingWithoutPer() {
        XCTAssertEqual(rules(UKV2Cases.countCell), ["S5"])
        XCTAssertEqual(headers(UKV2Cases.countCell), ["Per 100g", "Per Slice 36g"])
        XCTAssertEqual(bases(UKV2Cases.noPer), [.per100ml, .perServing])
        XCTAssertEqual(headers(UKV2Cases.noPer), ["Per 100 ml", "Per 250 ml serving"])
    }

    // MARK: Test 2, N7

    func testN7ReadsBothCopyFormsIdentically() {
        let safari = parse(UKV2Cases.c4Safari), scripted = parse(UKV2Cases.c4Scripted)
        XCTAssertFalse(safari.declined, "\(safari.declineReasons)")
        XCTAssertEqual(safari.cells, scripted.cells)
        XCTAssertEqual(safari.headers, scripted.headers)
        XCTAssertEqual(rules(UKV2Cases.c4Scripted), ["S6"])
        XCTAssertEqual(NutritionLabelTextParserUK.prepare(UKV2Cases.c4Safari).n7Pairs, 8, "eight values: energy kJ and kcal are two")
    }

    func testN7LeavesEveryBrokenShapeToDecline() {
        for (name, text) in [("two labels", UKV2Cases.c4TwoLabels), ("two values", UKV2Cases.c4TwoValues),
                             ("two cells", UKV2Cases.c4TwoCells), ("reference basis", UKV2Cases.c4Reference)] {
            XCTAssertNil(NutritionLabelTextParserUK.prepare(text).n7Pairs, name)
            XCTAssertTrue(parse(text).declined, name)
        }
    }

    func testN7KeepsComparatorsAndNeverMakesAMarkerZero() {
        let candidate = parse(UKV2Cases.c4Comparator)
        XCTAssertFalse(candidate.declined, "\(candidate.declineReasons)")
        XCTAssertEqual(candidate.cells.first { $0.nutrient == "salt" }?.comparator, .less)
        // Parser v3 does not read `Trace` as a value here, so G4 (b) sees a pair it did not read and declines.
        let trace = parse(UKV2Cases.c4Trace)
        XCTAssertEqual(trace.declineReasons, [UKReadingGuard.regionInconsistent])
        XCTAssertFalse(trace.cells.contains { $0.decimalText == "0" })
    }

    // MARK: Test 5 and 6, bindings and rule interactions

    func testRuleInteractions() {
        XCTAssertEqual(rules(UKV2Cases.c4WithCount), ["S1"])
        assertReads(UKV2Cases.c4WithCount, "C4 with a count line")
        XCTAssertEqual(Set(rules(UKV2Cases.c4WithVitamins)), ["S2"])
        assertReads(UKV2Cases.c4WithVitamins, "C4 with vitamins")
        XCTAssertEqual(Set(rules(UKV2Cases.gluedWithVitamins)), ["S2"])
        assertReads(UKV2Cases.gluedWithVitamins, "N4 with S2")
        XCTAssertEqual(parse(UKV2Cases.vitaminsThenSodium).declineReasons, [UKTableRegion.rowsAfterTable])
    }

    // MARK: Amendment 1, gate re-check

    func testS1AcceptsItsClosedFormsAndNothingOutsideThem() {
        for (index, text) in UKV2Cases.countForms.enumerated() {
            XCTAssertEqual(rules(text), ["S1"], "form \(index)")
            assertReads(text, "form \(index)")
        }
        for text in UKV2Cases.countNegatives { XCTAssertEqual(rules(text), [], text) }
    }

    func testTheNewTitlesAreHeadingsAndFollowingTables() {
        for text in UKV2Cases.titledHeadings { assertReads(text, text) }
        let candidate = parse(UKV2Cases.tableOfVitamins)
        XCTAssertFalse(candidate.declined, "\(candidate.declineReasons)")
        XCTAssertEqual(candidate.warnings.filter { $0.contains(UKSetAsideReport.reason) }, ["row_not_read: uk_set_aside: Vitamin D (NRV)"],
                       "a vitamin row naming NRV is still reported")
    }

    func testS2ReportsOneCellPerLineVitaminRows() {
        let candidate = parse(UKV2Cases.c4WithVitamins)
        XCTAssertEqual(candidate.warnings.filter { $0.contains(UKSetAsideReport.reason) }, ["row_not_read: uk_set_aside: Vitamin D"])
    }

    func testS4ChecksSpaceAlignedRowsToo() {
        XCTAssertFalse(rules(UKV2Cases.referenceColumnUntabbed).contains("S4"))
        XCTAssertTrue(parse(UKV2Cases.referenceColumnUntabbed).declined)
    }

    func testS6OnlyDropsALineRestatingTheSameBasis() {
        XCTAssertFalse(rules(UKV2Cases.c4OtherBasis).contains("S6"))
        XCTAssertTrue(parse(UKV2Cases.c4OtherBasis).declined)
    }

    func testS7KeepsAFootnoteWithAValueAndOneBeforeTheLastRow() {
        XCTAssertFalse(rules(UKV2Cases.footnoteWithValue).contains("S7"))
        XCTAssertFalse(rules(UKV2Cases.footnoteBeforeLastRow).contains("S7"))
    }

    func testN6ServingFormsBindPerServingAndABareFractionIsLeft() {
        XCTAssertEqual(headers(UKV2Cases.oneBar), ["Per 100g", "Per One bar (25g)"])
        XCTAssertEqual(bases(UKV2Cases.oneBar), [.per100g, .perServing])
        XCTAssertEqual(headers(UKV2Cases.fractionBag), ["Per 100g", "Per 1/6 of a bag (30g)"])
        XCTAssertEqual(bases(UKV2Cases.fractionBag), [.per100g, .perServing])
        for text in [UKV2Cases.oneBar, UKV2Cases.fractionBag] {
            let serving = parse(text).servingSize
            XCTAssertTrue(serving == nil || ["25", "30"].contains(serving?.decimalText ?? ""), "serving size never binds to 1 or 6")
        }
        XCTAssertFalse(NutritionLabelTextParserUK.prepare(UKV2Cases.fractionNoWeight).lines[0].contains("Per 1/6"))
    }

    func testG4CountsDuplicateLabelsSoNoValueIsLostWithoutAWord() {
        let prepared = NutritionLabelTextParserUK.prepare(UKV2Cases.c4Duplicate)
        let candidate = parse(UKV2Cases.c4Duplicate)
        guard !candidate.declined, let values = prepared.n7Pairs else { return }
        let unread = candidate.warnings.filter { $0.hasPrefix("row_not_read: ") }.count
        XCTAssertEqual(candidate.cells.count + unread, values, "every value N7 wrote is a cell or an unread row")
    }

    // MARK: Test 8, identity I1

    func testI1DeclinesCompoundCookingWordsAndNothingElse() {
        for heading in ["Typical values\t(ovenbaked) Per 100 g\tPer 30g", "Typical values\tPer 100g airfried\tPer 30g",
                        "Typical values\tPer 100g ovenmicrowaved\tPer 30g", "Typical values\tPer 100g oven-baked\tPer 30g",
                        "Typical values\tPer 100g pan-fried\tPer 30g"] {
            XCTAssertEqual(parse(UKV2Cases.headed(heading)).declineReasons, [UKReadingGuard.basisStateNotSupported], heading)
        }
        XCTAssertEqual(parse(UKV2Cases.c4Prepared).declineReasons, [UKReadingGuard.basisStateNotSupported])
        for word in ["panettone", "airy", "deeply", "unbaked", "uncooked", "serving", "ovens", "stirred"] {
            XCTAssertFalse(UKReadingGuard.carriesIdentityMarker(word), word)
        }
        for word in ["ovenbaked", "airfried", "deepfried", "stirfried", "panroasted", "shallowfried", "ovenmicrowaved"] {
            XCTAssertTrue(UKReadingGuard.carriesIdentityMarker(word), word)
        }
    }

    // MARK: Test 3 and 4, accounting and normaliser properties

    static let number = try! NSRegularExpression(pattern: #"\d+(?:[.,]\d+)?|<|less than"#)

    static func tokens(_ texts: [String]) -> [String] {
        texts.flatMap { text in
            number.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { Range($0.range, in: text).map { String(text[$0]) } }
        }.sorted()
    }

    func testRegionAccountingKeepsEveryNumberAndComparator() {
        for (index, text) in UKV2Cases.all.enumerated() {
            let folded = text.components(separatedBy: "\n")
            let region = UKTableRegion.apply(folded)
            guard region.declineCode == nil else { continue }
            XCTAssertEqual(Self.tokens(region.kept + region.setAside.map(\.text)), Self.tokens(folded), "case \(index)")
            for entry in region.setAside {
                XCTAssertTrue(entry.line >= 0 && entry.line < folded.count, "case \(index)")
                let atPosition = entry.cell.map { folded[entry.line].components(separatedBy: "\t")[$0] } ?? folded[entry.line]
                XCTAssertEqual(atPosition, entry.text, "case \(index): \(entry.rule.rawValue) is not at its stated position")
            }
            if region.setAside.isEmpty { XCTAssertEqual(region.kept, folded, "case \(index) changed with nothing set aside") }
        }
    }

    func testNormalisationAddsOrDropsNoNumberOrComparator() {
        for (index, text) in UKV2Cases.all.enumerated() {
            let region = UKTableRegion.apply(text.components(separatedBy: "\n"))
            let normalised = UKTextNormalisation.lines(region.kept, english: true).lines
            XCTAssertEqual(Self.tokens(normalised), Self.tokens(region.kept), "case \(index)")
        }
    }

    // MARK: Test 9, language gating

    func testTheLanguageIsDecidedOnceOnThePastedText() {
        let taiwan = "營養標示\n每一份量30公克\n本包裝含4份\n每份\t每100公克\n熱量\t120大卡\t400大卡"
        let prepared = NutritionLabelTextParserUK.prepare(taiwan)
        XCTAssertFalse(prepared.english)
        XCTAssertEqual(prepared.region.setAside, [])
        XCTAssertEqual(prepared.lines, taiwan.components(separatedBy: "\n"))
        // Normalisation follows the decision it is given, not a check of its own on the kept lines.
        let lines = ["Typical values\t", "Per 100ml"] + UKV2Cases.c4Pairs
        XCTAssertNotNil(UKTextNormalisation.lines(lines, english: true).n7Pairs)
        XCTAssertNil(UKTextNormalisation.lines(lines, english: false).n7Pairs)
        for text in UKV2Cases.all {
            XCTAssertEqual(NutritionLabelTextParserUK.prepare(text).english,
                           NutritionLabelTextParserV3().parse(text, inputSHA256: "").language == .english)
        }
    }
}
