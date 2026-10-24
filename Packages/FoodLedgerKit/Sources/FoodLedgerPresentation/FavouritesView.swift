import FoodLedgerApplication
import FoodLedgerDomain
import SwiftUI

/// The Favourites screen's port (consumer-owned). `FavouritesService` conforms below.
public protocol FavouritesManaging: AnyObject {
    func projection() throws -> FavouritesProjection
    /// Nil when the favourite's source can no longer be verified.
    func isEstimate(_ version: FavouriteVersion) -> Bool?
    /// Whether the favourite's count amount means servings of a pasted label (#306).
    func amountIsServings(_ version: FavouriteVersion) -> Bool
    func rename(_ favouriteID: FavouriteID, to label: LedgerText) throws
    func setDefaultAmount(_ favouriteID: FavouriteID, to amount: FavouriteAmount) throws
    func remove(_ favouriteID: FavouriteID) throws
    func arrange(_ items: [QuickAddItem]) throws
    func saveBuiltInWater(label: LedgerText, millilitres: Double) throws
    func removeBuiltInWater() throws
    /// Q7 amendment: re-adds plain water after its item was removed; a no-op when already offered.
    func addWaterToQuickAdd() throws
}

extension FavouritesService: FavouritesManaging {}

/// One row of the Favourites screen.
public struct FavouriteRow: Equatable, Identifiable {
    public let id: String
    public let item: QuickAddItem
    public let title: String
    public let detail: String
    public let isUnverifiable: Bool

    public init(id: String, item: QuickAddItem, title: String, detail: String, isUnverifiable: Bool) {
        self.id = id; self.item = item; self.title = title; self.detail = detail; self.isUnverifiable = isUnverifiable
    }
}

@MainActor
public final class FavouritesViewModel: ObservableObject {
    public enum Phase: Equatable { case loading, loaded, failed(String) }

