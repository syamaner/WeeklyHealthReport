import XCTest
import CoreFoundation
import HealthKit
@testable import WeeklyHealthReport

final class WorkoutEnrichmentTests: XCTestCase {
    private let prefix = WorkoutEnrichmentReader.namespace

    func testSharedV2FixturesRetainPartialDistanceAndResetState() throws {
        let complete = WorkoutEnrichmentReader.read(try fixture("complete", version: 2))
        XCTAssertEqual(complete.recognition, .supportedComplete)
        XCTAssertEqual(complete.activities[1].pacePrompt?.intervalDistance.coverage, "partialObservationWindow")
        let incomplete = WorkoutEnrichmentReader.read(try fixture("incomplete", version: 2))
        XCTAssertEqual(incomplete.recognition, .supportedIncomplete)
        XCTAssertEqual(incomplete.activities[0].pacePrompt?.intervalDistance.reason, "invalidDistanceEvidence")
    }

    func testIdentitySequenceAndObservationTimestampAreClosedInvariants() throws {
        let input = try fixture("complete")
        for (key, value) in [("intervalIndex", WorkoutMetadataValue.integer(2)), ("observedAt", .date(input.activities[0].start.addingTimeInterval(1)))] {
            var metadata = input.activities[0].metadata; metadata[prefix + key] = value
            XCTAssertEqual(WorkoutEnrichmentReader.read(replacing(input, activities: [replacing(input.activities[0], metadata: metadata), input.activities[1]])).recognition, .invalid)
        }
        var recovery = input.activities[0].metadata
        recovery[prefix + "prescribedSegmentKind"] = .string("recovery")
        XCTAssertEqual(WorkoutEnrichmentReader.read(replacing(input, activities: [replacing(input.activities[0], metadata: recovery), input.activities[1]])).recognition, .supportedComplete)
    }

    func testSharedCompleteV1FixtureAndIndependentStatistics() throws {
        let value = WorkoutEnrichmentReader.read(try fixture("complete"))
        XCTAssertEqual(value.recognition, .supportedComplete)
        XCTAssertEqual(value.activities.count, 2)
        XCTAssertEqual(value.statistics.activeEnergyKilocalories, 12)
        XCTAssertEqual(value.activities.compactMap { $0.statistics.activeEnergyKilocalories }.reduce(0, +), 9)
        XCTAssertEqual(value.activities[1].pacePrompt?.speedTargetSource, "manualOverride")
        XCTAssertEqual(value.activities[1].pacePrompt?.inclinationTargetSource, "planned")
        XCTAssertEqual(value.activities[0].pacePrompt?.intervalDistance.state, "unavailable")
        XCTAssertEqual(value.distanceMetres, 100)
    }

    func testSharedIncompleteFixtureNeverUpgrades() throws {
        XCTAssertEqual(WorkoutEnrichmentReader.read(try fixture("incomplete")).recognition, .supportedIncomplete)
    }

    func testSharedZeroPrefixFixtureIsNotAStoredWorkout() throws {
        let json = try fixtureJSON("zero-interval")
        let expected = try XCTUnwrap(json["expected"] as? [String: Any])
        XCTAssertTrue(expected["workout"] is NSNull)
        XCTAssertEqual(expected["finishCalls"] as? Int, 0)
    }

    func testAbsentNamespaceKeepsBasicActivitiesAndPartialStatistics() throws {
        let input = try fixture("complete")
        let stripped = replacing(input, metadata: [:], activities: input.activities.map { replacing($0, metadata: [:]) })
        let value = WorkoutEnrichmentReader.read(stripped)
        XCTAssertEqual(value.recognition, .notPacePrompt)
        XCTAssertEqual(value.activities.count, 2)
        XCTAssertEqual(value.statistics.heartRateAverageBPM, 100)
        XCTAssertNil(value.activities[0].pacePrompt)
    }

    func testHistoricalPhoneMetadataCannotBecomeWatchOwned() throws {
        let input = try fixture("complete")
        let result = WorkoutEnrichmentReader.read(replacing(input, metadata: [prefix + "summaryID": .string(UUID().uuidString.lowercased())]))
        XCTAssertEqual(result.recognition, .unsupported)
        XCTAssertNil(result.ownership)
    }

    func testMalformedTypesAndMissingRequiredKeysAreInvalid() throws {
        let input = try fixture("complete")
        for replacement in [WorkoutMetadataValue?.some(.string("1")), .some(.decimal(1.5)), .some(.invalid), nil] {
            var metadata = input.metadata
            metadata[prefix + "intervalCount"] = replacement
            XCTAssertEqual(WorkoutEnrichmentReader.read(replacing(input, metadata: metadata)).recognition, .invalid)
        }
    }

    func testUnknownVersionOwnershipAndEnumsAreUnsupported() throws {
        let input = try fixture("complete")
        for (key, value) in [("interchangeSchemaVersion", WorkoutMetadataValue.integer(99)), ("ownership", .string("phone")), ("interchangeStatus", .string("future"))] {
            var metadata = input.metadata; metadata[prefix + key] = value
            let result = WorkoutEnrichmentReader.read(replacing(input, metadata: metadata))
            XCTAssertEqual(result.recognition, .unsupported)
            XCTAssertEqual(result.statistics.activeEnergyKilocalories, 12)
        }
    }

    func testMissingVisibleActivitiesIsIncompleteAndExtraActivityIsInvalid() throws {
        let input = try fixture("complete")
        XCTAssertEqual(WorkoutEnrichmentReader.read(replacing(input, activities: Array(input.activities.prefix(1)))).recognition, .supportedIncomplete)
        XCTAssertEqual(WorkoutEnrichmentReader.read(replacing(input, activities: input.activities + [input.activities[0]])).recognition, .invalid)
    }

    func testInvalidSuffixRetainsValidatedPrefixButNeverCompleteness() throws {
        let input = try fixture("complete")
        var bad = input.activities[1].metadata
        bad[prefix + "summaryID"] = .string("00000000-0000-4000-8000-000000000999")
        let result = WorkoutEnrichmentReader.read(replacing(input, activities: [input.activities[0], replacing(input.activities[1], metadata: bad)]))
        XCTAssertEqual(result.recognition, .invalid)
        XCTAssertNotNil(result.activities[0].pacePrompt)
        XCTAssertNil(result.activities[1].pacePrompt)
        XCTAssertEqual(result.activities[1].statistics.heartRateAverageBPM, 100)
    }

