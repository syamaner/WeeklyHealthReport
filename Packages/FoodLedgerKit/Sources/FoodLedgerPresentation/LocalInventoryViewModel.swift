import FoodLedgerApplication
import FoodLedgerDomain
import SwiftUI

public struct InventoryLineDraft: Equatable {
    public var description: String
    public var selectedProductID: InventoryProductID?
    public var createProduct = false
    public var editProduct = false
    public var category = ""
    public var aliases = ""
    public var packDescription = ""
    public var productNotes = ""
    public var purchaseCount = ""
    public var unitsPerPack = ""
    public var packAmount = ""
    public var packUnit: QuantityUnit = .grams
    public var received = false
    public var acquisitionCorrection = ""
    public var note = ""
    public var remaining = ""
    public var remainingUnit: QuantityUnit = .grams
    public var assertionDate = Date(timeIntervalSince1970: 0)

    public init(line: ReceiptLineProposal) {
        description = line.description
        purchaseCount = line.purchaseCount.map { String($0) } ?? ""
        unitsPerPack = line.unitsPerPack.map { String($0) } ?? ""
        packAmount = line.packAmount.map { String($0) } ?? ""
        packUnit = line.packUnit ?? .grams
        packDescription = line.packAmount.map { "\($0) \(line.packUnit?.rawValue ?? "")" } ?? ""
    }
}

@MainActor
public final class LocalInventoryViewModel: ObservableObject {
    @Published public private(set) var snapshot = InventorySnapshot()
    @Published public var activeSourceID: SHA256Digest?
    @Published public private(set) var drafts: [String: InventoryLineDraft] = [:]
    @Published public var selectedLines: Set<String> = []
    @Published public var paste = ""
    @Published public var sourceKind: InventorySourceKind = .receipt
    @Published public var searchQuery = ""
    @Published public private(set) var message: String?
    @Published public private(set) var pendingCommand: InventoryCommand?
    private let service: LocalInventoryService
    private let ids: any LedgerIDGenerating
    private let clock: any LedgerClock

    public init(service: LocalInventoryService, ids: any LedgerIDGenerating, clock: any LedgerClock) throws {
        self.service = service
        self.ids = ids
        self.clock = clock
        snapshot = try service.store.snapshot()
        activeSourceID = snapshot.sources.last?.contentID
    }

    public var activeSource: InventorySource? { snapshot.sources.first { $0.contentID == activeSourceID } }
    public var products: [InventoryProductVersion] {
        searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? snapshot.products
            : InventoryMatcher.matches(searchQuery, products: snapshot.products).map(\.product)
    }

    public func draft(for line: ReceiptLineProposal) -> InventoryLineDraft {
        guard let source = activeSource else { return InventoryLineDraft(line: line) }
        if let draft = drafts[source.lineKey(line.lineNumber)] { return draft }
        var draft = InventoryLineDraft(line: line)
        draft.assertionDate = clock.now()
        if let saved = snapshot.review(sourceID: source.contentID, lineNumber: line.lineNumber), saved.disposition == .accepted {
            draft.description = saved.correctedDescription
            draft.selectedProductID = saved.productID
            if let product = snapshot.products.first(where: { $0.productID == saved.productID }) {
                Self.copyDetails(product, into: &draft)
            }
            draft.purchaseCount = saved.purchaseCount.map { String($0) } ?? ""
            draft.unitsPerPack = saved.unitsPerPack.map { String($0) } ?? ""
            draft.packAmount = saved.packAmount.map { String($0.value) } ?? ""
            draft.packUnit = saved.packAmount?.unit ?? .grams
            draft.received = saved.received
            draft.acquisitionCorrection = saved.acquisitionCorrection
            draft.note = saved.note
        }
        return draft
    }

    public func update(_ draft: InventoryLineDraft, line: ReceiptLineProposal) {
        guard pendingCommand == nil, let source = activeSource else { return }
        var next = draft
        if self.draft(for: line).description != draft.description {
            next.selectedProductID = nil
            next.createProduct = false
            next.editProduct = false
        }
        drafts[source.lineKey(line.lineNumber)] = next
    }

    public func matches(for line: ReceiptLineProposal) -> [InventoryMatch] {
        InventoryMatcher.matches(draft(for: line).description, products: snapshot.products)
    }

    public func select(_ product: InventoryProductVersion, for line: ReceiptLineProposal) {
        var draft = draft(for: line)
        draft.selectedProductID = product.productID
        draft.createProduct = false
        draft.editProduct = false
        Self.copyDetails(product, into: &draft)
        update(draft, line: line)
    }

    private static func copyDetails(_ product: InventoryProductVersion, into draft: inout InventoryLineDraft) {
        draft.category = product.category
        draft.aliases = product.aliases.joined(separator: ", ")
        draft.packDescription = product.packDescription
        draft.productNotes = product.notes
        draft.remaining = product.remaining.map { String($0.amount.value) } ?? ""
        draft.remainingUnit = product.remaining?.amount.unit ?? .grams
        if let remaining = product.remaining { draft.assertionDate = remaining.assertedAt }
    }

    public func importPaste() {
        importDocument(ExtractedInventoryDocument(originalBytes: Data(paste.utf8), text: paste, extractionVersion: "local-utf8-v1"), name: "Pasted \(sourceKind.rawValue)")
    }

    public func importDocument(_ document: ExtractedInventoryDocument, name: String) {
        guard pendingCommand == nil else { return }
        do {
            let source = try service.importDocument(document, kind: sourceKind, name: name, operationID: ids.makeID(OperationTag.self))
            snapshot = try service.store.snapshot()
            activeSourceID = source.contentID
            selectedLines = []
            message = "Source saved locally. Review each proposal; nothing has been accepted or logged."
        } catch { report(error) }
    }

