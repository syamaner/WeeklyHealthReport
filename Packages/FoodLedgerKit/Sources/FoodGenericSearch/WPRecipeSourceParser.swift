import CryptoKit
import Foundation
import SwiftSoup
import FoodLedgerApplication
import FoodLedgerDomain

/// Narrow captured JSON-LD / WP Recipe Maker correspondence; no linked resources or recipe calculation.
public enum WPRecipeSourceParser {
    public static let version = "wp-recipe-source-parser-v1"
    public static func profile(_ html: Data, sourceURL: URL) throws -> FoodSourceRecipeProfile {
        try Task.checkCancellation()
        guard !html.isEmpty, html.count <= FoodSourceContentLimits.htmlBytes,
              let text = String(data: html, encoding: .utf8) else { throw FoodSourceBindingError.invalidDocument }
        let document = try SwiftSoup.parseHTML(text)
        var indexes: [ObjectIdentifier: Int] = [:]
        func index(_ node: Node, depth: Int) throws {
            guard depth <= 128, indexes.count < 50_000 else { throw FoodSourceBindingError.unsupportedLayout }
            indexes[ObjectIdentifier(node)] = indexes.count + 1
            for child in node.getChildNodes() { try index(child, depth: depth + 1) }
        }
        try index(document, depth: 0)
        var recipes: [(String, [String: Any])] = []
        func walk(_ value: Any, pointer: String, depth: Int) throws {
            guard depth <= 128 else { throw FoodSourceBindingError.unsupportedLayout }
            if let object = value as? [String: Any] {
                if object["@type"] as? String == "Recipe" || (object["@type"] as? [String])?.contains("Recipe") == true {
                    recipes.append((pointer, object))
                }
                for key in object.keys.sorted() {
                    try walk(object[key]!, pointer: pointer + "/" + key.replacingOccurrences(of: "~", with: "~0").replacingOccurrences(of: "/", with: "~1"), depth: depth + 1)
                }
            } else if let list = value as? [Any] {
                for (i, item) in list.enumerated() { try walk(item, pointer: pointer + "/\(i)", depth: depth + 1) }
            }
        }
        for (i, script) in try document.select("script[type=application/ld+json]").array().enumerated() {
            let raw = Data(script.data().utf8)
            try SourceRecipeJSONKeyGuard.validate(raw)
            try walk(JSONSerialization.jsonObject(with: raw), pointer: "/script/\(i)", depth: 0)
        }
        guard recipes.count == 1, let (pointer, recipe) = recipes.first else { throw FoodSourceBindingError.unsupportedLayout }
        let card = try one(document, ".wprm-recipe-container")
        let nameElement = try one(card, ".wprm-recipe-name")
        guard let name = recipe["name"] as? String, name == (try visibleText(nameElement)),
              let recordID = recipe["@id"] as? String, recordID == sourceURL.absoluteString + "#recipe" else { throw FoodSourceBindingError.sourceMismatch }
        let yieldElement = try one(card, ".wprm-recipe-servings")
        let servings = try numeric(visibleText(yieldElement))
        guard servings > 0 else { throw FoodSourceBindingError.basisMismatch }
        let yields = (recipe["recipeYield"] as? [String]) ?? (recipe["recipeYield"] as? String).map { [$0] } ?? []
        guard !yields.isEmpty else { throw FoodSourceBindingError.basisMismatch }
        for yield in yields {
            let value = yield.replacingOccurrences(of: " Servings", with: "").replacingOccurrences(of: " Serving", with: "")
                .replacingOccurrences(of: " servings", with: "").replacingOccurrences(of: " serving", with: "")
            guard try numeric(value) == servings else { throw FoodSourceBindingError.basisMismatch }
        }
        guard let nutrition = recipe["nutrition"] as? [String: Any], nutrition["@type"] as? String == "NutritionInformation",
              nutrition["servingSize"] as? String == "1 serving" else { throw FoodSourceBindingError.basisMismatch }
        let panel = try one(card, ".wprm-nutrition-label-container")
        let fields: [(NutrientKey, String, String, String, String)] = [
            (.energyConsumed, "calories", "calories", "Calories:", "kcal"),
            (.fatTotal, "fatContent", "fat", "Fat:", "g"),
            (.carbohydrates, "carbohydrateContent", "carbohydrates", "Carbohydrates:", "g"),
            (.protein, "proteinContent", "protein", "Protein:", "g")]
        var declarations: [FoodSourceRecipeProfile.Declaration] = []
        for (field, key, suffix, label, unit) in fields {
            guard let literal = nutrition[key] as? String, literal.hasSuffix(" " + unit) else { throw FoodSourceBindingError.declarationMismatch }
            let amount = try numeric(String(literal.dropLast(unit.count + 1)))
            let row = try one(panel, ".wprm-nutrition-label-text-nutrition-container-" + suffix)
            let valueElement = try one(row, ".wprm-nutrition-label-text-nutrition-value")
            let unitElement = try one(row, ".wprm-nutrition-label-text-nutrition-unit")
            guard try numeric(visibleText(valueElement)) == amount,
                  try visibleText(unitElement) == unit, try visibleText(one(row, ".wprm-nutrition-label-text-nutrition-label")) == label else {
                throw FoodSourceBindingError.declarationMismatch
            }
            declarations.append(.init(field: field, value: try SourceExactNutrientValue(amount: amount,
                unit: LedgerText(unit), basis: FoodSourceRecipeProfile.basis), literal: literal,
                jsonPointer: pointer + "/nutrition/" + key,
                visibleValueNode: indexes[ObjectIdentifier(valueElement)]!, visibleUnitNode: indexes[ObjectIdentifier(unitElement)]!))
        }
        guard let ingredients = recipe["recipeIngredient"] as? [String] else { throw FoodSourceBindingError.invalidDocument }
        return try FoodSourceRecipeProfile(name: name, recordID: recordID,
            htmlSHA256: SHA256.hash(data: html).map { String(format: "%02x", $0) }.joined(), recipePointer: pointer,
            servings: servings, servingLiteral: "1 serving", ingredients: ingredients, declarations: declarations)
    }
    private static func one(_ root: Element, _ selector: String) throws -> Element {
        let elements = try root.select(selector).array()
        guard elements.count == 1 else { throw FoodSourceBindingError.unsupportedLayout }
        var ancestor: Element? = elements[0]
        while let node = ancestor { try visibleNode(node); ancestor = node.parent() }
        return elements[0]
    }
    private static func visibleText(_ element: Element) throws -> String {
        var parent: Element? = element
        while let node = parent { try visibleNode(node); parent = node.parent() }
        for node in try element.getAllElements().array() { try visibleNode(node) }
        return try element.text().split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
    private static func visibleNode(_ node: Element) throws {
            let style = try node.attr("style").lowercased().filter { !$0.isWhitespace }
            guard !["script", "style", "template", "noscript"].contains(node.tagName()),
                  !node.hasAttr("hidden"), try node.attr("aria-hidden") != "true",
                  !style.contains("display:none"), !style.contains("visibility:hidden") else { throw FoodSourceBindingError.unsupportedLayout }
    }
    private static func numeric(_ literal: String) throws -> Double {
        guard literal.range(of: "^[0-9]+(?:\\.[0-9]+)?$", options: .regularExpression) != nil,
              let amount = Double(literal), amount.isFinite, amount <= 100_000 else { throw FoodSourceBindingError.declarationMismatch }
        return amount
    }
}

/// JSONSerialization accepts duplicate keys; reject them before using its object graph.
private enum SourceRecipeJSONKeyGuard {
    static func validate(_ data: Data) throws {
        _ = try JSONSerialization.jsonObject(with: data)
        let bytes = Array(data); var cursor = 0
        func white() { while cursor < bytes.count && [9, 10, 13, 32].contains(bytes[cursor]) { cursor += 1 } }
        func string() throws -> String {
            guard cursor < bytes.count, bytes[cursor] == 34 else { throw FoodSourceBindingError.invalidDocument }
            let start = cursor; cursor += 1
            while cursor < bytes.count {
                let byte = bytes[cursor]; cursor += 1
                if byte == 92 { cursor += 1 }
                else if byte == 34 { return try JSONDecoder().decode(String.self, from: Data(bytes[start..<cursor])) }
            }
            throw FoodSourceBindingError.invalidDocument
        }
        func value(_ depth: Int) throws {
            white(); guard depth <= 128, cursor < bytes.count else { throw FoodSourceBindingError.invalidDocument }
            switch bytes[cursor] {
            case 123:
                cursor += 1; white(); var keys: Set<String> = []
                if bytes[cursor] == 125 { cursor += 1; return }
                while true {
                    white(); let key = try string()
                    guard keys.insert(key).inserted else { throw FoodSourceBindingError.invalidDocument }
                    white(); cursor += 1; try value(depth + 1); white()
                    if bytes[cursor] == 125 { cursor += 1; break }; cursor += 1
                }
            case 91:
                cursor += 1; white()
                if bytes[cursor] == 93 { cursor += 1; return }
                while true { try value(depth + 1); white(); if bytes[cursor] == 93 { cursor += 1; break }; cursor += 1 }
            case 34: _ = try string()
            default: while cursor < bytes.count && ![9,10,13,32,44,93,125].contains(bytes[cursor]) { cursor += 1 }
            }
        }
        try value(0)
    }
}
