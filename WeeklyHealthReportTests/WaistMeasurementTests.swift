import XCTest
@testable import WeeklyHealthReport

final class WaistMeasurementTests: XCTestCase {
    func testSelectsLatestMeasurementInEightWeekLookbackAndCalculatesTrend() throws {
        let calendar = testCalendar()
        let now = date(2026, 8, 25, hour: 9, calendar: calendar)
        let latest = WaistMeasurement(
            date: date(2026, 8, 25, hour: 8, calendar: calendar),
            centimetres: 101.4
        )
        let comparison = WaistMeasurement(
            date: date(2026, 7, 28, hour: 8, calendar: calendar),
            centimetres: 103.1
        )
        let summary = try XCTUnwrap(WaistSummary.calculate(
            measurements: [
                latest,
                comparison,
                WaistMeasurement(
                    date: date(2026, 8, 20, hour: 8, calendar: calendar),
                    centimetres: 102.1
                ),
                WaistMeasurement(
                    date: date(2026, 6, 1, hour: 8, calendar: calendar),
                    centimetres: 110
                )
            ],
            asOf: now,
            calendar: calendar
        ))

        XCTAssertEqual(summary.latest, latest)
        XCTAssertEqual(summary.comparison, comparison)
        XCTAssertEqual(
            try XCTUnwrap(summary.fourWeekChangeCentimetres),
            -1.7,
            accuracy: 0.000_001
        )
        XCTAssertEqual(summary.measurements.count, 3)
    }

    func testReturnsLatestWithoutTrendWhenNoSampleIs21To35DaysEarlier() throws {
        let calendar = testCalendar()
        let now = date(2026, 8, 25, hour: 9, calendar: calendar)
        let latest = WaistMeasurement(
            date: date(2026, 8, 24, hour: 8, calendar: calendar),
            centimetres: 100
        )
        let summary = try XCTUnwrap(WaistSummary.calculate(
            measurements: [
                latest,
                WaistMeasurement(
                    date: date(2026, 8, 14, hour: 8, calendar: calendar),
                    centimetres: 101
                )
            ],
            asOf: now,
            calendar: calendar
        ))

        XCTAssertEqual(summary.latest, latest)
        XCTAssertNil(summary.comparison)
        XCTAssertNil(summary.fourWeekChangeCentimetres)
    }

    func testReturnsNilWhenEightWeekLookbackContainsNoMeasurements() {
        let calendar = testCalendar()
        let now = date(2026, 8, 25, hour: 9, calendar: calendar)
        XCTAssertNil(WaistSummary.calculate(
            measurements: [
                WaistMeasurement(
                    date: date(2026, 6, 1, hour: 8, calendar: calendar),
                    centimetres: 100
                ),
                WaistMeasurement(
                    date: date(2026, 8, 25, hour: 10, calendar: calendar),
                    centimetres: 99
                )
            ],
            asOf: now,
            calendar: calendar
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
