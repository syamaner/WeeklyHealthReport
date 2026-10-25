import LabelValueMatching
import XCTest

/// Synthetic observations only (section 12.5 test 11): unique, none, several, row band, column
/// band and full-width normalisation.
final class LabelValueMatcherTests: XCTestCase {
    typealias M = LabelValueMatcher

    // A two-column Taiwan table: headers at x 0.5 and 0.8, rows going down the page.
    let lines: [M.Line] = [
        .init(text: "每份", box: .init(x: 0.45, y: 0.90, width: 0.1, height: 0.04)),
        .init(text: "每100公克", box: .init(x: 0.72, y: 0.90, width: 0.16, height: 0.04)),
        .init(text: "熱量", box: .init(x: 0.05, y: 0.80, width: 0.1, height: 0.04)),
        .init(text: "４８５大卡", box: .init(x: 0.45, y: 0.80, width: 0.12, height: 0.04)),
        .init(text: "262 大卡", box: .init(x: 0.74, y: 0.80, width: 0.12, height: 0.04)),
        .init(text: "脂肪", box: .init(x: 0.05, y: 0.70, width: 0.1, height: 0.04)),
        .init(text: "0公克", box: .init(x: 0.45, y: 0.70, width: 0.1, height: 0.04)),
        .init(text: "0公克", box: .init(x: 0.74, y: 0.70, width: 0.1, height: 0.04)),
        .init(text: "飽和脂肪", box: .init(x: 0.05, y: 0.60, width: 0.12, height: 0.04)),
        .init(text: "0公克", box: .init(x: 0.45, y: 0.60, width: 0.1, height: 0.04)),
        .init(text: "15公克", box: .init(x: 0.74, y: 0.60, width: 0.1, height: 0.04)),
        .init(text: "每一份量 185 公克", box: .init(x: 0.05, y: 0.95, width: 0.4, height: 0.03)),
    ]
    let headers = ["每份", "每100 公克"]
    let rowLabels = ["熱量", "脂肪", "飽和脂肪", "鈉"]

    func locate(_ queries: [M.Query]) -> [M.Status] {
        M.locate(queries, lines: lines, headers: headers, rowLabels: rowLabels, columnCount: 2) { _, _ in nil }.map(\.status)
    }

    func testFullWidthDigitsAndSpacesNormalise() {
        XCTAssertEqual(locate([.init(id: "a", rowLabel: "熱量", headerText: "每份", printedText: "485 大卡")]), [.found])
        XCTAssertEqual(locate([.init(id: "b", rowLabel: "熱量", headerText: "每100 公克", printedText: "262大卡")]), [.found])
    }

    func testRowAndColumnBandsSeparateRepeatedValues() {
        XCTAssertEqual(locate([.init(id: "c", rowLabel: "脂肪", headerText: "每份", printedText: "0公克")]), [.found])
        XCTAssertEqual(locate([.init(id: "d", rowLabel: "脂肪", headerText: "每100 公克", printedText: "0公克")]), [.found])
    }

    func testLabelInsideAnotherLabelIsNotItsRow() {
        // "脂肪" must not match inside "飽和脂肪", or the fat row band would be ambiguous.
        XCTAssertEqual(locate([.init(id: "e", rowLabel: "飽和脂肪", headerText: "每份", printedText: "0公克")]), [.found])
    }

    func testValueInsideLongerNumberIsNotFound() {
        XCTAssertEqual(locate([.init(id: "f", rowLabel: "飽和脂肪", headerText: "每100 公克", printedText: "5公克")]), [.notFound])
    }

    func testMisreadValueIsNotFound() {
        XCTAssertEqual(locate([.init(id: "g", rowLabel: "熱量", headerText: "每份", printedText: "458大卡")]), [.notFound])
    }

    func testWithoutBandsRepeatedValueIsAmbiguous() {
        XCTAssertEqual(locate([.init(id: "h", rowLabel: "鈉", headerText: nil, printedText: "0公克")]), [.ambiguous])
    }

    func testServingLineByContainment() {
        XCTAssertEqual(locate([.init(id: "i", rowLabel: nil, headerText: nil, printedText: "每一份量185公克")]), [.found])
    }

    func testUnitReadAsItsOwnLineFallsBackToTheNumber() {
        let split: [M.Line] = [
            .init(text: "鈉", box: .init(x: 0.05, y: 0.5, width: 0.05, height: 0.04)),
            .init(text: "糖", box: .init(x: 0.05, y: 0.4, width: 0.05, height: 0.04)),
            .init(text: "20", box: .init(x: 0.45, y: 0.5, width: 0.05, height: 0.04)),
            .init(text: "毫克", box: .init(x: 0.5, y: 0.5, width: 0.05, height: 0.04)),
            .init(text: "20公克", box: .init(x: 0.45, y: 0.4, width: 0.08, height: 0.04)),
        ]
        let found = M.locate([.init(id: "k", rowLabel: "鈉", headerText: nil, printedText: "20 毫克"),
                              .init(id: "l", rowLabel: "糖", headerText: nil, printedText: "20公克")],
                             lines: split, headers: [], rowLabels: ["鈉", "糖"], columnCount: 1) { _, _ in nil }.map(\.status)
        XCTAssertEqual(found, [.found, .found])
    }

