import Foundation
import NutritionLabelParsing

/// `label-photo-wire-mapping-v1` (docs/label-photo-ai-prefill-v1.md 8.3 and 12.5 test 1): the
/// Swift port of the evaluation's `route_c_mapping.map_wire`, wire answer to
/// `label-capture-candidate-v1`, with route `C`. Pure. It reads each printed value with the closed
/// value grammar of `draft_untouched_truth.parse_value` and never converts, infers or fills a
/// value: an `unknown` or unreadable value, or one under an undeclared header, is left out and
/// recorded in `warnings`; a parent is kept only when it names another row of the table. It keeps
/// the owner's amendments of 18 October 2026: M1 (an absolute value in a reference-intake column
/// is left out as unread), M2 (a bare energy number takes the one energy unit its row label
/// prints) and M3 (a per-serving column without a serving line takes the quantity its own header
/// prints). Python's `re` semantics are reproduced: `\d` is any Unicode decimal digit and `\s` any
/// Unicode white space. Parity with the Python reference is a contract test.
public enum LabelPhotoWireMapping {
    public static let version = "label-photo-wire-mapping-v1"
    static let languages: Set<String> = ["en", "zh-Hant", "mixed"]

    /// One candidate from one schema-valid wire answer.
    public static func map(_ wire: LabelPhotoWire, inputSHA256: String) -> LabelCaptureCandidate {
        let language = LabelLanguage(rawValue: wire.language) ?? .unknown
        if wire.declined {
            return .declined(route: "C", inputSHA256: inputSHA256, language: language,
                             reasons: wire.declineReasons.isEmpty ? ["declined_without_reason"] : wire.declineReasons)
        }
        var warnings: [String] = []
        let servingText = wire.servingSizeText.isEmpty ? "unknown" : wire.servingSizeText
        let packText = wire.servingsPerPackText.isEmpty ? "unknown" : wire.servingsPerPackText
        let serving = servingSize(servingText)
        let pack = servingsPerPack(packText)
        let servingQuantity: String? = serving.flatMap { size in size.decimalText.flatMap { decimal in size.unit.map { decimal + $0 } } }
        var headers: [LabelHeader] = []
        var headerIDs: Set<String> = []
        for header in wire.headers {
            if headerIDs.contains(header.headerID) {
                warnings.append("duplicate_header_id: \(header.headerID)")
                continue
            }
            var quantity = servingQuantity
            if header.basis == "per_serving", quantity == nil, let printed = printedMass(header.printedText) {
                quantity = printed.number + printed.unit
                warnings.append("serving_quantity_from_header: \(header.headerID)")
            }
            guard let basis = LabelBasis(rawValue: header.basis) else { continue }
            headerIDs.insert(header.headerID)
            headers.append(Parts.header(id: header.headerID, printedText: header.printedText, basis: basis,
                                        servingConversion: header.basis == "per_serving" ? quantity : nil))
        }
        let byID = Dictionary(headers.map { ($0.headerID, $0) }, uniquingKeysWith: { first, _ in first })
        var rowIDs: [String] = []
        var seen: [String: Int] = [:]
        for (index, row) in wire.rows.enumerated() {
            let base = row.nutrient != "unrecognised" ? row.nutrient : "row_\(index + 1)"
            seen[base, default: 0] += 1
            rowIDs.append(seen[base] == 1 ? base : "\(base)_\(seen[base]!)")
        }
        let present = Set(rowIDs)
        var cells: [LabelCell] = []
        var leftOutAmounts = 0
        for (row, rowID) in zip(wire.rows, rowIDs) {
            let parent = PythonText.strip(row.parentNutrient)
            let parentRow = !parent.isEmpty && !["none", "unknown", rowID, row.nutrient].contains(parent) && present.contains(parent) ? parent : nil
            for value in row.values {
                let printed = value.printedText
                guard let header = byID[value.headerID] else {
                    warnings.append("value_without_header: \(rowID) \(value.headerID)")
                    leftOutAmounts += 1
                    continue
                }
                var parsed = PythonText.strip(printed).lowercased() == "unknown" ? nil : parseValue(printed)
                if parsed == nil, header.basis != .referenceIntake {
                    parsed = unitFromRowLabel(row, printed: printed)
                    if parsed != nil { warnings.append("unit_from_row_label: \(rowID) \(header.headerID)") }
                }
                if let value = parsed, header.basis == .referenceIntake, value.canonicalUnit != "%" {
                    warnings.append("value_not_read: \(rowID) \(header.headerID) \(PythonText.repr(printed)) (absolute reference value)")
                    continue
                }
                guard let value = parsed else {
                    warnings.append("value_not_read: \(rowID) \(header.headerID) \(PythonText.repr(printed))")
                    if header.basis != .referenceIntake { leftOutAmounts += 1 }
                    continue
                }
                cells.append(LabelCell(rowID: rowID, parentRowID: parentRow, nutrient: row.nutrient, printedLabel: row.printedLabel,
                    headerID: header.headerID, basis: header.basis, printedText: printed, comparator: value.comparator,
                    decimalText: value.decimalText, unit: value.unit, canonicalUnit: value.canonicalUnit,
                    servingConversion: header.basis == .perServing ? (header.servingConversion ?? "unknown") : "not_applicable"))
            }
        }
        let pairs = cells.map { $0.rowID + "\u{0}" + $0.headerID }
        let duplicates = pairs.count != Set(pairs).count
        if duplicates { warnings.append("duplicate_cells") }
        let servingMissing = headers.contains { $0.basis == .perServing && ($0.servingConversion ?? "").isEmpty }
        if servingMissing { warnings.append("per_serving_without_printed_serving_quantity") }
        let ready = languages.contains(wire.language) && cells.contains { $0.basis != .referenceIntake } && leftOutAmounts == 0
            && !duplicates && !servingMissing && !warnings.contains { $0.hasPrefix("duplicate_header_id") }
        return LabelCaptureCandidate(route: "C", inputSHA256: inputSHA256, declined: false, declineReasons: [], wouldMarkReady: ready,
                                     language: language, servingSize: serving, servingsPerPack: pack, headers: headers, cells: cells,
                                     warnings: warnings)
    }

