import LabelValueMatching
import XCTest

/// Locator v3 (17.15) attack scenarios, written before the change: header bases, the
/// reference-intake column confirmed by its % unit and position, and a per-serving header printed
/// with its serving quantity in brackets (D4). Synthetic observations only. A wrong value must
/// never be found.
final class LabelValueMatcherReferenceIntakeTests: XCTestCase {
    typealias M = LabelValueMatcher

    struct Row { let label: String; let amount: String; let per100: String; let intake: String }
    // 蛋白質 prints 12公克 and 12%: a % value with a matching amount-like number.
    let rows = [Row(label: "熱量", amount: "485大卡", per100: "262大卡", intake: "24%"),
                Row(label: "蛋白質", amount: "12公克", per100: "6.8公克", intake: "12%"),
                Row(label: "脂肪", amount: "3公克", per100: "1.6公克", intake: "5%"),
                Row(label: "飽和脂肪", amount: "1.2公克", per100: "0.6公克", intake: "7%"),
                Row(label: "碳水化合物", amount: "65.2公克", per100: "35.2公克", intake: "22%"),
                Row(label: "鈉", amount: "120毫克", per100: "65毫克", intake: "6%")]
    var labels: [String] { rows.map(\.label) }
    let serving = "每一份量30公克"
    let intakeHeader = "每日參考值百分比"

    func line(_ text: String, x: Double, y: Double, width: Double = 0.08) -> M.Line {
        .init(text: text, box: .init(x: x - width / 2, y: y, width: width, height: 0.04))
    }

    /// Value columns at the given centres; each column is (centre, value for a row). Header lines
    /// sit in the band above the first row (row centres at 0.82, 0.74, ...).
    func table(columns: [(x: Double, value: (Row) -> String)], headerLines: [M.Line], servingLine: Bool = true) -> [M.Line] {
        var lines = headerLines
        if servingLine { lines.append(line(serving, x: 0.2, y: 0.97, width: 0.3)) }
        for (index, row) in rows.enumerated() {
            let y = 0.80 - Double(index) * 0.08
            lines.append(line(row.label, x: 0.11, y: y, width: 0.12))
            for column in columns { lines.append(line(column.value(row), x: column.x, y: y)) }
        }
        return lines
    }

    /// 每份 over the amount column at 0.45; the reference-intake header over two lines at 0.72.
    var twoColumnHeaders: [M.Line] {
        [line("每份", x: 0.45, y: 0.90), line("每日參考值", x: 0.72, y: 0.915, width: 0.14), line("百分比", x: 0.72, y: 0.875)]
    }
    var twoColumn: [M.Line] {
        table(columns: [(0.45, { $0.amount }), (0.72, { $0.intake })], headerLines: twoColumnHeaders)
    }

    func queries(_ columns: [(header: String, value: (Row) -> String)], withServing: Bool = true) -> [M.Query] {
        var result: [M.Query] = []
        for (index, row) in rows.enumerated() {
            for (column, spec) in columns.enumerated() {
                result.append(.init(id: "r\(index)c\(column)", rowLabel: row.label, headerText: spec.header, printedText: spec.value(row)))
            }
        }
        if withServing { result.append(.init(id: "serving", rowLabel: nil, headerText: nil, printedText: serving)) }
        return result
    }

    func locate(_ queries: [M.Query], _ lines: [M.Line], headers: [String], bases: [M.HeaderBasis]) -> [String: M.Status] {
        let located = M.locate(queries, lines: lines, headers: headers, rowLabels: labels, columnCount: headers.count,
                               headerBases: bases) { _, _ in nil }
        return Dictionary(uniqueKeysWithValues: zip(queries.map(\.id), located.map(\.status)))
    }

    func foundValues(_ status: [String: M.Status]) -> [String] {
        status.filter { $0.key != "serving" && $0.value == .found }.map(\.key).sorted()
    }

    // MARK: the lever

    func testTwoLineReferenceIntakeHeaderNoLongerBlocksTheTable() {
        let correct = queries([("每份", { $0.amount }), (intakeHeader, { $0.intake })])
        let status = locate(correct, twoColumn, headers: ["每份", intakeHeader], bases: [.amount, .referenceIntake])
        XCTAssertEqual(foundValues(status).count, 12)
        // v2's rule (no bases: every header must be located) finds none of them.
        let legacy = M.locate(correct, lines: twoColumn, headers: ["每份", intakeHeader], rowLabels: labels, columnCount: 2) { _, _ in nil }
        XCTAssertFalse(legacy.dropLast().contains { $0.status == .found })
    }

