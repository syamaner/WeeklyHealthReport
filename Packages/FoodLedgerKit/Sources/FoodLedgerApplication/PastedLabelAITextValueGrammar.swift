import Foundation

/// The closed value lists of the pasted label AI text route (docs/pasted-label-ai-text-v1.md 4.2,
/// 4.3 item 2 and 11.1): the comparators, the printed units with their canonical units, and the
/// unit alternatives in the order the value pattern tries them. They are held here, in the
/// application layer, so the text locator, the unit check and the text target's copy of
/// `parseValue` read one list. They equal the lists of `label-photo-wire-mapping-v1`
/// (`LabelPhotoWireMapping.units`, `valueUnits`, `echoUnits` and `comparators`), which a parity
/// test proves; the rules that differ are the text route's thousands separator (4.3 item 2),
/// which belongs to the token grammar, not to these lists, and, from revision 10, the text-only
/// kcal spellings (`textOnlyValueUnits`) and the bracket rule (`unbracketed`). A change to any
/// list is a new version.
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

    /// Revision 10 (mapping v2, locator v2): kcal spellings in other letter cases, which the photo
    /// list does not hold and the canonical table already maps to `kcal` case-insensitively
    /// (`Kcal`, `kCal`). Each names kcal and nothing else, so the reading is unambiguous. They are
    /// text-route only; the photo list and the parity with it are unchanged.
    public static let textOnlyValueUnits: [String] = ["Kcal", "kCal", "KCal", "KCAL"]

    /// The units the text route's value pattern and token scan try: the photo list, then the
    /// text-only kcal spellings (none is a prefix of another entry, so the order is safe).
    public static let textValueUnits: [String] = valueUnits + textOnlyValueUnits

    /// The units a trailing bracketed echo may print after a value (`5 g (g)`).
    public static let echoUnits: [String] = ["kcal", "kJ", "g", "mg", "mcg", "µg", "ml"]

    /// `textValueUnits` longest first (stable for equal lengths), so a scan takes `mg` before `g`
    /// and `毫克` before `克`.
    public static let unitsLongestFirst: [String] = textValueUnits.enumerated()
        .sorted { ($0.element.unicodeScalars.count, -$0.offset) > ($1.element.unicodeScalars.count, -$1.offset) }
        .map(\.element)

    /// The bracket rule (revision 10, mapping v2 and locator v2). A model may copy the brackets a
    /// label prints around a value (`(of which saturates) (4.9g)`, or a row wrapped as
    /// `(of which sugars 4.8g)`), so its printed text is `(4.9g)` or `4.8g)`. This drops one
    /// outer `(`/`（` and `)`/`）` pair, or one lone leading opener, or one lone trailing closer,
    /// and returns what it dropped, so the locator can require those same brackets beside the
    /// token in the text. Anything else (no bracket, a bracket inside, an echo such as `5 g (g)`)
    /// is returned unchanged with no brackets. It never changes the value itself.
    public struct Bracketed: Equatable, Sendable {
        public let open: Unicode.Scalar?
        public let core: String
        public let close: Unicode.Scalar?
        public var isBracketed: Bool { open != nil || close != nil }
        public init(open: Unicode.Scalar?, core: String, close: Unicode.Scalar?) { self.open = open; self.core = core; self.close = close }
    }

    static let openers: Set<Unicode.Scalar> = ["(", "\u{FF08}"]
    static let closers: Set<Unicode.Scalar> = [")", "\u{FF09}"]

    public static func unbracketed(_ printed: String) -> Bracketed {
        let scalars = Array(printed.unicodeScalars)
        let unchanged = Bracketed(open: nil, core: printed, close: nil)
        guard let first = scalars.first, let last = scalars.last else { return unchanged }
        let leading = openers.contains(first), trailing = closers.contains(last)
        guard leading || trailing else { return unchanged }
        let inner = Array(scalars[(leading ? 1 : 0)..<(scalars.count - (trailing ? 1 : 0))])
        // A bracket left inside (an echo `5 g (g)`, or `(5g) (2g)`) is not this rule's case.
        guard !inner.isEmpty, !inner.contains(where: { openers.contains($0) || closers.contains($0) }) else { return unchanged }
        if leading, trailing, (first == "(") != (last == ")") { return unchanged }
        var core = String.UnicodeScalarView()
        core.append(contentsOf: inner)
        return Bracketed(open: leading ? first : nil, core: String(core), close: trailing ? last : nil)
    }

    /// The canonical unit of a printed unit, or nil when it is outside the closed table.
    public static func canonicalUnit(_ unit: String) -> String? { units[unit] ?? units[unit.lowercased()] }

    /// The separators allowed between the parts of one value token: space, tab, U+00A0 and U+202F.
    public static func isTokenSpace(_ scalar: Unicode.Scalar) -> Bool {
        scalar == " " || scalar == "\t" || scalar == "\u{00A0}" || scalar == "\u{202F}"
    }

    /// A Unicode decimal digit (general category Nd), as the copied `parseValue` accepts.
    public static func isDigit(_ scalar: Unicode.Scalar) -> Bool { scalar.properties.generalCategory == .decimalNumber }
}
