import XCTest
@testable import WeeklyHealthReport

// All health values in this test file are synthetic fixtures.
final class HealthReportFormatterTests: XCTestCase {
    func testDurationFormatting() {
        XCTAssertEqual(HealthReportFormatter.duration(6 * 3600 + 48 * 60), "6h 48m")
        XCTAssertEqual(HealthReportFormatter.duration(89 * 60), "1h 29m")
    }

    func testWaistAndGlucoseFormatting() {
        let locale = Locale(identifier: "en_GB")
        XCTAssertEqual(HealthReportFormatter.waistCentimetres(84.74, locale: locale), "84.7 cm")
        XCTAssertEqual(HealthReportFormatter.glucose(5.76, locale: locale), "5.8 mmol/L")
        XCTAssertEqual(
            HealthReportFormatter.glucoseRange(minimum: 3.94, maximum: 8.66, locale: locale),
            "3.9–8.7 mmol/L"
        )
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
            weight: WeightTrendSummary(
                latest: WeightMeasurement(date: period.interval.end, kilograms: 100.6),
                currentSevenDayAverage: 100.8,
                previousSevenDayAverage: 101.2,
                trendKilograms: -0.4,
                dailyValues: []
            ),
            bodyFat: bodyFat,
            waist: WaistSummary(
                latest: WaistMeasurement(
                    date: date(2026, 8, 24, calendar: calendar),
                    centimetres: 101.4
                ),
                measurements: []
            ),
            glucose: GlucoseSummary(
                dailyValues: period.completedDays.map {
                    DailyGlucoseValue(
                        day: $0,
                        averageMillimolesPerLiter: 5.8,
                        minimumMillimolesPerLiter: 3.9,
                        maximumMillimolesPerLiter: 8.7,
                        sourceNames: ["Fixture Sensor"]
                    )
                },
                averageMillimolesPerLiter: 5.8,
                minimumMillimolesPerLiter: 3.9,
                maximumMillimolesPerLiter: 8.7
            ),
            steps: stepSummary(period: period),
            restingHeartRate: heartSummary(period: period, current: 73, previous: 70),
            hrv: heartSummary(period: period, current: 42, previous: 47),
            watchCoverage: WatchCoverageSummary(
                reportingDayCount: 7,
                coveredDays: Array(period.completedDays.prefix(4))
            ),
            sleep: SleepSummary(nights: [], averageDuration: 6 * 3600 + 48 * 60),
            activeEnergyKilocalories: 1974,
            exerciseMinutes: 89,
            workouts: WorkoutSummary(workouts: [
                WorkoutRecord(id: UUID(), startDate: period.interval.start, duration: 1800, activityName: "Walking")
            ])
        )

        let text = HealthReportFormatter.clipboardReport(
            report,
            generatedAt: date(2026, 8, 26, calendar: calendar),
            calendar: calendar,
            locale: Locale(identifier: "en_GB")
        )

        XCTAssertEqual(text, """
        Weekly Health Report
        18–24 Aug 2026
        Generated: 26 Aug 2026 at 09:00

        Latest Weight: 100.6 kg
        Weight Recorded: 25 Aug 2026 at 00:00
        Weight 7-day Avg: 100.8 kg
        Weight Trend: -0.4 kg vs previous 7d
        Body Fat: 26.5%
        Body Fat 28-day Avg: 26.7%
        Body Fat Trend: -0.9 pp vs previous 28d
        Waist Circumference: 101.4 cm
        Waist Recorded: 24 Aug 2026 at 09:00
        Glucose Daily Average: 5.8 mmol/L
        Glucose Observed Range: 3.9–8.7 mmol/L
        Glucose Data Coverage: 7 / 7 days
        Average Daily Steps: 2,727
        Resting HR Average: 73 bpm
        Resting HR Trend: +3.0 bpm vs previous 7d
        HRV Average: 42 ms
        HRV Trend: -5.0 ms vs previous 7d
        Watch Data Coverage: 4 / 7 days
        Average Sleep: 6h 48m
        Active Energy: 1,974 kcal
        Exercise: 89 min
        Workouts: 1
        Workout: Walking — 30m
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
            period: period, weight: nil, bodyFat: nil, waist: nil, glucose: nil, steps: nil,
            restingHeartRate: nil, hrv: nil, watchCoverage: nil, sleep: nil,
            activeEnergyKilocalories: nil, exerciseMinutes: nil, workouts: nil
        )
        let text = HealthReportFormatter.clipboardReport(report, calendar: calendar)
        XCTAssertTrue(text.contains("HRV Average: No data"))
        XCTAssertTrue(text.contains("Body Fat Trend: Insufficient history"))
        XCTAssertTrue(text.contains("Weight Recorded: No data"))
        XCTAssertTrue(text.contains("Waist Circumference: No data"))
        XCTAssertTrue(text.contains("Glucose Daily Average: No data"))
        XCTAssertTrue(text.contains("Watch Data Coverage: No data"))
        XCTAssertTrue(text.contains("Workout Details: No data"))
        XCTAssertFalse(text.contains("HRV Average: 0"))
    }

    private func stepSummary(period: ReportPeriod) -> StepSummary {
        StepSummary(
            dailyTotals: [], totalSteps: 19_089, averageDailySteps: 2727,
            reportingDayCount: 7, daysWithVisibleData: 7
        )
    }

    private func heartSummary(
        period: ReportPeriod,
        current: Double,
        previous: Double
    ) -> HeartMetricTrendSummary {
        let currentSummary = HeartMetricSummary(
            dailyValues: period.completedDays.prefix(3).map {
                DailyHeartMetricValue(day: $0, value: current, sourceNames: [])
            },
            average: current
        )
        let previousSummary = HeartMetricSummary(
            dailyValues: period.completedDays.prefix(3).map {
                DailyHeartMetricValue(day: $0, value: previous, sourceNames: [])
            },
            average: previous
        )
        return HeartMetricTrendSummary(
            current: currentSummary,
            previous: previousSummary,
            trend: current - previous
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
