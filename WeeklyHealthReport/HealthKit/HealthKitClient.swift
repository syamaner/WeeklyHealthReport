import Foundation
import HealthKit

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

final class HealthKitClient: HealthDataProviding {
    private let store: HKHealthStore

    init(store: HKHealthStore = HKHealthStore()) {
        self.store = store
    }

    var isHealthDataAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
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
        guard let restingHeartRateType = HKObjectType.quantityType(forIdentifier: .restingHeartRate),
              let hrvType = HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN),
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
                stepType, bodyMassType, bodyFatType,
                restingHeartRateType, hrvType, exerciseType, activeEnergyType,
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
        guard isHealthDataAvailable else {
            throw HealthDataError.unavailable
        }
        guard let bodyMassType = HKObjectType.quantityType(forIdentifier: .bodyMass) else {
            throw HealthDataError.missingBodyMassType
        }
        guard let lookbackStart = Calendar.autoupdatingCurrent.date(
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
                date: sample.endDate,
                kilograms: sample.quantity.doubleValue(for: kilograms)
            )
        }
        return measurements
    }

    func fetchBodyFatMeasurements(asOf date: Date) async throws -> [BodyFatMeasurement] {
        guard isHealthDataAvailable else {
            throw HealthDataError.unavailable
        }
        guard let bodyFatType = HKObjectType.quantityType(forIdentifier: .bodyFatPercentage) else {
            throw HealthDataError.missingBodyFatType
        }
        guard let lookbackStart = Calendar.autoupdatingCurrent.date(
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

    func fetchExerciseMinutes(for period: ReportPeriod) async throws -> Double? {
        guard let type = HKObjectType.quantityType(forIdentifier: .appleExerciseTime) else {
            throw HealthDataError.missingType("Apple Exercise Time")
        }
        return try await fetchCumulativeTotal(type: type, unit: .minute(), period: period)
    }

    func fetchActiveEnergyKilocalories(for period: ReportPeriod) async throws -> Double? {
        guard let type = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned) else {
            throw HealthDataError.missingType("active-energy")
        }
        return try await fetchCumulativeTotal(type: type, unit: .kilocalorie(), period: period)
    }

    func fetchWorkouts(for period: ReportPeriod) async throws -> [WorkoutRecord] {
        guard isHealthDataAvailable else { throw HealthDataError.unavailable }
        let datePredicate = HKQuery.predicateForSamples(
            withStart: period.interval.start,
            end: period.interval.end,
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

    private func fetchCumulativeTotal(
        type: HKQuantityType,
        unit: HKUnit,
        period: ReportPeriod
    ) async throws -> Double? {
        guard isHealthDataAvailable else { throw HealthDataError.unavailable }
        let datePredicate = HKQuery.predicateForSamples(
            withStart: period.interval.start,
            end: period.interval.end,
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
        case .functionalStrengthTraining: "Functional Strength Training"
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
