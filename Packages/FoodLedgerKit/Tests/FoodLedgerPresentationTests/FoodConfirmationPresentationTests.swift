import Foundation
import FoodLedgerApplication
import FoodLedgerDomain
import FoodLedgerPresentation
import FoodGenericSearch
import SwiftUI
import XCTest

@MainActor
final class FoodConfirmationPresentationTests: XCTestCase {
    func testDocumentedMilkVolumeEstimateRequiresExplicitTapAndClearsOnEdit() throws {
        let policy = try CoFIDWholeMilkVolumeConversion()
        let search = try CoFIDGenericFoodSearch(ids: RandomLedgerIDGenerator())
        let request = GenericFoodSearchRequest(
            text: try LedgerText("Milk, whole, pasteurised, average"),
            identity: GenericFoodIdentityQuery(), capturedAt: Date(timeIntervalSince1970: 1_700_000_000),
            locale: try LedgerText("en_GB")
        )
        guard case let .confirmation(route) = try search.search(request),
              let milk = route.matches.map(\.candidate).first(where: policy.applies(to:)) else {
            return XCTFail("Expected CoFID milk")
        }
        let input = try PopulatedFoodConfirmation(
            evidence: route.confirmation.evidence,
            sourceReleases: route.confirmation.sourceReleases + [policy.sourceRelease],
            candidates: [milk], expectedIdentity: milk.candidate.identity,
            expectedEdibleQuantity: milk.candidate.edibleQuantity
        )
        let model = FoodConfirmationViewModel(
            state: FoodConfirmationState(input: input), volumeConversionOffering: policy
        ) { _ in throw CocoaError(.fileWriteUnknown) }
        model.send(.setQuantity(200, .millilitres))
        XCTAssertNotNil(model.availableVolumeConversion)
        XCTAssertNil(model.state.quantity.conversion)
        XCTAssertTrue(model.consumedNutrition.allSatisfy { $0.knownAmount == nil })
        model.applyAvailableVolumeConversion()
        XCTAssertEqual(model.state.quantity.conversion?.convertedQuantity.value, 206)
        XCTAssertTrue(model.quantityBasisWarning?.contains("Estimated edible mass") == true)
        XCTAssertEqual(try XCTUnwrap(model.consumedNutrition.first { $0.key == .energyConsumed }?.knownAmount), 129.78, accuracy: 0.0001)
        XCTAssertTrue(model.consumedNutrition.first { $0.key == .energyConsumed }?.includesEstimates == true)
        model.removeOfferedVolumeConversion()
        XCTAssertNil(model.state.quantity.conversion)
        model.applyAvailableVolumeConversion()
        model.send(.setQuantity(250, .millilitres))
        XCTAssertNil(model.state.quantity.conversion)
        XCTAssertTrue(model.consumedNutrition.allSatisfy { $0.knownAmount == nil })
    }

    func testArchiveGuidanceStatesIntegrityAndIndependentDeletionBoundaries() {
        XCTAssertTrue(FoodArchiveGuidance.integrity.contains("check integrity"))
        XCTAssertTrue(FoodArchiveGuidance.integrity.contains("do not encrypt or anonymise"))
        XCTAssertTrue(FoodArchiveGuidance.deletion.contains("does not delete"))
        XCTAssertTrue(FoodArchiveGuidance.deletion.contains("exported separately"))
    }

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

    func testSaveGuidanceExplainsAcceptanceAndQuantityBeforeSaving() throws {
        let model = FoodConfirmationViewModel(state: try fixtureState()) { _ in
            XCTFail("Guidance must not save")
            throw CocoaError(.fileWriteUnknown)
        }
        XCTAssertTrue(model.saveRequirements.contains { $0.contains("Accept this match") })
        model.send(.accept)
        model.send(.setQuantity(nil, .grams))
        XCTAssertTrue(model.saveRequirements.contains { $0.contains("Amount eaten") })
        model.send(.setQuantity(100, .grams))
        XCTAssertTrue(model.saveRequirements.isEmpty)
        model.send(.setQuantity(2, .count))
        XCTAssertTrue(model.saveRequirements.contains { $0.contains("measured total") })
        model.send(.setQuantity(100, .grams))
        model.send(.setPlateChoice(.missing))
        XCTAssertTrue(model.saveRequirements.contains { $0.contains("empty plate") })
    }

