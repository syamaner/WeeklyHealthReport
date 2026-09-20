import Foundation
import FoodLedgerDomain

public final class FoodLedgerService: SourceReleaseInstalling, @unchecked Sendable {
    private let actorID: ActorID
    private let committer: any LedgerCommandCommitting
    private let clock: any LedgerClock
    private let encoder: any CanonicalEncoding
    private let digester: any Digesting
    private let operationRegistry: LedgerOperationRegistry

    public init(
        actorID: ActorID,
        committer: any LedgerCommandCommitting,
        clock: any LedgerClock,
        encoder: any CanonicalEncoding,
        digester: any Digesting,
        operationRegistry: LedgerOperationRegistry = .builtInV1
    ) {
        self.actorID = actorID
        self.committer = committer
        self.clock = clock
        self.encoder = encoder
        self.digester = digester
        self.operationRegistry = operationRegistry
    }

    public func commit(
        _ mutation: LedgerMutation,
        type: LedgerOperationType,
        operationID: OperationID,
        idempotencyKey: LedgerText? = nil
    ) throws -> CommitOutcome {
        try commit(
            mutation,
            type: type,
            operationID: operationID,
            idempotencyKey: idempotencyKey,
            persistedAttachments: []
        )
    }

    private func commit(
        _ mutation: LedgerMutation,
        type: LedgerOperationType,
        operationID: OperationID,
        idempotencyKey: LedgerText?,
        persistedAttachments: Set<AttachmentDescriptor>
    ) throws -> CommitOutcome {
        guard !mutation.isEmpty else { throw FoodLedgerStoreError.integrityFailure("empty mutation") }
        let referencedAttachments = Set(mutation.evidence.compactMap(\.attachment))
        guard referencedAttachments.isSubset(of: persistedAttachments) else {
            throw FoodLedgerStoreError.attachmentFailure("uncoordinated attachment reference")
        }
        try operationRegistry.requireSupported(type)
        let payload = try encoder.encode(mutation)
        let payloadHash = try digester.sha256(payload)

        if let existing = try committer.operation(id: operationID) {
            guard existing.payloadHash == payloadHash,
                  existing.actorID == actorID,
                  existing.operationType == type,
                  existing.idempotencyKey == idempotencyKey else {
                throw FoodLedgerStoreError.divergentDuplicateOperation
            }
            return .idempotent(existing)
        }

        let head = try committer.actorHead(for: actorID)
        let unsigned = UnsignedLedgerOperation(
            schemaVersion: LedgerOperation.schemaVersion,
            operationID: operationID,
            actorID: actorID,
            actorSequence: head.sequence + 1,
            operationType: type,
            createdAt: clock.now(),
            affectedIDs: mutation.affectedIDs,
            payloadHash: payloadHash,
            previousOperationHash: head.operationHash,
            idempotencyKey: idempotencyKey
        )
        let operationHash = try digester.sha256(encoder.encode(unsigned))
        let operation = LedgerOperation(
            operationID: operationID,
            actorID: actorID,
            actorSequence: unsigned.actorSequence,
            operationType: type,
            createdAt: unsigned.createdAt,
            affectedIDs: unsigned.affectedIDs,
            payload: payload,
            payloadHash: payloadHash,
            previousOperationHash: head.operationHash,
            operationHash: operationHash,
            idempotencyKey: idempotencyKey
        )
        return try committer.commit(LedgerTransaction(mutation: mutation, operation: operation))
    }

    public func installSourceRelease(
        _ release: SourceRelease,
        installation: SourceInstallation,
        operationID: OperationID,
        idempotencyKey: LedgerText?
    ) throws -> CommitOutcome {
        guard installation.sourceReleaseID == release.sourceReleaseID else {
            throw FoodLedgerStoreError.missingReference(installation.sourceReleaseID.value)
        }
        return try commit(
            LedgerMutation(sourceReleases: [release], sourceInstallations: [installation]),
            type: .installSourceRelease,
            operationID: operationID,
            idempotencyKey: idempotencyKey
        )
    }

    public func installSourceRelease(
        _ release: SourceRelease,
        operationID: OperationID,
        idempotencyKey: LedgerText?
    ) throws -> CommitOutcome {
        return try installSourceRelease(
            release,
            installation: SourceInstallation(
                sourceReleaseID: release.sourceReleaseID,
                manifestRelativePath: LedgerText("Datasets/\(release.sourceReleaseID.value)/manifest.json"),
                recordCount: 0,
                installedAt: clock.now()
            ),
            operationID: operationID,
            idempotencyKey: idempotencyKey
        )
    }

    public func recordEvidenceWithAttachment(
        bytes: Data,
        mediaKind: LedgerText,
        attachmentStore: any EvidenceAttachmentStoring,
        evidenceID: EvidenceID,
        kind: CaptureKind,
        locale: LedgerText,
        captureMethod: LedgerText,
        captureMethodVersion: LedgerText,
        payload: CapturePayload,
        operationID: OperationID,
        idempotencyKey: LedgerText? = nil
    ) throws -> CommitOutcome {
        let descriptor = try attachmentStore.persist(bytes, mediaKind: mediaKind)
        do {
            let evidence = try CaptureEvidence(
                evidenceID: evidenceID,
                kind: kind,
                capturedAt: clock.now(),
                locale: locale,
                captureMethod: captureMethod,
                captureMethodVersion: captureMethodVersion,
                originalPayload: payload,
                byteHash: descriptor.sha256,
                attachment: descriptor
            )
            return try commit(
                LedgerMutation(evidence: [evidence]),
                type: .recordEvidence,
                operationID: operationID,
                idempotencyKey: idempotencyKey,
                persistedAttachments: [descriptor]
            )
        } catch {
            try? attachmentStore.removeIfUnreferenced(descriptor)
            throw error
        }
    }
}
