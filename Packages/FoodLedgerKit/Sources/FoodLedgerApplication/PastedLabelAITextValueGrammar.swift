import Foundation

/// The closed value lists of the pasted label AI text route (docs/pasted-label-ai-text-v1.md 4.2,
/// 4.3 item 2 and 11.1): the comparators, the printed units with their canonical units, and the
/// unit alternatives in the order the value pattern tries them. They are held here, in the
/// application layer, so the text locator, the unit check and the text target's copy of
/// `parseValue` read one list. They equal the lists of `label-photo-wire-mapping-v1`
/// (`LabelPhotoWireMapping.units`, `valueUnits`, `echoUnits` and `comparators`), which a parity
/// test proves; the only rule that differs is the text route's thousands separator (4.3 item 2),
/// which belongs to the token grammar, not to these lists. A change to any list is a new version.
public enum PastedLabelAITextValueGrammar {
    /// A printed comparator and the comparator it means (`=`, `<` or `<=`, the raw values of the
    /// candidate's comparator).
    public struct Comparator: Equatable, Sendable {
        public let printed: String
        public let value: String
        public init(printed: String, value: String) { self.printed = printed; self.value = value }
    }

    /// The comparators, in the order the value pattern tries them (`<=` before `<`).
    public static let comparators: [Comparator] = [
        Comparator(printed: "<=", value: "<="), Comparator(printed: "≤", value: "<="), Comparator(printed: "＜", value: "<"),
        Comparator(printed: "<", value: "<"), Comparator(printed: "少於", value: "<"), Comparator(printed: "less than", value: "<")
    ]

    /// The printed unit to its canonical unit, looked up as printed, then lower-cased.
    public static let units: [String: String] = [
        "大卡": "kcal", "千卡": "kcal", "公克": "g", "克": "g", "毫克": "mg", "微克": "µg", "毫升": "ml", "kcal": "kcal", "kj": "kJ",
        "g": "g", "mg": "mg", "mcg": "µg", "µg": "µg", "μg": "µg", "ml": "ml", "%": "%"
    ]

    /// The unit alternatives a value may print, in the value pattern's order. Matching is exact
    /// (case-sensitive), as in the photo mapping.
    public static let valueUnits: [String] = ["大卡", "千卡", "公克", "毫克", "微克", "毫升", "克", "kcal", "kJ", "kj", "KJ", "mcg", "µg", "μg",
                                              "mg", "ml", "mL", "g", "%"]

    /// The units a trailing bracketed echo may print after a value (`5 g (g)`).
    public static let echoUnits: [String] = ["kcal", "kJ", "g", "mg", "mcg", "µg", "ml"]

    /// `valueUnits` longest first (stable for equal lengths), so a scan takes `mg` before `g`
    /// and `毫克` before `克`.
    public static let unitsLongestFirst: [String] = valueUnits.enumerated()
        .sorted { ($0.element.unicodeScalars.count, -$0.offset) > ($1.element.unicodeScalars.count, -$1.offset) }
        .map(\.element)

    /// The canonical unit of a printed unit, or nil when it is outside the closed table.
    public static func canonicalUnit(_ unit: String) -> String? { units[unit] ?? units[unit.lowercased()] }

    /// The separators allowed between the parts of one value token: space, tab, U+00A0 and U+202F.
    public static func isTokenSpace(_ scalar: Unicode.Scalar) -> Bool {
        scalar == " " || scalar == "\t" || scalar == "\u{00A0}" || scalar == "\u{202F}"
    }

    /// A Unicode decimal digit (general category Nd), as the copied `parseValue` accepts.
    public static func isDigit(_ scalar: Unicode.Scalar) -> Bool { scalar.properties.generalCategory == .decimalNumber }
}
