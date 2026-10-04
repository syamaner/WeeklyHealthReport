
extension DailyHealthExportTests {
    func testJoinedFreshPhoneStoreReadback() async throws {
        try await joinedPhoneStoreReadback(overrideUUID: nil)
    }

    // Deliberate failing control: a missing native record must never be a green probe.
    func testJoinedMissingSyntheticUUIDIsAFailure() async throws {
        try await joinedPhoneStoreReadback(overrideUUID: UUID(uuidString: "00000000-0000-4000-8000-000000009999")!)
    }

    private func joinedPhoneStoreReadback(overrideUUID: UUID?) async throws {
        #if targetEnvironment(simulator)
        XCTAssertEqual(ProcessInfo.processInfo.environment["SIMULATOR_UDID"], "__SYNTHETIC_PHONE_UDID__", "Synthetic-only dedicated phone required")
        guard ProcessInfo.processInfo.environment["SIMULATOR_UDID"] == "__SYNTHETIC_PHONE_UDID__" else { return }
        let root = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "JoinedInputs", withExtension: nil))
        let cases = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("scenarios.json"))) as? [[String: Any]])
        XCTAssertFalse(cases.isEmpty)
        guard !cases.isEmpty else { return }
        let output = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent(overrideUUID == nil ? "JoinedOutput" : "JoinedMissingControl")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        var results: [[String: Any]] = []
        defer {
            do { try JSONSerialization.data(withJSONObject: results, options: [.sortedKeys, .prettyPrinted]).write(to: output.appendingPathComponent("phone-store-visibility.json")) }
            catch { XCTFail("Unable to retain phone visibility diagnostics: \(error)") }
        }
        let store = HKHealthStore()
        let readTypes: Set<HKObjectType> = [HKObjectType.workoutType(), HKQuantityType(.heartRate), HKQuantityType(.activeEnergyBurned), HKQuantityType(.distanceWalkingRunning)]
        do { try await store.requestAuthorization(toShare: [], read: readTypes) }
        catch {
            results.append(["state": "authorizationRequestError", "error": String(describing: error), "readOnly": true])
            throw error
        }
        for scenario in cases {
            let name = (overrideUUID == nil ? "" : "missing-control-") + (try XCTUnwrap(scenario["name"] as? String))
            let id = try overrideUUID ?? XCTUnwrap(UUID(uuidString: try XCTUnwrap(scenario["nativeWorkoutUUID"] as? String)))
            let queryComplete = expectation(description: "Bounded synthetic UUID read")
            let storage = JoinedQueryResult()
            let query = HKSampleQuery(sampleType: .workoutType(), predicate: HKQuery.predicateForObject(with: id), limit: 1, sortDescriptors: nil) { _, samples, error in
                storage.finish(records: samples as? [HKWorkout] ?? [], error: error.map { String(describing: $0) })
                queryComplete.fulfill()
            }
            store.execute(query)
            let completion = await XCTWaiter.fulfillment(of: [queryComplete], timeout: 15)
            store.stop(query)
            guard completion == .completed else {
                results.append(["name": name, "state": "queryTimedOutOrInterrupted", "waiterResult": completion.rawValue,
                                "requestedSyntheticUUID": id.uuidString, "readOnly": true])
                XCTFail("Synthetic UUID query did not complete: \(name)")
                continue
            }
            let (records, queryError) = storage.snapshot()
            var result: [String: Any] = ["assemblyID": joinedAssemblyID, "sourceInputDigest": joinedSourceInputDigest, "name": name, "requestedSyntheticUUID": id.uuidString, "visibleCount": records.count, "readOnly": true, "pipelineCompleted": false]
            defer { results.append(result) }
            if let queryError {
                result["queryError"] = queryError
                result["state"] = "queryError; sync not established"
                XCTFail("Synthetic UUID query failed: \(name): \(queryError)")
                continue
            }
            guard records.count == 1, let workout = records.first, workout.uuid == id else {
                result["state"] = "exactSyntheticWorkoutNotVisible; sync not established"
                XCTFail("Expected exactly the requested synthetic workout: \(name)")
                continue
            }
            result["state"] = "visibleNativePhoneWorkout"
            result["nativeSourceBundleIdentifier"] = workout.sourceRevision.source.bundleIdentifier
            let fetchChecks = JoinedChecks()
            let client = HealthKitClient(store: store)
            let selected = DateInterval(start: workout.startDate.addingTimeInterval(-0.001), end: workout.endDate.addingTimeInterval(0.001))
            let exportRecords = try await client.fetchWorkouts(in: selected, recoverAcceptedDistance: true)
            fetchChecks.equal(exportRecords.count, 1, "Exact synthetic window must contain only the requested workout")
            let exportRecord = try XCTUnwrap(exportRecords.first { $0.id == id })
            result["actualSelectedDayFetchCompleted"] = true
            let basic = try await client.fetchWorkouts(in: selected)
            result["disabledRecoveryAcceptedState"] = basic.first?.enrichment?.acceptedDistance?.state
            result["disabledRecoveryAcceptedReason"] = basic.first?.enrichment?.acceptedDistance?.reason
            result["disabledRecoveryNativeMetres"] = basic.first?.enrichment?.distanceMetres
            result["enabledRecoveryAcceptedMetres"] = exportRecord.enrichment?.acceptedDistance?.metres.map { NSDecimalNumber(decimal: $0).stringValue }
            result["enabledRecoveryNativeMetres"] = exportRecord.enrichment?.distanceMetres
            fetchChecks.equal(basic.count, 1)
            if exportRecord.enrichment?.acceptedDistance?.evidence == "recoveredLegacyAssociatedSample" {
                fetchChecks.equal(basic.first?.enrichment?.acceptedDistance?.reason, "noDataOrAccess", "Basic/weekly path must not recover")
            }
            let passed = try assertJoinedWorkout(workout, scenario: scenario, output: output.appendingPathComponent("DirectPhoneRead"), recordOverride: exportRecord)
            result["pipelineCompleted"] = true
            result["pipelineAssertionsPassed"] = passed && fetchChecks.failures == 0
            result["associatedDistanceAssertionsPassed"] = try await joinedAssociatedDistance(store: store, workout: workout, scenario: scenario, result: &result)
            let data = try NSKeyedArchiver.archivedData(withRootObject: workout, requiringSecureCoding: true)
            try data.write(to: output.appendingPathComponent(name + "-phone-readback.archive"))
        }
        #else
        XCTFail("Physical Health stores are excluded")
        #endif
    }
    private func joinedAssociatedDistance(store: HKHealthStore, workout: HKWorkout, scenario: [String: Any], result: inout [String: Any]) async throws -> Bool {
        let done = expectation(description: "Exact associated synthetic distance")
        let storage = JoinedDistanceQueryResult()
        let query = HKSampleQuery(sampleType: HKQuantityType(.distanceWalkingRunning), predicate: HKQuery.predicateForObjects(from: workout), limit: 100, sortDescriptors: nil) { _, samples, error in
            storage.finish(records: samples as? [HKQuantitySample] ?? [], error: error.map { String(describing: $0) }); done.fulfill()
        }
        store.execute(query)
        let completion = await XCTWaiter.fulfillment(of: [done], timeout: 15)
        store.stop(query)
        guard completion == .completed else { result["associatedDistanceState"] = "timeoutOrInterrupted"; XCTFail("Associated distance timeout"); return false }
        let (samples, error) = storage.snapshot()
        if let error { result["associatedDistanceState"] = "error"; result["associatedDistanceError"] = error; XCTFail(error); return false }
        result["associatedDistanceState"] = "complete"
        result["associatedDistanceSamples"] = samples.map { ["metres": $0.quantity.doubleValue(for: .meter()), "start": $0.startDate.timeIntervalSince1970, "end": $0.endDate.timeIntervalSince1970, "sourceBundleIdentifier": $0.sourceRevision.source.bundleIdentifier, "syncIdentifier": $0.metadata?[HKMetadataKeySyncIdentifier] ?? NSNull(), "syncVersion": $0.metadata?[HKMetadataKeySyncVersion] ?? NSNull()] as [String: Any] }
        let checks = JoinedChecks()
        let expected = scenario["expectedAssociatedDistanceMetres"] as? NSNumber
        checks.equal(samples.count, expected == nil ? 0 : 1, "Expected exactly the declared synthetic sample count")
        if let expected, let sample = samples.first { checks.equal(sample.quantity.doubleValue(for: .meter()), expected.doubleValue, "Persisted accepted quantity must match independently declared writer input") }
        return checks.failures == 0
    }

}

