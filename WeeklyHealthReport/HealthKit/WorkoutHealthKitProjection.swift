import Foundation
import CoreFoundation
import HealthKit

/// One materialized workout query supplies every statistic; this adapter issues no sample queries.
enum WorkoutHealthKitProjection {
    static func record(_ workout: HKWorkout, activityName: String) -> WorkoutRecord {
        let heartRate = HKQuantityType(.heartRate)
        let energy = HKQuantityType(.activeEnergyBurned)
        var input = WorkoutEnrichmentInput(
            start: workout.startDate, end: workout.endDate,
            activity: activity(workout.workoutActivityType), metadata: metadata(workout.metadata),
            statistics: statistics(heartRate: workout.statistics(for: heartRate),
                                   energy: workout.statistics(for: energy), activity: false),
            distanceMetres: workout.statistics(for: HKQuantityType(.distanceWalkingRunning))?.sumQuantity()?.doubleValue(for: .meter()),
            activities: workout.workoutActivities.map { item in
                var result = WorkoutActivityInput(id: item.uuid, start: item.startDate, end: item.endDate,
                    duration: item.duration, activity: activity(item.workoutConfiguration.activityType),
                    indoor: item.workoutConfiguration.locationType == .indoor, metadata: metadata(item.metadata),
                    statistics: statistics(heartRate: item.statistics(for: heartRate),
                                           energy: item.statistics(for: energy), activity: true))
                #if compiler(>=6.4)
                if #available(iOS 27.0, *) { result.zones = zones(item.zoneGroup(for: heartRate)) }
                #endif
                return result
            })
        #if compiler(>=6.4)
        if #available(iOS 27.0, *) { input.zones = zones(workout.zoneGroup(for: heartRate)) }
        #endif
        return WorkoutRecord(id: workout.uuid, startDate: workout.startDate, duration: workout.duration,
                             activityName: activityName, enrichment: WorkoutEnrichmentReader.read(input))
    }

    static func metadata(_ values: [String: Any]?) -> [String: WorkoutMetadataValue] {
        (values ?? [:]).filter { $0.key.hasPrefix(WorkoutEnrichmentReader.namespace) }.mapValues { value in
            if let number = value as? NSNumber {
                guard CFGetTypeID(number) != CFBooleanGetTypeID(), number.doubleValue.isFinite else { return .invalid }
                // NSNumber's storage type is not a schema type. Accept only an exact,
                // in-range integer value; never round a fraction or coerce text/Boolean.
                if let integer = Int(exactly: number) { return .integer(integer) }
                return .decimal(number.decimalValue)
            }
            if let date = value as? Date { return .date(date) }
            if let string = value as? String { return .string(string) }
            return .invalid
        }
    }

    static func statistics(heartRate: HKStatistics?, energy: HKStatistics?, activity: Bool) -> WorkoutStatistics {
        let bpm = HKUnit.count().unitDivided(by: .minute())
        return WorkoutStatistics(provenance: activity ? "healthKitActivityStatistics" : "healthKitWorkoutStatistics",
            minimum: heartRate?.minimumQuantity()?.doubleValue(for: bpm),
            average: heartRate?.averageQuantity()?.doubleValue(for: bpm),
            maximum: heartRate?.maximumQuantity()?.doubleValue(for: bpm),
            energy: energy?.sumQuantity()?.doubleValue(for: .kilocalorie()))
    }

    private static func activity(_ type: HKWorkoutActivityType) -> String {
        switch type { case .walking: "walking"; case .running: "running"; default: "other" }
    }

    #if compiler(>=6.4)
    @available(iOS 27.0, *)
    private static func zones(_ group: HKWorkoutZoneGroup?) -> WorkoutHeartRateZones {
        guard let group, !group.zoneDurations.isEmpty else { return .noDataOrAccess }
        let source: String
        switch group.configuration.source {
        case .system: source = "system"
        case .user: source = "user"
        case .app: source = "app"
        @unknown default: return .unsupported
        }
        let bpm = HKUnit.count().unitDivided(by: .minute())
        let zones = group.zoneDurations.map {
            WorkoutHeartRateZones.Zone(index: $0.zone.index,
                minimumBPM: $0.zone.minimum?.doubleValue(for: bpm),
                maximumBPM: $0.zone.maximum?.doubleValue(for: bpm), durationSeconds: $0.duration)
        }
        guard zones.allSatisfy({ zone in
            zone.durationSeconds.isFinite && zone.durationSeconds >= 0
                && [zone.minimumBPM, zone.maximumBPM].allSatisfy { $0 == nil || ($0!.isFinite && $0! >= 0) }
        }) else { return .noDataOrAccess }
        let result = WorkoutHeartRateZones(state: "available", source: source, zones: zones)
        return result.isValid ? result : .noDataOrAccess
    }
    #endif
}
