import FoodLedgerApplication
import FoodLedgerDomain
import SwiftUI

@MainActor
public final class FoodConfirmationViewModel: ObservableObject {
    @Published public private(set) var state: FoodConfirmationState
    @Published public private(set) var savedResult: StoredFoodConfirmation?
    private let saveAction: @MainActor (FoodConfirmationState) throws -> StoredFoodConfirmation
    /// Writes `save_favourite_v1` for the logged entry version (#198). Nil hides "Save as favourite".
    private let favouriteAction: (@MainActor (LogItemVersionID) throws -> Void)?
    /// "Save as favourite" (the v5 D4 slot). The log save is unchanged; the favourite is a
    /// separate operation immediately afterwards.
    @Published public var savesFavourite: Bool
    @Published public private(set) var favouriteOutcome: FavouriteOutcome?
    public enum FavouriteOutcome: Equatable { case saved, failed }
    private let now: @Sendable () -> Date
    public let calendar: Calendar
    private let volumeConversionOffering: (any FoodVolumeConversionOffering)?
    private let searchInterpretation: FoodQueryInterpretation?
    /// Shown beside When when the Food Log day could not be used (owner decision D).
    public let whenNotice: String?
    public var quantitySuggestion: ParsedFoodQuery.Quantity? { searchInterpretation?.quantitySuggestion }
    public var displayedName: LedgerText { state.correction?.name ?? state.reopened?.productVersion.name ?? state.selectedCandidate.name }
    public var displayedBrand: LedgerText? { state.correction?.brand ?? state.reopened?.productVersion.brand ?? state.selectedCandidate.brand }
    public var displayedVariant: LedgerText? { state.correction?.variant ?? state.reopened?.productVersion.variant ?? state.selectedCandidate.variant }
    public var displayedIdentity: DecisiveIdentity { state.correction?.identity ?? state.reopened?.productVersion.identity ?? state.selectedCandidate.candidate.identity }
    public var selectionCaution: String? {
        FoodSearchResultText.caution(query: searchInterpretation?.parsedQuery, candidate: state.selectedCandidate,
            requestedPreparation: searchInterpretation?.preparation, isRecipe: state.isSourceRecipe)
    }

    public init(
        state: FoodConfirmationState,
        volumeConversionOffering: (any FoodVolumeConversionOffering)? = nil,
        searchInterpretation: FoodQueryInterpretation? = nil,
        now: @escaping @Sendable () -> Date = { Date() },
        calendar: Calendar = .autoupdatingCurrent,
        savesFavourite: Bool = false,
        favouriteAction: (@MainActor (LogItemVersionID) throws -> Void)? = nil,
        whenNotice: String? = nil,
        saveAction: @escaping @MainActor (FoodConfirmationState) throws -> StoredFoodConfirmation
    ) {
        self.state = state
        self.whenNotice = whenNotice
        self.savesFavourite = savesFavourite && favouriteAction != nil && !Self.isPlainWaterSource(state)
        self.favouriteAction = favouriteAction
        self.now = now
        self.calendar = calendar
        self.volumeConversionOffering = volumeConversionOffering
        self.searchInterpretation = searchInterpretation
        self.saveAction = saveAction
    }

    /// A pasted label's corrected input (#93): a value the user corrected or entered on Confirm
    /// rebuilds the source from a new manifest. The amount and time are kept; a "Add food details"
    /// correction is carried over with the new nutrients and basis, since it may only answer
    /// identity details. Nothing is saved: Log is still the only save. A new entry only.
    public func replaceSourceInput(_ input: PopulatedFoodConfirmation) {
        guard state.reopened == nil, savedResult == nil, state.phase != .saving, let candidate = input.candidates.first else { return }
        var next = FoodConfirmationState(input: input, prefillSourceQuantity: false)
        next.quantity = state.quantity
        next.occurredAt = state.occurredAt
        if let correction = state.correction {
            let source = candidate.candidate.identity
            let previous = correction.identity
            if let identity = try? DecisiveIdentity(preparation: previous.preparation, bone: previous.bone, skin: previous.skin,
                    drained: previous.drained, packingMedium: previous.packingMedium, fortification: previous.fortification,
                    declaredFortificants: previous.declaredFortificants, servingBasis: source.servingBasis) {
                FoodConfirmationReducer.reduce(state: &next, action: .applyCorrection(FoodCorrection(name: correction.name,
                    brand: correction.brand, variant: correction.variant, identity: identity, itemClass: correction.itemClass,
                    nutrients: candidate.candidate.nutrients, reason: correction.reason)))
            }
        }
        state = next
    }

    /// The whole-pack amount option for a pasted label (contract section 2.3), or nil.
    public var pastedLabelWholePack: PastedLabelWholePack? {
        guard state.reopened == nil else { return nil }
        return PastedLabelServingPolicy.wholePack(state.input, candidate: state.selectedCandidate)
    }

    /// Whole pack: that many servings, through the same servings conversion as any servings amount.
    public func chooseWholePack() {
        guard let pack = pastedLabelWholePack else { return }
        send(.setQuantity(pack.servings, .count))
    }

    /// Servings of a pasted label are the count unit's meaning on this Confirm.
    public var countsPastedLabelServings: Bool { state.pastedLabelServing != nil }

    /// A pasted label without a readable serving size can be logged in servings only.
    public var pastedLabelServingsOnly: Bool { state.pastedLabelServing?.unit == .count }

    public var availableVolumeConversion: QuantityConversionDraft? {
        guard state.correction == nil, state.quantity.directWeight == nil,
              state.quantity.conversion == nil,
              let value = state.quantity.value,
              let original = try? PositiveQuantity(value: value, unit: state.quantity.unit),
              let offering = volumeConversionOffering else { return nil }
        return try? offering.offer(for: state.selectedCandidate, original: original)
    }

    public func applyAvailableVolumeConversion() {
        guard let conversion = applicableVolumeConversion else { return }
        send(.setConversion(conversion))
    }

    /// The offered estimate when tapping it would apply it (its source release is on Confirm).
    /// Both estimate actions are gated on this, so neither shows when a tap would do nothing.
    public var applicableVolumeConversion: QuantityConversionDraft? {
        guard let conversion = availableVolumeConversion,
              state.input.sourceReleases.contains(where: { $0.sourceReleaseID == conversion.sourceReleaseID }) else { return nil }
        return conversion
    }

    /// The estimate action shown directly above Log while the estimate is available and not
    /// applied. Its energy is the Log total that tapping it would produce, computed from the same
    /// reducer and totals; nil energy (unknown or incomplete) leaves the kcal out. Never applies
    /// anything by itself.
    public struct VolumeEstimateLogBarAction: Equatable, Sendable {
        public let title: String
        public let accessibilityLabel: String
        /// False while saving: the amount must not change under a save in progress.
        public let isEnabled: Bool
        public static let accessibilityHint = "Estimates grams from the millilitres entered using a sourced whole-milk factor. Nothing is logged until you press Log."
    }

    /// The admission rule's wording (cofid-whole-milk-volume-admission-v1).
    public static let volumeEstimateActionTitle = "Use sourced whole-milk volume estimate"

    public var volumeEstimateLogBarAction: VolumeEstimateLogBarAction? {
        guard savedResult == nil, let conversion = applicableVolumeConversion else { return nil }
        let isEnabled = state.phase != .saving
        var applied = state
        FoodConfirmationReducer.reduce(state: &applied, action: .setConversion(conversion))
        guard applied.quantity.conversion == conversion,
              let kcal = Self.knownConsumedEnergy(applied, quantityIsEstimate: true) else {
            return VolumeEstimateLogBarAction(title: Self.volumeEstimateActionTitle,
                                              accessibilityLabel: Self.volumeEstimateActionTitle, isEnabled: isEnabled)
        }
        let energy = kcal > 0 && kcal < 0.5 ? FoodDisplayNumber.energy(kcal) : "about \(FoodDisplayNumber.energy(kcal))"
        return VolumeEstimateLogBarAction(title: "\(Self.volumeEstimateActionTitle) (\(energy))",
                                          accessibilityLabel: "\(Self.volumeEstimateActionTitle), \(energy)", isEnabled: isEnabled)
    }