    func testBoundsOverlapMissingEndAndDuplicateIdentityRejected() throws {
        let input = try fixture("complete")
        let first = input.activities[0], second = input.activities[1]
        for bad in [replacing(second, start: first.start), replacing(second, end: input.end.addingTimeInterval(1)), replacing(second, end: nil, removeEnd: true), replacing(second, metadata: first.metadata)] {
            XCTAssertEqual(WorkoutEnrichmentReader.read(replacing(input, activities: [first, bad])).recognition, .invalid)
        }
    }

    func testV2DistanceCoverageAndZeroArePreserved() throws {
        let input = try v2()
        let result = WorkoutEnrichmentReader.read(input)
        XCTAssertEqual(result.recognition, .supportedComplete)
        XCTAssertEqual(result.activities[0].pacePrompt?.intervalDistance.metres, 0)
        XCTAssertEqual(result.activities[0].pacePrompt?.intervalDistance.coverage, "completeInterval")
        var metadata = input.activities[0].metadata
        metadata[prefix + "intervalDistanceStartObservedAt"] = .date(input.activities[0].start.addingTimeInterval(1))
        let partial = WorkoutEnrichmentReader.read(replacing(input, activities: [replacing(input.activities[0], metadata: metadata), input.activities[1]]))
        XCTAssertEqual(partial.activities[0].pacePrompt?.intervalDistance.coverage, "partialObservationWindow")
    }

    func testV2MissingDistanceAndInvalidDistanceEvidenceRejected() throws {
        let input = try v2()
        for (key, value) in [(String, WorkoutMetadataValue?)]([
            ("intervalDistanceSchemaVersion", nil), ("intervalDistanceMetres", .decimal(1)),
            ("intervalDistanceEndCumulativeMetres", .decimal(9)),
            ("intervalDistanceEndObservedAt", .date(input.end.addingTimeInterval(1))),
            ("intervalDistanceStartObservedAt", .date(input.activities[0].end!))]) {
            var metadata = input.activities[0].metadata; metadata[prefix + key] = value
            XCTAssertEqual(WorkoutEnrichmentReader.read(replacing(input, activities: [replacing(input.activities[0], metadata: metadata), input.activities[1]])).recognition, .invalid)
        }
    }

    func testV2ResetReasonUnavailableAndUnknownReasonUnsupported() throws {
        let input = try v2()
        var metadata = input.activities[0].metadata
        for key in metadata.keys where key.hasPrefix(prefix + "intervalDistance") && key != prefix + "intervalDistanceSchemaVersion" {
            metadata.removeValue(forKey: key)
        }
        metadata[prefix + "intervalDistanceState"] = .string("unavailable")
        metadata[prefix + "intervalDistanceReason"] = .string("invalidDistanceEvidence")
        let unavailable = WorkoutEnrichmentReader.read(replacing(input, activities: [replacing(input.activities[0], metadata: metadata), input.activities[1]]))
        XCTAssertEqual(unavailable.recognition, .supportedComplete)
        XCTAssertNil(unavailable.activities[0].pacePrompt?.intervalDistance.metres)
        metadata[prefix + "intervalDistanceReason"] = .string("invented")
        XCTAssertEqual(WorkoutEnrichmentReader.read(replacing(input, activities: [replacing(input.activities[0], metadata: metadata), input.activities[1]])).recognition, .unsupported)
    }

    func testContradictoryDistanceShapesAreInvalid() throws {
        let input = try v2()
        var metadata = input.activities[0].metadata
        metadata[prefix + "intervalDistanceReason"] = .string("missingBoundary")
        XCTAssertEqual(WorkoutEnrichmentReader.read(replacing(input, activities: [replacing(input.activities[0], metadata: metadata), input.activities[1]])).recognition, .invalid)
        metadata[prefix + "intervalDistanceState"] = .string("unavailable")
        XCTAssertEqual(WorkoutEnrichmentReader.read(replacing(input, activities: [replacing(input.activities[0], metadata: metadata), input.activities[1]])).recognition, .invalid)
    }

