import Foundation

/// SDK-independent inputs; unknown values are retained only as an invalid type marker.
enum WorkoutMetadataValue: Equatable {
    case string(String), integer(Int), decimal(Decimal), date(Date), invalid
}

struct WorkoutStatistics: Codable, Equatable {
    let provenance: String
    let heartRateMinimumBPM: Double?
    let heartRateAverageBPM: Double?
    let heartRateMaximumBPM: Double?
    let activeEnergyKilocalories: Double?
    let energyInterpretation: String = "healthKitCalculationEstimate"
    var heartRateState: String {
        [heartRateMinimumBPM, heartRateAverageBPM, heartRateMaximumBPM].contains { $0 != nil }
            ? "available" : "noDataOrAccess"
    }
    var energyState: String { activeEnergyKilocalories == nil ? "noDataOrAccess" : "available" }

    init(provenance: String, minimum: Double? = nil, average: Double? = nil,
         maximum: Double? = nil, energy: Double? = nil) {
        self.provenance = provenance
        func visible(_ value: Double?) -> Double? {
            value.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
        }
        heartRateMinimumBPM = visible(minimum)
        heartRateAverageBPM = visible(average)
        heartRateMaximumBPM = visible(maximum)
        activeEnergyKilocalories = visible(energy)
    }

    private enum CodingKeys: String, CodingKey {
        case provenance
        case heartRateMinimumBPM = "heartRateMinimumBpm"
        case heartRateAverageBPM = "heartRateAverageBpm"
        case heartRateMaximumBPM = "heartRateMaximumBpm"
        case activeEnergyKilocalories, energyInterpretation, heartRateState, energyState
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(provenance: try c.decode(String.self, forKey: .provenance),
                  minimum: try c.decodeIfPresent(Double.self, forKey: .heartRateMinimumBPM),
                  average: try c.decodeIfPresent(Double.self, forKey: .heartRateAverageBPM),
                  maximum: try c.decodeIfPresent(Double.self, forKey: .heartRateMaximumBPM),
                  energy: try c.decodeIfPresent(Double.self, forKey: .activeEnergyKilocalories))
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(provenance, forKey: .provenance)
        try c.encodeIfPresent(heartRateMinimumBPM, forKey: .heartRateMinimumBPM)
        try c.encodeIfPresent(heartRateAverageBPM, forKey: .heartRateAverageBPM)
        try c.encodeIfPresent(heartRateMaximumBPM, forKey: .heartRateMaximumBPM)
        try c.encodeIfPresent(activeEnergyKilocalories, forKey: .activeEnergyKilocalories)
        try c.encode(energyInterpretation, forKey: .energyInterpretation)
        try c.encode(heartRateState, forKey: .heartRateState)
        try c.encode(energyState, forKey: .energyState)
    }
}

struct WorkoutHeartRateZones: Codable, Equatable {
    struct Zone: Codable, Equatable {
        let index: Int
        let minimumBPM: Double?
        let maximumBPM: Double?
        let durationSeconds: Double
        private enum CodingKeys: String, CodingKey {
            case index, durationSeconds
            case minimumBPM = "minimumBpm"
            case maximumBPM = "maximumBpm"
        }
    }
    let state: String
    let source: String?
    let zones: [Zone]
    static let unsupported = Self(state: "unsupported", source: nil, zones: [])
    static let noDataOrAccess = Self(state: "noDataOrAccess", source: nil, zones: [])

    var isValid: Bool {
        if ["unsupported", "noDataOrAccess"].contains(state) { return source == nil && zones.isEmpty }
        guard state == "available", let source, ["system", "user", "app"].contains(source), !zones.isEmpty else { return false }
        for (offset, zone) in zones.enumerated() {
            guard zone.index >= 0, zone.durationSeconds.isFinite, zone.durationSeconds >= 0,
                  [zone.minimumBPM, zone.maximumBPM].allSatisfy({ $0 == nil || ($0!.isFinite && $0! >= 0) }),
                  offset == 0 || zone.minimumBPM != nil,
                  offset == zones.count - 1 || zone.maximumBPM != nil else { return false }
            if let minimum = zone.minimumBPM, let maximum = zone.maximumBPM, minimum >= maximum { return false }
            if offset > 0 {
                let previous = zones[offset - 1]
                guard zone.index > previous.index, previous.maximumBPM == zone.minimumBPM else { return false }
            }
        }
        return true
    }
}