    func testMissingIdentityErrorNamesSpecificFields() {
        let message = FoodConfirmationViewModel.message(
            for: FoodConfirmationSaveError.unresolvedMandatoryIdentity([.preparation, .packingMedium])
        )
        XCTAssertTrue(message.contains("raw/cooked preparation"))
        XCTAssertTrue(message.contains("packing liquid or none"))
        XCTAssertTrue(message.contains("Review or correct food details"))
    }

    func testReferenceBasisAndConsumedPreviewNeverInferDensity() throws {
        let model = FoodConfirmationViewModel(state: try fixtureState(knownProtein: true)) { _ in
            throw CocoaError(.fileWriteUnknown)
        }
        XCTAssertEqual(model.nutritionReferenceTitle, "Reference nutrition — Per 100 g")
        XCTAssertEqual(FoodConfirmationViewModel.nutrientLabel(.energyConsumed), "Energy")
        model.send(.setQuantity(200, .millilitres))
        XCTAssertTrue(model.consumedNutrition.allSatisfy { $0.knownAmount == nil })
        XCTAssertNotNil(model.quantityBasisWarning)
        model.send(.setQuantity(200, .grams))
        XCTAssertEqual(model.consumedNutrition.first { $0.key == .protein }?.knownAmount, 16)
        XCTAssertTrue(model.consumedNutrition.first { $0.key == .protein }?.includesEstimates == true)
        XCTAssertNil(model.consumedNutrition.first { $0.key == .energyConsumed }?.knownAmount)
        model.send(.setQuantity(2, .count))
        XCTAssertTrue(model.consumedNutrition.isEmpty)
        model.send(.setConversion(QuantityConversionDraft(
            convertedQuantity: try PositiveQuantity(value: 150, unit: .grams),
            methodVersion: try LedgerText("user-measured-v1"))))
        XCTAssertEqual(model.consumedNutrition.first { $0.key == .protein }?.knownAmount, 12)
    }

    func testVolumeReferenceScalesOnlySupportedVolume() throws {
        let model = FoodConfirmationViewModel(state: try fixtureState(basis: .per100Millilitres, knownProtein: true)) { _ in
            throw CocoaError(.fileWriteUnknown)
        }
        XCTAssertEqual(model.nutritionReferenceTitle, "Reference nutrition — Per 100 mL")
        model.send(.setQuantity(200, .millilitres))
        XCTAssertEqual(model.consumedNutrition.first { $0.key == .protein }?.knownAmount, 16)
        model.send(.setQuantity(200, .grams))
        XCTAssertTrue(model.consumedNutrition.allSatisfy { $0.knownAmount == nil })
    }

    func testBoundedSourceRemainsVisibleAndIsNotAnExactConsumedTotal() throws {
        let state = try fixtureState(boundedProtein: true)
        let model = FoodConfirmationViewModel(state: state) { _ in throw CocoaError(.fileWriteUnknown) }
        model.send(.setQuantity(200, .grams))
        XCTAssertNil(model.consumedNutrition.first { $0.key == .protein }?.knownAmount)
        XCTAssertEqual(model.state.selectedCandidate.candidate.nutrients, state.selectedCandidate.candidate.nutrients)
        guard case .bounded = model.state.selectedCandidate.candidate.nutrients.entries.first(where: { $0.key == .protein })?.value else {
            return XCTFail("Source bounds must remain intact")
        }
    }

    func testPlatePreviewUsesSameSubtractionAsSavingAndInvalidAmountsStayUnavailable() throws {
        let model = FoodConfirmationViewModel(state: try fixtureState(knownProtein: true)) { _ in
            throw CocoaError(.fileWriteUnknown)
        }
        let plate = try PlateWeightVersion(
            plateWeightVersionID: PlateWeightVersionID("00000000-0000-0000-0000-000000000002"),
            plateID: PlateID("00000000-0000-0000-0000-000000000003"), ordinal: VersionOrdinal(1),
            emptyWeight: PositiveQuantity(value: 50, unit: .grams), createdAt: Date(timeIntervalSince1970: 0))
        model.send(.setQuantity(250, .grams))
        let edible = try FoodQuantityCalculator.subtractPlate(
            total: PositiveQuantity(value: 250, unit: .grams), emptyPlate: plate)
        for choice in [PlateWeightChoice.saved(plate), .new(emptyWeight: plate.emptyWeight, superseding: nil)] {
            model.send(.setPlateChoice(choice))
            XCTAssertEqual(model.consumedNutrition.first { $0.key == .protein }?.knownAmount, edible.value * 8 / 100)
        }
        for value in [0.0, -1, 50, Double.nan, Double.infinity] {
            model.send(.setQuantity(value, .grams))
            XCTAssertTrue(model.consumedNutrition.isEmpty)
        }
        model.send(.setQuantity(250, .millilitres))
        XCTAssertTrue(model.consumedNutrition.isEmpty)
        model.send(.setPlateChoice(.missing))
        XCTAssertTrue(model.consumedNutrition.isEmpty)
    }

