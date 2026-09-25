import Foundation
import FoodLedgerDomain

public protocol FoodReresolutionReading: FoodConfirmationReading {
    func currentRecords() throws -> [StoredFoodConfirmation]
    func resolutionLineage(_ id: ResolutionID) throws -> [NutritionResolutionVersion]
    func operation(_ id: OperationID) throws -> LedgerOperation?
    func audit(_ id: LogItemID) throws -> FoodReresolutionAudit
    func evidence(_ id: EvidenceID) throws -> CaptureEvidence?
}

public struct FoodReresolutionAudit: Sendable {
    public let logVersions: [LogItemVersion]
    public let resolutionVersions: [NutritionResolutionVersion]
    public let evidence: [CaptureEvidence]
}

/// Read projection over the existing ledger capabilities, shared by both stores.
public struct FoodReresolutionHistory: FoodReresolutionReading {
    private let archive: any FoodArchiveLedgerAccess
    private let confirmations: any FoodConfirmationReading

    public init(archive: any FoodArchiveLedgerAccess, confirmations: any FoodConfirmationReading) {
        self.archive = archive
        self.confirmations = confirmations
    }

    public func currentRecords() throws -> [StoredFoodConfirmation] {
        try archive.archiveState().records.logItems.sorted { $0.logItemID.rawValue < $1.logItemID.rawValue }
            .compactMap { try foodConfirmation(logItemID: $0.logItemID) }
    }

    public func foodConfirmation(logItemID: LogItemID) throws -> StoredFoodConfirmation? {
        let versions = try archive.archiveState().records.logItemVersions.filter { $0.logItemID == logItemID }
        let superseded = Set(versions.compactMap(\.supersedesLogItemVersionID))
        let heads = versions.filter { !superseded.contains($0.logItemVersionID) }
        guard heads.count <= 1 else { throw FoodReresolutionError.staleProposal }
        guard let head = heads.first else { return nil }
        guard case .product = head.composition else { return nil }
        guard let record = try confirmations.foodConfirmation(logItemID: logItemID),
              record.logItemVersion.logItemVersionID == head.logItemVersionID else { throw FoodReresolutionError.staleProposal }
        return record
    }

    public func sourceRelease(id: ExternalIdentifier) throws -> SourceRelease? { try confirmations.sourceRelease(id: id) }
    public func operation(_ id: OperationID) throws -> LedgerOperation? { try archive.operation(id: id) }
    public func evidence(_ id: EvidenceID) throws -> CaptureEvidence? {
        try archive.archiveState().records.evidence.first { $0.evidenceID == id }
    }
    public func resolutionLineage(_ id: ResolutionID) throws -> [NutritionResolutionVersion] {
        try archive.archiveState().records.resolutionVersions.filter { $0.resolutionID == id }
    }

    public func audit(_ id: LogItemID) throws -> FoodReresolutionAudit {
        let records = try archive.archiveState().records
        let logs = records.logItemVersions.filter { $0.logItemID == id }.sorted { $0.ordinal.value < $1.ordinal.value }
        let resolutionIDs = Set(logs.flatMap { [$0.originalResolutionVersionID, $0.effectiveResolutionVersionID] })
        let resolutions = records.resolutionVersions.filter { resolutionIDs.contains($0.resolutionVersionID) }
            .sorted { $0.resolutionVersionID.rawValue < $1.resolutionVersionID.rawValue }
        let productIDs = Set(logs.compactMap { log -> ProductVersionID? in
            if case let .product(id) = log.composition { return id }; return nil
        })
        let decisionIDs = Set(resolutions.flatMap(\.decisionIDs))
        let evidenceIDs = Set(records.productVersions.filter { productIDs.contains($0.productVersionID) }.flatMap(\.evidenceIDs)
            + records.candidateDecisions.filter { decisionIDs.contains($0.candidateDecisionID) }.flatMap { $0.candidate.evidenceIDs })
        return FoodReresolutionAudit(logVersions: logs, resolutionVersions: resolutions,
            evidence: records.evidence.filter { evidenceIDs.contains($0.evidenceID) }.sorted { $0.evidenceID.rawValue < $1.evidenceID.rawValue })
    }
}

