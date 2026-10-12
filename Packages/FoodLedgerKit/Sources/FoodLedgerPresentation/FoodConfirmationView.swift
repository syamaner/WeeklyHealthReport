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
        saveAction: @escaping @MainActor (FoodConfirmationState) throws -> StoredFoodConfirmation
    ) {
        self.state = state
        self.savesFavourite = savesFavourite && favouriteAction != nil && !Self.isPlainWaterSource(state)
        self.favouriteAction = favouriteAction
        self.now = now
        self.calendar = calendar
        self.volumeConversionOffering = volumeConversionOffering
        self.searchInterpretation = searchInterpretation
        self.saveAction = saveAction
    }

    public var availableVolumeConversion: QuantityConversionDraft? {
        guard state.correction == nil, state.quantity.directWeight == nil,
              state.quantity.conversion == nil,
              let value = state.quantity.value,
              let original = try? PositiveQuantity(value: value, unit: state.quantity.unit),
              let offering = volumeConversionOffering else { return nil }
        return try? offering.offer(for: state.selectedCandidate, original: original)
    }

    public func applyAvailableVolumeConversion() {
        guard let conversion = availableVolumeConversion,
              state.input.sourceReleases.contains(where: { $0.sourceReleaseID == conversion.sourceReleaseID }) else { return }
        send(.setConversion(conversion))
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

    private var usesOfferedVolumeEstimate: Bool {
        guard let sourceID = state.quantity.conversion?.sourceReleaseID,
              let offering = volumeConversionOffering else { return false }
        return sourceID == offering.sourceRelease.sourceReleaseID
    }

    public var quantityBasisWarning: String? {
        let basis = (state.correction?.identity ?? state.selectedCandidate.candidate.identity).servingBasis
        let unit = (try? state.quantity.calculationInput().unit) ?? state.quantity.unit
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
            return "This source is per 100 g. Choose a source per 100 mL or enter a measured gram amount; no density is inferred. Nutrient totals are unavailable for this unit."
        }
        if basis == .per100Millilitres && unit == .grams {
            return "This source is per 100 mL. Choose a source per 100 g or enter a measured volume; no density is inferred. Nutrient totals are unavailable for this unit."
        }
        return nil
    }

    public static func nutrientLabel(_ value: NutrientKey) -> String {
        value == .energyConsumed ? "Energy" : value.rawValue.replacingOccurrences(of: "_", with: " ").capitalized
    }

    public var nutritionReferenceTitle: String {
        "Reference nutrition — \(FoodConfirmationView.basisLabel(state.selectedCandidate.candidate.identity.servingBasis))"
    }

    public var consumedNutritionBasisLabel: String {
        let basis = (state.correction?.identity ?? state.selectedCandidate.candidate.identity).servingBasis
        let prefix = state.correction == nil ? "Calculation basis" : "User-corrected calculation basis"
        return "\(prefix): \(FoodConfirmationView.basisLabel(basis))"
    }

    public var consumedNutrition: [FoodIntakeTotal] {
        guard let quantity = try? state.calculatedEdibleQuantity() else { return [] }
        return FoodIntakeSummary(contributions: [FoodIntakeContribution(
            quantity: quantity,
            basis: (state.correction?.identity ?? state.selectedCandidate.candidate.identity).servingBasis,
            nutrients: state.correction?.nutrients ?? state.selectedCandidate.candidate.nutrients,
            quantityIsEstimate: state.quantity.directWeight?.basis == .estimated || usesOfferedVolumeEstimate
        )]).totals
    }

    public var nutritionReview: FoodNutritionReviewPresentation {
        FoodNutritionReviewPresentation(nutrients: state.correction?.nutrients ?? state.selectedCandidate.candidate.nutrients,
            sourceBasis: (state.correction?.identity ?? state.selectedCandidate.candidate.identity).servingBasis,
            edibleQuantity: try? state.calculatedEdibleQuantity(), totals: consumedNutrition)
    }

    public var originalAmountRequirement: String? {
        if state.quantity.directWeight != nil, state.quantity.value == nil, state.quantity.invalidOriginalAmountText != true { return nil }
        guard let value = state.quantity.value, value.isFinite, value > 0 else {
            return state.quantity.directWeight == nil
                ? "Enter a finite amount greater than zero, or use ‘Enter measured weight’ for a separate edible gram total."
                : "Correct the original amount to a finite value greater than zero, or clear this optional field. Your gram total is retained."
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
        if savesFavourite && offersFavourite { return "Log and save favourite" }
        guard nutritionReview.isConsumed,
              let energy = consumedNutrition.first(where: { $0.key == .energyConsumed }),
              energy.incompleteContributions == 0, let amount = energy.knownAmount else { return "Log" }
        return "Log \(FoodNutritionReviewPresentation.number(amount)) kcal"
    }

    public var occurredAtRange: ClosedRange<Date> {
        let current = now()
        return FoodLogPolicy.windowStart(now: current, calendar: calendar)...current
    }

    /// The displayed time: the chosen instant, or now when "Now" is still selected.
    public var displayedOccurredAt: Date { state.occurredAt ?? now() }

    public var occursNow: Bool { state.occurredAt == nil }

    /// A reopened entry older than the backdating window keeps its stored time: the picker is
    /// replaced by a read-only value, so no clamped or refused time can be written back.
    public var canChangeOccurredAt: Bool {
        guard let stored = state.reopened?.logItemVersion.occurredAt else { return true }
        return stored >= FoodLogPolicy.windowStart(now: now(), calendar: calendar)
    }

    /// One Log press: the explicit acceptance of the displayed food, amount, time and source.
    public func log() {
        guard canLog else { return }
        send(.accept)
        save()
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
            case .invalidTotal: return "Enter a finite total edible gram weight greater than zero."
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
            "Enter a finite quantity greater than zero."
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
    private let context: String?
    private let completionTitle: String
    private let showsCancelButton: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.locale) private var locale
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

    public init(
        model: FoodConfirmationViewModel, context: String? = nil,
        completionTitle: String = "Done", showsCancelButton: Bool = true, leave: @escaping () -> Void
    ) {
        self.model = model
        self.showsCancelButton = showsCancelButton
        self.context = context
        self.completionTitle = completionTitle
        self.leave = leave
        _totalText = State(initialValue: model.state.quantity.value.map { Self.editableNumber($0, locale: .autoupdatingCurrent) } ?? "")
    }

    /// The weighing method's title, shared by the picker and the saved, read-only plate row (#212).
    public static func weighingMethodTitle(usesPlate: Bool) -> String {
        usesPlate ? "Total minus empty plate" : "Food only / tared"
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
            if !model.occursNow && model.state.reopened == nil {
                Button("Use now") { model.send(.setOccurredAt(nil)) }
                    .frame(minHeight: 44)
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
                Button {
                    model.log()
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
            LabeledContent("Evidence", value: "\(model.state.selectedCandidate.candidate.evidenceIDs.count) retained item(s)")
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
                Button("Use \(FoodNutritionReviewPresentation.number(suggestion.value)) count from description") {
                    model.send(.setQuantity(suggestion.value, .count))
                    totalText = editableNumber(suggestion.value)
                }
                Text("Count only. Edible weight still needs confirmation.").font(.caption)
            }
            Button("Enter measured weight") { model.send(.beginDirectWeight); directWeightText = "" }
                .disabled(model.state.quantity.directWeight != nil || model.state.usesSourceDeclaredServing)
            if model.state.quantity.directWeight != nil {
                Text("Weigh edible food as eaten—peeled, boiled or fried. Exclude peel, shell, bone and anything you did not eat.").font(.caption)
                TextField(usesPlate ? "Total food and plate weight (g)" : "Total edible weight (g)", text: $directWeightText)
                    .amountKeyboard()
                    .onChange(of: directWeightText) { _, value in model.send(.setDirectWeight(FoodAmountFieldText.parse(value, locale: locale))) }
                    .accessibilityLabel("Total edible weight in grams")
                if usesPlate { Text("Enter the food and plate total here. The empty plate weight below is subtracted to obtain edible grams.").font(.caption) }
                Picker("Weight basis", selection: Binding<UserWeightBasis?>(
                    get: { model.state.quantity.directWeight?.basis },
                    set: { model.send(.setWeightBasis($0)) })) {
                    Text("Choose measured or estimated").tag(UserWeightBasis?.none)
                    Text("User-reported measured weight").tag(UserWeightBasis?.some(.measured))
                    Text("User-entered estimate").tag(UserWeightBasis?.some(.estimated))
                }
                ForEach(model.directWeightRequirements, id: \.self) { Text($0).font(.caption) }
                if model.state.quantity.directWeight?.needsReconfirmation == true {
                    Button("Keep this weight") { model.send(.confirmRetainedWeight) }.frame(minHeight: 44)
                }
                Text("Original amount below is retained separately; changing a count does not replace your gram total.").font(.caption)
                Button("Use original amount instead") { model.send(.endDirectWeight) }
            }
            TextField(model.state.isSourceRecipe ? "Recipe servings eaten" : model.state.usesSourceDeclaredServing ? "Source servings eaten" : model.state.quantity.directWeight == nil ? "Quantity" : "Original amount (optional)", text: $totalText)
                .amountKeyboard()
                .onChange(of: totalText) { _, value in
                    model.send(.setQuantityText(FoodAmountFieldText.canonical(value, locale: locale)))
                }
                .accessibilityLabel("Food or total weight quantity")
            Picker("Unit", selection: quantityUnitBinding) {
                Text("g").tag(QuantityUnit.grams)
                Text("mL").tag(QuantityUnit.millilitres)
                Text(model.state.isSourceRecipe ? "recipe servings" : model.state.usesSourceDeclaredServing ? "source servings" : "count").tag(QuantityUnit.count)
            }
            if let requirement = model.originalAmountRequirement { Text(requirement).font(.caption) }
            whenRow
            if let warning = model.quantityBasisWarning {
                Label(warning, systemImage: "exclamationmark.triangle").font(.caption)
            }
            if let offer = model.availableVolumeConversion {
                Button("Use sourced whole-milk volume estimate") { model.applyAvailableVolumeConversion() }
                Text("\(model.state.quantity.value?.formatted() ?? "") mL gives about \(offer.convertedQuantity.value.formatted()) g. This estimate applies only to the selected UK CoFID whole pasteurised milk record. Check the food before using it; measured edible grams remain an alternative.")
                    .font(.caption)
            }
            if let conversion = model.state.quantity.conversion {
                LabeledContent("Weight or volume method", value: conversion.methodVersion.value)
                    .accessibilityLabel("Conversion version \(conversion.methodVersion.value)")
                if let url = model.volumeConversionSourceURL,
                   let sourceID = conversion.sourceReleaseID,
                   let source = model.state.input.sourceReleases.first(where: { $0.sourceReleaseID == sourceID }) {
                    DisclosureGroup("Volume estimate source") {
                        Text(source.attribution.value).font(.caption).textSelection(.enabled)
                        Text(source.licence.value).font(.caption2).textSelection(.enabled)
                        Link("Open conversion source", destination: url)
                    }
                }
                if model.volumeConversionSourceURL != nil {
                    Button("Remove volume estimate") { model.removeOfferedVolumeConversion() }
                }
            }
            if model.state.quantity.unit == .count && model.state.quantity.directWeight == nil && !model.state.usesSourceDeclaredServing {
                Text("No source-backed size guide is available for this food. Enter the total edible weight, excluding shell, bone or other parts you did not eat.").font(.caption)
                TextField("Converted edible amount", text: $conversionText)
                    .amountKeyboard()
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
                LabeledContent("Weighed on a plate", value: Self.weighingMethodTitle(usesPlate: usesPlate))
                    .foregroundStyle(.secondary)
            } else {
                DisclosureGroup("Weighed on a plate") {
                    Picker("Weighing method", selection: plateModeBinding) {
                        Text(Self.weighingMethodTitle(usesPlate: false)).tag(false)
                        Text(Self.weighingMethodTitle(usesPlate: true)).tag(true)
                    }
                    if usesPlate {
                        TextField("Empty plate weight (g)", text: $emptyPlateText)
                            .amountKeyboard()
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
        Binding(get: { model.state.quantity.unit }, set: {
            model.send(.setQuantity(FoodAmountFieldText.parse(totalText, locale: locale), $0))
            model.send(.setQuantityText(FoodAmountFieldText.canonical(totalText, locale: locale)))
            if $0 == .count { updateConversion() }
        })
    }

    private func updateConversion() {
        guard model.state.quantity.unit == .count,
              let value = FoodAmountFieldText.parse(conversionText, locale: locale),
              let quantity = try? PositiveQuantity(value: value, unit: conversionUnit),
              let method = try? LedgerText(conversionMethod) else {
            model.send(.setConversion(nil))
            return
        }
        model.send(.setConversion(QuantityConversionDraft(
            convertedQuantity: quantity,
            methodVersion: method,
            sourceReleaseID: nil,
            evidenceID: nil
        )))
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

    private static func number(_ value: Double) -> String { value.formatted(.number.precision(.fractionLength(0...3))) }

    private static func editableNumber(_ value: Double, locale: Locale) -> String { FoodAmountFieldText.text(value, locale: locale) }
    private func editableNumber(_ value: Double) -> String { Self.editableNumber(value, locale: locale) }
}
