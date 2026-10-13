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
}