    func testOneLineReferenceIntakeHeaderMustBeAboveItsValues() {
        let correct = queries([("每份", { $0.amount }), (intakeHeader, { $0.intake })])
        let oneLine = table(columns: [(0.45, { $0.amount }), (0.72, { $0.intake })],
                            headerLines: [line("每份", x: 0.45, y: 0.90), line(intakeHeader, x: 0.72, y: 0.90, width: 0.16)])
        XCTAssertEqual(foundValues(locate(correct, oneLine, headers: ["每份", intakeHeader], bases: [.amount, .referenceIntake])).count, 12)
        // Printed (and located) left of 每份 while the reading puts it to the right: nothing confirms.
        let swapped = table(columns: [(0.30, { $0.intake }), (0.55, { $0.amount })],
                            headerLines: [line("每份", x: 0.55, y: 0.90), line(intakeHeader, x: 0.30, y: 0.90, width: 0.16)])
        XCTAssertEqual(foundValues(locate(correct, swapped, headers: ["每份", intakeHeader], bases: [.amount, .referenceIntake])), [])
    }

    // MARK: attacks

    func testPercentColumnMislabelledAsAnAmountColumnIsNeverFound() {
        // The reading calls the % column an amount column: its header must then be located, and is not.
        let mislabelled = queries([("每份", { $0.amount }), (intakeHeader, { $0.intake })])
        XCTAssertEqual(foundValues(locate(mislabelled, twoColumn, headers: ["每份", intakeHeader], bases: [.amount, .amount])), [])
        // The model reads the % values under 每份 (and the amounts under the intake header).
        let swappedValues = queries([("每份", { $0.intake }), (intakeHeader, { $0.amount })])
        XCTAssertEqual(foundValues(locate(swappedValues, twoColumn, headers: ["每份", intakeHeader], bases: [.amount, .referenceIntake])), [])
    }

    func testAmountColumnMislabelledAsReferenceIntakeIsNeverFound() {
        // The reverse: the reading calls the amount column reference intake and the % column an amount.
        let reversed = queries([("每份", { $0.amount }), (intakeHeader, { $0.intake })])
        XCTAssertEqual(foundValues(locate(reversed, twoColumn, headers: ["每份", intakeHeader], bases: [.referenceIntake, .amount])), [])
        // Every column called reference intake: no amount header to confirm anything.
        XCTAssertEqual(foundValues(locate(reversed, twoColumn, headers: ["每份", intakeHeader],
                                          bases: [.referenceIntake, .referenceIntake])), [])
    }

    func testAmountHeaderMissingWithThePercentHeaderReadFindsNothing() {
        let correct = queries([("每份", { $0.amount }), (intakeHeader, { $0.intake })])
        let noAmountHeader = table(columns: [(0.45, { $0.amount }), (0.72, { $0.intake })],
                                   headerLines: [line(intakeHeader, x: 0.72, y: 0.90, width: 0.16)])
        XCTAssertEqual(foundValues(locate(correct, noAmountHeader, headers: ["每份", intakeHeader], bases: [.amount, .referenceIntake])), [])
        // An amount header with no printed text can never be located either.
        let unprinted = queries([("", { $0.amount }), (intakeHeader, { $0.intake })])
        XCTAssertEqual(foundValues(locate(unprinted, twoColumn, headers: ["", intakeHeader], bases: [.amount, .referenceIntake])), [])
    }

    func testPercentValueWithAMatchingAmountLikeNumberIsNeverTakenForTheOther() {
        // 蛋白質 prints 12公克 and 12%. The model gives each the other's unit.
        var wrong = queries([("每份", { $0.amount }), (intakeHeader, { $0.intake })], withServing: false)
        wrong = wrong.map { query in
            guard query.rowLabel == "蛋白質" else { return query }
            let text = query.headerText == "每份" ? "12%" : "12公克"
            return .init(id: query.id, rowLabel: query.rowLabel, headerText: query.headerText, printedText: text)
        }
        let status = locate(wrong, twoColumn, headers: ["每份", intakeHeader], bases: [.amount, .referenceIntake])
        XCTAssertNotEqual(status["r1c0"], .found)
        XCTAssertNotEqual(status["r1c1"], .found)
        XCTAssertEqual(foundValues(status).count, 10)
    }