    public func removeOfferedVolumeConversion() {
        guard usesOfferedVolumeEstimate else { return }
        send(.setConversion(nil))
    }

    public var volumeConversionSourceURL: URL? {
        guard let sourceID = state.quantity.conversion?.sourceReleaseID,
              sourceID == volumeConversionOffering?.sourceRelease.sourceReleaseID else { return nil }
        return volumeConversionOffering?.sourceURL
    }

    /// The conversion's method as shown on the main screen. The offered estimate's method
    /// identifier stays behind "Volume estimate source"; a typed method is the user's own words.
    public var conversionMethodLabel: String? {
        guard let conversion = state.quantity.conversion else { return nil }
        return usesOfferedVolumeEstimate ? Self.offeredVolumeEstimateLabel : conversion.methodVersion.value
    }

    /// The factor is PHE 2018 Annex A Table 4 (citing McCance and Widdowson), checked as 1.03 by the
    /// adapter; it is not a CoFID field, so the label never names CoFID (admission v1).
    public static let offeredVolumeEstimateLabel = "Whole milk volume estimate (1.03 g per mL, PHE)"

    private var usesOfferedVolumeEstimate: Bool {
        guard let sourceID = state.quantity.conversion?.sourceReleaseID,
              let offering = volumeConversionOffering else { return false }
        return sourceID == offering.sourceRelease.sourceReleaseID
    }

    public var quantityBasisWarning: String? {
        let basis = (state.correction?.identity ?? state.selectedCandidate.candidate.identity).servingBasis
        // A measured weight is always grams and drives nutrition, whatever the unit picker says.
        let unit = state.quantity.directWeight != nil
            ? .grams : (try? state.quantity.calculationInput().unit) ?? state.quantity.unit
        if state.isSourceRecipe && unit != .count {
            return "This recipe declares nutrition per source serving. Its cooked gram weight is unknown, so grams or mL cannot be converted to servings. Choose recipe servings or a source with a measured weight basis."
        }
        if state.usesSourceDeclaredServing && unit != .count {
            return "This source declares nutrition per serving. Its gram weight is unknown. Enter source servings or choose a source with a weight or volume basis."
        }
        if basis == .per100Grams && unit == .millilitres {
            if let conversion = state.quantity.conversion, usesOfferedVolumeEstimate {
                return "Estimated edible mass: \(conversion.convertedQuantity.value.formatted()) g from the entered volume. This uses a separately sourced volume factor, not a measured weight or CoFID density field."
            }
            if let conversion = state.quantity.conversion {
                return "Converted edible amount: \(conversion.convertedQuantity.value.formatted()) \(conversion.convertedQuantity.unit.rawValue) using the recorded method. Check that the conversion describes the food as eaten."
            }
            return "This food’s nutrition is per 100 g, and millilitres cannot be converted to grams for it. Logged in mL, this entry has no nutrition."
        }
        if basis == .per100Millilitres && unit == .grams {
            return "This food’s nutrition is per 100 mL, and grams cannot be converted to millilitres for it. Logged in grams, this entry has no nutrition."
        }
        return nil
    }

    /// The amount's unit cannot be scaled to the source basis (owner decision B1): mL on a
    /// per 100 g source, or g on a per 100 mL source, with no conversion that reaches the basis.
    /// Presentation only: confirmation v5 still allows the save, with nutrition unknown.
    public enum UnitBasisMismatch: Equatable, Sendable {
        case millilitresOnGramBasis
        case gramsOnMillilitreBasis

        /// The unit the inline action switches to.
        public var sourceUnit: QuantityUnit {
            switch self {
            case .millilitresOnGramBasis: .grams
            case .gramsOnMillilitreBasis: .millilitres
            }
        }

        public var actionTitle: String {
            switch self {
            case .millilitresOnGramBasis: "Enter grams instead"
            case .gramsOnMillilitreBasis: "Enter mL instead"
            }
        }
    }

    public static let logWithoutNutritionTitle = "Log without nutrition"

    public var unitBasisMismatch: UnitBasisMismatch? {
        guard !state.isSourceRecipe, !state.usesSourceDeclaredServing else { return nil }
        let basis = (state.correction?.identity ?? state.selectedCandidate.candidate.identity).servingBasis
        // The unit nutrition is scaled from: a measured weight is grams; a conversion supplies its own unit.
        let unit = state.quantity.directWeight != nil
            ? .grams : state.quantity.conversion?.convertedQuantity.unit ?? state.quantity.unit
        switch (basis, unit) {
        case (.per100Grams, .millilitres): return .millilitresOnGramBasis
        case (.per100Millilitres, .grams): return .gramsOnMillilitreBasis
        default: return nil
        }
    }

    /// "Enter grams instead" / "Enter mL instead": switches to the source's unit and clears the
    /// amount (B2), so nothing is reread in the new unit.
    public func useSourceBasisUnit() {
        guard let unit = sourceUnitAction?.sourceUnit else { return }
        chooseQuantityUnit(unit)
    }

    /// The mismatch when the inline unit action can resolve it: not under a measured weight,
    /// which is always grams whatever the unit picker says.
    public var sourceUnitAction: UnitBasisMismatch? {
        state.quantity.directWeight == nil ? unitBasisMismatch : nil
    }

    public static func nutrientLabel(_ value: NutrientKey) -> String {
        FoodNutritionReviewPresentation.label(value)
    }

    public var nutritionReferenceTitle: String {
        "Reference nutrition: \(FoodConfirmationView.basisLabel(state.selectedCandidate.candidate.identity.servingBasis))"
    }

    public var consumedNutritionBasisLabel: String {
        let basis = (state.correction?.identity ?? state.selectedCandidate.candidate.identity).servingBasis
        let prefix = state.correction == nil ? "Calculation basis" : "User-corrected calculation basis"
        return "\(prefix): \(FoodConfirmationView.basisLabel(basis))"
    }

    public var consumedNutrition: [FoodIntakeTotal] {
        Self.consumedNutrition(state, quantityIsEstimate: state.quantity.directWeight?.basis == .estimated || usesOfferedVolumeEstimate)
    }

    private static func consumedNutrition(_ state: FoodConfirmationState, quantityIsEstimate: Bool) -> [FoodIntakeTotal] {
        guard let quantity = try? state.calculatedEdibleQuantity() else { return [] }
        return FoodIntakeSummary(contributions: [FoodIntakeContribution(
            quantity: quantity,
            basis: (state.correction?.identity ?? state.selectedCandidate.candidate.identity).servingBasis,
            nutrients: state.correction?.nutrients ?? state.selectedCandidate.candidate.nutrients,
            quantityIsEstimate: quantityIsEstimate
        )]).totals
    }

    public var nutritionReview: FoodNutritionReviewPresentation {
        Self.nutritionReview(state, totals: consumedNutrition)
    }

    private static func nutritionReview(_ state: FoodConfirmationState, totals: [FoodIntakeTotal]) -> FoodNutritionReviewPresentation {
        FoodNutritionReviewPresentation(nutrients: state.correction?.nutrients ?? state.selectedCandidate.candidate.nutrients,
            sourceBasis: (state.correction?.identity ?? state.selectedCandidate.candidate.identity).servingBasis,
            edibleQuantity: try? state.calculatedEdibleQuantity(), totals: totals)
    }

    /// The complete consumed energy the Log button states ("Log 130 kcal"), or nil when it is
    /// unknown, partial or not scalable.
    private static func knownConsumedEnergy(_ state: FoodConfirmationState, quantityIsEstimate: Bool) -> Double? {
        let totals = consumedNutrition(state, quantityIsEstimate: quantityIsEstimate)
        guard nutritionReview(state, totals: totals).isConsumed,
              let energy = totals.first(where: { $0.key == .energyConsumed }),
              energy.incompleteContributions == 0 else { return nil }
        return energy.knownAmount
    }

