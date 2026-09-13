import XCTest
@testable import WeeklyHealthReport

// All health values in this test file are synthetic fixtures.
final class HealthReportFormatterTests: XCTestCase {
    func testDurationFormatting() {
        XCTAssertEqual(HealthReportFormatter.duration(6 * 3600 + 48 * 60), "6h 48m")
        XCTAssertEqual(HealthReportFormatter.duration(89 * 60), "1h 29m")
    }

    func testCountAndCoverageHelpersPreserveCurrentOutputShapes() {
        let locale = Locale(identifier: "en_GB")
        XCTAssertEqual(HealthReportFormatter.count(1_234, locale: locale), "1234")
        XCTAssertEqual(HealthReportFormatter.readingCount(1, locale: locale), "1 reading")
        XCTAssertEqual(HealthReportFormatter.readingCount(2, locale: locale), "2 readings")
        XCTAssertEqual(
            HealthReportFormatter.readingCount(
                1,
                style: .alwaysPlural,
                locale: locale
            ),
            "1 readings"
        )
        XCTAssertEqual(
            HealthReportFormatter.dayCoverage(4, of: 7, locale: locale),
            "4 / 7 days"
        )
        XCTAssertEqual(
            HealthReportFormatter.dayCoverage(
                5,
                of: 7,
                spacing: .compact,
                locale: locale
            ),
            "5/7 days"
        )
    }

    func testBloodPressureSlotCoveragePreservesCompactLegacySpacingAndPlural() {
        let locale = Locale(identifier: "en_GB")
        XCTAssertEqual(
            HealthReportFormatter.bloodPressureSlotCoverage(
                BloodPressurePeriodSlotSummary(
                    averageSystolic: 124.1,
                    averageDiastolic: 79.2,
                    sampledDayCount: 5,
                    reportingDayCount: 7,
                    readingCount: 15
                ),
                locale: locale
            ),
            "5/7 days · 15 readings"
        )
        XCTAssertEqual(
            HealthReportFormatter.bloodPressureSlotCoverage(
                BloodPressurePeriodSlotSummary(
                    averageSystolic: 124.1,
                    averageDiastolic: 79.2,
                    sampledDayCount: 1,
                    reportingDayCount: 7,
                    readingCount: 1
                ),
                locale: locale
            ),
            "1/7 days · 1 readings"
        )
    }

    func testWorkoutDetailPreservesDurationSeparatorAndDate() {
        let calendar = testCalendar()
        let workout = WorkoutRecord(
            id: UUID(),
            startDate: date(2026, 9, 9, hour: 8, calendar: calendar),
            duration: 30 * 60,
            activityName: "Walking"
        )

        XCTAssertEqual(
            HealthReportFormatter.workoutDetail(workout, calendar: calendar),
            "30m — 09/09/26 - 08:00"
        )
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
        XCTAssertEqual(
            HealthReportFormatter.bloodPressure(
                systolic: 124.1,
                diastolic: 79.2,
                locale: locale
            ),
            "124.1/79.2 mmHg"
        )
        XCTAssertEqual(
            HealthReportFormatter.bloodPressure(
                systolic: 123,
                diastolic: 78,
                locale: locale
            ),
            "123/78 mmHg"
        )
    }

