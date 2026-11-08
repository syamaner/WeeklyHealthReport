import FoodLedgerApplication
import Foundation
import NutritionLabelParsing

/// `pasted-label-ai-text-mapping-v1` (docs/pasted-label-ai-text-v1.md 4.2, 4.3 item 2, D10, D16;
/// A1 finding F9): one text wire answer, checked against the sent text, to
/// `label-capture-candidate-v1` with route `C` (the model-read route gate v2 admits). Pure. It
/// never converts, infers or fills a value. It is `label-photo-wire-mapping-v1` with these
/// differences:
///
/// - **Its own copy of `parseValue`**, over the application layer's closed lists
///   (`PastedLabelAITextValueGrammar`), since the photo copy is internal to a pinned file. It
///   equals the photo copy (contract test 26) except for the **thousands rule**: a `,` followed by
///   exactly three digits and then a non-digit is a thousands separator (`1,046kJ` is 1046), where
///   the photo copy reads every `,` as a decimal mark. A thousands group led by `0` (`0,500g`) is
///   ambiguous: it is never 500 (nor 0.5), and is an attention item.
/// - **The model's unit for a bare number** is accepted only when the unit check
///   (`PastedLabelAITextUnitCheck`) finds it stated for the values in the text, in the row's label or
///   the column's header (D10). A header's basis quantity never states one (D16). A unit the check
///   does not find is still read, under attention (`unit_not_stated`); a unit outside the closed
///   table cannot be read, and is a not-read attention item. A printed unit is never overridden.
/// - **A bare number with no model unit is not read** (F9): a not-read cell, never a value, under
///   a blocking `unit_not_stated` attention item so the user enters it. The photo route's amendment M2 (a bare energy number taking the row label's
///   energy unit) is replaced by the unit check, which needs the model's unit.
///
/// Everything else (headers, M3, row IDs, parents, M1, duplicate cells, ready) is v1's.
public enum PastedLabelAITextWireMapping {
    public static let version = PastedLabelAITextUnitCheck.mappingVersion
    public static let route = "C"
    static let languages: Set<String> = ["en", "zh-Hant", "mixed"]

    /// One wire value's mapping: the cell it became, or why it was not read.
    public struct ValueMapping: Equatable, Sendable {
        public let rowIndex: Int
        public let valueIndex: Int
        public let read: PastedLabelAITextReadingResult.Read
        public let unitCheck: PastedLabelAITextUnitCheck.Outcome
        /// The mapping's own attention reasons for the value (the thousands rule, the unit check, duplicates).
        public let reasons: [PastedLabelAITextAttention.Reason]
    }

    public struct Mapped: Equatable, Sendable {
        public let candidate: LabelCaptureCandidate
        public let values: [ValueMapping]
        public let located: PastedLabelTextLocator.Result
    }

    /// The headers and rows the locator checks, from the wire (headers after duplicate IDs are dropped).
    static func locatorInput(_ wire: PastedLabelAITextWire) -> (headers: [PastedLabelTextLocator.Header], rows: [PastedLabelTextLocator.Row]) {
        var seen: Set<String> = []
        let headers = wire.headers.compactMap { header -> PastedLabelTextLocator.Header? in
            guard seen.insert(header.headerID).inserted else { return nil }
            return PastedLabelTextLocator.Header(id: header.headerID, printedText: header.printedText, basis: header.basis)
        }
        let rows = wire.rows.map { row in
            PastedLabelTextLocator.Row(printedLabel: row.printedLabel,
                                       values: row.values.map { PastedLabelTextLocator.Value(headerID: $0.headerID, printedText: $0.printedText) })
        }
        return (headers, rows)
    }

