import Foundation
import FoodLedgerApplication
import FoodLedgerDomain
import XCTest

final class FoodReresolutionContractTests: XCTestCase {
    func testAcceptPreservesOriginalsAndRetryIsIdempotentAcrossStores() throws {
        for harness in try LedgerFixtures.harnesses() {
            defer { harness.cleanup() }
            let fixture = try seed(harness)
            let provider = try UpgradeProvider(before: fixture.record)
            let service = makeService(fixture, provider: provider)
            let before = try fixture.archive.archiveState()
            let proposals = try service.proposals(logItemID: fixture.record.logItem.logItemID, target: provider.target)
            XCTAssertEqual(proposals.count, 1)
            XCTAssertEqual(proposals[0].diff.changes.map(\.key), [.protein])
            XCTAssertEqual(try fixture.archive.archiveState(), before, "Preview must not mutate")
            let prepared = try service.prepareAcceptance(proposals[0], reason: LedgerText("Review synthetic source correction"))
            XCTAssertEqual(try fixture.archive.archiveState(), before, "Preparation must not mutate")
            _ = try service.accept(prepared)
            let once = try fixture.archive.archiveState()
            _ = try service.accept(prepared)
            XCTAssertEqual(try fixture.archive.archiveState(), once)
            let current = try XCTUnwrap(harness.reader.foodConfirmation(logItemID: fixture.record.logItem.logItemID))
            XCTAssertEqual(current.productVersion, fixture.record.productVersion)
            XCTAssertEqual(current.logItemVersion.edibleQuantity, fixture.record.logItemVersion.edibleQuantity)
            XCTAssertEqual(current.logItemVersion.originalResolutionVersionID, fixture.record.logItemVersion.originalResolutionVersionID)
            XCTAssertEqual(current.resolutionVersion.supersedesResolutionVersionID, fixture.record.resolutionVersion.resolutionVersionID)
            XCTAssertEqual(current.logItemVersion.supersedesLogItemVersionID, fixture.record.logItemVersion.logItemVersionID)
            XCTAssertTrue(once.records.resolutionVersions.contains(fixture.record.resolutionVersion))
            XCTAssertTrue(once.records.logItemVersions.contains(fixture.record.logItemVersion))
            XCTAssertEqual(once.records.evidence, before.records.evidence)
            let audit = try service.audit(fixture.record.logItem.logItemID)
            XCTAssertTrue(audit.logVersions.contains(fixture.record.logItemVersion))
            XCTAssertTrue(audit.resolutionVersions.contains(fixture.record.resolutionVersion))
            XCTAssertEqual(audit.evidence, fixture.record.evidence)
        }
    }

    func testSourceRemovalStaleProposalsAndNoOpLeaveCurrentUnchanged() throws {
        for harness in try LedgerFixtures.harnesses() {
            defer { harness.cleanup() }
            let fixture = try seed(harness)
            let provider = try UpgradeProvider(before: fixture.record)
            let service = makeService(fixture, provider: provider)
            let proposal = try XCTUnwrap(service.proposals(logItemID: fixture.record.logItem.logItemID, target: provider.target).first)
            let first = try service.prepareAcceptance(proposal, reason: LedgerText("First explicit review"))
            let stale = try service.prepareAcceptance(proposal, reason: LedgerText("Separate stale review"))
            let before = try fixture.archive.archiveState()
            provider.available = false
            XCTAssertThrowsError(try service.accept(first))
            XCTAssertEqual(try fixture.archive.archiveState(), before)
            provider.available = true
            _ = try service.accept(first)
            let after = try fixture.archive.archiveState()
            XCTAssertThrowsError(try service.accept(stale))
            XCTAssertEqual(try fixture.archive.archiveState(), after)
            let unchanged = try XCTUnwrap(service.proposals(logItemID: fixture.record.logItem.logItemID, target: provider.target).first)
            XCTAssertTrue(unchanged.diff.isUnchanged)
            XCTAssertTrue(unchanged.isNoOp)
            XCTAssertThrowsError(try service.prepareAcceptance(unchanged, reason: LedgerText("No-op must not append records")))
            XCTAssertEqual(try fixture.archive.archiveState(), after)
        }
    }

