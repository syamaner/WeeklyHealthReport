import Foundation
import FoodLedgerApplication
import XCTest

final class FoodIntakeDayPreviewTests: XCTestCase {
    func testPastWeekUsesLocalCalendarAcrossSpringAndAutumnDST() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Europe/London"))
        for (year, month, day, hours) in [(2026, 3, 30, 23.0), (2026, 10, 26, 25.0)] {
            let now = try XCTUnwrap(calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12)))
            let previews = FoodIntakeDayPreview.pastWeek(records: .init(), now: now, calendar: calendar)
            XCTAssertEqual(previews.count, 7)
            XCTAssertEqual(Set(previews.map(\.date)).count, 7)
            XCTAssertEqual(calendar.component(.day, from: previews[0].date), day - 1)
            XCTAssertEqual(previews[0].date.timeIntervalSince(previews[1].date), 24 * 3600)
            XCTAssertEqual(calendar.startOfDay(for: now).timeIntervalSince(previews[0].date), hours * 3600)
            for preview in previews {
                XCTAssertEqual(calendar.component(.hour, from: preview.date), 0)
                XCTAssertEqual(preview.summary?.itemCount, 0)
                XCTAssertTrue(try XCTUnwrap(preview.summary).totals.allSatisfy { $0.knownAmount == nil })
            }
        }
    }

    func testLocalMidnightRollsTheWindowForward() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Pacific/Auckland"))
        let midnight = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 27)))
        let before = FoodIntakeDayPreview.pastWeek(records: .init(), now: midnight.addingTimeInterval(-1), calendar: calendar)
        let after = FoodIntakeDayPreview.pastWeek(records: .init(), now: midnight, calendar: calendar)
        XCTAssertEqual(calendar.component(.day, from: before[0].date), 25)
        XCTAssertEqual(calendar.component(.day, from: after[0].date), 26)
        XCTAssertEqual(before[0].date, after[1].date)
    }
}
