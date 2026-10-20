import Foundation

/// The serving-size grammar of `nutrition-label-text-parser-v3`
/// (`docs/pasted-nutrition-label-reader-v3.md` section 5.6), held here so the application can
/// locate the recorded serving quantity exactly as parser v3 did without importing the parser
/// (v1 decision 10). The four pattern strings are byte-identical to the parser's
/// `PatternsV3.servingSize`, `Patterns.parenthesised`, `Patterns.servingQuantity` and
/// `PatternsV3.packPhrase`; `FoodLabelTextCaptureTests` pins them, and the located quantity, to
/// the parser on the extended fixture set. Used only by `pasted-label-serving-v3`; the v2 copy
/// (`PastedLabelServingSizeGrammar`) is unchanged.
public enum PastedLabelServingSizeGrammarV3 {
    public static let labelPattern = #"(?i)^(?:serving\s+size|portion\s+size|每[一1]?份量)\s*[:：]?\s*(.+)$"#
    public static let parenthesisedPattern = #"[(（]([^)）]+)[)）]"#
    public static let quantityPattern = #"(\d+(?:\.\d+)?)\s*(g|ml|mL|公克|毫升|克)(?![\p{L}])"#
    public static let packPhrasePattern = #"本包裝包?含?\s*約?\s*\d+(?:\.\d+)?\s*份|(?i:servings?\s+per\s+(?:container|pack|package))"#

    static let label = try! NSRegularExpression(pattern: labelPattern)
    static let parenthesised = try! NSRegularExpression(pattern: parenthesisedPattern)
    static let quantity = try! NSRegularExpression(pattern: quantityPattern)
    static let packPhrase = try! NSRegularExpression(pattern: packPhrasePattern)
}