struct WorkoutActivityInput: Equatable {
    let id: UUID
    let start: Date
    let end: Date?
    let duration: Double
    let activity: String
    let indoor: Bool
    let metadata: [String: WorkoutMetadataValue]
    let statistics: WorkoutStatistics
    var zones: WorkoutHeartRateZones = .unsupported
}

struct WorkoutEnrichmentInput: Equatable {
    let start: Date
    let end: Date
    let activity: String
    let metadata: [String: WorkoutMetadataValue]
    let statistics: WorkoutStatistics
    let distanceMetres: Double?
    let activities: [WorkoutActivityInput]
    var zones: WorkoutHeartRateZones = .unsupported
    var sourceBundleIdentifier: String? = nil
}

struct WorkoutIntervalDistance: Codable, Equatable {
    let schemaVersion: Int
    let state: String
    let reason: String?
    let metres: Decimal?
    let startCumulativeMetres: Decimal?
    let endCumulativeMetres: Decimal?
    let startObservedAt: Date?
    let endObservedAt: Date?
    let provenance: String?
    let coverage: String?
    static func unavailable(_ reason: String) -> Self {
        Self(schemaVersion: 1, state: "unavailable", reason: reason, metres: nil,
             startCumulativeMetres: nil, endCumulativeMetres: nil,
             startObservedAt: nil, endObservedAt: nil, provenance: nil, coverage: nil)
    }
}

struct PacePromptInterval: Codable, Equatable {
    let segmentIndex: Int
    let intervalIndex: Int
    let prescribedSegmentKind: String
    let prescribedSpeedKilometresPerHour: Decimal
    let prescribedInclinationPercent: Decimal
    let effectiveTargetSpeedKilometresPerHour: Decimal
    let effectiveTargetInclinationPercent: Decimal
    let speedTargetSource: String
    let inclinationTargetSource: String
    let observedSpeedKilometresPerHour: Decimal
    let observedInclinationPercent: Decimal
    let observedAt: Date
    let observationProvenance: String
    let intervalEndReason: String
    let intervalDistance: WorkoutIntervalDistance
}

struct EnrichedWorkoutActivity: Codable, Equatable {
    let activityID: UUID
    let startedAt: Date
    let endedAt: Date?
    let durationSeconds: Double
    let activity: String
    let location: String
    let statistics: WorkoutStatistics
    let heartRateZones: WorkoutHeartRateZones
    var pacePrompt: PacePromptInterval?
    private enum CodingKeys: String, CodingKey {
        case activityID = "activityId"
        case startedAt, endedAt, durationSeconds, activity, location, statistics, heartRateZones, pacePrompt
    }
}

struct WorkoutEnrichment: Codable, Equatable {
    enum Recognition: String, Codable { case notPacePrompt, supportedComplete, supportedIncomplete, unsupported, invalid }
    let enrichmentVersion: Int
    let activity: String
    let startedAt: Date
    let endedAt: Date
    let statistics: WorkoutStatistics
    let heartRateZones: WorkoutHeartRateZones
    let recognition: Recognition
    let interchangeSchemaVersion: Int?
    let summaryID: String?
    let ownership: String?
    let manifestRevision: Int?
    let expectedIntervalCount: Int?
    let distanceState: String
    let distanceMetres: Double?
    let distanceProvenance: String?
    let activities: [EnrichedWorkoutActivity]
    var acceptedDistance: WorkoutAcceptedDistance? = nil
    var nativeDistanceSample: WorkoutNativeDistanceSample? = nil
    private enum CodingKeys: String, CodingKey {
        case summaryID = "summaryId"
        case enrichmentVersion, activity, startedAt, endedAt, statistics, heartRateZones, recognition, interchangeSchemaVersion
        case ownership, manifestRevision, expectedIntervalCount, distanceState, distanceMetres, distanceProvenance, activities, acceptedDistance, nativeDistanceSample
    }
}

