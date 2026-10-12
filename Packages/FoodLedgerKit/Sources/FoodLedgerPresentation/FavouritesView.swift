import FoodLedgerApplication
import FoodLedgerDomain
import SwiftUI

/// The Favourites screen's port (consumer-owned). `FavouritesService` conforms below.
public protocol FavouritesManaging: AnyObject {
    func projection() throws -> FavouritesProjection
    /// Nil when the favourite's source can no longer be verified.
    func isEstimate(_ version: FavouriteVersion) -> Bool?
    func rename(_ favouriteID: FavouriteID, to label: LedgerText) throws
    func setDefaultAmount(_ favouriteID: FavouriteID, to amount: FavouriteAmount) throws
    func remove(_ favouriteID: FavouriteID) throws
    func arrange(_ items: [QuickAddItem]) throws
    func saveBuiltInWater(label: LedgerText, millilitres: Double) throws
    func removeBuiltInWater() throws
}

extension FavouritesService: FavouritesManaging {}

/// One row of the Favourites screen.
public struct FavouriteRow: Equatable, Identifiable {
    public let id: String
    public let item: QuickAddItem
    public let title: String
    public let detail: String
    public let isUnverifiable: Bool
}

@MainActor
public final class FavouritesViewModel: ObservableObject {
    public enum Phase: Equatable { case loading, loaded, failed(String) }

    @Published public private(set) var phase: Phase = .loading
    @Published public private(set) var today: [FavouriteRow] = []
    @Published public private(set) var others: [FavouriteRow] = []
    @Published public private(set) var changeFailure: String?
    private let store: any FavouritesManaging

    public static let competingMessage = "Favourites changed on another device and need review before they can be shown."
    public static let unreadableMessage = "Favourites could not be read. Unlock your device and try again."
    public static let notSavedMessage = "The change was not saved. Try again."

    public init(store: any FavouritesManaging) { self.store = store }

    public var isEmpty: Bool { today.isEmpty && others.isEmpty }

    public func reload() {
        do {
            let projection = try store.projection()
            let rows = projection.quickAddItems.map(row)
            today = Array(rows.prefix(FavouritesProjection.todayCount))
            others = Array(rows.dropFirst(FavouritesProjection.todayCount))
            phase = .loaded
        } catch is FavouritesProjectionError {
            today = []; others = []; phase = .failed(Self.competingMessage)
        } catch {
            today = []; others = []; phase = .failed(Self.unreadableMessage)
        }
    }

    private func row(_ item: QuickAddItem) -> FavouriteRow {
        switch item {
        case .builtInWater:
            return FavouriteRow(id: "built-in-water", item: item, title: QuickAddText.title(item),
                                detail: QuickAddText.detail(item, isEstimate: false), isUnverifiable: false)
        case let .favourite(version):
            let estimate = store.isEstimate(version)
            return FavouriteRow(id: version.favouriteID.rawValue, item: item, title: QuickAddText.title(item),
                                detail: QuickAddText.detail(item, isEstimate: estimate), isUnverifiable: estimate == nil)
        }
    }

