import FoodLedgerApplication
import FoodLedgerDomain
import SwiftUI

@MainActor
public final class FoodConfirmationViewModel: ObservableObject {
    @Published public private(set) var state: FoodConfirmationState
    private let saveAction: @MainActor (FoodConfirmationState) throws -> StoredFoodConfirmation

    public init(
        state: FoodConfirmationState,
        saveAction: @escaping @MainActor (FoodConfirmationState) throws -> StoredFoodConfirmation
    ) {
        self.state = state
        self.saveAction = saveAction
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
            send(.saved(saved.logItem.logItemID))
        } catch {
            send(.saveFailed(Self.message(for: error)))
        }
    }

    public static func message(for error: Error) -> String {
        switch error {
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
        case FoodConfirmationSaveError.unresolvedMandatoryIdentity:
            "Resolve every highlighted identity difference before saving."
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
    @State private var emptyPlateText = ""
    @State private var conversionText = ""
    @State private var conversionUnit = QuantityUnit.grams
    @State private var conversionMethod = ""

    public init(model: FoodConfirmationViewModel, leave: @escaping () -> Void) {
        self.model = model
        self.leave = leave
    }

    public var body: some View {
        Form {
            identitySection
            candidateSection
            differencesSection
            quantitySection
            nutritionSection
            correctionSection
            recoverySection
            actionSection
        }
        .navigationTitle("Confirm food")
        .animation(reduceMotion ? nil : .default, value: model.state.selectedCandidateIndex)
        .onAppear {
            correctionName = model.state.selectedCandidate.name.value
            correctionBrand = model.state.selectedCandidate.brand?.value ?? ""
            correctionVariant = model.state.selectedCandidate.variant?.value ?? ""
            loadIdentityCorrection(model.state.selectedCandidate)
            if let value = model.state.quantity.value { totalText = Self.editableNumber(value) }
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
            LabeledContent("Source release", value: model.state.selectedCandidate.candidate.sourceReleaseID.value)
            LabeledContent("Source record", value: model.state.selectedCandidate.candidate.recordID.value)
            LabeledContent("Evidence", value: "\(model.state.selectedCandidate.candidate.evidenceIDs.count) retained item(s)")
            let identity = model.state.selectedCandidate.candidate.identity
            LabeledContent("Preparation", value: Self.preparationLabel(identity.preparation))
            LabeledContent("Bone", value: Self.label(identity.bone.rawValue))
            LabeledContent("Skin", value: Self.label(identity.skin.rawValue))
            LabeledContent("Drained", value: Self.label(identity.drained.rawValue))
            LabeledContent("Packing medium", value: Self.packingLabel(identity.packingMedium))
            LabeledContent("Fortification", value: Self.label(identity.fortification.rawValue))
            LabeledContent("Nutrition basis", value: Self.basisLabel(identity.servingBasis))
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Populated product identity and source evidence")
    }

    private var candidateSection: some View {
        Section("Supplied matches") {
            Picker("Candidate", selection: candidateBinding) {
                ForEach(model.state.input.candidates.indices, id: \.self) { index in
                    Text(model.state.input.candidates[index].name.value).tag(index)
                }
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
        Section("Material match differences") {
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
        Section("Edible quantity") {
            TextField("Quantity", text: $totalText)
                .onChange(of: totalText) { _, value in
                    model.send(.setQuantity(Double(value), model.state.quantity.unit))
                }
                .accessibilityLabel("Food or total weight quantity")
            Picker("Unit", selection: quantityUnitBinding) {
                Text("g").tag(QuantityUnit.grams)
                Text("mL").tag(QuantityUnit.millilitres)
                Text("count").tag(QuantityUnit.count)
            }
            if let conversion = model.state.quantity.conversion {
                LabeledContent("Immutable conversion", value: conversion.methodVersion.value)
                    .accessibilityLabel("Conversion version \(conversion.methodVersion.value)")
            }
            if model.state.quantity.unit == .count {
                TextField("Converted edible amount", text: $conversionText)
                    .onChange(of: conversionText) { _, _ in updateConversion() }
                Picker("Converted unit", selection: $conversionUnit) {
                    Text("g").tag(QuantityUnit.grams)
                    Text("mL").tag(QuantityUnit.millilitres)
                }
                .onChange(of: conversionUnit) { _, _ in updateConversion() }
                TextField("Conversion method/version", text: $conversionMethod)
                    .onChange(of: conversionMethod) { _, _ in updateConversion() }
                    .accessibilityHint("Required provenance for a count or portion conversion")
                if model.state.quantity.conversion == nil {
                    Label("A count conversion and method version are required", systemImage: "exclamationmark.triangle")
                }
            }
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
        Section("Nutrition and provenance") {
            ForEach(model.state.selectedCandidate.candidate.nutrients.entries, id: \.key.rawValue) { entry in
                LabeledContent(Self.nutrientLabel(entry.key), value: Self.nutrientValue(entry))
                    .accessibilityLabel("\(Self.nutrientLabel(entry.key)), \(Self.nutrientValue(entry))")
            }
            Text("Unknown values remain unknown. Bounds remain intervals and are never shown as exact amounts.")
                .font(.caption)
        }
    }

    private var correctionSection: some View {
        Section("Correct populated result") {
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
            Text("Corrections add an assertion and immutable version; original evidence is retained.")
                .font(.caption)
            Text("Unknown decisive identity values cannot be saved. Fortified identity must use the fortified-food item class.")
                .font(.caption)
        }
    }

    @ViewBuilder
    private var recoverySection: some View {
        if case let .saveFailed(message) = model.state.phase {
            Section("Save needs attention") {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .accessibilityLabel("Save failed. \(message)")
                Button("Try saving again") { model.save() }
            }
        } else if case .saved = model.state.phase {
            Section {
                Label("Food saved", systemImage: "checkmark.circle.fill")
                    .accessibilityLabel("Food saved successfully")
            }
        }
    }

    private var actionSection: some View {
        Section {
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

    private var candidateBinding: Binding<Int> {
        Binding(get: { model.state.selectedCandidateIndex }, set: {
            model.send(.selectCandidate($0))
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
        let selected = model.state.selectedCandidate.candidate
        model.send(.setConversion(QuantityConversionDraft(
            convertedQuantity: quantity,
            methodVersion: method,
            sourceReleaseID: selected.sourceReleaseID,
            evidenceID: selected.evidenceIDs.first
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
        switch (model.state.decision, model.state.phase) {
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

    private static func basisLabel(_ value: ResolutionBasis) -> String {
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
        value.rawValue.replacingOccurrences(of: "_", with: " ").capitalized
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
