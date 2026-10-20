import Foundation

/// The serving-size grammar of `nutrition-label-text-parser-v2`, held here so the application can
/// locate the recorded serving quantity exactly as the parser did without importing the parser
/// (decision 10). The pattern strings are byte-identical to the parser's `Patterns.servingSize`,
/// `Patterns.parenthesised` and `Patterns.servingQuantity`; `FoodLabelTextCaptureTests` pins
/// them and the located quantity to the parser on a fixture set. Fixed with parser v2 and
/// `pasted-label-serving-v2`.
public enum PastedLabelServingSizeGrammar {
    public static let labelPattern = #"(?i)^(?:serving\s+size|portion\s+size|每一?份量)\s*[:：]?\s*(.+)$"#
    public static let parenthesisedPattern = #"[(（]([^)）]+)[)）]"#
    public static let quantityPattern = #"(\d+(?:\.\d+)?)\s*(g|ml|mL|公克|毫升|克)(?![\p{L}])"#

    static let label = try! NSRegularExpression(pattern: labelPattern)
    static let parenthesised = try! NSRegularExpression(pattern: parenthesisedPattern)
    static let quantity = try! NSRegularExpression(pattern: quantityPattern)
}