    public var originalAmountRequirement: String? {
        if state.quantity.directWeight != nil, state.quantity.value == nil, state.quantity.invalidOriginalAmountText != true { return nil }
        guard let value = state.quantity.value, value.isFinite, value > 0 else {
            return state.quantity.directWeight == nil
                ? "Enter an amount greater than zero, or use ‘Enter measured weight’ to give the weight you ate in grams."
                : "Enter an original amount greater than zero, or clear this optional field. Your weight in grams is kept."
        }
        return nil
    }

    /// Typed requirements from the same pure policy the save service enforces.
    public var requirements: [FoodLogRequirement] {
        FoodLogPolicy.requirements(state, now: now(), calendar: calendar)
    }

    public var canLog: Bool {
        guard requirements.isEmpty, hasChangesToSave else { return false }
        switch state.phase {
        case .editing, .saveFailed: return true
        case .saving, .saved: return false
        }
    }

    /// The first blocking requirement, stated beside the disabled Log button.
    public var blockedReason: String? {
        requirements.first.map(FoodLogRequirementText.text) ?? (hasChangesToSave ? nil : Self.noChangesReason)
    }

    public static let noChangesReason = "No changes to save"

    /// Edit mode only: Save changes waits for a difference from the stored version. Presentation
    /// gating; the service still accepts an unchanged save (#197, F2).
    public var hasChangesToSave: Bool { state.reopened == nil || FoodLogPolicy.editChanges(state) }

    public var directWeightRequirements: [String] {
        requirements.filter { [.measuredWeightMissing, .weightBasisMissing, .retainedWeightNeedsConfirmation].contains($0) }
            .map(FoodLogRequirementText.text)
    }

    public var plateRequirements: [String] {
        requirements.filter { [.emptyPlateWeightMissing, .plateNeedsGramTotal, .plateNotLighterThanTotal].contains($0) }
            .map(FoodLogRequirementText.text)
    }

    public var pendingDifferences: [IdentityContradiction] { FoodLogPolicy.pendingDifferences(state) }

    public func offeredChoices(_ facet: IdentityContradiction) -> [FoodLogDecisionChoice] {
        FoodLogPolicy.offeredChoices(state, facet: facet)
    }

    public func sourceState(_ facet: IdentityContradiction) -> FoodLogSourceState {
        FoodLogPolicy.sourceState(state, facet: facet)
    }

    public var missingSourceDetails: [IdentityContradiction] { state.unresolvedIdentity }

    /// Whether Log would write a labelled estimate. Shown on the primary screen, never only in details.
    public var savesEstimate: Bool { FoodLogPolicy.savesEstimate(state) }

    public static let estimateNotice = "Logged as an estimate. Unknown details stay unknown."

    /// Whether the "Save as favourite" toggle is offered: a new entry with a favourite writer, and
    /// not plain water (already the built-in quick add, with its amount editable in Favourites).
    public var offersFavourite: Bool {
        favouriteAction != nil && state.reopened == nil && !Self.isPlainWaterSource(state)
    }

    public static func isPlainWaterSource(_ state: FoodConfirmationState) -> Bool {
        state.selectedCandidate.candidate.sourceReleaseID.value == PlainWaterReference.sourceReleaseID
    }

    public var logButtonTitle: String {
        if state.reopened != nil { return "Save changes" }
        let savesAsFavourite = savesFavourite && offersFavourite
        if unitBasisMismatch != nil {
            return savesAsFavourite ? "\(Self.logWithoutNutritionTitle) and save favourite" : Self.logWithoutNutritionTitle
        }
        if savesAsFavourite { return "Log and save favourite" }
        guard let amount = logEnergy else { return "Log" }
        return "Log \(FoodDisplayNumber.energy(amount))"
    }

    /// The energy the Log button states for a new entry, or nil when it is not complete.
    private var logEnergy: Double? {
        Self.knownConsumedEnergy(state, quantityIsEstimate: state.quantity.directWeight?.basis == .estimated
                                    || usesOfferedVolumeEstimate)
    }

    /// The figures captured at the Log press for the banner (owner decision, 15 October 2026).
    private var logPress: (energy: Double?, withoutNutrition: Bool)?

    /// The banner for the entry just logged, once Log may close Confirm: a new entry saved, and
    /// any favourite requested with it saved too. Nil for Save changes, before a save, and when
    /// the favourite failed, so Confirm stays with Try again and Done.
    public var loggedNotice: FoodLoggedNotice? {
        guard let saved = savedResult, let logPress, state.reopened == nil else { return nil }
        let savedFavourite = favouriteOutcome == .saved
        if savesFavourite && offersFavourite && !savedFavourite { return nil }
        return FoodLoggedNotice(saved: saved,
            message: FoodLoggedText.message(figure: logPress.energy.map { FoodDisplayNumber.energy($0) },
                                             withoutNutrition: logPress.withoutNutrition, savedFavourite: savedFavourite),
            detail: FoodLoggedText.detail(savedFavourite: savedFavourite))
    }

    public var occurredAtRange: ClosedRange<Date> {
        let current = now()
        return FoodLogPolicy.windowStart(now: current, calendar: calendar)...current
    }

    /// The displayed time: the chosen instant, or now when "Now" is still selected.
    public var displayedOccurredAt: Date { state.occurredAt ?? now() }

    public var occursNow: Bool { state.occurredAt == nil }

    /// A time requirement shown inline under When, for example after midnight moves the window
    /// past a prefilled day (owner decision D); the Log bar states it as well.
    public var whenRequirementText: String? {
        requirements.first { $0 == .occurredAtTooEarly || $0 == .occurredAtInFuture }.map(FoodLogRequirementText.text)
    }

    /// A reopened entry older than the backdating window keeps its stored time: the picker is
    /// replaced by a read-only value, so no clamped or refused time can be written back.
    public var canChangeOccurredAt: Bool {
        guard let stored = state.reopened?.logItemVersion.occurredAt else { return true }
        return stored >= FoodLogPolicy.windowStart(now: now(), calendar: calendar)
    }

    /// One Log press: the explicit acceptance of the displayed food, amount, time and source.
    public func log() {
        guard canLog else { return }
        logPress = (unitBasisMismatch == nil ? logEnergy : nil, unitBasisMismatch != nil)
        send(.accept)
        save()
    }

    /// The unit picker: a different unit clears the amount (B2), so Log waits for a new amount.
    public func chooseQuantityUnit(_ unit: QuantityUnit) {
        send(.setQuantityUnit(unit))
    }

    public func send(_ action: FoodConfirmationAction) {
        FoodConfirmationReducer.reduce(state: &state, action: action)
    }

    public func save() {
        guard state.phase != .saving else { return }
        if case .saved = state.phase { return }
        send(.beginSaving)
        do {
            let saved = try saveAction(state)
            savedResult = saved
            send(.saved(saved.logItem.logItemID))
        } catch {
            send(.saveFailed(Self.message(for: error)))
            return
        }
        if savesFavourite && offersFavourite { saveFavourite() }
    }

    /// The favourite operation after Log. A failure leaves the entry logged and offers Try again.
    public func saveFavourite() {
        guard let favouriteAction, let saved = savedResult, favouriteOutcome != .saved else { return }
        do {
            try favouriteAction(saved.logItemVersion.logItemVersionID)
            favouriteOutcome = .saved
        } catch {
            favouriteOutcome = .failed
        }
    }

