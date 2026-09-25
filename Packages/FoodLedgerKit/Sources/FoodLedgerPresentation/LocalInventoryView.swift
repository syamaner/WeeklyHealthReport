import FoodLedgerApplication
import FoodLedgerDomain
import SwiftUI

public struct LocalInventoryView: View {
    @ObservedObject private var model: LocalInventoryViewModel
    private let chooseFile: () -> Void
    private let searchFood: (InventoryProductVersion) -> Void

    public init(model: LocalInventoryViewModel, chooseFile: @escaping () -> Void, searchFood: @escaping (InventoryProductVersion) -> Void) {
        self.model = model
        self.chooseFile = chooseFile
        self.searchFood = searchFood
    }

    public var body: some View {
        Form {
            Section("Local receipt review") {
                Text("Optional inventory evidence. No Google account is needed. Purchases are not food consumed, and remaining stock is unknown unless explicitly confirmed.")
                Picker("Source", selection: $model.sourceKind) {
                    Text("Receipt").tag(InventorySourceKind.receipt)
                    Text("Catalogue").tag(InventorySourceKind.catalogue)
                }
                TextEditor(text: $model.paste).frame(minHeight: 100)
                    .accessibilityLabel("Paste receipt or catalogue text")
                Button("Import pasted text") { model.importPaste() }
                Button("Choose local text or PDF", action: chooseFile)
                Text("UTF-8 text or text-bearing PDF, up to 5 MB. Scanned pages are unsupported. Original sources are kept unchanged locally.")
                    .font(.caption)
            }.disabled(model.pendingCommand != nil)

            if let message = model.message {
                Section("Status") {
                    Text(message).accessibilityIdentifier("inventory.status")
                    if model.pendingCommand != nil { Button("Retry same save") { model.retryPending() } }
                    else { Button("Reload saved inventory (discard unsaved edits)") { model.reload() } }
                }
            }

            if !model.snapshot.sources.isEmpty {
                Section("Saved sources") {
                    Picker("Review source", selection: $model.activeSourceID) {
                        ForEach(model.snapshot.sources, id: \.contentID) { source in
                            Text("\(source.displayName) · \(source.kind.rawValue)").tag(Optional(source.contentID))
                        }
                    }.disabled(model.pendingCommand != nil)
                    if let source = model.activeSource {
                        let reviewed = source.lines.filter { model.snapshot.review(sourceID: source.contentID, lineNumber: $0.lineNumber) != nil }.count
                        Text("\(reviewed) of \(source.lines.count) rows have saved decisions. Deferred rows may still need attention.")
                        Text("Source ID: \(source.contentID.value.prefix(12))").font(.caption)
                        Button("Accept selected rows") { model.acceptSelected() }
                            .disabled(model.selectedLines.isEmpty || model.pendingCommand != nil)
                        Text("Only explicitly selected rows are attempted. Each needs a chosen or explicitly created product.").font(.caption)
                    }
                }
                if let source = model.activeSource {
                    Section("Review each original line") {
                        ForEach(source.lines, id: \.lineNumber) { line in
                            DisclosureGroup {
                                reviewEditor(line, source: source)
                            } label: {
                                VStack(alignment: .leading) {
                                    Text("\(line.lineNumber). \(line.original)")
                                    let saved = model.snapshot.review(sourceID: source.contentID, lineNumber: line.lineNumber)
                                    Text(saved.map { "\($0.disposition.rawValue.capitalized) · revision \($0.version)" } ?? "Needs review")
                                        .font(.caption)
                                }
                            }
                        }
                    }
                }
            }

            Section("Search reviewed inventory") {
                TextField("Product, alias or category", text: $model.searchQuery)
                if model.products.isEmpty { Text("No matching reviewed products.").foregroundStyle(.secondary) }
                ForEach(model.products, id: \.productID) { product in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(product.name).font(.headline)
                        Text([product.category, product.packDescription].filter { !$0.isEmpty }.joined(separator: " · "))
                        if let remaining = product.remaining {
                            Text("Confirmed remaining: \(remaining.amount.value.formatted()) \(remaining.amount.unit.rawValue), as of \(remaining.assertedAt.formatted(date: .abbreviated, time: .omitted))")
                        } else { Text("Remaining stock unknown") }
                        let rows = model.snapshot.sources.flatMap { source in source.lines.compactMap {
                            model.snapshot.review(sourceID: source.contentID, lineNumber: $0.lineNumber)
                        }}.filter { $0.productID == product.productID && $0.disposition == .accepted }
                        Text("\(rows.filter(\.received).count) received receipt rows; this is not a stock balance.").font(.caption)
                        Button("Use name in food search") { searchFood(product) }
                    }
                }
                Text("Food logging remains a separate confirmation. No automatic stock depletion. Common-items/favourites management is a later feature.").font(.caption)
            }
        }
        .navigationTitle("Receipt review")
    }

    @ViewBuilder
    private func reviewEditor(_ line: ReceiptLineProposal, source: InventorySource) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Original: \(line.original)").textSelection(.enabled)
            if let price = line.priceText { Text("Printed price: \(price) — not a quantity") }
            ForEach(line.notices, id: \.self) { Text($0).font(.caption) }
            Toggle("Select for batch acceptance", isOn: Binding(
                get: { model.selectedLines.contains(source.lineKey(line.lineNumber)) },
                set: { if $0 { model.selectedLines.insert(source.lineKey(line.lineNumber)) } else { model.selectedLines.remove(source.lineKey(line.lineNumber)) } }
            ))
            TextField("Corrected product description", text: binding(line, \.description))
            Text("Changing this description clears the previous product choice.").font(.caption)

            ForEach(model.matches(for: line), id: \.product.productID) { match in
                Button {
                    model.select(match.product, for: line)
                } label: {
                    VStack(alignment: .leading) {
                        Text("Choose \(match.product.name)")
                        Text(match.product.packDescription).font(.caption)
                        Text(match.differences.joined(separator: " ")).font(.caption)
                    }
                }
            }
            if let chosen = model.snapshot.products.first(where: { $0.productID == model.draft(for: line).selectedProductID }) {
                Text("Chosen: \(chosen.name) · \(chosen.packDescription)").font(.headline)
                Toggle("Correct this catalogue entry's details", isOn: binding(line, \.editProduct))
            }
            Toggle("Create a new catalogue product from this description", isOn: Binding(
                get: { model.draft(for: line).createProduct },
                set: {
                    var draft = model.draft(for: line)
                    draft.createProduct = $0
                    draft.editProduct = false
                    draft.selectedProductID = nil
                    model.update(draft, line: line)
                }
            ))
            if model.draft(for: line).createProduct || model.draft(for: line).editProduct {
                TextField("Category (optional)", text: binding(line, \.category))
                TextField("Confirmed aliases, comma separated (optional)", text: binding(line, \.aliases))
                TextField("Pack description (optional)", text: binding(line, \.packDescription))
                TextField("Catalogue notes (optional)", text: binding(line, \.productNotes))
                TextField("Explicitly confirmed amount left (blank = unknown)", text: binding(line, \.remaining))
                if !model.draft(for: line).remaining.isEmpty {
                    Picker("Remaining unit", selection: binding(line, \.remainingUnit)) {
                        Text("g").tag(QuantityUnit.grams)
                        Text("ml").tag(QuantityUnit.millilitres)
                        Text("count").tag(QuantityUnit.count)
                    }
                    DatePicker("Amount-left assertion date", selection: binding(line, \.assertionDate), displayedComponents: .date)
                    Text("Only enter an amount you have checked; the receipt does not establish what is left.").font(.caption)
                }
            }
            TextField("Number purchased (blank = unknown)", text: binding(line, \.purchaseCount))
            TextField("Units inside each pack (blank = unknown)", text: binding(line, \.unitsPerPack))
            TextField("Amount in each unit/pack (blank = unknown)", text: binding(line, \.packAmount))
            Picker("Pack amount unit", selection: binding(line, \.packUnit)) {
                Text("g").tag(QuantityUnit.grams)
                Text("ml").tag(QuantityUnit.millilitres)
                Text("count").tag(QuantityUnit.count)
            }
            if source.kind == .receipt {
                Toggle("I confirm this purchase was received", isOn: binding(line, \.received))
                if line.kind != .product {
                    Text("This looks like context, an order, adjustment or unit-price line. It does not establish receipt of goods. Leave unconfirmed unless you can correct that interpretation.").font(.caption)
                    if model.draft(for: line).received {
                        TextField("Required: explain the corrected delivered purchase", text: binding(line, \.acquisitionCorrection))
                    }
                }
            } else {
                Text("A catalogue row cannot establish received stock.").font(.caption)
            }
            TextField("Review note (optional)", text: binding(line, \.note))
            HStack {
                Button("Accept") { model.save(line, disposition: .accepted) }
                Button("Defer / undo acceptance") { model.save(line, disposition: .deferred) }
                Button("Decline") { model.save(line, disposition: .declined) }
            }.buttonStyle(.bordered)
            Text("Undo acceptance removes this row from received acquisitions but keeps catalogue entries and review history. Correct catalogue details explicitly above.").font(.caption)
        }.disabled(model.pendingCommand != nil)
    }

    private func binding<Value>(_ line: ReceiptLineProposal, _ keyPath: WritableKeyPath<InventoryLineDraft, Value>) -> Binding<Value> {
        Binding(get: { model.draft(for: line)[keyPath: keyPath] }, set: { value in
            var draft = model.draft(for: line)
            draft[keyPath: keyPath] = value
            model.update(draft, line: line)
        })
    }
}