    // MARK: The closed value grammar (`draft_untouched_truth`)

    struct Parsed: Equatable {
        let comparator: LabelComparator
        let decimalText: String
        let unit: String
        let canonicalUnit: String
    }

    /// `UNITS`: the printed unit to its canonical unit (looked up as printed, then lower-cased).
    static let units: [String: String] = [
        "大卡": "kcal", "千卡": "kcal", "公克": "g", "克": "g", "毫克": "mg", "微克": "µg", "毫升": "ml", "kcal": "kcal", "kj": "kJ",
        "g": "g", "mg": "mg", "mcg": "µg", "µg": "µg", "μg": "µg", "ml": "ml", "%": "%"
    ]
    /// The `VALUE` pattern's unit alternatives, in the pattern's order.
    static let valueUnits = ["大卡", "千卡", "公克", "毫克", "微克", "毫升", "克", "kcal", "kJ", "kj", "KJ", "mcg", "µg", "μg", "mg", "ml", "mL",
                             "g", "%"]
    static let echoUnits = ["kcal", "kJ", "g", "mg", "mcg", "µg", "ml"]
    static let comparators: [(String, LabelComparator)] = [("<=", .lessOrEqual), ("≤", .lessOrEqual), ("＜", .less), ("<", .less),
                                                           ("少於", .less), ("less than", .less)]

    static func canonical(_ unit: String) -> String? { units[unit] ?? units[unit.lowercased()] }