    func testSplitServingLineFallsBackToItsQuantity() {
        let split: [M.Line] = [.init(text: "每一份量", box: .init(x: 0.05, y: 0.9, width: 0.2, height: 0.04)),
                               .init(text: "185公克", box: .init(x: 0.3, y: 0.9, width: 0.1, height: 0.04))]
        XCTAssertEqual(M.locate([.init(id: "m", rowLabel: nil, headerText: nil, printedText: "每一份量 185 公克")], lines: split,
                                headers: [], rowLabels: [], columnCount: 1) { _, _ in nil }.map(\.status), [.found])
    }

    func testNearestRowCopesWithATiltedTable() {
        // Values drift down by most of a line across the table; the nearest row label still wins.
        let tilted: [M.Line] = [
            .init(text: "蛋白質", box: .init(x: 0.05, y: 0.60, width: 0.1, height: 0.04)),
            .init(text: "脂肪", box: .init(x: 0.05, y: 0.54, width: 0.1, height: 0.04)),
            .init(text: "0公克", box: .init(x: 0.6, y: 0.585, width: 0.1, height: 0.04)),
            .init(text: "0公克", box: .init(x: 0.6, y: 0.525, width: 0.1, height: 0.04)),
        ]
        XCTAssertEqual(M.locate([.init(id: "n", rowLabel: "脂肪", headerText: nil, printedText: "0公克")], lines: tilted,
                                headers: [], rowLabels: ["蛋白質", "脂肪"], columnCount: 1) { _, _ in nil }.map(\.status), [.found])
    }

    func testDriftedRepeatedValuesStayAmbiguousEvenWhenTheOrderWouldPlaceThem() {
        // The value column sits 0.035 below the labels (spacing 0.08, beyond the 1/3 limit): the
        // order would line the three 0公克 up by rank, but a drifted value is never placed.
        let shifted: [M.Line] = [
            .init(text: "每份", box: .init(x: 0.5, y: 0.9, width: 0.1, height: 0.04)),
            .init(text: "蛋白質", box: .init(x: 0.05, y: 0.80, width: 0.1, height: 0.04)),
            .init(text: "脂肪", box: .init(x: 0.05, y: 0.72, width: 0.1, height: 0.04)),
            .init(text: "飽和脂肪", box: .init(x: 0.05, y: 0.64, width: 0.1, height: 0.04)),
            .init(text: "0公克", box: .init(x: 0.5, y: 0.765, width: 0.1, height: 0.04)),
            .init(text: "0公克", box: .init(x: 0.5, y: 0.685, width: 0.1, height: 0.04)),
            .init(text: "0公克", box: .init(x: 0.5, y: 0.605, width: 0.1, height: 0.04)),
        ]
        let queries: [M.Query] = ["蛋白質", "脂肪", "飽和脂肪"].enumerated().map {
            .init(id: "r\($0.offset)", rowLabel: $0.element, headerText: "每份", printedText: "0 公克")
        }
        let found = M.locate(queries, lines: shifted, headers: ["每份"], rowLabels: ["蛋白質", "脂肪", "飽和脂肪"], columnCount: 1) { _, _ in nil }
        XCTAssertEqual(found.map(\.status), [.ambiguous, .ambiguous, .ambiguous])
        XCTAssertEqual(found.map { $0.region?.y }, [nil, nil, nil])
    }

    func testOrderIsNotUsedWhenTheCountsDiffer() {
        // Only two 0公克 occurrences for three values: one is missing, so rank cannot be trusted.
        let short: [M.Line] = [
            .init(text: "蛋白質", box: .init(x: 0.05, y: 0.80, width: 0.1, height: 0.04)),
            .init(text: "脂肪", box: .init(x: 0.05, y: 0.72, width: 0.1, height: 0.04)),
            .init(text: "飽和脂肪", box: .init(x: 0.05, y: 0.64, width: 0.1, height: 0.04)),
            .init(text: "0公克", box: .init(x: 0.5, y: 0.72, width: 0.1, height: 0.04)),
            .init(text: "0公克", box: .init(x: 0.6, y: 0.72, width: 0.1, height: 0.04)),
        ]
        let queries: [M.Query] = ["蛋白質", "脂肪", "飽和脂肪"].enumerated().map {
            .init(id: "s\($0.offset)", rowLabel: $0.element, headerText: nil, printedText: "0公克")
        }
        let found = M.locate(queries, lines: short, headers: [], rowLabels: ["蛋白質", "脂肪", "飽和脂肪"], columnCount: 1) { _, _ in nil }
        XCTAssertEqual(found.map(\.status), [.notFound, .ambiguous, .notFound])
    }

