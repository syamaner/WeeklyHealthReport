import XCTest
@testable import WeeklyHealthReport

// Every health value in this file is invented. These tests never access HealthKit.
final class DailyHealthExportTests: XCTestCase {
    func testEnvelopePreservesDailySemanticsAndExplicitAvailability() throws {
        let calendar = londonCalendar()
        let cutoff = date(2026, 9, 6, 23, calendar: calendar)
        let window = try DailyExportWindow.capture(at: cutoff, calendar: calendar)
        let tiedDate = date(2026, 9, 6, 8, calendar: calendar)
        var inputs = emptyInputs(window: window)
        inputs = replacing(
            inputs,
            weight: historicalWeights(window: window) + [
                WeightMeasurement(
                    id: UUID(uuidString: "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF")!,
                    date: tiedDate,
                    kilograms: 91
                ),
                WeightMeasurement(
                    id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
                    date: tiedDate,
                    kilograms: 81
                )
            ],
            bodyFat: [
                BodyFatMeasurement(date: tiedDate, percentage: 20),
                BodyFatMeasurement(
                    date: date(2026, 9, 6, 9, calendar: calendar),
                    percentage: 22
                )
            ],
            bloodOxygen: [
                OxygenSaturationMeasurement(date: tiedDate, percentage: 95, sourceName: "Watch"),
                OxygenSaturationMeasurement(
                    date: date(2026, 9, 6, 9, calendar: calendar),
                    percentage: 99,
                    sourceName: "Watch"
                )
            ],
            bloodPressure: [
                pressure(1, at: date(2026, 9, 6, 8, calendar: calendar), 120, 80),
                pressure(2, at: date(2026, 9, 6, 15, calendar: calendar), 130, 85),
                pressure(3, at: date(2026, 9, 6, 18, calendar: calendar), 140, 90)
            ],
            todayGlucose: glucose(window.day, average: 5.5, minimum: 4.0, maximum: 7.0),
            hourlyGlucose: window.glucoseHours.enumerated().map { index, hour in
                index == 8
                    ? glucose(hour, average: 5.2, minimum: 4.8, maximum: 5.7)
                    : glucose(hour)
            },
            todaySteps: DailyStepTotal(
                day: window.day,
                steps: 1_234,
                sourceNames: ["Phone", "Watch"]
            ),
            supportsMedicationData: false
        )

        let envelope = try DailyHealthExportBuilder.make(
            window: window,
            exportedAt: cutoff.addingTimeInterval(5),
            inputs: inputs
        )

        XCTAssertEqual(envelope.schemaVersion, 1)
        XCTAssertEqual(envelope.reportDate, "2026-09-06")
        XCTAssertEqual(envelope.timeZone, "Europe/London")
        XCTAssertEqual(envelope.today.weight.data?.value, 81)
        XCTAssertEqual(envelope.today.bodyFat.data?.dailyAverage.value, 21)
        XCTAssertEqual(envelope.today.bloodOxygen.data?.dailyMedian.value, 97)
        XCTAssertEqual(envelope.today.bloodPressure.data?.readings.map(\.slot), [
            "morning", nil, "evening"
        ])
        XCTAssertEqual(envelope.today.bloodPressure.data?.morning.data?.readingCount, 1)
        XCTAssertEqual(envelope.today.bloodPressure.data?.evening.data?.readingCount, 1)
        XCTAssertEqual(envelope.today.glucose.data?.hours.count, window.glucoseHours.count)
        XCTAssertEqual(envelope.today.glucose.data?.hours[8].statistics.availability, .available)
        XCTAssertEqual(envelope.today.glucose.data?.hours[9].statistics.availability, .noDataOrAccess)
        XCTAssertEqual(envelope.today.activity.steps.data?.value, 1_234)
        XCTAssertEqual(envelope.appContext.policyID, "last_7_completed_days_v1")
        XCTAssertEqual(envelope.appContext.window.end, "2026-09-06T00:00:00+01:00")
        XCTAssertEqual(envelope.today.medications.availability, .unsupported)
        XCTAssertNil(envelope.today.medications.data)

        let bytes = try DailyHealthExportSerializer.encode(envelope)
        let text = try XCTUnwrap(String(data: bytes, encoding: .utf8))
        XCTAssertTrue(text.contains("\"schema_version\" : 1"))
        XCTAssertTrue(text.contains("\"no_data_or_access\""))
        XCTAssertFalse(text.contains(": null"))
        XCTAssertEqual(bytes, try DailyHealthExportSerializer.encode(envelope))
    }

