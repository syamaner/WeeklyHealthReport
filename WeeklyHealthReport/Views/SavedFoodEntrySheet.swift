import SwiftUI
import FoodLedgerDomain
import FoodLedgerPresentation

/// App presentation owns loading; the confirmation service retains saved-record semantics.
@MainActor
final class SavedFoodEntrySession: ObservableObject, Identifiable {
    enum Phase {
        case loading
        case loaded(FoodConfirmationViewModel)
        case missing
        case failed
    }

    let id: LogItemID
    @Published private(set) var phase: Phase = .loading
    private let loader: () throws -> FoodConfirmationViewModel?

    init(id: LogItemID, loader: @escaping () throws -> FoodConfirmationViewModel?) {
        self.id = id
        self.loader = loader
    }

    func load() {
        phase = .loading
        do {
            if let model = try loader() { phase = .loaded(model) }
            else { phase = .missing }
        } catch { phase = .failed }
    }
}

struct SavedFoodEntrySheet: View {
    @ObservedObject var session: SavedFoodEntrySession
    let close: () -> Void

    var body: some View {
        NavigationStack {
            Group {
                switch session.phase {
                case .loading:
                    ProgressView("Loading saved food")
                case let .loaded(model):
                    FoodConfirmationView(model: model, showsCancelButton: false, leave: close)
                case .missing:
                    recovery("Saved entry unavailable", message: "This entry is no longer available. Close and refresh the food log, or retry.")
                case .failed:
                    recovery("Could not open saved food", message: "Your saved food is unchanged. Retry, or close and refresh the food log.")
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close", action: close) }
            }
        }
        .task { session.load() }
    }

    private func recovery(_ title: String, message: String) -> some View {
        ContentUnavailableView {
            Label(title, systemImage: "exclamationmark.circle")
        } description: {
            Text(message)
        } actions: {
            Button("Retry") { session.load() }
        }
        .navigationTitle(title)
    }
}