    /// `parse_value`: comparator, decimal text, printed unit and canonical unit, or nil when the
    /// text is not one printed amount (`VALUE` matched from the start to the end).
    static func parseValue(_ printed: String) -> Parsed? {
        let text = Array(printed)
        var start = PythonText.skipSpace(text, from: 0)
        var comparator = LabelComparator.equal
        var afterComparator: [Int] = [start]
        for (literal, value) in comparators where PythonText.starts(text, at: start, with: literal) {
            afterComparator = [PythonText.skipSpace(text, from: start + literal.count), start]
            comparator = value
            break
        }
        // The comparator group is optional: when it matched, the pattern tries it first.
        for (attempt, position) in afterComparator.enumerated() {
            let used = attempt == 0 && afterComparator.count == 2 ? comparator : .equal
            start = position
            for end in PythonText.decimalEnds(text, from: start, separators: [".", ","]) {
                let unitStart = PythonText.skipSpace(text, from: end)
                for unit in valueUnits where PythonText.starts(text, at: unitStart, with: unit) {
                    guard echoThenEnd(text, from: unitStart + unit.count), let canonical = canonical(unit) else { continue }
                    return Parsed(comparator: used, decimalText: String(text[start..<end]), unit: unit, canonicalUnit: canonical)
                }
            }
        }
        return nil
    }

    /// `\s*(?:[(（]\s*(?:kcal|kJ|g|mg|mcg|µg|ml)\s*[)）])?\s*$` from `index`.
    static func echoThenEnd(_ text: [Character], from index: Int) -> Bool {
        let afterSpace = PythonText.skipSpace(text, from: index)
        if afterSpace == text.count { return true }
        guard text[afterSpace] == "(" || text[afterSpace] == "（" else { return false }
        let unitStart = PythonText.skipSpace(text, from: afterSpace + 1)
        for unit in echoUnits where PythonText.starts(text, at: unitStart, with: unit) {
            let close = PythonText.skipSpace(text, from: unitStart + unit.count)
            if close < text.count, text[close] == ")" || text[close] == "）", PythonText.skipSpace(text, from: close + 1) == text.count {
                return true
            }
        }
        return false
    }

    /// `PRINTED_MASS.search`: `(\d+(?:\.\d+)?)\s*(g|ml|mL|公克|毫升|克)(?![A-Za-z])`, leftmost.
    static func printedMass(_ text: String) -> (number: String, unit: String)? {
        let characters = Array(text)
        for start in characters.indices where PythonText.isDigit(characters[start]) {
            for end in PythonText.decimalEnds(characters, from: start, separators: ["."]) {
                let unitStart = PythonText.skipSpace(characters, from: end)
                for unit in ["g", "ml", "mL", "公克", "毫升", "克"] where PythonText.starts(characters, at: unitStart, with: unit) {
                    let next = unitStart + unit.count
                    if next < characters.count, PythonText.isASCIILetter(characters[next]) { continue }
                    return (String(characters[start..<end]), unit)
                }
            }
        }
        return nil
    }

    static func servingSize(_ text: String) -> LabelServingSize? {
        guard !text.isEmpty, PythonText.strip(text).lowercased() != "unknown" else { return nil }
        guard let mass = printedMass(text) else {
            return Parts.servingSize(printedText: text, decimalText: nil, unit: nil, canonicalUnit: nil)
        }
        return Parts.servingSize(printedText: text, decimalText: mass.number, unit: mass.unit, canonicalUnit: canonical(mass.unit))
    }

    static func servingsPerPack(_ text: String) -> LabelServingsPerPack? {
        guard !text.isEmpty, PythonText.strip(text).lowercased() != "unknown" else { return nil }
        if let match = servingsZh(text) ?? servingsEnTrailing(text) ?? servingsEn(text) {
            return Parts.servingsPerPack(printedText: text, decimalText: match.number, approximate: match.approximate)
        }
        return nil
    }

