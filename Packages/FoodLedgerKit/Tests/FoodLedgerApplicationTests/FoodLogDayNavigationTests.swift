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

    // MARK: Add food day (owner decision D)

    /// A past day becomes that day at the current clock time; today, no day, a future or invalid
    /// key stay Now; a day older than the backdating window falls back to Now with its own case.
    func testAddFoodDayPrefillsThatDayAtTheCurrentClockTime() throws {
        let london = try calendar("Europe/London")
        let now = try instant("2026-10-13T08:42:17Z") // 09:42:17 BST
        XCTAssertEqual(FoodEntryWhenPrefill.resolve(dayKey: nil, now: now, calendar: london), .now)
        XCTAssertEqual(FoodEntryWhenPrefill.resolve(dayKey: "2026-10-13", now: now, calendar: london), .now)
        XCTAssertEqual(FoodEntryWhenPrefill.resolve(dayKey: "2026-10-14", now: now, calendar: london), .now)
        XCTAssertEqual(FoodEntryWhenPrefill.resolve(dayKey: "not-a-day", now: now, calendar: london), .now)
        XCTAssertEqual(FoodEntryWhenPrefill.resolve(dayKey: "2026-10-11", now: now, calendar: london),
                       .day(try instant("2026-10-11T08:42:17Z")))
        // The window's first day still reaches; the day before it does not.
        let seven = FoodEntryWhenPrefill.resolve(dayKey: "2026-10-06", now: now, calendar: london)
        XCTAssertEqual(seven, .day(try instant("2026-10-06T08:42:17Z")))
        XCTAssertEqual(FoodEntryWhenPrefill.resolve(dayKey: "2026-10-05", now: now, calendar: london), .beyondBackdatingWindow)
        XCTAssertNil(FoodEntryWhenPrefill.beyondBackdatingWindow.occurredAt, "falls back to Now")
        XCTAssertNil(FoodEntryWhenPrefill.now.occurredAt)
        // Across a clock change the wall time is kept: 09:42 GMT on a winter day.
        XCTAssertEqual(FoodEntryWhenPrefill.resolve(dayKey: "2026-10-26", now: try instant("2026-10-27T09:42:00Z"), calendar: london),
                       .day(try instant("2026-10-26T09:42:00Z")))
    }

    /// A wall time that does not exist on the chosen day (the spring-forward gap) is resolved by
    /// the calendar, and the result stays on that reporting day and inside the window.
    func testAddFoodDayResolvesANonExistentWallTime() throws {
        let london = try calendar("Europe/London")
        let now = try instant("2026-03-30T00:30:00Z") // 01:30 BST; 01:30 did not exist on 29 March
        let prefill = FoodEntryWhenPrefill.resolve(dayKey: "2026-03-29", now: now, calendar: london)
        let resolved = try XCTUnwrap(prefill.occurredAt)
        XCTAssertEqual(FoodReportingDay.key(for: resolved, calendar: london), "2026-03-29")
        XCTAssertLessThanOrEqual(resolved, now)
        XCTAssertGreaterThanOrEqual(resolved, FoodLogPolicy.windowStart(now: now, calendar: london))
    }

    /// The prefill is an ordinary chosen time: if midnight passes before Log, the oldest day
    /// leaves the window and the policy reports `occurredAtTooEarly` (shown inline under When).
    func testPrefilledOldestDayBecomesTooEarlyAfterMidnight() throws {
        let london = try calendar("Europe/London")
        let beforeMidnight = try instant("2026-10-13T22:58:00Z") // 23:58 BST
        let prefill = FoodEntryWhenPrefill.resolve(dayKey: "2026-10-06", now: beforeMidnight, calendar: london)
        let occurredAt = try XCTUnwrap(prefill.occurredAt)
        let afterMidnight = beforeMidnight.addingTimeInterval(4 * 60)
        XCTAssertGreaterThanOrEqual(occurredAt, FoodLogPolicy.windowStart(now: beforeMidnight, calendar: london))
        XCTAssertLessThan(occurredAt, FoodLogPolicy.windowStart(now: afterMidnight, calendar: london))
    }
}