    func testUnknownSourceIdentityRequiresExplicitAssertion() throws {
        for harness in try LedgerFixtures.harnesses() {
            defer { harness.cleanup() }
            let fixture = try seed(harness)
            let provider = try UpgradeProvider(before: fixture.record, unknownPreparation: true)
            let service = makeService(fixture, provider: provider)
            let proposal = try XCTUnwrap(service.proposals(logItemID: fixture.record.logItem.logItemID, target: provider.target).first)
            XCTAssertEqual(proposal.identityGaps, [.preparation])
            XCTAssertThrowsError(try service.prepareAcceptance(proposal, reason: LedgerText("Not enough confirmation")))
            let prepared = try service.prepareAcceptance(proposal, reason: LedgerText("Confirmed the recorded as-sold identity applies"), confirmsIdentityGaps: true)
            _ = try service.accept(prepared)
            let current = try XCTUnwrap(harness.reader.foodConfirmation(logItemID: fixture.record.logItem.logItemID))
            XCTAssertEqual(current.candidateDecision.outcome, .rejected)
            XCTAssertNotNil(current.candidateDecision.assertionID)
            XCTAssertEqual(current.assertions.last?.author, .user)
            XCTAssertEqual(current.productVersion, fixture.record.productVersion)
            let confirmations = FoodConfirmationService(ledger: fixture.ledger, reader: harness.reader, clock: LedgerFixtures.clock, ids: RandomLedgerIDGenerator())
            var reopened = try XCTUnwrap(confirmations.reopen(logItemID: current.logItem.logItemID))
            reopened.quantity.value = 70
            let quantityCorrection = try confirmations.save(reopened, operationID: LedgerFixtures.operationID(700))
            XCTAssertEqual(quantityCorrection.productVersion, current.productVersion)
            XCTAssertEqual(quantityCorrection.resolutionVersion, current.resolutionVersion)
            XCTAssertEqual(quantityCorrection.logItemVersion.edibleQuantity.value, 70)
        }
    }

    func testKnownPreparationOrItemClassContradictionsCannotBeAssertedAway() throws {
        for harness in try LedgerFixtures.harnesses() {
            defer { harness.cleanup() }
            let fixture = try seed(harness)
            let before = try fixture.archive.archiveState()
            for provider in [try UpgradeProvider(before: fixture.record, preparation: .cooked),
                             try UpgradeProvider(before: fixture.record, itemClass: .supplement)] {
                let service = makeService(fixture, provider: provider)
                XCTAssertTrue(try service.proposals(logItemID: fixture.record.logItem.logItemID, target: provider.target).isEmpty)
                XCTAssertThrowsError(try FoodReresolutionProposal(before: fixture.record, target: provider.target, input: provider.input, candidate: provider.input.candidates[0]))
            }
            XCTAssertEqual(try fixture.archive.archiveState(), before)
        }
    }