public struct PreparedFoodReresolution: Sendable {
    public let operationID: OperationID
    public let logItemID: LogItemID
    public let newLogVersionID: LogItemVersionID
    public let newResolutionVersionID: ResolutionVersionID
    fileprivate let before: StoredFoodConfirmation
    fileprivate let parentResolution: NutritionResolutionVersion
    fileprivate let target: FoodReresolutionTarget
    fileprivate let mutation: LedgerMutation
    fileprivate let idempotencyKey: LedgerText
}

public final class FoodReresolutionService: Sendable {
    private let ledger: FoodLedgerService
    private let reader: any FoodReresolutionReading
    private let provider: any FoodReresolutionProviding
    private let clock: any LedgerClock
    private let ids: any LedgerIDGenerating

    public init(ledger: FoodLedgerService, reader: any FoodReresolutionReading, provider: any FoodReresolutionProviding, clock: any LedgerClock, ids: any LedgerIDGenerating) {
        self.ledger = ledger
        self.reader = reader
        self.provider = provider
        self.clock = clock
        self.ids = ids
    }

    public func history() throws -> [StoredFoodConfirmation] { try reader.currentRecords() }
    public func audit(_ id: LogItemID) throws -> FoodReresolutionAudit { try reader.audit(id) }
    public func targets() throws -> [FoodReresolutionTarget] { try provider.targets() }

    public func proposals(logItemID: LogItemID, target: FoodReresolutionTarget) throws -> [FoodReresolutionProposal] {
        guard try provider.targets().contains(target) else { throw FoodReresolutionError.unavailableTarget }
        guard let before = try reader.foodConfirmation(logItemID: logItemID) else { throw FoodReresolutionError.missingLog }
        guard case let .confirmation(route) = try provider.candidates(for: before, target: target, at: clock.now()) else { return [] }
        return try route.confirmation.candidates.compactMap { candidate in
            guard FoodReresolutionProposal.hasNoKnownContradictions(before: before, candidate: candidate) else { return nil }
            return try FoodReresolutionProposal(before: before, target: target, input: route.confirmation, candidate: candidate)
        }
    }

