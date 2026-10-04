
extension DailyHealthExportTests {
    private func assertJoinedNativeValues(_ workout: HKWorkout, json: [String: Any], name: String, checks: JoinedChecks) throws {
        let path = "today.workouts.data.0.enrichment"
        try assertJoinedDate(workout.startDate, json: json, path: path + ".started_at", name: name, checks: checks)
        try assertJoinedDate(workout.endDate, json: json, path: path + ".ended_at", name: name, checks: checks)
        try assertJoinedNumber(workout.duration, json: json, path: "today.workouts.data.0.duration_seconds", name: name, checks: checks)
        let hr = HKQuantityType(.heartRate), energy = HKQuantityType(.activeEnergyBurned)
        try assertJoinedStatistics(workout.statistics(for: hr), energy: workout.statistics(for: energy), json: json,
                                   path: path + ".statistics", provenance: "healthKitWorkoutStatistics", name: name, checks: checks)
        let nativeDistance = workout.statistics(for: HKQuantityType(.distanceWalkingRunning))?.sumQuantity()?.doubleValue(for: .meter())
        let distanceClaim = workout.metadata?[WorkoutEnrichmentReader.namespace + "distanceProvenance"] as? String
        let distance = distanceClaim == "fr30zCumulativeDistanceDelta" ? nativeDistance.flatMap { $0.isFinite && $0 > 0 ? $0 : nil } : nil
        try assertJoinedNumber(distance, json: json, path: path + ".distance_metres", name: name, checks: checks)
        checks.equal(joinedValue(json, path: path + ".distance_state") as? String, distance == nil ? "noDataOrAccess" : "available", name)
        #if compiler(>=6.4)
        if #available(iOS 27.0, *) { try assertJoinedZones(workout.zoneGroup(for: hr), json: json, path: path + ".heart_rate_zones", name: name, checks: checks) }
        #endif
        for (index, activity) in workout.workoutActivities.enumerated() {
            let item = path + ".activities.\(index)"
            try assertJoinedStatistics(activity.statistics(for: hr), energy: activity.statistics(for: energy), json: json,
                                       path: item + ".statistics", provenance: "healthKitActivityStatistics", name: name, checks: checks)
            try assertJoinedNumber(activity.duration, json: json, path: item + ".duration_seconds", name: name, checks: checks)
            try assertJoinedDate(activity.startDate, json: json, path: item + ".started_at", name: name, checks: checks)
            if let end = activity.endDate { try assertJoinedDate(end, json: json, path: item + ".ended_at", name: name, checks: checks) }
            else { checks.isNil(joinedValue(json, path: item + ".ended_at")) }
            #if compiler(>=6.4)
            if #available(iOS 27.0, *) { try assertJoinedZones(activity.zoneGroup(for: hr), json: json, path: item + ".heart_rate_zones", name: name, checks: checks) }
            #endif
        }
    }

    private func assertJoinedDate(_ expected: Date, json: [String: Any], path: String, name: String, checks: JoinedChecks) throws {
        let text = try XCTUnwrap(joinedValue(json, path: path) as? String, "\(name): native \(path) missing")
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let actual = try XCTUnwrap(formatter.date(from: text))
        let canonical = try XCTUnwrap(formatter.date(from: formatter.string(from: expected)))
        checks.equal(actual, canonical, "\(name): native \(path) must equal the canonical millisecond projection")
    }

    private func assertJoinedStatistics(_ heart: HKStatistics?, energy: HKStatistics?, json: [String: Any], path: String, provenance: String, name: String, checks: JoinedChecks) throws {
        let bpm = HKUnit.count().unitDivided(by: .minute())
        let values = [heart?.minimumQuantity()?.doubleValue(for: bpm), heart?.averageQuantity()?.doubleValue(for: bpm), heart?.maximumQuantity()?.doubleValue(for: bpm)]
        for (key, value) in zip(["heart_rate_minimum_bpm", "heart_rate_average_bpm", "heart_rate_maximum_bpm"], values) {
            try assertJoinedNumber(value, json: json, path: path + "." + key, name: name, checks: checks)
        }
        let kcal = energy?.sumQuantity()?.doubleValue(for: .kilocalorie())
        try assertJoinedNumber(kcal, json: json, path: path + ".active_energy_kilocalories", name: name, checks: checks)
        checks.equal(joinedValue(json, path: path + ".heart_rate_state") as? String, values.contains { $0 != nil } ? "available" : "noDataOrAccess", name)
        checks.equal(joinedValue(json, path: path + ".energy_state") as? String, kcal == nil ? "noDataOrAccess" : "available", name)
        checks.equal(joinedValue(json, path: path + ".energy_interpretation") as? String, "healthKitCalculationEstimate", name)
        checks.equal(joinedValue(json, path: path + ".provenance") as? String, provenance, name)
    }

    private func assertJoinedNumber(_ expected: Double?, json: [String: Any], path: String, name: String, checks: JoinedChecks) throws {
        if let expected {
            let actual = try XCTUnwrap(joinedValue(json, path: path) as? NSNumber, "\(name): native \(path) missing")
            checks.equal(actual.doubleValue, expected, "\(name): native \(path)")
        } else { checks.isNil(joinedValue(json, path: path), "\(name): unavailable native \(path) became a value") }
    }

    #if compiler(>=6.4)
    @available(iOS 27.0, *)
    private func assertJoinedZones(_ group: HKWorkoutZoneGroup?, json: [String: Any], path: String, name: String, checks: JoinedChecks) throws {
        guard let group, !group.zoneDurations.isEmpty else {
            checks.equal(joinedValue(json, path: path + ".state") as? String, "noDataOrAccess", name)
            checks.equal((joinedValue(json, path: path + ".zones") as? [Any])?.count, 0, name)
            return
        }
        let source: String
        switch group.configuration.source {
        case .system: source = "system"
        case .user: source = "user"
        case .app: source = "app"
        @unknown default: checks.fail("New native zone source needs explicit expectation"); return
        }
        checks.equal(joinedValue(json, path: path + ".state") as? String, "available", name)
        checks.equal(joinedValue(json, path: path + ".source") as? String, source, name)
        checks.equal((joinedValue(json, path: path + ".zones") as? [Any])?.count, group.zoneDurations.count, name)
        let bpm = HKUnit.count().unitDivided(by: .minute())
        for (offset, value) in group.zoneDurations.enumerated() {
            let item = path + ".zones.\(offset)"
            try assertJoinedNumber(Double(value.zone.index), json: json, path: item + ".index", name: name, checks: checks)
            try assertJoinedNumber(value.zone.minimum?.doubleValue(for: bpm), json: json, path: item + ".minimum_bpm", name: name, checks: checks)
            try assertJoinedNumber(value.zone.maximum?.doubleValue(for: bpm), json: json, path: item + ".maximum_bpm", name: name, checks: checks)
            try assertJoinedNumber(value.duration, json: json, path: item + ".duration_seconds", name: name, checks: checks)
        }
    }
    #endif
}