    private struct Fixture {
        let record: StoredFoodConfirmation
        let ledger: FoodLedgerService
        let archive: any FoodArchiveLedgerAccess
        let reader: any FoodConfirmationReading
    }
    private func seed(_ harness: TestHarness) throws -> Fixture {
        let archive = try XCTUnwrap(harness.committer as? any FoodArchiveLedgerAccess)
        let ledger = try LedgerFixtures.service(harness.committer)
        let base = try LedgerFixtures.baseMutation()
        let candidate = try ProviderNeutralCandidate(sourceReleaseID: base.sourceReleases[0].sourceReleaseID, recordID: ExternalIdentifier("sample"), identity: LedgerFixtures.identity(), edibleQuantity: .known(PositiveQuantity(value: 100, unit: .grams), conversionVersionID: nil), nutrients: LedgerFixtures.nutrientSet(), evidenceIDs: base.evidence.map(\.evidenceID), matchMetadata: CandidateMatchMetadata(methodVersion: LedgerText("synthetic-v1"), score: 1, materialDifferences: [], libraryAliases: []))
        let populated = try PopulatedFoodCandidate(candidate: candidate, name: LedgerText("Sample food"), itemClass: .food)
        let input = try PopulatedFoodConfirmation(evidence: base.evidence, sourceReleases: base.sourceReleases, candidates: [populated], expectedIdentity: candidate.identity, expectedEdibleQuantity: candidate.edibleQuantity)
        var state = FoodConfirmationState(input: input)
        state.decision = .accepted
        state.quantity.value = 60
        let record = try FoodConfirmationService(ledger: ledger, reader: harness.reader, clock: LedgerFixtures.clock, ids: RandomLedgerIDGenerator()).save(state, operationID: LedgerFixtures.operationID(600))
        return Fixture(record: record, ledger: ledger, archive: archive, reader: harness.reader)
    }
    private func makeService(_ fixture: Fixture, provider: UpgradeProvider) -> FoodReresolutionService {
        FoodReresolutionService(ledger: fixture.ledger, reader: FoodReresolutionHistory(archive: fixture.archive, confirmations: fixture.reader), provider: provider, clock: LedgerFixtures.clock, ids: RandomLedgerIDGenerator())
    }
}

private final class UpgradeProvider: FoodReresolutionProviding, @unchecked Sendable {
    var available = true
    let target: FoodReresolutionTarget
    let input: PopulatedFoodConfirmation
    init(before: StoredFoodConfirmation, unknownPreparation: Bool = false, preparation: PreparationKind? = nil, itemClass: ItemClass = .food) throws {
        let release = try SourceRelease(sourceReleaseID: ExternalIdentifier("synthetic-v2"), sourceID: ExternalIdentifier("synthetic"), releasedAt: LedgerFixtures.date, artifactHash: SHA256Digest(String(repeating: "e", count: 64)), schemaVersion: LedgerText("1"), pipelineVersion: LedgerText("2"), licence: LedgerText("synthetic"), attribution: LedgerText("synthetic"), manifestHash: SHA256Digest(String(repeating: "f", count: 64)))
        target = FoodReresolutionTarget(sourceRelease: release, methodVersion: try LedgerText("synthetic-v2"))
        let old = before.productVersion.identity
        let identity = try DecisiveIdentity(preparation: preparation.map { try PreparationState(kind: $0) } ?? (unknownPreparation ? PreparationState(kind: .unknown) : old.preparation), bone: old.bone, skin: old.skin, drained: old.drained, packingMedium: old.packingMedium, fortification: old.fortification, servingBasis: old.servingBasis)
        let nutrients = try NutrientSet(entries: before.resolutionVersion.nutrients.entries.map { $0.key == .protein ? try NutrientEntry(key: .protein, value: .unknown(.noCompatibleSource)) : $0 })
        let candidate = try ProviderNeutralCandidate(sourceReleaseID: release.sourceReleaseID, recordID: ExternalIdentifier("updated-sample"), identity: identity, edibleQuantity: .known(PositiveQuantity(value: 100, unit: .grams), conversionVersionID: nil), nutrients: nutrients, evidenceIDs: before.evidence.map(\.evidenceID), matchMetadata: CandidateMatchMetadata(methodVersion: target.methodVersion, score: 1, materialDifferences: [], libraryAliases: []))
        let populated = try PopulatedFoodCandidate(candidate: candidate, name: LedgerText("Updated synthetic food"), itemClass: itemClass)
        input = try PopulatedFoodConfirmation(evidence: before.evidence, sourceReleases: before.sourceReleases + [release], candidates: [populated], expectedIdentity: old, expectedEdibleQuantity: candidate.edibleQuantity)
    }
    func targets() throws -> [FoodReresolutionTarget] { available ? [target] : [] }
    func candidates(for record: StoredFoodConfirmation, target: FoodReresolutionTarget, at: Date) throws -> GenericFoodSearchOutcome {
        guard available, target == self.target else { throw FoodReresolutionError.unavailableTarget }
        return .confirmation(GenericFoodConfirmationRoute(confirmation: input, matches: []))
    }
}
