import XCTest
@testable import WeeklyHealthReport

final class WaistMeasurementTests: XCTestCase {
    func testSelectsLatestMeasurementInsideReportPeriod() throws {
        let calendar = testCalendar()
        let period = ReportPeriod.make(
            selection: .lastSevenCompletedDays,
            now: date(2026, 8, 25, hour: 9, calendar: calendar),
            calendar: calendar
        )
        let latest = WaistMeasurement(
            date: date(2026, 8, 24, hour: 18, calendar: calendar),
            centimetres: 101.4
        )
        let summary = try XCTUnwrap(WaistSummary.calculate(
            measurements: [
                latest,
                WaistMeasurement(
                    date: date(2026, 8, 20, hour: 8, calendar: calendar),
                    centimetres: 102.1
                ),
                WaistMeasurement(
                    date: date(2026, 8, 25, hour: 8, calendar: calendar),
                    centimetres: 100.9
                )
            ],
            period: period
        ))

        XCTAssertEqual(summary.latest, latest)
        XCTAssertEqual(summary.measurements.count, 2)
    }

    func testReturnsNilWhenPeriodContainsNoMeasurements() {
        let calendar = testCalendar()
        let period = ReportPeriod.make(
            selection: .lastSevenCompletedDays,
            now: date(2026, 8, 25, hour: 9, calendar: calendar),
            calendar: calendar
        )
        XCTAssertNil(WaistSummary.calculate(
            measurements: [
                WaistMeasurement(
                    date: date(2026, 8, 25, hour: 8, calendar: calendar),
                    centimetres: 100
                )
            ],
            period: period
        ))
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
            year: year,
            month: month,
            day: day,
            hour: hour
        ))!
    }
}
