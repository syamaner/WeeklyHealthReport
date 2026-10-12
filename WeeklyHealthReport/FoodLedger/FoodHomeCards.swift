import SwiftUI
import FoodLedgerApplication
import FoodLedgerDomain
import FoodLedgerPresentation

/// Home's food card content, ready to render (#199). Pure: built from the
/// projection and phase 5's plain water total; nothing absent reads as 0.
struct FoodHomeCardContent: Equatable {
    struct Row: Equatable {
        let label: String
        let value: String
        let accessibilityLabel: String
    }

    struct Logged: Equatable {
        let energy: Row
        let entryCount: String
        let nutrients: [Row]
        let water: Row
        /// One footnote naming each known minimum, or nil when every total is complete.
        let footnote: String?
    }

    enum State: Equatable {
        case loading
        case unavailable
        case failed(String)
        case empty
        case logged(Logged)
    }

    static let title = "Food logged"
    static let emptyMessage = "Nothing logged yet today"
    static let unavailableMessage = "The local food log could not be opened."
    static let nutrientKeys: [NutrientKey] = [.protein, .carbohydrates, .fatTotal]

    static func make(
        projection: FoodIntakeProjection,
        plainWater: FoodIntakeTotal?,
        locale: Locale = .autoupdatingCurrent
    ) -> State {
        make(itemCount: projection.summary.itemCount, totals: projection.summary.totals,
             plainWater: plainWater, locale: locale)
    }

    static func make(
        itemCount: Int,
        totals: [FoodIntakeTotal],
        plainWater: FoodIntakeTotal?,
        locale: Locale = .autoupdatingCurrent
    ) -> State {
        guard itemCount > 0 else { return .empty }
        func row(_ key: NutrientKey) -> Row {
            guard let total = totals.first(where: { $0.key == key }) else {
                let label = FoodLogText.label(key)
                return Row(label: label, value: "Unknown", accessibilityLabel: "\(label), unknown")
            }
            let value = amount(total, locale: locale).map { total.incompleteContributions > 0 ? $0 + "+" : $0 } ?? "Unknown"
            return Row(label: FoodLogText.label(key), value: value,
                       accessibilityLabel: FoodLogText.totalAccessibility(total, locale: locale))
        }
        let minimums = ([NutrientKey.energyConsumed] + nutrientKeys).compactMap { key in
            totals.first(where: { $0.key == key }).flatMap { knownMinimum($0, locale: locale) }
        } + [plainWater.flatMap { waterMinimum($0, locale: locale) }].compactMap { $0 }
        return .logged(Logged(
            energy: row(.energyConsumed),
            entryCount: entryCount(itemCount),
            nutrients: nutrientKeys.map(row),
            water: Row(label: FoodLogText.plainWaterLabel, value: FoodLogText.plainWater(plainWater, locale: locale),
                       accessibilityLabel: FoodLogText.plainWaterAccessibility(plainWater, locale: locale)),
            footnote: minimums.isEmpty ? nil : minimums.joined(separator: " ")
        ))
    }

    static func entryCount(_ count: Int) -> String {
        count == 1 ? "1 entry" : "\(count) entries"
    }

    static func failureMessage(_ error: Error) -> String {
        switch error as? FoodIntakeProjectionError {
        case .competingVersions: "Conflicting food versions need review before an intake total can be shown."
        case .unsupportedMixture: "This day includes a mixed meal that cannot yet be totalled safely."
        default: "The local food log could not be read. Unlock your device and try again."
        }
    }

    /// "Fat unknown for 1 entry, so 41 g is a known minimum."
    private static func knownMinimum(_ total: FoodIntakeTotal, locale: Locale) -> String? {
        guard total.incompleteContributions > 0 else { return nil }
        let label = FoodLogText.label(total.key)
        let entries = entryCount(total.incompleteContributions)
        guard let value = amount(total, locale: locale) else { return "\(label) unknown for \(entries)." }
        return "\(label) unknown for \(entries), so \(value) is a known minimum."
    }

    /// "1,240 kcal" or "41 g" without the known-minimum mark; nil when unknown.
    private static func amount(_ total: FoodIntakeTotal, locale: Locale) -> String? {
        guard total.knownAmount != nil else { return nil }
        let complete = FoodIntakeTotal(key: total.key, knownAmount: total.knownAmount,
                                       incompleteContributions: 0, includesEstimates: total.includesEstimates)
        let value = FoodLogText.total(complete, locale: locale)
        return total.key == .energyConsumed ? value + " kcal" : value
    }

    private static func waterMinimum(_ total: FoodIntakeTotal, locale: Locale) -> String? {
        guard total.incompleteContributions > 0, total.knownAmount != nil else { return nil }
        let value = FoodLogText.plainWater(total, locale: locale)
        return "Plain water amount unknown for \(entryCount(total.incompleteContributions)), so \(value.hasSuffix("+") ? String(value.dropLast()) : value) is a known minimum."
    }
}