    func testAdjacentRowPercentValueIsNeverFound() {
        // The model gives 脂肪 the % printed on the 蛋白質 row.
        let shifted = queries([("每份", { $0.amount }), (intakeHeader, { $0.label == "脂肪" ? "12%" : $0.intake })])
        let status = locate(shifted, twoColumn, headers: ["每份", intakeHeader], bases: [.amount, .referenceIntake])
        XCTAssertNotEqual(status["r2c1"], .found)
    }

    func testPercentColumnPrintedOnTheOtherSideIsNeverFound() {
        // Printed % column left of 每份; the reading puts it to the right.
        let leftIntake = table(columns: [(0.30, { $0.intake }), (0.55, { $0.amount })], headerLines: [line("每份", x: 0.55, y: 0.90)])
        let reading = queries([("每份", { $0.amount }), (intakeHeader, { $0.intake })])
        let status = locate(reading, leftIntake, headers: ["每份", intakeHeader], bases: [.amount, .referenceIntake])
        XCTAssertEqual(foundValues(status).filter { $0.hasSuffix("c1") }, [])
    }

    func testAnOmittedColumnIsNeverTakenForOneTheReadingHas() {
        // Printed: 每份, 每100公克, %. The reading has 每份 and the reference intake only.
        let threeColumns = table(columns: [(0.40, { $0.amount }), (0.60, { $0.per100 }), (0.80, { $0.intake })],
                                 headerLines: [line("每份", x: 0.40, y: 0.90), line("每100公克", x: 0.60, y: 0.90, width: 0.12),
                                               line("每日參考值", x: 0.80, y: 0.915, width: 0.14), line("百分比", x: 0.80, y: 0.875)])
        let per100AsServing = queries([("每份", { $0.per100 }), (intakeHeader, { $0.intake })])
        XCTAssertEqual(foundValues(locate(per100AsServing, threeColumns, headers: ["每份", intakeHeader], bases: [.amount, .referenceIntake])), [])
        // The real 每份 header unread and a stray 每份 over the per-100 column (C1 with a basis).
        let stray = table(columns: [(0.40, { $0.amount }), (0.60, { $0.per100 }), (0.80, { $0.intake })],
                          headerLines: [line("每份", x: 0.60, y: 0.90), line("每日參考值", x: 0.80, y: 0.915, width: 0.14),
                                        line("百分比", x: 0.80, y: 0.875)])
        XCTAssertEqual(foundValues(locate(per100AsServing, stray, headers: ["每份", intakeHeader], bases: [.amount, .referenceIntake])), [])
        // An unheaded second % column, read as the reference intake.
        let twoPercent = table(columns: [(0.40, { $0.amount }), (0.60, { $0.intake }), (0.80, { _ in "1%" })],
                               headerLines: [line("每份", x: 0.40, y: 0.90)])
        let lastAsIntake = queries([("每份", { $0.amount }), (intakeHeader, { _ in "1%" })])
        let status = locate(lastAsIntake, twoPercent, headers: ["每份", intakeHeader], bases: [.amount, .referenceIntake])
        XCTAssertEqual(foundValues(status).filter { $0.hasSuffix("c1") }, [])
    }

    func testThreeColumnsWithSwappedAmountsFindNoSwappedValue() {
        let threeColumns = table(columns: [(0.40, { $0.amount }), (0.60, { $0.per100 }), (0.80, { $0.intake })],
                                 headerLines: [line("每份", x: 0.40, y: 0.90), line("每100公克", x: 0.60, y: 0.90, width: 0.12),
                                               line("每日參考值", x: 0.80, y: 0.915, width: 0.14), line("百分比", x: 0.80, y: 0.875)])
        let headers = ["每份", "每100公克", intakeHeader]
        let bases: [M.HeaderBasis] = [.amount, .amount, .referenceIntake]
        let correct = queries([("每份", { $0.amount }), ("每100公克", { $0.per100 }), (intakeHeader, { $0.intake })])
        XCTAssertEqual(foundValues(locate(correct, threeColumns, headers: headers, bases: bases)).count, 18)
        let swapped = queries([("每份", { $0.per100 }), ("每100公克", { $0.amount }), (intakeHeader, { $0.intake })])
        XCTAssertEqual(foundValues(locate(swapped, threeColumns, headers: headers, bases: bases)).filter { !$0.hasSuffix("c2") }, [])
        // Headers swapped in the reading: their order on the photo disagrees, so nothing confirms.
        let swappedHeaders = queries([("每100公克", { $0.amount }), ("每份", { $0.per100 }), (intakeHeader, { $0.intake })])
        XCTAssertEqual(foundValues(locate(swappedHeaders, threeColumns, headers: ["每100公克", "每份", intakeHeader], bases: bases)), [])
    }

