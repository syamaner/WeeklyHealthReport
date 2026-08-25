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

    func testTrendComparesDailyFirstPeriodMeans() throws {
        let calendar = testCalendar()
        let start = date(2026, 8, 18, calendar: calendar)
        let current = values(start: start, values: [70, 72, 74], calendar: calendar)
        let previousStart = calendar.date(byAdding: .day, value: -3, to: start)!
        let previous = values(start: previousStart, values: [67, 69, 71], calendar: calendar)
        let summary = try XCTUnwrap(HeartMetricTrendSummary.calculate(
            currentValues: current,
            previousValues: previous
        ))

        XCTAssertEqual(summary.current.average, 72, accuracy: 0.0001)
        XCTAssertEqual(summary.previous?.average ?? 0, 69, accuracy: 0.0001)
        XCTAssertEqual(summary.trend ?? 0, 3, accuracy: 0.0001)
    }

    func testTrendRequiresThreeValidDaysInBothPeriods() throws {
        let calendar = testCalendar()
        let start = date(2026, 8, 18, calendar: calendar)
        let current = values(start: start, values: [70, 72], calendar: calendar)
        let previous = values(start: start, values: [68, 69, 70], calendar: calendar)
        let summary = try XCTUnwrap(HeartMetricTrendSummary.calculate(
            currentValues: current,
            previousValues: previous
        ))
        XCTAssertNil(summary.trend)
    }

    private func values(
        start: Date,
        values: [Double],
        calendar: Calendar
    ) -> [DailyHeartMetricValue] {
        values.enumerated().map { offset, value in
            let dayStart = calendar.date(byAdding: .day, value: offset, to: start)!
            return DailyHeartMetricValue(
                day: DateInterval(
                    start: dayStart,
                    end: calendar.date(byAdding: .day, value: 1, to: dayStart)!
                ),
                value: value,
                sourceNames: []
            )
        }
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
