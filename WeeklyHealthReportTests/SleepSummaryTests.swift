import XCTest
@testable import WeeklyHealthReport

// All health values in this test file are synthetic fixtures.
final class SleepSummaryTests: XCTestCase {
    func testOnlyRecognisedAsleepStagesAreIncluded() {
        XCTAssertTrue(SleepStage.asleepUnspecified.countsAsAsleep)
        XCTAssertTrue(SleepStage.asleepCore.countsAsAsleep)
        XCTAssertTrue(SleepStage.asleepDeep.countsAsAsleep)
        XCTAssertTrue(SleepStage.asleepREM.countsAsAsleep)
        XCTAssertFalse(SleepStage.awake.countsAsAsleep)
        XCTAssertFalse(SleepStage.inBed.countsAsAsleep)
        XCTAssertFalse(SleepStage.other.countsAsAsleep)
    }

    func testMergeOverlapsPreventsDoubleCountingAcrossSources() {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let merged = SleepSummary.mergeOverlaps([
            AsleepInterval(start: base, end: base.addingTimeInterval(4 * 3600)),
            AsleepInterval(start: base.addingTimeInterval(2 * 3600), end: base.addingTimeInterval(6 * 3600)),
            AsleepInterval(start: base.addingTimeInterval(7 * 3600), end: base.addingTimeInterval(8 * 3600))
        ])

        XCTAssertEqual(merged.count, 2)
        XCTAssertEqual(merged.reduce(0) { $0 + $1.duration }, 7 * 3600, accuracy: 0.001)
    }

    func testNightlyTotalsAndAverageUseOnlyNightsWithData() throws {
        let calendar = testCalendar()
        let now = date(2026, 8, 25, 9, calendar: calendar)
        let period = ReportPeriod.make(
            selection: .lastSevenCompletedDays,
            now: now,
            calendar: calendar
        )
        let firstWakeDay = period.completedDays[0].start
        let secondWakeDay = period.completedDays[1].start
        let intervals = [
            interval(beforeWakeDay: firstWakeDay, startHour: 23, endHour: 7, calendar: calendar),
            interval(beforeWakeDay: firstWakeDay, startHour: 1, endHour: 6, calendar: calendar),
            interval(beforeWakeDay: secondWakeDay, startHour: 0, endHour: 6, calendar: calendar)
        ]

        let summary = try XCTUnwrap(SleepSummary.calculate(
            asleepIntervals: intervals,
            period: period,
            calendar: calendar
        ))

        XCTAssertEqual(summary.nights.count, 2)
        XCTAssertEqual(summary.nights[0].duration, 8 * 3600, accuracy: 0.001)
        XCTAssertEqual(summary.nights[1].duration, 6 * 3600, accuracy: 0.001)
        XCTAssertEqual(summary.averageDuration, 7 * 3600, accuracy: 0.001)
    }

    func testIntervalsOutsideNightBucketsProduceNoData() {
        let calendar = testCalendar()
        let period = ReportPeriod.make(
            selection: .lastSevenCompletedDays,
            now: date(2026, 8, 25, 9, calendar: calendar),
            calendar: calendar
        )
        let interval = AsleepInterval(
            start: date(2026, 8, 1, 1, calendar: calendar),
            end: date(2026, 8, 1, 2, calendar: calendar)
        )
        XCTAssertNil(SleepSummary.calculate(asleepIntervals: [interval], period: period, calendar: calendar))
    }

    private func interval(
        beforeWakeDay wakeDay: Date,
        startHour: Int,
        endHour: Int,
        calendar: Calendar
    ) -> AsleepInterval {
        let previousDay = calendar.date(byAdding: .day, value: -1, to: wakeDay)!
        let startDay = startHour >= 12 ? previousDay : wakeDay
        let start = calendar.date(bySettingHour: startHour, minute: 0, second: 0, of: startDay)!
        let end = calendar.date(bySettingHour: endHour, minute: 0, second: 0, of: wakeDay)!
        return AsleepInterval(start: start, end: end)
    }

    private func testCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London")!
        return calendar
    }

    private func date(
        _ year: Int, _ month: Int, _ day: Int, _ hour: Int,
        calendar: Calendar
    ) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }
}
