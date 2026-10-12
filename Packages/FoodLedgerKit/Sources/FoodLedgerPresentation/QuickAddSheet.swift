import FoodLedgerApplication
import FoodLedgerDomain
import SwiftUI

/// Plain text for quick-add items: Home chips, Favourites rows and the sheet title.
public enum QuickAddText {
    public static let waterSourceLine = "Plain water. Counts towards water intake and adds no energy."
    public static let foodSourceLine = "Same source as your saved entry. Nothing is logged until you choose Log."
    public static let waterBoundText = "Enter an amount above 0 and up to 5,000 mL."
    public static let unverifiable = "Source can no longer be verified"
    public static let favouriteNotSaved = "Logged. Favourite not saved"

    public static func amount(_ value: Double, unit: QuantityUnit, locale: Locale = .current) -> String {
        let number = value.formatted(.number.precision(.fractionLength(0...2)).locale(locale))
        switch unit {
        case .grams: return "\(number) g"
        case .millilitres: return "\(number) mL"
        case .count: return value == 1 ? "1 piece" : "\(number) pieces"
        }
    }

    public static func title(_ item: QuickAddItem) -> String {
        switch item {
        case .builtInWater: PlainWaterReference.name
        case let .favourite(version): version.label.value
        }
    }

    public static func defaultAmount(_ item: QuickAddItem) -> String {
        switch item {
        case .builtInWater: amount(QuickAddItem.builtInWaterMillilitres, unit: .millilitres)
        case let .favourite(version): amount(version.defaultAmount.value, unit: version.defaultAmount.unit)
        }
    }

    /// "Water 250 mL".
    public static func chip(_ item: QuickAddItem) -> String { "\(title(item)) \(defaultAmount(item))" }

    public static func isPlainWater(_ item: QuickAddItem) -> Bool {
        switch item {
        case .builtInWater: true
        case let .favourite(version): version.binding == .reference(.plainWaterV1)
        }
    }

    /// "250 mL · plain water", "150 g · Estimate", "150 g".
    public static func detail(_ item: QuickAddItem, isEstimate: Bool?, locale: Locale = .current) -> String {
        if isPlainWater(item) { return "\(defaultAmount(item)) · plain water" }
        guard let isEstimate else { return "\(defaultAmount(item)) · \(unverifiable)" }
        return isEstimate ? "\(defaultAmount(item)) · Estimate" : defaultAmount(item)
    }
}

/// Home's quick-add chips (the first four items). A tap only opens the sheet or Confirm.
public struct QuickAddChipRow: View {
    private let items: [QuickAddItem]
    private let open: (QuickAddItem) -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    public init(items: [QuickAddItem], open: @escaping (QuickAddItem) -> Void) {
        self.items = items; self.open = open
    }

    public var body: some View {
        let columns = dynamicTypeSize.isAccessibilitySize ? [GridItem(.flexible())] : [GridItem(.flexible()), GridItem(.flexible())]
        LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                Button { open(item) } label: {
                    HStack(spacing: 6) {
                        Image(systemName: QuickAddText.isPlainWater(item) ? "drop" : "star").accessibilityHidden(true)
                        Text(QuickAddText.chip(item)).lineLimit(2).multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .padding(.horizontal, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Quick add \(QuickAddText.chip(item))")
                .accessibilityHint("Opens quick add. Nothing is logged until you choose Log.")
            }
        }
    }
}

/// The one-step quick-add sheet's orchestration. Opening it writes nothing; one Log press saves
/// once through the confirmation v5 path. The sheet renders `QuickAddPolicy` output only.
@MainActor
public final class QuickAddSheetModel: ObservableObject, Identifiable {
    public enum Phase: Equatable { case ready, saving, saved, failed(String) }

    public nonisolated let id = UUID()
    public let preparation: QuickAddPreparation
    @Published public private(set) var state: FoodConfirmationState
    @Published public private(set) var phase: Phase = .ready
    /// The selected preset, or nil when "Other amount" is in use.
    @Published public private(set) var selectedPreset: Double?
    @Published public private(set) var customText = ""
    @Published public private(set) var savedResult: StoredFoodConfirmation?
    private let now: @Sendable () -> Date
    public let calendar: Calendar
    private let logAction: @MainActor (FoodConfirmationState) throws -> StoredFoodConfirmation

    public init(preparation: QuickAddPreparation, now: @escaping @Sendable () -> Date = { Date() },
                calendar: Calendar = .autoupdatingCurrent,
                log: @escaping @MainActor (FoodConfirmationState) throws -> StoredFoodConfirmation) {
        self.preparation = preparation
        state = preparation.state
        selectedPreset = preparation.state.quantity.value
        self.now = now; self.calendar = calendar; logAction = log
    }

    public var title: String { "Quick add \(preparation.label)" }
    public var unit: QuantityUnit { preparation.defaultAmount.unit }

    /// Water: 150, 250, 330 and 500 mL. A food favourite: its default amount (Q5).
    public var presets: [Double] {
        preparation.isPlainWater ? QuickAddPolicy.waterPresetsMillilitres : [preparation.defaultAmount.value]
    }

    public var sourceLine: String { preparation.isPlainWater ? QuickAddText.waterSourceLine : QuickAddText.foodSourceLine }

    public var requirements: [FoodLogRequirement] {
        QuickAddPolicy.sheetRequirements(state, isPlainWater: preparation.isPlainWater, now: now(), calendar: calendar)
    }

