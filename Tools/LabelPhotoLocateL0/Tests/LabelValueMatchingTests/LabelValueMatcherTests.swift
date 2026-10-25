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
        M.locate(queries, lines: lines, headers: headers, rowLabels: rowLabels) { _, _ in nil }.map(\.status)
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
                             lines: split, headers: [], rowLabels: ["鈉", "糖"]) { _, _ in nil }.map(\.status)
        XCTAssertEqual(found, [.found, .found])
    }

    func testSplitServingLineFallsBackToItsQuantity() {
        let split: [M.Line] = [.init(text: "每一份量", box: .init(x: 0.05, y: 0.9, width: 0.2, height: 0.04)),
                               .init(text: "185公克", box: .init(x: 0.3, y: 0.9, width: 0.1, height: 0.04))]
        XCTAssertEqual(M.locate([.init(id: "m", rowLabel: nil, headerText: nil, printedText: "每一份量 185 公克")], lines: split,
                                headers: [], rowLabels: []) { _, _ in nil }.map(\.status), [.found])
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
                                headers: [], rowLabels: ["蛋白質", "脂肪"]) { _, _ in nil }.map(\.status), [.found])
    }

    func testFoundRegionIsRoundedAndInsideTheUnitSquare() throws {
        let location = M.locate([.init(id: "j", rowLabel: "熱量", headerText: "每份", printedText: "485大卡")], lines: lines,
                                headers: headers, rowLabels: rowLabels) { index, _ in
            index == 3 ? .init(x: -0.000_01, y: 0.802_345, width: 0.123_456, height: 0.04) : nil
        }[0]
        let region = try XCTUnwrap(location.region)
        XCTAssertEqual(region, .init(x: 0, y: 0.8023, width: 0.1235, height: 0.04))
    }
}