    func testHeadersPrintedOnOneLineAreBothFound() {
        let oneLine: [M.Line] = [
            .init(text: "反式脂肪", box: .init(x: 0.05, y: 0.5, width: 0.1, height: 0.04)),
            .init(text: "每份 每100公克", box: .init(x: 0.4, y: 0.9, width: 0.5, height: 0.04)),
            .init(text: "碳水化合物", box: .init(x: 0.05, y: 0.42, width: 0.1, height: 0.04)),
            .init(text: "0公克", box: .init(x: 0.45, y: 0.5, width: 0.1, height: 0.04)),
            .init(text: "0公克", box: .init(x: 0.75, y: 0.5, width: 0.1, height: 0.04)),
        ]
        // Sub-boxes: 每份 on the left half of the header line, 每100公克 on the right.
        let found = M.locate([.init(id: "t", rowLabel: "反式脂肪", headerText: "每100公克", printedText: "0公克")],
                             lines: oneLine, headers: ["每份", "每100公克"], rowLabels: ["反式脂肪", "碳水化合物"], columnCount: 2) { index, range in
            guard index == 1 else { return nil }
            let left = oneLine[1].text.distance(from: oneLine[1].text.startIndex, to: range.lowerBound) == 0
            return left ? .init(x: 0.42, y: 0.9, width: 0.1, height: 0.04) : .init(x: 0.72, y: 0.9, width: 0.16, height: 0.04)
        }
        XCTAssertEqual(found.map(\.status), [.found])
        XCTAssertEqual(found.first?.region?.x, 0.75)
    }

    // MARK: Order pass safety (invariant review of #320)

    /// One column printed 蛋白質 0公克 / 脂肪 3公克 / 飽和脂肪 0公克 / 反式脂肪 0公克; the model
    /// swaps fat (0公克, wrong) and saturated fat (3公克, wrong). Neither wrong value may be found,
    /// or the photo would hide a silent error.
    let swapLines: [M.Line] = [
        .init(text: "蛋白質", box: .init(x: 0.05, y: 0.80, width: 0.1, height: 0.04)),
        .init(text: "脂肪", box: .init(x: 0.05, y: 0.72, width: 0.1, height: 0.04)),
        .init(text: "飽和脂肪", box: .init(x: 0.05, y: 0.64, width: 0.1, height: 0.04)),
        .init(text: "反式脂肪", box: .init(x: 0.05, y: 0.56, width: 0.1, height: 0.04)),
        .init(text: "0公克", box: .init(x: 0.5, y: 0.80, width: 0.1, height: 0.04)),
        .init(text: "3公克", box: .init(x: 0.5, y: 0.72, width: 0.1, height: 0.04)),
        .init(text: "0公克", box: .init(x: 0.5, y: 0.64, width: 0.1, height: 0.04)),
        .init(text: "0公克", box: .init(x: 0.5, y: 0.56, width: 0.1, height: 0.04)),
    ]
    let swapLabels = ["蛋白質", "脂肪", "飽和脂肪", "反式脂肪"]

    func testSwappedValuesAreNotFoundAndTheOrderPassNeverMovesThem() {
        let queries: [M.Query] = zip(swapLabels, ["0公克", "0公克", "3公克", "0公克"]).enumerated().map {
            .init(id: "w\($0.offset)", rowLabel: $0.element.0, headerText: nil, printedText: $0.element.1)
        }
        let found = M.locate(queries, lines: swapLines, headers: [], rowLabels: swapLabels, columnCount: 1) { _, _ in nil }
        XCTAssertEqual(found.map(\.status), [.found, .notFound, .notFound, .found])
        XCTAssertEqual(found[0].region?.y, 0.80)
        XCTAssertEqual(found[3].region?.y, 0.56)
    }

    func testOrderPassPlacesNothingOnARowHoldingMoreNumbersThanTheReadingLists() {
        // Two 0公克 values both on the protein row of a one-column reading: the counts and order
        // would give protein the top one, but the row holds an unlisted number, so protein stays
        // ambiguous and fat not found.
        let crowded: [M.Line] = [
            .init(text: "蛋白質", box: .init(x: 0.05, y: 0.80, width: 0.1, height: 0.04)),
            .init(text: "脂肪", box: .init(x: 0.05, y: 0.60, width: 0.1, height: 0.04)),
            .init(text: "0公克", box: .init(x: 0.5, y: 0.81, width: 0.1, height: 0.04)),
            .init(text: "0公克", box: .init(x: 0.5, y: 0.75, width: 0.1, height: 0.04)),
        ]
        let queries: [M.Query] = [.init(id: "a", rowLabel: "蛋白質", headerText: nil, printedText: "0公克"),
                                  .init(id: "b", rowLabel: "脂肪", headerText: nil, printedText: "0公克")]
        let found = M.locate(queries, lines: crowded, headers: [], rowLabels: ["蛋白質", "脂肪"], columnCount: 1) { _, _ in nil }
        XCTAssertEqual(found.map(\.status), [.ambiguous, .notFound])
        XCTAssertNil(found[0].region)
    }

    func testNoOrderPassForTwoValueColumnsWithoutSeparableHeaders() {
        // Two value columns, no header text returned: the "column" would be the whole photo.
        let twoColumns: [M.Line] = [
            .init(text: "脂肪", box: .init(x: 0.05, y: 0.70, width: 0.1, height: 0.04)),
            .init(text: "飽和脂肪", box: .init(x: 0.05, y: 0.60, width: 0.1, height: 0.04)),
            .init(text: "0公克", box: .init(x: 0.45, y: 0.70, width: 0.1, height: 0.04)),
            .init(text: "0公克", box: .init(x: 0.75, y: 0.70, width: 0.1, height: 0.04)),
        ]
        let queries: [M.Query] = [.init(id: "c", rowLabel: "脂肪", headerText: nil, printedText: "0公克"),
                                  .init(id: "d", rowLabel: "脂肪", headerText: nil, printedText: "0公克")]
        let found = M.locate(queries, lines: twoColumns, headers: [], rowLabels: ["脂肪", "飽和脂肪"], columnCount: 2) { _, _ in nil }
        XCTAssertEqual(found.map(\.status), [.ambiguous, .ambiguous])
    }

