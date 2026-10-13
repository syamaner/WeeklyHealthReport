import FoodLedgerApplication
import FoodLedgerDomain
import SwiftUI

/// Plain text for one recent food row on Add food.
public struct AddFoodRecentRowText: Equatable, Sendable {
    public let title: String
    public let detail: String
    public let energy: String?

    public init(_ recent: FoodRecentRelogItem, now: Date, calendar: Calendar) {
        title = recent.name
        let amount = recent.item.lastAmount
        let unit = amount.unit == .grams ? "g" : amount.unit == .millilitres ? "mL" : (amount.value == 1 ? "piece" : "pieces")
        let shownAmount = amount.unit == .count
            ? "\(FoodDisplayNumber.amount(amount.value)) \(unit)" : FoodDisplayNumber.quantity(amount.value, unit: unit)
        let day: String
        if calendar.isDate(recent.item.occurredAt, inSameDayAs: now) { day = "today" }
        else if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
                calendar.isDate(recent.item.occurredAt, inSameDayAs: yesterday) { day = "yesterday" }
        else {
            var style = Date.FormatStyle(date: .omitted, time: .omitted).day().month(.abbreviated)
            style.calendar = calendar; style.timeZone = calendar.timeZone
            day = recent.item.occurredAt.formatted(style)
        }
        detail = (recent.isEstimate ? "Estimate · " : "") + "Last: \(shownAmount) · \(day)"
        energy = recent.item.energyKcal.map { "\(FoodDisplayNumber.kcal($0)) kcal" }
    }

    /// Accessibility text sizes stack the name, detail and energy (the Food Log row approach).
    public static func stacks(at size: DynamicTypeSize) -> Bool { size.isAccessibilitySize }
}

/// Add food (#196): one field for food and amount in the user's own words, the other entry
/// routes, favourites (#198) and recent foods. Nothing is logged here.
public struct AddFoodView: View {
    @State private var text = ""
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private let recents: [FoodRecentRelogItem]
    private let now: Date
    private let calendar: Calendar
    private let search: (String) -> Void
    private let scanBarcode: (() -> Void)?
    private let pasteOrDictate: (() -> Void)?
    private let favourites: (() -> Void)?
    /// Nil when favourites cannot be read: shown as a failure with a way to Favourites, never as empty.
    private let favouriteItems: [QuickAddItem]?
    private let quickAdd: ((QuickAddItem) -> Void)?
    private let relog: (FoodRecentRelogItem) -> Void
    /// Save as favourite on recent rows (owner decision A); nil hides it.
    private let favouriteSaving: FavouriteSaveModel?
    /// Under the list route when Add food carries a past Food Log day: list items are logged
    /// for now (confirmation v5 section 10), unlike the other routes.
    private let listImportNote: String?

    public init(recents: [FoodRecentRelogItem], now: Date = Date(), calendar: Calendar = .current,
                initialText: String = "",
                search: @escaping (String) -> Void, scanBarcode: (() -> Void)?, pasteOrDictate: (() -> Void)?,
                favourites: (() -> Void)?, favouriteItems: [QuickAddItem]? = [], quickAdd: ((QuickAddItem) -> Void)? = nil,
                favouriteSaving: FavouriteSaveModel? = nil,
                listImportNote: String? = nil,
                relog: @escaping (FoodRecentRelogItem) -> Void) {
        self.listImportNote = listImportNote
        self.recents = recents; self.now = now; self.calendar = calendar
        self.favouriteSaving = favouriteSaving
        self.search = search; self.scanBarcode = scanBarcode; self.pasteOrDictate = pasteOrDictate
        self.favourites = favourites; self.favouriteItems = favouriteItems; self.quickAdd = quickAdd; self.relog = relog
        _text = State(initialValue: initialText)
    }

