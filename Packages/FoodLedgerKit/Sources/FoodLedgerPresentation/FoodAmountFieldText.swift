import FoodLedgerApplication
import SwiftUI

/// Text for an amount field shown with a decimal pad (#212). The decimal pad offers only the
/// locale's decimal separator, so a comma-decimal locale types "1,5". The field shows numbers
/// with that separator and hands `FoodAmountTextParser` canonical text (a full stop, no
/// grouping), so 1500 g stays 1500 g and "1,5" in a comma-decimal locale reads as 1.5.
///
/// Text whose separators could mean two different amounts is refused, never guessed: a pasted
/// "1.500" in a comma-decimal locale may be German grouping (1500) or a decimal (1.5), so it is
/// invalid rather than a possible thousandfold error.
public enum FoodAmountFieldText {
    /// The keyboard toolbar action that dismisses the decimal pad, which has no return key.
    public static let keyboardDoneTitle = "Done"

    /// Stands in for refused text when the reducer needs non-empty text it cannot parse, so the
    /// existing invalid-amount message blocks saving. Letters never parse as an amount.
    static let refusedText = "ambiguous amount"

    /// The editable text for a value in this locale: no grouping, the locale's decimal separator.
    public static func text(_ value: Double, locale: Locale) -> String {
        let canonical = FoodAmountTextParser.editableText(value)
        let separator = locale.decimalSeparator ?? "."
        return separator == "." ? canonical : canonical.replacingOccurrences(of: ".", with: separator)
    }

    /// Canonical text for the parser, or nil when the separators are ambiguous in this locale.
    public static func canonical(_ text: String, locale: Locale) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // Space grouping ("1 500", including no-break and narrow no-break spaces) is refused in
        // every locale; a mixed fraction such as "1 1/2" is not a grouping pattern.
        if matches(trimmed, #"^\d{1,3}([ \x{00A0}\x{202F}]\d{3})+([.,]\d+)?$"#) { return nil }
        let separator = locale.decimalSeparator ?? "."
        if separator == "." {
            // A comma is only grouping here: "1,500" or "1,000.5" is fine, "1,5" is refused.
            if trimmed.contains(","), !matches(trimmed, #"^\d{1,3}(,\d{3})+(\.\d+)?$"#) { return nil }
            return text
        }
        if trimmed.contains(".") {
            // Both separators, or a full stop followed by exactly three digits, could be grouping.
            if trimmed.contains(separator) || matches(trimmed, #"\.\d{3}(?!\d)"#) { return nil }
            return text
        }
        return text.replacingOccurrences(of: separator, with: ".")
    }

    /// Text for the Confirm reducer: canonical text, or text that is non-empty and never parses,
    /// so a refused amount shows the invalid-amount message instead of a guessed value.
    public static func reducerText(_ text: String, locale: Locale) -> String {
        canonical(text, locale: locale) ?? refusedText
    }

    /// The parsed amount, or nil when the text is not one unambiguous positive amount.
    public static func parse(_ text: String, locale: Locale) -> Double? {
        canonical(text, locale: locale).flatMap(FoodAmountTextParser.parse)
    }

    private static func matches(_ text: String, _ pattern: String) -> Bool {
        text.range(of: pattern, options: .regularExpression) != nil
    }
}

extension View {
    /// A decimal pad for an amount field (#212), focused through `focus` so it can be dismissed.
    func amountKeyboard(_ focus: FocusState<Bool>.Binding) -> some View {
        #if os(iOS)
        keyboardType(.decimalPad).focused(focus)
        #else
        focused(focus)
        #endif
    }

    /// The decimal pad has no return key: scrolling or "Done" above the keyboard dismisses it.
    func amountKeyboardDismissal(_ focus: FocusState<Bool>.Binding) -> some View {
        #if os(iOS)
        scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button(FoodAmountFieldText.keyboardDoneTitle) { focus.wrappedValue = false }
                        .accessibilityHint("Hides the keyboard")
                }
            }
        #else
        self
        #endif
    }
}
