import Foundation
import FoodLedgerDomain

public enum InventoryStoreError: Error, Equatable {
    case staleRevision, conflictingRetry, invalidReference, invalidVersion, corruptStore, unsupportedSchema
}

public enum InventoryMutation: Codable, Equatable, Sendable {
    case source(InventorySource)
    case product(InventoryProductVersion)
    case review(InventoryReviewRevision)
}

public struct InventoryCommand: Codable, Equatable, Sendable {
    public let operationID: OperationID
    public let expectedRevision: Int
    public let mutations: [InventoryMutation]

    public init(operationID: OperationID, expectedRevision: Int, mutations: [InventoryMutation]) {
        self.operationID = operationID
        self.expectedRevision = expectedRevision
        self.mutations = mutations
    }
}

public struct InventorySnapshot: Equatable, Sendable {
    public private(set) var revision = 0
    public private(set) var sources: [InventorySource] = []
    public private(set) var productVersions: [InventoryProductVersion] = []
    public private(set) var reviewHistory: [InventoryReviewRevision] = []

    public init() {}

    public var products: [InventoryProductVersion] {
        Dictionary(grouping: productVersions, by: \.productID).values.compactMap {
            $0.max { $0.version < $1.version }
        }.sorted { $0.productID.rawValue < $1.productID.rawValue }
    }

    public func review(sourceID: SHA256Digest, lineNumber: Int) -> InventoryReviewRevision? {
        reviewHistory.last { $0.sourceID == sourceID && $0.lineNumber == lineNumber }
    }

    public func applying(_ command: InventoryCommand, digester: any Digesting) throws -> InventorySnapshot {
        guard command.expectedRevision == revision else { throw InventoryStoreError.staleRevision }
        guard !command.mutations.isEmpty else { throw InventoryStoreError.invalidReference }
        _ = try OperationID(command.operationID.rawValue)
        var next = self
        for mutation in command.mutations {
            switch mutation {
            case let .source(source):
                try source.validate()
                guard try digester.sha256(source.originalBytes) == source.contentID else { throw InventoryStoreError.corruptStore }
                if let existing = next.sources.first(where: { $0.contentID == source.contentID }) {
                    guard existing.originalBytes == source.originalBytes, existing.kind == source.kind else {
                        throw InventoryStoreError.conflictingRetry
                    }
                    // Retain the first immutable extraction on exact-byte reimport.
                } else { next.sources.append(source) }
            case let .product(product):
                try product.validate()
                let previous = next.products.first { $0.productID == product.productID }
                guard product.version == (previous?.version ?? 0) + 1 else { throw InventoryStoreError.invalidVersion }
                next.productVersions.append(product)
            case let .review(review):
                try review.validate()
                guard let source = next.sources.first(where: { $0.contentID == review.sourceID }),
                      let line = source.lines.first(where: { $0.lineNumber == review.lineNumber }) else {
                    throw InventoryStoreError.invalidReference
                }
                let prior = next.review(sourceID: review.sourceID, lineNumber: review.lineNumber)
                guard review.version == (prior?.version ?? 0) + 1 else { throw InventoryStoreError.invalidVersion }
                if review.disposition == .accepted {
                    guard next.productVersions.contains(where: {
                        $0.productID == review.productID && $0.version == review.productVersion
                    }) else { throw InventoryStoreError.invalidReference }
                }
                // Never infer delivery from context/adjustments; require an explicit correction.
                if review.received {
                    guard source.kind == .receipt else { throw InventoryStoreError.invalidReference }
                    if line.kind != .product {
                        _ = try LedgerText(review.acquisitionCorrection, field: "explicit acquisition correction")
                    }
                }
                next.reviewHistory.append(review)
            }
        }
        next.revision += 1
        return next
    }
}

/// Implementations must atomically apply all mutations, detect stale snapshots and
/// return the existing result for an identical operation retry before checking revision.
public protocol InventoryStoring: Sendable {
    func snapshot() throws -> InventorySnapshot
    @discardableResult func commit(_ command: InventoryCommand) throws -> InventorySnapshot
}

public struct ExtractedInventoryDocument: Equatable, Sendable {
    public let originalBytes: Data
    public let text: String
    public let extractionVersion: String

    public init(originalBytes: Data, text: String, extractionVersion: String) {
        self.originalBytes = originalBytes
        self.text = text
        self.extractionVersion = extractionVersion
    }
}

public enum InventoryDocumentFormat: Sendable { case text, pdf }
public enum InventoryDocumentError: Error { case tooLarge, unreadable, emptyOrScanned, unsupported }

public protocol InventoryDocumentExtracting: Sendable {
    func extract(_ bytes: Data, format: InventoryDocumentFormat) throws -> ExtractedInventoryDocument
}

public final class LocalInventoryService: Sendable {
    public let store: any InventoryStoring
    private let digester: any Digesting
    private let clock: any LedgerClock

    public init(store: any InventoryStoring, digester: any Digesting, clock: any LedgerClock) {
        self.store = store
        self.digester = digester
        self.clock = clock
    }

    public func selectionEvidence(
        for product: InventoryProductVersion, evidenceID: EvidenceID, locale: LedgerText
    ) throws -> CaptureEvidence {
        guard try store.snapshot().productVersions.contains(product) else { throw InventoryStoreError.invalidReference }
        struct Selection: Encodable {
            let productID: String
            let version: Int
            let name: String
            let packDescription: String
        }
        let data = try JSONEncoder().encode(Selection(productID: product.productID.rawValue, version: product.version, name: product.name, packDescription: product.packDescription))
        return try CaptureEvidence(
            evidenceID: evidenceID, kind: .manual, capturedAt: clock.now(), locale: locale,
            captureMethod: LedgerText("local-inventory-selection"), captureMethodVersion: LedgerText("inventory-selection-v1"),
            originalPayload: .text(LedgerText(String(decoding: data, as: UTF8.self)))
        )
    }

    public func importDocument(
        _ document: ExtractedInventoryDocument, kind: InventorySourceKind,
        name: String, operationID: OperationID
    ) throws -> InventorySource {
        let identity = try digester.sha256(document.originalBytes)
        let current = try store.snapshot()
        if let existing = current.sources.first(where: { $0.contentID == identity }) {
            guard existing.kind == kind else { throw InventoryStoreError.conflictingRetry }
            return existing
        }
        let source = try InventorySource(
            contentID: identity, kind: kind, displayName: name,
            originalBytes: document.originalBytes, extractedText: document.text,
            extractionVersion: document.extractionVersion, importedAt: clock.now()
        )
        let saved = try store.commit(InventoryCommand(
            operationID: operationID, expectedRevision: current.revision, mutations: [.source(source)]
        ))
        guard let persisted = saved.sources.first(where: { $0.contentID == identity }) else {
            throw InventoryStoreError.corruptStore
        }
        return persisted
    }
}