    func testANarrowColumnTouchingAnAmountColumnIsNeverFound() {
        // E2 with bases: a narrow unheaded column just right of 每份 (x 0.51 to 0.55), read either as
        // per serving or as the reference intake; the cell must hold one token and the row no more
        // tokens than the reading has columns.
        for narrow in ["5公克", "9%"] {
            var lines = twoColumn
            for index in rows.indices {
                lines.append(line(narrow, x: 0.53, y: 0.80 - Double(index) * 0.08, width: 0.04))
            }
            let asAmount = queries([("每份", { _ in narrow }), (intakeHeader, { $0.intake })])
            let asIntake = queries([("每份", { $0.amount }), (intakeHeader, { _ in narrow })])
            for reading in [asAmount, asIntake] {
                let status = locate(reading, lines, headers: ["每份", intakeHeader], bases: [.amount, .referenceIntake])
                XCTAssertEqual(foundValues(status).filter { id in reading.first { $0.id == id }?.printedText == narrow }, [], narrow)
            }
        }
    }

    // MARK: #322 round 1

    func withServing(_ reading: [M.Query], _ text: String) -> [M.Query] {
        reading.map { $0.id == "serving" ? M.Query(id: "serving", rowLabel: nil, headerText: nil, printedText: text) : $0 }
    }

    func testAServingSizeMisreadAsATableValueIsNeverFound() {
        // G1 / F9: the photo prints 每一份量30公克; the model reads 3公克, which is 脂肪's value.
        let misread = withServing(queries([("每份", { $0.amount }), (intakeHeader, { $0.intake })]), "每一份量3公克")
        let status = locate(misread, twoColumn, headers: ["每份", intakeHeader], bases: [.amount, .referenceIntake])
        XCTAssertNotEqual(status["serving"], .found)
        // F8d: the same misread beside a header printed with its quantity: the header is not vouched for.
        let d4 = locate(misread, bracketed("每份（30公克）"), headers: ["每份", intakeHeader], bases: [.amount, .referenceIntake])
        XCTAssertEqual(d4.filter { $0.value == .found }.map(\.key), [])
        // F8c: the bracket says 35 g, the printed serving line 30 g, and the model reads 35 g.
        let f8c = withServing(queries([("每份", { $0.amount }), (intakeHeader, { $0.intake })]), "每一份量35公克")
        XCTAssertEqual(locate(f8c, bracketed("每份（35公克）"), headers: ["每份", intakeHeader], bases: [.amount, .referenceIntake])
            .filter { $0.value == .found }.map(\.key), [])
        // Control: read correctly, the serving line is found on its own line.
        XCTAssertEqual(locate(queries([("每份", { $0.amount }), (intakeHeader, { $0.intake })]), twoColumn, headers: ["每份", intakeHeader],
                              bases: [.amount, .referenceIntake])["serving"], .found)
    }

    func testTwoPercentColumnsNeedTheReferenceIntakeHeader() {
        // G2 / F5b: two % columns between the amount columns, neither % header read, the first
        // blank on the top rows so their token count fits; the model reads the second.
        var lines = [line("每份", x: 0.30, y: 0.90), line("每100公克", x: 0.80, y: 0.90, width: 0.12), line(serving, x: 0.2, y: 0.97, width: 0.3)]
        for (index, row) in rows.enumerated() {
            let y = 0.80 - Double(index) * 0.08
            lines.append(line(row.label, x: 0.11, y: y, width: 0.12))
            lines.append(line(row.amount, x: 0.30, y: y))
            if index >= 3 { lines.append(line("9%", x: 0.48, y: y)) }
            lines.append(line(row.intake, x: 0.62, y: y))
            lines.append(line(row.per100, x: 0.80, y: y))
        }
        let reading = queries([("每份", { $0.amount }), (intakeHeader, { $0.intake }), ("每100公克", { $0.per100 })])
        let status = locate(reading, lines, headers: ["每份", intakeHeader, "每100公克"], bases: [.amount, .referenceIntake, .amount])
        XCTAssertEqual(status.filter { $0.key.hasSuffix("c1") && $0.value == .found }.map(\.key), [])
        // Per serving is still found on the top rows; on the rows that print both % columns the row
        // holds more tokens than the reading has columns, so nothing there is confirmed.
        XCTAssertEqual(status.filter { $0.key.hasSuffix("c0") && $0.value == .found }.map(\.key).sorted(), ["r0c0", "r1c0", "r2c0"])
    }

