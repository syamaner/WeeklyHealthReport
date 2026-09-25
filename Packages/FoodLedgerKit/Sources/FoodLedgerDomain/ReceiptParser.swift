import Foundation

public enum ReceiptLineKind: String, Codable, Sendable { case product, context, requiresReview }

public struct ReceiptLineProposal: Codable, Equatable, Sendable {
    public let lineNumber: Int
    public let original: String
    public let description: String
    public let kind: ReceiptLineKind
    public let purchaseCount: Double?
    public let unitsPerPack: Double?
    public let packAmount: Double?
    public let packUnit: QuantityUnit?
    /// Printed price text, never a quantity and never an inferred currency.
    public let priceText: String?
    public let notices: [String]
}

/// Receipt-specific grammar: proposals only, not stock assertions or food servings.
public enum ReceiptParser {
    public static let version = "receipt-lexical-v1"
    public static let maximumCharacters = 100_000
    public static let maximumLines = 1_000
    public enum ParseError: Error { case empty, tooLarge }

    public static func parse(_ text: String) throws -> [ReceiptLineProposal] {
        guard text.count <= maximumCharacters else { throw ParseError.tooLarge }
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n").components(separatedBy: "\n")
        guard lines.count <= maximumLines else { throw ParseError.tooLarge }
        let result = lines.enumerated().compactMap { index, line in
            line.trimmingCharacters(in: .whitespaces).isEmpty ? nil : parseLine(line, number: index + 1)
        }
        guard !result.isEmpty else { throw ParseError.empty }
        return result
    }

    private static func parseLine(_ original: String, number: Int) -> ReceiptLineProposal {
        var text = original.trimmingCharacters(in: .whitespaces)
        var kind: ReceiptLineKind = .product
        var notices = ["Review the printed product, pack and purchase amount."]
        var purchaseCount: Double?
        var unitsPerPack: Double?
        var packAmount: Double?
        var packUnit: QuantityUnit?
        var price: String?

        if first(#"(?i)^(?:sub\s*total|total|tax|vat|change|cash|card|balance|discount|coupon|saving|delivery fee)\b"#, text) != nil {
            kind = .context
            notices = ["Receipt context, not an acquisition."]
        } else if first(#"(?i)\b(?:refund|return|returned|substitution|substitute|cancelled|canceled|not delivered|out of stock|order|ordered)\b"#, text) != nil
                    || first(#"(?:^|\s)-\s*(?:[£$€]\s*)?\d"#, text) != nil {
            kind = .requiresReview
            notices = ["Return, adjustment or order language: do not infer delivered stock."]
        }
        if let match = first(#"(?:[£$€]\s*\d+(?:[.,]\d{2})?|\d+[.,]\d{2}(?:\s*(?:GBP|EUR|USD))?)\s*$"#, text) {
            price = match[0].trimmingCharacters(in: .whitespaces)
            text = String(text.dropLast(match[0].count)).trimmingCharacters(in: .whitespaces)
            notices.append("Printed price retained separately; currency is not guessed.")
        }
        // Only an explicit leading count × product is proposed as purchase count.
        // A multiplier immediately before a measured pack is its internal pack count.
        if let match = first(#"(?i)^(\d+(?:[.,]\d+)?)\s*[x×]\s+(?=[\p{L}])"#, text) {
            purchaseCount = FoodListParser.number(match[1])
            text = String(text.dropFirst(match[0].count))
        }
        let amountPattern = #"(?i)(?:(\d+(?:[.,]\d+)?)\s*[x×]\s*)?(\d+(?:[.,]\d+)?)\s*(kilograms?|kg|grammes?|grams?|grms?|gm|gr|g|millilitres?|milliliters?|mililitres?|milliliteres|ml|litres?|liters?|l)\b"#
        let amounts = all(amountPattern, text)
        if amounts.count == 1, let match = amounts.first,
           let value = FoodListParser.number(match[2]),
           let definition = FoodListParser.unitDefinition(match[3]),
           (value * definition.scale).isFinite {
            packAmount = value * definition.scale
            packUnit = definition.unit
            unitsPerPack = match[1].isEmpty ? nil : FoodListParser.number(match[1])
            notices.append("Measured amount may describe a pack or variable-weight purchase; confirm its meaning.")
            text = text.replacingOccurrences(of: match[0], with: " ")
        } else if !amounts.isEmpty {
            notices.append("Multiple or ambiguous measured amounts; no pack quantity inferred.")
        }
        if first(#"(?i)\b(?:per|each|@)\b|/\s*(?:kg|g|l|ml)\b"#, text) != nil {
            kind = .requiresReview
            purchaseCount = nil
            packAmount = nil
            packUnit = nil
            unitsPerPack = nil
            notices.append("Rate or unit-price language needs manual review.")
        }
        if kind != .product {
            purchaseCount = nil
            unitsPerPack = nil
            packAmount = nil
            packUnit = nil
        }
        text = text.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        if text.isEmpty { text = original; kind = .context }
        return ReceiptLineProposal(
            lineNumber: number, original: original, description: text, kind: kind,
            purchaseCount: purchaseCount, unitsPerPack: unitsPerPack,
            packAmount: packAmount, packUnit: packUnit, priceText: price, notices: notices
        )
    }

    private static func first(_ pattern: String, _ text: String) -> [String]? { all(pattern, text).first }
    private static func all(_ pattern: String, _ text: String) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).map { match in
            (0..<match.numberOfRanges).map { index in
                Range(match.range(at: index), in: text).map { String(text[$0]) } ?? ""
            }
        }
    }
}
