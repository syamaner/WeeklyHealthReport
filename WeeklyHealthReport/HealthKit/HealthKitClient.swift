import Foundation
import HealthKit

enum HealthStoreProvider {
    // HealthKit authorization UI and queries share one long-lived store. Keeping
    // its identity stable also lets the per-object medication sheet reopen.
    static let shared = HKHealthStore()
}

enum HealthDataError: LocalizedError, Equatable {
    case unavailable
    case missingStepType
    case missingBodyMassType
    case missingBodyFatType
    case missingType(String)

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "Health data is unavailable on this device."
        case .missingStepType:
            return "The HealthKit step-count type is unavailable."
        case .missingBodyMassType:
            return "The HealthKit body-mass type is unavailable."
        case .missingBodyFatType:
            return "The HealthKit body-fat type is unavailable."
        case .missingType(let name):
            return "The HealthKit \(name) type is unavailable."
        }
    }
}

final class HealthKitClient: HealthDataProviding, DailyHealthExportDataProviding {
    private let store: HKHealthStore

    init(store: HKHealthStore = HealthStoreProvider.shared) {
        self.store = store
    }

    var isHealthDataAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    var supportsMedicationData: Bool {
        if #available(iOS 26.0, *) { return true }
        return false
    }

    func requestReadAuthorization() async throws {
        guard isHealthDataAvailable else {
            throw HealthDataError.unavailable
        }
        guard let stepType = HKObjectType.quantityType(forIdentifier: .stepCount) else {
            throw HealthDataError.missingStepType
        }
        guard let bodyMassType = HKObjectType.quantityType(forIdentifier: .bodyMass) else {
            throw HealthDataError.missingBodyMassType
        }
        guard let bodyFatType = HKObjectType.quantityType(forIdentifier: .bodyFatPercentage) else {
            throw HealthDataError.missingBodyFatType
        }
        guard let waistType = HKObjectType.quantityType(forIdentifier: .waistCircumference),
              let glucoseType = HKObjectType.quantityType(forIdentifier: .bloodGlucose)
        else {
            throw HealthDataError.missingType("waist or blood-glucose")
        }
        guard let heartRateType = HKObjectType.quantityType(forIdentifier: .heartRate),
              let restingHeartRateType = HKObjectType.quantityType(forIdentifier: .restingHeartRate),
              let hrvType = HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN),
              let vo2MaxType = HKObjectType.quantityType(forIdentifier: .vo2Max),
              let oxygenSaturationType = HKObjectType.quantityType(forIdentifier: .oxygenSaturation),
              let bloodPressureSystolicType = HKObjectType.quantityType(
                forIdentifier: .bloodPressureSystolic
              ),
              let bloodPressureDiastolicType = HKObjectType.quantityType(
                forIdentifier: .bloodPressureDiastolic
              ),
              let exerciseType = HKObjectType.quantityType(forIdentifier: .appleExerciseTime),
              let activeEnergyType = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned),
              let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis)
        else {
            throw HealthDataError.missingType("required metric")
        }
        let workoutType = HKObjectType.workoutType()

        // A successful request means the authorization sheet completed. HealthKit
        // intentionally does not reveal whether read access was granted or denied.
        try await store.requestAuthorization(
            toShare: [],
            read: [
                stepType, bodyMassType, bodyFatType, waistType, glucoseType,
                heartRateType, restingHeartRateType, hrvType, vo2MaxType,
                oxygenSaturationType, bloodPressureSystolicType,
                bloodPressureDiastolicType, exerciseType, activeEnergyType,
                workoutType, sleepType
            ]
        )
    }

    func fetchDailySteps(for period: ReportPeriod) async throws -> [DailyStepTotal] {
        guard isHealthDataAvailable else {
            throw HealthDataError.unavailable
        }
        guard let stepType = HKObjectType.quantityType(forIdentifier: .stepCount) else {
            throw HealthDataError.missingStepType
        }
        guard !period.completedDays.isEmpty else { return [] }

        // Do not manually sum source samples. HKStatistics merges sources before
        // applying cumulativeSum, matching HealthKit's resolved step semantics.
        let datePredicate = HKQuery.predicateForSamples(
            withStart: period.interval.start,
            end: period.interval.end,
            options: []
        )
        let samplePredicate = HKSamplePredicate.quantitySample(
            type: stepType,
            predicate: datePredicate
        )
        let descriptor = HKStatisticsCollectionQueryDescriptor(
            predicate: samplePredicate,
            options: .cumulativeSum,
            anchorDate: period.interval.start,
            intervalComponents: DateComponents(day: 1)
        )

        let collection = try await descriptor.result(for: store)
        var statisticsByStart: [Date: HKStatistics] = [:]
        collection.enumerateStatistics(
            from: period.interval.start,
            to: period.interval.end
        ) { statistics, _ in
            guard statistics.startDate >= period.interval.start,
                  statistics.startDate < period.interval.end else { return }
            statisticsByStart[statistics.startDate] = statistics
        }

        let countUnit = HKUnit.count()
        return period.completedDays.map { day in
            let statistics = statisticsByStart[day.start]
            let steps = statistics?.sumQuantity()?.doubleValue(for: countUnit)
            let sources = statistics?.sources?.map(\.name).sorted() ?? []
            return DailyStepTotal(day: day, steps: steps, sourceNames: sources)
        }
    }

    func fetchWeightMeasurements(asOf date: Date) async throws -> [WeightMeasurement] {
        try await fetchWeightMeasurements(
            asOf: date,
            calendar: .autoupdatingCurrent
        )
    }

    private func fetchWeightMeasurements(
        asOf date: Date,
        calendar: Calendar
    ) async throws -> [WeightMeasurement] {
        guard isHealthDataAvailable else {
            throw HealthDataError.unavailable
        }
        guard let bodyMassType = HKObjectType.quantityType(forIdentifier: .bodyMass) else {
            throw HealthDataError.missingBodyMassType
        }
        guard let lookbackStart = calendar.date(
            byAdding: .day,
            value: -30,
            to: date
        ) else {
            return []
        }

        let datePredicate = HKQuery.predicateForSamples(
            withStart: lookbackStart,
            end: date,
            options: []
        )
        let samplePredicate = HKSamplePredicate.quantitySample(
            type: bodyMassType,
            predicate: datePredicate
        )
        let descriptor = HKSampleQueryDescriptor(
            predicates: [samplePredicate],
            sortDescriptors: [SortDescriptor(\.endDate, order: .forward)]
        )

        let samples = try await descriptor.result(for: store)
        let kilograms = HKUnit.gramUnit(with: .kilo)
        let measurements = samples.map { sample in
            WeightMeasurement(
                id: sample.uuid,
                date: sample.endDate,
                kilograms: sample.quantity.doubleValue(for: kilograms)
            )
        }
        return measurements
    }

    func fetchBodyFatMeasurements(asOf date: Date) async throws -> [BodyFatMeasurement] {
        try await fetchBodyFatMeasurements(
            asOf: date,
            calendar: .autoupdatingCurrent
        )
    }

    private func fetchBodyFatMeasurements(
        asOf date: Date,
        calendar: Calendar
    ) async throws -> [BodyFatMeasurement] {
        guard isHealthDataAvailable else {
            throw HealthDataError.unavailable
        }
        guard let bodyFatType = HKObjectType.quantityType(forIdentifier: .bodyFatPercentage) else {
            throw HealthDataError.missingBodyFatType
        }
        guard let lookbackStart = calendar.date(
            byAdding: .day,
            value: -60,
            to: date
        ) else {
            return []
        }

        let datePredicate = HKQuery.predicateForSamples(
            withStart: lookbackStart,
            end: date,
            options: []
        )
        let samplePredicate = HKSamplePredicate.quantitySample(
            type: bodyFatType,
            predicate: datePredicate
        )
        let descriptor = HKSampleQueryDescriptor(
            predicates: [samplePredicate],
            sortDescriptors: [SortDescriptor(\.endDate, order: .forward)]
        )

        let samples = try await descriptor.result(for: store)
        return samples.map { sample in
            let fraction = sample.quantity.doubleValue(for: .percent())
            return BodyFatMeasurement(
                date: sample.endDate,
                percentage: BodyFatMeasurement.percentagePoints(
                    fromHealthKitFraction: fraction
                )
            )
        }
    }

    func fetchWaistMeasurements(asOf date: Date) async throws -> [WaistMeasurement] {
        try await fetchWaistMeasurements(
            asOf: date,
            calendar: .autoupdatingCurrent
        )
    }

    private func fetchWaistMeasurements(
        asOf date: Date,
        calendar: Calendar
    ) async throws -> [WaistMeasurement] {
        guard isHealthDataAvailable else { throw HealthDataError.unavailable }
        guard let type = HKObjectType.quantityType(forIdentifier: .waistCircumference) else {
            throw HealthDataError.missingType("waist-circumference")
        }
        guard let lookbackStart = calendar.date(
            byAdding: .day,
            value: -56,
            to: date
        ) else {
            return []
        }
        let datePredicate = HKQuery.predicateForSamples(
            withStart: lookbackStart,
            end: date,
            options: .strictStartDate
        )
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: type, predicate: datePredicate)],
            sortDescriptors: [SortDescriptor(\.startDate, order: .forward)]
        )
        let samples = try await descriptor.result(for: store)
        let centimetres = HKUnit.meterUnit(with: .centi)
        return samples.map {
            WaistMeasurement(
                date: $0.startDate,
                centimetres: $0.quantity.doubleValue(for: centimetres)
            )
        }
    }

    func fetchVO2MaxMeasurements(asOf date: Date) async throws -> [VO2MaxMeasurement] {
        try await fetchVO2MaxMeasurements(
            asOf: date,
            calendar: .autoupdatingCurrent
        )
    }

    private func fetchVO2MaxMeasurements(
        asOf date: Date,
        calendar: Calendar
    ) async throws -> [VO2MaxMeasurement] {
        guard isHealthDataAvailable else { throw HealthDataError.unavailable }
        guard let type = HKObjectType.quantityType(forIdentifier: .vo2Max) else {
            throw HealthDataError.missingType("VO2-max")
        }
        guard let lookbackStart = HealthReportingPolicy.vo2MaxWindowStarts(
            asOf: date,
            calendar: calendar
        )?.sixMonth else {
            return []
        }
        let datePredicate = HKQuery.predicateForSamples(
            withStart: lookbackStart,
            end: date,
            options: .strictStartDate
        )
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: type, predicate: datePredicate)],
            sortDescriptors: [SortDescriptor(\.startDate, order: .forward)]
        )
        let samples = try await descriptor.result(for: store)
        let unit = HKUnit.literUnit(with: .milli)
            .unitDivided(by: .gramUnit(with: .kilo))
            .unitDivided(by: .minute())
        return samples.map {
            VO2MaxMeasurement(
                date: $0.startDate,
                millilitresPerKilogramMinute: $0.quantity.doubleValue(for: unit),
                sourceName: $0.sourceRevision.source.name
            )
        }
    }

    func fetchOxygenSaturationMeasurements(
        for period: ReportPeriod,
        asOf date: Date
    ) async throws -> [OxygenSaturationMeasurement] {
        try await fetchOxygenSaturationMeasurements(
            for: period,
            asOf: date,
            calendar: .autoupdatingCurrent
        )
    }

    private func fetchOxygenSaturationMeasurements(
        for period: ReportPeriod,
        asOf date: Date,
        calendar: Calendar
    ) async throws -> [OxygenSaturationMeasurement] {
        guard isHealthDataAvailable else { throw HealthDataError.unavailable }
        guard let type = HKObjectType.quantityType(forIdentifier: .oxygenSaturation) else {
            throw HealthDataError.missingType("oxygen-saturation")
        }
        guard let queryStart = HealthReportingPolicy.oxygenSaturationQueryStart(
            for: period,
            asOf: date,
            calendar: calendar
        ) else { return [] }
        let datePredicate = HKQuery.predicateForSamples(
            withStart: queryStart,
            end: date,
            options: .strictStartDate
        )
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: type, predicate: datePredicate)],
            sortDescriptors: [SortDescriptor(\.startDate, order: .forward)]
        )
        let samples = try await descriptor.result(for: store)
        return samples.map {
            OxygenSaturationMeasurement(
                date: $0.startDate,
                percentage: OxygenSaturationMeasurement.percentagePoints(
                    fromHealthKitFraction: $0.quantity.doubleValue(for: .percent())
                ),
                sourceName: $0.sourceRevision.source.name
            )
        }
    }

    func fetchBloodPressureReadings(
        for period: ReportPeriod,
        asOf date: Date
    ) async throws -> [BloodPressureReading] {
        try await fetchBloodPressureReadings(
            for: period,
            asOf: date,
            calendar: .autoupdatingCurrent
        )
    }

    private func fetchBloodPressureReadings(
        for period: ReportPeriod,
        asOf date: Date,
        calendar: Calendar
    ) async throws -> [BloodPressureReading] {
        guard isHealthDataAvailable else { throw HealthDataError.unavailable }
        guard let correlationType = HKObjectType.correlationType(forIdentifier: .bloodPressure),
              let systolicType = HKObjectType.quantityType(forIdentifier: .bloodPressureSystolic),
              let diastolicType = HKObjectType.quantityType(forIdentifier: .bloodPressureDiastolic)
        else {
            throw HealthDataError.missingType("blood-pressure")
        }
        guard let queryStart = HealthReportingPolicy.bloodPressureQueryStart(
            for: period,
            asOf: date,
            calendar: calendar
        ) else { return [] }
        let datePredicate = HKQuery.predicateForSamples(
            withStart: queryStart,
            end: date,
            options: .strictStartDate
        )
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.correlation(type: correlationType, predicate: datePredicate)],
            sortDescriptors: [SortDescriptor(\.startDate, order: .forward)]
        )
        let correlations = try await descriptor.result(for: store)
        let millimetresOfMercury = HKUnit.millimeterOfMercury()

        return correlations.compactMap { correlation in
            let systolicSamples = correlation.objects(for: systolicType)
                .compactMap { $0 as? HKQuantitySample }
            let diastolicSamples = correlation.objects(for: diastolicType)
                .compactMap { $0 as? HKQuantitySample }

            // HealthKit can hide one component when only one quantity type is
            // readable. Never combine that partial correlation with a sample
            // from another reading.
            guard systolicSamples.count == 1, diastolicSamples.count == 1,
                  let systolic = systolicSamples.first,
                  let diastolic = diastolicSamples.first
            else { return nil }

            return BloodPressureReading(
                id: correlation.uuid,
                date: correlation.startDate,
                systolicMillimetresOfMercury: systolic.quantity.doubleValue(
                    for: millimetresOfMercury
                ),
                diastolicMillimetresOfMercury: diastolic.quantity.doubleValue(
                    for: millimetresOfMercury
                ),
                sourceName: correlation.sourceRevision.source.name
            )
        }
    }

    func fetchDailyBloodGlucose(for period: ReportPeriod) async throws -> [DailyGlucoseValue] {
        guard isHealthDataAvailable else { throw HealthDataError.unavailable }
        guard let type = HKObjectType.quantityType(forIdentifier: .bloodGlucose) else {
            throw HealthDataError.missingType("blood-glucose")
        }
        guard !period.completedDays.isEmpty else { return [] }

        let datePredicate = HKQuery.predicateForSamples(
            withStart: period.interval.start,
            end: period.interval.end,
            options: []
        )
        let descriptor = HKStatisticsCollectionQueryDescriptor(
            predicate: .quantitySample(type: type, predicate: datePredicate),
            options: [.discreteAverage, .discreteMin, .discreteMax],
            anchorDate: period.interval.start,
            intervalComponents: DateComponents(day: 1)
        )
        let collection = try await descriptor.result(for: store)
        var statisticsByStart: [Date: HKStatistics] = [:]
        collection.enumerateStatistics(from: period.interval.start, to: period.interval.end) {
            statistics, _ in
            guard statistics.startDate >= period.interval.start,
                  statistics.startDate < period.interval.end else { return }
            statisticsByStart[statistics.startDate] = statistics
        }

        // HealthKit may store glucose as mg/dL or mmol/L. Converting with the
        // documented glucose molar mass normalises every source to mmol/L.
        let millimolesPerLiter = HKUnit
            .moleUnit(with: .milli, molarMass: HKUnitMolarMassBloodGlucose)
            .unitDivided(by: .liter())
        return period.completedDays.map { day in
            let statistics = statisticsByStart[day.start]
            return DailyGlucoseValue(
                day: day,
                averageMillimolesPerLiter: statistics?.averageQuantity()?.doubleValue(
                    for: millimolesPerLiter
                ),
                minimumMillimolesPerLiter: statistics?.minimumQuantity()?.doubleValue(
                    for: millimolesPerLiter
                ),
                maximumMillimolesPerLiter: statistics?.maximumQuantity()?.doubleValue(
                    for: millimolesPerLiter
                ),
                sourceNames: statistics?.sources?.map(\.name).sorted() ?? []
            )
        }
    }

    func fetchDailyRestingHeartRate(for period: ReportPeriod) async throws -> [DailyHeartMetricValue] {
        guard let type = HKObjectType.quantityType(forIdentifier: .restingHeartRate) else {
            throw HealthDataError.missingType("resting-heart-rate")
        }
        let unit = HKUnit.count().unitDivided(by: .minute())
        return try await fetchDailyDiscreteAverage(type: type, unit: unit, period: period)
    }

    func fetchDailyHRV(for period: ReportPeriod) async throws -> [DailyHeartMetricValue] {
        guard let type = HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN) else {
            throw HealthDataError.missingType("HRV")
        }
        return try await fetchDailyDiscreteAverage(
            type: type,
            unit: .secondUnit(with: .milli),
            period: period
        )
    }

    func fetchAppleWatchHeartRateSampleDates(for period: ReportPeriod) async throws -> [Date] {
        try await fetchAppleWatchHeartRateSampleDates(in: period.interval)
    }

    private func fetchAppleWatchHeartRateSampleDates(
        in interval: DateInterval
    ) async throws -> [Date] {
        guard isHealthDataAvailable else { throw HealthDataError.unavailable }
        guard let type = HKObjectType.quantityType(forIdentifier: .heartRate) else {
            throw HealthDataError.missingType("heart-rate")
        }
        let datePredicate = HKQuery.predicateForSamples(
            withStart: interval.start,
            end: interval.end,
            options: []
        )
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: type, predicate: datePredicate)],
            sortDescriptors: [SortDescriptor(\.startDate, order: .forward)]
        )
        let samples = try await descriptor.result(for: store)

        // Heart-rate samples are an evidence marker for Watch presence, not a
        // continuous wear-time measurement. Intermittent sampling cannot support
        // an accurate hours-worn claim.
        return samples.compactMap { sample in
            let productType = sample.sourceRevision.productType ?? ""
            let deviceModel = sample.device?.model ?? ""
            let isAppleWatch = productType.hasPrefix("Watch")
                || deviceModel.localizedCaseInsensitiveContains("watch")
            return isAppleWatch ? sample.startDate : nil
        }
    }

    func fetchExerciseMinutes(for period: ReportPeriod) async throws -> Double? {
        try await fetchExerciseMinutes(in: period.interval)
    }

    private func fetchExerciseMinutes(in interval: DateInterval) async throws -> Double? {
        guard let type = HKObjectType.quantityType(forIdentifier: .appleExerciseTime) else {
            throw HealthDataError.missingType("Apple Exercise Time")
        }
        return try await fetchCumulativeTotal(type: type, unit: .minute(), interval: interval)
    }

    func fetchActiveEnergyKilocalories(for period: ReportPeriod) async throws -> Double? {
        try await fetchActiveEnergyKilocalories(in: period.interval)
    }

    private func fetchActiveEnergyKilocalories(in interval: DateInterval) async throws -> Double? {
        guard let type = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned) else {
            throw HealthDataError.missingType("active-energy")
        }
        return try await fetchCumulativeTotal(
            type: type,
            unit: .kilocalorie(),
            interval: interval
        )
    }

    func fetchWorkouts(for period: ReportPeriod) async throws -> [WorkoutRecord] {
        try await fetchWorkouts(in: period.interval)
    }

    private func fetchWorkouts(in interval: DateInterval) async throws -> [WorkoutRecord] {
        guard isHealthDataAvailable else { throw HealthDataError.unavailable }
        let datePredicate = HKQuery.predicateForSamples(
            withStart: interval.start,
            end: interval.end,
            options: .strictStartDate
        )
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.workout(datePredicate)],
            sortDescriptors: [SortDescriptor(\.startDate, order: .forward)]
        )
        let workouts = try await descriptor.result(for: store)
        return workouts.map {
            WorkoutRecord(
                id: $0.uuid,
                startDate: $0.startDate,
                duration: $0.duration,
                activityName: Self.workoutName($0.workoutActivityType)
            )
        }
    }

    func fetchAsleepIntervals(
        for period: ReportPeriod,
        calendar: Calendar
    ) async throws -> [AsleepInterval] {
        guard isHealthDataAvailable else { throw HealthDataError.unavailable }
        guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else {
            throw HealthDataError.missingType("sleep-analysis")
        }
        guard let queryInterval = SleepSummary.queryInterval(for: period, calendar: calendar) else {
            return []
        }
        let datePredicate = HKQuery.predicateForSamples(
            withStart: queryInterval.start,
            end: queryInterval.end,
            options: []
        )
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.categorySample(type: sleepType, predicate: datePredicate)],
            sortDescriptors: [SortDescriptor(\.startDate, order: .forward)]
        )
        let samples = try await descriptor.result(for: store)
        // Awake and inBed samples are intentionally excluded. The pure sleep
        // aggregator clips and unions all included intervals across sources.
        return samples.compactMap { sample in
            guard Self.sleepStage(for: sample.value).countsAsAsleep else { return nil }
            return AsleepInterval(start: sample.startDate, end: sample.endDate)
        }
    }

    func fetchTakenMedicationDoses(for period: ReportPeriod) async throws -> [MedicationDoseRecord] {
        guard isHealthDataAvailable else { throw HealthDataError.unavailable }
        guard !period.completedDays.isEmpty else { return [] }
        return try await fetchTakenMedicationDoses(in: period.interval)
    }

    func fetchDailyHealthExportInputs(
        for window: DailyExportWindow
    ) async throws -> DailyHealthExportInputs {
        guard isHealthDataAvailable else { throw HealthDataError.unavailable }
        guard let previous = window.context.precedingEquivalent(
            calendar: window.calendar
        ) else {
            throw DailyHealthExportError.invalidWindow
        }

        let weight = try await fetchWeightMeasurements(
            asOf: window.cutoff,
            calendar: window.calendar
        )
        let bodyFat = try await fetchBodyFatMeasurements(
            asOf: window.cutoff,
            calendar: window.calendar
        )
        let waist = try await fetchWaistMeasurements(
            asOf: window.cutoff,
            calendar: window.calendar
        )
        let vo2Max = try await fetchVO2MaxMeasurements(
            asOf: window.cutoff,
            calendar: window.calendar
        )
        let bloodOxygen = try await fetchOxygenSaturationMeasurements(
            for: window.context,
            asOf: window.cutoff,
            calendar: window.calendar
        )
        let bloodPressure = try await fetchBloodPressureReadings(
            for: window.context,
            asOf: window.cutoff,
            calendar: window.calendar
        )

        var todaySteps = DailyStepTotal(day: window.day, steps: nil, sourceNames: [])
        var todayGlucose = DailyGlucoseValue(
            day: window.day,
            averageMillimolesPerLiter: nil,
            minimumMillimolesPerLiter: nil,
            maximumMillimolesPerLiter: nil,
            sourceNames: []
        )
        var hourlyGlucose: [DailyGlucoseValue] = []
        var todayRestingHeartRate = DailyHeartMetricValue(
            day: window.day,
            value: nil,
            sourceNames: []
        )
        var todayHRV = DailyHeartMetricValue(day: window.day, value: nil, sourceNames: [])
        var todayWatchSamples: [Date] = []
        var todayActiveEnergy: Double?
        var todayExercise: Double?
        var todayWorkouts: [WorkoutRecord] = []
        if window.day.duration > 0 {
            todaySteps = try await fetchStepTotal(in: window.day)
            todayGlucose = try await fetchGlucoseStatistics(in: [window.day]).first
                ?? todayGlucose
            hourlyGlucose = try await fetchGlucoseStatistics(in: window.glucoseHours)
            todayRestingHeartRate = try await fetchDiscreteAverage(
                identifier: .restingHeartRate,
                name: "resting-heart-rate",
                unit: HKUnit.count().unitDivided(by: .minute()),
                interval: window.day
            )
            todayHRV = try await fetchDiscreteAverage(
                identifier: .heartRateVariabilitySDNN,
                name: "HRV",
                unit: .secondUnit(with: .milli),
                interval: window.day
            )
            todayWatchSamples = try await fetchAppleWatchHeartRateSampleDates(in: window.day)
            todayActiveEnergy = try await fetchActiveEnergyKilocalories(in: window.day)
            todayExercise = try await fetchExerciseMinutes(in: window.day)
            todayWorkouts = try await fetchWorkouts(in: window.day)
        }
        let todaySleep = try await fetchAsleepIntervals(in: window.sleep)
        let todayMedications = supportsMedicationData && window.day.duration > 0
            ? try await fetchTakenMedicationDoses(in: window.day)
            : []

        let contextSteps = try await fetchDailySteps(for: window.context)
        let contextGlucose = try await fetchDailyBloodGlucose(for: window.context)
        let contextRHR = try await fetchDailyRestingHeartRate(for: window.context)
        let previousRHR = try await fetchDailyRestingHeartRate(for: previous)
        let contextHRV = try await fetchDailyHRV(for: window.context)
        let previousHRV = try await fetchDailyHRV(for: previous)
        let contextWatch = try await fetchAppleWatchHeartRateSampleDates(for: window.context)
        let contextActiveEnergy = try await fetchActiveEnergyKilocalories(for: window.context)
        let contextExercise = try await fetchExerciseMinutes(for: window.context)
        let contextWorkouts = try await fetchWorkouts(for: window.context)
        let contextSleep = try await fetchAsleepIntervals(
            for: window.context,
            calendar: window.calendar
        )
        let contextMedications = supportsMedicationData
            ? try await fetchTakenMedicationDoses(for: window.context)
            : []

        return DailyHealthExportInputs(
            weight: weight,
            bodyFat: bodyFat,
            waist: waist,
            vo2Max: vo2Max,
            bloodOxygen: bloodOxygen,
            bloodPressure: bloodPressure,
            todaySteps: todaySteps,
            todayGlucose: todayGlucose,
            hourlyGlucose: hourlyGlucose,
            todayRestingHeartRate: todayRestingHeartRate,
            todayHRV: todayHRV,
            todayWatchSampleDates: todayWatchSamples,
            todayActiveEnergyKilocalories: todayActiveEnergy,
            todayExerciseMinutes: todayExercise,
            todayWorkouts: todayWorkouts,
            todayAsleepIntervals: todaySleep,
            todayMedicationDoses: todayMedications,
            supportsMedicationData: supportsMedicationData,
            contextSteps: contextSteps,
            contextGlucose: contextGlucose,
            contextRestingHeartRate: contextRHR,
            previousRestingHeartRate: previousRHR,
            contextHRV: contextHRV,
            previousHRV: previousHRV,
            contextWatchSampleDates: contextWatch,
            contextActiveEnergyKilocalories: contextActiveEnergy,
            contextExerciseMinutes: contextExercise,
            contextWorkouts: contextWorkouts,
            contextAsleepIntervals: contextSleep,
            contextMedicationDoses: contextMedications
        )
    }

    private func fetchTakenMedicationDoses(
        in interval: DateInterval
    ) async throws -> [MedicationDoseRecord] {
        guard isHealthDataAvailable else { throw HealthDataError.unavailable }
        guard #available(iOS 26.0, *) else { return [] }
        return try await fetchTakenMedicationDosesOnIOS26(in: interval)
    }

    @available(iOS 26.0, *)
    private func fetchTakenMedicationDosesOnIOS26(
        in interval: DateInterval
    ) async throws -> [MedicationDoseRecord] {
        // Medication access is per object. This query returns only the active or
        // archived medication concepts that the person explicitly authorised.
        let medications = try await HKUserAnnotatedMedicationQueryDescriptor()
            .result(for: store)
        var records: [MedicationDoseRecord] = []

        for (index, annotatedMedication) in medications.enumerated() {
            let medication = annotatedMedication.medication
            let medicationPredicate = HKQuery.predicateForMedicationDoseEvent(
                medicationConceptIdentifier: medication.identifier
            )
            let takenPredicate = HKQuery.predicateForMedicationDoseEvent(status: .taken)
            let datePredicate = HKQuery.predicateForSamples(
                withStart: interval.start,
                end: interval.end,
                options: .strictStartDate
            )
            let predicate = NSCompoundPredicate(
                type: .and,
                subpredicates: [medicationPredicate, takenPredicate, datePredicate]
            )
            let samplePredicate = HKSamplePredicate.sample(
                type: .medicationDoseEventType(),
                predicate: predicate
            )
            let descriptor = HKSampleQueryDescriptor(
                predicates: [samplePredicate],
                sortDescriptors: [SortDescriptor(\HKSample.startDate, order: .forward)]
            )
            let samples = try await descriptor.result(for: store)

            // The key is intentionally local to this fetch. HealthKit's opaque
            // concept identifier provides exact matching, including strength,
            // while no identifier or medication data is persisted by the app.
            let medicationKey = "medication-\(index)"
            records.append(contentsOf: samples.compactMap { sample in
                guard let event = sample as? HKMedicationDoseEvent else { return nil }
                let unit = event.unit.unitString == "count" ? "dose" : event.unit.unitString
                return MedicationDoseRecord(
                    id: event.uuid,
                    medicationKey: medicationKey,
                    medicationName: medication.displayText,
                    date: event.startDate,
                    quantity: event.doseQuantity,
                    unitLabel: unit
                )
            })
        }

        return records
    }

    private func fetchDailyDiscreteAverage(
        type: HKQuantityType,
        unit: HKUnit,
        period: ReportPeriod
    ) async throws -> [DailyHeartMetricValue] {
        guard isHealthDataAvailable else { throw HealthDataError.unavailable }
        guard !period.completedDays.isEmpty else { return [] }
        let datePredicate = HKQuery.predicateForSamples(
            withStart: period.interval.start,
            end: period.interval.end,
            options: []
        )
        let descriptor = HKStatisticsCollectionQueryDescriptor(
            predicate: .quantitySample(type: type, predicate: datePredicate),
            options: .discreteAverage,
            anchorDate: period.interval.start,
            intervalComponents: DateComponents(day: 1)
        )
        let collection = try await descriptor.result(for: store)
        var statisticsByStart: [Date: HKStatistics] = [:]
        collection.enumerateStatistics(from: period.interval.start, to: period.interval.end) {
            statistics, _ in
            guard statistics.startDate >= period.interval.start,
                  statistics.startDate < period.interval.end else { return }
            statisticsByStart[statistics.startDate] = statistics
        }
        return period.completedDays.map { day in
            let statistics = statisticsByStart[day.start]
            return DailyHeartMetricValue(
                day: day,
                value: statistics?.averageQuantity()?.doubleValue(for: unit),
                sourceNames: statistics?.sources?.map(\.name).sorted() ?? []
            )
        }
    }

    private func fetchStepTotal(in interval: DateInterval) async throws -> DailyStepTotal {
        guard isHealthDataAvailable else { throw HealthDataError.unavailable }
        guard let type = HKObjectType.quantityType(forIdentifier: .stepCount) else {
            throw HealthDataError.missingStepType
        }
        let predicate = HKQuery.predicateForSamples(
            withStart: interval.start,
            end: interval.end,
            options: []
        )
        let descriptor = HKStatisticsQueryDescriptor(
            predicate: .quantitySample(type: type, predicate: predicate),
            options: .cumulativeSum
        )
        let statistics = try await descriptor.result(for: store)
        return DailyStepTotal(
            day: interval,
            steps: statistics?.sumQuantity()?.doubleValue(for: .count()),
            sourceNames: statistics?.sources?.map(\.name).sorted() ?? []
        )
    }

    private func fetchDiscreteAverage(
        identifier: HKQuantityTypeIdentifier,
        name: String,
        unit: HKUnit,
        interval: DateInterval
    ) async throws -> DailyHeartMetricValue {
        guard isHealthDataAvailable else { throw HealthDataError.unavailable }
        guard let type = HKObjectType.quantityType(forIdentifier: identifier) else {
            throw HealthDataError.missingType(name)
        }
        let datePredicate = HKQuery.predicateForSamples(
            withStart: interval.start,
            end: interval.end,
            options: []
        )
        let descriptor = HKStatisticsQueryDescriptor(
            predicate: .quantitySample(type: type, predicate: datePredicate),
            options: .discreteAverage
        )
        let statistics = try await descriptor.result(for: store)
        return DailyHeartMetricValue(
            day: interval,
            value: statistics?.averageQuantity()?.doubleValue(for: unit),
            sourceNames: statistics?.sources?.map(\.name).sorted() ?? []
        )
    }

    private func fetchGlucoseStatistics(
        in intervals: [DateInterval]
    ) async throws -> [DailyGlucoseValue] {
        guard isHealthDataAvailable else { throw HealthDataError.unavailable }
        guard let type = HKObjectType.quantityType(forIdentifier: .bloodGlucose) else {
            throw HealthDataError.missingType("blood-glucose")
        }
        let unit = HKUnit
            .moleUnit(with: .milli, molarMass: HKUnitMolarMassBloodGlucose)
            .unitDivided(by: .liter())

        var values: [DailyGlucoseValue] = []
        for interval in intervals {
            let predicate = HKQuery.predicateForSamples(
                withStart: interval.start,
                end: interval.end,
                options: []
            )
            let descriptor = HKStatisticsQueryDescriptor(
                predicate: .quantitySample(type: type, predicate: predicate),
                options: [.discreteAverage, .discreteMin, .discreteMax]
            )
            let statistics = try await descriptor.result(for: store)
            values.append(DailyGlucoseValue(
                day: interval,
                averageMillimolesPerLiter: statistics?.averageQuantity()?.doubleValue(for: unit),
                minimumMillimolesPerLiter: statistics?.minimumQuantity()?.doubleValue(for: unit),
                maximumMillimolesPerLiter: statistics?.maximumQuantity()?.doubleValue(for: unit),
                sourceNames: statistics?.sources?.map(\.name).sorted() ?? []
            ))
        }
        return values
    }

    private func fetchAsleepIntervals(in interval: DateInterval) async throws -> [AsleepInterval] {
        guard isHealthDataAvailable else { throw HealthDataError.unavailable }
        guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else {
            throw HealthDataError.missingType("sleep-analysis")
        }
        let datePredicate = HKQuery.predicateForSamples(
            withStart: interval.start,
            end: interval.end,
            options: []
        )
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.categorySample(type: sleepType, predicate: datePredicate)],
            sortDescriptors: [SortDescriptor(\.startDate, order: .forward)]
        )
        return try await descriptor.result(for: store).compactMap { sample in
            guard Self.sleepStage(for: sample.value).countsAsAsleep else { return nil }
            return AsleepInterval(start: sample.startDate, end: sample.endDate)
        }
    }

    private func fetchCumulativeTotal(
        type: HKQuantityType,
        unit: HKUnit,
        interval: DateInterval
    ) async throws -> Double? {
        guard isHealthDataAvailable else { throw HealthDataError.unavailable }
        let datePredicate = HKQuery.predicateForSamples(
            withStart: interval.start,
            end: interval.end,
            options: []
        )
        let descriptor = HKStatisticsQueryDescriptor(
            predicate: .quantitySample(type: type, predicate: datePredicate),
            options: .cumulativeSum
        )
        let statistics = try await descriptor.result(for: store)
        return statistics?.sumQuantity()?.doubleValue(for: unit)
    }

    private static func workoutName(_ activity: HKWorkoutActivityType) -> String {
        switch activity {
        case .walking: "Walking"
        case .running: "Running"
        case .cycling: "Cycling"
        case .functionalStrengthTraining: "FST"
        case .traditionalStrengthTraining: "Traditional Strength Training"
        case .hiking: "Hiking"
        case .yoga: "Yoga"
        case .swimming: "Swimming"
        case .elliptical: "Elliptical"
        case .highIntensityIntervalTraining: "HIIT"
        default: "Workout"
        }
    }

    private static func sleepStage(for value: Int) -> SleepStage {
        switch value {
        case HKCategoryValueSleepAnalysis.inBed.rawValue: .inBed
        case HKCategoryValueSleepAnalysis.awake.rawValue: .awake
        case HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue: .asleepUnspecified
        case HKCategoryValueSleepAnalysis.asleepCore.rawValue: .asleepCore
        case HKCategoryValueSleepAnalysis.asleepDeep.rawValue: .asleepDeep
        case HKCategoryValueSleepAnalysis.asleepREM.rawValue: .asleepREM
        default: .other
        }
    }
}
