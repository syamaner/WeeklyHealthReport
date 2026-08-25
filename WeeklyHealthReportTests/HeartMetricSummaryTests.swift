import XCTest
@testable import WeeklyHealthReport

final class HeartMetricSummaryTests: XCTestCase {
    func testWeeklyMeanUsesOneValuePerValidDay() throws {
        let calendar = testCalendar()
        let start = date(2026, 8, 18, calendar: calendar)
        let days = (0..<3).map { offset in
            let dayStart = calendar.date(byAdding: .day, value: offset, to: start)!
            return DateInterval(
                start: dayStart,
                end: calendar.date(byAdding: .day, value: 1, to: dayStart)!
            )
        }
        let summary = try XCTUnwrap(HeartMetricSummary.aggregate([
            DailyHeartMetricValue(day: days[0], value: 60, sourceNames: []),
            DailyHeartMetricValue(day: days[1], value: nil, sourceNames: []),
            DailyHeartMetricValue(day: days[2], value: 90, sourceNames: [])
        ]))

        XCTAssertEqual(summary.average, 75, accuracy: 0.0001)
        XCTAssertEqual(summary.validDayCount, 2)
    }

    func testNoValidDailyValuesReturnsNil() {
        XCTAssertNil(HeartMetricSummary.aggregate([]))
    }

    private func testCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London")!
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, calendar: Calendar) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }
}
