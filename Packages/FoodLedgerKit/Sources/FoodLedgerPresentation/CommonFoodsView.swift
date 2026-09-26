import FoodLedgerDomain
import SwiftUI

public struct CommonFoodsView: View {
    @ObservedObject private var model: LocalInventoryViewModel
    private let addToReview: (InventoryProductVersion) -> Void
    @State private var editing: InventoryProductVersion?
    @State private var showsEditor = false
    @State private var name = ""
    @State private var aliases = ""
    @State private var portion = ""
    @State private var unit: QuantityUnit = .grams
    @State private var favourite = true

    public init(model: LocalInventoryViewModel, addToReview: @escaping (InventoryProductVersion) -> Void) {
        self.model = model; self.addToReview = addToReview
    }

    public var body: some View {
        List {
            Section {
                Text("Save usual foods and portions. Quick-add opens a review.")
                Button("Add common food") { edit(nil) }
                TextField("Search names and aliases", text: $model.searchQuery)
            }
            Section("Favourites") { products(model.products.filter(\.isFavourite)) }
            Section("Other saved foods") { products(model.products.filter { !$0.isFavourite }) }
            if let message = model.message {
                Section("Status") {
                    Text(message)
                    if model.pendingCommand != nil { Button("Retry same save") { model.retryPending() } }
                    else { Button("Reload saved foods") { model.reload() } }
                }
            }
            if let message = model.checkpointMessage {
                Section("Review progress") {
                    Text(message)
                    Button("Retry saving review progress") { model.retryCheckpoint() }
                }
            }
            if model.pendingCommand != nil && model.message == nil {
                Section("Pending save") { Button("Retry same save") { model.retryPending() } }
            }
        }
        .navigationTitle("Common foods")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .sheet(isPresented: $showsEditor) {
            NavigationStack {
                Form {
                    VStack(alignment: .leading) {
                        Text("Food name").font(.caption)
                        TextField("Food name", text: $name)
                    }
                    VStack(alignment: .leading) {
                        Text("Aliases, comma separated").font(.caption)
                        TextField("Aliases, comma separated", text: $aliases)
                    }
                    Toggle("Favourite", isOn: $favourite)
                    VStack(alignment: .leading) {
                        Text("Usual portion (optional)").font(.caption)
                        TextField("Usual portion (optional)", text: $portion)
                    }
                    Picker("Unit", selection: $unit) {
                        Text("g").tag(QuantityUnit.grams)
                        Text("mL").tag(QuantityUnit.millilitres)
                        Text("count").tag(QuantityUnit.count)
                    }
                    Text("A usual portion is a suggestion. It does not record a purchase, remaining stock or food consumed.")
                    if let message = model.message { Text(message) }
                    if model.pendingCommand != nil {
                        Button("Retry same save") { if model.retryPending() { showsEditor = false } }
                    } else {
                        Button("Save common food") {
                            if model.saveCommonFood(previous: editing, name: name, aliases: aliases, portion: portion, unit: unit, favourite: favourite) { showsEditor = false }
                        }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                .navigationTitle(editing == nil ? "New common food" : "Edit common food")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showsEditor = false } } }
            }
        }
    }

    @ViewBuilder private func products(_ values: [InventoryProductVersion]) -> some View {
        if values.isEmpty { Text("No foods here yet.").foregroundStyle(.secondary) }
        ForEach(values, id: \.productID) { product in
            VStack(alignment: .leading, spacing: 8) {
                Text(product.name).font(.headline)
                if !product.aliases.isEmpty { Text(product.aliases.joined(separator: ", ")).font(.caption) }
                if let amount = product.usualPortion { Text("Usual: \(amount.value.formatted()) \(amount.unit.rawValue)").font(.caption) }
                Button("Quick-add for review") { addToReview(product) }
                Button("Edit") { edit(product) }
            }
            .buttonStyle(.borderless)
        }
    }

    private func edit(_ product: InventoryProductVersion?) {
        guard model.pendingCommand == nil else { return }
        editing = product; name = product?.name ?? ""; aliases = product?.aliases.joined(separator: ", ") ?? ""
        portion = product?.usualPortion.map { String($0.value) } ?? ""
        unit = product?.usualPortion?.unit ?? .grams; favourite = product?.isFavourite ?? true
        showsEditor = true
    }
}
