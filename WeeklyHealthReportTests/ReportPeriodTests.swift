import XCTest
@testable import WeeklyHealthReport

final class ReportPeriodTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London")!
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4
        return calendar
    }

    func testLastSevenCompletedDaysUsesCalendarMidnights() {
        let now = date(2026, 8, 25, 14)
        let period = ReportPeriod.make(
            selection: .lastSevenCompletedDays,
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(period.interval.start, date(2026, 8, 18))
        XCTAssertEqual(period.interval.end, date(2026, 8, 25))
        XCTAssertEqual(period.completedDays.count, 7)
    }

    func testCurrentWeekExcludesCurrentPartialDay() {
        let period = ReportPeriod.make(
            selection: .currentWeek,
            now: date(2026, 8, 25, 14),
            calendar: calendar
        )

        XCTAssertEqual(period.interval.start, date(2026, 8, 24))
        XCTAssertEqual(period.interval.end, date(2026, 8, 25))
        XCTAssertEqual(period.completedDays.count, 1)
    }

    func testPreviousWeekUsesLocaleWeekBoundaries() {
        let period = ReportPeriod.make(
            selection: .previousWeek,
            now: date(2026, 8, 25, 14),
            calendar: calendar
        )

        XCTAssertEqual(period.interval.start, date(2026, 8, 17))
        XCTAssertEqual(period.interval.end, date(2026, 8, 24))
        XCTAssertEqual(period.completedDays.count, 7)
    }

    func testSevenDaysRemainSevenAcrossDaylightSavingChange() {
        let period = ReportPeriod.make(
            selection: .lastSevenCompletedDays,
            now: date(2026, 10, 27, 12),
            calendar: calendar
        )

        XCTAssertEqual(period.completedDays.count, 7)
        XCTAssertTrue(period.completedDays.contains { $0.duration == 25 * 60 * 60 })
    }

    func testPrecedingEquivalentHasSameNumberOfCompletedCalendarDays() throws {
        let current = ReportPeriod.make(
            selection: .lastSevenCompletedDays,
            now: date(2026, 8, 25, 14),
            calendar: calendar
        )
        let previous = try XCTUnwrap(current.precedingEquivalent(calendar: calendar))

        XCTAssertEqual(previous.interval.start, date(2026, 8, 11))
        XCTAssertEqual(previous.interval.end, date(2026, 8, 18))
        XCTAssertEqual(previous.completedDays.count, current.completedDays.count)
    }

    func testHealthMetricQueryAndAggregationWindowPoliciesAgree() throws {
        let asOf = date(2026, 8, 25, 14)
        let period = ReportPeriod.make(
            selection: .lastSevenCompletedDays,
            now: asOf,
            calendar: calendar
        )
        let bloodPressureStart = try XCTUnwrap(
            HealthReportingPolicy.bloodPressureLatestLookbackStart(
                asOf: asOf,
                calendar: calendar
            )
        )
        XCTAssertEqual(bloodPressureStart, date(2026, 7, 26))
        XCTAssertEqual(
            HealthReportingPolicy.bloodPressureQueryStart(
                for: period,
                asOf: asOf,
                calendar: calendar
            ),
            min(period.interval.start, bloodPressureStart)
        )

        let oxygenStart = try XCTUnwrap(
            HealthReportingPolicy.oxygenSaturationLatestLookbackStart(
                asOf: asOf,
                calendar: calendar
            )
        )
        XCTAssertEqual(oxygenStart, date(2026, 7, 26))
        XCTAssertEqual(
            HealthReportingPolicy.oxygenSaturationQueryStart(
                for: period,
                asOf: asOf,
                calendar: calendar
            ),
            min(period.interval.start, oxygenStart)
        )

        let vo2Starts = try XCTUnwrap(
            HealthReportingPolicy.vo2MaxWindowStarts(
                asOf: asOf,
                calendar: calendar
            )
        )
        XCTAssertEqual(vo2Starts.fourWeek, date(2026, 7, 29))
        XCTAssertEqual(vo2Starts.threeMonth, date(2026, 5, 25))
        XCTAssertEqual(vo2Starts.sixMonth, date(2026, 2, 25))
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }
}
