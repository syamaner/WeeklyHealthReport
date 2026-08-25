import Foundation
import HealthKit

enum HealthDataError: LocalizedError {
    case unavailable
    case missingStepType

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "Health data is unavailable on this device."
        case .missingStepType:
            return "The HealthKit step-count type is unavailable."
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

        // A successful request means the authorization sheet completed. HealthKit
        // intentionally does not reveal whether read access was granted or denied.
        try await store.requestAuthorization(toShare: [], read: [stepType])
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
}