    public var body: some View {
        Form {
            Section {
                HStack {
                    TextField("Food and amount, e.g. 2 scrambled eggs", text: $text)
                        .accessibilityLabel("Food and amount")
                        .submitLabel(.search)
                        .onSubmit(submit)
                    if !text.isEmpty {
                        Button { text = "" } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        }
                        .buttonStyle(.borderless)
                        .frame(minWidth: 44, minHeight: 44)
                        .accessibilityLabel("Clear text")
                    }
                }
            } footer: {
                Text("Type what you ate in your own words. Amounts and raw or cooked are picked up from the text.")
            }
            Section {
                if let scanBarcode { routeRow("Scan barcode", systemImage: "barcode.viewfinder", action: scanBarcode) }
                if let pasteOrDictate { routeRow("Paste or dictate a list", systemImage: "list.bullet", action: pasteOrDictate) }
                if let favourites { routeRow("Favourites", systemImage: "star", action: favourites) }
            } footer: {
                if pasteOrDictate != nil, let listImportNote { Text(listImportNote) }
            }
            Section {
                switch AddFoodFavouritesState(favouriteItems, quickAdd: quickAdd != nil) {
                case .failed:
                    Label(AddFoodFavouritesState.failedText, systemImage: "exclamationmark.triangle")
                    if let favourites { routeRow("Review favourites", systemImage: "star", action: favourites) }
                case .empty:
                    Text(AddFoodFavouritesState.emptyText).foregroundStyle(.secondary)
                case let .items(items):
                    ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                        Button { quickAdd?(item) } label: {
                            HStack {
                                Text(QuickAddText.title(item)).foregroundStyle(.primary)
                                Spacer(minLength: 8)
                                Text(QuickAddText.defaultAmount(item)).font(.subheadline).foregroundStyle(.secondary).monospacedDigit()
                            }.frame(minHeight: 44).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Opens quick add. Nothing is logged until you choose Log.")
                    }
                }
            } header: { Text("Favourites") }
            Section {
                if recents.isEmpty {
                    Text("No recent foods").foregroundStyle(.secondary)
                } else {
                    ForEach(recents, id: \.item.logItemID) { recent in
                        let row = AddFoodRecentRowText(recent, now: now, calendar: calendar)
                        Button { relog(recent) } label: {
                            recentRow(row, recent: recent).frame(minHeight: 44).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Opens the confirmation with the last amount filled in")
                        .modifier(RecentFavouriteActions(model: savingModel(recent), id: recent.logItemVersionID,
                                                         logItemID: recent.item.logItemID, title: row.title))
                    }
                }
            } header: { Text("Recent") } footer: {
                if let favouriteSaving {
                    RecentFooter(model: favouriteSaving, recents: recents.filter { savingModel($0) != nil })
                } else {
                    Text(RecentFooter.text(showsSaveHint: false))
                }
            }
        }
        .navigationTitle("Add food")
    }

    /// Whether any row can still be saved: pinnable, not plain water and not already a favourite.
    @MainActor
    public static func showsSaveHint(_ recents: [FoodRecentRelogItem], model: FavouriteSaveModel) -> Bool {
        recents.contains { recent in
            guard let id = recent.logItemVersionID, !recent.isPlainWater else { return false }
            return !model.state(for: id).isFavourite
        }
    }

    /// The saving model for a row that may be saved: verified, pinnable and not plain water.
    private func savingModel(_ recent: FoodRecentRelogItem) -> FavouriteSaveModel? {
        guard recent.logItemVersionID != nil, !recent.isPlainWater else { return nil }
        return favouriteSaving
    }

    @ViewBuilder
    private func favouriteBadge(_ recent: FoodRecentRelogItem) -> some View {
        if let model = savingModel(recent), let id = recent.logItemVersionID { RecentFavouriteBadge(model: model, id: id) }
    }

    @ViewBuilder
    private func recentRow(_ row: AddFoodRecentRowText, recent: FoodRecentRelogItem) -> some View {
        if AddFoodRecentRowText.stacks(at: dynamicTypeSize) {
            // Stacked at accessibility sizes, as in the Food Log, so the name never breaks mid-word.
            VStack(alignment: .leading, spacing: 4) {
                Text(row.title).foregroundStyle(.primary)
                Text(row.detail).font(.caption).foregroundStyle(.secondary)
                favouriteBadge(recent)
                if let energy = row.energy { Text(energy).font(.subheadline).foregroundStyle(.secondary).monospacedDigit() }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        } else {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(row.title).foregroundStyle(.primary)
                    Text(row.detail).font(.caption).foregroundStyle(.secondary)
                    favouriteBadge(recent)
                }
                Spacer(minLength: 8)
                if let energy = row.energy { Text(energy).font(.subheadline).foregroundStyle(.secondary).monospacedDigit() }
            }
        }
    }

    private func submit() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        search(trimmed)
    }

    private func routeRow(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Label(title, systemImage: systemImage).foregroundStyle(.primary)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary).accessibilityHidden(true)
            }.frame(minHeight: 44).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
}

