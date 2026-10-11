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
        let day: String
        if calendar.isDate(recent.item.occurredAt, inSameDayAs: now) { day = "today" }
        else if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
                calendar.isDate(recent.item.occurredAt, inSameDayAs: yesterday) { day = "yesterday" }
        else {
            var style = Date.FormatStyle(date: .omitted, time: .omitted).day().month(.abbreviated)
            style.calendar = calendar; style.timeZone = calendar.timeZone
            day = recent.item.occurredAt.formatted(style)
        }
        detail = (recent.isEstimate ? "Estimate · " : "") + "Last: \(amount.value.formatted()) \(unit) · \(day)"
        energy = recent.item.energyKcal.map { "\(Int($0.rounded(.toNearestOrAwayFromZero))) kcal" }
    }
}

/// Add food (#196): one field for food and amount in the user's own words, the other entry
/// routes, favourites (placeholder until #198) and recent foods. Nothing is logged here.
public struct AddFoodView: View {
    @State private var text = ""
    private let recents: [FoodRecentRelogItem]
    private let now: Date
    private let calendar: Calendar
    private let search: (String) -> Void
    private let scanBarcode: (() -> Void)?
    private let pasteOrDictate: (() -> Void)?
    private let favourites: (() -> Void)?
    private let relog: (FoodRecentRelogItem) -> Void

    public init(recents: [FoodRecentRelogItem], now: Date = Date(), calendar: Calendar = .current,
                initialText: String = "",
                search: @escaping (String) -> Void, scanBarcode: (() -> Void)?, pasteOrDictate: (() -> Void)?,
                favourites: (() -> Void)?, relog: @escaping (FoodRecentRelogItem) -> Void) {
        self.recents = recents; self.now = now; self.calendar = calendar
        self.search = search; self.scanBarcode = scanBarcode; self.pasteOrDictate = pasteOrDictate
        self.favourites = favourites; self.relog = relog
        _text = State(initialValue: initialText)
    }

    public var body: some View {
        Form {
            Section {
                TextField("Food and amount, e.g. 2 scrambled eggs", text: $text)
                    .accessibilityLabel("Food and amount")
                    .submitLabel(.search)
                    .onSubmit(submit)
            } footer: {
                Text("Type what you ate in your own words. Amounts and raw or cooked are picked up from the text.")
            }
            Section {
                if let scanBarcode { routeRow("Scan barcode", systemImage: "barcode.viewfinder", action: scanBarcode) }
                if let pasteOrDictate { routeRow("Paste or dictate a list", systemImage: "list.bullet", action: pasteOrDictate) }
                if let favourites { routeRow("Favourites", systemImage: "star", action: favourites) }
            }
            Section("Favourites") {
                Text("No favourites yet").foregroundStyle(.secondary)
            }
            Section {
                if recents.isEmpty {
                    Text("No recent foods").foregroundStyle(.secondary)
                } else {
                    ForEach(recents, id: \.item.logItemID) { recent in
                        let row = AddFoodRecentRowText(recent, now: now, calendar: calendar)
                        Button { relog(recent) } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(row.title).foregroundStyle(.primary)
                                    Text(row.detail).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 8)
                                if let energy = row.energy { Text(energy).font(.subheadline).foregroundStyle(.secondary).monospacedDigit() }
                            }.frame(minHeight: 44).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Opens the confirmation with the last amount filled in")
                    }
                }
            } header: { Text("Recent") } footer: {
                Text("Recent foods open the confirmation with the last amount filled in. Nothing is logged until you choose Log.")
            }
        }
        .navigationTitle("Add food")
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
