import CryptoKit
import Foundation
import SwiftSoup
import FoodLedgerApplication

/// HTML5-normalised table projection only. No scripts, linked-resource fetches or nutrient inference.
/// Source coordinates refer to this versioned projection; the raw-byte hash preserves its input.
public enum HTMLFoodSourceTableProjector {
    public static let version = "swift-html-source-tables-v2"
    private static let ignored: Set<String> = ["script", "style", "noscript", "template", "head"]
    private static let blocks: Set<String> = ["p", "div", "li", "h1", "h2", "h3", "h4", "h5", "h6"]

    public static func project(_ html: Data) throws -> Data {
        try Task.checkCancellation()
        guard !html.isEmpty, html.count <= FoodSourceContentLimits.htmlBytes,
              let text = String(data: html, encoding: .utf8) else { throw FoodSourceBindingError.invalidDocument }
        let document = try SwiftSoup.parseHTML(text)
        // Bound traversal separately from byte size. Reject hidden/nested source structures rather than flattening them.
        var nodes = 0
        func checkTree(_ node: Node, depth: Int) throws {
            nodes += 1
            guard depth <= 128, nodes <= 50_000 else { throw FoodSourceBindingError.unsupportedLayout }
            try Task.checkCancellation()
            if let element = node as? Element, ignored.contains(element.tagName()) { return }
            for child in node.getChildNodes() { try checkTree(child, depth: depth + 1) }
        }
        try checkTree(document, depth: 0)
        var tables: [[String: Any]] = []
        var cellCount = 0
        for table in try document.getElementsByTag("table").array() {
            try Task.checkCancellation()
            var ancestor = table.parent()
            var skip = false
            while let parent = ancestor {
                if ignored.contains(parent.tagName()) { skip = true; break }
                guard parent.tagName() != "table" else { throw FoodSourceBindingError.unsupportedLayout }
                ancestor = parent.parent()
            }
            if skip { continue }
            guard tables.count < 32 else { throw FoodSourceBindingError.unsupportedLayout }
            var rows: [[String: Any]] = []
            var captions: [String] = []
            func appendRow(_ row: Element, section: String) throws {
                guard rows.count < 256 else { throw FoodSourceBindingError.unsupportedLayout }
                var cells: [[String: Any]] = []
                for node in row.getChildNodes() {
                    if let text = node as? TextNode {
                        guard text.getWholeText().trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw FoodSourceBindingError.unsupportedLayout }
                        continue
                    }
                    guard let element = node as? Element else { continue }
                    let tag = element.tagName()
                    if ignored.contains(tag) { continue }
                    guard ["td", "th"].contains(tag), cells.count < 32, cellCount < 4096 else { throw FoodSourceBindingError.unsupportedLayout }
                    cellCount += 1
                    var cell: [String: Any] = ["tag": tag, "segments": try segments(element)]
                    for attribute in ["rowspan", "colspan"] {
                        let raw = try element.attr(attribute)
                        guard raw.isEmpty || (raw.allSatisfy({ $0 >= "0" && $0 <= "9" }) && Int(raw).map { (1...1000).contains($0) } == true) else { throw FoodSourceBindingError.unsupportedLayout }
                        cell[attribute] = raw.isEmpty ? 1 : Int(raw)!
                    }
                    let scope = try element.attr("scope")
                    if !scope.isEmpty { cell["scope"] = scope }
                    cells.append(cell)
                }
                rows.append(["section": section, "cells": cells])
            }
            for node in table.getChildNodes() {
                if let text = node as? TextNode {
                    guard text.getWholeText().trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw FoodSourceBindingError.unsupportedLayout }
                    continue
                }
                guard let element = node as? Element else { continue }
                let tag = element.tagName()
                if ignored.contains(tag) || tag == "colgroup" { continue }
                if tag == "caption" { captions.append(try element.text()); continue }
                if tag == "tr" { try appendRow(element, section: "table"); continue }
                guard ["thead", "tbody", "tfoot"].contains(tag) else { throw FoodSourceBindingError.unsupportedLayout }
                for row in element.children().array() {
                    if ignored.contains(row.tagName()) { continue }
                    guard row.tagName() == "tr" else { throw FoodSourceBindingError.unsupportedLayout }
                    try appendRow(row, section: tag)
                }
            }
            tables.append(["id": tables.count + 1, "rows": rows, "captions": captions])
        }
        guard !tables.isEmpty else { throw FoodSourceBindingError.unsupportedLayout }
        let digest = SHA256.hash(data: html).map { String(format: "%02x", $0) }.joined()
        let result = try JSONSerialization.data(withJSONObject: ["version": "table-preserving-source-v7",
            "projection_version": version, "html_sha256": digest, "tables": tables], options: [.sortedKeys])
        guard result.count <= FoodSourceDocumentDecoder.maximumBytes else { throw FoodSourceBindingError.invalidDocument }
        return result
    }

    private static func segments(_ cell: Element) throws -> [String] {
        var result: [String] = []
        var parts = ""
        var lastExplicitBreak = false
        func flush(explicit: Bool = false) throws {
            let value = parts.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            if explicit || !value.isEmpty {
                guard result.count < 64 else { throw FoodSourceBindingError.unsupportedLayout }
                result.append(value); lastExplicitBreak = explicit
            }
            parts = ""
        }
        func visit(_ node: Node, depth: Int) throws {
            guard depth <= 128 else { throw FoodSourceBindingError.unsupportedLayout }
            try Task.checkCancellation()
            if let text = node as? TextNode { parts += text.getWholeText(); return }
            guard let element = node as? Element else { return }
            let tag = element.tagName()
            if ignored.contains(tag) { return }
            guard tag != "table" else { throw FoodSourceBindingError.unsupportedLayout }
            if tag == "br" { try flush(explicit: true); return }
            if blocks.contains(tag) { try flush() }
            for child in element.getChildNodes() { try visit(child, depth: depth + 1) }
            if blocks.contains(tag) { try flush() }
        }
        for child in cell.getChildNodes() { try visit(child, depth: 0) }
        if !parts.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || result.isEmpty || lastExplicitBreak {
            try flush(explicit: true)
        }
        return result
    }
}
