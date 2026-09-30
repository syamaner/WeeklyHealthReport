import FoodLedgerApplication
import FoodLedgerDomain
import SwiftUI

@MainActor
public final class FoodConfirmationViewModel: ObservableObject {
    @Published public private(set) var state: FoodConfirmationState
    @Published public private(set) var savedResult: StoredFoodConfirmation?
    private let saveAction: @MainActor (FoodConfirmationState) throws -> StoredFoodConfirmation
    private let volumeConversionOffering: (any FoodVolumeConversionOffering)?

    public init(
        state: FoodConfirmationState,
        volumeConversionOffering: (any FoodVolumeConversionOffering)? = nil,
        saveAction: @escaping @MainActor (FoodConfirmationState) throws -> StoredFoodConfirmation
    ) {
        self.state = state
        self.volumeConversionOffering = volumeConversionOffering
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

    public var needsAcceptance: Bool {
        switch state.decision {
        case .undecided, .declined: true
        case .accepted, .acceptedClosestMatch: false
        }
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

    public var directWeightRequirements: [String] {
        guard let direct = state.quantity.directWeight else { return [] }
        var result: [String] = []
        if direct.totalGrams.map({ !$0.isFinite || $0 <= 0 }) ?? true {
            result.append("Enter the total edible weight in grams, greater than zero. Weigh only the food you ate.")
        }
        if direct.basis == nil { result.append("Choose ‘User-reported measured weight’ or ‘User-entered estimate’. Typed grams alone do not declare a measurement.") }
        if direct.needsReconfirmation { result.append("The selected food or preparation changed. Check that this total still describes it, then use ‘Accept this match’ to reconfirm.") }
        return result
    }

    public var plateRequirements: [String] {
        guard state.quantity.plateChoice != .foodOnly else { return [] }
        if case .missing = state.quantity.plateChoice { return ["Enter the empty plate weight, or choose ‘Food only / tared’."] }
        guard let entered = try? state.quantity.calculationInput() else { return [] }
        guard entered.unit == .grams else { return ["Plate subtraction needs a total weight in grams. Enter measured weight or choose ‘Food only / tared’."] }
        let emptyWeight: Double
        switch state.quantity.plateChoice {
        case let .saved(plate): emptyWeight = plate.emptyWeight.value
        case let .new(weight, _): emptyWeight = weight.value
        default: return []
        }
        return entered.value <= emptyWeight ? ["The total weight must be greater than the empty plate weight. Correct either weight, or choose ‘Food only / tared’."] : []
    }

    /// Guidance uses the same unresolved-identity rule as the save service.
    public var saveRequirements: [String] {
        var result: [String] = []
        switch state.decision {
        case .undecided, .declined:
            result.append("Confirm that this is the food you want using ‘Accept this match’.")
        case .accepted:
            if state.reopened == nil && state.correction == nil && !state.materialDifferences.isEmpty {
                result.append("Explain why the closest match is acceptable, or correct the food details before saving.")
            }
        case .acceptedClosestMatch: break
        }
        let missing = state.unresolvedIdentity
        if !missing.isEmpty {
            result.append("Food details still needed: \(Self.detailNames(missing)). Open ‘Review or correct food details’, enter only what you know, and apply the correction. You can also choose another match.")
        }
        if state.quantity.directWeight == nil || state.quantity.value != nil || state.quantity.invalidOriginalAmountText == true {
            if let amount = state.quantity.value, amount.isFinite, amount > 0 {} else {
                result.append("Enter an amount greater than zero in ‘Amount eaten’.")
            }
        }
        if state.isSourceRecipe && (state.quantity.unit != .count || state.quantity.directWeight != nil || state.quantity.conversion != nil || state.quantity.plateChoice != .foodOnly) {
            result.append("Enter the number of source recipe servings eaten. A weighed portion cannot be converted because cooked serving weight is unknown.")
        }
        result += directWeightRequirements
        if state.quantity.directWeight == nil && state.quantity.unit == .count && state.quantity.conversion == nil && !state.isSourceRecipe {
            result.append("For a count, enter the measured total edible weight or volume and how it was measured, or change the amount to g or mL.")
        }
        result += plateRequirements
        return result
    }

    private static func detailNames(_ details: [IdentityContradiction]) -> String {
        details.map { detail in
            switch detail {
            case .preparation: "raw/cooked preparation"
            case .bone: "bone"
            case .skin: "skin"
            case .drained: "drained state"
            case .packingMedium: "packing liquid or none"
            case .fortification: "fortification"
            case .servingBasis: "nutrition basis"
            case .edibleQuantity: "edible amount"
            }
        }.joined(separator: ", ")
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
        }
    }

    public static func message(for error: Error) -> String {
        if let error = error as? DirectWeightError {
            switch error {
            case .missingBasis: return "Choose measured weight or user-entered estimate beside the gram total."
            case .invalidTotal: return "Enter a finite total edible gram weight greater than zero."
            case .needsReconfirmation: return "Recheck the total for the selected preparation and accept this match again."
            }
        }
        return switch error {
        case FoodConfirmationSaveError.noAcceptedCandidate:
            "Choose or accept a populated match before saving."
        case FoodConfirmationSaveError.invalidQuantity:
            "Enter a finite quantity greater than zero."
        case FoodQuantityValidationError.missingConversion:
            "This unit needs the displayed conversion before it can be saved."
        case FoodQuantityValidationError.missingPlateWeight:
            "Enter or choose an empty plate weight."
        case FoodQuantityValidationError.invalidPlateUnit:
            "Plate subtraction is available for gram weights only."
        case FoodQuantityValidationError.nonPositiveEdibleQuantity:
            "The total must be greater than the empty plate weight."
        case let FoodConfirmationSaveError.unresolvedMandatoryIdentity(details):
            "Food details still needed: \(detailNames(details)). Open ‘Review or correct food details’ or choose another match."
        case FoodConfirmationSaveError.unexplainedMaterialDifferences:
            "Explain the highlighted differences or apply a correction before saving."
        default:
            "The food was not saved. Your confirmation is still here; review it and try again."
        }
    }
}

public struct FoodConfirmationView: View {
    @ObservedObject private var model: FoodConfirmationViewModel
    private let leave: () -> Void
    private let context: String?
    private let completionTitle: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var closestExplanation = ""
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
        completionTitle: String = "Done", leave: @escaping () -> Void
    ) {
        self.model = model
        self.context = context
        self.completionTitle = completionTitle
        self.leave = leave
        _totalText = State(initialValue: model.state.quantity.value.map(Self.editableNumber) ?? "")
    }

