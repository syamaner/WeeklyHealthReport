import XCTest
@testable import WeeklyHealthReport

final class WatchCoverageSummaryTests: XCTestCase {
    func testCountsUniqueCompletedDaysContainingWatchSamples() throws {
        let calendar = testCalendar()
        let period = ReportPeriod.make(
            selection: .lastSevenCompletedDays,
            now: date(2026, 8, 25, hour: 9, calendar: calendar),
            calendar: calendar
        )
        let summary = try XCTUnwrap(WatchCoverageSummary.calculate(
            appleWatchSampleDates: [
                date(2026, 8, 18, hour: 8, calendar: calendar),
                date(2026, 8, 18, hour: 18, calendar: calendar),
                date(2026, 8, 20, hour: 12, calendar: calendar),
                date(2026, 8, 24, hour: 23, calendar: calendar),
                date(2026, 8, 25, hour: 1, calendar: calendar)
            ],
            period: period
        ))

        XCTAssertEqual(summary.daysWithWatchData, 3)
        XCTAssertEqual(summary.reportingDayCount, 7)
        XCTAssertEqual(summary.coveredDays.map(\.start), [
            date(2026, 8, 18, hour: 0, calendar: calendar),
            date(2026, 8, 20, hour: 0, calendar: calendar),
            date(2026, 8, 24, hour: 0, calendar: calendar)
        ])
    }

    func testNoWatchSamplesProducesNoDataRatherThanZeroCoverage() {
        let calendar = testCalendar()
        let period = ReportPeriod.make(
            selection: .lastSevenCompletedDays,
            now: date(2026, 8, 25, hour: 9, calendar: calendar),
            calendar: calendar
        )

        XCTAssertNil(WatchCoverageSummary.calculate(appleWatchSampleDates: [], period: period))
    }

    func testExactMidnightBelongsOnlyToFollowingDayAcrossDST() throws {
        let calendar = testCalendar()
        let period = ReportPeriod.make(
            selection: .lastSevenCompletedDays,
            now: date(2026, 10, 27, hour: 9, calendar: calendar),
            calendar: calendar
        )
        let midnightAfterLongDay = date(2026, 10, 26, hour: 0, calendar: calendar)
        let summary = try XCTUnwrap(WatchCoverageSummary.calculate(
            appleWatchSampleDates: [
                midnightAfterLongDay.addingTimeInterval(-1),
                midnightAfterLongDay
            ],
            period: period
        ))

        XCTAssertEqual(summary.coveredDays.map(\.start), [
            date(2026, 10, 25, hour: 0, calendar: calendar),
            midnightAfterLongDay
        ])
        XCTAssertEqual(summary.coveredDays.first?.duration, 25 * 60 * 60)
    }

    private func testCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London")!
        return calendar
    }

    private func date(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        hour: Int,
        calendar: Calendar
    ) -> Date {
        calendar.date(from: DateComponents(
            year: year, month: month, day: day, hour: hour
        ))!
    }
}
