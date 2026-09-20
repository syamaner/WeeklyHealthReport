import Foundation
import FoodLedgerApplication
import FoodLedgerDomain
import FoodLedgerGRDB
import XCTest

final class ApplicationBoundaryTests: XCTestCase {
    func testAttachmentIsRemovedWhenAtomicCommitFails() throws {
        let committer = AlwaysFailingCommitter()
        let attachments = RecordingAttachmentStore()
        let service = try LedgerFixtures.service(committer)

        XCTAssertThrowsError(try service.recordEvidenceWithAttachment(
            bytes: Data("synthetic image bytes".utf8),
            mediaKind: LedgerText("image/jpeg"),
            attachmentStore: attachments,
            evidenceID: LedgerFixtures.id(201, EvidenceTag.self),
            kind: .synthetic,
            locale: LedgerText("en_GB"),
            captureMethod: LedgerText("synthetic"),
            captureMethodVersion: LedgerText("v1"),
            payload: .descriptor(LedgerText("synthetic attachment")),
            operationID: LedgerFixtures.operationID(202)
        ))
        XCTAssertEqual(attachments.persisted.count, 1)
        XCTAssertEqual(attachments.removed, attachments.persisted)
    }

    func testAttachmentWriteFailureNeverAttemptsDatabaseCommit() throws {
        let committer = CountingCommitter()
        let service = try LedgerFixtures.service(committer)
        XCTAssertThrowsError(try service.recordEvidenceWithAttachment(
            bytes: Data([1]),
            mediaKind: LedgerText("image/jpeg"),
            attachmentStore: FailingAttachmentStore(),
            evidenceID: LedgerFixtures.id(203, EvidenceTag.self),
            kind: .synthetic,
            locale: LedgerText("en_GB"),
            captureMethod: LedgerText("synthetic"),
            captureMethodVersion: LedgerText("v1"),
            payload: .descriptor(LedgerText("failure")),
            operationID: LedgerFixtures.operationID(204)
        ))
        XCTAssertEqual(committer.commitCount, 0)
    }

    func testGenericCommitCannotBypassAttachmentCoordination() throws {
        let committer = CountingCommitter()
        let service = try LedgerFixtures.service(committer)
        let bytes = Data("uncoordinated".utf8)
        let descriptor = try AttachmentDescriptor(
            sha256: LedgerFixtures.digester.sha256(bytes),
            mediaKind: LedgerText("image/jpeg"),
            byteCount: bytes.count,
            relativePath: LedgerText("aa/\(String(repeating: "a", count: 64))")
        )
        let evidence = try CaptureEvidence(
            evidenceID: LedgerFixtures.id(208, EvidenceTag.self),
            kind: .synthetic,
            capturedAt: LedgerFixtures.date,
            locale: LedgerText("en_GB"),
            captureMethod: LedgerText("synthetic"),
            captureMethodVersion: LedgerText("v1"),
            originalPayload: .descriptor(LedgerText("uncoordinated")),
            byteHash: descriptor.sha256,
            attachment: descriptor
        )

        XCTAssertThrowsError(try service.commit(
            LedgerMutation(evidence: [evidence]),
            type: .recordEvidence,
            operationID: LedgerFixtures.operationID(209)
        )) { error in
            XCTAssertEqual(
                error as? FoodLedgerStoreError,
                .attachmentFailure("uncoordinated attachment reference")
            )
        }
        XCTAssertEqual(committer.commitCount, 0)
    }

    func testSyntheticCandidateAdapterAddsWithoutDomainOrGRDBChanges() throws {
        let adapter: any CandidateProducing = SyntheticCandidateAdapter()
        let candidate = try adapter.candidate()
        let expected = try LedgerFixtures.identity(drained: .drained)
        let decision = try CandidateDecision(
            candidateDecisionID: LedgerFixtures.id(205, CandidateDecisionTag.self),
            candidate: candidate,
            expectedIdentity: expected,
            expectedEdibleQuantity: .known(
                try PositiveQuantity(value: 100, unit: .grams),
                conversionVersionID: nil
            ),
            requestedOutcome: .rejected,
            createdAt: LedgerFixtures.date
        )
        XCTAssertEqual(decision.outcome, .rejected)
        XCTAssertEqual(decision.contradictionReasons, [.drained])
    }

