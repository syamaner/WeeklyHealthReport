import Foundation

/// The closed per-serving rule of `off-product-projection-v6` (docs/off-barcode-candidate-plan-v1.md,
/// 12 November 2026), shared by the barcode and text-search projection and by the Your food database
/// codec (docs/personal-food-catalogue-import-v2.md), so the two cannot drift. The skill's
/// `off_rules.py` and `export_v1.py` mirror these values; the parity and fixture tests pin them.
public enum OpenFoodFactsServingRule {
    /// The transform on every value scaled from a per-serving panel. Not a calculation: it is absent
    /// from `NutrientDerivation.calculatedTransforms`, so the food export marks it `calculated: false`.
    public static let transformID = "off-serving-to-100"
    public static let transformVersion = "v1"
    public static let projectionVersion = "off-product-projection-v6"

    /// The most any food can hold per 100 g or 100 ml, by canonical unit; nil where no limit applies.
    public static func plausibleMaximum(_ unit: NutrientUnit) -> Double? {
        switch unit {
        case .grams: 100
        case .milligrams: 100_000
        case .kilocalories: 900
        default: nil
        }
    }

    /// True for a scaled amount above its unit's maximum, which means the stated serving was wrong.
    public static func isImplausible(_ amount: Double, unit: NutrientUnit) -> Bool {
        plausibleMaximum(unit).map { amount > $0 } ?? false
    }
}
