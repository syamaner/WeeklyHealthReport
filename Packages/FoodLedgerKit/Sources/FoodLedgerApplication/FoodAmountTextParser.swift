import Foundation

/// A scalar in an explicitly chosen unit, not a food description or a conversion.
public enum FoodAmountTextParser {
    public static func parse(_ text: String) -> Double? {
        let literal = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if literal == "half" { return 0.5 }
        // Reuse the closed numerical guards (fractions, signs, thousands, bounds).
        // The entire scalar must be consumed; unit words/food text cannot sneak through.
        guard literal.range(of: #"^[\d\s.,/½¼¾−–—+\-]+$"#, options: .regularExpression) != nil else { return nil }
        let parsed = FoodQueryParser.parse(literal + " g rice")
        guard parsed.route == .search, parsed.food == "rice", parsed.attributes.isEmpty,
              let quantity = parsed.quantity, quantity.unit == "g" else { return nil }
        return quantity.value
    }
}