/// Recognition is all-or-prefix: invalid or unsupported suffixes never promote a mirror.
enum WorkoutEnrichmentReader {
    static let namespace = "com.otherweather.PromptPace."
    private enum Failure: Error { case invalid, unsupported }
    private struct Metadata {
        let values: [String: WorkoutMetadataValue]
        func has(_ key: String) -> Bool { values[namespace + key] != nil }
        func string(_ key: String, allowed: Set<String>? = nil) throws -> String {
            guard case .string(let value) = values[namespace + key] else { throw Failure.invalid }
            if let allowed, !allowed.contains(value) { throw Failure.unsupported }
            return value
        }
        func integer(_ key: String) throws -> Int {
            guard case .integer(let value) = values[namespace + key] else { throw Failure.invalid }
            return value
        }
        func decimal(_ key: String, nonnegative: Bool = true) throws -> Decimal {
            let value: Decimal
            switch values[namespace + key] {
            case .decimal(let number): value = number
            case .integer(let number): value = Decimal(number)
            default: throw Failure.invalid
            }
            guard !value.isNaN, !nonnegative || value >= 0 else { throw Failure.invalid }
            return value
        }
        func date(_ key: String) throws -> Date {
            guard case .date(let date) = values[namespace + key], date.timeIntervalSinceReferenceDate.isFinite
            else { throw Failure.invalid }
            return date
        }
        func uuid(_ key: String) throws -> String {
            let value = try string(key)
            guard let uuid = UUID(uuidString: value), uuid.uuidString.lowercased() == value else { throw Failure.invalid }
            return value
        }
    }

    static func read(_ input: WorkoutEnrichmentInput) -> WorkoutEnrichment {
        let metadata = Metadata(values: input.metadata)
        let version = try? metadata.integer("interchangeSchemaVersion")
        var recognition: WorkoutEnrichment.Recognition = .notPacePrompt
        var summaryID: String?
        var ownership: String?
        var revision: Int?
        var count: Int?
        var distanceProvenance: String?
        var distance: Double?
        var accepted: WorkoutAcceptedDistance = .unavailable("notPacePrompt")
        var nativeDecision: WorkoutNativeDistanceSample?
        var headerValidated = false
        var activities = input.activities.sorted { $0.start < $1.start }.map {
            EnrichedWorkoutActivity(activityID: $0.id, startedAt: $0.start, endedAt: $0.end,
                durationSeconds: $0.duration, activity: $0.activity, location: $0.indoor ? "indoor" : "otherOrUnknown",
                statistics: $0.statistics, heartRateZones: $0.zones, pacePrompt: nil)
        }
        let recognized = input.metadata.keys.contains { $0.hasPrefix(namespace) }
            || input.activities.contains { $0.metadata.keys.contains { $0.hasPrefix(namespace) } }
        if recognized {
            accepted = .unavailable("invalidEvidence")
            do {
                // Historical phone metadata must not be inferred to have Watch ownership.
                guard metadata.has("interchangeSchemaVersion") else { throw Failure.unsupported }
                guard let version else { throw Failure.invalid }
                guard [1, 2, 3].contains(version) else { throw Failure.unsupported }
                if version == 3, !WorkoutAcceptedDistancePolicy.watchPrimarySources.contains(input.sourceBundleIdentifier ?? "") {
                    accepted = .unavailable("unsupportedSource")
                    throw Failure.invalid
                }
                summaryID = try metadata.uuid("summaryID")
                ownership = try metadata.string("ownership", allowed: ["watchPrimary"])
                let status = try metadata.string("interchangeStatus", allowed: ["complete", "incomplete"])
                let declaredRevision = try metadata.integer("manifestRevision")
                let declaredCount = try metadata.integer("intervalCount")
                guard declaredRevision >= 0, (1...64).contains(declaredCount),
                      input.start < input.end, ["walking", "running"].contains(input.activity)
                else { throw Failure.invalid }
                revision = declaredRevision
                count = declaredCount
                let count = declaredCount
                distanceProvenance = try metadata.string("distanceProvenance", allowed: ["fr30zCumulativeDistanceDelta", "unavailable"])
                if version < 3, input.metadata.keys.contains(where: {
                    $0.hasPrefix(namespace + "acceptedDistance") || $0.hasPrefix(namespace + "nativeDistanceSample")
                }) { throw Failure.invalid }
                if version == 3 {
                    let parsed = try WorkoutAcceptedDistancePolicy.metadata(input.metadata, nativeProvenance: distanceProvenance!)
                    guard status == "complete" || parsed.0.state == "unavailable" else { throw Failure.invalid }
                    (accepted, nativeDecision) = parsed
                } else if distanceProvenance == "unavailable" {
                    accepted = .unavailable("notAccepted")
                } else {
                    accepted = .unavailable(WorkoutAcceptedDistancePolicy.watchPrimarySources.contains(input.sourceBundleIdentifier ?? "") ? "noDataOrAccess" : "unsupportedSource")
                }
                headerValidated = true
                if distanceProvenance == "fr30zCumulativeDistanceDelta",
                   let metres = input.distanceMetres, metres.isFinite, metres > 0 { distance = metres }
                var previousEnd = input.start
                var identities = Set<String>()
                var activityIDs = Set<UUID>()
                var previousIdentity: (segment: Int, interval: Int)?
                let sorted = input.activities.sorted { $0.start < $1.start }
                guard sorted.count <= count,
                      zip(input.activities, input.activities.dropFirst()).allSatisfy({ $0.start <= $1.start })
                else { throw Failure.invalid }
                for (index, activity) in sorted.enumerated() {
                    guard let end = activity.end, activity.start >= previousEnd, end > activity.start,
                          end <= input.end, activity.duration.isFinite, activity.duration >= 0,
                          activity.duration <= end.timeIntervalSince(activity.start) + 0.001,
                          activity.activity == input.activity, activity.indoor,
                          activityIDs.insert(activity.id).inserted else { throw Failure.invalid }
                    let interval = try interval(activity, version: version, summaryID: summaryID!)
                    guard identities.insert("\(interval.segmentIndex):\(interval.intervalIndex)").inserted
                    else { throw Failure.invalid }
                    if let previousIdentity {
                        guard interval.segmentIndex >= previousIdentity.segment,
                              interval.segmentIndex == previousIdentity.segment
                                ? interval.intervalIndex == previousIdentity.interval + 1
                                : interval.intervalIndex == 0 else { throw Failure.invalid }
                    } else if interval.intervalIndex != 0 { throw Failure.invalid }
                    previousIdentity = (interval.segmentIndex, interval.intervalIndex)
                    activities[index].pacePrompt = interval
                    previousEnd = end
                }
                recognition = status == "complete" && activities.count == count ? .supportedComplete : .supportedIncomplete
            } catch Failure.unsupported {
                recognition = .unsupported
                if !headerValidated { accepted = .unavailable("unsupportedInterchange") }
            }
            catch { recognition = .invalid }
        }
        return WorkoutEnrichment(enrichmentVersion: 2, activity: input.activity, startedAt: input.start, endedAt: input.end, statistics: input.statistics,
            heartRateZones: input.zones, recognition: recognition, interchangeSchemaVersion: version,
            summaryID: summaryID, ownership: ownership, manifestRevision: revision, expectedIntervalCount: count,
            distanceState: distance == nil ? "noDataOrAccess" : "available", distanceMetres: distance,
            distanceProvenance: distanceProvenance, activities: activities, acceptedDistance: accepted, nativeDistanceSample: nativeDecision)
    }

