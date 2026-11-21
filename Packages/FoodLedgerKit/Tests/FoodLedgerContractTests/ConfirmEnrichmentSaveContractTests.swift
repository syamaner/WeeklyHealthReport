import Foundation
@testable import FoodLedgerApplication
import FoodLedgerDomain
import FoodLedgerTestSupport
import XCTest

/// Confirm enrichment v1, PR 1 (phase gate section 2.4a and the G12 fixture cases): a save of a candidate
/// that cites CE1 items rebuilds its evidence list from its own IDs, a new log drops every CE1 ID, and no
/// save writes an `openrouter_estimate` value before the suggestion layer exists. Synthetic data only.
final class ConfirmEnrichmentSaveContractTests: XCTestCase {
    typealias A = ApprovedEstimateConfirmContractTests
    typealias F = ConfirmEnrichmentFixtures

    /// The oats input with a B capture and a choices item appended to its candidate, as a reopened CE1
    /// entry's bound candidate would cite them.
    static func citingState(_ service: FoodConfirmationService, nutrients: NutrientSet? = nil) throws -> (FoodConfirmationState, F.Built) {
        let built = try F.built()
        let base = try A.input([A.oats])
        let source = base.candidates[0]
        let candidate = try ProviderNeutralCandidate(
            sourceReleaseID: source.candidate.sourceReleaseID, recordID: source.candidate.recordID,
            identity: source.candidate.identity, edibleQuantity: source.candidate.edibleQuantity,
            nutrients: nutrients ?? source.candidate.nutrients,
            evidenceIDs: source.candidate.evidenceIDs + [built.captureEvidence.evidenceID, built.choicesEvidence.evidenceID],
            matchMetadata: source.candidate.matchMetadata)
        let populated = try PopulatedFoodCandidate(candidate: candidate, name: source.name, brand: source.brand, variant: source.variant,
            barcode: source.barcode, itemClass: source.itemClass, packFacts: source.packFacts)
        let input = try PopulatedFoodConfirmation(evidence: base.evidence + [built.captureEvidence, built.choicesEvidence],
            sourceReleases: base.sourceReleases, candidates: [populated],
            expectedIdentity: candidate.identity, expectedEdibleQuantity: candidate.edibleQuantity)
        var state = FoodConfirmationState(input: input, prefillSourceQuantity: false)
        service.bindEstimates(&state)
        try A.correct(&state)
        FoodConfirmationReducer.reduce(state: &state, action: .setQuantity(150, .grams))
        FoodConfirmationReducer.reduce(state: &state, action: .accept)
        return (state, built)
    }

    func testASaveCitingCE1ItemsCarriesNoneAndANewLogDropsThem() throws {
        for harness in try LedgerFixtures.harnesses() {
            defer { harness.cleanup() }
            let service = try A.service(harness)
            let (state, built) = try Self.citingState(service)
            let ce1: Set<EvidenceID> = [built.captureEvidence.evidenceID, built.choicesEvidence.evidenceID]
            let saved = try service.save(state, operationID: LedgerFixtures.operationID(11_549))
            XCTAssertTrue(Set(saved.candidateDecision.candidate.evidenceIDs).isDisjoint(with: ce1), harness.name)
            XCTAssertTrue(Set(saved.productVersion.evidenceIDs).isDisjoint(with: ce1), harness.name)
            XCTAssertEqual(saved.candidateDecision.candidate.evidenceIDs,
                           ConfirmEnrichmentCitation.ownEvidenceIDs(state.selectedCandidate.candidate, evidence: state.input.evidence))
            let relog = try service.relogInput(saved)
            XCTAssertTrue(Set(relog.candidates[0].candidate.evidenceIDs).isDisjoint(with: ce1), harness.name)
            XCTAssertTrue(relog.evidence.allSatisfy { !ConfirmEnrichmentVersions.isEnrichmentEvidence($0) }, harness.name)
        }
    }

    func testAnUnverifiedOpenRouterEstimateIsNeverSaved() throws {
        for harness in try LedgerFixtures.harnesses() {
            defer { harness.cleanup() }
            let service = try A.service(harness)
            let base = try A.input([A.oats]).candidates[0].candidate.nutrients
            let probe = try F.built()
            let value = try F.value(6.5, key: .fiber, provenance: try F.provenance(probe.captureEvidence, key: .fiber))
            let nutrients = try NutrientSet(entries: base.entries.map { $0.key == .fiber ? try NutrientEntry(key: .fiber, value: value) : $0 })
            let (state, _) = try Self.citingState(service, nutrients: nutrients)
            XCTAssertThrowsError(try service.save(state, operationID: LedgerFixtures.operationID(11_550))) {
                XCTAssertEqual($0 as? FoodConfirmationSaveError, .invalidOpenRouterEstimate, harness.name)
            }
        }
    }
}
