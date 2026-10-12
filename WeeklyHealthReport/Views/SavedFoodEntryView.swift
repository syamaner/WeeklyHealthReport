import SwiftUI
import FoodLedgerApplication
import FoodLedgerDomain
import FoodLedgerPresentation

/// Read-only saved entry (#197), pushed from the Food Log or Home. Content loads separately
/// from the edit model, so it never opens blank; Edit opens Confirm in edit mode.
struct SavedFoodEntryView: View {
    @StateObject private var model: SavedFoodEntryViewModel
    private let calendar: Calendar
    private let now: () -> Date
    @State private var showsEdit = false
    @Environment(\.dismiss) private var dismiss

    init(model: @autoclosure @escaping () -> SavedFoodEntryViewModel, calendar: Calendar, now: @escaping () -> Date) {
        _model = StateObject(wrappedValue: model())
        self.calendar = calendar
        self.now = now
    }

    var body: some View {
        content
            .navigationTitle(title)
            .toolbar {
                if model.phase == .loaded {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Edit") { if model.beginEdit() != nil { showsEdit = true } }
                            .accessibilityHint("Opens this entry for editing. The original is kept as history.")
                    }
                }
            }
            .task { await model.load() }
            .navigationDestination(isPresented: $showsEdit) {
                if let edit = model.editModel {
                    SavedEntryEditHost(model: edit) {
                        showsEdit = false
                        Task { await model.finishEdit() }
                    }
                }
            }
            .alert(FoodLogText.removeAlertTitle, isPresented: $model.confirmsRemoval) {
                Button("Cancel", role: .cancel) {}
                Button("Remove", role: .destructive) { Task { await model.confirmRemoval() } }
            } message: { Text(FoodLogText.removeAlertMessage) }
            .alert("Entry unchanged", isPresented: Binding(get: { model.changeAlert != nil }, set: { if !$0 { model.changeAlert = nil } })) {
                Button("OK") { model.changeAlert = nil }
            } message: { Text(model.changeAlert.map(FoodLogText.changeAlert) ?? "") }
            .onChange(of: model.didRemove) { _, removed in if removed { dismiss() } }
    }

    /// Each state has its own title, so missing and failed are distinct even to VoiceOver.
    private var title: String {
        switch model.phase {
        case .loading, .loaded: "Saved entry"
        case .missing: "Saved entry unavailable"
        case .failed: "Could not open saved food"
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .loading:
            ProgressView("Loading saved food").frame(maxWidth: .infinity, maxHeight: .infinity)
        case .missing:
            recovery("Saved entry unavailable", message: "This entry is no longer available. Go back and refresh the food log, or retry.")
        case .failed:
            recovery("Could not open saved food", message: "Your saved food is unchanged. Retry, or go back to the food log.")
        case .loaded:
            if let detail = model.detail { loaded(detail) }
        }
    }

    private func loaded(_ detail: SavedFoodEntryDetail) -> some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text(detail.name).font(.title3.weight(.semibold))
                    Text("\(FoodLogText.savedAmount(detail)) · \(FoodLogText.when(detail.occurredAt, now: now(), calendar: calendar))")
                        .foregroundStyle(.secondary)
                    if let estimate = FoodLogText.headerEstimate(detail) {
                        Text(estimate).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
                .accessibilityElement(children: .combine)
            }
            if model.editUnavailable {
                Section {
                    Label("This entry can’t be edited right now", systemImage: "exclamationmark.triangle")
                    Text("Its saved source could not be verified. The entry is unchanged.").font(.footnote).foregroundStyle(.secondary)
                    Button("Retry") { if model.beginEdit() != nil { showsEdit = true } }.frame(minHeight: 44)
                }
            }
            nutrition(detail)
            Section("Source") {
                Text(FoodLogText.source(detail))
                if let variant = detail.variant { Text(variant).font(.subheadline).foregroundStyle(.secondary) }
                ForEach(Array(detail.decisions.enumerated()), id: \.offset) { _, decision in
                    LabeledContent(FoodLogText.facet(decision.facet), value: FoodLogText.decision(decision))
                }
            }
            Section("History") {
                ForEach(Array(detail.history.enumerated()), id: \.offset) { _, event in
                    LabeledContent(FoodLogText.history(event.kind, now: now(), calendar: calendar),
                                   value: FoodLogText.when(event.at, now: now(), calendar: calendar))
                }
            }
            Section {
                Button("Remove from log", role: .destructive) { model.confirmsRemoval = true }
                    .frame(minHeight: 44)
            } footer: { Text(FoodLogText.savedEntryFootnote) }
        }
    }

    @ViewBuilder
    private func nutrition(_ detail: SavedFoodEntryDetail) -> some View {
        switch detail.nutrition {
        case let .calculated(totals):
            Section("Nutrition") {
                ForEach(FoodLogDayContent.stripKeys, id: \.rawValue) { key in
                    if let total = totals.first(where: { $0.key == key }) {
                        LabeledContent(FoodLogText.label(key), value: FoodLogText.nutrient(total, augmented: detail.augmentedKeys.contains(key)))
                    }
                }
                DisclosureGroup("All nutrients") {
                    ForEach(totals.filter { !FoodLogDayContent.stripKeys.contains($0.key) }, id: \.key.rawValue) { total in
                        LabeledContent(FoodLogText.label(total.key), value: FoodLogText.nutrient(total, augmented: detail.augmentedKeys.contains(total.key)))
                    }
                }
            }
        case let .notCalculable(reason):
            Section("Nutrition") {
                Text(FoodLogText.notCalculableTitle())
                Text(FoodLogText.notCalculableReason(reason)).font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    private func recovery(_ title: String, message: String) -> some View {
        ContentUnavailableView {
            Label(title, systemImage: "exclamationmark.circle")
        } description: {
            Text(message)
        } actions: {
            Button("Retry") { Task { await model.load() } }
            Button("Back") { dismiss() }
        }
    }
}

/// Confirm in edit mode, hosted by the saved entry (#197). Its own type so tests render the
/// real host.
struct SavedEntryEditHost: View {
    @ObservedObject var model: FoodConfirmationViewModel
    let finish: () -> Void

    var body: some View {
        FoodConfirmationView(model: model, leave: finish)
    }
}