    /// Canonical bytes are necessary but not sufficient for recovering a remote v6 file.
    /// Reuse the reader's closed invariants; never trust a serialized complete label.
    static func validatesExport(_ value: WorkoutEnrichment) -> Bool {
        guard [1, 2].contains(value.enrichmentVersion), value.startedAt.timeIntervalSinceReferenceDate.isFinite,
              value.endedAt.timeIntervalSinceReferenceDate.isFinite, value.endedAt >= value.startedAt,
              value.statistics.provenance == "healthKitWorkoutStatistics", value.heartRateZones.isValid,
              value.ownership == nil || value.ownership == "watchPrimary",
              value.summaryID == nil || UUID(uuidString: value.summaryID!)?.uuidString.lowercased() == value.summaryID,
              value.manifestRevision == nil || value.manifestRevision! >= 0,
              value.expectedIntervalCount == nil || (1...64).contains(value.expectedIntervalCount!)
        else { return false }
        switch value.distanceState {
        case "available":
            guard let distance = value.distanceMetres, distance.isFinite, distance > 0,
                  value.distanceProvenance == "fr30zCumulativeDistanceDelta" else { return false }
        case "noDataOrAccess":
            guard value.distanceMetres == nil,
                  value.distanceProvenance == nil || ["unavailable", "fr30zCumulativeDistanceDelta"].contains(value.distanceProvenance!) else { return false }
        default: return false
        }
        if value.enrichmentVersion == 1 {
            guard value.acceptedDistance == nil, value.nativeDistanceSample == nil else { return false }
        } else if !validatesAcceptedDistance(value) { return false }
        let supported = [.supportedComplete, .supportedIncomplete].contains(value.recognition)
        if supported {
            guard value.startedAt < value.endedAt, (value.enrichmentVersion == 1 ? [1, 2] : [1, 2, 3]).contains(value.interchangeSchemaVersion ?? -1), ["walking", "running"].contains(value.activity), value.summaryID != nil,
                  value.ownership == "watchPrimary", value.manifestRevision != nil,
                  let count = value.expectedIntervalCount, value.activities.count <= count,
                  value.distanceProvenance != nil else { return false }
            if value.recognition == .supportedComplete, count != value.activities.count { return false }
        }
        if value.recognition == .notPacePrompt {
            guard value.interchangeSchemaVersion == nil, value.summaryID == nil, value.ownership == nil,
                  value.manifestRevision == nil, value.expectedIntervalCount == nil,
                  value.distanceProvenance == nil else { return false }
        }
        var previousStart: Date?
        var previousEnd = value.startedAt
        var previousIdentity: (segment: Int, interval: Int)?
        var seen = Set<UUID>()
        var foundUnrecognised = false
        for activity in value.activities {
            guard activity.startedAt.timeIntervalSinceReferenceDate.isFinite,
                  previousStart == nil || activity.startedAt >= previousStart!,
                  activity.durationSeconds.isFinite, activity.durationSeconds >= 0,
                  activity.statistics.provenance == "healthKitActivityStatistics",
                  activity.heartRateZones.isValid, seen.insert(activity.activityID).inserted,
                  ["indoor", "otherOrUnknown"].contains(activity.location) else { return false }
            previousStart = activity.startedAt
            if let projection = activity.pacePrompt {
                guard !foundUnrecognised, value.recognition != .notPacePrompt,
                      let version = value.interchangeSchemaVersion, (value.enrichmentVersion == 1 ? [1, 2] : [1, 2, 3]).contains(version),
                      let summaryID = value.summaryID, let end = activity.endedAt,
                      activity.startedAt >= previousEnd, end > activity.startedAt, end <= value.endedAt,
                      activity.durationSeconds <= end.timeIntervalSince(activity.startedAt) + 0.001,
                      ["walking", "running"].contains(activity.activity), activity.activity == value.activity, activity.location == "indoor"
                else { return false }
                let input = WorkoutActivityInput(id: activity.activityID, start: activity.startedAt, end: end,
                    duration: activity.durationSeconds, activity: activity.activity, indoor: true,
                    metadata: exportedMetadata(projection, summaryID: summaryID, version: version),
                    statistics: activity.statistics, zones: activity.heartRateZones)
                guard let checked = try? interval(input, version: version, summaryID: summaryID), checked == projection else { return false }
                if let previousIdentity {
                    guard projection.segmentIndex >= previousIdentity.segment,
                          projection.segmentIndex == previousIdentity.segment
                            ? projection.intervalIndex == previousIdentity.interval + 1
                            : projection.intervalIndex == 0 else { return false }
                } else if projection.intervalIndex != 0 { return false }
                previousIdentity = (projection.segmentIndex, projection.intervalIndex)
                previousEnd = end
            } else {
                if supported { return false }
                foundUnrecognised = true
            }
        }
        return true
    }