    func testMaterializedSDKWorkoutUsesSameReaderWithoutStoreQueries() {
        let start = Date(timeIntervalSince1970: 1_760_000_000)
        let end = start.addingTimeInterval(60)
        let workout = HKWorkout(activityType: .walking, start: start, end: end, duration: 60,
                                totalEnergyBurned: nil, totalDistance: nil, metadata: nil)
        let result = WorkoutHealthKitProjection.record(workout, activityName: "Walking")
        XCTAssertEqual(result.id, workout.uuid)
        XCTAssertEqual(result.enrichment?.recognition, .notPacePrompt)
        XCTAssertEqual(result.enrichment?.statistics.heartRateState, "noDataOrAccess")
        XCTAssertEqual(result.enrichment?.statistics.energyState, "noDataOrAccess")
        XCTAssertEqual(result.enrichment?.activities.map(\.activityID), workout.workoutActivities.map(\.uuid))
        XCTAssertTrue(result.enrichment?.activities.allSatisfy { $0.pacePrompt == nil && $0.statistics.heartRateState == "noDataOrAccess" } == true)
        #if compiler(>=6.4)
        if #available(iOS 27.0, *) {
            XCTAssertEqual(result.enrichment?.heartRateZones.state, "noDataOrAccess")
        } else {
            XCTAssertEqual(result.enrichment?.heartRateZones.state, "unsupported")
        }
        #else
        XCTAssertEqual(result.enrichment?.heartRateZones.state, "unsupported")
        #endif
    }

    func testSettledTargetsSourcesAndOriginalOrderCannotBeRepairedIntoComplete() throws {
        let input = try fixture("complete")
        XCTAssertEqual(WorkoutEnrichmentReader.read(replacing(input, activities: input.activities.reversed())).recognition, .invalid)
        for key in ["observedSpeedKilometresPerHour", "observedInclinationPercent", "prescribedSpeedKilometresPerHour", "prescribedInclinationPercent"] {
            var metadata = input.activities[0].metadata
            metadata[prefix + key] = .decimal(99)
            XCTAssertEqual(WorkoutEnrichmentReader.read(replacing(input, activities: [replacing(input.activities[0], metadata: metadata), input.activities[1]])).recognition, .invalid)
        }
    }

    func testZoneShapeAndEnumAdmission() {
        let zones: [WorkoutHeartRateZones.Zone] = [.init(index: 0, minimumBPM: nil, maximumBPM: 120, durationSeconds: 10), .init(index: 1, minimumBPM: 120, maximumBPM: nil, durationSeconds: 20)]
        XCTAssertTrue(WorkoutHeartRateZones(state: "available", source: "system", zones: zones).isValid)
        XCTAssertFalse(WorkoutHeartRateZones(state: "available", source: "invented", zones: zones).isValid)
        XCTAssertFalse(WorkoutHeartRateZones(state: "future", source: nil, zones: []).isValid)
        XCTAssertFalse(WorkoutHeartRateZones(state: "unsupported", source: "user", zones: []).isValid)
        XCTAssertFalse(WorkoutHeartRateZones(state: "available", source: "user", zones: zones.reversed()).isValid)
        XCTAssertFalse(WorkoutHeartRateZones(state: "available", source: "user", zones: [.init(index: 0, minimumBPM: 150, maximumBPM: 120, durationSeconds: -1)]).isValid)
        let zero = WorkoutStatistics(provenance: "healthKitWorkoutStatistics", minimum: 0, energy: 0)
        XCTAssertEqual(zero.heartRateMinimumBPM, 0)
        XCTAssertEqual(zero.heartRateState, "available")
        XCTAssertEqual(zero.activeEnergyKilocalories, 0)
    }

    func testCanonicalExportAdmissionRechecksCompleteMirrorClaims() throws {
        let valid = WorkoutEnrichmentReader.read(try v2())
        XCTAssertTrue(WorkoutEnrichmentReader.validatesExport(valid))
        let bytes = try JSONEncoder().encode(valid)
        let original = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        let mutations: [(inout [String: Any]) -> Void] = [
            { $0["expectedIntervalCount"] = 3 },
            { $0["interchangeSchemaVersion"] = 99 },
            { $0["ownership"] = "phone" },
            { $0["distanceMetres"] = -1 },
            { value in
                var activities = value["activities"] as! [[String: Any]]
                var interval = activities[0]["pacePrompt"] as! [String: Any]
                interval["speedTargetSource"] = "future"
                activities[0]["pacePrompt"] = interval; value["activities"] = activities
            },
            { value in
                var activities = value["activities"] as! [[String: Any]]
                var interval = activities[0]["pacePrompt"] as! [String: Any]
                var distance = interval["intervalDistance"] as! [String: Any]
                distance["metres"] = 99
                interval["intervalDistance"] = distance; activities[0]["pacePrompt"] = interval; value["activities"] = activities
            },
            { value in
                var activities = value["activities"] as! [[String: Any]]
                var interval = activities[0]["pacePrompt"] as! [String: Any]
                var distance = interval["intervalDistance"] as! [String: Any]
                distance["coverage"] = "partialObservationWindow"
                interval["intervalDistance"] = distance; activities[0]["pacePrompt"] = interval; value["activities"] = activities
            },
            { value in
                var activities = value["activities"] as! [[String: Any]]
                activities[1]["activity"] = "running"; value["activities"] = activities
            }
        ]
        for mutate in mutations {
            var changed = original; mutate(&changed)
            let decoded = try JSONDecoder().decode(WorkoutEnrichment.self, from: JSONSerialization.data(withJSONObject: changed))
            XCTAssertFalse(WorkoutEnrichmentReader.validatesExport(decoded))
        }
        let incomplete = WorkoutEnrichmentReader.read(try fixture("incomplete", version: 2))
        XCTAssertTrue(WorkoutEnrichmentReader.validatesExport(incomplete))
        let input = try fixture("complete")
        var malformed = input.activities[1].metadata
        malformed[prefix + "summaryID"] = .string("bad")
        let invalid = WorkoutEnrichmentReader.read(replacing(input, activities: [input.activities[0], replacing(input.activities[1], metadata: malformed)]))
        XCTAssertEqual(invalid.recognition, .invalid)
        XCTAssertTrue(WorkoutEnrichmentReader.validatesExport(invalid))
    }

    func testSDKMetadataBridgeRejectsBooleanAndStringCoercion() {
        let mapped = WorkoutHealthKitProjection.metadata([prefix + "intervalCount": true, prefix + "manifestRevision": "2", prefix + "observedAt": Date(timeIntervalSince1970: 1), "other.secret": "not exported"])
        XCTAssertEqual(mapped[prefix + "intervalCount"], .invalid)
        XCTAssertEqual(mapped[prefix + "manifestRevision"], .string("2"))
        XCTAssertEqual(mapped[prefix + "observedAt"], .date(Date(timeIntervalSince1970: 1)))
        XCTAssertNil(mapped["other.secret"])
    }

    func testSDKMetadataBridgeUsesExactNumericValueInsteadOfStorageType() {
        let integers: [(NSNumber, Int)] = [
            (NSNumber(value: 2.0), 2), (NSNumber(value: Float(2)), 2),
            (NSDecimalNumber(string: "2.0"), 2), (NSDecimalNumber(string: "2e0"), 2),
            (NSNumber(value: Int.min), Int.min), (NSNumber(value: Int.max), Int.max),
            (NSDecimalNumber(decimal: Decimal(Int.min)), Int.min),
            (NSDecimalNumber(decimal: Decimal(Int.max)), Int.max), (NSNumber(value: -0.0), 0)
        ]
        for (number, expected) in integers {
            XCTAssertEqual(WorkoutHealthKitProjection.metadata([prefix + "intervalCount": number])[prefix + "intervalCount"], .integer(expected))
        }
        let decimals: [NSNumber] = [
            NSDecimalNumber(string: "5.2"), NSNumber(value: 2.5),
            NSDecimalNumber(string: "2.0000000000000000000000000000000000001"),
            NSDecimalNumber(decimal: Decimal(Int.max) + 1),
            NSDecimalNumber(decimal: Decimal(Int.min) - 1), NSNumber(value: UInt64.max)
        ]
        for number in decimals {
            XCTAssertEqual(WorkoutHealthKitProjection.metadata([prefix + "intervalCount": number])[prefix + "intervalCount"], .decimal(number.decimalValue))
        }
        for number in [NSNumber(value: true), NSNumber(value: false), NSNumber(value: Double.nan),
                       NSNumber(value: Double.infinity), NSNumber(value: -Double.infinity), NSDecimalNumber.notANumber] {
            XCTAssertEqual(WorkoutHealthKitProjection.metadata([prefix + "intervalCount": number])[prefix + "intervalCount"], .invalid)
        }
    }

    func testNativeArchivedNumericMetadataKeepsV1V2CompleteAndIncompleteFixtures() throws {
        for version in [1, 2] {
            for name in ["complete", "incomplete"] {
                let expected = WorkoutEnrichmentReader.read(try fixture(name, version: version))
                for decimalStorage in [false, true] {
                    let input = try fixture(name, version: version) { raw, activity in
                        try self.archivedMetadata(self.reboxingIntegers(raw, decimalStorage: decimalStorage), activity: activity)
                    }
                    XCTAssertEqual(WorkoutEnrichmentReader.read(input), expected, "v\(version) \(name), decimal storage: \(decimalStorage)")
                }
            }
        }
    }

    func testNativeArchivedMetadataPreservesFractionalDecimalsAndDates() throws {
        let observedAt = Date(timeIntervalSince1970: 60.123456789)
        let raw: [String: Any] = [prefix + "observedSpeedKilometresPerHour": NSDecimalNumber(string: "5.2"),
                                  prefix + "observedInclinationPercent": NSDecimalNumber(string: "1.3"),
                                  prefix + "observedAt": observedAt]
        for activity in [false, true] {
            let mapped = WorkoutHealthKitProjection.metadata(try archivedMetadata(raw, activity: activity))
            XCTAssertEqual(mapped[prefix + "observedSpeedKilometresPerHour"], .decimal(Decimal(string: "5.2")!))
            XCTAssertEqual(mapped[prefix + "observedInclinationPercent"], .decimal(Decimal(string: "1.3")!))
            XCTAssertEqual(mapped[prefix + "observedAt"], .date(observedAt))
        }
    }

    func testNativeArchivedNumericMetadataStillRejectsMalformedSchemaAndInvariants() throws {
        let cases: [(String, Any, Bool, WorkoutEnrichment.Recognition)] = [
            ("interchangeSchemaVersion", NSNumber(value: 99.0), false, .unsupported),
            ("interchangeSchemaVersion", NSNumber(value: 2.5), false, .invalid),
            ("intervalCount", NSNumber(value: true), false, .invalid),
            ("intervalCount", "2", false, .invalid),
            ("intervalCount", NSNumber(value: 2.5), false, .invalid),
            ("intervalCount", NSDecimalNumber(decimal: Decimal(Int.max) + 1), false, .invalid),
            ("manifestRevision", NSDecimalNumber(decimal: Decimal(Int.min) - 1), false, .invalid),
            ("summaryID", "not-a-uuid", false, .invalid),
            ("ownership", "phone", false, .unsupported),
            ("speedTargetSource", "future", true, .unsupported),
            ("segmentIndex", NSNumber(value: 0.5), true, .invalid),
            ("observedAt", Date(timeIntervalSince1970: 1), true, .invalid)
        ]
        for (key, value, inActivity, expected) in cases {
            let input = try fixture("complete", version: 2) { raw, activity in
                var raw = self.reboxingIntegers(raw, decimalStorage: false)
                if activity == inActivity { raw[self.prefix + key] = value }
                return try self.archivedMetadata(raw, activity: activity)
            }
            XCTAssertEqual(WorkoutEnrichmentReader.read(input).recognition, expected, key)
        }
    }

    func testPartialHeartRateAndZeroEnergyRemainIndependent() {
        let statistics = WorkoutStatistics(provenance: "healthKitActivityStatistics", minimum: nil, average: 120, maximum: .infinity, energy: 0)
        XCTAssertEqual(statistics.heartRateState, "available")
        XCTAssertEqual(statistics.heartRateAverageBPM, 120)
        XCTAssertNil(statistics.heartRateMaximumBPM)
        XCTAssertEqual(statistics.activeEnergyKilocalories, 0)
        XCTAssertEqual(WorkoutHealthKitProjection.statistics(heartRate: nil, energy: nil, activity: true).heartRateState, "noDataOrAccess")
    }

    func testZoneAvailabilityAndBoundariesSurviveProjection() throws {
        var input = try fixture("complete")
        input.zones = .init(state: "available", source: "user", zones: [.init(index: 0, minimumBPM: nil, maximumBPM: 120, durationSeconds: 30)])
        let value = WorkoutEnrichmentReader.read(input)
        XCTAssertEqual(value.heartRateZones.source, "user")
        XCTAssertNil(value.heartRateZones.zones[0].minimumBPM)
        XCTAssertEqual(value.activities[0].heartRateZones.state, "unsupported")
    }

    private func v2() throws -> WorkoutEnrichmentInput {
        let input = try fixture("complete")
        var metadata = input.metadata; metadata[prefix + "interchangeSchemaVersion"] = .integer(2)
        let activities = input.activities.map { activity in
            var values = activity.metadata
            values[prefix + "intervalDistanceSchemaVersion"] = .integer(1)
            values[prefix + "intervalDistanceState"] = .string("observed")
            values[prefix + "intervalDistanceMetres"] = .decimal(0)
            values[prefix + "intervalDistanceStartCumulativeMetres"] = .decimal(10)
            values[prefix + "intervalDistanceEndCumulativeMetres"] = .decimal(10)
            values[prefix + "intervalDistanceStartObservedAt"] = .date(activity.start)
            values[prefix + "intervalDistanceEndObservedAt"] = .date(activity.end!)
            values[prefix + "intervalDistanceProvenance"] = .string("fr30zCumulativeDistanceDelta")
            return replacing(activity, metadata: values)
        }
        return replacing(input, metadata: metadata, activities: activities)
    }

    private func fixtureJSON(_ name: String, version: Int = 1) throws -> [String: Any] {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("docs/fixtures/watch-health-v\(version)/\(name).synthetic.json"))) as? [String: Any])
    }

    private func fixture(_ name: String, version: Int = 1,
                         transformMetadata: (([String: Any], Bool) throws -> [String: Any])? = nil) throws -> WorkoutEnrichmentInput {
        let root = try fixtureJSON(name, version: version)
        let expected = try XCTUnwrap(root["expected"] as? [String: Any])
        let workout = try XCTUnwrap(expected["workout"] as? [String: Any])
        func date(_ value: Any?) -> Date {
            let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return formatter.date(from: value as! String)!
        }
        func metadata(_ value: Any?, activity: Bool) throws -> [String: WorkoutMetadataValue] {
            var raw = value as! [String: Any]
            for (key, value) in raw where key.hasSuffix("observedAt") || key.hasSuffix("ObservedAt") { raw[key] = date(value) }
            if let transformMetadata { raw = try transformMetadata(raw, activity) }
            return WorkoutHealthKitProjection.metadata(raw)
        }
        func statistics(_ value: Any?, activity: Bool) -> WorkoutStatistics {
            let raw = value as! [String: Any], hr = raw["heartRate"] as? [String: Any], energy = raw["activeEnergy"] as? [String: Any]
            return .init(provenance: activity ? "healthKitActivityStatistics" : "healthKitWorkoutStatistics", minimum: hr?["minimum"] as? Double, average: hr?["average"] as? Double, maximum: hr?["maximum"] as? Double, energy: energy?["sum"] as? Double)
        }
        let activities = try (workout["activities"] as! [[String: Any]]).map {
            WorkoutActivityInput(id: UUID(uuidString: $0["activityID"] as! String)!, start: date($0["startedAt"]), end: date($0["endedAt"]), duration: $0["durationSeconds"] as! Double, activity: $0["activity"] as! String, indoor: $0["location"] as? String == "indoor", metadata: try metadata($0["metadata"], activity: true), statistics: statistics($0["statistics"], activity: true))
        }
        return WorkoutEnrichmentInput(start: date(workout["startedAt"]), end: date(workout["endedAt"]), activity: workout["activity"] as! String, metadata: try metadata(workout["metadata"], activity: false), statistics: statistics(workout["statistics"], activity: false), distanceMetres: (workout["distance"] as? [String: Any])?["metres"] as? Double, activities: activities, sourceBundleIdentifier: workout["sourceBundleIdentifier"] as? String)
    }

    private func reboxingIntegers(_ raw: [String: Any], decimalStorage: Bool) -> [String: Any] {
        raw.mapValues { value in
            guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
                  let integer = Int(exactly: number) else { return value }
            return decimalStorage ? NSDecimalNumber(decimal: Decimal(integer)) : NSNumber(value: Double(integer))
        }
    }

    /// Synthetic SDK objects only: no Health store, permissions, builder or sample queries.
    private func archivedMetadata(_ raw: [String: Any], activity: Bool) throws -> [String: Any] {
        let start = Date(timeIntervalSince1970: 0), end = start.addingTimeInterval(60)
        if activity {
            let configuration = HKWorkoutConfiguration(); configuration.activityType = .walking
            let value = HKWorkoutActivity(workoutConfiguration: configuration, start: start, end: end, metadata: raw)
            let data = try NSKeyedArchiver.archivedData(withRootObject: value, requiringSecureCoding: true)
            return try XCTUnwrap(NSKeyedUnarchiver.unarchivedObject(ofClass: HKWorkoutActivity.self, from: data)?.metadata)
        }
        let value = HKWorkout(activityType: .walking, start: start, end: end, workoutEvents: nil,
                              totalEnergyBurned: nil, totalDistance: nil, metadata: raw)
        let data = try NSKeyedArchiver.archivedData(withRootObject: value, requiringSecureCoding: true)
        return try XCTUnwrap(NSKeyedUnarchiver.unarchivedObject(ofClass: HKWorkout.self, from: data)?.metadata)
    }

    private func replacing(_ input: WorkoutEnrichmentInput, metadata: [String: WorkoutMetadataValue]? = nil, activities: [WorkoutActivityInput]? = nil) -> WorkoutEnrichmentInput {
        .init(start: input.start, end: input.end, activity: input.activity, metadata: metadata ?? input.metadata, statistics: input.statistics, distanceMetres: input.distanceMetres, activities: activities ?? input.activities, zones: input.zones)
    }
    private func replacing(_ input: WorkoutActivityInput, metadata: [String: WorkoutMetadataValue]? = nil, start: Date? = nil, end: Date? = nil, removeEnd: Bool = false) -> WorkoutActivityInput {
        .init(id: input.id, start: start ?? input.start, end: removeEnd ? nil : end ?? input.end, duration: input.duration, activity: input.activity, indoor: input.indoor, metadata: metadata ?? input.metadata, statistics: input.statistics, zones: input.zones)
    }
}