    func testNoOrderPassWhenQueryOrderDiffersFromPrintedOrder() {
        // The same crowded column as above, but the queries list fat before protein.
        let crowded: [M.Line] = [
            .init(text: "蛋白質", box: .init(x: 0.05, y: 0.80, width: 0.1, height: 0.04)),
            .init(text: "脂肪", box: .init(x: 0.05, y: 0.60, width: 0.1, height: 0.04)),
            .init(text: "0公克", box: .init(x: 0.5, y: 0.81, width: 0.1, height: 0.04)),
            .init(text: "0公克", box: .init(x: 0.5, y: 0.75, width: 0.1, height: 0.04)),
        ]
        let queries: [M.Query] = [.init(id: "b", rowLabel: "脂肪", headerText: nil, printedText: "0公克"),
                                  .init(id: "a", rowLabel: "蛋白質", headerText: nil, printedText: "0公克")]
        let found = M.locate(queries, lines: crowded, headers: [], rowLabels: ["蛋白質", "脂肪"], columnCount: 1) { _, _ in nil }
        XCTAssertEqual(found.map(\.status), [.notFound, .ambiguous])
    }

    // MARK: First-pass row distance limit (re-check of #320)

    let rows = ["蛋白質", "脂肪", "飽和脂肪"]
    func rowLines(values: [(String, Double)]) -> [M.Line] {
        [.init(text: "蛋白質", box: .init(x: 0.05, y: 0.80, width: 0.1, height: 0.04)),
         .init(text: "脂肪", box: .init(x: 0.05, y: 0.72, width: 0.1, height: 0.04)),
         .init(text: "飽和脂肪", box: .init(x: 0.05, y: 0.64, width: 0.1, height: 0.04))]
            + values.map { .init(text: $0.0, box: .init(x: 0.5, y: $0.1, width: 0.1, height: 0.04)) }
    }

    func testTiltDriftOfFiveHundredthsAtEightHundredthsSpacingIsNeverFoundOnTheWrongRow() {
        // Printed: protein 0公克, fat 3公克, saturated fat 0公克; every value drifted 0.05 low.
        // The model wrongly reads fat as 0公克: protein's drifted 0公克 is now nearest fat.
        let lines = rowLines(values: [("0公克", 0.75), ("3公克", 0.67), ("0公克", 0.59)])
        let queries: [M.Query] = zip(rows, ["0公克", "0公克", "0公克"]).enumerated().map {
            .init(id: "t\($0.offset)", rowLabel: $0.element.0, headerText: nil, printedText: $0.element.1)
        }
        let found = M.locate(queries, lines: lines, headers: [], rowLabels: rows, columnCount: 1) { _, _ in nil }
        XCTAssertFalse(found.contains { $0.status == .found }, "\(found.map(\.status))")
        XCTAssertEqual(found[1].status, .ambiguous)
    }

    func testValuesHalfARowLowWithCompensatingErrorsAreNeverFound() {
        // Every value printed half a row (0.04) below its label; the model shifts each value up a
        // row, so each wrong value sits exactly between its own label and the next.
        let lines = rowLines(values: [("1公克", 0.76), ("2公克", 0.68), ("3公克", 0.60)])
        let queries: [M.Query] = zip(rows, ["2公克", "3公克", "1公克"]).enumerated().map {
            .init(id: "h\($0.offset)", rowLabel: $0.element.0, headerText: nil, printedText: $0.element.1)
        }
        let found = M.locate(queries, lines: lines, headers: [], rowLabels: rows, columnCount: 1) { _, _ in nil }
        XCTAssertFalse(found.contains { $0.status == .found }, "\(found.map(\.status))")
    }

    func testUnlistedSecondColumnMakesAOneColumnMatchAmbiguous() {
        // The reading has one column, but the fat row also prints a second value (5公克).
        let lines = rowLines(values: [("0公克", 0.80), ("3公克", 0.72), ("0公克", 0.64)])
            + [.init(text: "5公克", box: .init(x: 0.75, y: 0.72, width: 0.1, height: 0.04))]
        let queries: [M.Query] = zip(rows, ["0公克", "3公克", "0公克"]).enumerated().map {
            .init(id: "u\($0.offset)", rowLabel: $0.element.0, headerText: nil, printedText: $0.element.1)
        }
        let found = M.locate(queries, lines: lines, headers: [], rowLabels: rows, columnCount: 1) { _, _ in nil }
        XCTAssertEqual(found.map(\.status), [.found, .ambiguous, .found])
    }

    func testAlignedSingleColumnValuesAreStillFound() {
        let lines = rowLines(values: [("0公克", 0.80), ("3公克", 0.715), ("0公克", 0.645)])
        let queries: [M.Query] = zip(rows, ["0公克", "3公克", "0公克"]).enumerated().map {
            .init(id: "v\($0.offset)", rowLabel: $0.element.0, headerText: nil, printedText: $0.element.1)
        }
        let found = M.locate(queries, lines: lines, headers: [], rowLabels: rows, columnCount: 1) { _, _ in nil }
        XCTAssertEqual(found.map(\.status), [.found, .found, .found])
    }