    func testReusableDateAndTimeFormatIsCompactAndExact() {
        let calendar = testCalendar()
        XCTAssertEqual(
            HealthReportFormatter.dateAndTime(
                date(2026, 9, 1, hour: 20, minute: 14, calendar: calendar),
                calendar: calendar
            ),
            "01/09/26 - 20:14"
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
        let snapshot = presentationSnapshot(
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
            bloodPressure: BloodPressureSummary(
                latest: BloodPressureReading(
                    id: UUID(),
                    date: date(2026, 8, 24, hour: 20, minute: 14, calendar: calendar),
                    systolicMillimetresOfMercury: 123,
                    diastolicMillimetresOfMercury: 78,
                    sourceName: "Fixture Monitor"
                ),
                latestMorningBatch: BloodPressureBatchSummary(
                    averageSystolic: 125.3,
                    averageDiastolic: 79.7,
                    readingCount: 3,
                    firstReadingDate: date(2026, 8, 24, hour: 8, minute: 5, calendar: calendar),
                    latestReadingDate: date(2026, 8, 24, hour: 8, minute: 11, calendar: calendar),
                    sourceNames: ["Fixture Monitor"]
                ),
                latestEveningBatch: BloodPressureBatchSummary(
                    averageSystolic: 122.7,
                    averageDiastolic: 77.3,
                    readingCount: 3,
                    firstReadingDate: date(2026, 8, 24, hour: 20, minute: 9, calendar: calendar),
                    latestReadingDate: date(2026, 8, 24, hour: 20, minute: 14, calendar: calendar),
                    sourceNames: ["Fixture Monitor"]
                ),
                morning: BloodPressurePeriodSlotSummary(
                    averageSystolic: 124.1,
                    averageDiastolic: 79.2,
                    sampledDayCount: 5,
                    reportingDayCount: 7,
                    readingCount: 15
                ),
                evening: BloodPressurePeriodSlotSummary(
                    averageSystolic: 122.8,
                    averageDiastolic: 77.6,
                    sampledDayCount: 4,
                    reportingDayCount: 7,
                    readingCount: 12
                ),
                dailyValues: [],
                readings: []
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

        let text = ReportDocument(
            snapshot: snapshot,
            calendar: calendar,
            locale: Locale(identifier: "en_GB")
        ).plainText(
            generatedAt: date(2026, 8, 26, calendar: calendar),
            calendar: calendar,
            locale: Locale(identifier: "en_GB")
        )

        XCTAssertEqual(text, """
        Weekly Health Report
        Last 7 Completed Days
        18–24 Aug 2026
        Generated: 26/08/26 - 09:00

        Steps
        Average Daily Steps: 2,727
        Data Coverage: 7 / 7 days
        Weekly Total: 19,089

        Weight
        Latest Weight: 100.6 kg
        Measured: 25/08/26 - 00:00
        7-day Average: 100.8 kg
        Weight Trend: -0.4 kg vs previous 7d

        Body Composition
        Body Fat: 26.5% latest
        7-day Average: 26.7%
        28-day Average: 26.7%
        Body Fat Trend: ↓ 0.9 pp vs previous 28d
        Waist Circumference: 101.4 cm
        Waist Measured: 24/08/26 - 09:00
        4-week Waist Trend: -1.7 cm vs ~4 weeks earlier

        Heart
        Resting HR Average: 73 bpm
        Resting HR Trend: +3.0 bpm vs previous 7d
        HRV Average: 42 ms
        HRV Trend: -5.0 ms vs previous 7d
        Watch Data Coverage: 4 / 7 days

        Blood Pressure
        Latest reading: 123/78 mmHg
        Recorded: 24/08/26 - 20:14
        Morning average: 124.1/79.2 mmHg
        Latest batch: 125.3/79.7 mmHg
        Recorded: 24/08/26 - 08:11 · 3 readings
        Coverage: 5/7 days · 15 readings
        Evening average: 122.8/77.6 mmHg
        Latest batch: 122.7/77.3 mmHg
        Recorded: 24/08/26 - 20:14 · 3 readings
        Coverage: 4/7 days · 12 readings
        Period averages use completed days. Morning is before 14:00; evening is from 17:00. Mid-afternoon readings are excluded from both slot summaries.

        Cardiorespiratory
        Latest VO₂ Max: 32.1 mL/kg/min
        VO₂ Max Measured: 24/08/26 - 09:00
        4-Week Average: 31.8 mL/kg/min (8 days)
        3-Month Average: 30.9 mL/kg/min (24 days)
        6-Month Average: 29.7 mL/kg/min (51 days)
        Latest Blood Oxygen: 97%
        Blood Oxygen Measured: 24/08/26 - 09:00
        Period Typical: 97%
        Daily Median Range: 96–98%
        Blood Oxygen Coverage: 7 / 7 days
        Apple Watch blood-oxygen measurements are wellness estimates, not medical measurements.

        Glucose
        Daily Average: 5.8 mmol/L
        Observed Range: 3.9–8.7 mmol/L
        Data Coverage: 7 / 7 days

        Activity
        Active Energy: 1,974 kcal
        Exercise: 89 min
        Workouts: 1
        Workout Time: 30m
        Walking: 30m — 18/08/26 - 00:00

        Sleep
        Average Sleep: 6h 48m

        Medications Taken
        No taken medication events are visible for this period.
        """)
        XCTAssertFalse(text.hasSuffix("\n"))
    }

    func testClipboardMissingDataIsExplicitRatherThanZero() {
        let calendar = testCalendar()
        let period = ReportPeriod.make(
            selection: .lastSevenCompletedDays,
            now: date(2026, 8, 25, calendar: calendar),
            calendar: calendar
        )
        let text = ReportDocument(
            snapshot: presentationSnapshot(
                period: period,
                glucoseState: .failed("Synthetic glucose failure")
            ),
            calendar: calendar,
            locale: Locale(identifier: "en_GB")
        ).plainText(
            generatedAt: date(2026, 8, 25, calendar: calendar),
            calendar: calendar,
            locale: Locale(identifier: "en_GB")
        )
        XCTAssertTrue(text.contains("HRV Average: No data"), text)
        XCTAssertTrue(text.contains(
            "No weight data is visible, or Health access was not granted."
        ))
        XCTAssertTrue(text.contains("Waist Circumference: No data"))
        XCTAssertTrue(text.contains("Daily Average: Query failed"))
        XCTAssertTrue(text.contains("Latest VO₂ Max: No data"))
        XCTAssertTrue(text.contains("Latest Blood Oxygen: No data"))
        XCTAssertTrue(text.contains(
            "No complete blood-pressure readings are visible, or Health access was not granted."
        ))
        XCTAssertTrue(text.contains("Watch Data Coverage: No data"))
        XCTAssertTrue(text.contains("Workouts: No data"))
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
        let snapshot = presentationSnapshot(
            period: period,
            medications: MedicationSummary.aggregate([medication])
        )

        let document = ReportDocument(
            snapshot: snapshot,
            calendar: calendar,
            locale: Locale(identifier: "en_GB")
        )
        let text = document.plainText(
            generatedAt: eventDate, calendar: calendar,
            locale: Locale(identifier: "en_GB")
        )

        XCTAssertTrue(text.contains(
            "ExampleMed 20 mg: 1 dose at 09/02/26 - 09:00; 1 taken event"
        ))
        let withoutMedicationSection = ReportDocument(
            snapshot: presentationSnapshot(
                period: period,
                medications: MedicationSummary.aggregate([medication]),
                includesMedicationSection: false
            ),
            calendar: calendar,
            locale: Locale(identifier: "en_GB")
        ).plainText(
            generatedAt: eventDate,
            calendar: calendar,
            locale: Locale(identifier: "en_GB")
        )
        XCTAssertFalse(withoutMedicationSection.contains("Medications Taken"))
    }

    private func presentationSnapshot(
        period: ReportPeriod,
        weight: WeightTrendSummary? = nil,
        bodyFat: BodyFatTrendSummary? = nil,
        waist: WaistSummary? = nil,
        glucose: GlucoseSummary? = nil,
        vo2Max: VO2MaxSummary? = nil,
        bloodOxygen: BloodOxygenSummary? = nil,
        bloodPressure: BloodPressureSummary? = nil,
        steps: StepSummary? = nil,
        restingHeartRate: HeartMetricTrendSummary? = nil,
        hrv: HeartMetricTrendSummary? = nil,
        watchCoverage: WatchCoverageSummary? = nil,
        sleep: SleepSummary? = nil,
        activeEnergyKilocalories: Double? = nil,
        exerciseMinutes: Double? = nil,
        workouts: WorkoutSummary? = nil,
        medications: MedicationSummary? = nil,
        glucoseState: MetricState<GlucoseSummary>? = nil,
        includesMedicationSection: Bool = true
    ) -> ReportPresentationSnapshot {
        ReportPresentationSnapshot(
            period: period,
            steps: steps.map(StepsState.loaded) ?? .noDataOrAccess,
            weight: weight.map(MetricState.available) ?? .noDataOrAccess,
            bodyFat: bodyFat.map(MetricState.available) ?? .noDataOrAccess,
            waist: waist.map(MetricState.available) ?? .noDataOrAccess,
            glucose: glucoseState ?? glucose.map(MetricState.available) ?? .noDataOrAccess,
            vo2Max: vo2Max.map(MetricState.available) ?? .noDataOrAccess,
            bloodOxygen: bloodOxygen.map(MetricState.available) ?? .noDataOrAccess,
            bloodPressure: bloodPressure.map(MetricState.available) ?? .noDataOrAccess,
            restingHeartRate: restingHeartRate.map(MetricState.available) ?? .noDataOrAccess,
            hrv: hrv.map(MetricState.available) ?? .noDataOrAccess,
            watchCoverage: watchCoverage.map(MetricState.available) ?? .noDataOrAccess,
            exercise: exerciseMinutes.map(MetricState.available) ?? .noDataOrAccess,
            activeEnergy: activeEnergyKilocalories.map(MetricState.available) ?? .noDataOrAccess,
            workouts: workouts.map(MetricState.available) ?? .noDataOrAccess,
            sleep: sleep.map(MetricState.available) ?? .noDataOrAccess,
            medications: medications.map(MetricState.available) ?? .noDataOrAccess,
            includesMedicationSection: includesMedicationSection,
            showsMorningBloodPressureDetails: true,
            showsEveningBloodPressureDetails: true
        )
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

    private func date(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        hour: Int = 9,
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