    public func report(_ error: Error) {
        if error is InventoryDocumentError {
            message = "Could not import this file. Use a UTF-8 text file or a text-bearing PDF under 5 MB (up to 100 pages). Scanned or empty pages are unsupported."
        } else {
            message = "Could not complete the change. Check the values or reload the saved inventory. Nothing is automatically accepted."
        }
    }

    public func reload() {
        guard pendingCommand == nil else { return }
        do {
            snapshot = try service.store.snapshot()
            drafts = [:]
            message = "Saved inventory reloaded; unsaved edits cleared."
        } catch { report(error) }
    }

    @discardableResult
    public func save(_ line: ReceiptLineProposal, disposition: InventoryReviewDisposition) -> Bool {
        guard pendingCommand == nil, let source = activeSource else { return false }
        do {
            let draft = draft(for: line)
            var mutations: [InventoryMutation] = []
            var product: InventoryProductVersion?
            if disposition == .accepted {
                if draft.createProduct || draft.editProduct {
                    let previous = draft.editProduct ? snapshot.products.first { $0.productID == draft.selectedProductID } : nil
                    if draft.editProduct && previous == nil { throw InventoryStoreError.invalidReference }
                    let amount = try Self.amount(draft.remaining, unit: draft.remainingUnit, allowsZero: true)
                    let remaining = try amount.map { try InventoryRemainingAssertion(amount: $0, assertedAt: draft.assertionDate) }
                    let created = try InventoryProductVersion(
                        productID: previous?.productID ?? ids.makeID(InventoryProductTag.self), version: (previous?.version ?? 0) + 1,
                        name: previous?.name ?? draft.description, category: draft.category,
                        aliases: Self.aliases(draft.aliases), packDescription: draft.packDescription,
                        remaining: remaining, notes: draft.productNotes, updatedAt: clock.now()
                    )
                    product = created
                    mutations.append(.product(created))
                } else {
                    product = snapshot.products.first { $0.productID == draft.selectedProductID }
                    guard product != nil else { message = "Choose a catalogue product or explicitly create a new one first."; return false }
                }
            }
            let accepted = disposition == .accepted
            let review = try InventoryReviewRevision(
                sourceID: source.contentID, lineNumber: line.lineNumber,
                version: (snapshot.review(sourceID: source.contentID, lineNumber: line.lineNumber)?.version ?? 0) + 1,
                disposition: disposition, productID: product?.productID, productVersion: product?.version,
                correctedDescription: accepted ? draft.description : "",
                purchaseCount: accepted ? try Self.positive(draft.purchaseCount) : nil,
                unitsPerPack: accepted ? try Self.positive(draft.unitsPerPack) : nil,
                packAmount: accepted ? try Self.amount(draft.packAmount, unit: draft.packUnit, allowsZero: false) : nil,
                received: accepted && draft.received,
                acquisitionCorrection: accepted && draft.received ? draft.acquisitionCorrection : "",
                note: draft.note, reviewedAt: clock.now()
            )
            mutations.append(.review(review))
            pendingCommand = InventoryCommand(operationID: try ids.makeID(OperationTag.self), expectedRevision: snapshot.revision, mutations: mutations)
            return retryPending()
        } catch { report(error); return false }
    }

    @discardableResult
    public func retryPending() -> Bool {
        guard let pendingCommand else { return false }
        do {
            snapshot = try service.store.commit(pendingCommand)
            for mutation in pendingCommand.mutations {
                if case let .review(review) = mutation {
                    drafts[review.lineKey] = nil
                    selectedLines.remove(review.lineKey)
                }
            }
            self.pendingCommand = nil
            message = "Saved locally. No food consumption or stock depletion was recorded."
            return true
        } catch InventoryStoreError.staleRevision {
            self.pendingCommand = nil
            message = "Inventory changed since this review. Reload the saved inventory before retrying your correction. This change was not saved."
            return false
        } catch is FoodLedgerValidationError {
            self.pendingCommand = nil
            message = "Review was not saved. Check required correction explanations, dates and quantities, then try again."
            return false
        } catch InventoryStoreError.invalidReference {
            self.pendingCommand = nil
            message = "Review was not saved. Check the selected product and source; a catalogue is not a delivered purchase."
            return false
        } catch InventoryStoreError.invalidVersion {
            self.pendingCommand = nil
            message = "Review was not saved. Reload the latest inventory revision before correcting it."
            return false
        } catch {
            message = "Save failed or its result is uncertain. Retry the same change before editing; this prevents duplicates."
            return false
        }
    }

    public func acceptSelected() {
        guard let source = activeSource, pendingCommand == nil else { return }
        let chosen = source.lines.filter { selectedLines.contains(source.lineKey($0.lineNumber)) }
        var saved = 0
        for line in chosen {
            guard save(line, disposition: .accepted) else { break }
            saved += 1
        }
        message = "Saved \(saved) of \(chosen.count) selected rows. \(saved < chosen.count ? "Remaining rows need attention; no failed row was reported as saved." : "No food was logged.")"
    }

    private static func aliases(_ value: String) -> [String] {
        value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
    private static func positive(_ value: String) throws -> Double? {
        guard !value.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        guard let number = FoodListParser.number(value) else { throw FoodLedgerValidationError.nonPositive("amount") }
        return number
    }
    private static func amount(_ value: String, unit: QuantityUnit, allowsZero: Bool) throws -> InventoryAmount? {
        if allowsZero, Double(value.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")) == 0 {
            return try InventoryAmount(value: 0, unit: unit)
        }
        return try positive(value).map { try InventoryAmount(value: $0, unit: unit) }
    }
}
