import Foundation
import FoodLedgerApplication
import FoodLedgerDomain
import FoodLedgerPresentation
import FoodLedgerTestSupport
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
        // B1: before the estimate, mL on this per 100 g record logs without nutrition, and both
        // "Enter grams instead" and the sourced estimate are offered.
        XCTAssertEqual(model.logButtonTitle, "Log without nutrition")
        XCTAssertEqual(model.sourceUnitAction?.actionTitle, "Enter grams instead")
        model.applyAvailableVolumeConversion()
        XCTAssertNil(model.unitBasisMismatch, "the estimate reaches the gram basis")
        XCTAssertEqual(model.logButtonTitle, "Log 130 kcal")
        // The main screen names the estimate plainly; the method identifier stays in its details.
        XCTAssertEqual(model.conversionMethodLabel, "Whole milk volume estimate (1.03 g per mL, PHE)")
        XCTAssertFalse(try XCTUnwrap(model.conversionMethodLabel).contains("cofid-"))
        XCTAssertFalse(try XCTUnwrap(model.conversionMethodLabel).contains("CoFID"), "the factor is not a CoFID field")
        XCTAssertTrue(try XCTUnwrap(model.state.quantity.conversion).methodVersion.value.contains("milk"), "identifier kept in the state")
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

    /// Owner change: the available estimate sits above Log, stating the energy applying it would
    /// give; Log keeps "Log without nutrition" and nothing applies until the tap.
    func testVolumeEstimateLogBarActionShowsBesideLogUntilApplied() throws {
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
        XCTAssertNil(model.volumeEstimateLogBarAction, "no amount yet")
        model.send(.setQuantity(200, .grams))
        XCTAssertNil(model.volumeEstimateLogBarAction, "grams need no estimate")

        model.send(.setQuantity(200, .millilitres))
        let action = try XCTUnwrap(model.volumeEstimateLogBarAction)
        XCTAssertEqual(action.title, "Use sourced whole-milk volume estimate (about 130 kcal)")
        XCTAssertEqual(action.accessibilityLabel, "Use sourced whole-milk volume estimate, about 130 kcal")
        XCTAssertEqual(model.logButtonTitle, "Log without nutrition", "Log keeps its own title")
        XCTAssertNil(model.state.quantity.conversion, "showing the action applies nothing")

        model.applyAvailableVolumeConversion()
        XCTAssertNil(model.volumeEstimateLogBarAction, "hidden once applied")
        XCTAssertEqual(model.logButtonTitle, "Log 130 kcal", "the action's energy is the applied Log total")
        model.removeOfferedVolumeConversion()
        XCTAssertNotNil(model.volumeEstimateLogBarAction, "offered again after removal")

        model.send(.setQuantity(250, .millilitres))
        XCTAssertEqual(model.volumeEstimateLogBarAction?.title, "Use sourced whole-milk volume estimate (about 162 kcal)", "257.5 g × 63 kcal/100 g")
        model.send(.setQuantity(0.5, .millilitres))
        XCTAssertEqual(model.volumeEstimateLogBarAction?.title, "Use sourced whole-milk volume estimate (less than 1 kcal)")

        let withoutSource = FoodConfirmationViewModel(
            state: FoodConfirmationState(input: try PopulatedFoodConfirmation(
                evidence: route.confirmation.evidence, sourceReleases: route.confirmation.sourceReleases,
                candidates: [milk], expectedIdentity: milk.candidate.identity,
                expectedEdibleQuantity: milk.candidate.edibleQuantity)),
            volumeConversionOffering: policy
        ) { _ in throw CocoaError(.fileWriteUnknown) }
        withoutSource.send(.setQuantity(200, .millilitres))
        XCTAssertNil(withoutSource.volumeEstimateLogBarAction, "not offered when the tap could not apply it")
        XCTAssertNotNil(withoutSource.availableVolumeConversion)
        XCTAssertNil(withoutSource.applicableVolumeConversion, "the amount-section button is gated the same way")
        XCTAssertEqual(model.applicableVolumeConversion, model.availableVolumeConversion)
    }

    /// An offering whose applied amount still cannot be scaled leaves the kcal out (never
    /// invented), and the action is disabled while a save is in progress.
    func testVolumeEstimateLogBarActionOmitsUnknownEnergyAndDisablesWhileSaving() throws {
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
        let stub = UnscalableVolumeOffering(sourceRelease: policy.sourceRelease, sourceURL: policy.sourceURL)
        let unknown = FoodConfirmationViewModel(
            state: FoodConfirmationState(input: input), volumeConversionOffering: stub
        ) { _ in throw CocoaError(.fileWriteUnknown) }
        unknown.send(.setQuantity(200, .millilitres))
        let fallback = try XCTUnwrap(unknown.volumeEstimateLogBarAction)
        XCTAssertEqual(fallback.title, "Use sourced whole-milk volume estimate", "no kcal when applying gives none")
        XCTAssertEqual(fallback.accessibilityLabel, "Use sourced whole-milk volume estimate")
        XCTAssertTrue(fallback.isEnabled)

        var enabledDuringSave: Bool?
        weak var saving: FoodConfirmationViewModel?
        let model = FoodConfirmationViewModel(
            state: FoodConfirmationState(input: input), volumeConversionOffering: policy
        ) { _ in
            enabledDuringSave = saving?.volumeEstimateLogBarAction?.isEnabled
            throw CocoaError(.fileWriteUnknown)
        }
        saving = model
        model.send(.setQuantity(200, .millilitres))
        XCTAssertEqual(model.volumeEstimateLogBarAction?.isEnabled, true)
        model.save()
        XCTAssertEqual(enabledDuringSave, false, "disabled while saving")
        XCTAssertEqual(model.volumeEstimateLogBarAction?.isEnabled, true, "enabled again after a failed save")
        XCTAssertNil(model.state.quantity.conversion, "saving never applies the estimate")
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
            "Enter an amount greater than zero."
        )
        XCTAssertEqual(
            FoodConfirmationViewModel.message(
                for: FoodConfirmationSaveError.unmetRequirements([.decideDifference(.preparation)])
            ),
            "Answer ‘How was it prepared?’ to log."
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
        model.send(.setQuantity(175, .grams))
        model.log()

        XCTAssertEqual(model.state.selectedCandidate, initial.selectedCandidate)
        XCTAssertEqual(model.state.quantity.value, 175)
        guard case let .saveFailed(message) = model.state.phase else {
            return XCTFail("Expected a recoverable save failure")
        }
        XCTAssertTrue(message.contains("try again"))
    }

    func testSaveGuidanceUsesTypedRequirementsAndOneLogAction() throws {
        let model = FoodConfirmationViewModel(state: try fixtureState()) { _ in
            XCTFail("Guidance must not save")
            throw CocoaError(.fileWriteUnknown)
        }
        XCTAssertTrue(model.requirements.isEmpty, "Acceptance is the Log press, not a requirement")
        model.send(.setQuantity(nil, .grams))
        XCTAssertEqual(model.requirements, [.amountMissing])
        XCTAssertFalse(model.canLog)
        XCTAssertEqual(model.blockedReason, "Enter an amount greater than zero.")
        model.send(.setQuantity(100, .grams))
        XCTAssertTrue(model.canLog)
        model.send(.setQuantity(2, .count))
        XCTAssertEqual(model.requirements, [.countNeedsMeasuredAmount])
        model.send(.setQuantity(100, .grams))
        model.send(.setPlateChoice(.missing))
        XCTAssertEqual(model.requirements, [.emptyPlateWeightMissing])
        for requirement in model.requirements + [.sourceIdentityMissing([.skin])] {
            XCTAssertFalse(FoodLogRequirementText.text(requirement).contains("Open"))
            XCTAssertFalse(FoodLogRequirementText.text(requirement).contains("disclosure"))
        }
    }

    /// Contract test 16: whenever Log would write an estimate, the notice is on the primary screen
    /// model (not a details disclosure), and inline decisions drive Log and the blocked reason.
    func testEstimateNoticeAndInlineDecisionsDriveTheLogAction() throws {
        let base = try fixtureState().input
        let identity = base.candidates[0].candidate.identity
        let raw = try DecisiveIdentity(preparation: PreparationState(kind: .raw), bone: identity.bone, skin: identity.skin,
            drained: identity.drained, packingMedium: identity.packingMedium, fortification: identity.fortification,
            servingBasis: identity.servingBasis)
        let input = try PopulatedFoodConfirmation(evidence: base.evidence, sourceReleases: base.sourceReleases,
            candidates: base.candidates, expectedIdentity: raw, expectedEdibleQuantity: base.expectedEdibleQuantity)
        var saves = 0
        let model = FoodConfirmationViewModel(state: FoodConfirmationState(input: input)) { state in
            saves += 1
            throw CocoaError(.fileWriteUnknown)
        }
        XCTAssertEqual(model.pendingDifferences, [.preparation])
        XCTAssertFalse(model.canLog)
        XCTAssertEqual(model.blockedReason, "Answer ‘How was it prepared?’ to log.")
        XCTAssertFalse(model.savesEstimate)
        model.log()
        XCTAssertEqual(saves, 0, "A blocked Log press never saves")
        model.send(.decideDifference(.preparation, .matchesSource))
        XCTAssertTrue(model.canLog)
        XCTAssertFalse(model.savesEstimate)
        model.send(.decideDifference(.preparation, .notSure))
        XCTAssertTrue(model.savesEstimate)
        XCTAssertEqual(FoodConfirmationViewModel.estimateNotice, "Logged as an estimate. Unknown details stay unknown.")
        XCTAssertEqual(model.offeredChoices(.preparation).map {
            FoodLogRequirementText.choice($0, facet: .preparation, source: model.sourceState(.preparation))
        }, ["As sold, as the source", "Raw", "Cooked", "Reheated", "Not sure"])
        model.log()
        XCTAssertEqual(saves, 1, "One Log press saves once")
        XCTAssertEqual(model.state.decision, .accepted)
        let view = FoodConfirmationView(model: model, leave: {}).environment(\.dynamicTypeSize, .accessibility5)
        XCTAssertFalse(String(describing: view).isEmpty)
    }

    /// Review fix 6: a reopened entry older than the window shows its stored time read-only, and an
    /// amount-only edit saves with the stored occurredAt unchanged (no clamped time is written back).
    func testReopenedTenDayOldEntryAmountEditKeepsStoredTime() throws {
        struct Clock: LedgerClock { let value: Date; func now() -> Date { value } }
        final class IDs: LedgerIDGenerating, @unchecked Sendable {
            private var value = 9_000
            func makeID<Tag>(_ tag: Tag.Type) throws -> LedgerID<Tag> {
                value += 1; return try LedgerID(String(format: "00000000-0000-0000-0000-%012x", value))
            }
        }
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let old = now.addingTimeInterval(-10 * 86_400)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Europe/London"))
        let store = InMemoryFoodLedgerStore()
        let ids = IDs()
        func service(at date: Date) -> FoodConfirmationService {
            let ledger = FoodLedgerService(actorID: try! LedgerID("00000000-0000-0000-0000-000000000999"), committer: store,
                clock: Clock(value: date), encoder: FoundationCanonicalJSONEncoder(), digester: SHA256Digester())
            return FoodConfirmationService(ledger: ledger, reader: store, clock: Clock(value: date), ids: ids,
                digester: SHA256Digester(), calendar: calendar)
        }
        var state = try fixtureState()
        state.decision = .accepted
        let saved = try service(at: old).save(state, operationID: LedgerID("00000000-0000-0000-0000-000000000501"))
        XCTAssertEqual(saved.logItemVersion.occurredAt, old)
        let current = service(at: now)
        let reopened = try XCTUnwrap(current.reopen(logItemID: saved.logItem.logItemID))
        let model = FoodConfirmationViewModel(state: reopened, now: { now }, calendar: calendar) { state in
            try current.save(state, operationID: LedgerID("00000000-0000-0000-0000-000000000502"))
        }
        XCTAssertFalse(model.canChangeOccurredAt, "Outside the window the time is shown read-only")
        XCTAssertEqual(model.displayedOccurredAt, old)
        model.send(.setQuantity(150, .grams))
        XCTAssertTrue(model.requirements.isEmpty)
        model.log()
        let result = try XCTUnwrap(model.savedResult)
        XCTAssertEqual(result.logItemVersion.occurredAt, old)
        XCTAssertEqual(result.logItemVersion.reportingDate, saved.logItemVersion.reportingDate)
        XCTAssertEqual(result.logItemVersion.edibleQuantity.value, 150)
    }

    func testMissingIdentityErrorNamesSpecificFields() {
        let message = FoodConfirmationViewModel.message(
            for: FoodConfirmationSaveError.unmetRequirements([.sourceIdentityMissing([.preparation, .packingMedium])])
        )
        XCTAssertTrue(message.contains("raw/cooked preparation"))
        XCTAssertTrue(message.contains("packing liquid or none"))
        XCTAssertTrue(message.contains("Choose a different match or add the food details"))
    }

    /// B2: the unit picker clears the amount through the reducer, so Log is blocked with the
    /// amount requirement until a new amount is typed; Log then states whole kcal.
    func testUnitPickerClearsTheAmountAndBlocksLog() throws {
        let model = FoodConfirmationViewModel(state: try fixtureState(knownProtein: true)) { _ in
            throw CocoaError(.fileWriteUnknown)
        }
        model.send(.setQuantity(150, .grams))
        XCTAssertTrue(model.canLog)
        model.chooseQuantityUnit(.millilitres)
        XCTAssertNil(model.state.quantity.value)
        XCTAssertEqual(model.requirements, [.amountMissing])
        XCTAssertFalse(model.canLog)
        XCTAssertEqual(model.blockedReason, "Enter an amount greater than zero.")
        model.chooseQuantityUnit(.grams)
        model.send(.setQuantityText("150"))
        XCTAssertTrue(model.canLog)
    }

    /// B1: an amount whose unit cannot be scaled to the source basis logs without nutrition, says
    /// so on the button, and offers the source's unit inline (clearing the amount). The v5 rule is
    /// unchanged: such a save is still allowed.
    func testUnscalableUnitLogsWithoutNutritionAndOffersTheSourceUnit() throws {
        let grams = FoodConfirmationViewModel(state: try fixtureState(knownProtein: true), savesFavourite: true,
                                              favouriteAction: { _ in }) { _ in throw CocoaError(.fileWriteUnknown) }
        grams.send(.setQuantity(200, .millilitres))
        XCTAssertEqual(grams.unitBasisMismatch, .millilitresOnGramBasis)
        XCTAssertEqual(grams.logButtonTitle, "Log without nutrition and save favourite", "both apply")
        grams.savesFavourite = false
        XCTAssertEqual(grams.logButtonTitle, "Log without nutrition")
        grams.savesFavourite = true
        XCTAssertTrue(grams.canLog, "presentation only: confirmation v5 still allows the save")
        XCTAssertEqual(grams.sourceUnitAction?.actionTitle, "Enter grams instead")
        XCTAssertEqual(grams.quantityBasisWarning, "This food’s nutrition is per 100 g, and millilitres cannot be converted to grams for it. Logged in mL, this entry has no nutrition.")
        grams.useSourceBasisUnit()
        XCTAssertEqual(grams.state.quantity.unit, .grams)
        XCTAssertNil(grams.state.quantity.value, "the amount is cleared, not reread in grams")
        XCTAssertNil(grams.unitBasisMismatch)
        XCTAssertFalse(grams.canLog)
        XCTAssertEqual(grams.logButtonTitle, "Log and save favourite")

        let millilitres = FoodConfirmationViewModel(state: try fixtureState(basis: .per100Millilitres, knownProtein: true)) { _ in
            throw CocoaError(.fileWriteUnknown)
        }
        millilitres.send(.setQuantity(200, .grams))
        XCTAssertEqual(millilitres.unitBasisMismatch, .gramsOnMillilitreBasis)
        XCTAssertEqual(millilitres.sourceUnitAction?.actionTitle, "Enter mL instead")
        XCTAssertEqual(millilitres.logButtonTitle, "Log without nutrition")
        millilitres.useSourceBasisUnit()
        XCTAssertEqual(millilitres.state.quantity.unit, .millilitres)
        XCTAssertNil(millilitres.state.quantity.value)
        millilitres.send(.setQuantity(200, .millilitres))
        XCTAssertEqual(millilitres.logButtonTitle, "Log")
        // A measured weight is grams whatever the picker says: no unit action can resolve it.
        millilitres.send(.beginDirectWeight)
        millilitres.send(.setDirectWeight(150))
        XCTAssertEqual(millilitres.unitBasisMismatch, .gramsOnMillilitreBasis)
        XCTAssertNil(millilitres.sourceUnitAction)
        XCTAssertEqual(millilitres.logButtonTitle, "Log without nutrition")
        // A count converted to grams scales on a per 100 g source.
        let count = FoodConfirmationViewModel(state: try fixtureState(knownProtein: true)) { _ in throw CocoaError(.fileWriteUnknown) }
        count.chooseQuantityUnit(.count)
        count.send(.setQuantity(2, .count))
        count.send(.setConversion(QuantityConversionDraft(
            convertedQuantity: try PositiveQuantity(value: 150, unit: .grams), methodVersion: try LedgerText("measured-v1"))))
        XCTAssertNil(count.unitBasisMismatch)
    }

    /// Owner decision D: Confirm states a time outside the window under When (as well as in the
    /// Log bar), and shows the backdating notice only while When is Now.
    func testWhenRequirementAndNoticeAreInline() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        var state = try fixtureState()
        state.occurredAt = now.addingTimeInterval(-8 * 86_400 - 3_600)
        let model = FoodConfirmationViewModel(state: state, now: { now }, calendar: Calendar(identifier: .gregorian),
                                              whenNotice: FoodLogText.backdatingLimitNotice) { _ in throw CocoaError(.fileWriteUnknown) }
        XCTAssertEqual(model.whenRequirementText, "Choose a time within the last 7 days.")
        XCTAssertEqual(model.blockedReason, model.whenRequirementText)
        model.send(.setOccurredAt(now.addingTimeInterval(3_600)))
        XCTAssertEqual(model.whenRequirementText, "Choose a time that is not in the future.")
        model.send(.setOccurredAt(nil))
        XCTAssertNil(model.whenRequirementText)
        XCTAssertEqual(model.whenNotice, "Entries can be logged up to 7 days back.")
    }

    /// Review fix: a unit change clears the typed count conversion as well as the state's, so
    /// count, g, count never brings an earlier conversion back.
    func testCountToGramsToCountDoesNotRestoreAnEarlierConversion() throws {
        let model = FoodConfirmationViewModel(state: try fixtureState(knownProtein: true)) { _ in throw CocoaError(.fileWriteUnknown) }
        let locale = Locale(identifier: "en_GB")
        var fields = FoodConfirmationView.ConversionFields(text: "150", unit: .grams, method: "kitchen scale")
        model.chooseQuantityUnit(.count)
        model.send(.setQuantity(2, .count))
        model.send(.setConversion(fields.draft(locale: locale)))
        XCTAssertEqual(model.state.quantity.conversion?.convertedQuantity.value, 150)
        XCTAssertEqual(model.conversionMethodLabel, "kitchen scale", "a typed method is shown as typed")
        model.chooseQuantityUnit(.grams)
        fields = .cleared // what the view does on the switch
        XCTAssertNil(model.state.quantity.conversion)
        model.chooseQuantityUnit(.count)
        model.send(.setConversion(fields.draft(locale: locale)))
        XCTAssertNil(model.state.quantity.conversion, "nothing comes back")
        XCTAssertEqual(fields, FoodConfirmationView.ConversionFields(text: "", unit: .grams, method: ""))
        XCTAssertTrue(model.requirements.contains(.countNeedsMeasuredAmount))
        XCTAssertNil(FoodConfirmationView.ConversionFields(text: "150", unit: .grams, method: " ").draft(locale: locale))
    }

    /// #296: three eggs, 168 g and an empty method. Log stays blocked by the unchanged rule, and the
    /// field-local text names the one missing part instead of repeating the whole requirement.
    func testCountConversionNamesTheMissingMethodAndTheRuleIsUnchanged() throws {
        let model = FoodConfirmationViewModel(state: try fixtureState(knownProtein: true)) { _ in throw CocoaError(.fileWriteUnknown) }
        let locale = Locale(identifier: "en_GB")
        model.chooseQuantityUnit(.count)
        model.send(.setQuantity(3, .count))
        let weightOnly = FoodConfirmationView.ConversionFields(text: "168", unit: .grams, method: "")
        model.send(.setConversion(weightOnly.draft(locale: locale)))
        XCTAssertEqual(model.requirements, [.countNeedsMeasuredAmount])
        XCTAssertFalse(model.canLog)
        XCTAssertEqual(weightOnly.requirementText(locale: locale),
                       "Add how you measured the 168 g, for example kitchen scale or package weight. If you did not measure it, use ‘Enter measured weight’ and choose ‘I estimated it’.")
        XCTAssertEqual(FoodConfirmationView.ConversionFields(text: "168", unit: .grams, method: "  ").requirementText(locale: locale),
                       weightOnly.requirementText(locale: locale), "whitespace is not a method")
        XCTAssertEqual(FoodConfirmationView.ConversionFields(text: "200", unit: .millilitres, method: "").requirementText(locale: locale)?
            .hasPrefix("Add how you measured the 200 mL"), true)
        XCTAssertEqual(FoodConfirmationView.ConversionFields(text: "", unit: .grams, method: "kitchen scale").requirementText(locale: locale),
                       "Enter the total edible weight or volume, greater than zero.")
        XCTAssertEqual(FoodConfirmationView.ConversionFields(text: "0", unit: .grams, method: "kitchen scale").requirementText(locale: locale),
                       "Enter the total edible weight or volume, greater than zero.")
        XCTAssertEqual(FoodConfirmationView.ConversionFields.cleared.requirementText(locale: locale),
                       "Enter the total edible weight or volume and how you measured it.")

        // The method is the user's own words, stored as typed; nothing is chosen for them.
        let complete = FoodConfirmationView.ConversionFields(text: "168", unit: .grams, method: "kitchen scale")
        XCTAssertNil(complete.requirementText(locale: locale))
        model.send(.setConversion(complete.draft(locale: locale)))
        XCTAssertTrue(model.requirements.isEmpty)
        XCTAssertTrue(model.canLog)
        XCTAssertEqual(model.state.quantity.conversion?.methodVersion.value, "kitchen scale")
        XCTAssertNil(model.state.quantity.conversion?.sourceReleaseID)
        XCTAssertNil(model.state.quantity.conversion?.evidenceID)
        XCTAssertNil(model.state.quantity.directWeight, "the count conversion never becomes a weight declaration")
    }

    func testReferenceBasisAndConsumedPreviewNeverInferDensity() throws {
        let model = FoodConfirmationViewModel(state: try fixtureState(knownProtein: true)) { _ in
            throw CocoaError(.fileWriteUnknown)
        }
        XCTAssertEqual(model.nutritionReferenceTitle, "Reference nutrition: Per 100 g")
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
        XCTAssertEqual(model.nutritionReferenceTitle, "Reference nutrition: Per 100 mL")
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
        XCTAssertEqual(model.nutritionReferenceTitle, "Reference nutrition: Per 100 g")
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
        XCTAssertTrue(model.requirements.isEmpty)
        XCTAssertNil(model.quantityBasisWarning)
        XCTAssertEqual(model.consumedNutrition.first { $0.key == .protein }?.knownAmount, 12)
        XCTAssertTrue(model.consumedNutrition.first { $0.key == .protein }?.includesEstimates == true)
        model.send(.setQuantityText("abc"))
        XCTAssertTrue(model.originalAmountRequirement?.contains("clear") == true)
        XCTAssertFalse(model.requirements.isEmpty)
        XCTAssertTrue(model.consumedNutrition.isEmpty)
        model.send(.setQuantityText(""))
        XCTAssertNil(model.originalAmountRequirement)
        XCTAssertTrue(model.requirements.isEmpty)
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
        XCTAssertEqual(model.nutritionReview.mainRows.first { $0.key == .fatTotal }?.value, "Unknown")
        model.send(.setQuantityText("half"))
        XCTAssertEqual(model.state.quantity.value, 0.5)
        XCTAssertTrue(model.nutritionReview.isConsumed)
        XCTAssertEqual(model.nutritionReview.basis, "For 0.5 g eaten")
        XCTAssertEqual(model.nutritionReview.mainRows.first { $0.key == .protein }?.value, "Less than 0.1 g",
                       "0.04 g is below the one-decimal display, but never shown as zero")
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

    /// #212: the amount fields use a decimal pad, so Confirm hands the reducer canonical text. A
    /// comma decimal is accepted where it is the locale's separator and whole grams stay exact.
    func testConfirmReducerAcceptsDecimalPadTextPerLocale() throws {
        let german = Locale(identifier: "de_DE"), english = Locale(identifier: "en_GB")
        for (text, locale, expected) in [("1,5", german, 1.5), ("1500", german, 1500.0), ("1500", english, 1500), ("0.5", english, 0.5)] {
            var state = try fixtureState()
            FoodConfirmationReducer.reduce(state: &state, action: .setQuantityText(FoodAmountFieldText.reducerText(text, locale: locale)))
            XCTAssertEqual(state.quantity.value, expected, "\(text) in \(locale.identifier)")
            XCTAssertEqual(state.quantity.invalidOriginalAmountText, false, "\(text) in \(locale.identifier)")
        }
        // Ambiguous grouping is refused with the existing invalid-amount state, never 1.5 g.
        let french = Locale(identifier: "fr_FR")
        for (text, locale) in [("1.500", german), ("1 500", french), ("1,5", english)] {
            var state = try fixtureState()
            FoodConfirmationReducer.reduce(state: &state, action: .setQuantityText(FoodAmountFieldText.reducerText(text, locale: locale)))
            XCTAssertNil(state.quantity.value, "\(text) in \(locale.identifier)")
            XCTAssertEqual(state.quantity.invalidOriginalAmountText, true, "\(text) in \(locale.identifier)")
        }
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

/// Offers a "conversion" that stays in millilitres, so the per 100 g source still cannot be
/// scaled after applying it: the energy for the action is unknown.
private struct UnscalableVolumeOffering: FoodVolumeConversionOffering {
    let sourceRelease: SourceRelease
    let sourceURL: URL

    func offer(for candidate: PopulatedFoodCandidate, original: PositiveQuantity) throws -> QuantityConversionDraft? {
        guard original.unit == .millilitres else { return nil }
        return QuantityConversionDraft(convertedQuantity: original, methodVersion: try LedgerText("stub-unscalable-v1"),
                                       sourceReleaseID: sourceRelease.sourceReleaseID)
    }
}
