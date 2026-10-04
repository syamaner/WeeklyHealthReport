
// Synthetic-only cross-repository harness. Not an application feature.
private let joinedAssemblyID = "__ASSEMBLY_ID__"
private let joinedSourceInputDigest = "__SOURCE_INPUT_DIGEST__"
extension DailyHealthExportTests {
    func testJoinedProducerNativeArchivesToCanonicalDailyJSON() async throws {
        try requireJoinedSyntheticSimulator()
        let root = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "JoinedInputs", withExtension: nil))
        let cases = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("scenarios.json"))) as? [[String: Any]])
        XCTAssertFalse(cases.isEmpty, "No producer archive is not a passing integration test")
        let output = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("JoinedOutput")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        for scenario in cases {
            let archiveName = try XCTUnwrap(scenario["archive"] as? String)
            let archive = try Data(contentsOf: root.appendingPathComponent(archiveName))
            let original = try XCTUnwrap(NSKeyedUnarchiver.unarchivedObject(ofClass: HKWorkout.self, from: archive))
            let projected = try await WorkoutHealthKitProjection.records([original], store: HKHealthStore(), activityName: { _ in "Walking" })
            try assertJoinedWorkout(original, scenario: scenario, output: output, recordOverride: try XCTUnwrap(projected.first))
        }
    }

    @discardableResult
    private func assertJoinedWorkout(_ original: HKWorkout, scenario: [String: Any], output: URL, recordOverride: WorkoutRecord? = nil) throws -> Bool {
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let checks = JoinedChecks()
        let name = try XCTUnwrap(scenario["name"] as? String)
        guard scenario["reboxWholeMetadata"] as? Bool != true else {
            XCTFail("Native acceptance never perturbs HealthKit metadata"); throw NSError(domain: "JoinedNativeAcceptance", code: 1)
        }
        let workout = original
        var completedCase = false
        var strictIdentityPassed = false
        defer {
        let native: [String: Any] = ["assemblyID": joinedAssemblyID, "sourceInputDigest": joinedSourceInputDigest, "name": name, "workoutUUID": workout.uuid.uuidString,
            "nativeActivityCount": workout.workoutActivities.count,
            "originalVersionObjCType": (original.metadata?[WorkoutEnrichmentReader.namespace + "interchangeSchemaVersion"] as? NSNumber).map { String(cString: $0.objCType) } ?? "absent",
            "nativeVersionObjCType": (workout.metadata?[WorkoutEnrichmentReader.namespace + "interchangeSchemaVersion"] as? NSNumber).map { String(cString: $0.objCType) } ?? "absent",
            "representationPerturbation": scenario["reboxWholeMetadata"] as? Bool ?? false,
            "expectedFieldCount": (scenario["expectedJSONPaths"] as? [String: Any])?.count ?? 0, "strictIdentity": strictIdentityPassed ? "passed" : "notPassed",
            "caseCompleted": completedCase,
            "caseAssertionsPassed": completedCase && checks.failures == 0,
            "caseAssertionFailures": checks.failures + (completedCase ? 0 : 1)]
            do { try JSONSerialization.data(withJSONObject: native, options: [.sortedKeys, .prettyPrinted]).write(to: output.appendingPathComponent(name + "-native.json")) }
            catch { XCTFail("Unable to retain case diagnostic: \(error)") }
        }
        let record = recordOverride ?? WorkoutHealthKitProjection.record(workout, activityName: "Walking")
        checks.equal(record.id, workout.uuid, name)
        checks.equal(record.startDate, workout.startDate, name)
        checks.equal(record.duration, workout.duration, name)
        checks.equal(record.enrichment?.activities.map(\.activityID), workout.workoutActivities.map(\.uuid), name)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Europe/London"))
        let now = workout.endDate.addingTimeInterval(60)
        let window = try DailyExportWindow.capture(at: now, calendar: calendar)
        let envelope = try DailyHealthExportBuilder.make(window: window, exportedAt: now,
            inputs: emptyInputs(window: window, workouts: [record]), includeWorkoutEnrichment: true)
        checks.equal(envelope.schemaVersion, 7, name)
        checks.equal(envelope.today.workouts.data?.count, 1, name)
        checks.isNil(envelope.today.activity.activeEnergy.data, "Workout totals must not populate an unqueried daily total")
        let bytes = try DailyHealthExportSerializer.encode(envelope)
        try bytes.write(to: output.appendingPathComponent(name + "-candidate.json"))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        try assertJoinedNativeValues(original, json: json, name: name, checks: checks)
        let expected = try XCTUnwrap(scenario["expectedJSONPaths"] as? [String: Any])
        checks.isFalse(expected.isEmpty, "Independent field expectations required")
        for (path, value) in expected {
            let actual = joinedValue(json, path: path)
            if value is NSNull { checks.isNil(actual, "\(name): \(path) must be absent") }
            else {
                let actual = try XCTUnwrap(actual, "\(name): \(path) missing")
                let actualBytes = try JSONSerialization.data(withJSONObject: ["value": actual], options: [.sortedKeys])
                let expectedBytes = try JSONSerialization.data(withJSONObject: ["value": value], options: [.sortedKeys])
                checks.equal(actualBytes, expectedBytes, "\(name): \(path)")
            }
        }
        let text = try XCTUnwrap(String(data: bytes, encoding: .utf8))
        checks.isFalse(text.contains(WorkoutEnrichmentReader.namespace), "Raw metadata keys must not escape the allowlist")
        checks.isNil(envelope.today.foodLog)
        checks.isNil(envelope.today.foodNutritionSummary)
        let identity = try DailyHealthExportIdentityPolicy().validate(payload: bytes, reportDate: window.reportDate)
        strictIdentityPassed = true
        checks.equal(identity.payloadSHA256, DailyDriveExportCoordinator.sha256(bytes))
        try bytes.write(to: output.appendingPathComponent(name + ".json"))
        completedCase = true
        return checks.failures == 0
    }

    private func joinedValue(_ object: Any, path: String) -> Any? {
        path.split(separator: ".").reduce(Optional(object)) { current, component in
            if let dictionary = current as? [String: Any] { return dictionary[String(component)] }
            if let array = current as? [Any], let index = Int(component), array.indices.contains(index) { return array[index] }
            return nil
        }
    }
}

private final class JoinedChecks {
    private(set) var failures = 0
    func equal<T: Equatable>(_ actual: T, _ expected: T, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
        if actual != expected { failures += 1; XCTFail(message + ": expected \(expected), received \(actual)", file: file, line: line) }
    }
    func equal(_ actual: Double, _ expected: Double, accuracy: Double, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
        if !actual.isFinite || !expected.isFinite || abs(actual - expected) > accuracy { failures += 1; XCTFail(message + ": expected \(expected), received \(actual)", file: file, line: line) }
    }
    func isFalse(_ value: Bool, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) { equal(value, false, message, file: file, line: line) }
    func isNil<T>(_ value: T?, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) { if value != nil { failures += 1; XCTFail(message, file: file, line: line) } }
    func fail(_ message: String, file: StaticString = #filePath, line: UInt = #line) { failures += 1; XCTFail(message, file: file, line: line) }
}