    private static func validatesAcceptedDistance(_ value: WorkoutEnrichment) -> Bool {
        guard let accepted = value.acceptedDistance, accepted.isValid else { return false }
        let version = value.interchangeSchemaVersion
        let header = value.summaryID != nil && value.ownership == "watchPrimary" && value.manifestRevision != nil
            && value.expectedIntervalCount != nil && value.startedAt < value.endedAt
            && ["walking", "running"].contains(value.activity) && value.distanceProvenance != nil
        if let decision = value.nativeDistanceSample {
            guard version == 3, header, decision.isValid(accepted: accepted, nativeProvenance: value.distanceProvenance) else { return false }
        }
        if accepted.state == "accepted" {
            guard header else { return false }
            if accepted.evidence == "producerMetadataV3" {
                guard version == 3, value.nativeDistanceSample != nil else { return false }
                // Equal visible/expected counts plus incomplete recognition means
                // an explicitly incomplete writer header, not missing visible activities.
                return value.recognition != .supportedIncomplete || value.expectedIntervalCount != value.activities.count
            }
            return [1, 2].contains(version ?? -1) && value.distanceProvenance == "fr30zCumulativeDistanceDelta" && value.nativeDistanceSample == nil
        }
        switch accepted.reason {
        case "notPacePrompt": return value.recognition == .notPacePrompt && value.nativeDistanceSample == nil
        case "unsupportedInterchange": return value.recognition == .unsupported && value.nativeDistanceSample == nil
        case "unsupportedSource": return value.nativeDistanceSample == nil && (version == 3 ? value.recognition == .invalid && value.activities.allSatisfy { $0.pacePrompt == nil } : [1, 2].contains(version ?? -1) && header)
        case "notAccepted": return header && (version == 3 ? value.nativeDistanceSample?.reason == "notAccepted" : [1, 2].contains(version ?? -1) && value.distanceProvenance == "unavailable")
        case "noDataOrAccess": return header && [1, 2].contains(version ?? -1) && value.distanceProvenance == "fr30zCumulativeDistanceDelta" && value.nativeDistanceSample == nil
        case "invalidEvidence": return value.nativeDistanceSample == nil && (value.recognition == .invalid || (header && [1, 2].contains(version ?? -1)))
        default: return false
        }
    }

