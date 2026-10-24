import FoodLedgerApplication
import FoodLedgerDomain
import SwiftUI

@MainActor
public final class FoodConfirmationViewModel: ObservableObject {
    @Published public private(set) var state: FoodConfirmationState {
        didSet { if state.correction == nil && correctionAppliedOnConfirm { correctionAppliedOnConfirm = false } }
    }
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
        // Pasted label Confirm v1 C11: the flag, and Not stated while fortification stays unknown.
        next.answersLabelFortification = state.answersLabelFortification
        if state.decisions[.fortification] == .notSure, candidate.candidate.identity.fortification == .unknown {
            next.decisions[.fortification] = .notSure
        }
        sourceDetailsNotice = nil
        if let correction = state.correction {
            let source = candidate.candidate.identity
            let previous = correction.identity
            do {
                let identity = try DecisiveIdentity(preparation: previous.preparation, bone: previous.bone, skin: previous.skin,
                    drained: previous.drained, packingMedium: previous.packingMedium, fortification: previous.fortification,
                    declaredFortificants: previous.declaredFortificants, servingBasis: source.servingBasis)
                FoodConfirmationReducer.reduce(state: &next, action: .applyCorrection(FoodCorrection(name: correction.name,
                    brand: correction.brand, variant: correction.variant, identity: identity, itemClass: correction.itemClass,
                    nutrients: candidate.candidate.nutrients, reason: correction.reason)))
            } catch {
                // Never dropped silently: the details requirement shows again, with this reason.
                sourceDetailsNotice = Self.sourceDetailsNotCarried
            }
        }
        state = next
    }

    /// Why an "Add food details" answer was not carried into a rebuilt pasted-label source.
    @Published public internal(set) var sourceDetailsNotice: String?
    public static let sourceDetailsNotCarried = "Your food details could not be kept after this change. Add them again before logging."

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

    /// Where the pasted label's serving size came from: printed, or corrected or entered by the
    /// user on Confirm (its correction record). Whole pack's caption names it.
    public var pastedLabelServingSizeOrigin: NutrientValueOrigin {
        guard let manifest = PastedLabelValueOrigins.manifest(state.input, candidate: state.selectedCandidate),
              let entry = manifest.corrections.first(where: { $0.nutrient == PastedLabelManifest.Correction.servingSize }) else {
            return .printed
        }
        return entry.kind == .corrected ? .correctedByYou : .enteredByYou
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

    /// count-conversion-method-v1 "Estimated by eye": never a measured conversion. Opens direct
    /// weight with the estimated basis (the user's explicit choice), keeps the count as the original
    /// input and carries a gram amount when one was typed.
    public func useEstimatedCountWeight(grams: Double?) {
        guard state.quantity.unit == .count, state.quantity.directWeight == nil else { return }
        send(.beginDirectWeight)
        send(.setDirectWeight(grams))
        send(.setWeightBasis(.estimated))
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
        return usesOfferedVolumeEstimate ? Self.offeredVolumeEstimateLabel
            : FoodConfirmationView.ConversionFields.storedMethodLabel(conversion.methodVersion)
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
            if state.quantity.directWeight == nil && state.quantity.unit == .millilitres {
                return "Enter the amount you had in mL, greater than zero."
            }
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
        requirements.first.map(requirementText) ?? (hasChangesToSave ? nil : Self.noChangesReason)
    }

    /// One renderer for requirements: the pasted-label fortification decision has its own label
    /// wording (pasted label Confirm v1, 4.2); everything else is the generic copy.
    public func requirementText(_ requirement: FoodLogRequirement) -> String {
        if requirement == .decideDifference(.fortification), labelFortificationApplies {
            return PastedLabelText.fortificationRequirement
        }
        return FoodLogRequirementText.text(requirement)
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

    /// Decisions rendered by the generic decisions loop. The pasted-label fortification facet is
    /// rendered by its own section (C5), so it is skipped here.
    public var pendingDifferences: [IdentityContradiction] {
        let pending = FoodLogPolicy.pendingDifferences(state)
        return labelFortificationApplies ? pending.filter { $0 != .fortification } : pending
    }

    // MARK: Pasted label fortification (pasted label Confirm v1, #306)

    /// The answer as Confirm shows it.
    public enum LabelFortification: Equatable, Sendable { case unanswered, yes, no, notStated }

    /// The editable source the Yes and No answers rebuild. Held weakly: the route owns it.
    private weak var labelSource: PastedLabelSourceModel?

    /// The one entry point that marks this Confirm as answering a pasted label's fortification
    /// (C4, R2). Only an editable source (a new reading) sets the flag; a stored source never does.
    public func answersLabelFortification(for source: PastedLabelSourceModel) {
        guard source.isEditable, state.reopened == nil, savedResult == nil else { return }
        labelSource = source
        state.answersLabelFortification = true
    }

    /// Whether the Fortification section asks the question on this Confirm.
    public var labelFortificationApplies: Bool { PastedLabelFortificationPolicy.applies(state) }

    /// Whether this Confirm asks the Fortification question: an editable reading, or a re-log or
    /// favourite of a stored label whose fortification is still unknown. A stored Yes or No is
    /// shown read-only instead (invariant re-check of b555285d).
    public var asksLabelFortification: Bool {
        labelFortificationApplies && state.reopened == nil
            && (state.answersLabelFortification || state.selectedCandidate.candidate.identity.fortification == .unknown)
    }

    /// Whether Yes and No can be answered inline: only an editable source can be rebuilt.
    public var answersLabelFortificationInline: Bool { asksLabelFortification && state.answersLabelFortification }

    /// The answers offered inline, in order.
    public var labelFortificationChoices: [LabelFortification] {
        answersLabelFortificationInline ? [.yes, .no, .notStated] : [.notStated]
    }

    /// Whether the estimate notice sits in the Fortification section, below the answers, so that
    /// choosing Not stated moves nothing above the finger (journey QA of 381e694e).
    public var showsEstimateNoticeInFortification: Bool { asksLabelFortification && savesEstimate }

    /// Whether the footer adds the generic estimate notice: never after Not stated, whose own
    /// footer already says the entry is an estimate (one notice, #306 journey QA D4).
    public var showsSeparateEstimateNotice: Bool { showsEstimateNoticeInFortification && labelFortification != .notStated }

    /// The Source footer. A pasted label never suggests another match: an editable reading points
    /// to Edit label text and corrections; a re-log or favourite to pasting the label again (D3).
    public var sourceFooter: String {
        let pasted = PastedLabelFortificationPolicy.isPastedLabel(state.input, candidate: state.selectedCandidate)
        guard pasted, state.reopened == nil else {
            return "Need to correct the food itself? Choose a different match, or edit the details from the entry after logging."
        }
        return state.answersLabelFortification ? PastedLabelText.sourceFooter : PastedLabelText.sourceFooterStored
    }

    /// The recorded answer, read-only: on a reopened pasted-label entry (section 5.1), or on a
    /// re-log or favourite of a stored label already answered Yes or No. Nil when the question is
    /// asked or the source is not a pasted label.
    public var reopenedLabelFortification: String? {
        guard !asksLabelFortification,
              let manifest = PastedLabelValueOrigins.manifest(state.input, candidate: state.selectedCandidate) else { return nil }
        if let reopened = state.reopened { return PastedLabelFortificationText.value(reopened, manifest: manifest) }
        guard labelFortificationApplies else { return nil }
        return PastedLabelFortificationText.value(answer: manifest.identityMapping.fortificationAnswer,
                                                  recordsNotStated: false, corrected: false)
    }

    public var labelFortification: LabelFortification {
        if state.decisions[.fortification] == .notSure { return .notStated }
        if let reopened = state.reopened, PastedLabelFortificationPolicy.recordsNotStated(reopened) { return .notStated }
        switch labelSource?.fortificationAnswer {
        case .yes?: return .yes
        case .no?: return .no
        default: return .unanswered
        }
    }

    /// Why the last answer could not be applied, or nil.
    @Published public private(set) var labelFortificationFailure: String?

    /// Yes and No rebuild the source with the manifest answer; Not stated records the existing
    /// typed `not_sure` decision with the source left unknown (C2).
    public func answerLabelFortification(_ answer: LabelFortification) {
        guard asksLabelFortification, savedResult == nil else { return }
        labelFortificationFailure = nil
        switch answer {
        case .unanswered: return
        case .notStated:
            if let source = labelSource, source.fortificationAnswer != .unanswered {
                do { try source.answerFortification(.unanswered) } catch {
                    labelFortificationFailure = PastedLabelText.fortificationNotApplied
                    return
                }
            }
            // Only a pending difference is decided: a known fortification has nothing to record.
            guard FoodLogPolicy.pendingDifferences(state).contains(.fortification) else { return }
            send(.decideDifference(.fortification, .notSure))
        case .yes, .no:
            guard let source = labelSource else { return }
            do {
                try source.answerFortification(answer == .yes ? .yes : .no)
            } catch {
                labelFortificationFailure = PastedLabelText.fortificationNotApplied
            }
        }
    }

    public var labelFortificationFooter: String {
        switch labelFortification {
        case .unanswered where !answersLabelFortificationInline: PastedLabelText.fortificationFooterStored
        case .unanswered: PastedLabelText.fortificationFooterUnanswered
        case .yes: PastedLabelText.fortificationFooterYes
        case .no: PastedLabelText.fortificationFooterNo
        case .notStated: PastedLabelText.fortificationFooterNotStated
        }
    }

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
        return "Log \(energyIsCalculated ? "about " : "")\(FoodDisplayNumber.energy(amount))"
    }

    /// The energy value is a calculated one (pasted label, kJ only; contract section 3.5), so
    /// it shows "about" wherever it is stated, the Log button and banner included.
    public var energyIsCalculated: Bool {
        let nutrients = state.correction?.nutrients ?? state.selectedCandidate.candidate.nutrients
        return nutrients.entries.first { $0.key == .energyConsumed }.map { NutrientDerivation.isCalculated($0.value) } ?? false
    }

    /// A value shown on Confirm with its calculated marking: "about 371 kcal · Calculated" for a
    /// calculated nutrient (section 3.5), otherwise the value as given.
    public func markingCalculated(_ key: NutrientKey, _ value: String) -> String {
        let nutrients = state.correction?.nutrients ?? state.selectedCandidate.candidate.nutrients
        guard let entry = nutrients.entries.first(where: { $0.key == key }), NutrientDerivation.isCalculated(entry.value) else { return value }
        // An exact amount reads "about …"; a bound keeps its own wording and gains the tag.
        return value.first?.isNumber == true ? "about \(value) · Calculated" : "\(value) · Calculated"
    }

    /// A nutrient as shown on Confirm, with a calculated value through the one calculated
    /// formatter (section 3.5): whole kcal and mg with "about" for an exact amount, an outward
    /// bound for a bound, and the "Calculated" tag. `consumed` is the amount eaten when the row
    /// shows intake; `source` true shows the stored source value. Other values are unchanged.
    public func displayValue(_ key: NutrientKey, _ value: String, consumed: Double? = nil, source: Bool = false) -> String {
        let nutrients = state.correction?.nutrients ?? state.selectedCandidate.candidate.nutrients
        guard let entry = nutrients.entries.first(where: { $0.key == key }), NutrientDerivation.isCalculated(entry.value) else { return value }
        let tag = NutrientOriginText.tag(.calculated(rule: ""))
        let exact: Bool = switch entry.value { case .measured, .augmented: true; default: false }
        if exact, let consumed {
            return "\(NutrientOriginText.calculatedAmount(consumed, unit: key.canonicalUnit.rawValue, comparator: "=")) · \(tag)"
        }
        if source {
            let shown = NutrientOriginText.amount(entry.value, origin: .calculated(rule: ""))
            return shown.hasSuffix(" · \(tag)") ? shown : "\(shown) · \(tag)"
        }
        // A calculated upper bound for the amount eaten: the Food Log row's rule (an upper end
        // and no lower end, scaled to the amount; "less than 0" stays unknown), shown as a bound
        // with its end rounded up, never as unavailable, an exact amount or zero.
        if case let .bounded(bounds) = entry.value, bounds.lower == nil, let upper = bounds.upper, upper > 0 || bounds.upperClosed,
           let eaten = try? state.calculatedEdibleQuantity(),
           let scale = FoodIntakeSummary.scale(quantity: eaten, basis: (state.correction?.identity ?? state.selectedCandidate.candidate.identity).servingBasis),
           (upper * scale).isFinite {
            return NutrientOriginText.calculatedAmount(upper * scale, unit: key.canonicalUnit.rawValue, comparator: bounds.upperClosed ? "<=" : "<")
        }
        return markingCalculated(key, value)
    }

    /// The consumed amount behind a compact nutrition row, when the row shows intake.
    public func consumedAmount(_ key: NutrientKey, _ review: FoodNutritionReviewPresentation) -> Double? {
        guard review.isConsumed else { return nil }
        return consumedNutrition.first { $0.key == key }?.knownAmount
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
            message: FoodLoggedText.message(figure: logPress.energy.map { (energyIsCalculated ? "about " : "") + FoodDisplayNumber.energy($0) },
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
        // The user answered "Add food details" again: the not-carried notice no longer applies.
        if case .applyCorrection = action {
            sourceDetailsNotice = nil
            correctionAppliedOnConfirm = true
        }
    }

    /// The Food details sheet's Apply (#276): records the typed details as a correction on
    /// Confirm. Returns false, changing nothing, when an answer is invalid. Nothing is saved;
    /// Log (or Save changes) stays the only save.
    @discardableResult
    public func applyFoodDetails(_ draft: FoodDetailsDraft) -> Bool {
        guard savedResult == nil, draft.canApply, let correction = draft.correction(for: state.selectedCandidate) else { return false }
        send(.applyCorrection(correction))
        return true
    }

    /// Set once the user applied food details on this Confirm, so the correction is marked with
    /// a visible confirmation rather than only a caption. Reset whenever the correction is gone
    /// (`state`'s observer), so a later carried-over correction is not announced as the user's.
    @Published private var correctionAppliedOnConfirm = false

    /// The button that opens the Food details sheet, or nil: "Add food details" while source
    /// details are missing, otherwise "Correct food details" for a saved entry or once details
    /// were applied, so an applied correction can be reopened before Log (#276).
    public var foodDetailsActionTitle: String? {
        // C6: never the catalogue form while an editable pasted label asks its own question. A
        // re-log or favourite cannot rebuild its stored label, so Yes or No goes through Food
        // details there, beside the inline Not stated.
        if state.answersLabelFortification && state.reopened == nil { return nil }
        if asksLabelFortification, state.selectedCandidate.candidate.identity.fortification == .unknown {
            return Self.addFoodDetailsTitle
        }
        if !missingSourceDetails.isEmpty { return Self.addFoodDetailsTitle }
        if state.reopened != nil || state.correction != nil { return Self.correctFoodDetailsTitle }
        return nil
    }

    public static let addFoodDetailsTitle = "Add food details"
    public static let correctFoodDetailsTitle = "Correct food details"

    /// The confirmation shown on Confirm, and announced to VoiceOver, after food details were
    /// applied (#276). Nil once the correction no longer stands (for example another match).
    public var correctionNotice: String? {
        guard correctionAppliedOnConfirm, state.correction != nil else { return nil }
        return state.reopened == nil ? Self.correctionAppliedForLog : Self.correctionAppliedForEdit
    }

    public static let correctionAppliedForLog =
        "Food details corrected. Log saves the correction as a new version with this entry."
    public static let correctionAppliedForEdit =
        "Food details corrected. Save changes saves the correction as a new version."

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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// The focused amount field, if any; "Done" above the decimal pad clears it (#212).
    @FocusState private var editingAmount: AmountFieldFocus?
    @State private var showsCorrection = false
    @State private var showsMatches = false
    /// The Food details sheet's answers; nil until Confirm appears and loads them.
    @State private var correctionDraft: FoodDetailsDraft?
    /// Set by Apply so the confirmation is announced once the sheet has closed (#276).
    @State private var announcesCorrection = false
    @State private var totalText = ""
    @State private var directWeightText = ""
    @State private var emptyPlateText = ""
    @State private var conversionText = ""
    @State private var conversionUnit = QuantityUnit.grams
    @State private var conversionMethod: ConversionFields.MethodSelection?
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
                labelFortificationSection
                decisionsSection
                quantitySection
                // Pasted label Confirm v1 (#306) C7: the label's values come after the amount.
                if let pastedLabel {
                    PastedLabelSourceSections(model: pastedLabel, editLabelText: model.savedResult == nil ? editLabelText : nil)
                }
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
                Text(model.sourceFooter)
            }
            recoverySection
            // #282 and the journey QA of #284: when the pinned bar would crowd out the content,
            // its warnings, hint and estimate scroll here, beside the Log area; Log stays pinned.
            if showsBeforeLog { beforeLogSection }
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
        .sheet(isPresented: $showsCorrection, onDismiss: announceCorrection) {
            NavigationStack {
                FoodDetailsForm(model: model, draft: correctionDraftBinding) {
                    announcesCorrection = true
                    showsCorrection = false
                }
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
            if correctionDraft == nil { correctionDraft = FoodDetailsDraft(model: model) }
            if let value = model.state.quantity.value { totalText = editableNumber(value) }
            directWeightText = model.state.quantity.directWeight?.totalGrams.map(editableNumber) ?? ""
            if let conversion = model.state.quantity.conversion {
                conversionText = editableNumber(conversion.convertedQuantity.value)
                conversionUnit = conversion.convertedQuantity.unit
                conversionMethod = ConversionFields.MethodSelection(stored: conversion.methodVersion)
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
            if model.savesEstimate && !model.showsEstimateNoticeInFortification {
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
            if let notice = model.correctionNotice {
                Label(notice, systemImage: "checkmark.circle").font(.subheadline)
            } else if model.state.correction != nil {
                Text("Uses your food correction").font(.caption)
            }
            if let notice = model.sourceDetailsNotice {
                Label(notice, systemImage: "exclamationmark.triangle").font(.subheadline)
            }
            if !model.missingSourceDetails.isEmpty {
                Label(FoodLogRequirementText.text(.sourceIdentityMissing(model.missingSourceDetails)),
                      systemImage: "exclamationmark.triangle")
                    .font(.subheadline)
            }
            if let title = model.foodDetailsActionTitle {
                Button(title) { showsCorrection = true }
                    .frame(minHeight: 44)
            }
            if model.state.input.candidates.count > 1 && model.state.reopened == nil && !model.asksLabelFortification {
                Button("Choose a different match") { showsMatches = true }
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

    /// Pasted label Confirm v1 (#306) section 4.1: one question in label wording, asked once.
    @ViewBuilder
    private var labelFortificationSection: some View {
        if model.asksLabelFortification {
            Section {
                Text(PastedLabelText.fortificationQuestion).font(.subheadline)
                    .accessibilityHidden(true)
                Picker(PastedLabelText.fortificationQuestion, selection: Binding<FoodConfirmationViewModel.LabelFortification?>(
                    get: { model.labelFortification == .unanswered ? nil : model.labelFortification },
                    set: { if let answer = $0 { model.answerLabelFortification(answer) } })) {
                    ForEach(model.labelFortificationChoices, id: \.self) { choice in
                        Text(PastedLabelText.fortificationChoice(choice)).tag(FoodConfirmationViewModel.LabelFortification?.some(choice))
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
                .accessibilityLabel(PastedLabelText.fortificationQuestion)
                if let failure = model.labelFortificationFailure {
                    Label(failure, systemImage: "exclamationmark.triangle").font(.subheadline)
                }
            } header: {
                Text(PastedLabelText.fortificationHeader)
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.labelFortificationFooter)
                    if model.showsSeparateEstimateNotice {
                        Label(FoodConfirmationViewModel.estimateNotice, systemImage: "info.circle")
                            .accessibilityLabel(FoodConfirmationViewModel.estimateNotice)
                    }
                }
            }
        } else if let value = model.reopenedLabelFortification {
            Section(PastedLabelText.fortificationHeader) {
                LabeledContent(PastedLabelFortificationText.title, value: value)
            }
        }
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

    /// Whether the bottom bar keeps only Log pinned and moves its warnings, hint and estimate into
    /// the scrolling content: at accessibility text sizes, or when the bar would hold more than
    /// two of them (about a third of the screen). Warning text is never truncated either way.
    public static func pinsOnlyLog(isAccessibilitySize: Bool, warningCount: Int, hasBlockedReason: Bool, hasEstimate: Bool) -> Bool {
        isAccessibilitySize || warningCount + (hasBlockedReason ? 1 : 0) + (hasEstimate ? 1 : 0) > 2
    }

    private var pinsOnlyLog: Bool {
        Self.pinsOnlyLog(isAccessibilitySize: dynamicTypeSize.isAccessibilitySize, warningCount: pastedLabel?.warnings.count ?? 0,
                         hasBlockedReason: model.blockedReason != nil, hasEstimate: model.volumeEstimateLogBarAction != nil)
    }

    @ViewBuilder
    private var logWarnings: some View {
        // Pasted label warnings (section 4): near Log, never blocking, never a pass badge.
        if let warnings = pastedLabel?.warnings, !warnings.isEmpty {
            ForEach(warnings, id: \.self) { warning in
                Label(warning, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityLabel("Warning. \(warning)")
            }
        }
    }

    @ViewBuilder
    private var estimateButton: some View {
        // Secondary and next to Log, so the sourced estimate is not missed when Log
        // would save without nutrition. It only applies the estimate; Log still saves.
        if let estimate = model.volumeEstimateLogBarAction {
            Button {
                model.applyAvailableVolumeConversion()
            } label: {
                Text(estimate.title)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.bordered)
            .disabled(!estimate.isEnabled)
            .accessibilityLabel(estimate.accessibilityLabel)
            .accessibilityHint(FoodConfirmationViewModel.VolumeEstimateLogBarAction.accessibilityHint)
        }
    }

    @ViewBuilder
    private var blockedReasonText: some View {
        if let reason = model.blockedReason {
            Text(reason).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The one line pinned beside a disabled Log when the full hint is in "Before you log".
    public static let pinnedBlockedReason = "Not ready to log yet. See “Before you log” below."

    /// Whether "Before you log" has anything to show; an empty section is never rendered.
    public static func showsBeforeLog(pinsOnlyLog: Bool, warningCount: Int, hasBlockedReason: Bool, hasEstimate: Bool) -> Bool {
        pinsOnlyLog && (warningCount > 0 || hasBlockedReason || hasEstimate)
    }

    private var showsBeforeLog: Bool {
        Self.showsBeforeLog(pinsOnlyLog: pinsOnlyLog, warningCount: pastedLabel?.warnings.count ?? 0,
                            hasBlockedReason: model.blockedReason != nil, hasEstimate: model.volumeEstimateLogBarAction != nil)
    }

    /// The bar's warnings, hint and estimate as the last content section when only Log is pinned.
    /// The hint is styled like the warnings: left-aligned, with an icon.
    private var beforeLogSection: some View {
        Section("Before you log") {
            logWarnings
            estimateButton
            if let reason = model.blockedReason {
                Label(reason, systemImage: "info.circle")
                    .font(.footnote)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
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
                if !pinsOnlyLog {
                    logWarnings
                    estimateButton
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
                if !pinsOnlyLog {
                    blockedReasonText
                } else if model.blockedReason != nil {
                    // Beside the disabled Log, one short line (it may wrap); the full hint scrolls.
                    Text(Self.pinnedBlockedReason).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
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
                Button(PastedLabelText.wholePackTitle(pack.servings)) {
                    model.chooseWholePack()
                    totalText = editableNumber(pack.servings)
                }
                .frame(minHeight: 44)
                .accessibilityHint("Sets the amount to the servings in one pack")
                Text((pack.origin == .printed ? "Servings per pack printed on the label. " : "Servings per pack entered by you. ")
                     + PastedLabelText.wholePackNote(servingSize: model.pastedLabelServingSizeOrigin)).font(.caption)
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
                // A closed choice (count-conversion-method-v1, #299); "Estimated by eye" is an
                // estimated direct weight, never a measured conversion.
                Picker(ConversionFields.methodTitle, selection: $conversionMethod) {
                    Text("Choose one").tag(ConversionFields.MethodSelection?.none)
                    if case let .recorded(text)? = conversionMethod {
                        Text(ConversionFields.label(.recorded(text))).tag(ConversionFields.MethodSelection?.some(.recorded(text)))
                    }
                    ForEach(CountConversionMethod.allCases, id: \.self) { method in
                        Text(ConversionFields.label(.choice(method))).tag(ConversionFields.MethodSelection?.some(.choice(method)))
                    }
                }
                .onChange(of: conversionMethod) { _, selection in
                    if case .choice(.estimatedByEye)? = selection { useEstimateByEye() } else { updateConversion() }
                }
                .accessibilityHint("Required. Kitchen scale and package weight are measured; estimated by eye logs an estimate.")
                .accessibilityIdentifier("confirm.conversionMethod")
                if model.state.quantity.conversion == nil,
                   let requirement = ConversionFields(text: conversionText, unit: conversionUnit, method: conversionMethod)
                    .requirementText(locale: locale) {
                    Label(requirement, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .accessibilityIdentifier("confirm.conversionRequirement")
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
                let value = model.displayValue(row.key, row.value, consumed: model.consumedAmount(row.key, review), source: !review.isConsumed)
                LabeledContent(row.title, value: value)
                    .accessibilityLabel("\(row.title), \(value), \(review.basis)")
            }
            if review.includesEstimates || model.state.isGenericEstimate || model.state.isSourceRecipe || model.state.reviewedWebProposalScope != nil {
                Text("Estimated nutrition").font(.caption)
            }
            if !review.isConsumed { Text("Source values. Enter a compatible amount to see your intake.").font(.caption) }
            DisclosureGroup("More nutrients") {
                ForEach(review.otherRows, id: \.key.rawValue) { row in
                    LabeledContent(row.title, value: model.displayValue(row.key, row.value, consumed: model.consumedAmount(row.key, review),
                                                                        source: !review.isConsumed))
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
                    let value = model.displayValue(entry.key, Self.nutrientValue(entry), source: true)
                    LabeledContent(Self.nutrientLabel(entry.key), value: value)
                        .accessibilityLabel("\(Self.nutrientLabel(entry.key)), \(value)")
                }
            }
            Section("Consumed nutrition for the amount eaten") {
                Text(model.consumedNutritionBasisLabel).font(.caption)
                ForEach(model.state.selectedCandidate.candidate.nutrients.entries, id: \.key.rawValue) { entry in
                    let total = totals.first { $0.key == entry.key }
                    LabeledContent(Self.nutrientLabel(entry.key), value: total?.knownAmount.map {
                        model.displayValue(entry.key,
                            "\(Self.number($0)) \(entry.key.canonicalUnit.rawValue)\(total?.includesEstimates == true ? " estimated" : "")",
                            consumed: $0)
                    } ?? model.displayValue(entry.key, "Unavailable"))
                }
                Text("Unknown values remain unknown. Bounds remain intervals and are never shown as exact amounts. Unavailable consumed values require a supported amount conversion and an exact source value.")
                    .font(.caption)
            }
        }
    }

    private var correctionDraftBinding: Binding<FoodDetailsDraft> {
        Binding(get: { correctionDraft ?? FoodDetailsDraft(model: model) }, set: { correctionDraft = $0 })
    }

    /// After Apply closed the sheet: VoiceOver hears the confirmation that Confirm now shows.
    private func announceCorrection() {
        guard announcesCorrection else { return }
        announcesCorrection = false
        if let notice = model.correctionNotice { AccessibilityNotification.Announcement(notice).post() }
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
            correctionDraft = FoodDetailsDraft(model: model, reason: correctionDraft?.reason ?? "")
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

    /// "Estimated by eye": the amount becomes an estimated direct weight with the count kept as the
    /// original input. A typed gram amount is carried over; millilitres are never read as grams.
    private func useEstimateByEye() {
        let grams = ConversionFields(text: conversionText, unit: conversionUnit, method: conversionMethod)
            .estimatedGrams(locale: locale)
        model.useEstimatedCountWeight(grams: grams)
        directWeightText = grams.map(editableNumber) ?? ""
        resetConversionFields()
    }

    /// The count conversion on Confirm: converted amount, its unit and how it was obtained.
    public struct ConversionFields: Equatable, Sendable {
        /// A closed choice (count-conversion-method-v1), or the typed text of a conversion recorded
        /// before v1, kept unchanged on reopen.
        public enum MethodSelection: Hashable, Sendable {
            case choice(CountConversionMethod)
            case recorded(LedgerText)

            /// The selection that shows a stored conversion method.
            public init(stored: LedgerText) {
                self = CountConversionMethod(storedCode: stored).map(Self.choice) ?? .recorded(stored)
            }
        }

        public var text: String
        public var unit: QuantityUnit
        public var method: MethodSelection?

        public init(text: String, unit: QuantityUnit, method: MethodSelection?) {
            self.text = text; self.unit = unit; self.method = method
        }

        /// The fields after a unit change: empty, grams, no method.
        public static let cleared = ConversionFields(text: "", unit: .grams, method: nil)

        public static let methodTitle = "How you got this amount"

        /// The shown label. The v1 code-to-label table is frozen by count-conversion-method-v1.
        public static func label(_ selection: MethodSelection) -> String {
            switch selection {
            case .choice(.kitchenScale): "Kitchen scale"
            case .choice(.packageWeight): "Package weight"
            case .choice(.estimatedByEye): "Estimated by eye"
            case let .recorded(text): "Recorded: \(FoodLogText.conversionMethodLabel(text.value) ?? text.value)"
            }
        }

        /// The label of a stored conversion method: the v1 label for a v1 code, else the stored text.
        public static func storedMethodLabel(_ stored: LedgerText) -> String {
            switch MethodSelection(stored: stored) {
            case let .choice(method): label(.choice(method))
            case .recorded: FoodLogText.conversionMethodLabel(stored.value) ?? stored.value
            }
        }

        /// The field-local requirement naming exactly which part is still missing, or nil when the
        /// fields describe a conversion. Presentation only: the Log rule stays
        /// `countNeedsMeasuredAmount`, unchanged.
        public func requirementText(locale: Locale) -> String? {
            guard draft(locale: locale) == nil else { return nil }
            switch (amount(locale: locale), method) {
            case let (amount?, nil):
                let unitText = unit == .millilitres ? "mL" : "g"
                return "Choose how you got the \(FoodNutritionReviewPresentation.number(amount.value)) \(unitText): kitchen scale, package weight or estimated by eye."
            case (nil, _?):
                return "Enter the total edible weight or volume, greater than zero."
            default:
                return "Enter the total edible weight or volume and choose how you got it."
            }
        }

        /// The measured conversion these fields describe, or nil when a part is missing or invalid,
        /// or when the method is an estimate (which is never a conversion).
        public func draft(locale: Locale) -> QuantityConversionDraft? {
            guard let quantity = amount(locale: locale), let method else { return nil }
            let methodText: LedgerText
            switch method {
            case let .choice(choice):
                guard let code = choice.storedCode else { return nil }
                methodText = code
            case let .recorded(text):
                methodText = text
            }
            return QuantityConversionDraft(convertedQuantity: quantity, methodVersion: methodText,
                                           sourceReleaseID: nil, evidenceID: nil)
        }

        /// The gram amount carried into an estimated direct weight; nil for millilitres or no amount.
        public func estimatedGrams(locale: Locale) -> Double? {
            guard unit == .grams else { return nil }
            return amount(locale: locale)?.value
        }

        private func amount(locale: Locale) -> PositiveQuantity? {
            FoodAmountFieldText.parse(text, locale: locale).flatMap { try? PositiveQuantity(value: $0, unit: unit) }
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
