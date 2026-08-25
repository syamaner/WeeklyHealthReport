import Foundation
import HealthKit

enum HealthDataError: LocalizedError {
    case unavailable
    case missingStepType
    case missingBodyMassType
    case missingBodyFatType
    case missingBMIType

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
        case .missingBMIType:
            return "The HealthKit BMI type is unavailable."
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
        guard let bmiType = HKObjectType.quantityType(forIdentifier: .bodyMassIndex) else {
            throw HealthDataError.missingBMIType
        }

        // A successful request means the authorization sheet completed. HealthKit
        // intentionally does not reveal whether read access was granted or denied.
        try await store.requestAuthorization(
            toShare: [],
            read: [stepType, bodyMassType, bodyFatType, bmiType]
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

    func fetchLatestWeight(asOf date: Date) async throws -> WeightMeasurement? {
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
            return nil
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
            sortDescriptors: [SortDescriptor(\.endDate, order: .reverse)],
            limit: 1
        )

        let samples = try await descriptor.result(for: store)
        let kilograms = HKUnit.gramUnit(with: .kilo)
        let measurements = samples.map { sample in
            WeightMeasurement(
                date: sample.endDate,
                kilograms: sample.quantity.doubleValue(for: kilograms)
            )
        }
        return WeightMeasurement.latest(in: measurements)
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
            BodyFatMeasurement(
                date: sample.endDate,
                percentage: sample.quantity.doubleValue(for: .percent())
            )
        }
    }

    func fetchLatestBMI(asOf date: Date) async throws -> BMIMeasurement? {
        guard isHealthDataAvailable else {
            throw HealthDataError.unavailable
        }
        guard let bmiType = HKObjectType.quantityType(forIdentifier: .bodyMassIndex) else {
            throw HealthDataError.missingBMIType
        }
        guard let lookbackStart = Calendar.autoupdatingCurrent.date(
            byAdding: .day,
            value: -30,
            to: date
        ) else {
            return nil
        }

        let datePredicate = HKQuery.predicateForSamples(
            withStart: lookbackStart,
            end: date,
            options: []
        )
        let samplePredicate = HKSamplePredicate.quantitySample(
            type: bmiType,
            predicate: datePredicate
        )
        let descriptor = HKSampleQueryDescriptor(
            predicates: [samplePredicate],
            sortDescriptors: [SortDescriptor(\.endDate, order: .reverse)],
            limit: 1
        )

        let samples = try await descriptor.result(for: store)
        let measurements = samples.map { sample in
            BMIMeasurement(
                date: sample.endDate,
                value: sample.quantity.doubleValue(for: .count())
            )
        }
        return BMIMeasurement.latest(in: measurements)
    }
}