    /// Quick-add order across both sections. Writes one arrangement version.
    public func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        var items = (today + others).map(\.item)
        items.move(fromOffsets: source, toOffset: destination)
        perform { try store.arrange(items) }
    }

    /// The VoiceOver alternative to dragging.
    public func move(_ row: FavouriteRow, by offset: Int) {
        let rows = today + others
        guard let index = rows.firstIndex(of: row) else { return }
        let target = index + offset
        guard rows.indices.contains(target) else { return }
        move(fromOffsets: IndexSet(integer: index), toOffset: offset > 0 ? target + 1 : target)
    }

    public func rename(_ row: FavouriteRow, to text: String) {
        perform {
            let label = try LedgerText(text)
            switch row.item {
            case .builtInWater: try store.saveBuiltInWater(label: label, millilitres: QuickAddItem.builtInWaterMillilitres)
            case let .favourite(version): try store.rename(version.favouriteID, to: label)
            }
        }
    }

    public func setDefaultAmount(_ row: FavouriteRow, to value: Double?) {
        perform {
            guard let value else { throw FoodLedgerValidationError.nonPositive("favourite amount") }
            switch row.item {
            case .builtInWater:
                try store.saveBuiltInWater(label: LedgerText(PlainWaterReference.name), millilitres: try FavouriteAmount(value: value, unit: .millilitres).value)
            case let .favourite(version):
                try store.setDefaultAmount(version.favouriteID, to: FavouriteAmount(value: value, unit: version.defaultAmount.unit))
            }
        }
    }

    public func remove(_ row: FavouriteRow) {
        perform {
            switch row.item {
            case .builtInWater: try store.removeBuiltInWater()
            case let .favourite(version): try store.remove(version.favouriteID)
            }
        }
    }

    private func perform(_ change: () throws -> Void) {
        do { try change(); changeFailure = nil } catch { changeFailure = Self.notSavedMessage }
        reload()
    }
}

/// Favourites (#198): quick-add order (the first four appear on Today), other favourites, and the
/// routes that create a favourite. Photo routes are not available yet (#93).
public struct FavouritesView: View {
    @ObservedObject private var model: FavouritesViewModel
    private let createFromSearch: () -> Void
    private let createFromBarcode: () -> Void
    private let createFromWebLookup: () -> Void
    @State private var editing: FavouriteRow?
    @State private var labelText = ""
    @State private var amountText = ""
    @State private var removing: FavouriteRow?
    @Environment(\.locale) private var locale

    public init(model: FavouritesViewModel, createFromSearch: @escaping () -> Void,
                createFromBarcode: @escaping () -> Void, createFromWebLookup: @escaping () -> Void) {
        self.model = model
        self.createFromSearch = createFromSearch; self.createFromBarcode = createFromBarcode
        self.createFromWebLookup = createFromWebLookup
    }