    private static func exportedMetadata(_ value: PacePromptInterval, summaryID: String, version: Int) -> [String: WorkoutMetadataValue] {
        var fields: [String: WorkoutMetadataValue] = [
            "timelineSchemaVersion": .integer(1), "summaryID": .string(summaryID),
            "segmentIndex": .integer(value.segmentIndex), "intervalIndex": .integer(value.intervalIndex),
            "prescribedSegmentKind": .string(value.prescribedSegmentKind),
            "prescribedSpeedKilometresPerHour": .decimal(value.prescribedSpeedKilometresPerHour),
            "prescribedInclinationPercent": .decimal(value.prescribedInclinationPercent),
            "effectiveTargetSpeedKilometresPerHour": .decimal(value.effectiveTargetSpeedKilometresPerHour),
            "effectiveTargetInclinationPercent": .decimal(value.effectiveTargetInclinationPercent),
            "speedTargetSource": .string(value.speedTargetSource), "inclinationTargetSource": .string(value.inclinationTargetSource),
            "observedSpeedKilometresPerHour": .decimal(value.observedSpeedKilometresPerHour),
            "observedInclinationPercent": .decimal(value.observedInclinationPercent),
            "observedAt": .date(value.observedAt), "observationProvenance": .string(value.observationProvenance),
            "intervalEndReason": .string(value.intervalEndReason)
        ]
        if version >= 2 {
            let distance = value.intervalDistance
            fields["intervalDistanceSchemaVersion"] = .integer(distance.schemaVersion)
            fields["intervalDistanceState"] = .string(distance.state)
            fields["intervalDistanceReason"] = distance.reason.map(WorkoutMetadataValue.string)
            fields["intervalDistanceMetres"] = distance.metres.map(WorkoutMetadataValue.decimal)
            fields["intervalDistanceStartCumulativeMetres"] = distance.startCumulativeMetres.map(WorkoutMetadataValue.decimal)
            fields["intervalDistanceEndCumulativeMetres"] = distance.endCumulativeMetres.map(WorkoutMetadataValue.decimal)
            fields["intervalDistanceStartObservedAt"] = distance.startObservedAt.map(WorkoutMetadataValue.date)
            fields["intervalDistanceEndObservedAt"] = distance.endObservedAt.map(WorkoutMetadataValue.date)
            fields["intervalDistanceProvenance"] = distance.provenance.map(WorkoutMetadataValue.string)
        }
        return Dictionary(uniqueKeysWithValues: fields.map { (namespace + $0.key, $0.value) })
    }