    /// `SERVINGS.search`: `(約)?\s*(\d+(?:\.\d+)?)\s*份`, leftmost.
    static func servingsZh(_ text: String) -> (number: String, approximate: Bool)? {
        let c = Array(text)
        for start in 0...c.count {
            var attempts: [(Int, Bool)] = []
            if start < c.count, c[start] == "約" { attempts.append((start + 1, true)) }
            attempts.append((start, false))
            for (position, approximate) in attempts {
                let digits = PythonText.skipSpace(c, from: position)
                guard digits < c.count, PythonText.isDigit(c[digits]) else { continue }
                for end in PythonText.decimalEnds(c, from: digits, separators: ["."]) {
                    let mark = PythonText.skipSpace(c, from: end)
                    if mark < c.count, c[mark] == "份" { return (String(c[digits..<end]), approximate) }
                }
            }
        }
        return nil
    }

    /// `SERVINGS_EN.search` (case-insensitive):
    /// `(about|approx\.?|approximately)?\s*(\d+(?:\.\d+)?)\s*servings?`, leftmost.
    static func servingsEn(_ text: String) -> (number: String, approximate: Bool)? {
        let c = Array(text)
        for start in 0...c.count {
            var attempts: [(Int, Bool)] = []
            for word in ["about", "approx.", "approx", "approximately"] where PythonText.startsCaseless(c, at: start, with: word) {
                attempts.append((start + word.count, true))
            }
            attempts.append((start, false))
            for (position, approximate) in attempts {
                let digits = PythonText.skipSpace(c, from: position)
                guard digits < c.count, PythonText.isDigit(c[digits]) else { continue }
                for end in PythonText.decimalEnds(c, from: digits, separators: ["."]) {
                    let word = PythonText.skipSpace(c, from: end)
                    if PythonText.startsCaseless(c, at: word, with: "serving") { return (String(c[digits..<end]), approximate) }
                }
            }
        }
        return nil
    }

    /// `SERVINGS_EN_TRAILING.search` (case-insensitive):
    /// `servings?\s+per\s+(?:container|pack(?:age)?)\D*?(about\s+)?(\d+(?:\.\d+)?)`, leftmost.
    static func servingsEnTrailing(_ text: String) -> (number: String, approximate: Bool)? {
        let c = Array(text)
        for start in c.indices where PythonText.startsCaseless(c, at: start, with: "serving") {
            var afterWord = [start + 7]
            if PythonText.startsCaseless(c, at: start + 7, with: "s") { afterWord.insert(start + 8, at: 0) }
            for position in afterWord {
                guard position < c.count, PythonText.isSpace(c[position]) else { continue }
                let per = PythonText.skipSpace(c, from: position)
                guard PythonText.startsCaseless(c, at: per, with: "per"), per + 3 < c.count, PythonText.isSpace(c[per + 3]) else { continue }
                let noun = PythonText.skipSpace(c, from: per + 3)
                var ends: [Int] = []
                if PythonText.startsCaseless(c, at: noun, with: "container") { ends.append(noun + 9) }
                if PythonText.startsCaseless(c, at: noun, with: "package") { ends.append(noun + 7) }
                if PythonText.startsCaseless(c, at: noun, with: "pack") { ends.append(noun + 4) }
                for end in ends {
                    // `\D*?` is lazy: the shortest run of non-digits after which the rest matches.
                    var lazy = end
                    while lazy <= c.count {
                        if let match = aboutThenNumber(c, from: lazy) { return match }
                        guard lazy < c.count, !PythonText.isDigit(c[lazy]) else { break }
                        lazy += 1
                    }
                }
            }
        }
        return nil
    }

    static func aboutThenNumber(_ c: [Character], from index: Int) -> (number: String, approximate: Bool)? {
        var attempts: [(Int, Bool)] = []
        if PythonText.startsCaseless(c, at: index, with: "about"), index + 5 < c.count, PythonText.isSpace(c[index + 5]) {
            attempts.append((PythonText.skipSpace(c, from: index + 5), true))
        }
        attempts.append((index, false))
        for (position, approximate) in attempts where position < c.count && PythonText.isDigit(c[position]) {
            guard let end = PythonText.decimalEnds(c, from: position, separators: ["."]).first else { continue }
            return (String(c[position..<end]), approximate)
        }
        return nil
    }