extension WorkoutEnrichmentTests {
    func testV3AcceptedAggregateRetainsExactDecimalAndIndependentNativeDecision() throws {
        let input = try acceptedV3("100.125")
        let value = WorkoutEnrichmentReader.read(input)
        XCTAssertEqual(value.recognition, .supportedComplete)
        XCTAssertEqual(value.acceptedDistance?.metres, Decimal(string: "100.125"))
        XCTAssertEqual(value.acceptedDistance?.evidence, "producerMetadataV3")
        XCTAssertEqual(value.nativeDistanceSample?.reason, "pauseOverlap")
        XCTAssertNil(value.distanceMetres)
        XCTAssertEqual(value.activities[0].pacePrompt?.intervalDistance.metres, 40)
        XCTAssertTrue(WorkoutEnrichmentReader.validatesExport(value))
        let zero = WorkoutEnrichmentReader.read(try acceptedV3("0", reason: "zeroAggregate"))
        XCTAssertEqual(zero.acceptedDistance?.metres, 0)
        XCTAssertEqual(zero.acceptedDistance?.state, "accepted")
        XCTAssertTrue(WorkoutEnrichmentReader.validatesExport(zero))
    }

    func testV3TrustAndContradictoryHeaderFailClosedWithoutLegacyFallback() throws {
        var foreign = try acceptedV3("100")
        foreign.sourceBundleIdentifier = "com.example.foreign"
        let result = WorkoutEnrichmentReader.read(foreign)
        XCTAssertEqual(result.recognition, .invalid)
        XCTAssertEqual(result.acceptedDistance?.reason, "unsupportedSource")
        XCTAssertTrue(result.activities.allSatisfy { $0.pacePrompt == nil })
        XCTAssertNotNil(result.statistics.activeEnergyKilocalories)
        XCTAssertNil(LegacyWorkoutDistanceRequest.make(workoutID: UUID(), source: "com.otherweather.PromptPace", enrichment: result))
        XCTAssertTrue(WorkoutEnrichmentReader.validatesExport(result))
        for (key, wrong) in [("nativeDistanceSampleReason", WorkoutMetadataValue.string("zeroAggregate")),
                             ("acceptedDistanceSchemaVersion", .decimal(1.5)), ("acceptedDistanceMetres", .decimal(100)),
                             ("acceptedDistanceReason", .string("notAccepted")), ("nativeDistanceSampleState", .string("included"))] {
            let input = try acceptedV3("100")
            var fields = input.metadata; fields[prefix + key] = wrong
            var changed = replacing(input, metadata: fields); changed.sourceBundleIdentifier = input.sourceBundleIdentifier
            let invalid = WorkoutEnrichmentReader.read(changed)
            XCTAssertEqual(invalid.recognition, .invalid, key)
            XCTAssertEqual(invalid.acceptedDistance?.reason, "invalidEvidence", key)
            XCTAssertNil(invalid.nativeDistanceSample, key)
        }
    }

