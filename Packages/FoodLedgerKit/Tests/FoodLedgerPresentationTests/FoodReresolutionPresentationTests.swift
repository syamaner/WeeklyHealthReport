import FoodLedgerApplication
import FoodLedgerDomain
import FoodLedgerPresentation
import FoodLedgerTestSupport
import XCTest

@MainActor
final class FoodReresolutionPresentationTests: XCTestCase {
    func testExplicitTargetCandidateAndDeclineDoNotWrite() throws {
        let fixture = try Fixture()
        let model = fixture.model
        model.load()
        XCTAssertNil(model.selectedTargetID)
        model.preview(fixture.record)
        XCTAssertTrue(model.proposals.isEmpty)
        model.selectedTargetID = fixture.provider.target.identifier
        model.preview(fixture.record)
        XCTAssertEqual(model.proposals.count, 1)
        XCTAssertNil(model.selectedIndex)
        model.save()
        XCTAssertEqual(try fixture.store.counts().operations, 1)
        model.select(0)
        model.reason = "Review the fixture update"
        model.decline()
        XCTAssertTrue(model.proposals.isEmpty)
        XCTAssertEqual(try fixture.store.counts().operations, 1)
    }

    func testLostResponseCannotBeDiscardedOrDuplicated() throws {
        let fixture = try Fixture()
        let model = fixture.model
        model.load()
        model.selectedTargetID = fixture.provider.target.identifier
        model.preview(fixture.record)
        model.select(0)
        model.reason = "Explicit test acceptance"
        fixture.committer.failAfterNextCommit = true
        model.save()
        XCTAssertNotNil(model.pending)
        XCTAssertEqual(try fixture.store.counts().operations, 2)
        model.decline()
        XCTAssertNotNil(model.pending)
        fixture.provider.available = false
        model.retry()
        XCTAssertNil(model.pending)
        XCTAssertEqual(try fixture.store.counts().operations, 2)
        model.showAudit(try XCTUnwrap(model.records.first))
        XCTAssertEqual(model.audit?.logVersions.count, 2)
        XCTAssertEqual(model.audit?.resolutionVersions.count, 2)
    }

    func testRemovedSourceBeforeAcceptanceLeavesHistoryAlone() throws {
        let fixture = try Fixture()
        let model = fixture.model
        model.load()
        model.selectedTargetID = fixture.provider.target.identifier
        model.preview(fixture.record)
        model.select(0)
        model.reason = "Review"
        fixture.provider.available = false
        model.save()
        XCTAssertNil(model.pending)
        XCTAssertEqual(try fixture.store.counts().operations, 1)
    }

    @MainActor private struct Fixture {
        let store: InMemoryFoodLedgerStore
        let committer: FailingCommitter
        let record: StoredFoodConfirmation
        let provider: TestProvider
        let model: FoodReresolutionViewModel

