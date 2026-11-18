import CryptoKit
import Foundation
import SwiftSoup
import FoodLedgerApplication
import FoodLedgerDomain

/// Format-based capture: DOM text, table rows and JSON-LD, without executing page
/// content. Block coordinates belong to this projection version, not rendered CSS.
///
/// Part-read pages (#508 phase 3, docs/web-lookup-part-read-phase3-gate.md): without permission an
/// HTML page over `FoodDocumentBounds.current` is refused at the bound, as before. With permission the
/// walk continues to the end and `FoodDocumentBlockSelection` chooses the kept blocks; every error after
/// the bound other than cancellation is `responseTooLarge`. Whole pages are unchanged byte for byte.
public enum GenericFoodDocumentProjector {
    public static let version = "swift-food-document-blocks-v6"
    public static let maximumBytes = 3_000_000
    private static let ignored: Set<String> = ["style", "template"]
    private static let atomic: Set<String> = ["h1", "h2", "h3", "h4", "h5", "h6", "p", "li", "tr", "caption", "dt", "dd", "div"]

    public static func project(_ raw: Data, url: URL, mediaType: String, retrievedAt: Date,
                               origin: String = "publisher_http",
                               partRead: FoodDocumentPartReadPermission = .refused) throws -> CapturedFoodDocument {
        try project(raw, url: url, mediaType: mediaType, retrievedAt: retrievedAt, origin: origin, partRead: partRead,
                    boundPassed: {}, selectionStarts: {})
    }

