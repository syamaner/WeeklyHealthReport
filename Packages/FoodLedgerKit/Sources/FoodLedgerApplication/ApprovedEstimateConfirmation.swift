import Foundation
import FoodLedgerDomain

// Approved estimates from Your food database on Confirm and at save (estimates on catalogue v2
// sections 3.2 and 5; phase gate docs/personal-food-catalogue-estimates-v2-phase.md sections 3.3 to
// 3.5). An estimate is kept, withheld or left out; there is no route from it to a measured value.

/// What binds a candidate's estimate values to its capture manifest.
public struct ApprovedEstimateBinding: Equatable, Sendable {
    public let evidenceID: EvidenceID
    public let manifestHash: SHA256Digest

    public init(evidenceID: EvidenceID, manifestHash: SHA256Digest) {
        self.evidenceID = evidenceID; self.manifestHash = manifestHash
    }
}

/// Builds the capture manifest when a database candidate is bound to Confirm (the route's own
/// confirmation). The payload holds no time and no evidence ID, so the same release and entry give
/// the same bytes and hash every time.
public struct ApprovedEstimateManifestBuilder: Sendable {
    public static let captureMethod = "Your food database estimates as offered"
    private let ids: any LedgerIDGenerating
    private let encoder: any CanonicalEncoding
    private let digester: any Digesting

    public init(ids: any LedgerIDGenerating, encoder: any CanonicalEncoding = FoundationCanonicalJSONEncoder(),
                digester: any Digesting) {
        self.ids = ids; self.encoder = encoder; self.digester = digester
    }

    /// The inline evidence and the binding for one entry; nil when the entry has no estimate.
    public func capture(entry: PersonalFoodDatabaseEntry, file: PersonalFoodDatabaseFile, databaseRelease: SourceRelease,
                        capturedAt: Date, locale: LedgerText) throws -> (evidence: CaptureEvidence, binding: ApprovedEstimateBinding)? {
        guard let manifest = ApprovedEstimateCaptureManifest(databaseReleaseID: databaseRelease.sourceReleaseID.value,
                                                             entry: entry, corpora: file.genericCorpora) else { return nil }
        let payload = try encoder.encode(manifest)
        let hash = try digester.sha256(payload)
        let evidence = try CaptureEvidence(
            evidenceID: ids.makeID(EvidenceTag.self), kind: .labelText, capturedAt: capturedAt, locale: locale,
            captureMethod: LedgerText(Self.captureMethod),
            captureMethodVersion: LedgerText(ApprovedEstimateProvenance.captureMethodVersion),
            originalPayload: .text(LedgerText(String(decoding: payload, as: UTF8.self))), byteHash: hash)
        return (evidence, ApprovedEstimateBinding(evidenceID: evidence.evidenceID, manifestHash: hash))
    }
}

/// Reads approved-estimate evidence from stored or pending records. Other `.labelText` readers
/// select by their own `captureMethodVersion` and ignore these items, and this reader ignores theirs.
public enum ApprovedEstimateSource {
    public static func isEstimate(_ value: NutrientValue) -> Bool {
        value.provenance.contains { $0.sourceKind == .approvedEstimate }
    }

    /// The candidate's nutrient keys whose value is an approved estimate. From the candidate, never
    /// from the manifest's payload, so every rule still works when the manifest fails its hash.
    public static func estimateKeys(_ candidate: ProviderNeutralCandidate) -> Set<NutrientKey> {
        Set(candidate.nutrients.entries.filter { isEstimate($0.value) }.map(\.key))
    }

    /// Whether `saved` is the candidate's nutrients except that an estimate key may be unknown: the
    /// only shape a saved version of such a candidate takes without a nutrient correction.
    public static func matchesExceptHiddenEstimates(_ saved: NutrientSet, candidate: ProviderNeutralCandidate) -> Bool {
        let keys = estimateKeys(candidate)
        guard !keys.isEmpty else { return false }
        return zip(saved.entries, candidate.nutrients.entries).allSatisfy { stored, offered in
            stored == offered || (keys.contains(stored.key) && stored.value == .unknown(.noCompatibleSource))
        }
    }

    public static func isManifest(_ evidence: CaptureEvidence) -> Bool {
        evidence.kind == .labelText && evidence.captureMethodVersion.value == ApprovedEstimateProvenance.captureMethodVersion
    }

