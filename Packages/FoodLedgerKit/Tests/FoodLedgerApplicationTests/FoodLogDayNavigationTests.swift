import Foundation
import FoodLedgerApplication
import XCTest

final class FoodLogDayNavigationTests: XCTestCase {
    private func calendar(_ zone: String, _ identifier: Calendar.Identifier = .gregorian) throws -> Calendar {
        var calendar = Calendar(identifier: identifier)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: zone))
        return calendar
    }

    private func instant(_ text: String) throws -> Date {
        try XCTUnwrap(ISO8601DateFormatter().date(from: text))
    }

    func testStepsAcrossMonthAndYearEndsAndNeverPastToday() throws {
        let navigation = FoodLogDayNavigation(now: try instant("2026-01-01T10:00:00Z"), calendar: try calendar("Europe/London"))
        XCTAssertEqual(navigation.todayKey, "2026-01-01")
        XCTAssertEqual(navigation.previous("2026-01-01"), "2025-12-31")
        XCTAssertEqual(navigation.previous("2025-03-01"), "2025-02-28")
        XCTAssertEqual(navigation.next("2025-12-31"), "2026-01-01")
        XCTAssertNil(navigation.next("2026-01-01"), "next is disabled on today")
        XCTAssertFalse(navigation.canMoveForward(from: "2026-01-01"))
        XCTAssertTrue(navigation.canMoveForward(from: "2025-12-31"))
        XCTAssertEqual(navigation.clampedKey(for: try instant("2026-01-05T10:00:00Z")), "2026-01-01", "future dates are refused")
    }

    func testDaylightSavingDaysInLondonAndAuckland() throws {
        let london = FoodLogDayNavigation(now: try instant("2026-10-26T09:00:00Z"), calendar: try calendar("Europe/London"))
        XCTAssertEqual(london.previous("2026-10-26"), "2026-10-25")
        XCTAssertEqual(london.previous("2026-10-25"), "2026-10-24")
        XCTAssertEqual(london.previous("2026-03-30"), "2026-03-29")
        XCTAssertEqual(london.previous("2026-03-29"), "2026-03-28")
        // 23:30 UTC on 28 March is still 28 March in London (GMT); 00:30 UTC on 29 March is 29 March.
        XCTAssertEqual(london.key(for: try instant("2026-03-28T23:30:00Z")), "2026-03-28")
        XCTAssertEqual(london.key(for: try instant("2026-10-24T23:30:00Z")), "2026-10-25", "BST until 25 October")

        let auckland = FoodLogDayNavigation(now: try instant("2026-09-27T12:00:00Z"), calendar: try calendar("Pacific/Auckland"))
        XCTAssertEqual(auckland.todayKey, "2026-09-28")
        XCTAssertEqual(auckland.previous("2026-09-28"), "2026-09-27")
        XCTAssertEqual(auckland.previous("2026-09-27"), "2026-09-26")
    }

    func testNonGregorianDisplayCalendarsYieldTheSameKeys() throws {
        let now = try instant("2026-10-11T12:00:00Z")
        let gregorian = FoodLogDayNavigation(now: now, calendar: try calendar("Europe/London"))
        for identifier in [Calendar.Identifier.buddhist, .japanese] {
            let other = FoodLogDayNavigation(now: now, calendar: try calendar("Europe/London", identifier))
            XCTAssertEqual(other.todayKey, gregorian.todayKey)
            XCTAssertEqual(other.previous("2026-10-11"), "2026-10-10")
            XCTAssertEqual(other.key(for: now), "2026-10-11")
        }
    }

    /// After a time-zone change a stored key can be ahead of today; it is never offered.
    func testAKeyAheadOfTodayIsNotReachable() throws {
        let navigation = FoodLogDayNavigation(now: try instant("2026-10-11T08:00:00Z"), calendar: try calendar("America/Los_Angeles"))
        XCTAssertEqual(navigation.todayKey, "2026-10-11")
        XCTAssertNil(navigation.next("2026-10-11"))
        XCTAssertEqual(navigation.clampedKey(for: try XCTUnwrap(navigation.date(forKey: "2026-10-12"))), "2026-10-11")
    }
}