    public var blockedReason: String? {
        guard let first = requirements.first else { return nil }
        if preparation.isPlainWater, first == .amountTextInvalid || first == .amountMissing { return QuickAddText.waterBoundText }
        return FoodLogRequirementText.text(first)
    }

    public var canLog: Bool { requirements.isEmpty && (phase == .ready || phase.isFailure) }

    /// "Log 250 mL".
    public var logTitle: String {
        guard let value = state.quantity.value, value.isFinite, value > 0 else { return "Log" }
        return "Log \(QuickAddText.amount(value, unit: unit))"
    }

    public var occurredAtRange: ClosedRange<Date> {
        let current = now()
        return FoodLogPolicy.windowStart(now: current, calendar: calendar)...current
    }

    public var displayedOccurredAt: Date { state.occurredAt ?? now() }
    public var occursNow: Bool { state.occurredAt == nil }

    public func choosePreset(_ value: Double) {
        guard phase != .saving, phase != .saved else { return }
        selectedPreset = value; customText = ""
        FoodConfirmationReducer.reduce(state: &state, action: .setQuantity(value, unit))
    }

    /// "Other amount": typed in the same unit. A unit change opens Confirm instead (Q5).
    public func setCustomText(_ text: String) {
        guard phase != .saving, phase != .saved else { return }
        selectedPreset = nil; customText = text
        FoodConfirmationReducer.reduce(state: &state, action: .setQuantity(nil, unit))
        FoodConfirmationReducer.reduce(state: &state, action: .setQuantityText(text))
    }

    public func setOccurredAt(_ date: Date?) {
        guard phase != .saving, phase != .saved else { return }
        FoodConfirmationReducer.reduce(state: &state, action: .setOccurredAt(date))
    }

    /// One Log press: the explicit acceptance of the food, amount, time and source shown.
    public func log() {
        guard canLog else { return }
        phase = .saving
        var accepted = state
        FoodConfirmationReducer.reduce(state: &accepted, action: .accept)
        do {
            savedResult = try logAction(accepted)
            state = accepted
            phase = .saved
        } catch {
            phase = .failed(FoodConfirmationViewModel.message(for: error))
        }
    }

    /// The state for Confirm ("Edit"): the current sheet state, not yet accepted.
    public var editState: FoodConfirmationState { state }
}

private extension QuickAddSheetModel.Phase {
    var isFailure: Bool { if case .failed = self { true } else { false } }
}

/// The quick-add sheet: food line, presets, Other amount, When, a plain source line and Log.
public struct QuickAddSheet: View {
    @ObservedObject private var model: QuickAddSheetModel
    private let edit: () -> Void
    private let close: () -> Void
    @State private var showsOther = false
    @State private var text = ""

    public init(model: QuickAddSheetModel, edit: @escaping () -> Void, close: @escaping () -> Void) {
        self.model = model; self.edit = edit; self.close = close
    }

    public var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.preparation.label).font(.headline)
                    Text(model.sourceLine).font(.subheadline).foregroundStyle(.secondary)
                }.accessibilityElement(children: .combine)
            }
            Section("Amount") {
                ForEach(model.presets, id: \.self) { value in
                    Button { model.choosePreset(value); showsOther = false } label: {
                        HStack {
                            Text(QuickAddText.amount(value, unit: model.unit)).foregroundStyle(.primary)
                            Spacer()
                            if model.selectedPreset == value && !showsOther {
                                Image(systemName: "checkmark").foregroundStyle(.tint).accessibilityHidden(true)
                            }
                        }.frame(minHeight: 44).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(model.selectedPreset == value && !showsOther ? .isSelected : [])
                }
                Button { showsOther = true; model.setCustomText(text) } label: {
                    HStack {
                        Text("Other amount").foregroundStyle(.primary)
                        Spacer()
                        if showsOther { Image(systemName: "checkmark").foregroundStyle(.tint).accessibilityHidden(true) }
                    }.frame(minHeight: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(showsOther ? .isSelected : [])
                if showsOther {
                    HStack {
                        TextField("Amount", text: $text)
                            #if os(iOS)
                            .keyboardType(.decimalPad)
                            #endif
                            .onChange(of: text) { _, value in model.setCustomText(value) }
                            .accessibilityLabel("Other amount in \(model.unit == .millilitres ? "millilitres" : model.unit == .grams ? "grams" : "pieces")")
                        Text(model.unit == .count ? "pieces" : model.unit.rawValue).foregroundStyle(.secondary)
                    }.frame(minHeight: 44)
                }
            }
            Section("When") {
                Toggle("Now", isOn: Binding(get: { model.occursNow },
                                            set: { model.setOccurredAt($0 ? nil : model.displayedOccurredAt) }))
                    .frame(minHeight: 44)
                if !model.occursNow {
                    DatePicker("Time", selection: Binding(get: { model.displayedOccurredAt }, set: { model.setOccurredAt($0) }),
                               in: model.occurredAtRange)
                }
            }
            if case let .failed(message) = model.phase {
                Section("Not logged") { Label(message, systemImage: "exclamationmark.triangle.fill") }
            }
        }
        .navigationTitle(model.title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel", action: close) }
            ToolbarItem(placement: .primaryAction) { Button("Edit", action: edit).disabled(model.phase == .saving) }
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 6) {
                Button { model.log() } label: {
                    Group { if model.phase == .saving { ProgressView() } else { Text(model.logTitle) } }
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!model.canLog)
                .accessibilityHint(model.blockedReason ?? "Logs this amount at the time shown")
                if let reason = model.blockedReason {
                    Text(reason).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal).padding(.vertical, 8).background(.bar)
        }
    }
}
