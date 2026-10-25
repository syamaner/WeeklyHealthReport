import FoodLabelPhotoReading
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
        XCTAssertEqual(found.map(\.status), [.found, .ambiguous, .found])
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

    func testNoRowLabelLocatedMeansAmbiguousNotFound() {
        let lines: [M.Line] = [.init(text: "3公克", box: .init(x: 0.5, y: 0.72, width: 0.1, height: 0.04))]
        let found = M.locate([.init(id: "x", rowLabel: "脂肪", headerText: nil, printedText: "3公克")], lines: lines, headers: [],
                             rowLabels: ["脂肪", "蛋白質"], columnCount: 1) { _, _ in nil }
        XCTAssertEqual(found.map(\.status), [.ambiguous])
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
