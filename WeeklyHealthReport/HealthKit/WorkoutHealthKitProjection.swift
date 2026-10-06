import Foundation
import CoreFoundation
import HealthKit

/// Materialized native statistics remain independent of narrowly recovered legacy distance evidence.
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
        input.sourceBundleIdentifier = workout.sourceRevision.source.bundleIdentifier
        #if compiler(>=6.4)
        if #available(iOS 27.0, *) { input.zones = zones(workout.zoneGroup(for: heartRate)) }
        #endif
        return WorkoutRecord(id: workout.uuid, startDate: workout.startDate, duration: workout.duration,
                             activityName: activityName, enrichment: WorkoutEnrichmentReader.read(input))
    }

    /// Query only exact associated legacy aggregate identities, in bounded batches.
    /// New v3 metadata and unrelated workouts cause no sample query.
    static func records(_ workouts: [HKWorkout], store: HKHealthStore, recoverAcceptedDistance: Bool = true, includeHeartRateReadings: Bool = false, activityName: (HKWorkoutActivityType) -> String) async throws -> [WorkoutRecord] {
        var records = workouts.map { record($0, activityName: activityName($0.workoutActivityType)) }
        let native = Dictionary(workouts.map { ($0.uuid, $0) }, uniquingKeysWith: { first, _ in first })
        let requests = zip(workouts, records).compactMap { workout, record in
            record.enrichment.flatMap { LegacyWorkoutDistanceRequest.make(workoutID: workout.uuid, source: workout.sourceRevision.source.bundleIdentifier, enrichment: $0) }
        }
        let recovered = try await LegacyWorkoutDistanceRecovery.resolve(requests, enabled: recoverAcceptedDistance) { batch, limit in
            let alternatives = try batch.map { request -> NSPredicate in
                guard let workout = native[request.workoutID] else { throw WorkoutAcceptedDistancePolicy.Invalid.metadata }
                return NSCompoundPredicate(andPredicateWithSubpredicates: [
                    HKQuery.predicateForObjects(from: workout),
                    HKQuery.predicateForObjects(withMetadataKey: HKMetadataKeySyncIdentifier, allowedValues: [request.syncIdentifier])
                ])
            }
            let descriptor = HKSampleQueryDescriptor(predicates: [.quantitySample(type: HKQuantityType(.distanceWalkingRunning),
                predicate: NSCompoundPredicate(orPredicateWithSubpredicates: alternatives))], sortDescriptors: [], limit: limit)
            return try await descriptor.result(for: store).map(legacyDistanceSample)

        }
        for index in records.indices {
            if let distance = recovered[records[index].id] { records[index].enrichment?.acceptedDistance = distance }
        }
        if includeHeartRateReadings {
            for index in records.indices {
                try Task.checkCancellation()
                guard let enrichment = records[index].enrichment else { continue }
                let readings = try await heartRateReadings(workouts[index], store: store, enrichment: enrichment)
                records[index].enrichment?.enrichmentVersion = 3
                records[index].enrichment?.heartRateReadings = readings
            }
        }
        try Task.checkCancellation()
        return records
    }

    /// Expand native quantity series; never substitute the parent sample's summary.
    private static func heartRateReadings(_ workout: HKWorkout, store: HKHealthStore,
                                         enrichment: WorkoutEnrichment) async throws -> WorkoutHeartRateReadings {
        let descriptor = HKQuantitySeriesSampleQueryDescriptor(
            predicate: .quantitySample(type: HKQuantityType(.heartRate),
                                       predicate: HKQuery.predicateForObjects(from: workout)),
            options: [.includeSample])
        var grouped: [UUID: [WorkoutHeartRateReadings.Entry]] = [:]
        var count = 0
        do {
            for try await result in descriptor.results(for: store) {
                try Task.checkCancellation()
                guard let sample = result.sample else { return .unavailable("invalidEvidence") }
                count += 1
                guard count <= WorkoutHeartRateReadings.maximumEntries else { return .unavailable("limitExceeded") }
                let entry = WorkoutHeartRateReadings.Entry(sampleID: sample.uuid, entryIndex: 0,
                    startedAt: result.dateInterval.start, endedAt: result.dateInterval.end,
                    beatsPerMinute: result.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute())),
                    sourceBundleIdentifier: sample.sourceRevision.source.bundleIdentifier)
                grouped[sample.uuid, default: []].append(entry)
                guard grouped.count <= WorkoutHeartRateReadings.maximumParents else { return .unavailable("limitExceeded") }
            }
        } catch {
            try Task.checkCancellation()
            if error is CancellationError { throw error }
            return .unavailable("failed")
        }
        let entries = grouped.values.flatMap { entries in
            entries.sorted {
                if $0.startedAt != $1.startedAt { return $0.startedAt < $1.startedAt }
                if $0.endedAt != $1.endedAt { return $0.endedAt < $1.endedAt }
                return $0.beatsPerMinute < $1.beatsPerMinute
            }.enumerated().map { index, entry in
                WorkoutHeartRateReadings.Entry(sampleID: entry.sampleID, entryIndex: index,
                    startedAt: entry.startedAt, endedAt: entry.endedAt,
                    beatsPerMinute: entry.beatsPerMinute, sourceBundleIdentifier: entry.sourceBundleIdentifier)
            }
        }
        return .project(entries, into: enrichment)
    }

    static func legacyDistanceSample(_ sample: HKQuantitySample) -> LegacyWorkoutDistanceSample {
        let version: Int?
        if let number = sample.metadata?[HKMetadataKeySyncVersion] as? NSNumber,
           CFGetTypeID(number) != CFBooleanGetTypeID() { version = Int(exactly: number) } else { version = nil }
        return LegacyWorkoutDistanceSample(id: sample.uuid,
            syncIdentifier: sample.metadata?[HKMetadataKeySyncIdentifier] as? String, syncVersion: version,
            sourceBundleIdentifier: sample.sourceRevision.source.bundleIdentifier,
            start: sample.startDate, end: sample.endDate, metres: sample.quantity.doubleValue(for: .meter()))
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