/// Add food's Recent footer. The swipe hint appears only while at least one row can still be saved
/// (pinnable, not plain water, not already a favourite).
struct RecentFooter: View {
    @ObservedObject var model: FavouriteSaveModel
    /// Rows that offer the action (pinnable and not plain water).
    let recents: [FoodRecentRelogItem]

    static func text(showsSaveHint: Bool) -> String {
        "Recent foods open the confirmation with the last amount filled in. Nothing is logged until you choose Log."
            + (showsSaveHint ? " Swipe right or touch and hold to save one as a favourite." : "")
    }

    var body: some View {
        Text(Self.text(showsSaveHint: AddFoodView.showsSaveHint(recents, model: model)))
    }
}

/// "Already a favourite" or "Saved as favourite" on a recent row, never colour alone.
struct RecentFavouriteBadge: View {
    @ObservedObject var model: FavouriteSaveModel
    let id: LogItemVersionID

    var body: some View {
        let state = model.state(for: id)
        if state.isFavourite {
            Label(FavouriteSaveText.title(state), systemImage: "star.fill").font(.caption).foregroundStyle(.secondary)
        }
    }
}

/// Save as favourite on a recent row: a leading swipe, the context menu and a VoiceOver action. A
/// failure says "Favourite not saved" with Try again; the logged entry is unchanged either way.
struct RecentFavouriteActions: ViewModifier {
    let model: FavouriteSaveModel?
    let id: LogItemVersionID?
    let logItemID: LogItemID
    let title: String

    func body(content: Content) -> some View {
        if let model, let id {
            content.modifier(Actions(model: model, id: id, logItemID: logItemID, title: title))
        } else {
            content
        }
    }

    private struct Actions: ViewModifier {
        @ObservedObject var model: FavouriteSaveModel
        let id: LogItemVersionID
        let logItemID: LogItemID
        let title: String
        @State private var alert = FavouriteRetryAlert()

        func body(content: Content) -> some View {
            let canSave = !model.state(for: id).isFavourite
            content
                .swipeActions(edge: .leading) {
                    if canSave {
                        Button(action: save) { Label(FavouriteSaveText.save, systemImage: "star") }.tint(.orange)
                    }
                }
                .contextMenu {
                    if canSave {
                        Button(action: save) { Label(FavouriteSaveText.save, systemImage: "star") }
                    } else {
                        Label(FavouriteSaveText.title(model.state(for: id)), systemImage: "star.fill")
                    }
                }
                .accessibilityActions {
                    if canSave { Button(FavouriteSaveText.save, action: save) }
                }
                .alert(FavouriteSaveText.failed, isPresented: Binding(get: { alert.isPresented },
                                                                      set: { if !$0 { alert.dismissed() } })) {
                    Button(FavouriteSaveText.tryAgain) { alert.tryAgain() }
                    Button("Cancel", role: .cancel) {}
                } message: { Text(FavouriteSaveText.failedMessage) }
                // Try again runs only after the alert has gone, so a second failure presents it again.
                .onChange(of: alert.isPresented) { _, shown in
                    if !shown, alert.takeRetry() { Task { @MainActor in save() } }
                }
        }

        private func save() {
            model.save(id, logItemID: logItemID)
            alert.finished(model.state(for: id))
        }
    }
}

/// In-memory diagnostics of the last search and web lookup, shown in Settings › Developer
/// tools. Never persisted and never given a credential.
@MainActor
public final class FoodSearchDiagnosticsLog: ObservableObject {
    @Published public private(set) var searchLines: [String] = []
    @Published public private(set) var webLookupLines: [String] = []
    public init() {}
    public func recordSearch(_ lines: [String]) { searchLines = lines }
    public func recordWebLookup(_ lines: [String]) { webLookupLines = lines }
}

/// What Add food's Favourites section shows (#198).
public enum AddFoodFavouritesState: Equatable {
    case failed
    case empty
    case items([QuickAddItem])

    public static let failedText = "Favourites could not be read."
    public static let emptyText = "No favourites yet"

    public init(_ items: [QuickAddItem]?, quickAdd: Bool) {
        guard let items else { self = .failed; return }
        self = items.isEmpty || !quickAdd ? .empty : .items(items)
    }
}
