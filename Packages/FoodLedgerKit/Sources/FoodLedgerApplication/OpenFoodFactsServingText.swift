import FoodLedgerDomain
import Foundation

/// The wording for a value scaled from an Open Food Facts per-serving panel
/// (`off-product-projection-v6`), shared by the barcode and text-search source line and by Your food
/// database entries (docs/personal-food-catalogue-import-v2.md), so both routes state a serving the
/// same way.
public enum OpenFoodFactsServingText {
    /// "28" or "12.5": the serving as Open Food Facts states it, without a trailing ".0".
    public static func number(_ value: Double) -> String {
        value == value.rounded() && abs(value) < 1e15 ? String(Int64(value)) : String(value)
    }

    /// "g" or "ml", as the barcode route's source line writes them.
    public static func unit(millilitres: Bool) -> String { millilitres ? "ml" : "g" }

    /// "28 g" or "250 ml".
    public static func serving(_ quantity: PositiveQuantity) -> String {
        "\(number(quantity.value)) \(unit(millilitres: quantity.unit == .millilitres))"
    }

    /// The Confirm line for a Your food database entry with scaled values (owner decision 3,
    /// 13 November 2026): "Some values scaled from a 28 g serving".
    public static func databaseEntryNote(_ quantity: PositiveQuantity) -> String {
        "Some values scaled from a \(serving(quantity)) serving"
    }
}
