import FoodLedgerApplication
import FoodLedgerDomain
@testable import FoodLedgerPresentation
import Foundation
import XCTest

/// Food details from the catalogue (docs/personal-food-catalogue-identity-facts-v1-amendment.md section 5,
/// contract test 7): the Confirm line and decision I1-D1 (changing a catalogue fact needs no typed
/// reason, and is still not a fill). Synthetic fixtures only.
@MainActor
final class IdentityFactsPresentationTests: XCTestCase {
    static let fixtures = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("docs/fixtures")

    /// The golden's oats entry as Confirm gets it, without its merge record: its stated facts apply.
    static func state(_ fixture: String = "personal-food-database-estimates-v4/golden.json") throws -> FoodConfirmationState {
        let file = try PersonalFoodDatabaseCodec.decode(try Data(contentsOf: fixtures.appendingPathComponent(fixture))).get()
        let release = try PersonalFoodDatabaseRelease.sourceRelease(fileSHA256: SHA256Digest(String(repeating: "e", count: 64)),
                                                                     generated: file.generated, schema: file.schema)
        let entry = try XCTUnwrap(file.entries.first { $0.title == "Synthetic Example Oats" })
        let evidence = try CaptureEvidence(evidenceID: EvidenceID("00000000-0000-0000-0000-0000000000aa"), kind: .genericSearch,
            capturedAt: Date(timeIntervalSince1970: 1_794_000_000), locale: LedgerText("en-GB"),
            captureMethod: LedgerText("typed_generic_food_search"), captureMethodVersion: LedgerText("pfc-resolution-v2"),
            originalPayload: .text(LedgerText("synthetic example oats")))
        let built = try XCTUnwrap(PersonalFoodDatabaseCandidateBuilder.build(entry: entry, file: file, databaseRelease: release,
            record: nil, evidenceIDs: [evidence.evidenceID], score: 1))
        return FoodConfirmationState(input: try PopulatedFoodConfirmation(evidence: [evidence], sourceReleases: built.releases,
            candidates: [built.candidate], expectedIdentity: built.candidate.candidate.identity,
            expectedEdibleQuantity: built.candidate.candidate.edibleQuantity))
    }

    static func model(_ state: FoodConfirmationState) -> FoodConfirmationViewModel {
        FoodConfirmationViewModel(state: state) { _ in throw FoodConfirmationSaveError.noAcceptedCandidate }
    }

    func testTheLineListsOnlyTheFileFactsAndHidesAfterACorrection() throws {
        let state = try Self.state()
        let model = Self.model(state)
        XCTAssertEqual(model.databaseFactsLine, "Food details from your food database: raw, no bone, no skin, not fortified")
        var corrected = state
        corrected.correction = FoodCorrection(name: state.selectedCandidate.name, brand: state.selectedCandidate.brand,
            variant: nil, identity: state.selectedCandidate.candidate.identity, itemClass: state.selectedCandidate.itemClass,
            nutrients: state.selectedCandidate.candidate.nutrients, reason: try LedgerText(FoodDetailsFillPolicy.carriedReason))
        XCTAssertNil(Self.model(corrected).databaseFactsLine, "hidden after a correction or a carried fill")
        // A candidate without the frozen-prefix note shows no line.
        XCTAssertNil(Self.model(try Self.state("personal-food-database-estimates-v2/golden.json")).databaseFactsLine)
    }

    func testTheNoteSurvivesEncodingAsSavedCandidateData() throws {
        let candidate = try Self.state().selectedCandidate.candidate
        let decoded = try JSONDecoder().decode(ProviderNeutralCandidate.self, from: JSONEncoder().encode(candidate))
        XCTAssertEqual(decoded.matchMetadata?.materialDifferences, candidate.matchMetadata?.materialDifferences)
        XCTAssertTrue(decoded.matchMetadata?.materialDifferences.contains {
            $0.value.hasPrefix(PersonalFoodDatabaseCandidateBuilder.factsNotePrefix) } == true)
    }

    func testDecisionD1AChangedCatalogueFactNeedsNoTypedReasonAndIsNotAFill() throws {
        let state = try Self.state()
        var draft = FoodDetailsDraft(model: Self.model(state))
        draft.bone = BoneState.withBone.rawValue
        XCTAssertFalse(draft.fillsOnly(in: state))
        XCTAssertTrue(draft.changesDatabaseFactsOnly(in: state))
        XCTAssertTrue(draft.canApply(in: state))
        let correction = try XCTUnwrap(draft.correction(in: state))
        XCTAssertEqual(correction.reason.value, "Food details changed from your food database")
        XCTAssertFalse(FoodDetailsFillPolicy.isFill(correction, in: state), "weight and conversion are cleared, not carried")
        // A typed reason is kept.
        var typed = draft
        typed.reason = "Synthetic reason"
        XCTAssertEqual(typed.correction(in: state)?.reason.value, "Synthetic reason")
        // Filling a blank stays the fill rule's own.
        var fill = FoodDetailsDraft(model: Self.model(state))
        fill.drained = DrainedState.notApplicable.rawValue
        XCTAssertTrue(fill.fillsOnly(in: state))
        XCTAssertEqual(fill.correction(in: state)?.reason.value, FoodDetailsFillPolicy.filledReason)
        // Anything beyond the food details still needs a reason.
        var renamed = draft
        renamed.name = "Synthetic renamed oats"
        XCTAssertFalse(renamed.canApply(in: state))
    }

    func testWithoutCatalogueFactsAStatedChangeStillNeedsAReason() throws {
        let state = try Self.state("personal-food-database-estimates-v2/golden.json")
        var draft = FoodDetailsDraft(model: Self.model(state))
        draft.preparation = PreparationKind.cooked.rawValue
        XCTAssertFalse(draft.changesDatabaseFactsOnly(in: state))
        XCTAssertFalse(draft.canApply(in: state))
    }
}