    func testV3ValidatedAggregateSurvivesInvalidIntervalButNotInvalidIdentity() throws {
        let input = try acceptedV3("100")
        var fields = input.activities[0].metadata; fields[prefix + "observedSpeedKilometresPerHour"] = .decimal(99)
        var changed = replacing(input, activities: [replacing(input.activities[0], metadata: fields), input.activities[1]])
        changed.sourceBundleIdentifier = input.sourceBundleIdentifier
        let result = WorkoutEnrichmentReader.read(changed)
        XCTAssertEqual(result.recognition, .invalid)
        XCTAssertEqual(result.acceptedDistance?.metres, 100)
        XCTAssertTrue(result.activities.allSatisfy { $0.pacePrompt == nil })
        XCTAssertTrue(WorkoutEnrichmentReader.validatesExport(result))
        var bad = input.metadata; bad[prefix + "summaryID"] = .string("invalid")
        changed = replacing(input, metadata: bad); changed.sourceBundleIdentifier = input.sourceBundleIdentifier
        XCTAssertEqual(WorkoutEnrichmentReader.read(changed).acceptedDistance?.reason, "invalidEvidence")
    }

    func testCanonicalAggregateDecimalRejectsRoundingAndNoncanonicalForms() {
        for valid in ["0", "0.125", "100", "12345678901234567890123456789012345678"] {
            XCTAssertNotNil(WorkoutAcceptedDistancePolicy.canonicalDecimal(valid), valid)
        }
        for bad in ["-0", "-1", "+1", "01", "1.0", "1.", ".5", "1e3", "NaN", "inf", " 1", "1 ",
                    "123456789012345678901234567890123456789123456789", "0." + String(repeating: "0", count: 130) + "1",
                    String(repeating: "9", count: 257)] {
            XCTAssertNil(WorkoutAcceptedDistancePolicy.canonicalDecimal(bad), bad)
        }
    }

