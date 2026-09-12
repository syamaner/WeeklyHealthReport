import Foundation

enum DailyHealthExportError: Error, Equatable {
    case invalidTimeZone
    case invalidWindow
    case invalidMetricValue
    case nutritionSourceRequired
    case nutritionSourceUnavailable
    case notesChanged
    case notesUnavailable
}

struct DailyExportWindow: Equatable {
    let reportDate: String
    let timeZoneIdentifier: String
    let cutoff: Date
    let day: DateInterval
    let context: ReportPeriod
    let sleep: DateInterval
    let glucoseHours: [DateInterval]
    let calendar: Calendar

    static func capture(
        at cutoff: Date,
        calendar suppliedCalendar: Calendar
    ) throws -> DailyExportWindow {
        var calendar = Calendar(identifier: suppliedCalendar.identifier)
        calendar.timeZone = suppliedCalendar.timeZone
        calendar.locale = suppliedCalendar.locale
        calendar.firstWeekday = suppliedCalendar.firstWeekday
        calendar.minimumDaysInFirstWeek = suppliedCalendar.minimumDaysInFirstWeek
        guard !calendar.timeZone.identifier.isEmpty else {
            throw DailyHealthExportError.invalidTimeZone
        }

        let start = calendar.startOfDay(for: cutoff)
        guard start <= cutoff,
              let previousDay = calendar.date(byAdding: .day, value: -1, to: start),
              let sleepStart = calendar.date(
                bySettingHour: 12,
                minute: 0,
                second: 0,
                of: previousDay
              ),
              let noon = calendar.date(
                bySettingHour: 12,
                minute: 0,
                second: 0,
                of: start
              )
        else {
            throw DailyHealthExportError.invalidWindow
        }

        var hours: [DateInterval] = []
        var cursor = start
        while cursor < cutoff {
            guard let nextHour = calendar.date(byAdding: .hour, value: 1, to: cursor),
                  nextHour > cursor
            else {
                throw DailyHealthExportError.invalidWindow
            }
            let end = min(nextHour, cutoff)
            hours.append(DateInterval(start: cursor, end: end))
            cursor = end
        }

        return DailyExportWindow(
            reportDate: ExportDateText.date(start, calendar: calendar),
            timeZoneIdentifier: calendar.timeZone.identifier,
            cutoff: cutoff,
            day: DateInterval(start: start, end: cutoff),
            context: ReportPeriod.make(
                selection: .lastSevenCompletedDays,
                now: cutoff,
                calendar: calendar
            ),
            sleep: DateInterval(start: sleepStart, end: min(noon, cutoff)),
            glucoseHours: hours,
            calendar: calendar
        )
    }
}

enum ExportAvailability: String, Codable, Equatable {
    case available
    case noDataOrAccess = "no_data_or_access"
    case unsupported
    case insufficientData = "insufficient_data"
}

struct ExportMetric<Value: Codable & Equatable>: Codable, Equatable {
    let availability: ExportAvailability
    let data: Value?

    static func available(_ value: Value) -> ExportMetric<Value> {
        ExportMetric(availability: .available, data: value)
    }

    static var noDataOrAccess: ExportMetric<Value> {
        ExportMetric(availability: .noDataOrAccess, data: nil)
    }

    static var unsupported: ExportMetric<Value> {
        ExportMetric(availability: .unsupported, data: nil)
    }

    static var insufficientData: ExportMetric<Value> {
        ExportMetric(availability: .insufficientData, data: nil)
    }
}

struct ExportInterval: Codable, Equatable {
    let start: String
    let end: String
}

struct ExportScalar: Codable, Equatable {
    let value: Double
    let unit: String
}

struct ExportTimestampedScalar: Codable, Equatable {
    let value: Double
    let unit: String
    let recordedAt: String
}

struct ExportStatistics: Codable, Equatable {
    let average: Double
    let minimum: Double
    let maximum: Double
    let unit: String
    let sourceNames: [String]
}

struct ExportCoverage: Codable, Equatable {
    let sampledDays: Int
    let reportingDays: Int
}

struct ExportWindowedScalar: Codable, Equatable {
    let value: Double
    let unit: String
    let window: ExportInterval
    let coverage: ExportCoverage
}

struct ExportTrend: Codable, Equatable {
    let change: Double
    let unit: String
    let comparison: String
}

struct DailyWeightData: Codable, Equatable {
    let value: Double
    let unit: String
    let recordedAt: String
}

struct DailyMeasurementListData: Codable, Equatable {
    let measurements: [ExportTimestampedScalar]
}

struct DailyBodyFatData: Codable, Equatable {
    let measurements: [ExportTimestampedScalar]
    let dailyAverage: ExportScalar
}

struct DailyBloodOxygenData: Codable, Equatable {
    let measurements: [ExportTimestampedScalar]
    let dailyMedian: ExportScalar
}

struct DailyBloodPressureReading: Codable, Equatable {
    let systolic: Double
    let diastolic: Double
    let unit: String
    let recordedAt: String
    let slot: String?
}

struct DailyBloodPressureData: Codable, Equatable {
    let readings: [DailyBloodPressureReading]
    let morning: ExportMetric<ExportBloodPressureBatch>
    let evening: ExportMetric<ExportBloodPressureBatch>
}

struct ExportBloodPressureBatch: Codable, Equatable {
    let averageSystolic: Double
    let averageDiastolic: Double
    let unit: String
    let readingCount: Int
}

struct HourlyGlucoseData: Codable, Equatable {
    let window: ExportInterval
    let statistics: ExportMetric<ExportStatistics>
}

struct DailyGlucoseData: Codable, Equatable {
    let statistics: ExportStatistics
    let hours: [HourlyGlucoseData]
}

struct DailySleepData: Codable, Equatable {
    let wakeDate: String
    let durationSeconds: Double
    let intervals: [ExportInterval]
}

struct DailyActivityData: Codable, Equatable {
    let steps: ExportMetric<ExportScalar>
    let activeEnergy: ExportMetric<ExportScalar>
    let exercise: ExportMetric<ExportScalar>
}