    public static func message(for error: Error) -> String {
        if let error = error as? DirectWeightError {
            switch error {
            case .missingBasis: return "Choose measured weight or user-entered estimate beside the gram total."
            case .invalidTotal: return "Enter the weight you ate in grams, greater than zero."
            case .needsReconfirmation: return "Check that the weight still describes this food, then choose ‘Keep this weight’."
            }
        }
        return switch error {
        case FoodConfirmationSaveError.noAcceptedCandidate:
            "Choose a populated match before logging."
        case let FoodConfirmationSaveError.unmetRequirements(requirements):
            requirements.first.map(FoodLogRequirementText.text) ?? "Check the food and amount, then log again."
        case FoodConfirmationSaveError.staleDecisions:
            "The food changed after you answered. Answer the questions again, then log."
        case FoodConfirmationSaveError.invalidQuantity:
            "Enter an amount greater than zero."
        case FoodConfirmationSaveError.invalidReviewedSource:
            "The reviewed source values or their serving basis changed. Return to the source review; identity corrections cannot change its nutrition."
        case FoodQuantityValidationError.missingConversion:
            "This unit needs the displayed conversion before it can be saved."
        case FoodQuantityValidationError.missingPlateWeight:
            "Enter or choose an empty plate weight."
        case FoodQuantityValidationError.invalidPlateUnit:
            "Plate subtraction is available for gram weights only."
        case FoodQuantityValidationError.nonPositiveEdibleQuantity:
            "The total must be greater than the empty plate weight."
        default:
            "The food was not logged. Your choices are still here; review them and try again."
        }
    }
}

