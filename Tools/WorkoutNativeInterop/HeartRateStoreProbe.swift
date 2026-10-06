// Optional test assembly: replace the sole dedicated simulator placeholder before appending
// to DailyHealthExportTests.swift in a private assembled copy. Never a production Health writer.
extension DailyHealthExportTests {
    func testSyntheticNativeHeartRateSeriesToCanonicalDailyJSON() async throws {
        #if targetEnvironment(simulator)
        guard ProcessInfo.processInfo.environment["SIMULATOR_UDID"] == "__SYNTHETIC_HR_PHONE_UDID__" else {
            throw XCTSkip("Requires the explicitly nominated fresh synthetic Health store")
        }
        let store = HKHealthStore()
        let type = HKQuantityType(.heartRate)
        try await store.requestAuthorization(toShare: [HKObjectType.workoutType(), type], read: [HKObjectType.workoutType(), type])
        let now = Date()
        let start = now.addingTimeInterval(-300)
        let workout = HKWorkout(activityType: .walking, start: start, end: start.addingTimeInterval(120))
        try await store.save(workout)
        let unit = HKUnit.count().unitDivided(by: .minute())
        let ordinary = HKQuantitySample(type: type, quantity: HKQuantity(unit: unit, doubleValue: 80),
            start: start.addingTimeInterval(1), end: start.addingTimeInterval(1))
        try await store.save(ordinary)
        try await store.addSamples([ordinary], to: workout)
        let series = HKQuantitySeriesSampleBuilder(healthStore: store, quantityType: type, startDate: start.addingTimeInterval(2), device: nil)
        try series.insert(HKQuantity(unit: unit, doubleValue: 91), at: start.addingTimeInterval(2.000123))
        try series.insert(HKQuantity(unit: unit, doubleValue: 103), at: start.addingTimeInterval(3.000234))
        let samples = try await series.finishSeries(metadata: nil)
        XCTAssertFalse(samples.isEmpty)
        try await store.addSamples(samples, to: workout)
        // Same-time unassociated evidence must never leak into a workout's series.
        let decoy = HKQuantitySample(type: type, quantity: HKQuantity(unit: unit, doubleValue: 199),
            start: start.addingTimeInterval(2), end: start.addingTimeInterval(2))
        try await store.save(decoy)
        let native = try await HKSampleQueryDescriptor(predicates: [.workout(HKQuery.predicateForObject(with: workout.uuid))], sortDescriptors: []).result(for: store)
        XCTAssertEqual(native.count, 1)
        let records = try await HealthKitClient(store: store).fetchWorkouts(
            in: DateInterval(start: start, end: start.addingTimeInterval(120)), includeHeartRateReadings: true)
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.id, workout.uuid)
        let readings = try XCTUnwrap(records.first?.enrichment?.heartRateReadings)
        XCTAssertEqual(readings.state, "available")
        XCTAssertEqual(readings.entries.map(\.beatsPerMinute), [80, 91, 103])
        XCTAssertEqual(readings.entries.map(\.startedAt), [start.addingTimeInterval(1), start.addingTimeInterval(2.000123), start.addingTimeInterval(3.000234)])
        XCTAssertTrue(readings.entries.allSatisfy { $0.startedAt == $0.endedAt })
        XCTAssertFalse(readings.entries.contains { $0.sampleID == decoy.uuid })
        XCTAssertEqual(Set(readings.entries.map(\.sampleID)), Set([ordinary.uuid] + samples.map(\.uuid)))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London")!
        let window = try DailyExportWindow.capture(at: now, calendar: calendar)
        let envelope = try DailyHealthExportBuilder.make(window: window, exportedAt: now,
            inputs: emptyInputs(window: window, workouts: records), includeWorkoutEnrichment: true)
        XCTAssertEqual(envelope.schemaVersion, 8)
        let bytes = try DailyHealthExportSerializer.encode(envelope)
        XCTAssertNoThrow(try DailyHealthExportIdentityPolicy().validate(payload: bytes, reportDate: window.reportDate))
        let basic = try await WorkoutHealthKitProjection.records(native, store: store, activityName: { _ in "Walking" })
        XCTAssertNil(basic.first?.enrichment?.heartRateReadings)
        let output = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        try bytes.write(to: output.appendingPathComponent("synthetic-heart-rate-schema8.json"))
        #else
        throw XCTSkip("Physical Health stores are excluded")
        #endif
    }
}