    func testAReferenceIntakeColumnHoldingAmountsConfirmsNothing() {
        // C1 under a first-column reference intake: the reading calls a column of amounts reference
        // intake, and its header is not located; its bases are wrong, so nothing confirms.
        let lines = table(columns: [(0.45, { $0.amount }), (0.72, { $0.per100 })], headerLines: [line("每份", x: 0.72, y: 0.90)])
        let reading = queries([("每100公克", { $0.amount }), ("每份", { $0.per100 })])
        XCTAssertEqual(locate(reading, lines, headers: ["每100公克", "每份"], bases: [.referenceIntake, .amount])
            .filter { $0.key != "serving" && $0.value == .found }.map(\.key), [])
    }

    // MARK: #322 round 2

    func testTwoNarrowPercentColumnsCloseTogetherAreTwoPositions() {
        // H4: narrow % tokens (0.04 wide) at 0.55 (blank on the top rows) and a second column close
        // by; neither reference-intake header read; the model reads the second column.
        for second in [0.60, 0.64] {
            var lines = [line("每份", x: 0.30, y: 0.90), line("每100公克", x: 0.80, y: 0.90, width: 0.12),
                         line(serving, x: 0.2, y: 0.97, width: 0.3)]
            for (index, row) in rows.enumerated() {
                let y = 0.80 - Double(index) * 0.08
                lines.append(line(row.label, x: 0.11, y: y, width: 0.12))
                lines.append(line(row.amount, x: 0.30, y: y))
                if index >= 3 { lines.append(line("9%", x: 0.55, y: y, width: 0.04)) }
                lines.append(line(row.intake, x: second, y: y, width: 0.04))
                lines.append(line(row.per100, x: 0.80, y: y))
            }
            let reading = queries([("每份", { $0.amount }), (intakeHeader, { $0.intake }), ("每100公克", { $0.per100 })])
            let status = locate(reading, lines, headers: ["每份", intakeHeader, "每100公克"], bases: [.amount, .referenceIntake, .amount])
            XCTAssertEqual(status.filter { $0.key.hasSuffix("c1") && $0.value == .found }.map(\.key), [], "\(second)")
        }
    }

    func testServingWordsElsewhereDoNotVouchForAQuantity() {
        // H1: a footnote below the table prints the serving words beside a stray 3公克; the serving
        // line prints 30 g and the model reads 3 g.
        let lines = twoColumn + [line("*每一份量含膳食纖維 3公克", x: 0.25, y: 0.25, width: 0.4)]
        let misread = withServing(queries([("每份", { $0.amount }), (intakeHeader, { $0.intake })]), "每一份量3公克")
        XCTAssertNotEqual(locate(misread, lines, headers: ["每份", intakeHeader], bases: [.amount, .referenceIntake])["serving"], .found)
    }

    // MARK: D4, a per-serving header printed with its serving quantity

    func bracketed(_ header: String) -> [M.Line] {
        table(columns: [(0.45, { $0.amount }), (0.72, { $0.intake })],
              headerLines: [line(header, x: 0.45, y: 0.90, width: 0.14), line("每日參考值", x: 0.72, y: 0.915, width: 0.14),
                            line("百分比", x: 0.72, y: 0.875)])
    }

    func testHeaderWithTheServingQuantityInBracketsIsAHeader() {
        let correct = queries([("每份", { $0.amount }), (intakeHeader, { $0.intake })])
        for header in ["每份（30公克）", "每份(30 公克)"] {
            XCTAssertEqual(foundValues(locate(correct, bracketed(header), headers: ["每份", intakeHeader], bases: [.amount, .referenceIntake])).count,
                           12, header)
        }
    }

    func testBracketedQuantityThatIsNotTheServingSizeIsNotAHeader() {
        let correct = queries([("每份", { $0.amount }), (intakeHeader, { $0.intake })])
        for header in ["每份（35公克）", "每份（30毫升）", "每份（30公克）（2份）", "每份（30公克 12%）", "每份 30公克", "每份（約30公克）"] {
            XCTAssertEqual(foundValues(locate(correct, bracketed(header), headers: ["每份", intakeHeader], bases: [.amount, .referenceIntake])),
                           [], header)
        }
        // Without a serving line in the reading, no bracketed quantity is allowed.
        let noServing = queries([("每份", { $0.amount }), (intakeHeader, { $0.intake })], withServing: false)
        XCTAssertEqual(foundValues(locate(noServing, bracketed("每份（30公克）"), headers: ["每份", intakeHeader], bases: [.amount, .referenceIntake])),
                       [])
    }
}
