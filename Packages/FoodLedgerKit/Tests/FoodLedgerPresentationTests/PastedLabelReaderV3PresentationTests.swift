import Foundation
@testable import FoodLedgerApplication
import FoodLedgerDomain
@testable import FoodLedgerPresentation
import FoodLedgerTestSupport
import XCTest

/// Reader v3 PR 2 (#93, `docs/pasted-nutrition-label-reader-v3.md` sections 2, 3.7 and 3.8) at
/// view-model level: the "Printed but not read" list on Confirm and the `too_little_read` copy.
/// Synthetic readings only.
@MainActor
final class PastedLabelReaderV3PresentationTests: XCTestCase {
    private typealias F = LabelFixtures

    private static let unreadWarnings = [
        "row_not_read: stacked_sequence: 飽和脂肪", "unrecognised_row: 膽固醇", "row_not_read: duplicate_row: 鈉",
        "row_not_read: unexplained_bound: 糖", "row_not_read: value_before_label: 添加糖", "row_not_read: some_later_reason: 某某",
        "row_not_read: duplicate_row: 鈉",
    ]

    func testTheApplicationListsUnreadRowsFromTheCandidateWarnings() {
        let reading = F.reading(warnings: Self.unreadWarnings)
        XCTAssertEqual(reading.unreadRows, [
            LabelUnreadRow(reason: "stacked_sequence", printedLabel: "飽和脂肪"), LabelUnreadRow(reason: "duplicate_row", printedLabel: "鈉"),
            LabelUnreadRow(reason: "unexplained_bound", printedLabel: "糖"), LabelUnreadRow(reason: "value_before_label", printedLabel: "添加糖"),
            LabelUnreadRow(reason: "some_later_reason", printedLabel: "某某"),
        ], "in order, without repeats; other warnings are not unread rows")
        XCTAssertEqual(LabelUnreadRow.rows(in: ["row_not_read: malformed_value: Fat: total"]),
                       [LabelUnreadRow(reason: "malformed_value", printedLabel: "Fat: total")], "the label keeps any later colon")
        XCTAssertTrue(F.reading().unreadRows.isEmpty)
    }

    func testConfirmListsEveryRowPrintedButNotReadWithItsReason() throws {
        let source = try F.source(F.reading(warnings: Self.unreadWarnings))
        XCTAssertEqual(source.printedButNotRead.map(\.title), ["飽和脂肪", "鈉", "糖", "添加糖", "某某"])
        XCTAssertEqual(source.printedButNotRead.map(\.printedText), Array(repeating: "Not read", count: 5))
        XCTAssertEqual(source.printedButNotRead.map(\.note), [
            "Not read: from this row on, the lines are not in the order of a table.",
            "Not read: this row is printed more than once.",
            "Not read: a word such as \"more than\" or \"at least\" is printed near this row.",
            "Not read: a value is printed before this label instead of after it.",
            "Not read.",
        ])
        // The unread mandatory row keeps its own Not read flag (G3) above the list.
        XCTAssertEqual(source.rows.first { $0.id == "saturates" }?.flag, "Not read: saturated fat. Add it, or leave it unknown.")
        // A stored entry shows the same list from its manifest, read-only.
        let stored = PastedLabelSourceModel(stored: source.manifest, nutrients: source.nutrients)
        XCTAssertFalse(stored.isEditable)
        XCTAssertEqual(stored.printedButNotRead, source.printedButNotRead)
        // A reading with nothing unread has no such section.
        XCTAssertTrue(try F.source().printedButNotRead.isEmpty)
        // The words carry no code.
        for item in source.printedButNotRead {
            XCTAssertFalse(item.note.contains("_"), item.note)
        }
        XCTAssertEqual(PastedLabelText.printedButNotReadTitle, "Printed but not read")
    }

    func testTooLittleReadDeclinesWithItsOwnCopy() throws {
        XCTAssertEqual(PastedLabelCodes.classify(PastedLabelCodes.tooLittleRead), .init(kind: .hardDecline, copy: .tooLittleRead))
        let stub = F.StubReader(F.declined([PastedLabelCodes.tooLittleRead]))
        var lines: [[String]] = []
        let model = F.textModel(stub) { lines.append($0) }
        model.name = "Synthetic oat crackers"
        model.text = F.pastedText
        XCTAssertNil(model.readLabel(), "a hard decline never opens Confirm")
        XCTAssertEqual(model.text, F.pastedText, "the text is kept")
        XCTAssertEqual(model.declineMessages, ["Only a few values could be read from this text. Try copying the table again, or use Search or Barcode."])
        XCTAssertEqual(lines.last?.first, "Pasted label declined: too_little_read", "the code goes to Developer tools only")
    }
}