    /// Amendment M2: an energy row whose label prints exactly one energy unit and whose value is
    /// a bare number takes that unit, read with `parse_value`; it must agree with the row.
    static func unitFromRowLabel(_ row: LabelPhotoWire.Row, printed: String) -> Parsed? {
        guard row.nutrient == "energy_kj" || row.nutrient == "energy_kcal", PythonText.isBareNumber(printed) else { return nil }
        let found = energyLabelUnits(row.printedLabel)
        guard Set(found.map { $0.lowercased() }).count == 1, let unit = found.first else { return nil }
        guard let parsed = parseValue(PythonText.strip(printed) + unit),
              parsed.canonicalUnit == (row.nutrient == "energy_kj" ? "kJ" : "kcal") else { return nil }
        return parsed
    }

    /// `ENERGY_LABEL_UNIT.findall` (case-insensitive): `(?<![A-Za-z])(kJ|kcal)(?![A-Za-z])`.
    static func energyLabelUnits(_ label: String) -> [String] {
        let c = Array(label)
        var found: [String] = []
        var index = 0
        while index < c.count {
            if index > 0, PythonText.isASCIILetter(c[index - 1]) { index += 1; continue }
            var matched = false
            for unit in ["kj", "kcal"] where PythonText.startsCaseless(c, at: index, with: unit) {
                let end = index + unit.count
                if end < c.count, PythonText.isASCIILetter(c[end]) { continue }
                found.append(String(c[index..<end])); index = end; matched = true
                break
            }
            if !matched { index += 1 }
        }
        return found
    }
}

/// The candidate's header and serving types have no public memberwise initialiser, and their
/// file is pinned by the reader v3 freeze, so they are built through their public `Decodable`
/// conformance from the same members.
enum Parts {
    static func decode<T: Decodable>(_ type: T.Type, _ members: [String: Any?]) -> T {
        let object = members.mapValues { $0 ?? NSNull() }
        // Plain strings and booleans only, so neither step can fail.
        // swiftlint:disable:next force_try
        return try! JSONDecoder().decode(T.self, from: JSONSerialization.data(withJSONObject: object))
    }

    static func header(id: String, printedText: String, basis: LabelBasis, servingConversion: String?) -> LabelHeader {
        decode(LabelHeader.self, ["header_id": id, "printed_text": printedText, "basis": basis.rawValue, "serving_conversion": servingConversion])
    }

    static func servingSize(printedText: String, decimalText: String?, unit: String?, canonicalUnit: String?) -> LabelServingSize {
        decode(LabelServingSize.self, ["printed_text": printedText, "decimal_text": decimalText, "unit": unit, "canonical_unit": canonicalUnit])
    }

    static func servingsPerPack(printedText: String, decimalText: String, approximate: Bool) -> LabelServingsPerPack {
        decode(LabelServingsPerPack.self, ["printed_text": printedText, "decimal_text": decimalText, "approximate": approximate])
    }
}

/// The few Python `str` and `re` behaviours the mapping depends on.
enum PythonText {
    /// `\d` in a `str` pattern: any character of category Nd.
    static func isDigit(_ character: Character) -> Bool {
        character.unicodeScalars.count == 1 && character.unicodeScalars.first!.properties.generalCategory == .decimalNumber
    }

    /// `\s` in a `str` pattern, and `str.isspace`.
    static func isSpace(_ character: Character) -> Bool {
        guard character.unicodeScalars.count == 1, let scalar = character.unicodeScalars.first else {
            return character == "\r\n"
        }
        if (0x1C...0x1F).contains(scalar.value) { return true }
        return scalar.properties.isWhitespace
    }

