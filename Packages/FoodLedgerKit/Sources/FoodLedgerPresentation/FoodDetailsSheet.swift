import FoodLedgerApplication
import FoodLedgerDomain
import SwiftUI

/// The typed answers in the Food details sheet opened from Confirm ("Add food details" or
/// "Correct food details"). Applying them is an explicit user action that records a correction
/// on Confirm; Log (or Save changes) is still the only save (#276, #285).
public struct FoodDetailsDraft: Equatable, Sendable {
    public enum Basis: Hashable, Sendable {
        case keepPopulated
        case per100Grams
        case per100Millilitres
    }

    public var name: String
    public var brand: String
    public var variant: String
    public var reason: String
    public var preparation: String
    public var preparationMethod: String
    public var bone: String
    public var skin: String
    public var drained: String
    public var packingMedium: String
    public var fortification: String
    public var itemClass: String
    public var basis: Basis

    /// The details Confirm currently shows: a correction, the reopened entry or the selected source.
    /// The reason is the user's own text and is carried over rather than reloaded.
    @MainActor
    public init(model: FoodConfirmationViewModel, reason: String = "") {
        let identity = model.displayedIdentity
        name = model.displayedName.value
        brand = model.displayedBrand?.value ?? ""
        variant = model.displayedVariant?.value ?? ""
        self.reason = reason
        preparation = identity.preparation.kind.rawValue
        preparationMethod = identity.preparation.method?.value ?? ""
        bone = identity.bone.rawValue
        skin = identity.skin.rawValue
        drained = identity.drained.rawValue
        if case let .named(value) = identity.packingMedium { packingMedium = value.value } else { packingMedium = "" }
        fortification = identity.fortification.rawValue
        itemClass = (model.state.correction?.itemClass ?? model.state.reopened?.productVersion.itemClass
                     ?? model.state.selectedCandidate.itemClass).rawValue
        basis = .keepPopulated
    }

    /// Apply stays disabled until a product name and a reason are present.
    public var canApply: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// The correction these answers describe for the selected source, or nil when an answer is
    /// invalid (for example a named preparation without its method). Nutrients are the source's.
    public func correction(for selected: PopulatedFoodCandidate) -> FoodCorrection? {
        guard let name = try? LedgerText(name),
              let reason = try? LedgerText(reason),
              let itemClass = ItemClass(rawValue: itemClass),
              let preparationKind = PreparationKind(rawValue: preparation),
              let bone = BoneState(rawValue: bone),
              let skin = SkinState(rawValue: skin),
              let drained = DrainedState(rawValue: drained),
              let fortification = FortificationState(rawValue: fortification) else { return nil }
        let method = preparationKind == .named ? try? Self.optionalText(preparationMethod) : nil
        guard let preparationState = try? PreparationState(kind: preparationKind, method: method) else { return nil }
        let packing: PackingMediumState
        if let value = try? Self.optionalText(packingMedium) { packing = .named(value) } else { packing = .unknown }
        let source = selected.candidate.identity
        let servingBasis: ResolutionBasis = switch basis {
        case .keepPopulated: source.servingBasis
        case .per100Grams: .per100Grams
        case .per100Millilitres: .per100Millilitres
        }
        guard let identity = try? DecisiveIdentity(
            preparation: preparationState, bone: bone, skin: skin, drained: drained, packingMedium: packing,
            fortification: fortification,
            declaredFortificants: fortification == .fortified ? source.declaredFortificants : [],
            servingBasis: servingBasis
        ) else { return nil }
        return FoodCorrection(name: name, brand: try? Self.optionalText(brand), variant: try? Self.optionalText(variant),
                              identity: identity, itemClass: itemClass, nutrients: selected.candidate.nutrients,
                              reason: reason)
    }

    /// One edit of the reason field (#285). The reason is a single note that wraps while typed, so
    /// Return finishes the field instead of adding a line: an edit that only inserts one line
    /// break keeps the previous text and reports `finishes`. Pasted line breaks become spaces.
    public static func reasonEdit(from old: String, to new: String) -> (text: String, finishes: Bool) {
        guard new.contains(where: \.isNewline) else { return (new, false) }
        if new.count == old.count + 1, new.filter({ !$0.isNewline }) == old, new.filter(\.isNewline).count == 1 {
            return (old, true)
        }
        let joined = new.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).joined(separator: " ")
        return (joined, false)
    }

    public static let invalidDetailsMessage =
        "These details could not be applied. Check the product name, the reason and, for a named preparation, its method."

    private static func optionalText(_ value: String) throws -> LedgerText? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : try LedgerText(trimmed)
    }
}

/// The Food details sheet's form. The host owns the draft and presentation; `applied` runs after
/// a correction was recorded on Confirm, so the host can close the sheet and announce it.
public struct FoodDetailsForm: View {
    @ObservedObject private var model: FoodConfirmationViewModel
    @Binding private var draft: FoodDetailsDraft
    private let applied: () -> Void
    @State private var failure: String?
    @FocusState private var reasonFocused: Bool
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    public init(model: FoodConfirmationViewModel, draft: Binding<FoodDetailsDraft>, applied: @escaping () -> Void) {
        self.model = model
        _draft = draft
        self.applied = applied
    }

