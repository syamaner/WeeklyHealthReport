import Foundation

/// An independently evidenced treadmill total; never a replacement for native statistics.
struct WorkoutAcceptedDistance: Codable, Equatable {
    let schemaVersion: Int
    let state: String
    let metres: Decimal?
    let provenance: String?
    let evidence: String?
    let reason: String?

    static func unavailable(_ reason: String) -> Self {
        .init(schemaVersion: 1, state: "unavailable", metres: nil, provenance: nil, evidence: nil, reason: reason)
    }
    static func accepted(_ metres: Decimal, evidence: String) -> Self {
        .init(schemaVersion: 1, state: "accepted", metres: metres, provenance: "fr30zCumulativeDistanceDelta", evidence: evidence, reason: nil)
    }
    var isValid: Bool {
        guard schemaVersion == 1 else { return false }
        if state == "accepted" {
            guard let metres, !metres.isNaN, metres >= 0, provenance == "fr30zCumulativeDistanceDelta", reason == nil else { return false }
            return evidence == "producerMetadataV3" || (evidence == "recoveredLegacyAssociatedSample"
                && WorkoutAcceptedDistancePolicy.isPersistedDoubleDecimal(metres))
        }
        return state == "unavailable" && metres == nil && provenance == nil && evidence == nil
            && ["notPacePrompt", "unsupportedInterchange", "unsupportedSource", "notAccepted", "noDataOrAccess", "invalidEvidence"].contains(reason ?? "")
    }
}

struct WorkoutNativeDistanceSample: Codable, Equatable {
    let schemaVersion: Int
    let state: String
    let reason: String?

    func isValid(accepted: WorkoutAcceptedDistance, nativeProvenance: String?) -> Bool {
        guard schemaVersion == 1, accepted.isValid else { return false }
        if state == "included" {
            return reason == nil && accepted.state == "accepted" && (accepted.metres ?? 0) > 0
                && nativeProvenance == "fr30zCumulativeDistanceDelta"
        }
        guard state == "suppressed", nativeProvenance == "unavailable" else { return false }
        switch reason {
        case "notAccepted": return accepted.state == "unavailable" && accepted.reason == "notAccepted"
        case "zeroAggregate": return accepted.state == "accepted" && accepted.metres == 0
        case "pauseOverlap", "uncertainTemporalCoverage", "writeNotAuthorized": return accepted.state == "accepted" && (accepted.metres ?? 0) > 0
        default: return false
        }
    }
}

enum WorkoutAcceptedDistancePolicy {
    // A real companion-graph simulator save/query reports the phone source ID
    // for the Watch writer. Legacy samples must still match their workout exactly.
    static let watchPrimarySources: Set<String> = ["com.otherweather.PromptPace.watchkitapp", "com.otherweather.PromptPace"]
    enum Invalid: Error { case metadata }

    static func isPersistedDoubleDecimal(_ metres: Decimal) -> Bool {
        guard !metres.isNaN, metres > 0,
              let number = Double(NSDecimalNumber(decimal: metres).stringValue), number.isFinite,
              let canonical = Decimal(string: String(number), locale: Locale(identifier: "en_US_POSIX")) else { return false }
        return canonical == metres
    }

    /// Round-trip equality rejects exponent syntax, rounding, negative zero and noncanonical decimals.
    static func canonicalDecimal(_ text: String) -> Decimal? {
        guard !text.isEmpty, text.count <= 256,
              text.range(of: #"^(0|[1-9][0-9]*)(\.[0-9]*[1-9])?$"#, options: .regularExpression) != nil,
              let value = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")), !value.isNaN, value >= 0,
              NSDecimalNumber(decimal: value).stringValue == text else { return nil }
        return value
    }

    static func metadata(_ fields: [String: WorkoutMetadataValue], nativeProvenance: String) throws -> (WorkoutAcceptedDistance, WorkoutNativeDistanceSample) {
        let n = WorkoutEnrichmentReader.namespace
        func value(_ key: String) -> WorkoutMetadataValue? { fields[n + key] }
        func string(_ key: String) throws -> String {
            guard case .string(let text) = value(key) else { throw Invalid.metadata }; return text
        }
        guard value("acceptedDistanceSchemaVersion") == .integer(1) else { throw Invalid.metadata }
        let accepted: WorkoutAcceptedDistance
        switch try string("acceptedDistanceState") {
        case "accepted":
            guard let metres = canonicalDecimal(try string("acceptedDistanceMetres")),
                  try string("acceptedDistanceProvenance") == "fr30zCumulativeDistanceDelta", value("acceptedDistanceReason") == nil else { throw Invalid.metadata }
            accepted = .accepted(metres, evidence: "producerMetadataV3")
        case "unavailable":
            guard try string("acceptedDistanceReason") == "notAccepted", value("acceptedDistanceMetres") == nil,
                  value("acceptedDistanceProvenance") == nil else { throw Invalid.metadata }
            accepted = .unavailable("notAccepted")
        default: throw Invalid.metadata
        }
        let state = try string("nativeDistanceSampleState")
        let reason: String?
        if state == "included" { guard value("nativeDistanceSampleReason") == nil else { throw Invalid.metadata }; reason = nil }
        else { reason = try string("nativeDistanceSampleReason") }
        let decision = WorkoutNativeDistanceSample(schemaVersion: 1, state: state, reason: reason)
        guard decision.isValid(accepted: accepted, nativeProvenance: nativeProvenance) else { throw Invalid.metadata }
        return (accepted, decision)
    }
}

struct LegacyWorkoutDistanceRequest: Equatable {
    let workoutID: UUID
    let summaryID: String
    let sourceBundleIdentifier: String
    let start: Date
    let end: Date
    var syncIdentifier: String { WorkoutEnrichmentReader.namespace + "distance." + summaryID }
    var isValid: Bool {
        UUID(uuidString: summaryID)?.uuidString.lowercased() == summaryID
            && WorkoutAcceptedDistancePolicy.watchPrimarySources.contains(sourceBundleIdentifier)
            && start.timeIntervalSinceReferenceDate.isFinite && end.timeIntervalSinceReferenceDate.isFinite && end > start
    }