    static func isASCIILetter(_ character: Character) -> Bool { character.isASCII && character.isLetter }

    static func skipSpace(_ text: [Character], from index: Int) -> Int {
        var index = index
        while index < text.count, isSpace(text[index]) { index += 1 }
        return index
    }

    static func starts(_ text: [Character], at index: Int, with literal: String) -> Bool {
        let pattern = Array(literal)
        guard index >= 0, index + pattern.count <= text.count else { return false }
        return Array(text[index..<(index + pattern.count)]) == pattern
    }

    /// Case-insensitive ASCII comparison (`re.IGNORECASE` on these ASCII words).
    static func startsCaseless(_ text: [Character], at index: Int, with literal: String) -> Bool {
        let pattern = Array(literal)
        guard index >= 0, index + pattern.count <= text.count else { return false }
        return zip(text[index..<(index + pattern.count)], pattern).allSatisfy { $0.lowercased() == $1.lowercased() }
    }

    /// The ends of `\d+(?:[sep]\d+)?` from `start`, in the order the pattern backtracks: the
    /// longest integer part with its fraction first, then without, then shorter integer parts.
    static func decimalEnds(_ text: [Character], from start: Int, separators: Set<Character>) -> [Int] {
        var integerEnd = start
        while integerEnd < text.count, isDigit(text[integerEnd]) { integerEnd += 1 }
        guard integerEnd > start else { return [] }
        var ends: [Int] = []
        for end in stride(from: integerEnd, to: start, by: -1) {
            if end < text.count, separators.contains(text[end]) {
                var fraction = end + 1
                while fraction < text.count, isDigit(text[fraction]) { fraction += 1 }
                if fraction > end + 1 {
                    // `\d+` in the fraction also backtracks, longest first.
                    ends.append(contentsOf: stride(from: fraction, to: end + 1, by: -1))
                }
            }
            ends.append(end)
        }
        return ends
    }

    /// `str.strip()`.
    static func strip(_ text: String) -> String {
        let c = Array(text)
        var start = 0, end = c.count
        while start < end, isSpace(c[start]) { start += 1 }
        while end > start, isSpace(c[end - 1]) { end -= 1 }
        return String(c[start..<end])
    }

    /// `BARE_NUMBER.fullmatch`: `\s*\d+(?:[.,]\d+)?\s*`.
    static func isBareNumber(_ text: String) -> Bool {
        let c = Array(text)
        let start = skipSpace(c, from: 0)
        return decimalEnds(c, from: start, separators: [".", ","]).contains { skipSpace(c, from: $0) == c.count }
    }

    /// `repr(str)` as Python 3 writes it.
    static func repr(_ text: String) -> String {
        let quote: Character = text.contains("'") && !text.contains("\"") ? "\"" : "'"
        var out = String(quote)
        for scalar in text.unicodeScalars {
            switch scalar {
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            default:
                if Character(scalar) == quote {
                    out += "\\" + String(quote)
                } else if isPrintable(scalar) {
                    out.unicodeScalars.append(scalar)
                } else if scalar.value < 0x100 {
                    out += String(format: "\\x%02x", scalar.value)
                } else if scalar.value < 0x10000 {
                    out += String(format: "\\u%04x", scalar.value)
                } else {
                    out += String(format: "\\U%08x", scalar.value)
                }
            }
        }
        out.append(quote)
        return out
    }

    /// `str.isprintable` for one character: not in categories Cc, Cf, Cs, Co, Cn, Zl, Zp, or Zs
    /// other than the space.
    static func isPrintable(_ scalar: Unicode.Scalar) -> Bool {
        if scalar == " " { return true }
        switch scalar.properties.generalCategory {
        case .control, .format, .surrogate, .privateUse, .unassigned, .lineSeparator, .paragraphSeparator, .spaceSeparator: return false
        default: return true
        }
    }
}