    func testLegacyRecoveryKeepsPersistedQuantitySeparateFromNativeStatistic() async throws {
        let request = legacyRequest(1)
        let sample = legacySample(request, metres: 100)
        let result = try await LegacyWorkoutDistanceRecovery.resolve([request]) { requests, limit in
            XCTAssertEqual(requests, [request]); XCTAssertEqual(limit, 3); return [sample]
        }
        XCTAssertEqual(result[request.workoutID], .accepted(100, evidence: "recoveredLegacyAssociatedSample"))
        XCTAssertEqual(LegacyWorkoutDistanceRecovery.validate([], request: request).reason, "noDataOrAccess")
        XCTAssertEqual(LegacyWorkoutDistanceRecovery.validate([sample, sample], request: request).reason, "invalidEvidence")
        for bad in [legacySample(request, metres: 0), legacySample(request, metres: -.infinity), legacySample(request, metres: .nan),
                    legacySample(request, source: "com.example.foreign"), legacySample(request, version: 2),
                    legacySample(request, offset: 0.0001), legacySample(request, sync: "foreign")] {
            XCTAssertEqual(LegacyWorkoutDistanceRecovery.validate([bad], request: request).reason, "invalidEvidence")
        }
    }

    func testLegacyRecoveryBatchesAndRejectsAmbiguousOrTruncatedQueries() async throws {
        let requests = (1...65).map(legacyRequest)
        var sizes: [Int] = []
        let result = try await LegacyWorkoutDistanceRecovery.resolve(requests) { batch, limit in
            sizes.append(batch.count); XCTAssertEqual(limit, 2 * batch.count + 1)
            return batch.map { self.legacySample($0) }
        }
        XCTAssertEqual(sizes, [32, 32, 1]); XCTAssertEqual(result.count, 65)
        XCTAssertTrue(result.values.allSatisfy { $0.state == "accepted" })
        let request = requests[0]
        let duplicates = try await LegacyWorkoutDistanceRecovery.resolve([request, request]) { _, _ in XCTFail("Duplicate summary must not query"); return [] }
        XCTAssertEqual(duplicates[request.workoutID]?.reason, "invalidEvidence")
        let truncated = try await LegacyWorkoutDistanceRecovery.resolve([request]) { _, limit in Array(repeating: self.legacySample(request), count: limit) }
        XCTAssertEqual(truncated[request.workoutID]?.reason, "invalidEvidence")
        enum QueryFailure: Error { case failed }
        do { _ = try await LegacyWorkoutDistanceRecovery.resolve([request]) { _, _ in throw QueryFailure.failed }; XCTFail("Error must block export") }
        catch QueryFailure.failed {}
        let cancelled = Task {
            try await LegacyWorkoutDistanceRecovery.resolve([request]) { _, _ in
                withUnsafeCurrentTask { $0?.cancel() }; return [self.legacySample(request)]
            }
        }
        do { _ = try await cancelled.value; XCTFail("Cancellation must block export") } catch is CancellationError {}
    }

    private func acceptedV3(_ metres: String, reason: String = "pauseOverlap") throws -> WorkoutEnrichmentInput {
        let input = try fixture("complete", version: 2)
        var fields = input.metadata
        fields[prefix + "interchangeSchemaVersion"] = .integer(3)
        fields[prefix + "distanceProvenance"] = .string("unavailable")
        fields[prefix + "acceptedDistanceSchemaVersion"] = .integer(1)
        fields[prefix + "acceptedDistanceState"] = .string("accepted")
        fields[prefix + "acceptedDistanceMetres"] = .string(metres)
        fields[prefix + "acceptedDistanceProvenance"] = .string("fr30zCumulativeDistanceDelta")
        fields[prefix + "nativeDistanceSampleState"] = .string("suppressed")
        fields[prefix + "nativeDistanceSampleReason"] = .string(reason)
        var result = replacing(input, metadata: fields)
        result.sourceBundleIdentifier = "com.otherweather.PromptPace.watchkitapp"
        return result
    }