    func testMorningEveningAndBedtimeRemainOneReportingDateWithFreshSnapshots() throws {
        let calendar = londonCalendar()
        let times = [8, 18, 23]
        let weights = [80.1, 80.2, 80.3]

        for (hour, kilograms) in zip(times, weights) {
            let cutoff = date(2026, 9, 6, hour, calendar: calendar)
            let window = try DailyExportWindow.capture(at: cutoff, calendar: calendar)
            let inputs = replacing(
                emptyInputs(window: window),
                weight: [WeightMeasurement(
                    date: cutoff.addingTimeInterval(-60),
                    kilograms: kilograms
                )]
            )
            let envelope = try DailyHealthExportBuilder.make(
                window: window,
                exportedAt: cutoff,
                inputs: inputs
            )

            XCTAssertEqual(envelope.reportDate, "2026-09-06")
            XCTAssertEqual(envelope.today.weight.data?.value, kilograms)
            XCTAssertEqual(envelope.dataAsOf, String(format: "2026-09-06T%02d:00:00+01:00", hour))
            XCTAssertEqual(
                envelope.appContext.weight.data?.currentSevenDayAverage.availability,
                .insufficientData
            )
        }
    }

    func testWindowHandlesMidnightAndDSTWithoutAssumingTwentyFourHours() throws {
        let calendar = londonCalendar()
        let midnight = try DailyExportWindow.capture(
            at: date(2026, 9, 7, 0, calendar: calendar),
            calendar: calendar
        )
        XCTAssertEqual(midnight.reportDate, "2026-09-07")
        XCTAssertTrue(midnight.glucoseHours.isEmpty)
        XCTAssertEqual(midnight.day.start, midnight.day.end)

        let spring = try DailyExportWindow.capture(
            at: date(2026, 3, 29, 23, calendar: calendar),
            calendar: calendar
        )
        let autumn = try DailyExportWindow.capture(
            at: date(2026, 10, 25, 23, calendar: calendar),
            calendar: calendar
        )
        XCTAssertEqual(spring.glucoseHours.count, 22)
        XCTAssertEqual(autumn.glucoseHours.count, 24)
        XCTAssertTrue(autumn.glucoseHours.contains {
            $0.start.timeIntervalSince1970 != $0.end.timeIntervalSince1970
        })
    }

    func testLaterCorrectionCanRemoveEarlierTodayValueWithoutReusingSnapshot() throws {
        let calendar = londonCalendar()
        let cutoff = date(2026, 9, 6, 18, calendar: calendar)
        let window = try DailyExportWindow.capture(at: cutoff, calendar: calendar)
        let earlier = replacing(
            emptyInputs(window: window),
            weight: [WeightMeasurement(date: cutoff.addingTimeInterval(-3_600), kilograms: 82)]
        )
        let corrected = emptyInputs(window: window)

        let first = try DailyHealthExportBuilder.make(
            window: window,
            exportedAt: cutoff,
            inputs: earlier
        )
        let second = try DailyHealthExportBuilder.make(
            window: window,
            exportedAt: cutoff.addingTimeInterval(60),
            inputs: corrected
        )

        XCTAssertEqual(first.today.weight.availability, .available)
        XCTAssertEqual(second.today.weight.availability, .noDataOrAccess)
        XCTAssertNil(second.today.weight.data)
    }