    // MARK: Own row label not located (re-check of 8ebfe912)

    /// Case 10: the model writes the fat label as 脂舫 (not on the photo) and reads saturated fat's
    /// printed 3公克 as fat's value. It must not be found on the saturated fat row.
    func testUnlocatedOwnLabelNeverFindsAnotherRowsValue() {
        let lines = rowLines(values: [("0公克", 0.80), ("5公克", 0.72), ("3公克", 0.64)])
        let queries: [M.Query] = [.init(id: "p", rowLabel: "蛋白質", headerText: nil, printedText: "0公克"),
                                  .init(id: "f", rowLabel: "脂舫", headerText: nil, printedText: "3公克"),
                                  .init(id: "s", rowLabel: "飽和脂肪", headerText: nil, printedText: "3公克")]
        let found = M.locate(queries, lines: lines, headers: [], rowLabels: ["蛋白質", "脂舫", "飽和脂肪"], columnCount: 1) { _, _ in nil }
        XCTAssertNotEqual(found[1].status, .found)
        // v2 places 脂舫 on the printed 脂肪 line (one character different, between its located
        // neighbours), so the wrong value is plainly not on the fat row.
        XCTAssertEqual(found.map(\.status), [.found, .notFound, .found])
    }

    /// Case 10b: the same misspelt label, with the value printed on the fat row itself (between the
    /// located labels, near none of them): still not found, because its row cannot be confirmed.
    func testUnlocatedOwnLabelWithAValueOnNoOtherRowIsStillNotFound() {
        let lines = rowLines(values: [("0公克", 0.80), ("5公克", 0.72), ("1公克", 0.64)])
        let queries: [M.Query] = [.init(id: "p", rowLabel: "蛋白質", headerText: nil, printedText: "0公克"),
                                  .init(id: "f", rowLabel: "脂舫", headerText: nil, printedText: "5公克")]
        let found = M.locate(queries, lines: lines, headers: [], rowLabels: ["蛋白質", "脂舫"], columnCount: 1) { _, _ in nil }
        XCTAssertNotEqual(found[1].status, .found)
        XCTAssertEqual(found[1].status, .ambiguous)
    }

    // MARK: Locator v2 recovery (L1c, 17.11)

    func testMisreadLabelBetweenLocatedNeighboursIsRecoveredAndItsValueFound() {
        // Vision read 脂肪 as 脂舫; the model has the right label and value.
        let lines: [M.Line] = [
            .init(text: "蛋白質", box: .init(x: 0.05, y: 0.80, width: 0.1, height: 0.04)),
            .init(text: "脂舫", box: .init(x: 0.05, y: 0.72, width: 0.1, height: 0.04)),
            .init(text: "飽和脂肪", box: .init(x: 0.05, y: 0.64, width: 0.1, height: 0.04)),
            .init(text: "2公克", box: .init(x: 0.5, y: 0.80, width: 0.1, height: 0.04)),
            .init(text: "5公克", box: .init(x: 0.5, y: 0.72, width: 0.1, height: 0.04)),
            .init(text: "1公克", box: .init(x: 0.5, y: 0.64, width: 0.1, height: 0.04)),
        ]
        let queries: [M.Query] = zip(rows, ["2公克", "5公克", "1公克"]).enumerated().map {
            .init(id: "m\($0.offset)", rowLabel: $0.element.0, headerText: nil, printedText: $0.element.1)
        }
        let found = M.locate(queries, lines: lines, headers: [], rowLabels: rows, columnCount: 1) { _, _ in nil }
        XCTAssertEqual(found.map(\.status), [.found, .found, .found])
        // The wrong value read on the recovered row is still not found.
        var wrong = queries
        wrong[1] = .init(id: "m1", rowLabel: "脂肪", headerText: nil, printedText: "1公克")
        XCTAssertNotEqual(M.locate(wrong, lines: lines, headers: [], rowLabels: rows, columnCount: 1) { _, _ in nil }[1].status, .found)
    }

    func testUnreadLabelIsPlacedByRowOrderOnlyWhenTheGapFitsOneRow() {
        // 脂肪 was not read at all; its neighbours are one row step apart on either side.
        let lines: [M.Line] = [
            .init(text: "蛋白質", box: .init(x: 0.05, y: 0.80, width: 0.1, height: 0.04)),
            .init(text: "飽和脂肪", box: .init(x: 0.05, y: 0.64, width: 0.1, height: 0.04)),
            .init(text: "反式脂肪", box: .init(x: 0.05, y: 0.56, width: 0.1, height: 0.04)),
            .init(text: "2公克", box: .init(x: 0.5, y: 0.80, width: 0.1, height: 0.04)),
            .init(text: "5公克", box: .init(x: 0.5, y: 0.72, width: 0.1, height: 0.04)),
            .init(text: "1公克", box: .init(x: 0.5, y: 0.64, width: 0.1, height: 0.04)),
            .init(text: "0公克", box: .init(x: 0.5, y: 0.56, width: 0.1, height: 0.04)),
        ]
        let labels = ["蛋白質", "脂肪", "飽和脂肪", "反式脂肪"]
        let queries: [M.Query] = zip(labels, ["2公克", "5公克", "1公克", "0公克"]).enumerated().map {
            .init(id: "o\($0.offset)", rowLabel: $0.element.0, headerText: nil, printedText: $0.element.1)
        }
        XCTAssertEqual(M.locate(queries, lines: lines, headers: [], rowLabels: labels, columnCount: 1) { _, _ in nil }[1].status, .found)
        // An adjacent row's value under the placed label is still never found.
        var wrong = queries
        wrong[1] = .init(id: "o1", rowLabel: "脂肪", headerText: nil, printedText: "1公克")
        XCTAssertNotEqual(M.locate(wrong, lines: lines, headers: [], rowLabels: labels, columnCount: 1) { _, _ in nil }[1].status, .found)
        // A label missing from the very top or bottom is never placed (only one neighbour).
        let edge = Array(lines.dropFirst())
        XCTAssertNotEqual(M.locate(queries, lines: edge, headers: [], rowLabels: labels, columnCount: 1) { _, _ in nil }[0].status, .found)
    }