        init() throws {
            store = InMemoryFoodLedgerStore()
            committer = FailingCommitter(store: store)
            let ids = RandomLedgerIDGenerator()
            let clock = Clock()
            let ledger = FoodLedgerService(actorID: try ids.makeID(ActorTag.self), committer: committer, clock: clock, encoder: FoundationCanonicalJSONEncoder(), digester: SHA256Digester())
            let release = try Self.release("synthetic-v1")
            let identity = try DecisiveIdentity(preparation: PreparationState(kind: .asSold), bone: .notApplicable, skin: .notApplicable, drained: .notApplicable, packingMedium: .named(LedgerText("none")), fortification: .unfortified, servingBasis: .per100Grams)
            let nutrients = try NutrientSet(entries: NutrientKey.allCases.map { try NutrientEntry(key: $0, value: .unknown(.notDeclared)) })
            let evidence = try CaptureEvidence(evidenceID: ids.makeID(EvidenceTag.self), kind: .synthetic, capturedAt: clock.now(), locale: LedgerText("en_GB"), captureMethod: LedgerText("synthetic"), captureMethodVersion: LedgerText("1"), originalPayload: .text(LedgerText("Synthetic food")))
            let candidate = try ProviderNeutralCandidate(sourceReleaseID: release.sourceReleaseID, recordID: ExternalIdentifier("sample"), identity: identity, edibleQuantity: .known(PositiveQuantity(value: 100, unit: .grams), conversionVersionID: nil), nutrients: nutrients, evidenceIDs: [evidence.evidenceID])
            let populated = try PopulatedFoodCandidate(candidate: candidate, name: LedgerText("Synthetic food"), itemClass: .food)
            let input = try PopulatedFoodConfirmation(evidence: [evidence], sourceReleases: [release], candidates: [populated], expectedIdentity: identity, expectedEdibleQuantity: candidate.edibleQuantity)
            var state = FoodConfirmationState(input: input)
            state.decision = .accepted
            record = try FoodConfirmationService(ledger: ledger, reader: store, clock: clock, ids: ids).save(state, operationID: ids.makeID(OperationTag.self))
            let target = FoodReresolutionTarget(sourceRelease: try Self.release("synthetic-v2"), methodVersion: try LedgerText("synthetic-matcher-v2"))
            provider = try TestProvider(target: target, record: record)
            model = FoodReresolutionViewModel(service: FoodReresolutionService(ledger: ledger, reader: FoodReresolutionHistory(archive: store, confirmations: store), provider: provider, clock: clock, ids: ids))
        }
        private static func release(_ id: String) throws -> SourceRelease {
            try SourceRelease(sourceReleaseID: ExternalIdentifier(id), sourceID: ExternalIdentifier("synthetic"), releasedAt: Clock().now(), artifactHash: SHA256Digest(String(repeating: "a", count: 64)), schemaVersion: LedgerText("1"), pipelineVersion: LedgerText("1"), licence: LedgerText("synthetic"), attribution: LedgerText("synthetic"), manifestHash: SHA256Digest(String(repeating: "b", count: 64)))
        }
    }
}

private struct Clock: LedgerClock { func now() -> Date { Date(timeIntervalSince1970: 1_700_000_000) } }
private final class FailingCommitter: LedgerCommandCommitting, @unchecked Sendable {
    let store: InMemoryFoodLedgerStore
    var failAfterNextCommit = false
    init(store: InMemoryFoodLedgerStore) { self.store = store }
    func actorHead(for id: ActorID) throws -> ActorHead { try store.actorHead(for: id) }
    func operation(id: OperationID) throws -> LedgerOperation? { try store.operation(id: id) }
    func commit(_ transaction: LedgerTransaction) throws -> CommitOutcome {
        let result = try store.commit(transaction)
        if failAfterNextCommit { failAfterNextCommit = false; throw CocoaError(.fileReadUnknown) }
        return result
    }
}
private final class TestProvider: FoodReresolutionProviding, @unchecked Sendable {
    let target: FoodReresolutionTarget
    let input: PopulatedFoodConfirmation
    var available = true
    init(target: FoodReresolutionTarget, record: StoredFoodConfirmation) throws {
        self.target = target
        let nutrients = try NutrientSet(entries: NutrientKey.allCases.map { try NutrientEntry(key: $0, value: .unknown($0 == .protein ? .noCompatibleSource : .notDeclared)) })
        let candidate = try ProviderNeutralCandidate(sourceReleaseID: target.sourceRelease.sourceReleaseID, recordID: ExternalIdentifier("new-sample"), identity: record.productVersion.identity, edibleQuantity: record.candidateDecision.candidate.edibleQuantity, nutrients: nutrients, evidenceIDs: record.evidence.map(\.evidenceID), matchMetadata: CandidateMatchMetadata(methodVersion: target.methodVersion, score: 1, materialDifferences: [], libraryAliases: []))
        let populated = try PopulatedFoodCandidate(candidate: candidate, name: LedgerText("New synthetic food"), itemClass: .food)
        input = try PopulatedFoodConfirmation(evidence: record.evidence, sourceReleases: [target.sourceRelease], candidates: [populated], expectedIdentity: candidate.identity, expectedEdibleQuantity: candidate.edibleQuantity)
    }
    func targets() throws -> [FoodReresolutionTarget] { available ? [target] : [] }
    func candidates(for record: StoredFoodConfirmation, target: FoodReresolutionTarget, at: Date) throws -> GenericFoodSearchOutcome { .confirmation(GenericFoodConfirmationRoute(confirmation: input, matches: [])) }
}