    public static func isLeftOut(_ evidence: CaptureEvidence) -> Bool {
        evidence.kind == .labelText && evidence.captureMethodVersion.value == ApprovedEstimateProvenance.leftOutMethodVersion
    }

    /// Whether the candidate holds an approved estimate or lists a capture manifest (a favourite whose
    /// estimates were all withheld or left out still lists its manifest).
    public static func holdsManifest(_ candidate: ProviderNeutralCandidate, evidence: [CaptureEvidence]) -> Bool {
        !estimateKeys(candidate).isEmpty || manifestEvidence(candidate, evidence: evidence) != nil
    }

    public static func manifestEvidence(_ candidate: ProviderNeutralCandidate, evidence: [CaptureEvidence]) -> CaptureEvidence? {
        evidence.first { candidate.evidenceIDs.contains($0.evidenceID) && isManifest($0) }
    }

    private static func verifiedPayload(_ evidence: CaptureEvidence, digester: any Digesting) -> Data? {
        guard case let .text(payload) = evidence.originalPayload, let hash = evidence.byteHash else { return nil }
        let data = Data(payload.value.utf8)
        return (try? digester.sha256(data)) == hash ? data : nil
    }

    /// The candidate's capture manifest when its payload hashes to its `byteHash` and to every
    /// estimate value's `responseHash`; nil when it is missing or altered ("Evidence not available").
    public static func verifiedManifest(_ candidate: ProviderNeutralCandidate, evidence: [CaptureEvidence],
                                        digester: any Digesting) -> (manifest: ApprovedEstimateCaptureManifest, evidence: CaptureEvidence)? {
        guard let stored = manifestEvidence(candidate, evidence: evidence),
              let data = verifiedPayload(stored, digester: digester),
              let manifest = ApprovedEstimateCaptureManifest.decode(data) else { return nil }
        guard manifest.entryID == candidate.recordID.value,
              manifest.databaseReleaseID == candidate.sourceReleaseID.value else { return nil }
        // The manifest must describe the candidate's own values, not merely accompany them with
        // matching identifiers: each estimated nutrient is exactly the captured estimate (amount,
        // unit, evidence record and release), and nothing else carries the provenance kind.
        for entry in candidate.nutrients.entries {
            let values = [entry.value] + entry.conflictCandidates
            guard values.contains(where: isEstimate) else { continue }
            guard entry.conflictCandidates.isEmpty, case let .augmented(exact) = entry.value, exact.provenance.count == 1,
                  let provenance = exact.provenance.first, provenance.sourceKind == .approvedEstimate,
                  provenance.evidenceID == stored.evidenceID, provenance.responseHash == stored.byteHash,
                  provenance.sourceReleaseID.value == manifest.databaseReleaseID,
                  let captured = manifest.estimate(entry.key), captured.value == exact.amount,
                  captured.unit == exact.unit.rawValue, provenance.recordID?.value == captured.evidence.id else { return nil }
        }
        return (manifest, stored)
    }

    /// The verified leave-out item of one resolution version: only the item whose version ID is the
    /// effective version's is read; earlier items may stay listed and are ignored.
    public enum LeftOutReading: Equatable, Sendable {
        case none
        case keys(Set<NutrientKey>)
        /// An item names this version but does not verify, or belongs to another manifest.
        case unavailable
    }

    public static func leftOut(resolutionVersionID: ResolutionVersionID, manifestHash: SHA256Digest?,
                               evidence: [CaptureEvidence], digester: any Digesting) -> LeftOutReading {
        var reading = LeftOutReading.none
        for item in evidence where isLeftOut(item) {
            guard case let .text(payload) = item.originalPayload else { continue }
            let data = Data(payload.value.utf8)
            // Read loosely first to find the item of this version, then verify it strictly.
            guard let decoded = ApprovedEstimateLeftOutEvidence.decode(data) else {
                if payload.value.contains(resolutionVersionID.rawValue) { reading = .unavailable }
                continue
            }
            guard decoded.resolutionVersionID == resolutionVersionID.rawValue else { continue }
            guard let hash = item.byteHash, (try? digester.sha256(data)) == hash, let manifestHash,
                  decoded.manifestSHA256 == manifestHash.value else { return .unavailable }
            reading = .keys(decoded.keys)
        }
        return reading
    }
}