struct DailyWorkoutData: Codable, Equatable {
    let recordID: String
    let activity: String
    let startedAt: String
    let durationSeconds: Double

    private enum CodingKeys: String, CodingKey {
        case recordID = "recordId"
        case activity
        case startedAt
        case durationSeconds
    }
}

struct DailyMedicationData: Codable, Equatable {
    let medication: String
    let recordedAt: String
    let quantity: Double?
    let unit: String
}

struct DailyWatchCoverageData: Codable, Equatable {
    let qualifyingDataPresent: Bool
}

struct DailyNutritionNutrient: Codable, Equatable {
    let key: String
    let label: String
    let category: NutritionCategory
    let unit: String
    let value: ExportMetric<ExportScalar>
}

struct DailyNutritionData: Codable, Equatable {
    let source: NutritionSource
    let nutrients: [DailyNutritionNutrient]
}

struct ExportNutritionDay: Codable, Equatable {
    let date: String
    let value: ExportMetric<ExportScalar>
}

struct ExportNutritionAverage: Codable, Equatable {
    let value: Double
    let unit: String
    let sampledDays: Int
    let reportingDays: Int
}

struct ExportNutritionTrend: Codable, Equatable {
    let change: Double
    let unit: String
}

struct ExportNutritionNutrientContext: Codable, Equatable {
    let key: String
    let label: String
    let category: NutritionCategory
    let unit: String
    let days: [ExportNutritionDay]
    let average: ExportMetric<ExportNutritionAverage>
    let previousAverage: ExportMetric<ExportNutritionAverage>
    let trend: ExportMetric<ExportNutritionTrend>
}

struct ExportNutritionContext: Codable, Equatable {
    let policyID: String
    let currentWindow: ExportInterval
    let previousWindow: ExportInterval
    let nutrients: [ExportNutritionNutrientContext]

    private enum CodingKeys: String, CodingKey {
        case policyID = "policyId"
        case currentWindow
        case previousWindow
        case nutrients
    }
}

struct DailyHealthMetrics: Codable, Equatable {
    let notes: [String]?
    let weight: ExportMetric<DailyWeightData>
    let bodyFat: ExportMetric<DailyBodyFatData>
    let waist: ExportMetric<DailyMeasurementListData>
    let bloodPressure: ExportMetric<DailyBloodPressureData>
    let glucose: ExportMetric<DailyGlucoseData>
    let restingHeartRate: ExportMetric<ExportScalar>
    let hrv: ExportMetric<ExportScalar>
    let bloodOxygen: ExportMetric<DailyBloodOxygenData>
    let vo2Max: ExportMetric<DailyMeasurementListData>
    let sleep: ExportMetric<DailySleepData>
    let activity: DailyActivityData
    let workouts: ExportMetric<[DailyWorkoutData]>
    let watchCoverage: ExportMetric<DailyWatchCoverageData>
    let medications: ExportMetric<[DailyMedicationData]>
    let nutrition: DailyNutritionData?

    private enum CodingKeys: String, CodingKey {
        case notes, weight, bodyFat, waist, bloodPressure, glucose
        case restingHeartRate, hrv, bloodOxygen, vo2Max, sleep
        case activity, workouts, watchCoverage, medications, nutrition
    }
}

struct ExportWeightContext: Codable, Equatable {
    let latest: ExportTimestampedScalar
    let currentSevenDayAverage: ExportMetric<ExportWindowedScalar>
    let previousSevenDayAverage: ExportMetric<ExportWindowedScalar>
    let trend: ExportMetric<ExportTrend>
}

struct ExportBodyFatContext: Codable, Equatable {
    let latest: ExportTimestampedScalar
    let sevenDayAverage: ExportMetric<ExportWindowedScalar>
    let current28DayAverage: ExportMetric<ExportWindowedScalar>
    let previous28DayAverage: ExportMetric<ExportWindowedScalar>
    let trend: ExportMetric<ExportTrend>
}

struct ExportWaistContext: Codable, Equatable {
    let latest: ExportTimestampedScalar
    let comparison: ExportMetric<ExportTimestampedScalar>
    let fourWeekChange: ExportMetric<ExportTrend>
}

struct ExportVO2Window: Codable, Equatable {
    let window: ExportInterval
    let average: ExportMetric<ExportScalar>
    let sampledDays: Int
}

struct ExportVO2Context: Codable, Equatable {
    let latest: ExportTimestampedScalar
    let fourWeek: ExportVO2Window
    let threeMonth: ExportVO2Window
    let sixMonth: ExportVO2Window
}

struct ExportGlucoseContext: Codable, Equatable {
    let statistics: ExportStatistics
    let coverage: ExportCoverage
}

struct ExportHeartContext: Codable, Equatable {
    let currentAverage: ExportWindowedScalar
    let previousAverage: ExportMetric<ExportWindowedScalar>
    let trend: ExportMetric<ExportTrend>
}

struct ExportBloodOxygenContext: Codable, Equatable {
    let latest: ExportTimestampedScalar
    let typical: ExportMetric<ExportScalar>
    let dailyMedianRange: ExportMetric<ExportRange>
    let coverage: ExportCoverage
}

struct ExportRange: Codable, Equatable {
    let minimum: Double
    let maximum: Double
    let unit: String
}

struct ExportBloodPressureSlotContext: Codable, Equatable {
    let averageSystolic: Double
    let averageDiastolic: Double
    let unit: String
    let coverage: ExportCoverage
    let readingCount: Int
}

struct ExportBloodPressureContext: Codable, Equatable {
    let latest: DailyBloodPressureReading
    let morning: ExportMetric<ExportBloodPressureSlotContext>
    let evening: ExportMetric<ExportBloodPressureSlotContext>
}

struct ExportStepContext: Codable, Equatable {
    let total: ExportScalar
    let dailyAverage: ExportScalar
    let coverage: ExportCoverage
}

