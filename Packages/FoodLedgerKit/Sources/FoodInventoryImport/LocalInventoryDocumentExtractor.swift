import Foundation
import PDFKit
import FoodLedgerApplication
import FoodLedgerDomain

public struct LocalInventoryDocumentExtractor: InventoryDocumentExtracting {
    public init() {}

    public func extract(_ bytes: Data, format: InventoryDocumentFormat) throws -> ExtractedInventoryDocument {
        guard !bytes.isEmpty else { throw InventoryDocumentError.unreadable }
        guard bytes.count <= 5_000_000 else { throw InventoryDocumentError.tooLarge }
        let text: String
        let version: String
        switch format {
        case .text:
            guard let decoded = String(data: bytes, encoding: .utf8) else { throw InventoryDocumentError.unreadable }
            text = decoded.hasPrefix("\u{feff}") ? String(decoded.dropFirst()) : decoded
            version = "local-utf8-v1"
        case .pdf:
            guard let document = PDFDocument(data: bytes), !document.isLocked else { throw InventoryDocumentError.unreadable }
            guard document.pageCount > 0, document.pageCount <= 100 else { throw InventoryDocumentError.tooLarge }
            var pages: [String] = []
            for index in 0..<document.pageCount {
                guard let page = document.page(at: index), let content = page.string,
                      !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    // Do not silently drop an image-only page from a mixed document.
                    throw InventoryDocumentError.emptyOrScanned
                }
                pages.append(content)
                guard pages.reduce(0, { $0 + $1.count + 1 }) <= ReceiptParser.maximumCharacters else {
                    throw InventoryDocumentError.tooLarge
                }
            }
            text = pages.joined(separator: "\n")
            version = "local-pdfkit-text-v1"
        }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw InventoryDocumentError.emptyOrScanned }
        guard text.count <= ReceiptParser.maximumCharacters else { throw InventoryDocumentError.tooLarge }
        return ExtractedInventoryDocument(originalBytes: bytes, text: text, extractionVersion: version)
    }
}