/// What a reopened log's leave-out state starts from (phase gate section 3.4).
public struct ApprovedEstimateSeed: Equatable, Sendable {
    /// The keys of the effective version's verified leave-out evidence.
    public var leftOut: Set<NutrientKey>
    /// False when the manifest or the leave-out item fails its hash: every saved unknown estimate key
    /// is then frozen as unknown, and the entry shows "Evidence not available".
    public var evidenceAvailable: Bool

    public init(leftOut: Set<NutrientKey> = [], evidenceAvailable: Bool = true) {
        self.leftOut = leftOut; self.evidenceAvailable = evidenceAvailable
    }
}

/// How a saved unknown estimate key reads on a reopened log (contract section 5, stored shapes).
public enum ApprovedEstimateSavedState: Equatable, Sendable {
    /// "Left out by you": the key is in the effective version's leave-out evidence.
    case leftOutByYou
    /// "Estimate left out when this was logged": in the manifest, not in the leave-out evidence.
    case leftOutWhenLogged
    /// The manifest or leave-out evidence does not verify.
    case evidenceNotAvailable
}

extension FoodConfirmationState {
    /// The selected candidate's nutrient keys that are approved estimates.
    public var estimateKeys: Set<NutrientKey> { ApprovedEstimateSource.estimateKeys(selectedCandidate.candidate) }

    /// The selected candidate's verified capture manifest, as the service bound it; nil when the
    /// state was never bound or the manifest does not verify.
    public var estimateManifest: ApprovedEstimateCaptureManifest? {
        ApprovedEstimateSource.manifestEvidence(selectedCandidate.candidate, evidence: input.evidence)
            .flatMap { estimateManifests[$0.evidenceID] }
    }

    /// The identity the estimates are checked against.
    var estimateConfirmedIdentity: DecisiveIdentity {
        correction?.identity ?? reopened?.productVersion.identity ?? selectedCandidate.candidate.identity
    }

    /// The estimates withheld for the current details (contract section 3.2). An unbound state, or
    /// one whose manifest does not verify, withholds every estimate.
    public var withheldEstimates: [NutrientKey: ApprovedEstimateWithholding] {
        let keys = estimateKeys
        guard !keys.isEmpty else { return [:] }
        guard let manifest = estimateManifest else {
            return Dictionary(uniqueKeysWithValues: keys.map { ($0, ApprovedEstimateWithholding.evidenceUnavailable) })
        }
        let policy = ApprovedEstimateEligibility.withheld(
            manifest: manifest, records: estimateRecords, confirmed: estimateConfirmedIdentity,
            candidateBasis: selectedCandidate.candidate.identity.servingBasis)
        var result = policy.filter { keys.contains($0.key) }
        // A key the manifest does not hold cannot be checked.
        for key in keys where manifest.estimate(key) == nil { result[key] = .evidenceUnavailable }
        return result
    }

    /// The left-out keys that are saved as left out: never a withheld key (withholding wins), and
    /// only estimate keys.
    public var savedLeaveOutSet: Set<NutrientKey> {
        let keys = estimateKeys
        guard !leftOutEstimates.isEmpty, !keys.isEmpty else { return [] }
        if reopened != nil, correction == nil { return leftOutEstimates.intersection(keys) }
        return leftOutEstimates.intersection(keys).subtracting(withheldEstimates.keys)
    }

    /// The one application predicate "the log's food facts changed" (contract section 5): a
    /// correction is present, or the leave-out set differs from its seed (for a new log, is not
    /// empty). It decides only whether new records are written.
    public var foodFactsChanged: Bool { correction != nil || savedLeaveOutSet != estimateSeed.leftOut }

    private static func unknown(_ nutrients: NutrientSet, keys: Set<NutrientKey>) -> NutrientSet {
        guard !keys.isEmpty else { return nutrients }
        let entries = nutrients.entries.map { entry in
            keys.contains(entry.key) ? ((try? NutrientEntry(key: entry.key, value: .unknown(.noCompatibleSource))) ?? entry) : entry
        }
        return (try? NutrientSet(entries: entries)) ?? nutrients
    }