    private func legacyRequest(_ index: Int) -> LegacyWorkoutDistanceRequest {
        .init(workoutID: UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d", index))!,
              summaryID: String(format: "00000000-0000-4000-8001-%012d", index), sourceBundleIdentifier: "com.otherweather.PromptPace.watchkitapp",
              start: Date(timeIntervalSince1970: 1_700_000_000.1234), end: Date(timeIntervalSince1970: 1_700_000_010.123))
    }
    private func legacySample(_ request: LegacyWorkoutDistanceRequest, metres: Double = 100, source: String? = nil, version: Int = 1, offset: TimeInterval = 0, sync: String? = nil) -> LegacyWorkoutDistanceSample {
        .init(id: UUID(), syncIdentifier: sync ?? request.syncIdentifier, syncVersion: version,
              sourceBundleIdentifier: source ?? request.sourceBundleIdentifier,
              start: LegacyWorkoutDistanceRecovery.legacyDate(request.start)!.addingTimeInterval(offset),
              end: LegacyWorkoutDistanceRecovery.legacyDate(request.end)!, metres: metres)
    }
}

extension WorkoutEnrichmentTests {
    func testNativeLegacySampleProjectionPreservesQuantityAndSemanticSyncVersion() throws {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        for (number, expected) in [(NSNumber(value: 1), Int?.some(1)), (NSNumber(value: 1.0), 1),
                                   (NSNumber(value: 1.5), nil), (NSNumber(value: true), nil)] {
            let sample = HKQuantitySample(type: HKQuantityType(.distanceWalkingRunning), quantity: HKQuantity(unit: .meter(), doubleValue: 100.125), start: start, end: start.addingTimeInterval(10), metadata: [HKMetadataKeySyncIdentifier: "synthetic-distance", HKMetadataKeySyncVersion: number])
            let bytes = try NSKeyedArchiver.archivedData(withRootObject: sample, requiringSecureCoding: true)
            let native = try XCTUnwrap(NSKeyedUnarchiver.unarchivedObject(ofClass: HKQuantitySample.self, from: bytes))
            let projected = WorkoutHealthKitProjection.legacyDistanceSample(native)
            XCTAssertEqual(projected.syncVersion, expected)
            XCTAssertEqual(projected.syncIdentifier, "synthetic-distance")
            XCTAssertEqual(projected.metres, 100.125)
            XCTAssertEqual(projected.start, start)
            XCTAssertEqual(projected.end, start.addingTimeInterval(10))
            XCTAssertEqual(projected.id, native.uuid)
        }
    }

    func testLegacyQueryEligibilityRequiresValidatedHeaderAndTrustedNativeSource() throws {
        var input = try fixture("complete", version: 2)
        input.sourceBundleIdentifier = "com.otherweather.PromptPace.watchkitapp"
        let value = WorkoutEnrichmentReader.read(input)
        XCTAssertNotNil(LegacyWorkoutDistanceRequest.make(workoutID: UUID(), source: input.sourceBundleIdentifier!, enrichment: value))
        XCTAssertNil(LegacyWorkoutDistanceRequest.make(workoutID: UUID(), source: "com.example.foreign", enrichment: value))
        let untrusted = WorkoutEnrichmentReader.read(try fixture("complete", version: 2))
        XCTAssertEqual(untrusted.recognition, .supportedComplete)
        XCTAssertEqual(untrusted.acceptedDistance?.reason, "unsupportedSource")
        XCTAssertNil(LegacyWorkoutDistanceRequest.make(workoutID: UUID(), source: "com.otherweather.PromptPace.watchkitapp", enrichment: untrusted))
        var metadata = input.metadata; metadata[prefix + "manifestRevision"] = .integer(-1)
        var bad = replacing(input, metadata: metadata); bad.sourceBundleIdentifier = input.sourceBundleIdentifier
        XCTAssertNil(LegacyWorkoutDistanceRequest.make(workoutID: UUID(), source: input.sourceBundleIdentifier!, enrichment: WorkoutEnrichmentReader.read(bad)))
    }
}

extension WorkoutEnrichmentTests {
    func testExactSharedV3FixturesPreserveAcceptedAndNativeDistancesIndependently() throws {
        for (name, accepted, native, reason) in [
            ("paused", Decimal?.some(100), Double?.none, "pauseOverlap"),
            ("submillisecond", Decimal(string: "30.625"), nil, "pauseOverlap"),
            ("safe", Decimal(string: "30.625"), 30.625, ""),
            ("zero", Decimal?.some(0), nil, "zeroAggregate"),
            ("incomplete", nil, nil, "notAccepted")
        ] {
            let input = try fixture(name, version: 3)
            let value = WorkoutEnrichmentReader.read(input)
            XCTAssertEqual(value.recognition, name == "incomplete" ? .supportedIncomplete : .supportedComplete, name)
            XCTAssertEqual(value.acceptedDistance?.metres, accepted, name)
            XCTAssertEqual(value.distanceMetres, native, name)
            XCTAssertEqual(value.nativeDistanceSample?.reason ?? "", reason, name)
            XCTAssertTrue(WorkoutEnrichmentReader.validatesExport(value), name)
            XCTAssertNil(LegacyWorkoutDistanceRequest.make(workoutID: UUID(), source: input.sourceBundleIdentifier!, enrichment: value), name)
            let roundTrip = try fixture(name, version: 3) { raw, activity in
                try self.archivedMetadata(self.reboxingIntegers(raw, decimalStorage: true), activity: activity)
            }
            XCTAssertEqual(WorkoutEnrichmentReader.read(roundTrip), value, name)
        }
    }
}