    static func make(workoutID: UUID, source: String, enrichment: WorkoutEnrichment) -> Self? {
        guard [1, 2].contains(enrichment.interchangeSchemaVersion ?? -1),
              enrichment.acceptedDistance?.reason == "noDataOrAccess", let summary = enrichment.summaryID,
              enrichment.ownership == "watchPrimary", enrichment.manifestRevision != nil,
              enrichment.expectedIntervalCount != nil, enrichment.distanceProvenance == "fr30zCumulativeDistanceDelta",
              WorkoutAcceptedDistancePolicy.watchPrimarySources.contains(source) else { return nil }
        return .init(workoutID: workoutID, summaryID: summary, sourceBundleIdentifier: source, start: enrichment.startedAt, end: enrichment.endedAt)
    }
}

/// Only fields required to validate one associated legacy aggregate cross this boundary.
struct LegacyWorkoutDistanceSample: Equatable {
    let id: UUID
    let syncIdentifier: String?
    let syncVersion: Int?
    let sourceBundleIdentifier: String
    let start: Date
    let end: Date
    let metres: Double
}

enum LegacyWorkoutDistanceRecovery {
    static let maximumBatchSize = 32
    typealias Query = ([LegacyWorkoutDistanceRequest], Int) async throws -> [LegacyWorkoutDistanceSample]

    static func resolve(_ requests: [LegacyWorkoutDistanceRequest], enabled: Bool = true, query: Query) async throws -> [UUID: WorkoutAcceptedDistance] {
        try Task.checkCancellation()
        guard enabled else { return [:] }
        var result: [UUID: WorkoutAcceptedDistance] = [:]
        let counts = Dictionary(grouping: requests, by: \.summaryID)
        let unique = requests.filter { request in
            guard request.isValid else { result[request.workoutID] = .unavailable("invalidEvidence"); return false }
            guard counts[request.summaryID]?.count == 1 else { result[request.workoutID] = .unavailable("invalidEvidence"); return false }
            return true
        }
        for offset in stride(from: 0, to: unique.count, by: maximumBatchSize) {
            try Task.checkCancellation()
            let batch = Array(unique[offset..<min(offset + maximumBatchSize, unique.count)])
            let limit = 2 * batch.count + 1
            let rows = try await query(batch, limit)
            try Task.checkCancellation()
            if rows.count >= limit || Set(rows.map(\.id)).count != rows.count {
                for request in batch { result[request.workoutID] = .unavailable("invalidEvidence") }
                continue
            }
            let expectedIDs = Set(batch.map(\.syncIdentifier))
            if rows.contains(where: { !expectedIDs.contains($0.syncIdentifier ?? "") }) {
                for request in batch { result[request.workoutID] = .unavailable("invalidEvidence") }
                continue
            }
            for request in batch {
                let candidates = rows.filter { $0.syncIdentifier == request.syncIdentifier }
                result[request.workoutID] = validate(candidates, request: request)
            }
        }
        return result
    }

    static func validate(_ samples: [LegacyWorkoutDistanceSample], request: LegacyWorkoutDistanceRequest) -> WorkoutAcceptedDistance {
        guard request.isValid else { return .unavailable("invalidEvidence") }
        guard !samples.isEmpty else { return .unavailable("noDataOrAccess") }
        guard samples.count == 1, let sample = samples.first,
              WorkoutAcceptedDistancePolicy.watchPrimarySources.contains(request.sourceBundleIdentifier),
              sample.sourceBundleIdentifier == request.sourceBundleIdentifier,
              sample.syncIdentifier == request.syncIdentifier, sample.syncVersion == 1,
              sample.metres.isFinite, sample.metres > 0,
              sample.start == legacyDate(request.start), sample.end == legacyDate(request.end), sample.end > sample.start else { return .unavailable("invalidEvidence") }
        // Preserve the persisted Double's shortest round-tripping decimal, not
        // NSNumber.decimalValue's shorter (and potentially lossy) conversion.
        guard let metres = Decimal(string: String(sample.metres), locale: Locale(identifier: "en_US_POSIX")),
              !metres.isNaN, metres > 0,
              Double(NSDecimalNumber(decimal: metres).stringValue) == sample.metres else { return .unavailable("invalidEvidence") }
        return .accepted(metres, evidence: "recoveredLegacyAssociatedSample")
    }

    /// Reproduce the old wire's exact millisecond projection, rather than accepting a tolerance.
    static func legacyDate(_ date: Date) -> Date? {
        guard date.timeIntervalSinceReferenceDate.isFinite else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: formatter.string(from: date))
    }
}
