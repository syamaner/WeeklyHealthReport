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
        /// "Includes estimates" when known values include estimates, as in the Food Log.
        var caption: String? = nil
    }

    struct Logged: Equatable {
        let energy: Row
        let entryCount: String
        let nutrients: [Row]
        let water: Row
        /// One line about the known minimums ("+"), or nil when every total is complete.
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
    /// Rows after energy, in order. Fibre follows fat (phase 6 amendment, 23 October 2026, #288).
    static let nutrientKeys: [NutrientKey] = [.protein, .carbohydrates, .fatTotal, .fiber]

    static func make(
        projection: FoodIntakeProjection,
        plainWater: FoodIntakeTotal?,
        locale: Locale = .autoupdatingCurrent
    ) -> State {
        // Plain water is not a food entry and adds nothing to the nutrient totals
        // (`food-intake-summary-v5`, #304), so only food rows count here.
        make(itemCount: projection.summary.itemCount, foodItemCount: projection.summary.foodItemCount,
             totals: projection.summary.totals, plainWater: plainWater, locale: locale,
             incompleteEntries: incompleteEntries(projection.rows.filter { !$0.isPlainWater }.map(\.totals),
                                                  dayTotals: projection.summary.totals, plainWater: plainWater))
    }

    /// Distinct current entries behind the card's known minimums: an entry counts once when any
    /// shown total it contributes to (energy, protein, carbohydrates, fat, fibre) lacks its value.
    /// `rows` are food entries only; plain water that cannot be scaled leaves the water figure a
    /// known minimum, so the larger count covers it.
    static func incompleteEntries(_ rows: [[FoodIntakeTotal]], dayTotals: [FoodIntakeTotal], plainWater: FoodIntakeTotal?) -> Int {
        let affected = ([NutrientKey.energyConsumed] + nutrientKeys).filter { key in
            (dayTotals.first { $0.key == key }?.incompleteContributions ?? 0) > 0
        }
        let entries = rows.filter { totals in
            affected.contains { key in (totals.first { $0.key == key }?.incompleteContributions ?? 1) > 0 }
        }.count
        return max(entries, plainWater?.incompleteContributions ?? 0)
    }

    /// `itemCount` is every current entry (the card is empty only with none); `foodItemCount`, the
    /// entries that are not plain water, is the count shown. Nil means every entry is food.
    static func make(
        itemCount: Int,
        foodItemCount: Int? = nil,
        totals: [FoodIntakeTotal],
        plainWater: FoodIntakeTotal?,
        locale: Locale = .autoupdatingCurrent,
        incompleteEntries: Int
    ) -> State {
        guard itemCount > 0 else { return .empty }
        func row(_ key: NutrientKey) -> Row {
            guard let total = totals.first(where: { $0.key == key }) else {
                let label = FoodLogText.label(key)
                return Row(label: label, value: "Unknown", accessibilityLabel: "\(label), unknown")
            }
            let value = amount(total, locale: locale).map { total.incompleteContributions > 0 ? $0 + "+" : $0 } ?? "Unknown"
            return Row(label: FoodLogText.label(key), value: value,
                       accessibilityLabel: FoodLogText.totalAccessibility(total, locale: locale),
                       caption: FoodLogText.totalCaption(total))
        }
        let affected = (([NutrientKey.energyConsumed] + nutrientKeys).compactMap { key in totals.first { $0.key == key } }
            + [plainWater].compactMap { $0 }).filter { $0.incompleteContributions > 0 }
        return .logged(Logged(
            energy: row(.energyConsumed),
            entryCount: entryCount(foodItemCount ?? itemCount),
            nutrients: nutrientKeys.map(row),
            water: Row(label: FoodLogText.plainWaterLabel, value: FoodLogText.plainWater(plainWater, locale: locale),
                       accessibilityLabel: FoodLogText.plainWaterAccessibility(plainWater, locale: locale)),
            footnote: footnote(affected, entries: incompleteEntries)
        ))
    }

    /// One short line whatever the number of affected totals (owner decision F, 13 October
    /// 2026): "Some values are unknown for 2 entries, so totals marked + are known minimums."
    /// `entries` is the count of distinct entries (`incompleteEntries`).
    static func footnote(_ affected: [FoodIntakeTotal], entries: Int) -> String? {
        guard !affected.isEmpty else { return nil }
        let unknown = "Some values are unknown for \(entryCount(max(entries, 1)))"
        // "+" appears only beside a total with a known part; an all-unknown total reads "Unknown".
        return affected.contains { $0.knownAmount != nil }
            ? unknown + ", so totals marked + are known minimums." : unknown + "."
    }

    static let loadingMessage = "Loading food log"

    /// The card as plain text for Today's Full Page, in the card's own words.
    static func fullPageSection(_ state: State) -> TodayFullPageDocument.Section {
        typealias Row = TodayFullPageDocument.Row
        switch state {
        case .loading: return .init(title: title, rows: [Row(value: loadingMessage)])
        case .unavailable: return .init(title: title, rows: [Row(value: unavailableMessage)])
        case .failed(let message): return .init(title: title, rows: [Row(value: message)])
        case .empty: return .init(title: title, rows: [Row(value: emptyMessage)])
        case .logged(let logged):
            let energy = Row(logged.energy.label, value: logged.energy.value, note: logged.energy.caption)
            let others = (logged.nutrients + [logged.water]).map { Row($0.label, value: $0.value, note: $0.caption) }
            return .init(title: title, rows: [energy, Row(value: logged.entryCount)] + others, footer: logged.footnote)
        }
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

    /// "1,240 kcal" or "41 g" without the known-minimum mark; nil when unknown.
    private static func amount(_ total: FoodIntakeTotal, locale: Locale) -> String? {
        guard total.knownAmount != nil else { return nil }
        let complete = FoodIntakeTotal(key: total.key, knownAmount: total.knownAmount,
                                       incompleteContributions: 0, includesEstimates: total.includesEstimates)
        let value = FoodLogText.total(complete, locale: locale)
        return total.key == .energyConsumed ? value + " kcal" : value
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
                HomeCard(id: .food, fullPage: { _ in FoodHomeCardContent.fullPageSection(model.state) }) { _ in
                    AnyView(FoodHomeCard(model: model))
                },
                // Add food is only a control, so Full Page omits it.
                HomeCard(id: .addFood) { _ in AnyView(AddFoodHomeCard(available: model.root != nil)) },
                HomeCard(id: .quickAdd, fullPage: { _ in QuickAddHomeCard.fullPageSection(model.quickAdd) }) { _ in
                    AnyView(QuickAddHomeCard(model: model))
                }
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
                ProgressView(FoodHomeCardContent.loadingMessage)
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
                        if let caption = logged.energy.caption {
                            Text(caption).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(logged.energy.accessibilityLabel), \(logged.entryCount)")
                .accessibilityHint("Opens the Food Log")
                ForEach(logged.nutrients + [logged.water], id: \.label) { row in
                    LabeledContent {
                        Text(row.value).monospacedDigit()
                    } label: {
                        Text(row.label)
                        if let caption = row.caption {
                            Text(caption)
                        }
                    }
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

    static let title = "Quick add"
    static let noFavourites = "No favourites yet"
    static let unreadable = "Favourites could not be read."

    /// Full Page lists each chip's name and default amount; the chips themselves
    /// and the favourites links are controls. Nil when the card is hidden.
    static func fullPageSection(_ state: FoodHomeModel.QuickAddState) -> TodayFullPageDocument.Section? {
        typealias Row = TodayFullPageDocument.Row
        switch state {
        case .unavailable:
            return nil
        case .items(let items):
            let rows = items.isEmpty
                ? [Row(value: noFavourites)]
                : items.map { Row(QuickAddText.title($0), value: QuickAddText.defaultAmount($0)) }
            return .init(title: title, rows: rows)
        case .unreadable:
            return .init(title: title, rows: [Row(value: unreadable)])
        }
    }

    var body: some View {
        switch model.quickAdd {
        case .unavailable:
            EmptyView()
        case .items(let items):
            Section {
                if items.isEmpty {
                    Text(Self.noFavourites).foregroundStyle(.secondary)
                } else {
                    QuickAddChipRow(items: items) { model.quickAddRequest = $0 }
                        .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                }
                NavigationLink("Manage favourites", value: AppRoute.favourites)
            } header: { Text(Self.title) } footer: {
                Text("A quick add opens a short confirmation. Nothing is logged until you choose Log.")
            }
        case .unreadable:
            Section {
                Label(Self.unreadable, systemImage: "exclamationmark.triangle")
                NavigationLink("Review favourites", value: AppRoute.favourites)
            } header: { Text(Self.title) }
        }
    }
}