    func testAppContextMapsExistingPureCalculationsWithoutUsingUISelection() throws {
        let calendar = londonCalendar()
        let cutoff = date(2026, 9, 6, 23, calendar: calendar)
        let window = try DailyExportWindow.capture(at: cutoff, calendar: calendar)
        let inputs = populatedInputs(window: window)
        let envelope = try DailyHealthExportBuilder.make(
            window: window,
            exportedAt: cutoff,
            inputs: inputs
        )

        let expectedWeight = try XCTUnwrap(WeightTrendSummary.calculate(
            measurements: inputs.weight,
            asOf: cutoff,
            calendar: calendar
        ))
        XCTAssertEqual(
            envelope.appContext.weight.data?.currentSevenDayAverage.data?.value,
            expectedWeight.currentSevenDayAverage
        )
        XCTAssertEqual(
            envelope.appContext.weight.data?.trend.data?.change,
            expectedWeight.trendKilograms
        )

        let expectedGlucose = try XCTUnwrap(GlucoseSummary.aggregate(inputs.contextGlucose))
        XCTAssertEqual(
            envelope.appContext.glucose.data?.statistics.average,
            expectedGlucose.averageMillimolesPerLiter
        )
        let expectedSteps = try XCTUnwrap(StepSummary.aggregate(inputs.contextSteps))
        XCTAssertEqual(envelope.appContext.steps.data?.total.value, expectedSteps.totalSteps)
        XCTAssertEqual(
            envelope.appContext.steps.data?.dailyAverage.value,
            expectedSteps.averageDailySteps
        )

        let expectedRHR = try XCTUnwrap(HeartMetricTrendSummary.calculate(
            currentValues: inputs.contextRestingHeartRate,
            previousValues: inputs.previousRestingHeartRate
        ))
        XCTAssertEqual(
            envelope.appContext.restingHeartRate.data?.currentAverage.value,
            expectedRHR.current.average
        )
        XCTAssertEqual(
            envelope.appContext.restingHeartRate.data?.trend.data?.change,
            expectedRHR.trend
        )

        let expectedSleep = try XCTUnwrap(SleepSummary.calculate(
            asleepIntervals: inputs.contextAsleepIntervals,
            period: window.context,
            calendar: calendar
        ))
        XCTAssertEqual(
            envelope.appContext.sleep.data?.averageDurationSeconds,
            expectedSleep.averageDuration
        )
        XCTAssertEqual(envelope.appContext.workouts.data?.count, inputs.contextWorkouts.count)
        XCTAssertEqual(envelope.appContext.medications.data?.takenEventCount, 1)
        XCTAssertEqual(envelope.appContext.policyID, "last_7_completed_days_v1")
        XCTAssertEqual(
            envelope.appContext.window.start,
            "2026-08-30T00:00:00+01:00"
        )
    }

    func testQueryFailureBlocksSerialization() async throws {
        let calendar = londonCalendar()
        let provider = FailingDailyProvider()
        let service = DailyHealthExportService(
            healthData: provider,
            calendar: calendar,
            now: { self.date(2026, 9, 6, 8, calendar: calendar) }
        )

        do {
            _ = try await service.refresh()
            XCTFail("Expected the invented query failure to block JSON creation")
        } catch ProbeError.queryFailed {
            XCTAssertEqual(provider.fetchCount, 1)
        }
    }

    func testServiceFreezesCutoffBeforeQueryAndRecordsLaterExportTime() async throws {
        let calendar = londonCalendar()
        let cutoff = date(2026, 9, 6, 8, calendar: calendar)
        let exportedAt = cutoff.addingTimeInterval(30)
        let provider = RecordingDailyProvider { window in
            self.emptyInputs(window: window)
        }
        var times = [cutoff, exportedAt].makeIterator()
        let service = DailyHealthExportService(
            healthData: provider,
            calendar: calendar,
            now: { times.next()! }
        )

        let result = try await service.refresh()

        XCTAssertEqual(provider.window?.cutoff, cutoff)
        XCTAssertEqual(result.envelope.dataAsOf, "2026-09-06T08:00:00+01:00")
        XCTAssertEqual(result.envelope.exportedAt, "2026-09-06T08:00:30+01:00")
        XCTAssertEqual(result.envelope.appContext.policyID, "last_7_completed_days_v1")
    }