    func testTableWideOffsetIsRemovedWhenRowsAgree() {
        // Every value printed 0.035 below its label (spacing 0.08), beyond the 1/3 limit in v1.
        let labels = ["蛋白質", "脂肪", "飽和脂肪", "反式脂肪"]
        let values = ["2公克", "5公克", "1公克", "0公克"]
        var lines: [M.Line] = []
        for (index, label) in labels.enumerated() {
            let y = 0.80 - 0.08 * Double(index)
            lines.append(.init(text: label, box: .init(x: 0.05, y: y, width: 0.1, height: 0.04)))
            lines.append(.init(text: values[index], box: .init(x: 0.5, y: y - 0.035, width: 0.1, height: 0.04)))
        }
        let queries: [M.Query] = zip(labels, values).enumerated().map {
            .init(id: "t\($0.offset)", rowLabel: $0.element.0, headerText: nil, printedText: $0.element.1)
        }
        XCTAssertEqual(M.locate(queries, lines: lines, headers: [], rowLabels: labels, columnCount: 1) { _, _ in nil }.map(\.status),
                       [.found, .found, .found, .found])
        // With the offset removed, the next row's value is a whole row away: never found.
        var wrong = queries
        wrong[1] = .init(id: "t1", rowLabel: "脂肪", headerText: nil, printedText: "1公克")
        XCTAssertNotEqual(M.locate(wrong, lines: lines, headers: [], rowLabels: labels, columnCount: 1) { _, _ in nil }[1].status, .found)
    }

    func testColumnsAreInferredFromValueTokensWhenHeadersAreUnread() {
        let labels = ["蛋白質", "脂肪", "飽和脂肪"]
        let perServing = ["2公克", "3公克", "1公克"], per100 = ["4公克", "6公克", "2公克"]
        var lines: [M.Line] = []
        for (index, label) in labels.enumerated() {
            let y = 0.80 - 0.08 * Double(index)
            lines.append(.init(text: label, box: .init(x: 0.05, y: y, width: 0.1, height: 0.04)))
            lines.append(.init(text: perServing[index], box: .init(x: 0.45, y: y, width: 0.1, height: 0.04)))
            lines.append(.init(text: per100[index], box: .init(x: 0.75, y: y, width: 0.1, height: 0.04)))
        }
        var queries: [M.Query] = []
        for (index, label) in labels.enumerated() {
            queries.append(.init(id: "s\(index)", rowLabel: label, headerText: "每份", printedText: perServing[index]))
            queries.append(.init(id: "h\(index)", rowLabel: label, headerText: "每100公克", printedText: per100[index]))
        }
        let found = M.locate(queries, lines: lines, headers: ["每份", "每100公克"], rowLabels: labels, columnCount: 2) { _, _ in nil }
        XCTAssertEqual(found.map(\.status), Array(repeating: .found, count: 6))
        // S4: the other column's value in this column is never found.
        var wrong = queries
        wrong[2] = .init(id: "s1", rowLabel: "脂肪", headerText: "每份", printedText: "6公克")
        XCTAssertNotEqual(M.locate(wrong, lines: lines, headers: ["每份", "每100公克"], rowLabels: labels, columnCount: 2) { _, _ in nil }[2].status,
                          .found)
        // Header order unknown (only one header text for two columns): no inference.
        XCTAssertFalse(M.locate(queries, lines: lines, headers: ["每份"], rowLabels: labels, columnCount: 2) { _, _ in nil }
            .contains { $0.status == .found })
    }

    func testEvidenceSeparatesContradictedFromUnconfirmedValues() {
        let lines = rowLines(values: [("2公克", 0.80), ("5公克", 0.72), ("1公克", 0.64)])
        // Fat read as 1公克: printed only on the saturated fat row, and fat's own cell holds 5公克.
        let queries: [M.Query] = zip(rows, ["2公克", "1公克", "1公克"]).enumerated().map {
            .init(id: "v\($0.offset)", rowLabel: $0.element.0, headerText: nil, printedText: $0.element.1)
        }
        let found = M.locate(queries, lines: lines, headers: [], rowLabels: rows, columnCount: 1) { _, _ in nil }
        XCTAssertEqual(found[1].evidence, .conflictingInCell)
        // Fat read as 9公克: nowhere on the photo, own cell holds 5公克.
        var absent = queries
        absent[1] = .init(id: "v1", rowLabel: "脂肪", headerText: nil, printedText: "9公克")
        XCTAssertEqual(M.locate(absent, lines: lines, headers: [], rowLabels: rows, columnCount: 1) { _, _ in nil }[1].evidence,
                       .conflictingInCell)
        // A found value carries no evidence.
        XCTAssertEqual(found[0].evidence, .none)
    }