    public var body: some View {
        Form {
            if let context { Section("From your list") { Text(context) } }
            if model.state.input.sourceReleases.contains(where: { $0.sourceID.value == "open-food-facts" }) {
                Section("Open Food Facts source") {
                    Text("Community product data. Check the package; this is a source estimate.").font(.caption)
                    ForEach(model.state.input.sourceReleases.filter { $0.sourceID.value == "open-food-facts" }, id: \.sourceReleaseID) { source in
                        Text(source.attribution.value).font(.caption).textSelection(.enabled)
                        Text(source.licence.value).font(.caption2).textSelection(.enabled)
                    }
                    Link("Open Food Facts data licence", destination: URL(string: "https://openfoodfacts.github.io/openfoodfacts-server/api/tutorials/license-be-on-the-legal-side/")!)
                }
            }
            Group {
                identitySection
                candidateSection
                differencesSection
                quantitySection
            }
            .disabled(model.savedResult != nil)
            recoverySection
            actionSection
            Section {
                DisclosureGroup("Nutrition and source details") {
                    nutritionSection
                    sourceDetails
                }
                DisclosureGroup("Review or correct food details") { correctionSection }
                    .disabled(model.savedResult != nil)
            }
        }
        .navigationTitle("Confirm food")
        .animation(reduceMotion ? nil : .default, value: model.state.selectedCandidateIndex)
        .onAppear {
            correctionName = model.state.selectedCandidate.name.value
            correctionBrand = model.state.selectedCandidate.brand?.value ?? ""
            correctionVariant = model.state.selectedCandidate.variant?.value ?? ""
            loadIdentityCorrection(model.state.selectedCandidate)
            if let value = model.state.quantity.value { totalText = Self.editableNumber(value) }
            directWeightText = model.state.quantity.directWeight?.totalGrams.map(Self.editableNumber) ?? ""
            if let conversion = model.state.quantity.conversion {
                conversionText = Self.editableNumber(conversion.convertedQuantity.value)
                conversionUnit = conversion.convertedQuantity.unit
                conversionMethod = conversion.methodVersion.value
            }
        }
    }