extension WorkoutEnrichmentTests {
    func testLegacyDistanceConversionRoundTripsPersistedDoubleOrRejectsUnrepresentableValue() throws {
        let request = legacyRequest(1)
        let metres = 100.12345678901234
        let result = LegacyWorkoutDistanceRecovery.validate([legacySample(request, metres: metres)], request: request)
        let value = try XCTUnwrap(result.metres)
        XCTAssertEqual(Double(NSDecimalNumber(decimal: value).stringValue), metres)
        XCTAssertEqual(value, Decimal(string: "100.12345678901234"))
        for unsupported in [1e200, 1e-200] {
            XCTAssertEqual(LegacyWorkoutDistanceRecovery.validate([legacySample(request, metres: unsupported)], request: request).reason, "invalidEvidence")
        }
    }

    func testLegacyHeadersRejectV3OnlyMetadataBeforeRecoveryEligibility() throws {
        for version in [1, 2] {
            for key in ["acceptedDistanceSchemaVersion", "acceptedDistanceMetres", "nativeDistanceSampleState"] {
                let input = try fixture("complete", version: version)
                var metadata = input.metadata; metadata[prefix + key] = .string("invented")
                var changed = replacing(input, metadata: metadata); changed.sourceBundleIdentifier = "com.otherweather.PromptPace.watchkitapp"
                let result = WorkoutEnrichmentReader.read(changed)
                XCTAssertEqual(result.recognition, .invalid)
                XCTAssertEqual(result.acceptedDistance?.reason, "invalidEvidence")
                XCTAssertNil(LegacyWorkoutDistanceRequest.make(workoutID: UUID(), source: changed.sourceBundleIdentifier!, enrichment: result))
            }
        }
    }
}

extension WorkoutEnrichmentTests {
    func testDisabledSummaryOrBasicExportRecoveryNeverInvokesSampleCapability() async throws {
        let result = try await LegacyWorkoutDistanceRecovery.resolve([legacyRequest(1)], enabled: false) { _, _ in
            XCTFail("Weekly/context/basic exports must not query associated samples")
            return []
        }
        XCTAssertTrue(result.isEmpty)
    }
}

extension WorkoutEnrichmentTests {
    func testRecoveredExportCannotClaimPrecisionBeyondPersistedDouble() {
        let impossible = WorkoutAcceptedDistance.accepted(Decimal(string: "100.12345678901234123456789")!, evidence: "recoveredLegacyAssociatedSample")
        XCTAssertFalse(impossible.isValid)
        XCTAssertTrue(WorkoutAcceptedDistance.accepted(Decimal(string: "100.12345678901234")!, evidence: "recoveredLegacyAssociatedSample").isValid)
        XCTAssertTrue(WorkoutAcceptedDistance.accepted(Decimal(string: "100.12345678901234123456789")!, evidence: "producerMetadataV3").isValid)
    }
}

extension WorkoutEnrichmentTests {
    func testExplicitIncompleteV3HeaderCannotClaimConfirmedAggregate() throws {
        let input = try acceptedV3("100")
        var metadata = input.metadata; metadata[prefix + "interchangeStatus"] = .string("incomplete")
        var incomplete = replacing(input, metadata: metadata); incomplete.sourceBundleIdentifier = input.sourceBundleIdentifier
        let result = WorkoutEnrichmentReader.read(incomplete)
        XCTAssertEqual(result.recognition, .invalid)
        XCTAssertEqual(result.acceptedDistance?.reason, "invalidEvidence")
        XCTAssertNil(result.nativeDistanceSample)
        var missing = replacing(input, activities: Array(input.activities.prefix(1))); missing.sourceBundleIdentifier = input.sourceBundleIdentifier
        let visiblePrefix = WorkoutEnrichmentReader.read(missing)
        XCTAssertEqual(visiblePrefix.recognition, .supportedIncomplete)
        XCTAssertEqual(visiblePrefix.acceptedDistance?.metres, 100)
        XCTAssertTrue(WorkoutEnrichmentReader.validatesExport(visiblePrefix))
    }
}

extension WorkoutEnrichmentTests {
    func testMeasuredCompanionSourceAliasDoesNotAllowMixedSampleOwnership() throws {
        var input = try acceptedV3("100")
        input.sourceBundleIdentifier = "com.otherweather.PromptPace"
        XCTAssertEqual(WorkoutEnrichmentReader.read(input).acceptedDistance?.metres, 100)
        let original = legacyRequest(1)
        let companion = LegacyWorkoutDistanceRequest(workoutID: original.workoutID, summaryID: original.summaryID,
            sourceBundleIdentifier: "com.otherweather.PromptPace", start: original.start, end: original.end)
        XCTAssertEqual(LegacyWorkoutDistanceRecovery.validate([legacySample(companion)], request: companion).metres, 100)
        XCTAssertEqual(LegacyWorkoutDistanceRecovery.validate([legacySample(companion, source: "com.otherweather.PromptPace.watchkitapp")], request: companion).reason, "invalidEvidence")
        XCTAssertEqual(LegacyWorkoutDistanceRecovery.validate([legacySample(original, source: "com.otherweather.PromptPace")], request: original).reason, "invalidEvidence")
        for foreign in ["com.example.foreign", "com.otherweather.PromptPace.other", ""] {
            input.sourceBundleIdentifier = foreign
            XCTAssertEqual(WorkoutEnrichmentReader.read(input).acceptedDistance?.reason, "unsupportedSource")
        }
    }
}

extension WorkoutEnrichmentTests {
    func testProducerCanonicalDecimalExponentExtremesRetainExactValues() throws {
        for (exponent, canonical) in [(127, "1" + String(repeating: "0", count: 127)),
                                      (-128, "0." + String(repeating: "0", count: 127) + "1")] {
            let producerValue = try XCTUnwrap(Decimal(string: "1e\(exponent)", locale: Locale(identifier: "en_US_POSIX")))
            XCTAssertEqual(NSDecimalNumber(decimal: producerValue).stringValue, canonical)
            XCTAssertEqual(WorkoutAcceptedDistancePolicy.canonicalDecimal(canonical), producerValue)
            let accepted = WorkoutEnrichmentReader.read(try acceptedV3(canonical))
            XCTAssertEqual(accepted.acceptedDistance?.metres, producerValue)
            XCTAssertTrue(WorkoutEnrichmentReader.validatesExport(accepted))
        }
        XCTAssertNil(WorkoutAcceptedDistancePolicy.canonicalDecimal("1" + String(repeating: "0", count: 166)))
        XCTAssertNil(WorkoutAcceptedDistancePolicy.canonicalDecimal("0." + String(repeating: "0", count: 128) + "1"))
    }
}