struct ExportSleepContext: Codable, Equatable {
    let averageDurationSeconds: Double
    let coverage: ExportCoverage
}

struct ExportWorkoutContext: Codable, Equatable {
    let count: Int
    let totalDurationSeconds: Double
}

struct ExportMedicationContext: Codable, Equatable {
    let takenEventCount: Int
    let medicationCount: Int
    let medications: [ExportMedicationGroup]
}

struct ExportMedicationGroup: Codable, Equatable {
    let medication: String
    let takenEventCount: Int
    let latest: DailyMedicationData
}

struct DailyAppContext: Codable, Equatable {
    let policyID: String
    let window: ExportInterval
    let weight: ExportMetric<ExportWeightContext>
    let bodyFat: ExportMetric<ExportBodyFatContext>
    let waist: ExportMetric<ExportWaistContext>
    let glucose: ExportMetric<ExportGlucoseContext>
    let vo2Max: ExportMetric<ExportVO2Context>
    let bloodOxygen: ExportMetric<ExportBloodOxygenContext>
    let bloodPressure: ExportMetric<ExportBloodPressureContext>
    let steps: ExportMetric<ExportStepContext>
    let restingHeartRate: ExportMetric<ExportHeartContext>
    let hrv: ExportMetric<ExportHeartContext>
    let watchCoverage: ExportMetric<ExportCoverage>
    let sleep: ExportMetric<ExportSleepContext>
    let activeEnergy: ExportMetric<ExportScalar>
    let exercise: ExportMetric<ExportScalar>
    let workouts: ExportMetric<ExportWorkoutContext>
    let medications: ExportMetric<ExportMedicationContext>
    let nutrition: ExportNutritionContext?

    private enum CodingKeys: String, CodingKey {
        case policyID = "policyId"
        case window
        case weight
        case bodyFat
        case waist
        case glucose
        case vo2Max
        case bloodOxygen
        case bloodPressure
        case steps
        case restingHeartRate
        case hrv
        case watchCoverage
        case sleep
        case activeEnergy
        case exercise
        case workouts
        case medications
        case nutrition
    }
}

struct DailyHealthExportEnvelope: Codable, Equatable {
    let schemaVersion: Int
    let reportDate: String
    let timeZone: String
    let dataAsOf: String
    let exportedAt: String
    let dayWindow: ExportInterval
    let today: DailyHealthMetrics
    let appContext: DailyAppContext
}

struct DailyHealthExportInputs: Equatable {
    let weight: [WeightMeasurement]
    let bodyFat: [BodyFatMeasurement]
    let waist: [WaistMeasurement]
    let vo2Max: [VO2MaxMeasurement]
    let bloodOxygen: [OxygenSaturationMeasurement]
    let bloodPressure: [BloodPressureReading]
    let todaySteps: DailyStepTotal
    let todayGlucose: DailyGlucoseValue
    let hourlyGlucose: [DailyGlucoseValue]
    let todayRestingHeartRate: DailyHeartMetricValue
    let todayHRV: DailyHeartMetricValue
    let todayWatchSampleDates: [Date]
    let todayActiveEnergyKilocalories: Double?
    let todayExerciseMinutes: Double?
    let todayWorkouts: [WorkoutRecord]
    let todayAsleepIntervals: [AsleepInterval]
    let todayMedicationDoses: [MedicationDoseRecord]
    let supportsMedicationData: Bool
    let contextSteps: [DailyStepTotal]
    let contextGlucose: [DailyGlucoseValue]
    let contextRestingHeartRate: [DailyHeartMetricValue]
    let previousRestingHeartRate: [DailyHeartMetricValue]
    let contextHRV: [DailyHeartMetricValue]
    let previousHRV: [DailyHeartMetricValue]
    let contextWatchSampleDates: [Date]
    let contextActiveEnergyKilocalories: Double?
    let contextExerciseMinutes: Double?
    let contextWorkouts: [WorkoutRecord]
    let contextAsleepIntervals: [AsleepInterval]
    let contextMedicationDoses: [MedicationDoseRecord]
    let nutrition: NutritionExportInput
}