    private static func interval(_ activity: WorkoutActivityInput, version: Int, summaryID: String) throws -> PacePromptInterval {
        let m = Metadata(values: activity.metadata)
        guard try m.integer("timelineSchemaVersion") == 1 else { throw Failure.unsupported }
        guard try m.uuid("summaryID") == summaryID else { throw Failure.invalid }
        let segment = try m.integer("segmentIndex"), interval = try m.integer("intervalIndex")
        let observed = try m.date("observedAt")
        guard segment >= 0, interval >= 0, observed == activity.start else { throw Failure.invalid }
        if version == 1, m.values.keys.contains(where: { $0.hasPrefix(namespace + "intervalDistance") }) {
            throw Failure.invalid
        }
        let sources: Set<String> = ["planned", "manualOverride"]
        let result = try PacePromptInterval(segmentIndex: segment, intervalIndex: interval,
            prescribedSegmentKind: m.string("prescribedSegmentKind", allowed: ["warmUp", "interval", "recovery", "coolDown"]),
            prescribedSpeedKilometresPerHour: m.decimal("prescribedSpeedKilometresPerHour"),
            prescribedInclinationPercent: m.decimal("prescribedInclinationPercent", nonnegative: false),
            effectiveTargetSpeedKilometresPerHour: m.decimal("effectiveTargetSpeedKilometresPerHour"),
            effectiveTargetInclinationPercent: m.decimal("effectiveTargetInclinationPercent", nonnegative: false),
            speedTargetSource: m.string("speedTargetSource", allowed: sources),
            inclinationTargetSource: m.string("inclinationTargetSource", allowed: sources),
            observedSpeedKilometresPerHour: m.decimal("observedSpeedKilometresPerHour"),
            observedInclinationPercent: m.decimal("observedInclinationPercent", nonnegative: false), observedAt: observed,
            observationProvenance: m.string("observationProvenance", allowed: ["fr30zTreadmillDataCurrentEpoch"]),
            intervalEndReason: m.string("intervalEndReason", allowed: ["planTransition", "targetChanged", "paused", "completed", "endedByUser", "interrupted", "failed"]),
            intervalDistance: version == 1 ? .unavailable("legacyInterchange") : distance(m, activity: activity))
        guard result.observedSpeedKilometresPerHour == result.effectiveTargetSpeedKilometresPerHour,
              result.observedInclinationPercent == result.effectiveTargetInclinationPercent,
              result.speedTargetSource != "planned" || result.effectiveTargetSpeedKilometresPerHour == result.prescribedSpeedKilometresPerHour,
              result.inclinationTargetSource != "planned" || result.effectiveTargetInclinationPercent == result.prescribedInclinationPercent
        else { throw Failure.invalid }
        return result
    }

    private static func distance(_ m: Metadata, activity: WorkoutActivityInput) throws -> WorkoutIntervalDistance {
        guard try m.integer("intervalDistanceSchemaVersion") == 1 else { throw Failure.unsupported }
        let state = try m.string("intervalDistanceState", allowed: ["observed", "unavailable"])
        let observedKeys = ["intervalDistanceMetres", "intervalDistanceStartCumulativeMetres", "intervalDistanceEndCumulativeMetres", "intervalDistanceStartObservedAt", "intervalDistanceEndObservedAt", "intervalDistanceProvenance"]
        if state == "unavailable" {
            guard !observedKeys.contains(where: m.has) else { throw Failure.invalid }
            let reason = try m.string("intervalDistanceReason", allowed: ["missingBoundary", "invalidDistanceEvidence", "legacyInterval"])
            guard !reason.isEmpty else { throw Failure.invalid }
            return .unavailable(reason)
        }
        guard !m.has("intervalDistanceReason") else { throw Failure.invalid }
        let start = try m.decimal("intervalDistanceStartCumulativeMetres")
        let end = try m.decimal("intervalDistanceEndCumulativeMetres")
        let metres = try m.decimal("intervalDistanceMetres")
        let startTime = try m.date("intervalDistanceStartObservedAt")
        let endTime = try m.date("intervalDistanceEndObservedAt")
        let provenance = try m.string("intervalDistanceProvenance", allowed: ["fr30zCumulativeDistanceDelta"])
        guard end >= start, metres == end - start, startTime >= activity.start,
              endTime <= activity.end!, endTime > startTime else { throw Failure.invalid }
        return WorkoutIntervalDistance(schemaVersion: 1, state: state, reason: nil, metres: metres,
            startCumulativeMetres: start, endCumulativeMetres: end, startObservedAt: startTime,
            endObservedAt: endTime, provenance: provenance,
            coverage: startTime == activity.start && endTime == activity.end ? "completeInterval" : "partialObservationWindow")
    }
}