    /// One candidate from one schema-valid wire answer, checked against the sent `text`.
    public static func map(_ wire: PastedLabelAITextWire, text: String, inputSHA256: String) -> Mapped {
        let input = locatorInput(wire)
        let located = PastedLabelTextLocator.locate(text: text, headers: input.headers, rows: input.rows)
        let language = LabelLanguage(rawValue: wire.language) ?? .unknown
        if wire.declined {
            return Mapped(candidate: .declined(route: route, inputSHA256: inputSHA256, language: language,
                                               reasons: wire.declineReasons.isEmpty ? ["declined_without_reason"] : wire.declineReasons),
                          values: [], located: located)
        }
        let units = wire.rows.map { $0.values.map(\.unit) }
        let outcomes = PastedLabelAITextUnitCheck.check(text: text, rows: input.rows, units: units, located: located)
        var unitByValue: [[Int]: PastedLabelAITextUnitCheck.Outcome] = [:]
        for (value, outcome) in zip(located.values, outcomes) { unitByValue[[value.rowIndex, value.valueIndex]] = outcome }

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
            if header.basis == "per_serving", quantity == nil, let printed = TextPython.printedMass(header.printedText) {
                quantity = printed.number + printed.unit
                warnings.append("serving_quantity_from_header: \(header.headerID)")
            }
            guard let basis = LabelBasis(rawValue: header.basis) else { continue }
            headerIDs.insert(header.headerID)
            headers.append(TextParts.header(id: header.headerID, printedText: header.printedText, basis: basis,
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
        var values: [ValueMapping] = []
        var leftOutAmounts = 0
        for (rowIndex, (row, rowID)) in zip(wire.rows, rowIDs).enumerated() {
            let parent = TextPython.strip(row.parentNutrient)
            let parentRow = !parent.isEmpty && !["none", "unknown", rowID, row.nutrient].contains(parent) && present.contains(parent) ? parent : nil
            for (valueIndex, value) in row.values.enumerated() {
                let printed = value.printedText
                let unitCheck = unitByValue[[rowIndex, valueIndex]] ?? .notAValue
                func notRead(_ reason: PastedLabelAITextReadingResult.NotRead, _ reasons: [PastedLabelAITextAttention.Reason] = []) {
                    values.append(ValueMapping(rowIndex: rowIndex, valueIndex: valueIndex, read: .notRead(reason), unitCheck: unitCheck, reasons: reasons))
                }
                guard let header = byID[value.headerID] else {
                    warnings.append("value_without_header: \(rowID) \(value.headerID)")
                    leftOutAmounts += 1
                    notRead(.undeclaredHeader)
                    continue
                }
                let amountColumn = header.basis != .referenceIntake
                var parsed: Parsed?
                var reasons: [PastedLabelAITextAttention.Reason] = PastedLabelAITextAttention.reason(unitCheck).map { [$0] } ?? []
                if TextPython.strip(printed).lowercased() == "unknown" {
                    warnings.append("value_not_read: \(rowID) \(header.headerID) unknown")
                    if amountColumn { leftOutAmounts += 1 }
                    notRead(.unknown)
                    continue
                }
                switch parseValue(printed) {
                case let .value(value):
                    parsed = value
                case .thousandsLedByZero:
                    warnings.append("value_not_read: \(rowID) \(header.headerID) thousands group led by 0")
                    if amountColumn { leftOutAmounts += 1 }
                    notRead(.thousandsLedByZero, [.ambiguous])
                    continue
                case .notAValue:
                    guard isBareNumber(printed) else { break }
                    guard let modelUnit = value.unit else {
                        // F9: a bare number with no unit is a not-read cell, never a value. It is a
                        // blocking `unit_not_stated` item, so the user is prompted (A2 gate finding 3).
                        warnings.append("value_not_read: \(rowID) \(header.headerID) bare number without unit")
                        if amountColumn { leftOutAmounts += 1 }
                        notRead(.bareNumberWithoutUnit, [.unitNotStated])
                        continue
                    }
                    guard PastedLabelAITextValueGrammar.canonicalUnit(modelUnit) != nil,
                          case let .value(withUnit) = parseValue(TextPython.strip(printed) + modelUnit) else {
                        warnings.append("value_not_read: \(rowID) \(header.headerID) model unit outside the table")
                        if amountColumn { leftOutAmounts += 1 }
                        notRead(.unitOutsideTable, [.unitNotStated])
                        continue
                    }
                    parsed = withUnit
                    warnings.append("unit_from_model: \(rowID) \(header.headerID) \(unitCheck.rawValue)")
                }
                guard let read = parsed else {
                    warnings.append("value_not_read: \(rowID) \(header.headerID) \(TextPython.repr(printed))")
                    if amountColumn { leftOutAmounts += 1 }
                    notRead(.unreadable)
                    continue
                }
                if !amountColumn, read.canonicalUnit != "%" {
                    warnings.append("value_not_read: \(rowID) \(header.headerID) \(TextPython.repr(printed)) (absolute reference value)")
                    notRead(.absoluteReferenceValue)
                    continue
                }
                if cells.contains(where: { $0.rowID == rowID && $0.headerID == header.headerID }) { reasons.append(.ambiguous) }
                cells.append(LabelCell(rowID: rowID, parentRowID: parentRow, nutrient: row.nutrient, printedLabel: row.printedLabel,
                    headerID: header.headerID, basis: header.basis, printedText: printed, comparator: read.comparator,
                    decimalText: read.decimalText, unit: read.unit, canonicalUnit: read.canonicalUnit,
                    servingConversion: header.basis == .perServing ? (header.servingConversion ?? "unknown") : "not_applicable"))
                values.append(ValueMapping(rowIndex: rowIndex, valueIndex: valueIndex, read: .cell(rowID: rowID), unitCheck: unitCheck,
                                           reasons: PastedLabelAITextAttention.ordered(reasons)))
            }
        }
        let pairs = cells.map { $0.rowID + "\u{0}" + $0.headerID }
        let duplicates = pairs.count != Set(pairs).count
        if duplicates {
            warnings.append("duplicate_cells")
            // Both values of a duplicated row and header are ambiguous, not only the second.
            let repeated = Set(pairs.filter { pair in pairs.filter { $0 == pair }.count > 1 })
            values = values.map { value in
                guard let rowID = value.read.rowID, repeated.contains(rowID + "\u{0}" + (wire.rows[value.rowIndex].values[value.valueIndex].headerID)) else {
                    return value
                }
                return ValueMapping(rowIndex: value.rowIndex, valueIndex: value.valueIndex, read: value.read, unitCheck: value.unitCheck,
                                    reasons: PastedLabelAITextAttention.ordered(value.reasons + [.ambiguous]))
            }
        }
        let servingMissing = headers.contains { $0.basis == .perServing && ($0.servingConversion ?? "").isEmpty }
        if servingMissing { warnings.append("per_serving_without_printed_serving_quantity") }
        let ready = languages.contains(wire.language) && cells.contains { $0.basis != .referenceIntake } && leftOutAmounts == 0
            && !duplicates && !servingMissing && !warnings.contains { $0.hasPrefix("duplicate_header_id") }
        let candidate = LabelCaptureCandidate(route: route, inputSHA256: inputSHA256, declined: false, declineReasons: [], wouldMarkReady: ready,
                                              language: language, servingSize: serving, servingsPerPack: pack, headers: headers, cells: cells,
                                              warnings: warnings)
        return Mapped(candidate: candidate, values: values, located: located)
    }

    // MARK: The closed value grammar (a copy of the photo mapping's, over the application's lists)

    struct Parsed: Equatable {
        let comparator: LabelComparator
        let decimalText: String
        let unit: String
        let canonicalUnit: String
    }

    enum ParseResult: Equatable {
        case value(Parsed)
        /// A thousands group led by `0` (`0,500g`): ambiguous, so not read.
        case thousandsLedByZero
        case notAValue
    }

    static let comparators: [(String, LabelComparator)] = PastedLabelAITextValueGrammar.comparators.compactMap { entry in
        LabelComparator(rawValue: entry.value).map { (entry.printed, $0) }
    }

    /// `parse_value` with the text route's thousands rule (4.3 item 2). Every thousands separator
    /// (a `,` after a digit and followed by exactly three digits and then a non-digit or the end) is
    /// removed before the copied grammar reads the number; a number whose first group is `0` is
    /// ambiguous. Without a thousands separator the copied grammar runs on the text unchanged, so
    /// parity with the photo copy holds there by construction (contract test 26).
    static func parseValue(_ printed: String) -> ParseResult {
        let characters = Array(printed)
        var separators: [Int] = []
        for index in characters.indices where characters[index] == "," && index > 0 && TextPython.isDigit(characters[index - 1]) {
            let end = index + 4
            guard end <= characters.count, (index + 1..<end).allSatisfy({ TextPython.isDigit(characters[$0]) }),
                  end == characters.count || !TextPython.isDigit(characters[end]) else { continue }
            separators.append(index)
        }
        guard let first = separators.first else { return photoGrammar(printed).map(ParseResult.value) ?? .notAValue }
        var start = first - 1
        while start > 0, TextPython.isDigit(characters[start - 1]) { start -= 1 }
        if characters[start..<first].allSatisfy({ $0.wholeNumberValue == 0 }) {
            return .thousandsLedByZero
        }
        var removed = characters
        for index in separators.reversed() { removed.remove(at: index) }
        return photoGrammar(String(removed)).map(ParseResult.value) ?? .notAValue
    }

    /// The copy of `LabelPhotoWireMapping.parseValue`: comparator, decimal text, printed unit and
    /// canonical unit, or nil when the text is not one printed amount.
    static func photoGrammar(_ printed: String) -> Parsed? {
        let text = Array(printed)
        var start = TextPython.skipSpace(text, from: 0)
        var comparator = LabelComparator.equal
        var afterComparator: [Int] = [start]
        for (literal, value) in comparators where TextPython.starts(text, at: start, with: literal) {
            afterComparator = [TextPython.skipSpace(text, from: start + literal.count), start]
            comparator = value
            break
        }
        for (attempt, position) in afterComparator.enumerated() {
            let used = attempt == 0 && afterComparator.count == 2 ? comparator : .equal
            start = position
            for end in TextPython.decimalEnds(text, from: start, separators: [".", ","]) {
                let unitStart = TextPython.skipSpace(text, from: end)
                for unit in PastedLabelAITextValueGrammar.valueUnits where TextPython.starts(text, at: unitStart, with: unit) {
                    guard echoThenEnd(text, from: unitStart + unit.count), let canonical = PastedLabelAITextValueGrammar.canonicalUnit(unit) else {
                        continue
                    }
                    return Parsed(comparator: used, decimalText: String(text[start..<end]), unit: unit, canonicalUnit: canonical)
                }
            }
        }
        return nil
    }

    /// `\s*(?:[(（]\s*(?:kcal|kJ|g|mg|mcg|µg|ml)\s*[)）])?\s*$` from `index`.
    static func echoThenEnd(_ text: [Character], from index: Int) -> Bool {
        let afterSpace = TextPython.skipSpace(text, from: index)
        if afterSpace == text.count { return true }
        guard text[afterSpace] == "(" || text[afterSpace] == "（" else { return false }
        let unitStart = TextPython.skipSpace(text, from: afterSpace + 1)
        for unit in PastedLabelAITextValueGrammar.echoUnits where TextPython.starts(text, at: unitStart, with: unit) {
            let close = TextPython.skipSpace(text, from: unitStart + unit.count)
            if close < text.count, text[close] == ")" || text[close] == "）", TextPython.skipSpace(text, from: close + 1) == text.count {
                return true
            }
        }
        return false
    }

    /// A bare number: one comparator-or-not value token of the 4.3 grammar with no unit, and nothing else.
    static func isBareNumber(_ printed: String) -> Bool {
        let scan = PastedLabelTextScan(TextPython.strip(printed))
        guard scan.tokens.count == 1, let token = scan.tokens.first else { return false }
        return token.start == 0 && token.coreEnd == scan.scalars.count && token.unit == nil
    }

    static func servingSize(_ text: String) -> LabelServingSize? {
        guard !text.isEmpty, TextPython.strip(text).lowercased() != "unknown" else { return nil }
        guard let mass = TextPython.printedMass(text) else {
            return TextParts.servingSize(printedText: text, decimalText: nil, unit: nil, canonicalUnit: nil)
        }
        return TextParts.servingSize(printedText: text, decimalText: mass.number, unit: mass.unit,
                                     canonicalUnit: PastedLabelAITextValueGrammar.canonicalUnit(mass.unit))
    }

    /// v1's pack count rule: `(約)?\s*(\d+(?:\.\d+)?)\s*份`, then `servings per (container|pack|package) ... N`, then `N servings`.
    static func servingsPerPack(_ text: String) -> LabelServingsPerPack? {
        guard !text.isEmpty, TextPython.strip(text).lowercased() != "unknown" else { return nil }
        if let match = TextPython.servingsZh(text) ?? TextPython.servingsEnTrailing(text) ?? TextPython.servingsEn(text) {
            return TextParts.servingsPerPack(printedText: text, decimalText: match.number, approximate: match.approximate)
        }
        return nil
    }
}

/// The candidate's header and serving types are built through their public `Decodable`
/// conformance (their file is pinned by the reader v3 freeze), as the photo mapping does.
enum TextParts {
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
