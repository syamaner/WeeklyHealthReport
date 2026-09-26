import Foundation
import FoodLedgerDomain

public struct InventoryLineDraft: Codable, Equatable, Sendable {
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

public struct InventoryReviewCheckpoint: Codable, Sendable {
    public var schemaVersion = 1
    public let activeSourceID: SHA256Digest?
    public let drafts: [String: InventoryLineDraft]
    public let selectedLines: Set<String>
    public let paste: String
    public let sourceKind: InventorySourceKind
    public let pendingCommand: InventoryCommand?

    public init(activeSourceID: SHA256Digest?, drafts: [String: InventoryLineDraft], selectedLines: Set<String>, paste: String, sourceKind: InventorySourceKind, pendingCommand: InventoryCommand?) {
        self.activeSourceID = activeSourceID; self.drafts = drafts; self.selectedLines = selectedLines
        self.paste = paste; self.sourceKind = sourceKind; self.pendingCommand = pendingCommand
    }

    public func validate() throws {
        guard schemaVersion == 1, paste.count <= 100_000, drafts.count <= 10_000, selectedLines.count <= 10_000 else {
            throw InventoryStoreError.corruptStore
        }
    }
}

public protocol InventoryReviewCheckpointStoring: Sendable {
    func load() throws -> InventoryReviewCheckpoint?
    func save(_ checkpoint: InventoryReviewCheckpoint) throws
}