    func testVersionedOperationCanBeRegisteredWithoutChangingProductionTypes() throws {
        let custom = try XCTUnwrap(LedgerOperationType(rawValue: "synthetic_import_v2"))
        let committer = CountingCommitter()
        let service = FoodLedgerService(
            actorID: try LedgerFixtures.id(900, ActorTag.self),
            committer: committer,
            clock: LedgerFixtures.clock,
            encoder: LedgerFixtures.encoder,
            digester: LedgerFixtures.digester,
            operationRegistry: LedgerOperationRegistry(
                supported: LedgerOperationType.builtInV1.union([custom])
            )
        )

        _ = try service.commit(
            LedgerFixtures.baseMutation(),
            type: custom,
            operationID: LedgerFixtures.operationID(206)
        )
        XCTAssertEqual(committer.commitCount, 1)

        let defaultService = try LedgerFixtures.service(CountingCommitter())
        XCTAssertThrowsError(try defaultService.commit(
            LedgerFixtures.baseMutation(),
            type: custom,
            operationID: LedgerFixtures.operationID(207)
        )) { error in
            XCTAssertEqual(error as? FoodLedgerStoreError, .unsupportedOperation)
        }
    }
}

private protocol CandidateProducing: Sendable {
    func candidate() throws -> ProviderNeutralCandidate
}

private struct SyntheticCandidateAdapter: CandidateProducing {
    func candidate() throws -> ProviderNeutralCandidate {
        try ProviderNeutralCandidate(
            sourceReleaseID: try ExternalIdentifier("synthetic:v1"),
            recordID: try ExternalIdentifier("row:1"),
            identity: try LedgerFixtures.identity(drained: .undrained),
            edibleQuantity: .known(
                try PositiveQuantity(value: 100, unit: .grams),
                conversionVersionID: nil
            ),
            nutrients: try LedgerFixtures.nutrientSet(),
            evidenceIDs: [try LedgerFixtures.id(1, EvidenceTag.self)]
        )
    }
}

private final class RecordingAttachmentStore: EvidenceAttachmentStoring, @unchecked Sendable {
    var persisted: [AttachmentDescriptor] = []
    var removed: [AttachmentDescriptor] = []

    func persist(_ bytes: Data, mediaKind: LedgerText) throws -> AttachmentDescriptor {
        let descriptor = try AttachmentDescriptor(
            sha256: LedgerFixtures.digester.sha256(bytes),
            mediaKind: mediaKind,
            byteCount: bytes.count,
            relativePath: LedgerText("aa/\(String(repeating: "a", count: 64))")
        )
        persisted.append(descriptor)
        return descriptor
    }

    func removeIfUnreferenced(_ descriptor: AttachmentDescriptor) throws {
        removed.append(descriptor)
    }
}

private struct FailingAttachmentStore: EvidenceAttachmentStoring {
    func persist(_ bytes: Data, mediaKind: LedgerText) throws -> AttachmentDescriptor {
        throw FoodLedgerStoreError.attachmentFailure("synthetic failure")
    }

    func removeIfUnreferenced(_ descriptor: AttachmentDescriptor) throws {}
}

private final class AlwaysFailingCommitter: LedgerCommandCommitting, @unchecked Sendable {
    func actorHead(for actorID: ActorID) throws -> ActorHead {
        ActorHead(sequence: 0, operationHash: nil)
    }

    func operation(id: OperationID) throws -> LedgerOperation? { nil }

    func commit(_ transaction: LedgerTransaction) throws -> CommitOutcome {
        throw FoodLedgerStoreError.integrityFailure("synthetic commit failure")
    }
}

private final class CountingCommitter: LedgerCommandCommitting, @unchecked Sendable {
    var commitCount = 0

    func actorHead(for actorID: ActorID) throws -> ActorHead {
        ActorHead(sequence: 0, operationHash: nil)
    }

    func operation(id: OperationID) throws -> LedgerOperation? { nil }

    func commit(_ transaction: LedgerTransaction) throws -> CommitOutcome {
        commitCount += 1
        return .committed(transaction.operation)
    }
}
