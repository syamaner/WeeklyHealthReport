import XCTest
@testable import WeeklyHealthReport

// All health values in this test file are synthetic fixtures.
final class HealthReportFormatterTests: XCTestCase {
    func testDurationFormatting() {
        XCTAssertEqual(HealthReportFormatter.duration(6 * 3600 + 48 * 60), "6h 48m")
        XCTAssertEqual(HealthReportFormatter.duration(89 * 60), "1h 29m")
    }

    func testMedicationDoseFormattingPluralisesOnlyCountBasedDoses() {
        let locale = Locale(identifier: "en_GB")
        XCTAssertEqual(
            HealthReportFormatter.medicationDose(quantity: 2, unitLabel: "dose", locale: locale),
            "2 doses"
        )
        XCTAssertEqual(
            HealthReportFormatter.medicationDose(quantity: 2.5, unitLabel: "mL", locale: locale),
            "2.5 mL"
        )
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

    func testCardiorespiratoryFormatting() {
        let locale = Locale(identifier: "en_GB")
        XCTAssertEqual(HealthReportFormatter.vo2Max(31.84, locale: locale), "31.8 mL/kg/min")
        XCTAssertEqual(
            HealthReportFormatter.vo2MaxWindow(
                VO2MaxWindowSummary(average: 31.84, sampledDayCount: 8),
                locale: locale
            ),
            "31.8 mL/kg/min (8 days)"
        )
        XCTAssertEqual(
            HealthReportFormatter.vo2MaxWindow(
                VO2MaxWindowSummary(average: nil, sampledDayCount: 2),
                locale: locale
            ),
            "Insufficient data (2 days)"
        )
        XCTAssertEqual(HealthReportFormatter.bloodOxygen(96.7, locale: locale), "97%")
        XCTAssertEqual(
            HealthReportFormatter.bloodOxygenRange(minimum: 95.6, maximum: 98.2, locale: locale),
            "96–98%"
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
                comparison: WaistMeasurement(
                    date: date(2026, 7, 27, calendar: calendar),
                    centimetres: 103.1
                ),
                fourWeekChangeCentimetres: -1.7,
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
            vo2Max: VO2MaxSummary(
                latest: VO2MaxMeasurement(
                    date: date(2026, 8, 24, calendar: calendar),
                    millilitresPerKilogramMinute: 32.1,
                    sourceName: "Fixture Watch"
                ),
                fourWeek: VO2MaxWindowSummary(average: 31.8, sampledDayCount: 8),
                threeMonth: VO2MaxWindowSummary(average: 30.9, sampledDayCount: 24),
                sixMonth: VO2MaxWindowSummary(average: 29.7, sampledDayCount: 51),
                dailyValues: [],
                measurements: []
            ),
            bloodOxygen: BloodOxygenSummary(
                latest: OxygenSaturationMeasurement(
                    date: date(2026, 8, 24, calendar: calendar),
                    percentage: 97,
                    sourceName: "Fixture Watch"
                ),
                dailyValues: period.completedDays.map {
                    DailyOxygenSaturationValue(
                        day: $0,
                        medianPercentage: 97,
                        sampleCount: 4,
                        sourceNames: ["Fixture Watch"]
                    )
                },
                typicalPercentage: 97,
                minimumDailyMedian: 96,
                maximumDailyMedian: 98,
                measurements: []
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
            ]),
            medications: nil
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
        Waist 4-week Trend: -1.7 cm vs ~4 weeks earlier
        Glucose Daily Average: 5.8 mmol/L
        Glucose Observed Range: 3.9–8.7 mmol/L
        Glucose Data Coverage: 7 / 7 days
        Latest VO₂ Max: 32.1 mL/kg/min (24 Aug 2026 at 09:00)
        VO₂ Max — 4 Weeks: 31.8 mL/kg/min (8 days)
        VO₂ Max — 3 Months: 30.9 mL/kg/min (24 days)
        VO₂ Max — 6 Months: 29.7 mL/kg/min (51 days)
        Latest Blood Oxygen: 97% (24 Aug 2026 at 09:00)
        Typical Blood Oxygen: 97%
        Blood Oxygen Daily Range: 96–98%
        Blood Oxygen Data Coverage: 7 / 7 days
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
        Workout: Walking — 30m — 18/08/2026 - 00:00
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
            period: period, weight: nil, bodyFat: nil, waist: nil, glucose: nil,
            vo2Max: nil, bloodOxygen: nil, steps: nil,
            restingHeartRate: nil, hrv: nil, watchCoverage: nil, sleep: nil,
            activeEnergyKilocalories: nil, exerciseMinutes: nil, workouts: nil,
            medications: nil
        )
        let text = HealthReportFormatter.clipboardReport(report, calendar: calendar)
        XCTAssertTrue(text.contains("HRV Average: No data"))
        XCTAssertTrue(text.contains("Body Fat Trend: Insufficient history"))
        XCTAssertTrue(text.contains("Weight Recorded: No data"))
        XCTAssertTrue(text.contains("Waist Circumference: No data"))
        XCTAssertTrue(text.contains("Waist 4-week Trend: Insufficient history"))
        XCTAssertTrue(text.contains("Glucose Daily Average: No data"))
        XCTAssertTrue(text.contains("Latest VO₂ Max: No data"))
        XCTAssertTrue(text.contains("Latest Blood Oxygen: No data"))
        XCTAssertTrue(text.contains("Watch Data Coverage: No data"))
        XCTAssertTrue(text.contains("Workout Details: No data"))
        XCTAssertFalse(text.contains("HRV Average: 0"))
        XCTAssertFalse(text.contains("Medication Taken:"))
    }

    func testClipboardIncludesOnlyMedicationGroupsWithTakenEvents() throws {
        let calendar = testCalendar()
        let eventDate = date(2026, 2, 9, calendar: calendar)
        let period = ReportPeriod.make(
            selection: .lastSevenCompletedDays,
            now: date(2026, 2, 10, calendar: calendar),
            calendar: calendar
        )
        let medication = MedicationDoseRecord(
            id: UUID(), medicationKey: "example-20", medicationName: "ExampleMed 20 mg",
            date: eventDate, quantity: 1, unitLabel: "dose"
        )
        let report = WeeklyReportSnapshot(
            period: period, weight: nil, bodyFat: nil, waist: nil, glucose: nil,
            vo2Max: nil, bloodOxygen: nil, steps: nil,
            restingHeartRate: nil, hrv: nil, watchCoverage: nil, sleep: nil,
            activeEnergyKilocalories: nil, exerciseMinutes: nil, workouts: nil,
            medications: MedicationSummary.aggregate([medication])
        )

        let text = HealthReportFormatter.clipboardReport(
            report, generatedAt: eventDate, calendar: calendar,
            locale: Locale(identifier: "en_GB")
        )

        XCTAssertTrue(text.contains(
            "Medication Taken: ExampleMed 20 mg — 1 dose at 9 Feb 2026 at 09:00; 1 taken event"
        ))
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