    private var identitySection: some View {
        Section("Product") {
            Text(model.state.selectedCandidate.name.value).font(.headline)
            if let brand = model.state.selectedCandidate.brand {
                LabeledContent("Brand", value: brand.value)
            }
            if let variant = model.state.selectedCandidate.variant {
                LabeledContent("Variant", value: variant.value)
            }
            let identity = model.state.selectedCandidate.candidate.identity
            LabeledContent("Preparation", value: Self.preparationLabel(identity.preparation))
            LabeledContent("Nutrition basis", value: Self.basisLabel(identity.servingBasis))
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Populated product identity and source evidence")
    }

    private var sourceDetails: some View {
        Group {
            let identity = model.state.selectedCandidate.candidate.identity
            LabeledContent("Bone", value: Self.label(identity.bone.rawValue))
            LabeledContent("Skin", value: Self.label(identity.skin.rawValue))
            LabeledContent("Drained", value: Self.label(identity.drained.rawValue))
            LabeledContent("Packing medium", value: Self.packingLabel(identity.packingMedium))
            LabeledContent("Fortification", value: Self.label(identity.fortification.rawValue))
            LabeledContent("Source release", value: model.state.selectedCandidate.candidate.sourceReleaseID.value)
            LabeledContent("Source record", value: model.state.selectedCandidate.candidate.recordID.value)
            LabeledContent("Evidence", value: "\(model.state.selectedCandidate.candidate.evidenceIDs.count) retained item(s)")
        }
    }

    private var candidateSection: some View {
        Section("Supplied matches") {
            Picker("Candidate", selection: candidateBinding) {
                ForEach(model.state.input.candidates.indices, id: \.self) { index in
                    Text(model.state.input.candidates[index].name.value).tag(index)
                }
            }
            if model.state.isSourceRecipe {
                Text("Representative recipe estimate. Review the source ingredients and explain why this recipe is acceptable for your meal. A recipe serving is not a measured gram amount.").font(.caption)
                if let metadata = model.state.selectedCandidate.candidate.matchMetadata {
                    ForEach(metadata.materialDifferences, id: \.value) { Text($0.value).font(.caption) }
                }
            } else if model.state.isGenericEstimate {
                Text("Generic composition estimate. Missing source details remain unknown; accepting does not verify them.").font(.caption)
            }
            if model.state.quantity.directWeight?.needsReconfirmation == true {
                Text("Check the retained edible total for this food and preparation before accepting again.").font(.caption)
            }
            if model.needsAcceptance {
                Text("Use ‘Accept this match’ after reviewing the food and preparation.").font(.caption)
            }
            Button("Accept this match") { model.send(.accept) }
                .disabled(!model.state.materialDifferences.isEmpty)
            if !model.state.materialDifferences.isEmpty {
                TextField("Why this closest match is acceptable", text: $closestExplanation, axis: .vertical)
                    .accessibilityHint("Required to version an explained closest-match decision")
                Button("Accept explained closest match") {
                    guard let explanation = try? LedgerText(closestExplanation) else { return }
                    model.send(.acceptClosestMatch(explanation))
                }
                .disabled(closestExplanation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            Button("None of these — leave without saving", role: .cancel) {
                model.send(.decline)
                leave()
            }
        }
    }

    private var differencesSection: some View {
        Section("Details to review") {
            if model.state.materialDifferences.isEmpty {
                Label("No material differences", systemImage: "checkmark.circle")
            } else {
                ForEach(model.state.materialDifferences, id: \.rawValue) { difference in
                    Label(Self.label(difference), systemImage: "exclamationmark.triangle")
                        .accessibilityLabel("Material difference: \(Self.label(difference))")
                }
                Text("These differences stay visible and any closest-match decision is stored as a versioned user assertion.")
                    .font(.caption)
            }
        }
    }

    private var quantitySection: some View {
        Section("Amount eaten") {
            if model.state.isSourceRecipe {
                Text("Representative recipe: enter how many servings of this source recipe you ate, for example 0.5. Check the source recipe yield in the reference details; a vendor’s plate may differ. Cooked serving weight is unknown.").font(.caption)
            }
            Button("Enter measured weight") { model.send(.beginDirectWeight); directWeightText = "" }
                .disabled(model.state.quantity.directWeight != nil || model.state.isSourceRecipe)
            if model.state.quantity.directWeight != nil {
                Text("Enter the total edible grams for the selected preparation, as eaten: for example, an egg after peeling and boiling or frying. Exclude shell, peel, bone and other uneaten parts. Added or absorbed oil is not inferred.").font(.caption)
                TextField(usesPlate ? "Total food and plate weight (g)" : "Total edible weight (g)", text: $directWeightText)
                    .onChange(of: directWeightText) { _, value in model.send(.setDirectWeight(Double(value))) }
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
                Text("Original amount below is retained separately; changing a count does not replace your gram total.").font(.caption)
                Button("Use original amount instead") { model.send(.endDirectWeight) }
            }
            TextField(model.state.isSourceRecipe ? "Recipe servings eaten" : model.state.quantity.directWeight == nil ? "Quantity" : "Original amount (optional)", text: $totalText)
                .onChange(of: totalText) { _, value in
                    model.send(.setQuantityText(value))
                }
                .accessibilityLabel("Food or total weight quantity")
            Picker("Unit", selection: quantityUnitBinding) {
                Text("g").tag(QuantityUnit.grams)
                Text("mL").tag(QuantityUnit.millilitres)
                Text(model.state.isSourceRecipe ? "recipe servings" : "count").tag(QuantityUnit.count)
            }
            if let requirement = model.originalAmountRequirement { Text(requirement).font(.caption) }
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
            if model.state.quantity.unit == .count && model.state.quantity.directWeight == nil && !model.state.isSourceRecipe {
                Text("No source-backed size guide is available for this food. Enter the total edible weight, excluding shell, bone or other parts you did not eat.").font(.caption)
                TextField("Converted edible amount", text: $conversionText)
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
            Picker("Weighing method", selection: plateModeBinding) {
                Text("Food only / tared").tag(false)
                Text("Total minus empty plate").tag(true)
            }
            if usesPlate {
                TextField("Empty plate weight (g)", text: $emptyPlateText)
                    .onChange(of: emptyPlateText) { _, value in
                        guard let amount = Double(value),
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
            Section("Save needs attention") {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .accessibilityLabel("Save failed. \(message)")
                Button("Try saving again") { model.save() }.disabled(!canSave)
            }
        } else if case .saved = model.state.phase {
            Section {
                Label("Food saved", systemImage: "checkmark.circle.fill")
                    .accessibilityLabel("Food saved successfully")
                if let saved = model.savedResult {
                    LabeledContent("Saved food", value: saved.productVersion.name.value)
                    LabeledContent("Saved amount", value: "\(Self.editableNumber(saved.logItemVersion.edibleQuantity.value)) \(saved.logItemVersion.edibleQuantity.unit.rawValue)")
                }
            }
        }
    }

    private var actionSection: some View {
        Section {
            if case .saved = model.state.phase {
                Button(completionTitle, action: leave)
            } else {
                ForEach(model.saveRequirements, id: \.self) { requirement in
                    Text(requirement).font(.caption)
                }
                Button {
                    model.save()
                } label: {
                    Label("Save food", systemImage: "checkmark.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canSave)
                Button("Leave without saving", role: .cancel, action: leave)
            }
        }
    }

    private var candidateBinding: Binding<Int> {
        Binding(get: { model.state.selectedCandidateIndex }, set: {
            model.send(.selectCandidate($0))
            totalText = model.state.quantity.value.map(Self.editableNumber) ?? ""
            directWeightText = model.state.quantity.directWeight?.totalGrams.map(Self.editableNumber) ?? ""
            conversionText = model.state.quantity.conversion.map { Self.editableNumber($0.convertedQuantity.value) } ?? ""
            let selected = model.state.selectedCandidate
            correctionName = selected.name.value
            correctionBrand = selected.brand?.value ?? ""
            correctionVariant = selected.variant?.value ?? ""
            loadIdentityCorrection(selected)
        })
    }

    private var quantityUnitBinding: Binding<QuantityUnit> {
        Binding(get: { model.state.quantity.unit }, set: {
            model.send(.setQuantity(Double(totalText), $0))
            model.send(.setQuantityText(totalText))
            if $0 == .count { updateConversion() }
        })
    }

    private func updateConversion() {
        guard model.state.quantity.unit == .count,
              let value = Double(conversionText),
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
                    emptyPlateText = Self.editableNumber(saved.emptyWeight.value)
                } else {
                    model.send(.setPlateChoice(.missing))
                    emptyPlateText = ""
                }
            } else {
                model.send(.setPlateChoice(.foodOnly))
            }
        })
    }

    private var canSave: Bool {
        guard model.saveRequirements.isEmpty else { return false }
        return switch (model.state.decision, model.state.phase) {
        case (.accepted, .editing), (.acceptedClosestMatch, .editing),
             (.accepted, .saveFailed), (.acceptedClosestMatch, .saveFailed):
            true
        default:
            false
        }
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
        let identity = selected.candidate.identity
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
        correctionItemClass = selected.itemClass.rawValue
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

    private static func editableNumber(_ value: Double) -> String { String(value) }
}