    /// No write occurs here. Retain this value unchanged until save is acknowledged.
    public func prepareAcceptance(_ proposal: FoodReresolutionProposal, reason: LedgerText, confirmsIdentityGaps: Bool = false) throws -> PreparedFoodReresolution {
        guard !proposal.isNoOp else { throw FoodReresolutionError.noChange }
        try validateCurrent(proposal.before, target: proposal.target)
        let parent = try resolutionHead(proposal.before.resolution.resolutionID)
        let now = clock.now()
        let candidate = proposal.candidate.candidate
        guard proposal.identityGaps.isEmpty || confirmsIdentityGaps else { throw FoodReresolutionError.identityConfirmationRequired }
        let assertion: UserAssertion?
        if proposal.identityGaps.isEmpty { assertion = nil }
        else {
            assertion = try UserAssertion(
                assertionID: ids.makeID(AssertionTag.self), evidenceID: candidate.evidenceIDs.first,
                author: .user, createdAt: now, reason: reason,
                claim: LedgerText("Explicitly confirmed compatibility with unchanged logged identity despite source gaps: \(proposal.identityGaps.map(\.rawValue).joined(separator: ", "))")
            )
        }
        let decision = try CandidateDecision(
            candidateDecisionID: ids.makeID(CandidateDecisionTag.self), candidate: candidate,
            expectedIdentity: proposal.before.productVersion.identity,
            expectedEdibleQuantity: candidate.edibleQuantity,
            requestedOutcome: assertion == nil ? .selected : .rejected,
            assertionID: assertion?.assertionID, createdAt: now
        )
        let releaseIDs = proposal.sourceReleaseIDs
        var missingReleases: [SourceRelease] = []
        for id in releaseIDs {
            let proposed = proposal.input.sourceReleases.first { $0.sourceReleaseID == id }
            if let existing = try reader.sourceRelease(id: id) {
                guard proposed == nil || proposed == existing else { throw FoodReresolutionError.unavailableTarget }
            } else {
                guard let proposed else { throw FoodLedgerValidationError.missingProvenance }
                missingReleases.append(proposed)
            }
        }
        let resolution = try NutritionResolutionVersion(
            resolutionVersionID: ids.makeID(ResolutionVersionTag.self), resolutionID: parent.resolutionID,
            ordinal: VersionOrdinal(parent.ordinal.value + 1), supersedesResolutionVersionID: parent.resolutionVersionID,
            methodVersion: proposal.target.methodVersion, sourceReleaseIDs: releaseIDs,
            nutrients: candidate.nutrients, decisionIDs: [decision.candidateDecisionID],
            assertionIDs: assertion.map { [$0.assertionID] } ?? [], createdAt: now
        )
        let old = proposal.before.logItemVersion
        let log = try LogItemVersion(
            logItemVersionID: ids.makeID(LogItemVersionTag.self), logItemID: old.logItemID,
            ordinal: VersionOrdinal(old.ordinal.value + 1), supersedesLogItemVersionID: old.logItemVersionID,
            occurredAt: old.occurredAt, reportingDate: old.reportingDate, composition: old.composition,
            edibleQuantity: old.edibleQuantity, quantityConversionVersionID: old.quantityConversionVersionID,
            plateWeightVersionID: old.plateWeightVersionID, originalResolutionVersionID: old.originalResolutionVersionID,
            effectiveResolutionVersionID: resolution.resolutionVersionID,
            correctionReason: LedgerText("Opt-in nutrition re-resolution: \(reason.value)"), createdAt: now
        )
        let operationID = try ids.makeID(OperationTag.self)
        let newEvidence = try proposal.input.evidence.filter { evidence in
            guard let existing = try reader.evidence(evidence.evidenceID) else { return true }
            guard existing == evidence else { throw FoodLedgerValidationError.invalidProvenance }
            return false
        }
        return PreparedFoodReresolution(
            operationID: operationID, logItemID: old.logItemID,
            newLogVersionID: log.logItemVersionID, newResolutionVersionID: resolution.resolutionVersionID,
            before: proposal.before, parentResolution: parent, target: proposal.target,
            mutation: LedgerMutation(evidence: newEvidence, assertions: assertion.map { [$0] } ?? [], resolutionVersions: [resolution], logItemVersions: [log], candidateDecisions: [decision], sourceReleases: missingReleases),
            idempotencyKey: try LedgerText("food-reresolution:\(operationID.rawValue)")
        )
    }

    @discardableResult
    public func accept(_ prepared: PreparedFoodReresolution) throws -> CommitOutcome {
        // A prior successful save can be acknowledged even after a later edit or
        // target removal; the ledger verifies identical payload, actor and key.
        if try reader.operation(prepared.operationID) == nil {
            try validateCurrent(prepared.before, target: prepared.target)
            guard try resolutionHead(prepared.parentResolution.resolutionID) == prepared.parentResolution else {
                throw FoodReresolutionError.staleProposal
            }
        }
        // Existing store lineage/conflict guards reject concurrent competing
        // successors atomically; this operation never manufactures a conflict.
        return try ledger.commit(prepared.mutation, type: .correctResolution, operationID: prepared.operationID, idempotencyKey: prepared.idempotencyKey)
    }

    private func validateCurrent(_ before: StoredFoodConfirmation, target: FoodReresolutionTarget) throws {
        guard try provider.targets().contains(target) else { throw FoodReresolutionError.unavailableTarget }
        guard let current = try reader.foodConfirmation(logItemID: before.logItem.logItemID),
              current.logItemVersion == before.logItemVersion,
              current.productVersion == before.productVersion,
              current.resolutionVersion == before.resolutionVersion else { throw FoodReresolutionError.staleProposal }
    }

    private func resolutionHead(_ id: ResolutionID) throws -> NutritionResolutionVersion {
        let lineage = try reader.resolutionLineage(id)
        let superseded = Set(lineage.compactMap(\.supersedesResolutionVersionID))
        let heads = lineage.filter { !superseded.contains($0.resolutionVersionID) }
        guard heads.count == 1, let head = heads.first else { throw FoodReresolutionError.staleProposal }
        return head
    }
}
