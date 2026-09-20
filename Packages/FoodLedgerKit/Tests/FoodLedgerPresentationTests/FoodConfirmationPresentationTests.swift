import Foundation
import FoodLedgerApplication
import FoodLedgerDomain
import FoodLedgerPresentation
import SwiftUI
import XCTest

@MainActor
final class FoodConfirmationPresentationTests: XCTestCase {
    func testFailureMessagesProvideNonColourRecoveryInstructions() {
        XCTAssertEqual(
            FoodConfirmationViewModel.message(for: FoodQuantityValidationError.missingPlateWeight),
            "Enter or choose an empty plate weight."
        )
        XCTAssertEqual(
            FoodConfirmationViewModel.message(for: FoodConfirmationSaveError.invalidQuantity),
            "Enter a finite quantity greater than zero."
        )
        XCTAssertEqual(
            FoodConfirmationViewModel.message(
                for: FoodConfirmationSaveError.unexplainedMaterialDifferences([.preparation])
            ),
            "Explain the highlighted differences or apply a correction before saving."
        )
        XCTAssertTrue(
            FoodConfirmationViewModel.message(for: CocoaError(.fileWriteUnknown))
                .contains("try again")
        )
    }

    func testSharedViewBuildsForAccessibilityTextSize() throws {
        let model = FoodConfirmationViewModel(state: try fixtureState()) { _ in
            throw CocoaError(.fileWriteUnknown)
        }
        let view = FoodConfirmationView(model: model, leave: {})
            .environment(\.dynamicTypeSize, .accessibility5)
        XCTAssertFalse(String(describing: view).isEmpty)
    }

    func testSaveFailurePreservesPopulatedStateAndOffersRecoveryMessage() throws {
        let initial = try fixtureState()
        let model = FoodConfirmationViewModel(state: initial) { _ in
            throw CocoaError(.fileWriteUnknown)
        }
        model.send(.accept)
        model.send(.setQuantity(175, .grams))
        model.save()

        XCTAssertEqual(model.state.selectedCandidate, initial.selectedCandidate)
        XCTAssertEqual(model.state.quantity.value, 175)
        guard case let .saveFailed(message) = model.state.phase else {
            return XCTFail("Expected a recoverable save failure")
        }
        XCTAssertTrue(message.contains("try again"))
    }

    private func fixtureState() throws -> FoodConfirmationState {
        let evidenceID = try EvidenceID("00000000-0000-0000-0000-000000000001")
        let releaseID = try ExternalIdentifier("synthetic:presentation-v1")
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let evidence = try CaptureEvidence(
            evidenceID: evidenceID,
            kind: .synthetic,
            capturedAt: date,
            locale: LedgerText("en_GB"),
            captureMethod: LedgerText("presentation_fixture"),
            captureMethodVersion: LedgerText("v1"),
            originalPayload: .text(LedgerText("populated evidence"))
        )
        let release = SourceRelease(
            sourceReleaseID: releaseID,
            sourceID: try ExternalIdentifier("synthetic"),
            releasedAt: date,
            artifactHash: try SHA256Digest(String(repeating: "a", count: 64)),
            schemaVersion: try LedgerText("v1"),
            pipelineVersion: try LedgerText("v1"),
            licence: try LedgerText("fixture"),
            attribution: try LedgerText("fixture"),
            manifestHash: try SHA256Digest(String(repeating: "b", count: 64))
        )
        let identity = try DecisiveIdentity(
            preparation: PreparationState(kind: .asSold),
            bone: .notApplicable,
            skin: .notApplicable,
            drained: .notApplicable,
            packingMedium: .named(LedgerText("none")),
            fortification: .unfortified,
            servingBasis: .per100Grams
        )
        let nutrients = try NutrientSet(entries: NutrientKey.allCases.map {
            try NutrientEntry(key: $0, value: .unknown(.notDeclared))
        })
        let quantity = try PositiveQuantity(value: 100, unit: .grams)
        let candidate = try PopulatedFoodCandidate(
            candidate: ProviderNeutralCandidate(
                sourceReleaseID: releaseID,
                recordID: ExternalIdentifier("record:1"),
                identity: identity,
                edibleQuantity: .known(quantity, conversionVersionID: nil),
                nutrients: nutrients,
                evidenceIDs: [evidenceID]
            ),
            name: LedgerText("Fixture food"),
            itemClass: .food
        )
        return FoodConfirmationState(input: try PopulatedFoodConfirmation(
            evidence: [evidence],
            sourceReleases: [release],
            candidates: [candidate],
            expectedIdentity: identity,
            expectedEdibleQuantity: .known(quantity, conversionVersionID: nil)
        ))
    }
}