/// Food on Home: the totals card, Add food and quick add (#199). Reads use the
/// composition root's confirmation clock and calendar, so "today" matches Confirm.
@MainActor
final class FoodHomeModel: ObservableObject {
    enum QuickAddState {
        case unavailable
        case items([QuickAddItem])
        case unreadable
    }

    @Published private(set) var state: FoodHomeCardContent.State = .loading
    @Published private(set) var quickAdd: QuickAddState = .unavailable
    /// Set by a chip; phase 5's `QuickAddPresenter` consumes it and opens the sheet.
    @Published var quickAddRequest: QuickAddItem?
    let root: FoodLedgerCompositionRoot?

    init(root: FoodLedgerCompositionRoot?) {
        self.root = root
        if root == nil { state = .unavailable }
    }

    func reload() {
        guard let root else {
            state = .unavailable; quickAdd = .unavailable
            return
        }
        let now = root.confirmationNow
        let calendar = root.confirmationDayCalendar
        do {
            let projection = try root.intakeProjection(for: now, calendar: calendar)
            let water = try root.plainWaterTotal(for: now, calendar: calendar)
            state = FoodHomeCardContent.make(projection: projection, plainWater: water)
        } catch {
            state = .failed(FoodHomeCardContent.failureMessage(error))
        }
        quickAdd = root.quickAddItems().map { .items(Array($0.prefix(FavouritesProjection.todayCount))) } ?? .unreadable
    }
}

enum FoodHomeCards {
    static func feature(model: FoodHomeModel) -> HomeFeature {
        HomeFeature(
            cards: [
                HomeCard(id: .food) { _ in AnyView(FoodHomeCard(model: model)) },
                HomeCard(id: .addFood) { _ in AnyView(AddFoodHomeCard(available: model.root != nil)) },
                HomeCard(id: .quickAdd) { _ in AnyView(QuickAddHomeCard(model: model)) }
            ],
            decorate: { view in AnyView(view.modifier(FoodHomeQuickAddHost(model: model))) },
            refresh: { _ in model.reload() }
        )
    }
}

/// Quick add is presentation state of Home: the sheet and any full Confirm are
/// owned at screen level, and the one completion after Log reloads the food card.
private struct FoodHomeQuickAddHost: ViewModifier {
    @ObservedObject var model: FoodHomeModel

    func body(content: Content) -> some View {
        if let root = model.root {
            content.quickAdd(root: root, request: $model.quickAddRequest, logged: { model.reload() })
        } else {
            content
        }
    }
}

struct FoodHomeCard: View {
    @ObservedObject var model: FoodHomeModel

    var body: some View {
        Section {
            switch model.state {
            case .loading:
                ProgressView("Loading food log")
            case .unavailable:
                Label(FoodHomeCardContent.unavailableMessage, systemImage: "exclamationmark.triangle")
            case .failed(let message):
                Label(message, systemImage: "exclamationmark.triangle")
                Button("Try again") { model.reload() }
            case .empty:
                NavigationLink(value: AppRoute.foodLog) {
                    Text(FoodHomeCardContent.emptyMessage).foregroundStyle(.secondary)
                }
                .accessibilityHint("Opens the Food Log")
            case .logged(let logged):
                NavigationLink(value: AppRoute.foodLog) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(logged.energy.value).font(.title2.weight(.semibold)).monospacedDigit()
                        Text(logged.entryCount).font(.subheadline).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(logged.energy.accessibilityLabel), \(logged.entryCount)")
                .accessibilityHint("Opens the Food Log")
                ForEach(logged.nutrients + [logged.water], id: \.label) { row in
                    LabeledContent(row.label, value: row.value)
                        .monospacedDigit()
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(row.accessibilityLabel)
                }
            }
        } header: {
            Text(FoodHomeCardContent.title)
        } footer: {
            if case .logged(let logged) = model.state, let footnote = logged.footnote {
                Text(footnote)
            }
        }
    }
}

struct AddFoodHomeCard: View {
    let available: Bool

    var body: some View {
        Section {
            NavigationLink(value: AppRoute.addFood) {
                Label("Add food", systemImage: "plus.circle.fill")
                    .font(.headline)
                    .frame(minHeight: 44)
            }
            .disabled(!available)
            .accessibilityIdentifier("homeAddFood")
        }
    }
}

struct QuickAddHomeCard: View {
    @ObservedObject var model: FoodHomeModel

    var body: some View {
        switch model.quickAdd {
        case .unavailable:
            EmptyView()
        case .items(let items):
            Section {
                if items.isEmpty {
                    Text("No favourites yet").foregroundStyle(.secondary)
                } else {
                    QuickAddChipRow(items: items) { model.quickAddRequest = $0 }
                        .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                }
                NavigationLink("Manage favourites", value: AppRoute.favourites)
            } header: { Text("Quick add") } footer: {
                Text("A quick add opens a short confirmation. Nothing is logged until you choose Log.")
            }
        case .unreadable:
            Section {
                Label("Favourites could not be read.", systemImage: "exclamationmark.triangle")
                NavigationLink("Review favourites", value: AppRoute.favourites)
            } header: { Text("Quick add") }
        }
    }
}
