import Foundation

/// The one display format for food numbers on screens (UX copy pass, #140):
/// energy as whole kcal with grouping ("2,633"), other amounts to at most one
/// decimal place ("6.4"). Display only: stored values, exports and source
/// evidence are never rounded by this.
public enum FoodDisplayNumber {
    /// kcal to the nearest whole number, half away from zero, with grouping.
    public static func kcal(_ value: Double, locale: Locale = .current) -> String {
        amount(value.rounded(.toNearestOrAwayFromZero), fraction: 0...0, locale: locale)
    }

    /// An amount to at most `fraction` decimal places, with grouping.
    public static func amount(_ value: Double, fraction: ClosedRange<Int> = 0...1, locale: Locale = .current) -> String {
        value.formatted(.number.precision(.fractionLength(fraction)).locale(locale))
    }

    /// "260 kcal", or "less than 1 kcal" for a positive value that would round to 0. Lower
    /// case, for use inside a phrase ("Log less than 1 kcal").
    public static func energy(_ kcal: Double, locale: Locale = .current) -> String {
        kcal > 0 && kcal < 0.5 ? "less than 1 kcal" : "\(self.kcal(kcal, locale: locale)) kcal"
    }

    /// "6.4 g", or "less than 0.1 g" for a positive value that would round to 0 at one
    /// decimal place; never a zero for something present. Lower case, for use inside a phrase.
    public static func quantity(_ value: Double, unit: String, locale: Locale = .current) -> String {
        value > 0 && value < 0.05
            ? "less than \(amount(0.1, locale: locale)) \(unit)"
            : "\(amount(value, locale: locale)) \(unit)"
    }

    /// The same text starting a sentence or a value: "Less than 0.1 g".
    public static func capitalisedFirst(_ text: String) -> String {
        text.prefix(1).uppercased() + text.dropFirst()
    }
}
