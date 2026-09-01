import XCTest
@testable import WeeklyHealthReport

// All blood-pressure values in this file are synthetic fixtures.
final class BloodPressureSummaryTests: XCTestCase {
    func testUsesDailyFirstMorningAndEveningAverages() throws {
        let calendar = testCalendar()
        let asOf = date(2026, 9, 1, hour: 12, calendar: calendar)
        let period = ReportPeriod.make(
            selection: .lastSevenCompletedDays,
            now: asOf,
            calendar: calendar
        )
        let summary = try XCTUnwrap(BloodPressureSummary.calculate(
            readings: [
                reading(2026, 8, 30, 8, 0, 120, 80, calendar),
                reading(2026, 8, 30, 8, 5, 140, 90, calendar),
                reading(2026, 8, 31, 9, 0, 100, 70, calendar),
                reading(2026, 8, 30, 20, 0, 130, 82, calendar),
                reading(2026, 8, 31, 21, 0, 110, 72, calendar),
                reading(2026, 8, 31, 21, 5, 120, 76, calendar)
            ],
            period: period,
            asOf: asOf,
            calendar: calendar
        ))

        let morning = try XCTUnwrap(summary.morning)
        XCTAssertEqual(morning.averageSystolic, 115, accuracy: 0.0001)
        XCTAssertEqual(morning.averageDiastolic, 77.5, accuracy: 0.0001)
        XCTAssertEqual(morning.sampledDayCount, 2)
        XCTAssertEqual(morning.reportingDayCount, 7)
        XCTAssertEqual(morning.readingCount, 3)

        let evening = try XCTUnwrap(summary.evening)
        XCTAssertEqual(evening.averageSystolic, 122.5, accuracy: 0.0001)
        XCTAssertEqual(evening.averageDiastolic, 78, accuracy: 0.0001)
        XCTAssertEqual(evening.sampledDayCount, 2)
        XCTAssertEqual(evening.readingCount, 3)
    }

    func testSlotBoundariesExcludeMidAfternoonWithoutHidingLatestReading() throws {
        let calendar = testCalendar()
        let asOf = date(2026, 9, 1, hour: 18, calendar: calendar)
        let period = ReportPeriod.make(
            selection: .lastSevenCompletedDays,
            now: asOf,
            calendar: calendar
        )
        let beforeBoundary = date(2026, 8, 31, hour: 13, minute: 59, calendar: calendar)
        let excludedStart = date(2026, 8, 31, hour: 14, calendar: calendar)
        let eveningStart = date(2026, 8, 31, hour: 17, calendar: calendar)
        XCTAssertEqual(
            BloodPressureTimeSlot.classify(beforeBoundary, calendar: calendar),
            .morning
        )
        XCTAssertNil(BloodPressureTimeSlot.classify(excludedStart, calendar: calendar))
        XCTAssertEqual(
            BloodPressureTimeSlot.classify(eveningStart, calendar: calendar),
            .evening
        )

        let latestDate = date(2026, 9, 1, hour: 15, calendar: calendar)
        let summary = try XCTUnwrap(BloodPressureSummary.calculate(
            readings: [
                reading(at: beforeBoundary, systolic: 121, diastolic: 79),
                reading(at: excludedStart, systolic: 122, diastolic: 80),
                reading(at: eveningStart, systolic: 123, diastolic: 81),
                reading(at: latestDate, systolic: 124, diastolic: 82)
            ],
            period: period,
            asOf: asOf,
            calendar: calendar
        ))

        XCTAssertEqual(summary.latest.date, latestDate)
        XCTAssertEqual(summary.latest.systolicMillimetresOfMercury, 124)
        XCTAssertEqual(summary.morning?.readingCount, 1)
        XCTAssertEqual(summary.evening?.readingCount, 1)
    }

    func testLatestBatchesIncludeTodayWhilePeriodAverageUsesCompletedDays() throws {
        let calendar = testCalendar()
        let asOf = date(2026, 9, 1, hour: 21, calendar: calendar)
        let period = ReportPeriod.make(
            selection: .lastSevenCompletedDays,
            now: asOf,
            calendar: calendar
        )
        let summary = try XCTUnwrap(BloodPressureSummary.calculate(
            readings: [
                reading(2026, 8, 31, 8, 0, 130, 84, calendar),
                reading(2026, 9, 1, 8, 0, 120, 78, calendar),
                reading(2026, 9, 1, 8, 5, 124, 80, calendar),
                reading(2026, 9, 1, 20, 0, 118, 76, calendar),
                reading(2026, 9, 1, 20, 5, 122, 78, calendar)
            ],
            period: period,
            asOf: asOf,
            calendar: calendar
        ))

        XCTAssertEqual(summary.morning?.averageSystolic, 130)
        XCTAssertEqual(summary.morning?.sampledDayCount, 1)
        XCTAssertEqual(summary.latestMorningBatch?.averageSystolic, 122)
        XCTAssertEqual(summary.latestMorningBatch?.averageDiastolic, 79)
        XCTAssertEqual(summary.latestMorningBatch?.readingCount, 2)
        XCTAssertEqual(summary.latestEveningBatch?.averageSystolic, 120)
        XCTAssertEqual(summary.latestEveningBatch?.averageDiastolic, 77)
        XCTAssertEqual(summary.latestEveningBatch?.readingCount, 2)
    }

    func testRejectsInvalidReadingsAndReturnsNilWithoutACompleteValidPair() {
        let calendar = testCalendar()
        let asOf = date(2026, 9, 1, hour: 12, calendar: calendar)
        let period = ReportPeriod.make(
            selection: .lastSevenCompletedDays,
            now: asOf,
            calendar: calendar
        )
        XCTAssertNil(BloodPressureSummary.calculate(
            readings: [reading(2026, 8, 31, 9, 0, .nan, 80, calendar)],
            period: period,
            asOf: asOf,
            calendar: calendar
        ))
    }

    private func reading(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        _ hour: Int,
        _ minute: Int,
        _ systolic: Double,
        _ diastolic: Double,
        _ calendar: Calendar
    ) -> BloodPressureReading {
        reading(
            at: date(year, month, day, hour: hour, minute: minute, calendar: calendar),
            systolic: systolic,
            diastolic: diastolic
        )
    }

    private func reading(
        at date: Date,
        systolic: Double,
        diastolic: Double
    ) -> BloodPressureReading {
        BloodPressureReading(
            id: UUID(),
            date: date,
            systolicMillimetresOfMercury: systolic,
            diastolicMillimetresOfMercury: diastolic,
            sourceName: "Fixture Monitor"
        )
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
        minute: Int = 0,
        calendar: Calendar
    ) -> Date {
        calendar.date(from: DateComponents(
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute
        ))!
    }
}
