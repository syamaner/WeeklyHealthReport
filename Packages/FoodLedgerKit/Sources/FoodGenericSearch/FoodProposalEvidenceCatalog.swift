import Foundation
import FoodLedgerDomain

/// Provider-specific evidence IDs resolve to immutable captured text. The model
/// selects IDs; it cannot rewrite a quotation or manufacture a source location.
struct FoodProposalEvidenceCatalog {
    static let version = "food-evidence-catalog-v2"
    static let maximumExcerptCharacters = 1400
    private let documents: [CapturedFoodDocument]
    private let entries: [String: [Entry]]

    private struct Entry {
        let id: String
        let block: FoodDocumentBlock
        let quote: String
    }

    init(documents: [CapturedFoodDocument]) throws {
        guard !documents.isEmpty, documents.count <= 3,
              Set(documents.map(\.id)).count == documents.count else { throw GenericFoodProposalError.invalidDocument }
        var result: [String: [Entry]] = [:]
        for document in documents {
            try document.validate()
            var rows: [Entry] = []
            for block in document.blocks {
                for quote in Self.excerpts(block.text) {
                    rows.append(Entry(id: "e\(rows.count + 1)", block: block, quote: quote))
                }
            }
            result[document.id] = rows
        }
        self.documents = documents; entries = result
    }

    func requestDocuments() -> [[String: Any]] {
        documents.map { document in
            ["id": document.id, "url": document.url, "raw_sha256": document.rawSha256,
             "capture_origin": document.captureOrigin, "retrieved_at": document.retrievedAt,
             "evidence_catalog_version": Self.version,
             "blocks": (entries[document.id] ?? []).map { entry in
                 // Long DOM paths remain in the captured document and manifest.
                 // Providers cite IDs; paths add no required response capability.
                 ["id": entry.id, "kind": entry.block.kind, "text": entry.quote]
             }]
        }
    }

    func references(_ value: Any?, documentID: String) throws -> [[String: String]] {
        guard let ids = value as? [String], ids.count <= 40, Set(ids).count == ids.count,
              let offered = entries[documentID] else { throw GenericFoodProposalError.invalidReference }
        return try ids.map { id in
            guard let entry = offered.first(where: { $0.id == id }) else { throw GenericFoodProposalError.invalidReference }
            return ["block_id": entry.block.id, "quote": entry.quote]
        }
    }

    private static func excerpts(_ text: String) -> [String] {
        let characters = Array(text)
        guard characters.count > maximumExcerptCharacters else { return [text] }
        var result: [String] = []
        var start = 0
        while start < characters.count {
            let limit = min(start + maximumExcerptCharacters, characters.count)
            var end = limit
            if end < characters.count {
                // Prefer a word boundary, while keeping progress bounded even for
                // a long unbroken token. Quotes retain their original characters.
                while end > start + maximumExcerptCharacters / 2, !characters[end - 1].isWhitespace { end -= 1 }
                if end == start + maximumExcerptCharacters / 2 { end = limit }
            }
            result.append(String(characters[start..<end]))
            if end == characters.count { break }
            start = end - 100
        }
        return result
    }
}