enum DailyHealthExportBuilder {
    static func make(
        window: DailyExportWindow,
        exportedAt: Date,
        inputs: DailyHealthExportInputs,
        notes: [String] = []
    ) throws -> DailyHealthExportEnvelope {
        guard exportedAt >= window.cutoff else {
            throw DailyHealthExportError.invalidWindow
        }
        let calendar = window.calendar
        let interval = { ExportDateText.interval($0, calendar: calendar) }
        let timestamp = { ExportDateText.timestamp($0, calendar: calendar) }

        func finite(_ values: [Double]) throws {
            guard values.allSatisfy(\.isFinite) else {
                throw DailyHealthExportError.invalidMetricValue
            }
        }

        try finite(inputs.weight.map(\.kilograms))
        try finite(inputs.bodyFat.map(\.percentage))
        try finite(inputs.waist.map(\.centimetres))
        try finite(inputs.vo2Max.map(\.millilitresPerKilogramMinute))
        try finite(inputs.bloodOxygen.map(\.percentage))
        try finite(inputs.bloodPressure.flatMap {
            [$0.systolicMillimetresOfMercury, $0.diastolicMillimetresOfMercury]
        })
        try finite([
            inputs.todaySteps.steps,
            inputs.todayRestingHeartRate.value,
            inputs.todayHRV.value,
            inputs.todayActiveEnergyKilocalories,
            inputs.todayExerciseMinutes,
            inputs.contextActiveEnergyKilocalories,
            inputs.contextExerciseMinutes
        ].compactMap { $0 })
        try finite(([
            inputs.todayGlucose
        ] + inputs.hourlyGlucose + inputs.contextGlucose).flatMap {
            [
                $0.averageMillimolesPerLiter,
                $0.minimumMillimolesPerLiter,
                $0.maximumMillimolesPerLiter
            ].compactMap { $0 }
        })
        try finite(([
            inputs.todayRestingHeartRate,
            inputs.todayHRV
        ] + inputs.contextRestingHeartRate + inputs.previousRestingHeartRate
            + inputs.contextHRV + inputs.previousHRV).compactMap(\.value))
        try finite(inputs.todayWorkouts.map(\.duration) + inputs.contextWorkouts.map(\.duration))
        try finite(inputs.todayMedicationDoses.compactMap(\.quantity)
            + inputs.contextMedicationDoses.compactMap(\.quantity))
        guard inputs.hourlyGlucose.count == window.glucoseHours.count else {
            throw DailyHealthExportError.invalidWindow
        }
        guard notes.count <= DailyNotesPolicy.maximumNotesPerDay,
              notes.allSatisfy({
                  !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                      && $0.count <= DailyNotesPolicy.maximumCharactersPerNote
              }),
              notes.reduce(0, { $0 + $1.count }) <= DailyNotesPolicy.maximumCharactersPerDay else {
            throw DailyHealthExportError.invalidMetricValue
        }
        let nutrition = try makeNutrition(window: window, input: inputs.nutrition)

        let todayWeight = inputs.weight.filter { window.day.containsHalfOpen($0.date) }
        let weight = WeightMeasurement.latest(in: todayWeight).map {
            ExportMetric.available(DailyWeightData(
                value: $0.kilograms,
                unit: "kg",
                recordedAt: timestamp($0.date)
            ))
        } ?? .noDataOrAccess

        func exportedMeasurements(
            _ values: [(Date, Double)],
            unit: String
        ) -> [ExportTimestampedScalar] {
            values.filter { window.day.containsHalfOpen($0.0) }
                .sorted { $0.0 < $1.0 }
                .map {
                    ExportTimestampedScalar(value: $0.1, unit: unit, recordedAt: timestamp($0.0))
                }
        }

        let bodyFatMeasurements = exportedMeasurements(
            inputs.bodyFat.map { ($0.date, $0.percentage) },
            unit: "%"
        )
        let todayBodyFat: ExportMetric<DailyBodyFatData> = bodyFatMeasurements.isEmpty
            ? .noDataOrAccess
            : .available(DailyBodyFatData(
                measurements: bodyFatMeasurements,
                dailyAverage: ExportScalar(
                    value: bodyFatMeasurements.map(\.value).reduce(0, +)
                        / Double(bodyFatMeasurements.count),
                    unit: "%"
                )
            ))

        let oxygenMeasurements = exportedMeasurements(
            inputs.bloodOxygen.map { ($0.date, $0.percentage) },
            unit: "%"
        )
        let todayBloodOxygen: ExportMetric<DailyBloodOxygenData> = oxygenMeasurements.isEmpty
            ? .noDataOrAccess
            : .available(DailyBloodOxygenData(
                measurements: oxygenMeasurements,
                dailyMedian: ExportScalar(
                    value: median(oxygenMeasurements.map(\.value)),
                    unit: "%"
                )
            ))

        func measurementList(
            _ values: [(Date, Double)],
            unit: String
        ) -> ExportMetric<DailyMeasurementListData> {
            let measurements = exportedMeasurements(values, unit: unit)
            return measurements.isEmpty
                ? .noDataOrAccess
                : .available(DailyMeasurementListData(measurements: measurements))
        }

        let todayBloodPressure = inputs.bloodPressure
            .filter { window.day.containsHalfOpen($0.date) }
            .sorted { $0.date < $1.date }
        let bloodPressure: ExportMetric<DailyBloodPressureData>
        if todayBloodPressure.isEmpty {
            bloodPressure = .noDataOrAccess
        } else {
            func batch(_ slot: BloodPressureTimeSlot) -> ExportMetric<ExportBloodPressureBatch> {
                let readings = todayBloodPressure.filter {
                    BloodPressureTimeSlot.classify($0.date, calendar: calendar) == slot
                }
                guard !readings.isEmpty else { return .noDataOrAccess }
                return .available(ExportBloodPressureBatch(
                    averageSystolic: readings.map(\.systolicMillimetresOfMercury).reduce(0, +)
                        / Double(readings.count),
                    averageDiastolic: readings.map(\.diastolicMillimetresOfMercury).reduce(0, +)
                        / Double(readings.count),
                    unit: "mmHg",
                    readingCount: readings.count
                ))
            }
            bloodPressure = .available(DailyBloodPressureData(
                readings: todayBloodPressure.map {
                    DailyBloodPressureReading(
                        systolic: $0.systolicMillimetresOfMercury,
                        diastolic: $0.diastolicMillimetresOfMercury,
                        unit: "mmHg",
                        recordedAt: timestamp($0.date),
                        slot: BloodPressureTimeSlot.classify($0.date, calendar: calendar)?.rawValue
                    )
                },
                morning: batch(.morning),
                evening: batch(.evening)
            ))
        }

        let hourly = zip(window.glucoseHours, inputs.hourlyGlucose).map { hour, value in
            HourlyGlucoseData(
                window: interval(hour),
                statistics: glucoseStatistics(value).map(ExportMetric.available)
                    ?? .noDataOrAccess
            )
        }
        let glucose = glucoseStatistics(inputs.todayGlucose).map {
            ExportMetric.available(DailyGlucoseData(statistics: $0, hours: hourly))
        } ?? .noDataOrAccess

        let mergedSleep = SleepSummary.mergeOverlaps(inputs.todayAsleepIntervals.compactMap {
            let start = max($0.start, window.sleep.start)
            let end = min($0.end, window.sleep.end)
            return start < end ? AsleepInterval(start: start, end: end) : nil
        })
        let sleep: ExportMetric<DailySleepData> = mergedSleep.isEmpty
            ? .noDataOrAccess
            : .available(DailySleepData(
                wakeDate: window.reportDate,
                durationSeconds: mergedSleep.reduce(0) { $0 + $1.duration },
                intervals: mergedSleep.map { interval(DateInterval(start: $0.start, end: $0.end)) }
            ))

        let todayMedicationDoses = inputs.todayMedicationDoses.filter {
            window.day.containsHalfOpen($0.date)
        }
        let medications: ExportMetric<[DailyMedicationData]> = !inputs.supportsMedicationData
            ? .unsupported
            : todayMedicationDoses.isEmpty
                ? .noDataOrAccess
                : .available(todayMedicationDoses.sorted { $0.date < $1.date }.map {
                    DailyMedicationData(
                        medication: $0.medicationName,
                        recordedAt: timestamp($0.date),
                        quantity: $0.quantity,
                        unit: $0.unitLabel
                    )
                })

        let today = DailyHealthMetrics(
            notes: notes,
            weight: weight,
            bodyFat: todayBodyFat,
            waist: measurementList(
                inputs.waist.map { ($0.date, $0.centimetres) },
                unit: "cm"
            ),
            bloodPressure: bloodPressure,
            glucose: glucose,
            restingHeartRate: scalar(inputs.todayRestingHeartRate.value, unit: "bpm"),
            hrv: scalar(inputs.todayHRV.value, unit: "ms"),
            bloodOxygen: todayBloodOxygen,
            vo2Max: measurementList(
                inputs.vo2Max.map { ($0.date, $0.millilitresPerKilogramMinute) },
                unit: "mL/kg/min"
            ),
            sleep: sleep,
            activity: DailyActivityData(
                steps: scalar(inputs.todaySteps.steps, unit: "count"),
                activeEnergy: scalar(inputs.todayActiveEnergyKilocalories, unit: "kcal"),
                exercise: scalar(inputs.todayExerciseMinutes, unit: "min")
            ),
            workouts: inputs.todayWorkouts.filter {
                window.day.containsHalfOpen($0.startDate)
            }.isEmpty
                ? .noDataOrAccess
                : .available(inputs.todayWorkouts.filter {
                    window.day.containsHalfOpen($0.startDate)
                }.sorted { $0.startDate < $1.startDate }.map {
                    DailyWorkoutData(
                        recordID: $0.id.uuidString.lowercased(),
                        activity: $0.activityName,
                        startedAt: timestamp($0.startDate),
                        durationSeconds: $0.duration
                    )
                }),
            watchCoverage: inputs.todayWatchSampleDates.contains {
                window.day.containsHalfOpen($0)
            }
                ? .available(DailyWatchCoverageData(qualifyingDataPresent: true))
                : .noDataOrAccess,
            medications: medications,
            nutrition: nutrition.today
        )

        let context = try makeContext(
            window: window,
            inputs: inputs,
            calendar: calendar,
            nutrition: nutrition.context
        )
        return DailyHealthExportEnvelope(
            schemaVersion: 3,
            reportDate: window.reportDate,
            timeZone: window.timeZoneIdentifier,
            dataAsOf: timestamp(window.cutoff),
            exportedAt: timestamp(exportedAt),
            dayWindow: interval(window.day),
            today: today,
            appContext: context
        )
    }