    private func londonCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_GB")
        calendar.timeZone = TimeZone(identifier: "Europe/London")!
        return calendar
    }

    private func date(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        _ hour: Int,
        calendar: Calendar
    ) -> Date {
        calendar.date(from: DateComponents(
            year: year,
            month: month,
            day: day,
            hour: hour
        ))!
    }

    private func pressure(
        _ suffix: UInt8,
        at date: Date,
        _ systolic: Double,
        _ diastolic: Double
    ) -> BloodPressureReading {
        return BloodPressureReading(
            id: UUID(uuidString: String(
                format: "00000000-0000-0000-0000-0000000000%02X",
                suffix
            ))!,
            date: date,
            systolicMillimetresOfMercury: systolic,
            diastolicMillimetresOfMercury: diastolic,
            sourceName: "Invented monitor"
        )
    }

    private func glucose(
        _ interval: DateInterval,
        average: Double? = nil,
        minimum: Double? = nil,
        maximum: Double? = nil
    ) -> DailyGlucoseValue {
        DailyGlucoseValue(
            day: interval,
            averageMillimolesPerLiter: average,
            minimumMillimolesPerLiter: minimum,
            maximumMillimolesPerLiter: maximum,
            sourceNames: average == nil ? [] : ["Invented sensor"]
        )
    }

    private func historicalWeights(window: DailyExportWindow) -> [WeightMeasurement] {
        (1...10).map { offset in
            WeightMeasurement(
                date: window.calendar.date(
                    byAdding: .day,
                    value: -offset,
                    to: window.day.start
                )!.addingTimeInterval(8 * 3_600),
                kilograms: 80 + Double(offset) / 10
            )
        }
    }

    private func emptyInputs(window: DailyExportWindow) -> DailyHealthExportInputs {
        let emptyTodayHeart = DailyHeartMetricValue(
            day: window.day,
            value: nil,
            sourceNames: []
        )
        let contextHearts = window.context.completedDays.map {
            DailyHeartMetricValue(day: $0, value: nil, sourceNames: [])
        }
        let previous = window.context.precedingEquivalent(calendar: window.calendar)!
        let previousHearts = previous.completedDays.map {
            DailyHeartMetricValue(day: $0, value: nil, sourceNames: [])
        }
        return DailyHealthExportInputs(
            weight: [],
            bodyFat: [],
            waist: [],
            vo2Max: [],
            bloodOxygen: [],
            bloodPressure: [],
            todaySteps: DailyStepTotal(day: window.day, steps: nil, sourceNames: []),
            todayGlucose: glucose(window.day),
            hourlyGlucose: window.glucoseHours.map { glucose($0) },
            todayRestingHeartRate: emptyTodayHeart,
            todayHRV: emptyTodayHeart,
            todayWatchSampleDates: [],
            todayActiveEnergyKilocalories: nil,
            todayExerciseMinutes: nil,
            todayWorkouts: [],
            todayAsleepIntervals: [],
            todayMedicationDoses: [],
            supportsMedicationData: true,
            contextSteps: window.context.completedDays.map {
                DailyStepTotal(day: $0, steps: nil, sourceNames: [])
            },
            contextGlucose: window.context.completedDays.map { glucose($0) },
            contextRestingHeartRate: contextHearts,
            previousRestingHeartRate: previousHearts,
            contextHRV: contextHearts,
            previousHRV: previousHearts,
            contextWatchSampleDates: [],
            contextActiveEnergyKilocalories: nil,
            contextExerciseMinutes: nil,
            contextWorkouts: [],
            contextAsleepIntervals: [],
            contextMedicationDoses: []
        )
    }

    private func populatedInputs(window: DailyExportWindow) -> DailyHealthExportInputs {
        let calendar = window.calendar
        func day(_ offset: Int, hour: Int = 8) -> Date {
            calendar.date(byAdding: .day, value: -offset, to: window.day.start)!
                .addingTimeInterval(Double(hour) * 3_600)
        }
        let weights = (0...14).map {
            WeightMeasurement(date: day($0), kilograms: 80 + Double($0) / 10)
        }
        let bodyFat = [
            BodyFatMeasurement(date: day(1), percentage: 20),
            BodyFatMeasurement(date: day(2), percentage: 22),
            BodyFatMeasurement(date: day(30), percentage: 24),
            BodyFatMeasurement(date: day(40), percentage: 26)
        ]
        let waist = [
            WaistMeasurement(date: day(0), centimetres: 90),
            WaistMeasurement(date: day(28), centimetres: 92)
        ]
        let vo2 = [1, 10, 20, 100].map {
            VO2MaxMeasurement(
                date: day($0),
                millilitresPerKilogramMinute: 40 + Double($0) / 100,
                sourceName: "Invented Watch"
            )
        }
        let oxygen = [0, 1, 2].map {
            OxygenSaturationMeasurement(
                date: day($0),
                percentage: 96 + Double($0),
                sourceName: "Invented Watch"
            )
        }
        let pressures = [
            pressure(10, at: day(0), 121, 81),
            pressure(11, at: day(1), 120, 80),
            pressure(12, at: day(2, hour: 18), 130, 85)
        ]
        let contextSteps = window.context.completedDays.enumerated().map { index, interval in
            DailyStepTotal(
                day: interval,
                steps: 1_000 + Double(index),
                sourceNames: ["Invented resolver"]
            )
        }
        let contextGlucose = window.context.completedDays.enumerated().map { index, interval in
            glucose(
                interval,
                average: 5 + Double(index) / 10,
                minimum: 4,
                maximum: 7
            )
        }
        let contextHeart = window.context.completedDays.enumerated().map { index, interval in
            DailyHeartMetricValue(
                day: interval,
                value: 60 + Double(index),
                sourceNames: ["Invented Watch"]
            )
        }
        let previous = window.context.precedingEquivalent(calendar: calendar)!
        let previousHeart = previous.completedDays.enumerated().map { index, interval in
            DailyHeartMetricValue(
                day: interval,
                value: 58 + Double(index),
                sourceNames: ["Invented Watch"]
            )
        }
        let sleeps = window.context.completedDays.map { interval in
            AsleepInterval(
                start: calendar.date(byAdding: .hour, value: -1, to: interval.start)!,
                end: calendar.date(byAdding: .hour, value: 7, to: interval.start)!
            )
        }
        let medication = MedicationDoseRecord(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000099")!,
            medicationKey: "invented-medication",
            medicationName: "Invented medicine",
            date: day(1),
            quantity: 1,
            unitLabel: "dose"
        )
        let workout = WorkoutRecord(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000088")!,
            startDate: day(1),
            duration: 1_800,
            activityName: "Invented workout"
        )
        return DailyHealthExportInputs(
            weight: weights,
            bodyFat: bodyFat,
            waist: waist,
            vo2Max: vo2,
            bloodOxygen: oxygen,
            bloodPressure: pressures,
            todaySteps: DailyStepTotal(day: window.day, steps: 2_000, sourceNames: []),
            todayGlucose: glucose(window.day, average: 5.4, minimum: 4, maximum: 7),
            hourlyGlucose: window.glucoseHours.map { glucose($0) },
            todayRestingHeartRate: DailyHeartMetricValue(
                day: window.day,
                value: 61,
                sourceNames: []
            ),
            todayHRV: DailyHeartMetricValue(day: window.day, value: 42, sourceNames: []),
            todayWatchSampleDates: [day(0)],
            todayActiveEnergyKilocalories: 500,
            todayExerciseMinutes: 45,
            todayWorkouts: [],
            todayAsleepIntervals: [],
            todayMedicationDoses: [],
            supportsMedicationData: true,
            contextSteps: contextSteps,
            contextGlucose: contextGlucose,
            contextRestingHeartRate: contextHeart,
            previousRestingHeartRate: previousHeart,
            contextHRV: contextHeart,
            previousHRV: previousHeart,
            contextWatchSampleDates: [day(1), day(2)],
            contextActiveEnergyKilocalories: 3_500,
            contextExerciseMinutes: 210,
            contextWorkouts: [workout],
            contextAsleepIntervals: sleeps,
            contextMedicationDoses: [medication]
        )
    }

    private func replacing(
        _ value: DailyHealthExportInputs,
        weight: [WeightMeasurement]? = nil,
        bodyFat: [BodyFatMeasurement]? = nil,
        bloodOxygen: [OxygenSaturationMeasurement]? = nil,
        bloodPressure: [BloodPressureReading]? = nil,
        todayGlucose: DailyGlucoseValue? = nil,
        hourlyGlucose: [DailyGlucoseValue]? = nil,
        todaySteps: DailyStepTotal? = nil,
        supportsMedicationData: Bool? = nil
    ) -> DailyHealthExportInputs {
        DailyHealthExportInputs(
            weight: weight ?? value.weight,
            bodyFat: bodyFat ?? value.bodyFat,
            waist: value.waist,
            vo2Max: value.vo2Max,
            bloodOxygen: bloodOxygen ?? value.bloodOxygen,
            bloodPressure: bloodPressure ?? value.bloodPressure,
            todaySteps: todaySteps ?? value.todaySteps,
            todayGlucose: todayGlucose ?? value.todayGlucose,
            hourlyGlucose: hourlyGlucose ?? value.hourlyGlucose,
            todayRestingHeartRate: value.todayRestingHeartRate,
            todayHRV: value.todayHRV,
            todayWatchSampleDates: value.todayWatchSampleDates,
            todayActiveEnergyKilocalories: value.todayActiveEnergyKilocalories,
            todayExerciseMinutes: value.todayExerciseMinutes,
            todayWorkouts: value.todayWorkouts,
            todayAsleepIntervals: value.todayAsleepIntervals,
            todayMedicationDoses: value.todayMedicationDoses,
            supportsMedicationData: supportsMedicationData ?? value.supportsMedicationData,
            contextSteps: value.contextSteps,
            contextGlucose: value.contextGlucose,
            contextRestingHeartRate: value.contextRestingHeartRate,
            previousRestingHeartRate: value.previousRestingHeartRate,
            contextHRV: value.contextHRV,
            previousHRV: value.previousHRV,
            contextWatchSampleDates: value.contextWatchSampleDates,
            contextActiveEnergyKilocalories: value.contextActiveEnergyKilocalories,
            contextExerciseMinutes: value.contextExerciseMinutes,
            contextWorkouts: value.contextWorkouts,
            contextAsleepIntervals: value.contextAsleepIntervals,
            contextMedicationDoses: value.contextMedicationDoses
        )
    }
}

private enum ProbeError: Error {
    case queryFailed
}

private final class FailingDailyProvider: DailyHealthExportDataProviding {
    let isHealthDataAvailable = true
    private(set) var fetchCount = 0

    func requestReadAuthorization() async throws {}

    func fetchDailyHealthExportInputs(
        for window: DailyExportWindow
    ) async throws -> DailyHealthExportInputs {
        fetchCount += 1
        throw ProbeError.queryFailed
    }
}

private final class RecordingDailyProvider: DailyHealthExportDataProviding {
    let isHealthDataAvailable = true
    private let makeInputs: (DailyExportWindow) -> DailyHealthExportInputs
    private(set) var window: DailyExportWindow?

    init(makeInputs: @escaping (DailyExportWindow) -> DailyHealthExportInputs) {
        self.makeInputs = makeInputs
    }

    func requestReadAuthorization() async throws {}

    func fetchDailyHealthExportInputs(
        for window: DailyExportWindow
    ) async throws -> DailyHealthExportInputs {
        self.window = window
        return makeInputs(window)
    }
}
