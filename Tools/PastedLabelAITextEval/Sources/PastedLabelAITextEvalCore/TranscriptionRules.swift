import Foundation

/// The transcription value rules of the frozen fresh-set harnesses, copied (not imported) from
/// `FreshSet.problems` (`Packages/FoodLedgerKit/Tests/FoodLabelTextCaptureTests/FreshSet/FreshSetProtocol.swift`)
/// and `UKFreshSet.problems` (`.../UKFreshSet/UKFreshSetProtocol.swift`), so a case never holds a
/// value the frozen scorer's validation would refuse. Anything outside the closed lists is
/// allowed only with `outside_table`; a UK class marker (`Trace`, `Tr`, a dash) is a first-class
/// value and must not carry it.
///
/// One rule is stricter than the original: `FreshSet.rowNumber` reads a single comma between
/// digits as a decimal point unless three digits follow it or the row is a Taiwan alias row
/// (`RowClassifierV3`, inside the frozen parser). The alias classifier is not copied, so in the
/// Taiwan schema every comma needs `outside_table`; a real transcription refused by that is
/// reported by the converter, never accepted silently.
enum TranscriptionRules {
    enum Schema { case taiwan, uk }

    static let taiwanComparators: [String: String] = [
        "=": "=",
        "<": "<", "＜": "<", "未滿": "<", "少於": "<",
        "<=": "<=", "≦": "<=", "≤": "<=", "以下": "<=",
    ]
    static let ukComparators: [String: String] = [
        "=": "=",
        "<": "<", "less than": "<",
        "<=": "<=", "≤": "<=",
    ]
    static let taiwanUnits: [String: String] = [
        "大卡": "kcal", "千卡": "kcal", "kcal": "kcal", "cal": "cal",
        "kj": "kJ", "千焦": "kJ",
        "公克": "g", "克": "g", "g": "g", "gr": "g", "gm": "g",
        "毫克": "mg", "mg": "mg",
        "微克": "µg", "µg": "µg", "μg": "µg", "mcg": "µg",
        "毫升": "ml", "ml": "ml", "cc": "ml",
        "%": "%",
    ]
    static let ukUnits: [String: String] = [
        "kj": "kJ", "kcal": "kcal", "cal": "cal",
        "g": "g", "gm": "g", "gms": "g", "gr": "g", "grs": "g",
        "mg": "mg",
        "µg": "µg", "μg": "µg", "mcg": "µg",
        "ml": "ml",
        "%": "%",
    ]
    static let ukMarkers = ["trace", "tr", "-", "–", "—", "−"]

    static func comparator(_ printed: String, _ schema: Schema) -> String? {
        switch schema {
        case .taiwan: taiwanComparators[printed]
        case .uk: ukComparators[printed] ?? ukComparators[printed.lowercased()]
        }
    }

    static func singleUnit(_ printed: String, _ schema: Schema) -> String? {
        let table = schema == .taiwan ? taiwanUnits : ukUnits
        return table[printed] ?? table[printed.lowercased()]
    }

    /// Amendment 3: two units joined by `/` or `／`, or the second in brackets, map only when both
    /// parts map to the same canonical unit.
    static func unit(_ printed: String, _ schema: Schema) -> String? {
        if let single = singleUnit(printed, schema) { return single }
        let parts: [String]
        if let slash = printed.firstIndex(where: { $0 == "/" || $0 == "／" }) {
            parts = [String(printed[..<slash]), String(printed[printed.index(after: slash)...])]
        } else if let open = printed.firstIndex(where: { $0 == "(" || $0 == "（" }), let last = printed.last, last == ")" || last == "）" {
            parts = [String(printed[..<open]), String(printed[printed.index(after: open)..<printed.index(before: printed.endIndex)])]
        } else {
            return nil
        }
        guard parts.allSatisfy({ !$0.isEmpty }), let first = singleUnit(parts[0], schema), let second = singleUnit(parts[1], schema),
              first == second else { return nil }
        return first
    }

    static func decimal(_ text: String) -> Bool { text.range(of: #"^[0-9]+(\.[0-9]+)?$"#, options: .regularExpression) != nil }

    /// A comma number on a row whose label holds CJK script needs `outside_table` in either
    /// schema: the frozen alias check (`RowClassifierV3.isTaiwanAlias`) is not copied, and it would
    /// refuse a comma on a Taiwan alias row (Qodo finding 5 on #421).
    static func rowNumber(_ text: String, _ schema: Schema, label: String) -> Bool {
        guard text.contains(",") else { return decimal(text) }
        guard schema == .uk, !hasCJK(label), text.range(of: #"^[0-9]+,[0-9]+$"#, options: .regularExpression) != nil,
              let comma = text.firstIndex(of: ",") else { return false }
        return text[text.index(after: comma)...].count != 3
    }

    static func hasCJK(_ text: String) -> Bool {
        text.range(of: #"[\p{Script=Han}\p{Script=Hiragana}\p{Script=Katakana}]"#, options: .regularExpression) != nil
    }

    static func isClassMarker(_ value: TranscriptionShapes.Value) -> Bool {
        value.comparator == "=" && value.unit.isEmpty && ukMarkers.contains(value.number.lowercased())
    }

    /// Every value problem, as the frozen `problems` lists them.
    static func problems(_ expected: EvalCase.Expected, _ schema: Schema) -> [String] {
        var out: [String] = []
        if let s = expected.servingSize, s.outsideTable != true, !decimal(s.number) || unit(s.unit, schema) == nil {
            out.append("serving_size: outside the table without outside_table")
        }
        if let p = expected.servingsPerPack, !decimal(p.number) { out.append("servings_per_pack") }
        if expected.columns.isEmpty { out.append("no columns") }
        for row in expected.rows {
            for value in row.values.compactMap({ $0 }) {
                if schema == .uk, isClassMarker(value) {
                    if value.outsideTable == true { out.append("\(row.label): marker \(value.number) with outside_table") }
                    continue
                }
                guard value.outsideTable != true else { continue }
                if comparator(value.comparator, schema) == nil { out.append("\(row.label): comparator \(value.comparator) without outside_table") }
                if !rowNumber(value.number, schema, label: row.label) { out.append("\(row.label): number \(value.number) without outside_table") }
                if unit(value.unit, schema) == nil { out.append("\(row.label): unit \(value.unit) without outside_table") }
            }
        }
        return out
    }
}