    func testConversionInvalidationAndCorrectionBasisAreExplicit() throws {
        let model = FoodConfirmationViewModel(state: try fixtureState(knownProtein: true)) { _ in
            throw CocoaError(.fileWriteUnknown)
        }
        model.send(.setQuantity(2, .count))
        model.send(.setConversion(QuantityConversionDraft(
            convertedQuantity: try PositiveQuantity(value: 150, unit: .grams), methodVersion: try LedgerText("measured-v1"))))
        model.send(.setQuantity(200, .millilitres))
        XCTAssertNil(model.state.quantity.conversion)
        XCTAssertTrue(model.consumedNutrition.allSatisfy { $0.knownAmount == nil })
        let corrected = try fixtureState(basis: .per100Millilitres, knownProtein: true).selectedCandidate
        model.send(.applyCorrection(FoodCorrection(name: corrected.name, brand: nil, variant: nil,
            identity: corrected.candidate.identity, nutrients: corrected.candidate.nutrients, reason: try LedgerText("Synthetic basis correction"))))
        XCTAssertEqual(model.nutritionReferenceTitle, "Reference nutrition — Per 100 g")
        XCTAssertEqual(model.consumedNutritionBasisLabel, "User-corrected calculation basis: Per 100 mL")
        XCTAssertEqual(model.consumedNutrition.first { $0.key == .protein }?.knownAmount, 16)
    }

    func testUserPresentationCorrectionDoesNotRenameTheRetainedSourceCandidate() throws {
        let model = FoodConfirmationViewModel(state: try fixtureState(knownProtein: true)) { _ in
            XCTFail("Editing presentation does not save"); throw CocoaError(.fileWriteUnknown)
        }
        let original = model.state.selectedCandidate
        let changed = try FoodCorrection(name: LedgerText("User-observed food name"), brand: LedgerText("User-observed brand"),
            variant: LedgerText("User variant"), identity: original.candidate.identity, nutrients: original.candidate.nutrients,
            reason: LedgerText("Observed identity correction with unchanged source nutrition."))
        model.send(.applyCorrection(changed))
        XCTAssertEqual(model.displayedName, changed.name)
        XCTAssertEqual(model.displayedBrand, changed.brand)
        XCTAssertEqual(model.displayedVariant, changed.variant)
        XCTAssertEqual(model.displayedIdentity, changed.identity)
        XCTAssertEqual(model.state.selectedCandidate, original)
        XCTAssertTrue(FoodConfirmationViewModel.message(for: FoodConfirmationSaveError.invalidReviewedSource).contains("serving basis changed"))
    }

    func testDirectWeightFieldRequirementsAndEstimatedConsumedPreview() throws {
        let model = FoodConfirmationViewModel(state: try fixtureState(knownProtein: true)) { _ in throw CocoaError(.fileWriteUnknown) }
        model.send(.setQuantity(200, .millilitres))
        model.send(.beginDirectWeight)
        XCTAssertNil(model.state.quantity.directWeight?.totalGrams)
        XCTAssertEqual(model.directWeightRequirements.count, 2)
        model.send(.setDirectWeight(150))
        XCTAssertEqual(model.directWeightRequirements.count, 1)
        model.send(.setWeightBasis(.estimated))
        model.send(.accept)
        XCTAssertTrue(model.saveRequirements.isEmpty)
        XCTAssertNil(model.quantityBasisWarning)
        XCTAssertEqual(model.consumedNutrition.first { $0.key == .protein }?.knownAmount, 12)
        XCTAssertTrue(model.consumedNutrition.first { $0.key == .protein }?.includesEstimates == true)
        model.send(.setQuantityText("abc"))
        XCTAssertTrue(model.originalAmountRequirement?.contains("clear") == true)
        XCTAssertFalse(model.saveRequirements.isEmpty)
        XCTAssertTrue(model.consumedNutrition.isEmpty)
        model.send(.setQuantityText(""))
        XCTAssertNil(model.originalAmountRequirement)
        XCTAssertTrue(model.saveRequirements.isEmpty)
        XCTAssertEqual(model.state.quantity.directWeight?.totalGrams, 150)
        model.send(.setWeightBasis(.measured))
        XCTAssertTrue(model.consumedNutrition.first { $0.key == .protein }?.includesEstimates == true,
            "Measured quantity must not upgrade augmented source nutrients")
    }