    /// The nutrients this state shows and saves (phase gate section 3.4). Without an estimate key it
    /// is exactly what every site read before: the correction's, else the saved, else the candidate's.
    public var effectiveNutrients: NutrientSet {
        let candidate = selectedCandidate.candidate.nutrients
        let keys = estimateKeys
        guard !keys.isEmpty else { return correction?.nutrients ?? reopened?.resolutionVersion.nutrients ?? candidate }
        guard let reopened else {
            return Self.unknown(correction?.nutrients ?? candidate,
                                keys: Set(withheldEstimates.keys).union(leftOutEstimates).intersection(keys))
        }
        let saved = reopened.resolutionVersion.nutrients
        func savedUnknown(_ key: NutrientKey) -> Bool {
            if case .unknown? = saved.entries.first(where: { $0.key == key })?.value { return true }
            return false
        }
        if let correction {
            // A correction of details re-runs the check from the manifest, so a withheld key returns
            // when its contradiction is gone. With evidence unavailable every saved unknown stays.
            var hidden = Set(withheldEstimates.keys).union(leftOutEstimates)
            if !estimateSeed.evidenceAvailable { hidden.formUnion(keys.filter(savedUnknown)) }
            return Self.unknown(correction.nutrients, keys: hidden.intersection(keys))
        }
        guard leftOutEstimates != estimateSeed.leftOut else { return saved }  // reopening alone runs nothing
        let undone = estimateSeed.leftOut.subtracting(leftOutEstimates).intersection(keys)
        let withheld = withheldEstimates
        let restored = estimateSeed.evidenceAvailable ? undone.filter { withheld[$0] == nil } : []
        let entries = saved.entries.map { entry -> NutrientEntry in
            if leftOutEstimates.contains(entry.key), keys.contains(entry.key) {
                return (try? NutrientEntry(key: entry.key, value: .unknown(.noCompatibleSource))) ?? entry
            }
            if restored.contains(entry.key), let offered = candidate.entries.first(where: { $0.key == entry.key }) { return offered }
            return entry
        }
        return (try? NutrientSet(entries: entries)) ?? saved
    }

    /// The nutrients Confirm shows and totals. For a candidate without an approved estimate it is
    /// exactly what the view read before (the correction's, else the candidate's).
    public var displayNutrients: NutrientSet {
        estimateKeys.isEmpty ? correction?.nutrients ?? selectedCandidate.candidate.nutrients : effectiveNutrients
    }

    /// Whether withholding and leaving out leave no nutrient of the log known ("Nothing to log:
    /// every value was left out"). Never true for a state without a withheld or left-out key.
    public var estimatesLeaveNothingKnown: Bool {
        guard !estimateKeys.isEmpty else { return false }
        let effective = effectiveNutrients
        let hidden = estimateKeys.filter { key in
            if case .unknown? = effective.entries.first(where: { $0.key == key })?.value { return true }
            return false
        }
        guard !hidden.isEmpty else { return false }
        return effective.entries.allSatisfy { if case .unknown = $0.value { true } else { false } }
    }

    /// How each saved unknown estimate key of a reopened log reads, before any change.
    public var savedEstimateStates: [NutrientKey: ApprovedEstimateSavedState] {
        guard let reopened else { return [:] }
        var result: [NutrientKey: ApprovedEstimateSavedState] = [:]
        for key in estimateKeys {
            guard case .unknown? = reopened.resolutionVersion.nutrients.entries.first(where: { $0.key == key })?.value else { continue }
            result[key] = !estimateSeed.evidenceAvailable ? .evidenceNotAvailable
                : estimateSeed.leftOut.contains(key) ? .leftOutByYou : .leftOutWhenLogged
        }
        return result
    }

    /// A rebuilt state keeps the leave-out set and what was bound (phase gate section 3.4).
    public func carryingEstimateState(from other: FoodConfirmationState) -> FoodConfirmationState {
        var copy = self
        copy.leftOutEstimates = other.leftOutEstimates
        copy.estimateRecords = other.estimateRecords
        copy.estimateManifests = other.estimateManifests
        copy.estimateSeed = other.estimateSeed
        return copy
    }
}

/// The persisted texts of a leave-out save (phase gate section 3.5): data, not UI copy.
public enum ApprovedEstimateLeaveOutText {
    public static let reason = "Changed left-out estimated values under \(ApprovedEstimateProvenance.leftOutMethodVersion)"
    public static let editReason = "Estimated values left out or restored"

    static func keys(_ keys: Set<NutrientKey>) -> String {
        keys.isEmpty ? "none" : keys.map(\.rawValue).sorted().joined(separator: ", ")
    }

    public static func claim(_ keys: Set<NutrientKey>) -> String { "Estimated values left out: \(Self.keys(keys))" }
    public static func claimSuffix(_ keys: Set<NutrientKey>) -> String { "; estimated values left out: \(Self.keys(keys))" }
}