    func testNoRowLabelLocatedMeansAmbiguousNotFound() {
        let lines: [M.Line] = [.init(text: "3公克", box: .init(x: 0.5, y: 0.72, width: 0.1, height: 0.04))]
        let found = M.locate([.init(id: "x", rowLabel: "脂肪", headerText: nil, printedText: "3公克")], lines: lines, headers: [],
                             rowLabels: ["脂肪", "蛋白質"], columnCount: 1) { _, _ in nil }
        XCTAssertEqual(found.map(\.status), [.ambiguous])
    }

    // MARK: A found value never corroborates a wrong number, unit or bound (final re-check of #320)

    /// The fat row's printed text and the model's value; the other rows hold aligned values.
    func fatValue(printed: String, model: String) -> M.Status {
        let lines = rowLines(values: [("2公克", 0.80), (printed, 0.72), ("1公克", 0.64)])
        let queries: [M.Query] = zip(rows, ["2公克", model, "1公克"]).enumerated().map {
            .init(id: "q\($0.offset)", rowLabel: $0.element.0, headerText: nil, printedText: $0.element.1)
        }
        return M.locate(queries, lines: lines, headers: [], rowLabels: rows, columnCount: 1) { _, _ in nil }[1].status
    }

    func testS1UnitMisreadOnTheSameLineIsNotFound() {
        XCTAssertNotEqual(fatValue(printed: "20毫克", model: "20公克"), .found)
        XCTAssertEqual(fatValue(printed: "20毫克", model: "20毫克"), .found)
    }

    func testS1NumberAloneOnlyWhenTheUnitIsOnItsOwnLine() {
        // "20" ends its line but no unit line sits beside it: never found by number alone (R1).
        XCTAssertEqual(fatValue(printed: "20", model: "20毫克"), .ambiguous)
        // The positive case, with 毫克 read just to the right, is testUnitReadAsItsOwnLineFallsBackToTheNumber.
        // "20" followed on the same line by another word is not a split unit.
        XCTAssertNotEqual(fatValue(printed: "20份", model: "20毫克"), .found)
    }

    func testS2DroppedOrAddedComparatorIsNotFound() {
        XCTAssertNotEqual(fatValue(printed: "<0.5公克", model: "0.5公克"), .found)
        XCTAssertNotEqual(fatValue(printed: "＜0.5公克", model: "0.5公克"), .found)
        XCTAssertNotEqual(fatValue(printed: "未滿0.5公克", model: "0.5公克"), .found)
        XCTAssertNotEqual(fatValue(printed: "0.5公克以下", model: "0.5公克"), .found)
        XCTAssertNotEqual(fatValue(printed: "Less than 0.5g", model: "0.5g"), .found)
        XCTAssertNotEqual(fatValue(printed: "0.5公克", model: "<0.5公克"), .found)
        XCTAssertNotEqual(fatValue(printed: "0.5公克", model: "未滿0.5公克"), .found)
        XCTAssertEqual(fatValue(printed: "<0.5公克", model: "<0.5公克"), .found)
        XCTAssertEqual(fatValue(printed: "＜0.5 公克", model: "<0.5公克"), .found)
        XCTAssertEqual(fatValue(printed: "≦0.5公克", model: "≦0.5公克"), .found)
    }

    func testS3ThousandsSeparatorIsPartOfTheNumber() {
        XCTAssertNotEqual(fatValue(printed: "1,234公克", model: "234公克"), .found)
        XCTAssertNotEqual(fatValue(printed: "1,234公克", model: "34公克"), .found)
        XCTAssertEqual(fatValue(printed: "1,234公克", model: "1,234公克"), .found)
    }

    func testS4TwoColumnsWithoutReadableHeadersAreNeverFound() {
        // Per serving 3公克 and per 100 g 6公克; the headers were not read, and the model puts 6公克
        // in the per serving column.
        let lines: [M.Line] = [
            .init(text: "蛋白質", box: .init(x: 0.05, y: 0.80, width: 0.1, height: 0.04)),
            .init(text: "脂肪", box: .init(x: 0.05, y: 0.72, width: 0.1, height: 0.04)),
            .init(text: "3公克", box: .init(x: 0.45, y: 0.72, width: 0.1, height: 0.04)),
            .init(text: "6公克", box: .init(x: 0.75, y: 0.72, width: 0.1, height: 0.04)),
        ]
        let found = M.locate([.init(id: "f", rowLabel: "脂肪", headerText: "每份", printedText: "6公克")], lines: lines,
                             headers: ["每份", "每100公克"], rowLabels: ["蛋白質", "脂肪"], columnCount: 2) { _, _ in nil }
        XCTAssertNotEqual(found[0].status, .found)
        // No header text returned at all: still never found.
        let bare = M.locate([.init(id: "g", rowLabel: "脂肪", headerText: nil, printedText: "6公克")], lines: lines,
                            headers: [], rowLabels: ["蛋白質", "脂肪"], columnCount: 2) { _, _ in nil }
        XCTAssertNotEqual(bare[0].status, .found)
    }