    public var body: some View {
        List {
            switch model.phase {
            case .loading:
                Section { ProgressView("Loading favourites") }
            case let .failed(message):
                Section("Favourites unavailable") {
                    Label(message, systemImage: "exclamationmark.triangle")
                    Button("Try again") { model.reload() }.frame(minHeight: 44)
                }
            case .loaded:
                if let failure = model.changeFailure {
                    Section { Label(failure, systemImage: "exclamationmark.triangle") }
                }
                Section {
                    if model.today.isEmpty { Text("No favourites yet").foregroundStyle(.secondary) }
                    ForEach(model.today) { rowView($0) }
                        .onMove { model.move(fromOffsets: $0, toOffset: $1) }
                } header: { Text("On Today’s quick add") } footer: {
                    Text("Drag to reorder. The first four appear on Today.")
                }
                if !model.others.isEmpty {
                    Section("Other favourites") {
                        ForEach(model.others) { rowView($0) }
                            .onMove { source, destination in
                                model.move(fromOffsets: IndexSet(source.map { $0 + model.today.count }),
                                           toOffset: destination + model.today.count)
                            }
                    }
                }
            }
            Section {
                createRow("Food search", systemImage: "magnifyingglass", action: createFromSearch)
                createRow("Barcode", systemImage: "barcode.viewfinder", action: createFromBarcode)
                createRow("Web lookup", systemImage: "globe", action: createFromWebLookup)
                unavailableRow("Photo of nutrition label")
                unavailableRow("Photo of the food")
            } header: { Text("Create a favourite from") } footer: {
                Text("A favourite keeps its source and a default amount, so logging it later takes one step.")
            }
        }
        .navigationTitle("Favourites")
        .toolbar {
            #if os(iOS)
            if !model.isEmpty { EditButton() }
            #endif
        }
        .onAppear { model.reload() }
        .sheet(item: $editing) { row in
            NavigationStack {
                FavouriteEditor(labelText: $labelText, amountText: $amountText, unitLabel: unitLabel(row.item),
                                cancel: { editing = nil }, save: { save(row) },
                                remove: { removing = row; editing = nil })
            }
        }
        .alert("Remove this favourite?", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } })) {
            Button("Remove", role: .destructive) { if let removing { model.remove(removing) }; removing = nil }
            Button("Cancel", role: .cancel) { removing = nil }
        } message: { Text("Entries you have already logged stay in your Food Log.") }
    }

    private func rowView(_ row: FavouriteRow) -> some View {
        Button {
            labelText = row.title
            amountText = defaultAmountText(row.item)
            editing = row
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(row.title).foregroundStyle(.primary)
                    Text(row.detail).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary).accessibilityHidden(true)
            }.frame(minHeight: 44).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens the favourite to rename it, change its default amount or remove it")
        .accessibilityAction(named: "Move up") { model.move(row, by: -1) }
        .accessibilityAction(named: "Move down") { model.move(row, by: 1) }
    }

    private func save(_ row: FavouriteRow) {
        if labelText.trimmingCharacters(in: .whitespacesAndNewlines) != row.title { model.rename(row, to: labelText) }
        let amount = FoodAmountFieldText.parse(amountText, locale: locale)
        if amountText != defaultAmountText(row.item) { model.setDefaultAmount(row, to: amount) }
        editing = nil
    }

    private func defaultAmountText(_ item: QuickAddItem) -> String {
        switch item {
        case .builtInWater: FoodAmountFieldText.text(QuickAddItem.builtInWaterMillilitres, locale: locale)
        case let .favourite(version): FoodAmountFieldText.text(version.defaultAmount.value, locale: locale)
        }
    }

    private func unitLabel(_ item: QuickAddItem) -> String {
        switch item {
        case .builtInWater: "mL"
        case let .favourite(version): version.defaultAmount.unit == .count ? "pieces" : version.defaultAmount.unit.rawValue
        }
    }

    private func createRow(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Label(title, systemImage: systemImage).foregroundStyle(.primary)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary).accessibilityHidden(true)
            }.frame(minHeight: 44).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens \(title.lowercased()). Log the food with Save as favourite on to create a favourite.")
    }

    private func unavailableRow(_ title: String) -> some View {
        HStack {
            Text(title).foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text("Not yet available").font(.caption).foregroundStyle(.secondary)
        }
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
    }
}

/// The favourite editor sheet (#212). Its own view so it owns the amount focus: focus state of
/// the presenting view does not reach a sheet's content, and the keyboard "Done" would not show.
struct FavouriteEditor: View {
    /// The editor's one amount field, and where its "Done" goes: the sheet has no pinned bar
    /// and Save already sits in the navigation bar, so "Done" rides above the keyboard.
    static let amountField = AmountFieldFocus.favouriteDefault
    static let donePlacement = AmountDonePlacement.keyboard

    @Binding var labelText: String
    @Binding var amountText: String
    let unitLabel: String
    let cancel: () -> Void
    let save: () -> Void
    let remove: () -> Void
    @FocusState private var editingAmount: AmountFieldFocus?

    var body: some View {
        Form {
            Section("Name") { TextField("Name", text: $labelText).accessibilityLabel("Favourite name") }
            Section {
                HStack {
                    TextField("Default amount", text: $amountText)
                        .amountKeyboard($editingAmount, Self.amountField)
                        .accessibilityLabel("Default amount")
                    Text(unitLabel).foregroundStyle(.secondary)
                }
            } header: { Text("Default amount") } footer: {
                Text("Changing a favourite never changes entries you have already logged.")
            }
            Section {
                Button("Remove favourite", role: .destructive, action: remove).frame(minHeight: 44)
            }
        }
        .amountKeyboardDismissal($editingAmount, placement: Self.donePlacement)
        .navigationTitle("Edit favourite")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel", action: cancel) }
            ToolbarItem(placement: .confirmationAction) { Button("Save", action: save) }
        }
    }
}