    public static let reasonTitle = "Reason for correction"
    public static let applyTitle = "Apply correction as a new version"
    /// Accessibility text sizes put each picker's title above its full-width, wrapping value.
    public static func stacksTitles(at size: DynamicTypeSize) -> Bool { size.isAccessibilitySize }

    public static let basisOptions: [(FoodDetailsDraft.Basis, String)] = [
        (.keepPopulated, "Keep populated basis"), (.per100Grams, "Per 100 g"), (.per100Millilitres, "Per 100 mL")
    ]

    public var body: some View {
        Form {
            Section("Food details") {
                TextField("Product name", text: $draft.name)
                TextField("Brand (optional)", text: $draft.brand)
                TextField("Variant (optional)", text: $draft.variant)
                picker("Item class", $draft.itemClass,
                       [ItemClass.food, .fortifiedFood, .supplement, .drink, .water].map { ($0.rawValue, Self.label($0.rawValue)) })
                picker("Preparation", $draft.preparation,
                       [PreparationKind.asSold, .raw, .cooked, .reheated, .named, .unknown].map { ($0.rawValue, Self.label($0.rawValue)) })
                if draft.preparation == PreparationKind.named.rawValue {
                    TextField("Preparation method", text: $draft.preparationMethod)
                }
                picker("Bone", $draft.bone,
                       [BoneState.withBone, .boneless, .notApplicable, .unknown].map { ($0.rawValue, Self.label($0.rawValue)) })
                picker("Skin", $draft.skin,
                       [SkinState.skinOn, .skinless, .notApplicable, .unknown].map { ($0.rawValue, Self.label($0.rawValue)) })
                picker("Drained state", $draft.drained,
                       [DrainedState.drained, .undrained, .notApplicable, .unknown].map { ($0.rawValue, Self.label($0.rawValue)) })
                TextField("Packing medium", text: $draft.packingMedium)
                    .accessibilityHint("A blank packing medium remains unresolved")
                picker("Fortification", $draft.fortification,
                       [FortificationState.fortified, .unfortified, .unknown].map { ($0.rawValue, Self.label($0.rawValue)) })
                picker("Nutrition basis", $draft.basis, Self.basisOptions)
                reasonField
                Button(Self.applyTitle, action: apply)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .disabled(!draft.canApply)
                if let failure {
                    Label(failure, systemImage: "exclamationmark.triangle").font(.subheadline)
                }
                Text("Corrections keep your reason and the original source evidence.")
                    .font(.caption)
                Text("Enter only details you know. Missing catalogue facts remain unknown. Fortified identity must use the fortified-food item class.")
                    .font(.caption)
            }
        }
    }

    /// The reason keeps a visible label above the field, so neither truncates at the largest text
    /// sizes; the field wraps a long reason and Return (labelled Done) finishes it.
    private var reasonField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(Self.reasonTitle).accessibilityHidden(true)
            TextField(Self.reasonTitle, text: Binding(get: { draft.reason }, set: { new in
                let edit = FoodDetailsDraft.reasonEdit(from: draft.reason, to: new)
                draft.reason = edit.text
                if edit.finishes { reasonFocused = false }
            }), prompt: Text("Required"), axis: .vertical)
                .focused($reasonFocused)
                .submitLabel(.done)
                .frame(minHeight: 44)
                .accessibilityLabel(Self.reasonTitle)
        }
    }

    private func apply() {
        reasonFocused = false
        if model.applyFoodDetails(draft) {
            failure = nil
            applied()
        } else {
            failure = FoodDetailsDraft.invalidDetailsMessage
        }
    }

    /// A menu picker. At accessibility text sizes the title sits above a full-width value that
    /// wraps, since the standard row truncates long values such as "Keep populated basis" (#285).
    @ViewBuilder
    private func picker<Value: Hashable>(_ title: String, _ selection: Binding<Value>, _ options: [(Value, String)]) -> some View {
        let choices = Picker(title, selection: selection) {
            ForEach(options, id: \.0) { Text($0.1).tag($0.0) }
        }
        if Self.stacksTitles(at: dynamicTypeSize) {
            let current = options.first { $0.0 == selection.wrappedValue }?.1 ?? ""
            VStack(alignment: .leading, spacing: 6) {
                Text(title).accessibilityHidden(true)
                Menu {
                    choices.pickerStyle(.inline).labelsHidden()
                } label: {
                    HStack(alignment: .firstTextBaseline) {
                        Text(current).multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.up.chevron.down").accessibilityHidden(true)
                    }
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .accessibilityLabel(title)
                .accessibilityValue(current)
            }
        } else {
            choices
        }
    }

    private static func label(_ value: String) -> String {
        value.replacingOccurrences(of: "_", with: " ").capitalized
    }
}