    func testDecimalPointDroppedOrAddedIsNotFound() {
        XCTAssertNotEqual(fatValue(printed: "1.5公克", model: "15公克"), .found)
        XCTAssertNotEqual(fatValue(printed: "15公克", model: "1.5公克"), .found)
        XCTAssertNotEqual(fatValue(printed: "1.5公克", model: "5公克"), .found)
    }

    func testFullWidthDigitsAndUnitsNormalise() {
        XCTAssertEqual(fatValue(printed: "３．５ｇ", model: "3.5g"), .found)
        XCTAssertEqual(fatValue(printed: "１２％", model: "12%"), .found)
    }

    func testANumberInsideALongerNumberIsNotFound() {
        XCTAssertNotEqual(fatValue(printed: "123公克", model: "23公克"), .found)
        XCTAssertNotEqual(fatValue(printed: "230公克", model: "23公克"), .found)
        XCTAssertNotEqual(fatValue(printed: "230", model: "23公克"), .found)
    }

    func testPercentValuesNeedTheirPercentSign() {
        XCTAssertNotEqual(fatValue(printed: "12%", model: "12公克"), .found)
        XCTAssertNotEqual(fatValue(printed: "12公克", model: "12%"), .found)
        XCTAssertEqual(fatValue(printed: "12%", model: "12%"), .found)
    }

    func testKilocaloriesAndKilojoulesOnOneLineAreTold_apart() {
        // The energy line prints both; the model's kJ value equal to the kcal number is not found.
        let lines: [M.Line] = [
            .init(text: "熱量", box: .init(x: 0.05, y: 0.80, width: 0.1, height: 0.04)),
            .init(text: "蛋白質", box: .init(x: 0.05, y: 0.72, width: 0.1, height: 0.04)),
            .init(text: "1550kJ / 370kcal", box: .init(x: 0.45, y: 0.80, width: 0.3, height: 0.04)),
        ]
        let wrong = M.locate([.init(id: "e", rowLabel: "熱量", headerText: nil, printedText: "370kJ")], lines: lines, headers: [],
                             rowLabels: ["熱量", "蛋白質"], columnCount: 2) { _, _ in nil }
        XCTAssertNotEqual(wrong[0].status, .found)
        let kcalOnly = M.locate([.init(id: "k", rowLabel: "熱量", headerText: nil, printedText: "1550kcal")], lines: lines, headers: [],
                                rowLabels: ["熱量", "蛋白質"], columnCount: 2) { _, _ in nil }
        XCTAssertNotEqual(kcalOnly[0].status, .found)
    }

    func testAValueInsideARangeIsNotFound() {
        XCTAssertNotEqual(fatValue(printed: "25-30公克", model: "30公克"), .found)
        XCTAssertNotEqual(fatValue(printed: "25公克~30公克", model: "25公克"), .found)
        XCTAssertNotEqual(fatValue(printed: "25至30公克", model: "30公克"), .found)
        // A dash straight before a number is its sign (R4), so a dropped minus is not found.
        XCTAssertNotEqual(fatValue(printed: "-3公克", model: "3公克"), .found)
        XCTAssertNotEqual(fatValue(printed: "−3公克", model: "3公克"), .found)
        XCTAssertNotEqual(fatValue(printed: "3公克", model: "-3公克"), .found)
    }

    func testUnitBesideMustReadAsTheModelsUnit() {
        // "20" ends its line and the line beside it reads 公克, not the model's 毫克 (R1).
        let lines = rowLines(values: [("2公克", 0.80), ("20", 0.72), ("1公克", 0.64)])
            + [.init(text: "公克", box: .init(x: 0.6, y: 0.72, width: 0.05, height: 0.04))]
        let queries: [M.Query] = zip(rows, ["2公克", "20毫克", "1公克"]).enumerated().map {
            .init(id: "b\($0.offset)", rowLabel: $0.element.0, headerText: nil, printedText: $0.element.1)
        }
        let found = M.locate(queries, lines: lines, headers: [], rowLabels: rows, columnCount: 1) { _, _ in nil }
        XCTAssertNotEqual(found[1].status, .found)
    }

    func testAReadingWithNoUnitIsNeverFound() {
        XCTAssertNotEqual(fatValue(printed: "20", model: "20"), .found)
        XCTAssertNotEqual(fatValue(printed: "20公克", model: "20"), .found)
    }

    func testThousandsSeparatorOnAOneColumnRowIsOneNumber() {
        // R3: "2,030千焦" is one number, so the unlisted-number rule does not count two.
        XCTAssertEqual(fatValue(printed: "2,030千焦", model: "2,030千焦"), .found)
    }

    func testFoundRegionIsRoundedAndInsideTheUnitSquare() throws {
        let location = M.locate([.init(id: "j", rowLabel: "熱量", headerText: "每份", printedText: "485大卡")], lines: lines,
                                headers: headers, rowLabels: rowLabels, columnCount: 2) { index, _ in
            index == 3 ? .init(x: -0.000_01, y: 0.802_345, width: 0.123_456, height: 0.04) : nil
        }[0]
        let region = try XCTUnwrap(location.region)
        XCTAssertEqual(region, .init(x: 0, y: 0.8023, width: 0.1235, height: 0.04))
    }
}