    /// Test seams for cancellation: `boundPassed` runs once when a permitted walk passes the bound,
    /// `selectionStarts` once the walk has finished, just before selection.
    static func project(_ raw: Data, url: URL, mediaType: String, retrievedAt: Date, origin: String,
                        partRead: FoodDocumentPartReadPermission, boundPassed: () -> Void,
                        selectionStarts: () -> Void) throws -> CapturedFoodDocument {
        try Task.checkCancellation()
        if mediaType == "application/pdf" {
            return try GenericFoodPDFProjector.project(raw, url: url, retrievedAt: retrievedAt, origin: origin)
        }
        guard !raw.isEmpty else { throw GenericFoodProposalError.invalidDocument }
        guard raw.count <= maximumBytes else { throw FoodSourceAcquisitionError.responseTooLarge }
        guard let source = String(data: raw, encoding: .utf8) else { throw FoodSourceAcquisitionError.unsupportedContent }
        struct Emitted { let kind: String; let text: String; let path: String; let unit: String? }
        var emitted: [Emitted] = []
        var total = 0
        var passedBound = false
        let selects = partRead == .permitted && mediaType == "text/html"
        func emit(_ kind: String, _ text: String, _ locator: String, unit: String? = nil) throws {
            let value = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            if value.isEmpty { return }
            total += value.count
            if !passedBound, total > FoodDocumentBounds.current.characters || emitted.count >= FoodDocumentBounds.current.blocks {
                guard selects else { throw FoodSourceAcquisitionError.responseTooLarge }
                passedBound = true
                boundPassed()
                try Task.checkCancellation()
            }
            emitted.append(.init(kind: kind, text: value, path: locator, unit: unit))
        }
        if mediaType == "text/plain" {
            for (index, line) in source.components(separatedBy: .newlines).enumerated() {
                try emit("line", line, "line:\(index + 1)")
            }
        } else if mediaType == "text/html" {
            let document = try SwiftSoup.parseHTML(source)
            var nodeCount = 0
            func checkTree(_ node: Node, depth: Int) throws {
                nodeCount += 1
                guard depth <= 64, nodeCount <= 50_000 else { throw FoodSourceAcquisitionError.responseTooLarge }
                try Task.checkCancellation()
                for child in node.getChildNodes() { try checkTree(child, depth: depth + 1) }
            }
            try checkTree(document, depth: 0)
            func text(_ node: Node) -> String {
                if let value = node as? TextNode { return value.getWholeText() }
                guard let element = node as? Element, !ignored.contains(element.tagName()), element.tagName() != "script" else { return "" }
                if element.tagName() == "tr" {
                    // Adjacent value and unit cells are explicit source text,
                    // not a unit inferred from a column header. Keep every other
                    // cell boundary and never join across rows.
                    let units: Set<String> = ["g", "mg", "ml", "kcal", "kj", "公克", "克", "毫克", "毫升", "大卡", "千卡"]
                    var cells: [String] = []
                    for cell in element.children().array() where ["td", "th"].contains(cell.tagName()) {
                        let value = text(cell).split(whereSeparator: \.isWhitespace).joined(separator: " ")
                        if units.contains(value.lowercased()), let previous = cells.last,
                           previous.range(of: #"^[<>≤≥~≈+\-]?\s*[0-9]+(?:\.[0-9]+)?$"#, options: .regularExpression) != nil {
                            cells[cells.count - 1] += " " + value
                        } else { cells.append(value) }
                    }
                    return cells.joined(separator: " | ")
                }
                return element.getChildNodes().map(text).joined(separator: " ")
            }
            func hasAtomicDescendant(_ element: Element) -> Bool {
                element.children().array().contains { child in
                    if ignored.contains(child.tagName()) { return false }
                    if child.tagName() == "script" { return (try? child.attr("type").lowercased()) == "application/ld+json" }
                    return atomic.contains(child.tagName()) || hasAtomicDescendant(child)
                }
            }
            func hasNestedRowOrStructuredData(_ element: Element) -> Bool {
                element.children().array().contains { child in
                    if child.tagName() == "tr" { return true }
                    if child.tagName() == "script", (try? child.attr("type").lowercased()) == "application/ld+json" { return true }
                    return hasNestedRowOrStructuredData(child)
                }
            }
            // `table` and `dl` are the paths of the nearest ancestor table and definition list: the
            // structural unit keys of part-read selection. They never enter a block or locator.
            func walk(_ node: Node, path: String, table: String?, dl: String?) throws {
                try Task.checkCancellation()
                if let value = node as? TextNode { try emit("text", value.getWholeText(), path); return }
                guard let element = node as? Element else { return }
                let tag = element.tagName()
                if ignored.contains(tag) { return }
                let tableUnit = table.map { "table:" + $0 }
                if tag == "script" {
                    if try element.attr("type").lowercased() == "application/ld+json" {
                        let rawJSON = element.data()
                        guard let data = rawJSON.data(using: .utf8),
                              (try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])) != nil else {
                            throw GenericFoodProposalError.invalidDocument
                        }
                        // Keep the literal JSON text; decoding/re-encoding would change quotes.
                        try emit("json_ld", rawJSON, path)
                    }
                    return
                }
                // Paragraphs or divs inside cells do not change the enclosing
                // row's column relationship. Nested tables still retain their
                // own rows, and structured data must not be silently discarded.
                if tag == "tr", !hasNestedRowOrStructuredData(element) {
                    try emit(tag, text(element), path, unit: tableUnit); return
                }
                if atomic.contains(tag), !hasAtomicDescendant(element) {
                    try emit(tag, text(element), path, unit: ["tr", "caption"].contains(tag) ? tableUnit : nil); return
                }
                let ownTable = tag == "table" ? path : table
                let ownList = tag == "dl" ? path : dl
                let children = element.getChildNodes()
                var index = 0
                while index < children.count {
                    let child = children[index]
                    // A definition term and its single adjacent description form
                    // one source row. Whitespace is harmless; additional terms,
                    // descriptions or nested block content are not collapsed.
                    var previous = index - 1
                    while previous >= 0, let whitespace = children[previous] as? TextNode,
                          whitespace.getWholeText().trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { previous -= 1 }
                    if let term = child as? Element, term.tagName() == "dt", !hasAtomicDescendant(term),
                       previous < 0 || (children[previous] as? Element)?.tagName() != "dt" {
                        var next = index + 1
                        while next < children.count, let whitespace = children[next] as? TextNode,
                              whitespace.getWholeText().trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { next += 1 }
                        if next < children.count, let description = children[next] as? Element,
                           description.tagName() == "dd", !hasAtomicDescendant(description) {
                            var following = next + 1
                            while following < children.count, let whitespace = children[following] as? TextNode,
                                  whitespace.getWholeText().trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { following += 1 }
                            if following == children.count || (children[following] as? Element)?.tagName() != "dd" {
                                try emit("definition_row", text(term) + " | " + text(description),
                                         path + "/dt[\(index)]+dd[\(next)]", unit: ownList.map { "dl:" + $0 })
                                index = next + 1; continue
                            }
                        }
                    }
                    try walk(child, path: path + "/\(child.nodeName())[\(index)]", table: ownTable, dl: ownList)
                    index += 1
                }
            }
            do { try walk(document, path: "document", table: nil, dl: nil) }
            catch is CancellationError { throw CancellationError() }
            catch { throw passedBound ? FoodSourceAcquisitionError.responseTooLarge : error }
        } else { throw FoodSourceAcquisitionError.unsupportedContent }
        let hash = SHA256.hash(data: raw).map { String(format: "%02x", $0) }.joined()
        let retrieved = ISO8601DateFormatter().string(from: retrievedAt)
        guard passedBound else {
            let blocks = emitted.enumerated().map { index, block in
                FoodDocumentBlock(id: "b\(index + 1)", kind: block.kind, text: block.text, locator: block.path + ";projection:" + version)
            }
            return try CapturedFoodDocument(id: "doc_" + hash.prefix(16), url: url.absoluteString,
                rawSha256: hash, captureOrigin: origin, retrievedAt: retrieved, blocks: blocks)
        }
        do {
            selectionStarts()
            guard let kept = try FoodDocumentBlockSelection.select(emitted.map { .init(kind: $0.kind, text: $0.text, unit: $0.unit) })
            else { throw FoodSourceAcquisitionError.responseTooLarge }
            let suffix = ";projection:" + FoodDocumentPartialRead.selectedProjectionVersion
            let blocks = try kept.map { index in
                let block = emitted[index]
                let locator = block.path + suffix
                // Nothing is shortened: a locator too long for the stored document refuses the page.
                guard locator.count <= 500 else { throw FoodSourceAcquisitionError.responseTooLarge }
                return FoodDocumentBlock(id: "b\(index + 1)", kind: block.kind, text: block.text, locator: locator)
            }
            let record = FoodDocumentPartialRead(fullBlocks: emitted.count, fullCharacters: total, keptBlocks: blocks.count,
                                                 keptCharacters: blocks.reduce(0) { $0 + $1.text.count })
            return try CapturedFoodDocument(id: "doc_" + hash.prefix(16), url: url.absoluteString, rawSha256: hash,
                captureOrigin: origin, retrievedAt: retrieved, blocks: blocks, partialRead: record)
        } catch is CancellationError { throw CancellationError() }
        catch { throw FoodSourceAcquisitionError.responseTooLarge }
    }
}