public struct FoodConfirmationView: View {
    @ObservedObject private var model: FoodConfirmationViewModel
    private let leave: () -> Void
    /// Set by hosts of a new single food: Log then leaves through `leave` (the exit Done uses)
    /// and hands over the banner. Nil keeps the saved state with Done (list import, edit).
    private let logged: ((FoodLoggedNotice) -> Void)?
    private let context: String?
    private let completionTitle: String
    private let showsCancelButton: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.locale) private var locale
    /// The focused amount field, if any; "Done" above the decimal pad clears it (#212).
    @FocusState private var editingAmount: AmountFieldFocus?
    @State private var showsCorrection = false
    @State private var showsMatches = false
    @State private var correctionName = ""
    @State private var correctionBrand = ""
    @State private var correctionVariant = ""
    @State private var correctionReason = ""
    @State private var correctionPreparation = PreparationKind.unknown.rawValue
    @State private var correctionPreparationMethod = ""
    @State private var correctionBone = BoneState.unknown.rawValue
    @State private var correctionSkin = SkinState.unknown.rawValue
    @State private var correctionDrained = DrainedState.unknown.rawValue
    @State private var correctionPackingMedium = ""
    @State private var correctionFortification = FortificationState.unknown.rawValue
    @State private var correctionItemClass = ItemClass.food.rawValue
    @State private var correctionBasis = CorrectionBasis.keepPopulated
    @State private var totalText = ""
    @State private var directWeightText = ""
    @State private var emptyPlateText = ""
    @State private var conversionText = ""
    @State private var conversionUnit = QuantityUnit.grams
    @State private var conversionMethod = ""
    /// A pasted nutrition label's source section (#93): the live, editable model from the paste
    /// route, or the read-only model of a stored label (Edit, Recent foods, a favourite).
    @State private var pastedLabel: PastedLabelSourceModel?
    private let editLabelText: (() -> Void)?

    public init(
        model: FoodConfirmationViewModel, context: String? = nil,
        completionTitle: String = "Done", showsCancelButton: Bool = true,
        pastedLabel: PastedLabelSourceModel? = nil, editLabelText: (() -> Void)? = nil,
        logged: ((FoodLoggedNotice) -> Void)? = nil, leave: @escaping () -> Void
    ) {
        self.model = model
        _pastedLabel = State(initialValue: pastedLabel ?? PastedLabelSourceModel.stored(model.state))
        self.editLabelText = pastedLabel == nil ? nil : editLabelText
        self.logged = logged
        self.showsCancelButton = showsCancelButton
        self.context = context
        self.completionTitle = completionTitle
        self.leave = leave
    }

    /// The weighing method's title, shared by the picker and the saved, read-only plate row (#212).
    public static func weighingMethodTitle(usesPlate: Bool) -> String {
        usesPlate ? "Total minus empty plate" : "Food only / tared"
    }

    /// The saved, read-only plate row: the method and, when known, the empty plate weight, for
    /// example "Total minus empty plate · plate 330 g".
    public static func savedPlateRowValue(usesPlate: Bool, emptyPlateGrams: Double?, locale: Locale) -> String {
        let method = weighingMethodTitle(usesPlate: usesPlate)
        guard usesPlate, let emptyPlateGrams else { return method }
        return "\(method) · plate \(FoodAmountFieldText.text(emptyPlateGrams, locale: locale)) g"
    }

    /// One Log press. With a `logged` handler, a successful new entry leaves at once through the
    /// host's exit and then shows the banner; returns true when it closed. A failed save, Save
    /// changes or a failed favourite stay on Confirm as before.
    @discardableResult
    public static func logTapped(_ model: FoodConfirmationViewModel, leave: () -> Void,
                                 logged: ((FoodLoggedNotice) -> Void)?) -> Bool {
        model.log()
        guard let logged, let notice = model.loggedNotice else { return false }
        leave()
        logged(notice)
        return true
    }

    /// The exits Confirm offers (#197): before a save, Cancel when the host shows one; after a
    /// save, exactly one, the host's completion action. The view renders from this list.
    public static func exitTitles(isSaved: Bool, showsCancelButton: Bool, completionTitle: String) -> [String] {
        isSaved ? [completionTitle] : (showsCancelButton ? ["Cancel"] : [])
    }

    public var body: some View {
        Form {
            if let context { Section("From your list") { Text(context) } }
            Group {
                foodSection
                if let pastedLabel {
                    PastedLabelSourceSections(model: pastedLabel, editLabelText: model.savedResult == nil ? editLabelText : nil)
                }
                decisionsSection
                quantitySection
                compactNutritionSection
            }
            .disabled(model.savedResult != nil)
            if model.offersFavourite {
                Section {
                    Toggle("Save as favourite", isOn: $model.savesFavourite).frame(minHeight: 44)
                        .disabled(model.savedResult != nil)
                } footer: {
                    Text("A favourite keeps this source and amount, so logging it again takes one step.")
                }
            }
            Section {
                DisclosureGroup("Source details") {
                    sourceDetails
                    nutritionSection
                }
            } header: { Text("Source") } footer: {
                Text("Need to correct the food itself? Choose a different match, or edit the details from the entry after logging.")
            }
            recoverySection
        }
        .amountKeyboardDismissal($editingAmount)
        .navigationTitle(model.state.reopened == nil ? "Confirm food" : "Edit food")
        // After a save there is exactly one way out: the host's completion action in the Log
        // bar's place. No back button and no toolbar action (#197).
        .navigationBarBackButtonHidden(showsCancelButton || model.savedResult != nil)
        .toolbar {
            if Self.exitTitles(isSaved: model.savedResult != nil, showsCancelButton: showsCancelButton,
                               completionTitle: completionTitle) == ["Cancel"] {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        model.send(.decline)
                        leave()
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) { logBar }
        .sheet(isPresented: $showsCorrection) {
            NavigationStack {
                Form { correctionSection }
                    .navigationTitle("Food details")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("Close") { showsCorrection = false } }
                    }
            }
        }
        .sheet(isPresented: $showsMatches) {
            NavigationStack {
                List(model.state.input.candidates.indices, id: \.self) { index in
                    Button {
                        candidateBinding.wrappedValue = index
                        showsMatches = false
                    } label: {
                        HStack {
                            Text(model.state.input.candidates[index].name.value)
                            Spacer()
                            if index == model.state.selectedCandidateIndex {
                                Image(systemName: "checkmark").accessibilityLabel("Selected")
                            }
                        }
                        .frame(minHeight: 44)
                    }
                }
                .navigationTitle("Choose a match")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Close") { showsMatches = false } }
                }
            }
        }
        .animation(reduceMotion ? nil : .default, value: model.state.selectedCandidateIndex)
        .onAppear {
            correctionName = model.displayedName.value
            correctionBrand = model.displayedBrand?.value ?? ""
            correctionVariant = model.displayedVariant?.value ?? ""
            loadIdentityCorrection(model.state.selectedCandidate)
            if let value = model.state.quantity.value { totalText = editableNumber(value) }
            directWeightText = model.state.quantity.directWeight?.totalGrams.map(editableNumber) ?? ""
            if let conversion = model.state.quantity.conversion {
                conversionText = editableNumber(conversion.convertedQuantity.value)
                conversionUnit = conversion.convertedQuantity.unit
                conversionMethod = conversion.methodVersion.value
            }
        }
    }

    private var foodSection: some View {
        Section("Food") {
            Text(model.displayedName.value).font(.headline)
            if let line = sourceLine { Text(line).font(.subheadline).foregroundStyle(.secondary) }
            if model.displayedName != model.state.selectedCandidate.name {
                LabeledContent("Source food", value: model.state.selectedCandidate.name.value).font(.caption)
            }
            if let brand = model.displayedBrand {
                LabeledContent("Brand", value: brand.value)
            }
            if model.savesEstimate {
                Label(FoodConfirmationViewModel.estimateNotice, systemImage: "info.circle")
                    .font(.subheadline)
                    .accessibilityLabel(FoodConfirmationViewModel.estimateNotice)
            }
            if let caution = model.selectionCaution {
                Label(caution, systemImage: "exclamationmark.triangle").font(.caption)
            }
            if model.state.isSourceRecipe {
                Text("Representative recipe. A recipe serving is not a measured gram amount.").font(.caption)
            }
            if let metadata = model.state.selectedCandidate.candidate.matchMetadata,
               model.state.isSourceRecipe || model.state.reviewedWebProposalScope != nil {
                ForEach(metadata.materialDifferences, id: \.value) { Text($0.value).font(.caption) }
            }
            if model.state.correction != nil { Text("Uses your food correction").font(.caption) }
            if !model.missingSourceDetails.isEmpty {
                Label(FoodLogRequirementText.text(.sourceIdentityMissing(model.missingSourceDetails)),
                      systemImage: "exclamationmark.triangle")
                    .font(.subheadline)
                Button("Add food details") { showsCorrection = true }
                    .frame(minHeight: 44)
            }
            if model.state.input.candidates.count > 1 && model.state.reopened == nil {
                Button("Choose a different match") { showsMatches = true }
                    .frame(minHeight: 44)
            }
            if model.state.reopened != nil {
                Button("Correct food details") { showsCorrection = true }
                    .frame(minHeight: 44)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var sourceLine: String? {
        var parts: [String] = []
        if let scope = model.state.reviewedWebProposalScope {
            parts.append(scope == .representativeEstimate ? "Reviewed web estimate" : "Reviewed web product")
        } else if model.state.isGenericEstimate {
            parts.append("Generic food estimate")
        }
        let preparation = model.displayedIdentity.preparation
        if preparation.kind != .unknown { parts.append(Self.preparationLabel(preparation).lowercased()) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    @ViewBuilder
    private var decisionsSection: some View {
        ForEach(model.pendingDifferences, id: \.rawValue) { facet in
            let source = model.sourceState(facet)
            Section {
                Picker(FoodLogRequirementText.question(facet), selection: Binding<FoodLogDecisionChoice?>(
                    get: { model.state.decisions[facet] },
                    set: { model.send(.decideDifference(facet, $0)) })) {
                    ForEach(model.offeredChoices(facet), id: \.token) { choice in
                        Text(FoodLogRequirementText.choice(choice, facet: facet, source: source))
                            .tag(FoodLogDecisionChoice?.some(choice))
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
                if let choice = model.state.decisions[facet] {
                    Text(FoodLogRequirementText.result(choice)).font(.caption)
                }
            } header: {
                Text(FoodLogRequirementText.question(facet))
            } footer: {
                Text("This source is \(FoodLogRequirementText.state(source.token).lowercased()). Choose what you ate before logging.")
            }
        }
    }

    @ViewBuilder
    private var whenRow: some View {
        if !model.canChangeOccurredAt {
            LabeledContent("When", value: model.displayedOccurredAt.formatted(date: .abbreviated, time: .shortened))
            Text("Entries older than \(FoodLogPolicy.backdatingDays) days keep their logged time.").font(.caption)
        } else {
            DatePicker("When", selection: Binding(
                get: { model.displayedOccurredAt },
                set: { model.send(.setOccurredAt($0)) }),
                in: model.occurredAtRange)
            if let requirement = model.whenRequirementText {
                Label(requirement, systemImage: "exclamationmark.triangle").font(.caption)
            }
            if !model.occursNow && model.state.reopened == nil {
                Button("Use now") { model.send(.setOccurredAt(nil)) }
                    .frame(minHeight: 44)
            }
            if let notice = model.whenNotice, model.occursNow {
                Text(notice).font(.caption)
            }
        }
    }

    @ViewBuilder
    private var logBar: some View {
        if Self.exitTitles(isSaved: model.savedResult != nil, showsCancelButton: showsCancelButton,
                           completionTitle: completionTitle) == [completionTitle], model.savedResult != nil {
            Button(action: leave) {
                Text(completionTitle).frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(.bar)
        } else {
            VStack(spacing: 6) {
                // Pasted label warnings (section 4): above Log, never blocking, never a pass badge.
                if let warnings = pastedLabel?.warnings, !warnings.isEmpty {
                    ForEach(warnings, id: \.self) { warning in
                        Label(warning, systemImage: "exclamationmark.triangle")
                            .font(.footnote)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityLabel("Warning. \(warning)")
                    }
                }
                // Secondary and next to Log, so the sourced estimate is not missed when Log
                // would save without nutrition. It only applies the estimate; Log still saves.
                if let estimate = model.volumeEstimateLogBarAction {
                    Button {
                        model.applyAvailableVolumeConversion()
                    } label: {
                        Text(estimate.title)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                    .disabled(!estimate.isEnabled)
                    .accessibilityLabel(estimate.accessibilityLabel)
                    .accessibilityHint(FoodConfirmationViewModel.VolumeEstimateLogBarAction.accessibilityHint)
                }
                Button {
                    Self.logTapped(model, leave: leave, logged: logged)
                } label: {
                    Group {
                        if model.state.phase == .saving { ProgressView() } else { Text(model.logButtonTitle) }
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!model.canLog)
                .accessibilityHint(model.blockedReason ?? (model.state.reopened == nil ? "Logs this food with the amount and time shown" : "Saves your changes and keeps the original as history"))
                if let reason = model.blockedReason {
                    Text(reason).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(.bar)
        }
    }

    private var sourceDetails: some View {
        Group {
            let identity = model.state.selectedCandidate.candidate.identity
            if model.state.isGenericEstimate, let variant = model.state.selectedCandidate.variant {
                LabeledContent("Source description", value: variant.value)
            }
            LabeledContent("Preparation", value: Self.preparationLabel(identity.preparation))
            LabeledContent("Bone", value: Self.label(identity.bone.rawValue))
            LabeledContent("Skin", value: Self.label(identity.skin.rawValue))
            LabeledContent("Drained", value: Self.label(identity.drained.rawValue))
            LabeledContent("Packing medium", value: Self.packingLabel(identity.packingMedium))
            LabeledContent("Fortification", value: Self.label(identity.fortification.rawValue))
            ForEach(model.state.input.sourceReleases.filter { $0.sourceReleaseID == model.state.selectedCandidate.candidate.sourceReleaseID }, id: \.sourceReleaseID) { source in
                Text(source.attribution.value).font(.caption).textSelection(.enabled)
                Text(source.licence.value).font(.caption2).textSelection(.enabled)
            }
            LabeledContent("Source release", value: model.state.selectedCandidate.candidate.sourceReleaseID.value)
            LabeledContent("Source record", value: model.state.selectedCandidate.candidate.recordID.value)
            LabeledContent("Evidence", value: Self.evidenceCount(model.state.selectedCandidate.candidate.evidenceIDs.count))
        }
    }

    private var quantitySection: some View {
        Section("Amount eaten") {
            if model.state.isSourceRecipe {
                Text("Representative recipe: enter how many servings of this source recipe you ate, for example 0.5. Check the source recipe yield in the reference details; a vendor’s plate may differ. Cooked serving weight is unknown.").font(.caption)
            }
            if model.state.usesSourceDeclaredServing && !model.state.isSourceRecipe {
                Text("Enter source servings eaten, for example 0.5. Review the source's portion description; its gram weight remains unknown.").font(.caption)
            }
            if let suggestion = model.quantitySuggestion, model.state.quantity.value == nil,
               model.state.quantity.directWeight == nil, !model.state.usesSourceDeclaredServing {
                Button("Use \(FoodNutritionReviewPresentation.number(suggestion.value)) from your description") {
                    model.send(.setQuantity(suggestion.value, .count))
                    totalText = editableNumber(suggestion.value)
                }
                Text("Count only. Edible weight still needs confirmation.").font(.caption)
            }
            if model.countsPastedLabelServings {
                Text(model.pastedLabelServingsOnly
                     ? "Values are per serving and the serving size was not read, so enter servings eaten, for example 1 or 0.5."
                     : "Enter servings eaten, or grams or millilitres matching the label.").font(.caption)
            }
            if let pack = model.pastedLabelWholePack {
                Button("Whole pack (\(FoodDisplayNumber.amount(pack.servings, fraction: 0...2)) servings)") {
                    model.chooseWholePack()
                    totalText = editableNumber(pack.servings)
                }
                .frame(minHeight: 44)
                .accessibilityHint("Sets the amount to the servings in one pack")
                Text((pack.origin == .printed ? "Servings per pack printed on the label. " : "Servings per pack entered by you. ")
                     + PastedLabelText.wholePackNote).font(.caption)
            }
            Button("Enter measured weight") { model.send(.beginDirectWeight); directWeightText = "" }
                .disabled(model.state.quantity.directWeight != nil || model.state.usesSourceDeclaredServing || model.pastedLabelServingsOnly)
            if model.state.quantity.directWeight != nil {
                Text("Weigh the food as you ate it, for example peeled, boiled or fried. Leave out peel, shell, bone and anything you did not eat.").font(.caption)
                TextField(usesPlate ? "Total food and plate weight (g)" : "Total edible weight (g)", text: $directWeightText)
                    .amountKeyboard($editingAmount, .confirmDirectWeight)
                    .onChange(of: directWeightText) { _, value in model.send(.setDirectWeight(FoodAmountFieldText.parse(value, locale: locale))) }
                    .accessibilityLabel("Total edible weight in grams")
                if usesPlate { Text("Enter the food and plate total here. The empty plate weight below is subtracted to obtain edible grams.").font(.caption) }
                Picker("How you got the weight", selection: Binding<UserWeightBasis?>(
                    get: { model.state.quantity.directWeight?.basis },
                    set: { model.send(.setWeightBasis($0)) })) {
                    Text("Choose one").tag(UserWeightBasis?.none)
                    Text("I weighed it").tag(UserWeightBasis?.some(.measured))
                    Text("I estimated it").tag(UserWeightBasis?.some(.estimated))
                }
                ForEach(model.directWeightRequirements, id: \.self) { Text($0).font(.caption) }
                if model.state.quantity.directWeight?.needsReconfirmation == true {
                    Button("Keep this weight") { model.send(.confirmRetainedWeight) }.frame(minHeight: 44)
                }
                Text("The original amount below is kept as well. Changing it does not change your weight in grams.").font(.caption)
                Button("Use original amount instead") { model.send(.endDirectWeight) }
            }
            TextField(model.state.isSourceRecipe ? "Recipe servings eaten" : model.state.usesSourceDeclaredServing ? "Source servings eaten" : model.state.quantity.directWeight == nil ? "Quantity" : "Original amount (optional)", text: $totalText)
                .amountKeyboard($editingAmount, .confirmQuantity)
                .onChange(of: totalText) { _, value in
                    model.send(.setQuantityText(FoodAmountFieldText.reducerText(value, locale: locale)))
                }
                .accessibilityLabel("Food or total weight quantity")
            Picker("Unit", selection: quantityUnitBinding) {
                Text("g").tag(QuantityUnit.grams)
                Text("mL").tag(QuantityUnit.millilitres)
                Text(model.state.isSourceRecipe ? "recipe servings" : model.state.usesSourceDeclaredServing ? "source servings"
                     : model.countsPastedLabelServings ? "servings" : "count").tag(QuantityUnit.count)
            }
            if let requirement = model.originalAmountRequirement { Text(requirement).font(.caption) }
            whenRow
            if let warning = model.quantityBasisWarning {
                Label(warning, systemImage: "exclamationmark.triangle").font(.caption)
            }
            if let mismatch = model.sourceUnitAction {
                Button(mismatch.actionTitle) {
                    model.useSourceBasisUnit()
                    totalText = ""
                    resetConversionFields()
                }
                .frame(minHeight: 44)
            }
            if let offer = model.applicableVolumeConversion {
                Button(FoodConfirmationViewModel.volumeEstimateActionTitle) { model.applyAvailableVolumeConversion() }
                Text("\(model.state.quantity.value?.formatted() ?? "") mL gives about \(offer.convertedQuantity.value.formatted()) g. This estimate applies only to the selected UK CoFID whole pasteurised milk record. Check the food before using it; measured edible grams remain an alternative.")
                    .font(.caption)
            }
            if let conversion = model.state.quantity.conversion {
                let method = model.conversionMethodLabel ?? conversion.methodVersion.value
                LabeledContent("Weight or volume method", value: method)
                    .accessibilityLabel("Weight or volume method, \(method)")
                if let url = model.volumeConversionSourceURL,
                   let sourceID = conversion.sourceReleaseID,
                   let source = model.state.input.sourceReleases.first(where: { $0.sourceReleaseID == sourceID }) {
                    DisclosureGroup("Volume estimate source") {
                        LabeledContent("Method identifier", value: conversion.methodVersion.value)
                            .font(.caption).textSelection(.enabled)
                        Text(source.attribution.value).font(.caption).textSelection(.enabled)
                        Text(source.licence.value).font(.caption2).textSelection(.enabled)
                        Link("Open conversion source", destination: url)
                    }
                }
                if model.volumeConversionSourceURL != nil {
                    Button("Remove volume estimate") { model.removeOfferedVolumeConversion() }
                }
            }
            if model.state.quantity.unit == .count && model.state.quantity.directWeight == nil && !model.state.usesSourceDeclaredServing
                && !model.countsPastedLabelServings {
                Text("No source-backed size guide is available for this food. Enter the total edible weight, excluding shell, bone or other parts you did not eat.").font(.caption)
                TextField("Converted edible amount", text: $conversionText)
                    .amountKeyboard($editingAmount, .confirmConversion)
                    .onChange(of: conversionText) { _, _ in updateConversion() }
                Picker("Converted unit", selection: $conversionUnit) {
                    Text("g").tag(QuantityUnit.grams)
                    Text("mL").tag(QuantityUnit.millilitres)
                }
                .onChange(of: conversionUnit) { _, _ in updateConversion() }
                TextField("How was this weight or volume measured?", text: $conversionMethod)
                    .onChange(of: conversionMethod) { _, _ in updateConversion() }
                    .accessibilityHint("Required provenance for a count or portion conversion")
                if model.state.quantity.conversion == nil {
                    Label("Enter the total edible weight or volume and how you measured it", systemImage: "exclamationmark.triangle")
                }
            }
            ForEach(model.plateRequirements, id: \.self) { Text($0).font(.caption) }
            if model.savedResult != nil {
                // Once saved, a static row: a disclosure chevron would look active while every
                // other control is disabled (#212).
                LabeledContent("Weighed on a plate", value: Self.savedPlateRowValue(usesPlate: usesPlate, emptyPlateGrams: emptyPlateGrams, locale: locale))
                    .foregroundStyle(.secondary)
            } else {
                DisclosureGroup("Weighed on a plate") {
                    Picker("Weighing method", selection: plateModeBinding) {
                        Text(Self.weighingMethodTitle(usesPlate: false)).tag(false)
                        Text(Self.weighingMethodTitle(usesPlate: true)).tag(true)
                    }
                    if usesPlate {
                        TextField("Empty plate weight (g)", text: $emptyPlateText)
                            .amountKeyboard($editingAmount, .confirmEmptyPlate)
                            .onChange(of: emptyPlateText) { _, value in
                                guard let amount = FoodAmountFieldText.parse(value, locale: locale),
                                      let quantity = try? PositiveQuantity(value: amount, unit: .grams) else {
                                    model.send(.setPlateChoice(.missing))
                                    return
                                }
                                model.send(.setPlateChoice(.new(
                                    emptyWeight: quantity,
                                    superseding: model.state.reopened?.plateWeightVersion
                                )))
                            }
                            .accessibilityHint("The food weight is total weight minus this saved immutable plate version")
                    }
                }
            }
        }
    }

    private var compactNutritionSection: some View {
        let review = model.nutritionReview
        return Section(review.title) {
            Text(review.basis).font(.subheadline).foregroundStyle(.secondary)
            ForEach(review.mainRows, id: \.key.rawValue) { row in
                LabeledContent(row.title, value: row.value)
                    .accessibilityLabel("\(row.title), \(row.value), \(review.basis)")
            }
            if review.includesEstimates || model.state.isGenericEstimate || model.state.isSourceRecipe || model.state.reviewedWebProposalScope != nil {
                Text("Estimated nutrition").font(.caption)
            }
            if !review.isConsumed { Text("Source values. Enter a compatible amount to see your intake.").font(.caption) }
            DisclosureGroup("More nutrients") {
                ForEach(review.otherRows, id: \.key.rawValue) { row in
                    LabeledContent(row.title, value: row.value)
                }
            }
        }
    }

    private var nutritionSection: some View {
        let totals = model.consumedNutrition
        return Group {
            Section(model.nutritionReferenceTitle) {
                Text("Source reference values, not the amount eaten. Provenance and bounds are preserved.")
                    .font(.caption)
                ForEach(model.state.selectedCandidate.candidate.nutrients.entries, id: \.key.rawValue) { entry in
                    LabeledContent(Self.nutrientLabel(entry.key), value: Self.nutrientValue(entry))
                        .accessibilityLabel("\(Self.nutrientLabel(entry.key)), \(Self.nutrientValue(entry))")
                }
            }
            Section("Consumed nutrition for the amount eaten") {
                Text(model.consumedNutritionBasisLabel).font(.caption)
                ForEach(model.state.selectedCandidate.candidate.nutrients.entries, id: \.key.rawValue) { entry in
                    let total = totals.first { $0.key == entry.key }
                    LabeledContent(Self.nutrientLabel(entry.key), value: total?.knownAmount.map {
                        "\(Self.number($0)) \(entry.key.canonicalUnit.rawValue)\(total?.includesEstimates == true ? " estimated" : "")"
                    } ?? "Unavailable")
                }
                Text("Unknown values remain unknown. Bounds remain intervals and are never shown as exact amounts. Unavailable consumed values require a supported amount conversion and an exact source value.")
                    .font(.caption)
            }
        }
    }

    private var correctionSection: some View {
        Section("Food details") {
            TextField("Product name", text: $correctionName)
            TextField("Brand (optional)", text: $correctionBrand)
            TextField("Variant (optional)", text: $correctionVariant)
            Picker("Item class", selection: $correctionItemClass) {
                ForEach([ItemClass.food, .fortifiedFood, .supplement, .drink, .water], id: \.rawValue) {
                    Text(Self.label($0.rawValue)).tag($0.rawValue)
                }
            }
            Picker("Preparation", selection: $correctionPreparation) {
                ForEach([PreparationKind.asSold, .raw, .cooked, .reheated, .named, .unknown], id: \.rawValue) {
                    Text(Self.label($0.rawValue)).tag($0.rawValue)
                }
            }
            if correctionPreparation == PreparationKind.named.rawValue {
                TextField("Preparation method", text: $correctionPreparationMethod)
            }
            Picker("Bone", selection: $correctionBone) {
                ForEach([BoneState.withBone, .boneless, .notApplicable, .unknown], id: \.rawValue) {
                    Text(Self.label($0.rawValue)).tag($0.rawValue)
                }
            }
            Picker("Skin", selection: $correctionSkin) {
                ForEach([SkinState.skinOn, .skinless, .notApplicable, .unknown], id: \.rawValue) {
                    Text(Self.label($0.rawValue)).tag($0.rawValue)
                }
            }
            Picker("Drained state", selection: $correctionDrained) {
                ForEach([DrainedState.drained, .undrained, .notApplicable, .unknown], id: \.rawValue) {
                    Text(Self.label($0.rawValue)).tag($0.rawValue)
                }
            }
            TextField("Packing medium", text: $correctionPackingMedium)
                .accessibilityHint("A blank packing medium remains unresolved")
            Picker("Fortification", selection: $correctionFortification) {
                ForEach([FortificationState.fortified, .unfortified, .unknown], id: \.rawValue) {
                    Text(Self.label($0.rawValue)).tag($0.rawValue)
                }
            }
            Picker("Nutrition basis", selection: $correctionBasis) {
                Text("Keep populated basis").tag(CorrectionBasis.keepPopulated)
                Text("Per 100 g").tag(CorrectionBasis.per100Grams)
                Text("Per 100 mL").tag(CorrectionBasis.per100Millilitres)
            }
            TextField("Reason for correction", text: $correctionReason, axis: .vertical)
            Button("Apply correction as a new version") {
                guard let name = try? LedgerText(correctionName),
                      let reason = try? LedgerText(correctionReason),
                      let identity = makeCorrectedIdentity(),
                      let itemClass = ItemClass(rawValue: correctionItemClass) else { return }
                let selected = model.state.selectedCandidate
                model.send(.applyCorrection(FoodCorrection(
                    name: name,
                    brand: try? Self.optionalText(correctionBrand),
                    variant: try? Self.optionalText(correctionVariant),
                    identity: identity,
                    itemClass: itemClass,
                    nutrients: selected.candidate.nutrients,
                    reason: reason
                )))
            }
            .disabled(
                correctionName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || correctionReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            )
            Text("Corrections keep your reason and the original source evidence.")
                .font(.caption)
            Text("Enter only details you know. Missing catalogue facts remain unknown. Fortified identity must use the fortified-food item class.")
                .font(.caption)
        }
    }

    @ViewBuilder
    private var recoverySection: some View {
        if case let .saveFailed(message) = model.state.phase {
            Section("Not logged") {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .accessibilityLabel("Not logged. \(message)")
            }
        } else if case .saved = model.state.phase {
            Section {
                Label("Food logged", systemImage: "checkmark.circle.fill")
                    .accessibilityLabel("Food logged successfully")
                if model.favouriteOutcome == .failed {
                    Label(QuickAddText.favouriteNotSaved, systemImage: "exclamationmark.triangle.fill")
                    Button("Try again") { model.saveFavourite() }.frame(minHeight: 44)
                } else if model.favouriteOutcome == .saved {
                    Label("Saved as a favourite", systemImage: "star.fill")
                }
                if let saved = model.savedResult {
                    LabeledContent("Logged food", value: saved.productVersion.name.value)
                    LabeledContent("Logged amount", value: "\(editableNumber(saved.logItemVersion.edibleQuantity.value)) \(saved.logItemVersion.edibleQuantity.unit.rawValue)")
                }
            }
        }
    }

    private var candidateBinding: Binding<Int> {
        Binding(get: { model.state.selectedCandidateIndex }, set: {
            model.send(.selectCandidate($0))
            totalText = model.state.quantity.value.map(editableNumber) ?? ""
            directWeightText = model.state.quantity.directWeight?.totalGrams.map(editableNumber) ?? ""
            conversionText = model.state.quantity.conversion.map { editableNumber($0.convertedQuantity.value) } ?? ""
            let selected = model.state.selectedCandidate
            correctionName = selected.name.value
            correctionBrand = selected.brand?.value ?? ""
            correctionVariant = selected.variant?.value ?? ""
            loadIdentityCorrection(selected)
        })
    }

    private var quantityUnitBinding: Binding<QuantityUnit> {
        Binding(get: { model.state.quantity.unit }, set: { unit in
            // B2: a different unit clears the amount (in the reducer), so the old number is never
            // reread in the new unit; the field follows the state.
            guard unit != model.state.quantity.unit else { return }
            model.chooseQuantityUnit(unit)
            totalText = ""
            resetConversionFields()
        })
    }

    /// A unit change clears the typed conversion too (the reducer already cleared the state's),
    /// so count, g, count never brings back an earlier conversion.
    private func resetConversionFields() {
        let fields = ConversionFields.cleared
        conversionText = fields.text
        conversionUnit = fields.unit
        conversionMethod = fields.method
    }

    private func updateConversion() {
        guard model.state.quantity.unit == .count else { model.send(.setConversion(nil)); return }
        model.send(.setConversion(ConversionFields(text: conversionText, unit: conversionUnit, method: conversionMethod)
            .draft(locale: locale)))
    }

    /// The typed count conversion on Confirm: converted amount, its unit and how it was measured.
    public struct ConversionFields: Equatable, Sendable {
        public var text: String
        public var unit: QuantityUnit
        public var method: String

        public init(text: String, unit: QuantityUnit, method: String) {
            self.text = text; self.unit = unit; self.method = method
        }

        /// The fields after a unit change: empty, grams.
        public static let cleared = ConversionFields(text: "", unit: .grams, method: "")

        /// The conversion these fields describe, or nil when any part is missing or invalid.
        public func draft(locale: Locale) -> QuantityConversionDraft? {
            guard let value = FoodAmountFieldText.parse(text, locale: locale),
                  let quantity = try? PositiveQuantity(value: value, unit: unit),
                  let methodText = try? LedgerText(method) else { return nil }
            return QuantityConversionDraft(convertedQuantity: quantity, methodVersion: methodText,
                                           sourceReleaseID: nil, evidenceID: nil)
        }
    }

    private var emptyPlateGrams: Double? {
        switch model.state.quantity.plateChoice {
        case let .saved(version): version.emptyWeight.value
        case let .new(emptyWeight, _): emptyWeight.value
        case .foodOnly, .missing: nil
        }
    }

    private var usesPlate: Bool {
        switch model.state.quantity.plateChoice {
        case .foodOnly: false
        case .missing, .saved, .new: true
        }
    }

    private var plateModeBinding: Binding<Bool> {
        Binding(get: { usesPlate }, set: { enabled in
            if enabled {
                if let saved = model.state.reopened?.plateWeightVersion {
                    model.send(.setPlateChoice(.saved(saved)))
                    emptyPlateText = editableNumber(saved.emptyWeight.value)
                } else {
                    model.send(.setPlateChoice(.missing))
                    emptyPlateText = ""
                }
            } else {
                model.send(.setPlateChoice(.foodOnly))
            }
        })
    }

    private static func label(_ value: IdentityContradiction) -> String {
         value.rawValue.replacingOccurrences(of: "_", with: " ").capitalized
    }

    private static func label(_ value: String) -> String {
        value.replacingOccurrences(of: "_", with: " ").capitalized
    }

    private enum CorrectionBasis: Hashable {
        case keepPopulated
        case per100Grams
        case per100Millilitres
    }

    private func loadIdentityCorrection(_ selected: PopulatedFoodCandidate) {
        let identity = model.displayedIdentity
        correctionPreparation = identity.preparation.kind.rawValue
        correctionPreparationMethod = identity.preparation.method?.value ?? ""
        correctionBone = identity.bone.rawValue
        correctionSkin = identity.skin.rawValue
        correctionDrained = identity.drained.rawValue
        if case let .named(value) = identity.packingMedium {
            correctionPackingMedium = value.value
        } else {
            correctionPackingMedium = ""
        }
        correctionFortification = identity.fortification.rawValue
        correctionItemClass = (model.state.correction?.itemClass ?? model.state.reopened?.productVersion.itemClass ?? selected.itemClass).rawValue
        correctionBasis = .keepPopulated
    }

    private func makeCorrectedIdentity() -> DecisiveIdentity? {
        guard let preparationKind = PreparationKind(rawValue: correctionPreparation),
              let bone = BoneState(rawValue: correctionBone),
              let skin = SkinState(rawValue: correctionSkin),
              let drained = DrainedState(rawValue: correctionDrained),
              let fortification = FortificationState(rawValue: correctionFortification) else { return nil }
        let method = preparationKind == .named ? try? Self.optionalText(correctionPreparationMethod) : nil
        guard let preparation = try? PreparationState(kind: preparationKind, method: method) else { return nil }
        let packing: PackingMediumState
        if let value = try? Self.optionalText(correctionPackingMedium) { packing = .named(value) }
        else { packing = .unknown }
        let selected = model.state.selectedCandidate.candidate.identity
        let basis: ResolutionBasis
        switch correctionBasis {
        case .keepPopulated: basis = selected.servingBasis
        case .per100Grams: basis = .per100Grams
        case .per100Millilitres: basis = .per100Millilitres
        }
        return try? DecisiveIdentity(
            preparation: preparation,
            bone: bone,
            skin: skin,
            drained: drained,
            packingMedium: packing,
            fortification: fortification,
            declaredFortificants: fortification == .fortified ? selected.declaredFortificants : [],
            servingBasis: basis
        )
    }

    private static func optionalText(_ value: String) throws -> LedgerText? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : try LedgerText(trimmed)
    }

    private static func preparationLabel(_ value: PreparationState) -> String {
        value.method?.value ?? label(value.kind.rawValue)
    }

    private static func packingLabel(_ value: PackingMediumState) -> String {
        switch value { case let .named(text): text.value; case .unknown: "Unknown" }
    }

    fileprivate static func basisLabel(_ value: ResolutionBasis) -> String {
        switch value {
        case .per100Grams: "Per 100 g"
        case .per100Millilitres: "Per 100 mL"
        case let .perServing(quantity): "Per serving (\(number(quantity.value)) \(quantity.unit.rawValue))"
        case let .perUnit(quantity): "Per unit (\(number(quantity.value)) \(quantity.unit.rawValue))"
        case let .named(name, quantity): "\(name.value) (\(number(quantity.value)) \(quantity.unit.rawValue))"
        case .unknown: "Unknown"
        }
    }

    private static func nutrientLabel(_ value: NutrientKey) -> String {
        FoodConfirmationViewModel.nutrientLabel(value)
    }

    private static func nutrientValue(_ entry: NutrientEntry) -> String {
        switch entry.value {
        case let .measured(value): "\(number(value.amount)) \(value.unit.rawValue) measured"
        case let .augmented(value): "\(number(value.amount)) \(value.unit.rawValue) augmented"
        case let .bounded(value):
            "\(value.lower.map(number) ?? "open")–\(value.upper.map(number) ?? "open") \(value.unit.rawValue) bounded"
        case let .unknown(reason): "Unknown (\(String(describing: reason).replacingOccurrences(of: "_", with: " ")))"
        }
    }

    /// "1 saved item", "3 saved items".
    public static func evidenceCount(_ count: Int) -> String { count == 1 ? "1 saved item" : "\(count) saved items" }

    private static func number(_ value: Double) -> String { value.formatted(.number.precision(.fractionLength(0...3))) }

    private static func editableNumber(_ value: Double, locale: Locale) -> String { FoodAmountFieldText.text(value, locale: locale) }
    private func editableNumber(_ value: Double) -> String { Self.editableNumber(value, locale: locale) }
}