    private static func makeNutrition(
        window: DailyExportWindow,
        input: NutritionExportInput
    ) throws -> (today: DailyNutritionData, context: ExportNutritionContext) {
        guard !input.source.bundleIdentifier.isEmpty,
              input.nutrients.map(\.key) == NutritionCatalogue.all.map(\.key),
              let previous = window.context.precedingEquivalent(calendar: window.calendar)
        else {
            throw DailyHealthExportError.invalidWindow
        }

        let currentDays = window.context.completedDays.map(\.start)
        let previousDays = previous.completedDays.map(\.start)
        guard input.nutrients.allSatisfy({ nutrient in
            nutrient.currentDays.map(\.day) == currentDays
                && nutrient.previousDays.map(\.day) == previousDays
        }) else {
            throw DailyHealthExportError.invalidWindow
        }

        let values = input.nutrients.flatMap { nutrient in
            [nutrient.today].compactMap { $0 }
                + nutrient.currentDays.compactMap(\.value)
                + nutrient.previousDays.compactMap(\.value)
        }
        guard values.allSatisfy(\.isFinite) else {
            throw DailyHealthExportError.invalidMetricValue
        }

        func scalar(_ value: Double?, unit: NutritionExportUnit) -> ExportMetric<ExportScalar> {
            value.map {
                .available(ExportScalar(value: $0, unit: unit.rawValue))
            } ?? .noDataOrAccess
        }

        func average(
            _ days: [NutritionDailyTotal],
            unit: NutritionExportUnit
        ) -> ExportMetric<ExportNutritionAverage> {
            let available = days.compactMap(\.value)
            guard !available.isEmpty else { return .noDataOrAccess }
            return .available(ExportNutritionAverage(
                value: available.reduce(0, +) / Double(available.count),
                unit: unit.rawValue,
                sampledDays: available.count,
                reportingDays: days.count
            ))
        }

        var todayNutrients: [DailyNutritionNutrient] = []
        var contextNutrients: [ExportNutritionNutrientContext] = []
        for (definition, totals) in zip(NutritionCatalogue.all, input.nutrients) {
            let currentValues = totals.currentDays.compactMap(\.value)
            let previousValues = totals.previousDays.compactMap(\.value)
            let currentAverage = average(totals.currentDays, unit: definition.unit)
            let previousAverage = average(totals.previousDays, unit: definition.unit)
            let trend: ExportMetric<ExportNutritionTrend>
            if currentValues.count == 7, previousValues.count == 7 {
                let current = currentValues.reduce(0, +) / 7
                let prior = previousValues.reduce(0, +) / 7
                trend = .available(ExportNutritionTrend(
                    change: current - prior,
                    unit: definition.unit.rawValue
                ))
            } else {
                trend = .insufficientData
            }

            todayNutrients.append(DailyNutritionNutrient(
                key: definition.key,
                label: definition.label,
                category: definition.category,
                unit: definition.unit.rawValue,
                value: scalar(totals.today, unit: definition.unit)
            ))
            contextNutrients.append(ExportNutritionNutrientContext(
                key: definition.key,
                label: definition.label,
                category: definition.category,
                unit: definition.unit.rawValue,
                days: totals.currentDays.map {
                    ExportNutritionDay(
                        date: ExportDateText.date($0.day, calendar: window.calendar),
                        value: scalar($0.value, unit: definition.unit)
                    )
                },
                average: currentAverage,
                previousAverage: previousAverage,
                trend: trend
            ))
        }

        return (
            DailyNutritionData(source: input.source, nutrients: todayNutrients),
            ExportNutritionContext(
                policyID: NutritionCatalogue.reportingPolicyID,
                currentWindow: ExportDateText.interval(
                    window.context.interval,
                    calendar: window.calendar
                ),
                previousWindow: ExportDateText.interval(
                    previous.interval,
                    calendar: window.calendar
                ),
                nutrients: contextNutrients
            )
        )
    }