    func testNutritionFirstReferenceAndConsumedProjectionShareExistingCalculation() throws {
        var state = try fixtureState(knownProtein: true)
        state.quantity = FoodQuantityDraft()
        let model = FoodConfirmationViewModel(state: state) { _ in throw CocoaError(.fileWriteUnknown) }
        XCTAssertFalse(model.nutritionReview.isConsumed)
        XCTAssertEqual(model.nutritionReview.basis, "Per 100 g")
        XCTAssertEqual(model.nutritionReview.mainRows.map(\.key), [.energyConsumed, .protein, .carbohydrates, .fatTotal])
        XCTAssertEqual(model.nutritionReview.mainRows.first { $0.key == .fatTotal }?.value, "Not provided")
        model.send(.setQuantityText("half"))
        XCTAssertEqual(model.state.quantity.value, 0.5)
        XCTAssertTrue(model.nutritionReview.isConsumed)
        XCTAssertEqual(model.nutritionReview.basis, "For 0.5 g eaten")
        XCTAssertEqual(model.nutritionReview.mainRows.first { $0.key == .protein }?.value, "0.04 g")
        model.send(.setQuantity(0.5, .millilitres))
        XCTAssertFalse(model.nutritionReview.isConsumed)
        XCTAssertEqual(model.nutritionReview.basis, "Per 100 g")
    }
    func testSourceBasisDoesNotPrefillGenericIntakeAndCountSuggestionIsExplicit() throws {
        let input = try fixtureState().input
        let state = FoodConfirmationState(input: input, prefillSourceQuantity: false)
        let interpretation = FoodQueryInterpretation("half scallion pancake")
        let model = FoodConfirmationViewModel(state: state, searchInterpretation: interpretation) { _ in throw CocoaError(.fileWriteUnknown) }
        XCTAssertNil(model.state.quantity.value)
        XCTAssertFalse(model.nutritionReview.isConsumed)
        XCTAssertEqual(model.quantitySuggestion?.unit, "count")
        model.send(.setQuantity(0.5, .count))
        XCTAssertNil(model.state.quantity.conversion)
        XCTAssertFalse(model.nutritionReview.isConsumed)
        XCTAssertThrowsError(try model.state.calculatedEdibleQuantity())
    }
    func testBoundsAndSmallKnownValuesRemainHonest() throws {
        var state = try fixtureState(boundedProtein: true)
        state.quantity = FoodQuantityDraft()
        let model = FoodConfirmationViewModel(state: state) { _ in throw CocoaError(.fileWriteUnknown) }
        XCTAssertEqual(model.nutritionReview.mainRows.first { $0.key == .protein }?.value, "[1–2) g")
        model.send(.setQuantityText("1/2"))
        XCTAssertEqual(model.nutritionReview.mainRows.first { $0.key == .protein }?.value, "Unavailable · source is bounded")
        XCTAssertNotEqual(FoodNutritionReviewPresentation.number(0.000001), "0")
        model.send(.setQuantityText("1/0"))
        XCTAssertNil(model.state.quantity.value)
        XCTAssertFalse(model.nutritionReview.isConsumed)
    }

    private func fixtureState(basis: ResolutionBasis = .per100Grams, knownProtein: Bool = false, boundedProtein: Bool = false) throws -> FoodConfirmationState {
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
            servingBasis: basis
        )
        let protein = try ExactNutrientValue(amount: 8, unit: .grams,
            sourceValue: .exact(SourceExactNutrientValue(amount: 8, unit: LedgerText("g"), basis: basis)),
            provenance: [NutrientProvenance(sourceKind: .genericCompositionDataset,
                sourceID: ExternalIdentifier("synthetic"), sourceReleaseID: releaseID, recordID: ExternalIdentifier("record:1"))])
        let bounds = try NutrientBounds(lower: 1, upper: 2, lowerClosed: true, upperClosed: false,
            origin: .augmented, unit: .grams,
            sourceValue: .bounded(SourceBoundedNutrientValue(lower: 1, upper: 2, lowerClosed: true, upperClosed: false,
                unit: LedgerText("g"), basis: basis)), provenance: protein.provenance)
        let nutrients = try NutrientSet(entries: NutrientKey.allCases.map {
            try NutrientEntry(key: $0, value: $0 == .protein && boundedProtein ? .bounded(bounds) : knownProtein && $0 == .protein ? .augmented(protein) : .unknown(.notDeclared))
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