    @Published public private(set) var phase: Phase = .loading
    @Published public private(set) var today: [FavouriteRow] = []
    @Published public private(set) var others: [FavouriteRow] = []
    @Published public private(set) var changeFailure: String?
    /// "Add Water to quick add" is offered: the water item was removed and none is active.
    @Published public private(set) var canAddWater = false
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
            canAddWater = projection.canAddWater
            phase = .loaded
        } catch is FavouritesProjectionError {
            today = []; others = []; canAddWater = false; phase = .failed(Self.competingMessage)
        } catch {
            today = []; others = []; canAddWater = false; phase = .failed(Self.unreadableMessage)
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
                                detail: QuickAddText.detail(item, isEstimate: estimate, servings: store.amountIsServings(version)),
                                isUnverifiable: estimate == nil)
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

    /// Re-adds plain water to quick add (Q7 amendment, 13 October 2026).
    public func addWater() {
        perform { try store.addWaterToQuickAdd() }
    }

    public static let addWaterTitle = "Add Water to quick add"
    public static let addWaterFooter = "Water was removed from quick add. Adding it back keeps its name and amount."

    /// The removal confirmation. Water says how to add it back, since its item is built in.
    public static func removalTitle(_ row: FavouriteRow) -> String {
        QuickAddText.isPlainWater(row.item) ? "Remove Water from quick add?" : "Remove this favourite?"
    }

    public static func removalMessage(_ row: FavouriteRow) -> String {
        QuickAddText.isPlainWater(row.item)
            ? "Water will no longer appear in quick add. You can add it back in Favourites with \u{201C}\(addWaterTitle)\u{201D}. Water you have already logged stays in your Food Log."
            : "Entries you have already logged stay in your Food Log."
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
    private let createFromLogged: (() -> Void)?
    private let createFromSearch: () -> Void
    private let createFromBarcode: () -> Void
    private let createFromWebLookup: () -> Void
    @State private var editing: FavouriteRow?
    @State private var labelText = ""
    @State private var amountText = ""
    @Environment(\.locale) private var locale

    public init(model: FavouritesViewModel, createFromLogged: (() -> Void)? = nil, createFromSearch: @escaping () -> Void,
                createFromBarcode: @escaping () -> Void, createFromWebLookup: @escaping () -> Void) {
        self.model = model
        self.createFromLogged = createFromLogged
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
            if createFromLogged != nil || showsAddWater {
                Section {
                    if let createFromLogged {
                        createRow(FavouriteFromLoggedView.title, systemImage: "clock.arrow.circlepath", action: createFromLogged,
                                  hint: "Lists foods you have logged recently. Saving one as a favourite logs nothing.")
                    }
                    if showsAddWater {
                        Button { model.addWater() } label: {
                            Label(FavouritesViewModel.addWaterTitle, systemImage: "drop")
                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        }
                        .accessibilityHint("Puts the plain water item back on quick add. Nothing is logged.")
                    }
                } header: { Text("Add a favourite") } footer: {
                    Text(showsAddWater ? Self.addFooter + " " + FavouritesViewModel.addWaterFooter : Self.addFooter)
                }
            }
            Section {
                createRow("Food search", systemImage: "magnifyingglass", action: createFromSearch, hint: Self.logNowHint("food search"))
                createRow("Barcode", systemImage: "barcode.viewfinder", action: createFromBarcode, hint: Self.logNowHint("barcode"))
                createRow("Web lookup", systemImage: "globe", action: createFromWebLookup, hint: Self.logNowHint("web lookup"))
                unavailableRow("Photo of nutrition label")
                unavailableRow("Photo of the food")
            } header: { Text(Self.logNowHeader) } footer: {
                Text(Self.logNowFooter)
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
                                removalTitle: FavouritesViewModel.removalTitle(row),
                                removalMessage: FavouritesViewModel.removalMessage(row),
                                cancel: { editing = nil }, save: { save(row) },
                                remove: { model.remove(row); editing = nil })
            }
        }
    }

    private var showsAddWater: Bool { model.phase == .loaded && model.canAddWater }

    public static let addFooter = "A favourite keeps its source and a default amount, so logging it later takes one step."

    /// The search, barcode and web routes log the food now and save it as a favourite (owner
    /// decision A); Confirm shows When, so the time can be changed before Log.
    public static let logNowHeader = "Log now and save favourite"
    public static let logNowFooter = "These log the food as well as saving it. Check When on the confirmation before you choose Log."

    static func logNowHint(_ route: String) -> String {
        "Opens \(route). Log records the food at the time shown under When and saves it as a favourite."
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

    private func createRow(_ title: String, systemImage: String, action: @escaping () -> Void, hint: String) -> some View {
        Button(action: action) {
            HStack {
                Label(title, systemImage: systemImage).foregroundStyle(.primary)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary).accessibilityHidden(true)
            }.frame(minHeight: 44).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(hint)
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
    var removalTitle = "Remove this favourite?"
    var removalMessage = "Entries you have already logged stay in your Food Log."
    let cancel: () -> Void
    let save: () -> Void
    let remove: () -> Void
    @FocusState private var editingAmount: AmountFieldFocus?
    /// Removal is always confirmed, inside the editor so the alert never races the sheet's dismissal.
    @State private var confirmsRemoval = false

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
                Button("Remove favourite", role: .destructive) { confirmsRemoval = true }.frame(minHeight: 44)
            }
        }
        .amountKeyboardDismissal($editingAmount, placement: Self.donePlacement)
        .navigationTitle("Edit favourite")
        .alert(removalTitle, isPresented: $confirmsRemoval) {
            Button("Remove", role: .destructive, action: remove)
            Button("Cancel", role: .cancel) {}
        } message: { Text(removalMessage) }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel", action: cancel) }
            ToolbarItem(placement: .confirmationAction) { Button("Save", action: save) }
        }
    }
}
