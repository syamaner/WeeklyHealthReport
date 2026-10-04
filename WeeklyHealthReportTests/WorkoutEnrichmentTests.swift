import XCTest
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

    private func fixture(_ name: String, version: Int = 1) throws -> WorkoutEnrichmentInput {
        let root = try fixtureJSON(name, version: version)
        let expected = try XCTUnwrap(root["expected"] as? [String: Any])
        let workout = try XCTUnwrap(expected["workout"] as? [String: Any])
        func date(_ value: Any?) -> Date {
            let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return formatter.date(from: value as! String)!
        }
        func metadata(_ value: Any?) -> [String: WorkoutMetadataValue] {
            var raw = value as! [String: Any]
            for (key, value) in raw where key.hasSuffix("observedAt") || key.hasSuffix("ObservedAt") { raw[key] = date(value) }
            return WorkoutHealthKitProjection.metadata(raw)
        }
        func statistics(_ value: Any?, activity: Bool) -> WorkoutStatistics {
            let raw = value as! [String: Any], hr = raw["heartRate"] as? [String: Any], energy = raw["activeEnergy"] as? [String: Any]
            return .init(provenance: activity ? "healthKitActivityStatistics" : "healthKitWorkoutStatistics", minimum: hr?["minimum"] as? Double, average: hr?["average"] as? Double, maximum: hr?["maximum"] as? Double, energy: energy?["sum"] as? Double)
        }
        let activities = (workout["activities"] as! [[String: Any]]).map {
            WorkoutActivityInput(id: UUID(uuidString: $0["activityID"] as! String)!, start: date($0["startedAt"]), end: date($0["endedAt"]), duration: $0["durationSeconds"] as! Double, activity: $0["activity"] as! String, indoor: $0["location"] as? String == "indoor", metadata: metadata($0["metadata"]), statistics: statistics($0["statistics"], activity: true))
        }
        return WorkoutEnrichmentInput(start: date(workout["startedAt"]), end: date(workout["endedAt"]), activity: workout["activity"] as! String, metadata: metadata(workout["metadata"]), statistics: statistics(workout["statistics"], activity: false), distanceMetres: (workout["distance"] as? [String: Any])?["metres"] as? Double, activities: activities)
    }

    private func replacing(_ input: WorkoutEnrichmentInput, metadata: [String: WorkoutMetadataValue]? = nil, activities: [WorkoutActivityInput]? = nil) -> WorkoutEnrichmentInput {
        .init(start: input.start, end: input.end, activity: input.activity, metadata: metadata ?? input.metadata, statistics: input.statistics, distanceMetres: input.distanceMetres, activities: activities ?? input.activities, zones: input.zones)
    }
    private func replacing(_ input: WorkoutActivityInput, metadata: [String: WorkoutMetadataValue]? = nil, start: Date? = nil, end: Date? = nil, removeEnd: Bool = false) -> WorkoutActivityInput {
        .init(id: input.id, start: start ?? input.start, end: removeEnd ? nil : end ?? input.end, duration: input.duration, activity: input.activity, indoor: input.indoor, metadata: metadata ?? input.metadata, statistics: input.statistics, zones: input.zones)
    }
}
