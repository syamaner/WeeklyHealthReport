import XCTest
@testable import WeeklyHealthReport

final class HealthReportFormatterTests: XCTestCase {
    func testDurationFormatting() {
        XCTAssertEqual(HealthReportFormatter.duration(6 * 3600 + 48 * 60), "6h 48m")
        XCTAssertEqual(HealthReportFormatter.duration(89 * 60), "1h 29m")
    }

    func testClipboardReportIncludesValuesAndNoDiagnostics() throws {
        let calendar = testCalendar()
        let period = ReportPeriod.make(
            selection: .lastSevenCompletedDays,
            now: date(2026, 8, 25, calendar: calendar),
            calendar: calendar
        )
        let bodyFat = try XCTUnwrap(BodyFatTrendSummary.calculate(
            measurements: [
                BodyFatMeasurement(date: date(2026, 7, 10, calendar: calendar), percentage: 27.6),
                BodyFatMeasurement(date: date(2026, 7, 11, calendar: calendar), percentage: 27.6),
                BodyFatMeasurement(date: date(2026, 8, 20, calendar: calendar), percentage: 26.9),
                BodyFatMeasurement(date: date(2026, 8, 24, calendar: calendar), percentage: 26.5)
            ],
            asOf: date(2026, 8, 25, calendar: calendar),
            calendar: calendar
        ))
        let report = WeeklyReportSnapshot(
            period: period,
            weight: WeightMeasurement(date: period.interval.end, kilograms: 100.6),
            bmi: BMIMeasurement(date: period.interval.end, value: 30.8),
            bodyFat: bodyFat,
            steps: stepSummary(period: period),
            restingHeartRate: heartSummary(period: period, value: 73),
            hrv: heartSummary(period: period, value: 42),
            sleep: SleepSummary(nights: [], averageDuration: 6 * 3600 + 48 * 60),
            activeEnergyKilocalories: 1974,
            exerciseMinutes: 89,
            workouts: WorkoutSummary(workouts: [
                WorkoutRecord(id: UUID(), startDate: period.interval.start, duration: 1800, activityName: "Walking")
            ])
        )

        let text = HealthReportFormatter.clipboardReport(
            report,
            calendar: calendar,
            locale: Locale(identifier: "en_GB")
        )

        XCTAssertEqual(text, """
        Weekly Health Report
        18–24 Aug 2026

        Latest Weight: 100.6 kg
        BMI: 30.8
        Body Fat: 26.5%
        Body Fat 28-day Avg: 26.7%
        Body Fat Trend: -0.9 pp vs previous 28d
        Average Daily Steps: 2,727
        Resting HR Average: 73 bpm
        HRV Average: 42 ms
        Average Sleep: 6h 48m
        Active Energy: 1,974 kcal
        Exercise: 89 min
        Workouts: 1
        """)
    }

    func testClipboardMissingDataIsExplicitRatherThanZero() {
        let calendar = testCalendar()
        let period = ReportPeriod.make(
            selection: .lastSevenCompletedDays,
            now: date(2026, 8, 25, calendar: calendar),
            calendar: calendar
        )
        let report = WeeklyReportSnapshot(
            period: period, weight: nil, bmi: nil, bodyFat: nil, steps: nil,
            restingHeartRate: nil, hrv: nil, sleep: nil,
            activeEnergyKilocalories: nil, exerciseMinutes: nil, workouts: nil
        )
        let text = HealthReportFormatter.clipboardReport(report, calendar: calendar)
        XCTAssertTrue(text.contains("HRV Average: No data"))
        XCTAssertTrue(text.contains("Body Fat Trend: Insufficient history"))
        XCTAssertFalse(text.contains("HRV Average: 0"))
    }

    private func stepSummary(period: ReportPeriod) -> StepSummary {
        StepSummary(
            dailyTotals: [], totalSteps: 19_089, averageDailySteps: 2727,
            reportingDayCount: 7, daysWithVisibleData: 7
        )
    }

    private func heartSummary(period: ReportPeriod, value: Double) -> HeartMetricSummary {
        HeartMetricSummary(
            dailyValues: [DailyHeartMetricValue(day: period.completedDays[0], value: value, sourceNames: [])],
            average: value
        )
    }

    private func testCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London")!
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, calendar: Calendar) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 9))!
    }
}
