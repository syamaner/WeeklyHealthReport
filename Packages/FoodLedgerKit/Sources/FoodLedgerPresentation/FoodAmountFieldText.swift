import FoodLedgerApplication
import SwiftUI

/// Text for an amount field shown with a decimal pad (#212). The decimal pad offers only the
/// locale's decimal separator, so a comma-decimal locale types "1,5". The field shows numbers
/// with that separator and hands `FoodAmountTextParser` canonical text (a full stop, no
/// grouping), so 1500 g stays 1500 g and "1,5" in a comma-decimal locale reads as 1.5.
public enum FoodAmountFieldText {
    /// The editable text for a value in this locale: no grouping, the locale's decimal separator.
    public static func text(_ value: Double, locale: Locale) -> String {
        let canonical = FoodAmountTextParser.editableText(value)
        let separator = locale.decimalSeparator ?? "."
        return separator == "." ? canonical : canonical.replacingOccurrences(of: ".", with: separator)
    }

    /// Canonical text for the parser. Only a comma-decimal locale changes anything, and only when
    /// the text has no full stop: the decimal pad cannot type grouping, and text that already
    /// carries a full stop (pasted, or prefilled before a locale change) is left to the parser.
    public static func canonical(_ text: String, locale: Locale) -> String {
        guard let separator = locale.decimalSeparator, separator != ".", !text.contains(".") else { return text }
        return text.replacingOccurrences(of: separator, with: ".")
    }

    /// The parsed amount, or nil when the text is not one positive amount.
    public static func parse(_ text: String, locale: Locale) -> Double? {
        FoodAmountTextParser.parse(canonical(text, locale: locale))
    }
}

extension View {
    /// A decimal pad for an amount field (#212); a no-op where there is no software keyboard.
    func amountKeyboard() -> some View {
        #if os(iOS)
        keyboardType(.decimalPad)
        #else
        self
        #endif
    }
}