private final class JoinedQueryResult: @unchecked Sendable {
    private let lock = NSLock()
    private var records: [HKWorkout] = []
    private var error: String?
    func finish(records: [HKWorkout], error: String?) {
        lock.lock(); defer { lock.unlock() }
        self.records = records; self.error = error
    }
    func snapshot() -> ([HKWorkout], String?) {
        lock.lock(); defer { lock.unlock() }
        return (records, error)
    }
}

private final class JoinedDistanceQueryResult: @unchecked Sendable {
    private let lock = NSLock()
    private var records: [HKQuantitySample] = []
    private var error: String?
    func finish(records: [HKQuantitySample], error: String?) { lock.lock(); defer { lock.unlock() }; self.records = records; self.error = error }
    func snapshot() -> ([HKQuantitySample], String?) { lock.lock(); defer { lock.unlock() }; return (records, error) }
}

extension DailyHealthExportTests {
    private func requireJoinedSyntheticSimulator() throws {
        #if targetEnvironment(simulator)
        guard ProcessInfo.processInfo.environment["SIMULATOR_UDID"] == "__SYNTHETIC_PHONE_UDID__" else {
            XCTFail("Only the explicitly selected fresh synthetic simulator is authorised")
            throw NSError(domain: "JoinedNativeAcceptance", code: 2)
        }
        #else
        XCTFail("Physical Health stores are excluded")
        throw NSError(domain: "JoinedNativeAcceptance", code: 3)
        #endif
    }
}
