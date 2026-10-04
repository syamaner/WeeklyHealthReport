import CryptoKit
import Foundation
import PDFKit
import FoodLedgerApplication
import FoodLedgerDomain

/// Text projection only. PDFKit objects stay inside infrastructure; no view,
/// document actions, attachments, OCR or inferred table/unit relationships.
public enum GenericFoodPDFProjector {
    public static let version = "swift-food-pdf-rows-v1"
    public static let maximumPages = 10
    public static let maximumBytes = 1_000_000

    public static func project(_ raw: Data, url: URL, retrievedAt: Date,
                               origin: String = "publisher_http") throws -> CapturedFoodDocument {
        try Task.checkCancellation()
        guard raw.count <= maximumBytes else { throw FoodSourceAcquisitionError.responseTooLarge }
        guard !raw.isEmpty,
              raw.starts(with: Data("%PDF-".utf8)), let document = PDFDocument(data: raw),
              !document.isEncrypted, !document.isLocked, document.allowsCopying,
              document.pageCount > 0 else { throw FoodSourceAcquisitionError.unsupportedContent }
        guard document.pageCount <= maximumPages else { throw FoodSourceAcquisitionError.responseTooLarge }
        var blocks: [FoodDocumentBlock] = []
        var total = 0
        for pageIndex in 0..<document.pageCount {
            try Task.checkCancellation()
            guard let page = document.page(at: pageIndex), page.numberOfCharacters > 0 else {
                // Do not call a mixed text/scan document complete after skipping a page.
                throw FoodSourceAcquisitionError.unsupportedContent
            }
            guard page.numberOfCharacters <= 30_000 - total else { throw FoodSourceAcquisitionError.responseTooLarge }
            guard let selection = page.selection(for: NSRange(location: 0, length: page.numberOfCharacters)) else {
                throw FoodSourceAcquisitionError.unsupportedContent
            }
            let before = blocks.count
            struct Fragment { let text: String; let bounds: CGRect }
            var fragments: [Fragment] = []
            for line in selection.selectionsByLine() {
                try Task.checkCancellation()
                let text = (line.string ?? "").replacingOccurrences(of: "\u{fffc}", with: " ")
                    .split(whereSeparator: \.isWhitespace).joined(separator: " ")
                if text.isEmpty { continue }
                let bounds = line.bounds(for: page)
                guard [bounds.minX, bounds.minY, bounds.width, bounds.height].allSatisfy(\.isFinite),
                      !text.contains("\u{fffd}") else { throw FoodSourceAcquisitionError.unsupportedContent }
                fragments.append(.init(text: text, bounds: bounds))
                guard fragments.count <= 5000 else { throw FoodSourceAcquisitionError.responseTooLarge }
            }
            // PDFKit can return one line per table cell. Join only fragments on
            // the same physical baseline, preserving column order and separators.
            // This is layout projection, not inference of units or table meaning.
            fragments.sort { $0.bounds.midY != $1.bounds.midY
                ? $0.bounds.midY > $1.bounds.midY : $0.bounds.minX < $1.bounds.minX }
            var rows: [[Fragment]] = []
            for fragment in fragments {
                if let last = rows.last, let first = last.first, abs(first.bounds.midY - fragment.bounds.midY) <= 1 {
                    rows[rows.count - 1].append(fragment)
                } else { rows.append([fragment]) }
            }
            for row in rows {
                try Task.checkCancellation()
                let ordered = row.sorted { $0.bounds.minX < $1.bounds.minX }
                let text = ordered.map(\.text).joined(separator: " | ")
                let bounds = ordered.dropFirst().reduce(ordered[0].bounds) { $0.union($1.bounds) }
                total += text.count
                guard total <= 30_000, blocks.count < 512 else { throw FoodSourceAcquisitionError.responseTooLarge }
                let rectangle = [bounds.minX, bounds.minY, bounds.width, bounds.height]
                    .map { String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), Double($0)) }.joined(separator: ",")
                blocks.append(.init(id: "b\(blocks.count + 1)", kind: "pdf_row", text: text,
                    locator: "page:\(pageIndex + 1);rect:\(rectangle);projection:\(version)"))
            }
            guard blocks.count > before else { throw FoodSourceAcquisitionError.unsupportedContent }
        }
        let hash = SHA256.hash(data: raw).map { String(format: "%02x", $0) }.joined()
        return try CapturedFoodDocument(id: "doc_" + hash.prefix(16), url: url.absoluteString,
            rawSha256: hash, captureOrigin: origin, retrievedAt: ISO8601DateFormatter().string(from: retrievedAt), blocks: blocks)
    }
}