    private static func scalar(_ value: Double?, unit: String) -> ExportMetric<ExportScalar> {
        guard let value, value.isFinite else { return .noDataOrAccess }
        return .available(ExportScalar(value: value, unit: unit))
    }

    private static func glucoseStatistics(_ value: DailyGlucoseValue) -> ExportStatistics? {
        guard let average = value.averageMillimolesPerLiter,
              let minimum = value.minimumMillimolesPerLiter,
              let maximum = value.maximumMillimolesPerLiter,
              average.isFinite, minimum.isFinite, maximum.isFinite
        else { return nil }
        return ExportStatistics(
            average: average,
            minimum: minimum,
            maximum: maximum,
            unit: "mmol/L",
            sourceNames: value.sourceNames
        )
    }

    private static func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        let middle = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[middle - 1] + sorted[middle]) / 2
        }
        return sorted[middle]
    }

    private static func makeContext(
        window: DailyExportWindow,
        inputs: DailyHealthExportInputs,
        calendar: Calendar,
        nutrition: ExportNutritionContext
    ) throws -> DailyAppContext {
        let timestamp = { ExportDateText.timestamp($0, calendar: calendar) }
        let exportInterval = { ExportDateText.interval($0, calendar: calendar) }
        let contextPeriod = window.context
        let previousPeriod = contextPeriod.precedingEquivalent(calendar: calendar)
        let today = calendar.startOfDay(for: window.cutoff)
        guard let vo2WindowStarts = HealthReportingPolicy.vo2MaxWindowStarts(
            asOf: window.cutoff,
            calendar: calendar
        ) else {
            throw DailyHealthExportError.invalidWindow
        }
        guard let bodyFatSevenStart = calendar.date(
            byAdding: .day,
            value: -7,
            to: today
        ), let bodyFatCurrent28Start = calendar.date(
            byAdding: .day,
            value: -28,
            to: today
        ), let bodyFatPrevious28Start = calendar.date(
            byAdding: .day,
            value: -28,
            to: bodyFatCurrent28Start
        ) else {
            throw DailyHealthExportError.invalidWindow
        }

        let weightSummary = WeightTrendSummary.calculate(
            measurements: inputs.weight.filter { $0.date < window.cutoff },
            asOf: window.cutoff,
            calendar: calendar
        )
        let weight: ExportMetric<ExportWeightContext> = weightSummary.map { summary in
            let currentWindow = DateInterval(
                start: contextPeriod.interval.start,
                end: contextPeriod.interval.end
            )
            let previousWindow = previousPeriod?.interval ?? currentWindow
            return .available(ExportWeightContext(
                latest: ExportTimestampedScalar(
                    value: summary.latest.kilograms,
                    unit: "kg",
                    recordedAt: timestamp(summary.latest.date)
                ),
                currentSevenDayAverage: summary.currentSevenDayAverage.map {
                    .available(ExportWindowedScalar(
                        value: $0,
                        unit: "kg",
                        window: exportInterval(currentWindow),
                        coverage: ExportCoverage(
                            sampledDays: summary.dailyValues.filter {
                                currentWindow.containsHalfOpen($0.day)
                            }.count,
                            reportingDays: contextPeriod.completedDays.count
                        )
                    ))
                } ?? .insufficientData,
                previousSevenDayAverage: summary.previousSevenDayAverage.map {
                    .available(ExportWindowedScalar(
                        value: $0,
                        unit: "kg",
                        window: exportInterval(previousWindow),
                        coverage: ExportCoverage(
                            sampledDays: summary.dailyValues.filter {
                                previousWindow.containsHalfOpen($0.day)
                            }.count,
                            reportingDays: contextPeriod.completedDays.count
                        )
                    ))
                } ?? .insufficientData,
                trend: summary.trendKilograms.map {
                    .available(ExportTrend(change: $0, unit: "kg", comparison: "previous_7d"))
                } ?? .insufficientData
            ))
        } ?? .noDataOrAccess

        let bodyFatSummary = BodyFatTrendSummary.calculate(
            measurements: inputs.bodyFat.filter { $0.date < window.cutoff },
            asOf: window.cutoff,
            calendar: calendar
        )
        let bodyFat: ExportMetric<ExportBodyFatContext> = bodyFatSummary.map { summary in
            func average(
                _ value: Double?,
                start: Date,
                end: Date,
                reportingDays: Int
            ) -> ExportMetric<ExportWindowedScalar> {
                value.map {
                    .available(ExportWindowedScalar(
                        value: $0,
                        unit: "%",
                        window: exportInterval(DateInterval(start: start, end: end)),
                        coverage: ExportCoverage(
                            sampledDays: summary.dailyValues.filter {
                                $0.day >= start && $0.day < end
                            }.count,
                            reportingDays: reportingDays
                        )
                    ))
                } ?? .insufficientData
            }
            return .available(ExportBodyFatContext(
                latest: ExportTimestampedScalar(
                    value: summary.latest.percentage,
                    unit: "%",
                    recordedAt: timestamp(summary.latest.date)
                ),
                sevenDayAverage: average(
                    summary.sevenDayAverage,
                    start: bodyFatSevenStart,
                    end: today,
                    reportingDays: 7
                ),
                current28DayAverage: average(
                    summary.current28DayAverage,
                    start: bodyFatCurrent28Start,
                    end: today,
                    reportingDays: 28
                ),
                previous28DayAverage: average(
                    summary.previous28DayAverage,
                    start: bodyFatPrevious28Start,
                    end: bodyFatCurrent28Start,
                    reportingDays: 28
                ),
                trend: summary.trendPercentagePoints.map {
                    .available(ExportTrend(
                        change: $0,
                        unit: "percentage_points",
                        comparison: "previous_28d"
                    ))
                } ?? .insufficientData
            ))
        } ?? .noDataOrAccess

        let waistSummary = WaistSummary.calculate(
            measurements: inputs.waist.filter { $0.date < window.cutoff },
            asOf: window.cutoff,
            calendar: calendar
        )
        let waist: ExportMetric<ExportWaistContext> = waistSummary.map { summary in
            .available(ExportWaistContext(
                latest: ExportTimestampedScalar(
                    value: summary.latest.centimetres,
                    unit: "cm",
                    recordedAt: timestamp(summary.latest.date)
                ),
                comparison: summary.comparison.map {
                    .available(ExportTimestampedScalar(
                        value: $0.centimetres,
                        unit: "cm",
                        recordedAt: timestamp($0.date)
                    ))
                } ?? .insufficientData,
                fourWeekChange: summary.fourWeekChangeCentimetres.map {
                    .available(ExportTrend(change: $0, unit: "cm", comparison: "approximately_4w"))
                } ?? .insufficientData
            ))
        } ?? .noDataOrAccess

        let vo2Summary = VO2MaxSummary.calculate(
            measurements: inputs.vo2Max.filter { $0.date < window.cutoff },
            asOf: window.cutoff,
            calendar: calendar
        )
        let vo2Max: ExportMetric<ExportVO2Context> = vo2Summary.map { summary in
            func result(
                _ value: VO2MaxWindowSummary,
                start: Date
            ) -> ExportVO2Window {
                ExportVO2Window(
                    window: exportInterval(DateInterval(start: start, end: window.cutoff)),
                    average: value.average.map {
                        .available(ExportScalar(value: $0, unit: "mL/kg/min"))
                    } ?? .insufficientData,
                    sampledDays: value.sampledDayCount
                )
            }
            return .available(ExportVO2Context(
                latest: ExportTimestampedScalar(
                    value: summary.latest.millilitresPerKilogramMinute,
                    unit: "mL/kg/min",
                    recordedAt: timestamp(summary.latest.date)
                ),
                fourWeek: result(
                    summary.fourWeek,
                    start: vo2WindowStarts.fourWeek
                ),
                threeMonth: result(
                    summary.threeMonth,
                    start: vo2WindowStarts.threeMonth
                ),
                sixMonth: result(
                    summary.sixMonth,
                    start: vo2WindowStarts.sixMonth
                )
            ))
        } ?? .noDataOrAccess

        let glucoseSummary = GlucoseSummary.aggregate(inputs.contextGlucose)
        let glucose: ExportMetric<ExportGlucoseContext> = glucoseSummary.map {
            .available(ExportGlucoseContext(
                statistics: ExportStatistics(
                    average: $0.averageMillimolesPerLiter,
                    minimum: $0.minimumMillimolesPerLiter,
                    maximum: $0.maximumMillimolesPerLiter,
                    unit: "mmol/L",
                    sourceNames: Array(Set($0.dailyValues.flatMap(\.sourceNames))).sorted()
                ),
                coverage: ExportCoverage(
                    sampledDays: $0.validDayCount,
                    reportingDays: $0.reportingDayCount
                )
            ))
        } ?? .noDataOrAccess

        let oxygenSummary = BloodOxygenSummary.calculate(
            measurements: inputs.bloodOxygen.filter { $0.date < window.cutoff },
            period: contextPeriod,
            asOf: window.cutoff,
            calendar: calendar
        )
        let bloodOxygen: ExportMetric<ExportBloodOxygenContext> = oxygenSummary.map { summary in
            .available(ExportBloodOxygenContext(
                latest: ExportTimestampedScalar(
                    value: summary.latest.percentage,
                    unit: "%",
                    recordedAt: timestamp(summary.latest.date)
                ),
                typical: summary.typicalPercentage.map {
                    .available(ExportScalar(value: $0, unit: "%"))
                } ?? .noDataOrAccess,
                dailyMedianRange: summary.minimumDailyMedian.flatMap { minimum in
                    summary.maximumDailyMedian.map { maximum in
                        .available(ExportRange(minimum: minimum, maximum: maximum, unit: "%"))
                    }
                } ?? .noDataOrAccess,
                coverage: ExportCoverage(
                    sampledDays: summary.validDayCount,
                    reportingDays: summary.reportingDayCount
                )
            ))
        } ?? .noDataOrAccess

        let bloodPressureSummary = BloodPressureSummary.calculate(
            readings: inputs.bloodPressure.filter { $0.date < window.cutoff },
            period: contextPeriod,
            asOf: window.cutoff,
            calendar: calendar
        )
        let bloodPressure: ExportMetric<ExportBloodPressureContext> = bloodPressureSummary.map {
            summary in
            func slot(
                _ value: BloodPressurePeriodSlotSummary?
            ) -> ExportMetric<ExportBloodPressureSlotContext> {
                value.map {
                    .available(ExportBloodPressureSlotContext(
                        averageSystolic: $0.averageSystolic,
                        averageDiastolic: $0.averageDiastolic,
                        unit: "mmHg",
                        coverage: ExportCoverage(
                            sampledDays: $0.sampledDayCount,
                            reportingDays: $0.reportingDayCount
                        ),
                        readingCount: $0.readingCount
                    ))
                } ?? .noDataOrAccess
            }
            return .available(ExportBloodPressureContext(
                latest: DailyBloodPressureReading(
                    systolic: summary.latest.systolicMillimetresOfMercury,
                    diastolic: summary.latest.diastolicMillimetresOfMercury,
                    unit: "mmHg",
                    recordedAt: timestamp(summary.latest.date),
                    slot: BloodPressureTimeSlot.classify(
                        summary.latest.date,
                        calendar: calendar
                    )?.rawValue
                ),
                morning: slot(summary.morning),
                evening: slot(summary.evening)
            ))
        } ?? .noDataOrAccess

        let stepsSummary = StepSummary.aggregate(inputs.contextSteps)
        let steps: ExportMetric<ExportStepContext> = stepsSummary.map {
            .available(ExportStepContext(
                total: ExportScalar(value: $0.totalSteps, unit: "count"),
                dailyAverage: ExportScalar(value: $0.averageDailySteps, unit: "count/day"),
                coverage: ExportCoverage(
                    sampledDays: $0.daysWithVisibleData,
                    reportingDays: $0.reportingDayCount
                )
            ))
        } ?? .noDataOrAccess

        func heart(
            current: [DailyHeartMetricValue],
            previous: [DailyHeartMetricValue],
            unit: String
        ) -> ExportMetric<ExportHeartContext> {
            guard let summary = HeartMetricTrendSummary.calculate(
                currentValues: current,
                previousValues: previous
            ) else { return .noDataOrAccess }
            let previousWindow = previousPeriod?.interval ?? contextPeriod.interval
            return .available(ExportHeartContext(
                currentAverage: ExportWindowedScalar(
                    value: summary.current.average,
                    unit: unit,
                    window: exportInterval(contextPeriod.interval),
                    coverage: ExportCoverage(
                        sampledDays: summary.current.validDayCount,
                        reportingDays: contextPeriod.completedDays.count
                    )
                ),
                previousAverage: summary.previous.map {
                    .available(ExportWindowedScalar(
                        value: $0.average,
                        unit: unit,
                        window: exportInterval(previousWindow),
                        coverage: ExportCoverage(
                            sampledDays: $0.validDayCount,
                            reportingDays: contextPeriod.completedDays.count
                        )
                    ))
                } ?? .noDataOrAccess,
                trend: summary.trend.map {
                    .available(ExportTrend(
                        change: $0,
                        unit: unit,
                        comparison: "previous_equivalent_period"
                    ))
                } ?? .insufficientData
            ))
        }

        let watch = WatchCoverageSummary.calculate(
            appleWatchSampleDates: inputs.contextWatchSampleDates,
            period: contextPeriod
        )
        let sleep = SleepSummary.calculate(
            asleepIntervals: inputs.contextAsleepIntervals,
            period: contextPeriod,
            calendar: calendar
        )
        let workouts = inputs.contextWorkouts.isEmpty
            ? ExportMetric<ExportWorkoutContext>.noDataOrAccess
            : .available(ExportWorkoutContext(
                count: inputs.contextWorkouts.count,
                totalDurationSeconds: inputs.contextWorkouts.reduce(0) { $0 + $1.duration }
            ))
        let medicationSummary = MedicationSummary.aggregate(inputs.contextMedicationDoses)

        return DailyAppContext(
            policyID: "last_7_completed_days_v1",
            window: exportInterval(contextPeriod.interval),
            weight: weight,
            bodyFat: bodyFat,
            waist: waist,
            glucose: glucose,
            vo2Max: vo2Max,
            bloodOxygen: bloodOxygen,
            bloodPressure: bloodPressure,
            steps: steps,
            restingHeartRate: heart(
                current: inputs.contextRestingHeartRate,
                previous: inputs.previousRestingHeartRate,
                unit: "bpm"
            ),
            hrv: heart(current: inputs.contextHRV, previous: inputs.previousHRV, unit: "ms"),
            watchCoverage: watch.map {
                .available(ExportCoverage(
                    sampledDays: $0.daysWithWatchData,
                    reportingDays: $0.reportingDayCount
                ))
            } ?? .noDataOrAccess,
            sleep: sleep.map {
                .available(ExportSleepContext(
                    averageDurationSeconds: $0.averageDuration,
                    coverage: ExportCoverage(
                        sampledDays: $0.nights.count,
                        reportingDays: contextPeriod.completedDays.count
                    )
                ))
            } ?? .noDataOrAccess,
            activeEnergy: scalar(inputs.contextActiveEnergyKilocalories, unit: "kcal"),
            exercise: scalar(inputs.contextExerciseMinutes, unit: "min"),
            workouts: workouts,
            medications: !inputs.supportsMedicationData
                ? .unsupported
                : medicationSummary.map {
                    .available(ExportMedicationContext(
                        takenEventCount: $0.allDoses.count,
                        medicationCount: $0.groups.count,
                        medications: $0.groups.map { group in
                            let latest = group.latestDose
                            return ExportMedicationGroup(
                                medication: group.medicationName,
                                takenEventCount: group.count,
                                latest: DailyMedicationData(
                                    medication: latest.medicationName,
                                    recordedAt: timestamp(latest.date),
                                    quantity: latest.quantity,
                                    unit: latest.unitLabel
                                )
                            )
                        }
                    ))
                } ?? .noDataOrAccess,
            nutrition: nutrition
        )
    }
}

enum DailyHealthExportSerializer {
    static func encode(_ envelope: DailyHealthExportEnvelope) throws -> Data {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(envelope)
    }
}

private enum ExportDateText {
    static func date(_ date: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    static func timestamp(_ date: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssXXXXX"
        return formatter.string(from: date)
    }

    static func interval(_ interval: DateInterval, calendar: Calendar) -> ExportInterval {
        ExportInterval(
            start: timestamp(interval.start, calendar: calendar),
            end: timestamp(interval.end, calendar: calendar)
        )
    }
}

private extension DateInterval {
    func containsHalfOpen(_ date: Date) -> Bool {
        date >= start && date < end
    }
}
