import Foundation

/// Deterministic parser for printed nutrition-table text (routes A and B of the
/// nutrition-label capture evaluation, `docs/nutrition-label-capture-evaluation-v1.md`).
///
/// It recognises English (UK and US) tables and Taiwan 營養標示 tables, keeps bounds as
/// bounds and printed units as printed, and declines rather than guessing. It never
/// converts salt to sodium, kJ to kcal, a reference-intake percentage to an amount or a
/// per-serving value to per 100 g. It has no network, clock, randomness or hashing
/// dependency: the caller supplies the input hash.
public struct NutritionLabelTextParser: Sendable {
    public static let version = "nutrition-label-text-parser-v1"

    public init() {}

    public func parse(_ text: String, route: String = "A", inputSHA256: String) -> LabelCaptureCandidate {
        var state = ParseState()
        let normalised = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\u{00A0}", with: " ")
        let language = Self.language(of: normalised)
        if Self.hasUnsupportedScript(normalised) || (language == .unknown && !normalised.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) {
            return .declined(route: route, inputSHA256: inputSHA256, language: language, reasons: ["unsupported_language"])
        }
        for rawLine in normalised.components(separatedBy: "\n") {
            state.consume(rawLine)
            if !state.declineReasons.isEmpty { break }
        }
        return state.finish(route: route, inputSHA256: inputSHA256, language: language)
    }

    /// Japanese kana, Korean Hangul (syllables, jamo and compatibility jamo) or a
    /// Simplified-only character means the label is outside `en` and `zh-Hant`.
    static func hasUnsupportedScript(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            (0x3040...0x30FF).contains(scalar.value) || (0xAC00...0xD7AF).contains(scalar.value)
                || (0x1100...0x11FF).contains(scalar.value) || (0x3130...0x318F).contains(scalar.value)
        }
            || text.contains { LabelVocabulary.unsupportedScriptMarkers.contains($0) }
    }

    static func language(of text: String) -> LabelLanguage {
        let hasHan = text.unicodeScalars.contains { (0x4E00...0x9FFF).contains($0.value) }
        let words = Patterns.latinWord.matches(in: text).map { $0.lowercased() }
        let unitWords: Set<String> = ["kj", "kcal", "cal", "mg", "mcg", "ml"]
        let hasLatin = words.contains { !unitWords.contains($0) }
        switch (hasHan, hasLatin) {
        case (true, true): return .mixed
        case (true, false): return .traditionalChinese
        case (false, true): return .english
        case (false, false): return .unknown
        }
    }
}

// MARK: - Patterns

enum Patterns {
    static let value = LabelPattern(
        #"(?<![\p{L}\p{N}.,])(less than|<=|≤|＜|<|少於)?\s*(\d+(?:[.,]\d+)?)\s*(kJ|kj|KJ|Kj|kcal|Kcal|KCAL|kCal|Cal|cal|mcg|mg|µg|μg|mL|ml|g|%|大卡|千卡|公克|毫克|微克|毫升|克)?(?![\p{L}])"#
    )
    static let latinWord = LabelPattern(#"[A-Za-z]{2,}"#)
    static let headerPhrase = LabelPattern(#"(?i)\bper\b|每份|每\s*100|每日參考值|%\s*RI|\bRI\b|reference intake|%\s*DV|daily value|\bNRV\b"#)
    static let headerSplit = LabelPattern(#"\t|\s{2,}|　+"#)
    static let headerBoundary = LabelPattern(#"(?i)(?=\bper\b|%\s*RI|%\s*DV|每份|每\s*100|每日參考值)"#)
    static let referenceIntake = LabelPattern(#"(?i)%\s*RI|\bRI\b|reference intake|%\s*DV|daily value|\bNRV\b|每日參考值"#)
    static let per100g = LabelPattern(#"(?i)per\s*100\s*g\b|^100\s*g$|每\s*100\s*(公克|克)"#)
    static let per100ml = LabelPattern(#"(?i)per\s*100\s*ml\b|^100\s*ml$|每\s*100\s*毫升"#)
    static let perServing = LabelPattern(#"(?i)\bper\b|每份"#)
    static let parenthesised = LabelPattern(#"[(（]([^)）]+)[)）]"#)
    static let perQuantity = LabelPattern(#"(?i)\bper\s+(\d+(?:\.\d+)?\s*(?:g|ml))\b"#)
    static let title = LabelPattern(#"(?i)^(營養標示|營養成分|nutrition(al)?( information| facts| declaration)?|typical values?|nutrition information typical values)[:：]?$"#)
    static let servingsPerPack = [
        LabelPattern(#"(?i)^servings?\s+per\s+(?:container|pack|package)\s*[:：]?\s*(about\s+)?(\d+(?:\.\d+)?)"#),
        LabelPattern(#"(?i)^(?:this\s+pack\s+contains|pack\s+contains|contains)\s+(about\s+)?(\d+(?:\.\d+)?)\s+(?:servings|portions)"#),
        LabelPattern(#"^本包裝含\s*(約)?\s*(\d+(?:\.\d+)?)\s*份"#),
    ]
    static let servingSize = LabelPattern(#"(?i)^(?:serving\s+size|portion\s+size|每一?份量)\s*[:：]?\s*(.+)$"#)
    static let servingQuantity = LabelPattern(#"(\d+(?:\.\d+)?)\s*(g|ml|mL|公克|毫升|克)(?![\p{L}])"#)
    static let labelUnitHint = LabelPattern(#"[(（]\s*(g|mg|µg|mcg|kJ|kj|kcal|公克|毫克|大卡)\s*[)）]"#)
}

/// Minimal NSRegularExpression wrapper with deterministic, UTF-16-safe ranges.
struct LabelPattern: @unchecked Sendable {
    let expression: NSRegularExpression

    init(_ pattern: String) {
        // Patterns are compile-time literals covered by tests.
        expression = try! NSRegularExpression(pattern: pattern)
    }

    func firstMatch(in text: String) -> [String?]? {
        let range = NSRange(text.startIndex..., in: text)
        guard let match = expression.firstMatch(in: text, range: range) else { return nil }
        return (0..<match.numberOfRanges).map { index in
            Range(match.range(at: index), in: text).map { String(text[$0]) }
        }
    }

    func contains(_ text: String) -> Bool { firstMatch(in: text) != nil }

    func matches(in text: String) -> [String] {
        let range = NSRange(text.startIndex..., in: text)
        return expression.matches(in: text, range: range).compactMap { Range($0.range, in: text).map { String(text[$0]) } }
    }

    func matchDetails(in text: String) -> [(range: Range<String.Index>, groups: [String?])] {
        let range = NSRange(text.startIndex..., in: text)
        return expression.matches(in: text, range: range).compactMap { match in
            guard let whole = Range(match.range, in: text) else { return nil }
            let groups = (0..<match.numberOfRanges).map { index in
                Range(match.range(at: index), in: text).map { String(text[$0]) }
            }
            return (whole, groups)
        }
    }

    func split(_ text: String) -> [String] {
        var pieces: [String] = []
        var cursor = text.startIndex
        let range = NSRange(text.startIndex..., in: text)
        for match in expression.matches(in: text, range: range) {
            guard let found = Range(match.range, in: text) else { continue }
            pieces.append(String(text[cursor..<found.lowerBound]))
            cursor = found.upperBound
        }
        pieces.append(String(text[cursor...]))
        return pieces
    }
}

// MARK: - Parse state

struct PrintedValue {
    var printedText: String
    var comparator: LabelComparator
    var decimalText: String
    var unit: String?
}

struct RowDraft {
    var label: String
    var indented: Bool
    var values: [PrintedValue]
}

struct ParseState {
    var headers: [LabelHeader] = []
    var rows: [RowDraft] = []
    var servingSize: LabelServingSize?
    var servingsPerPack: LabelServingsPerPack?
    var declineReasons: [String] = []
    var lastLineWasHeader = false
    var rowsStarted = false

    mutating func consume(_ rawLine: String) {
        let content = rawLine.trimmingCharacters(in: .whitespaces.union(CharacterSet(charactersIn: "\u{3000}")))
        guard !content.isEmpty else { return }
        if content.hasPrefix("*") || content.hasPrefix("＊") || content.hasPrefix("†") { return }

        for pattern in Patterns.servingsPerPack {
            if let groups = pattern.firstMatch(in: content), let number = groups[2] {
                if servingsPerPack == nil {
                    servingsPerPack = LabelServingsPerPack(printedText: content, decimalText: number, approximate: groups[1] != nil)
                }
                lastLineWasHeader = false
                return
            }
        }
        if let groups = Patterns.servingSize.firstMatch(in: content), let rest = groups[1] {
            if servingSize == nil { servingSize = Self.servingSize(printed: content, quantityText: rest) }
            lastLineWasHeader = false
            return
        }
        if Patterns.title.contains(content) {
            if rowsStarted, content.contains("營養標示") || content.lowercased().hasPrefix("nutrition") {
                declineReasons.append("multiple_panels")
            }
            return
        }
        if lastLineWasHeader, let groups = Patterns.parenthesised.firstMatch(in: content), groups[0] == content,
           let index = headers.lastIndex(where: { $0.basis == .perServing }) {
            headers[index].printedText += " " + content
            if headers[index].servingConversion == nil { headers[index].servingConversion = groups[1]?.trimmingCharacters(in: .whitespaces) }
            return
        }
        if Patterns.headerPhrase.contains(content) {
            consumeHeader(content)
            return
        }
        lastLineWasHeader = false
        consumeRow(rawLine: rawLine, content: content)
    }

    mutating func consumeHeader(_ content: String) {
        var segments = Patterns.headerSplit.split(content).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if segments.count == 1 {
            segments = Patterns.headerBoundary.split(content).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        }
        var found: [LabelHeader] = []
        for segment in segments {
            guard let basis = Self.basis(of: segment) else { continue }
            var conversion: String?
            if basis == .perServing {
                if let quantity = Self.outermostParenthesised(segment) {
                    conversion = quantity
                } else if let groups = Patterns.perQuantity.firstMatch(in: segment) {
                    conversion = groups[1]
                }
            }
            found.append(LabelHeader(headerID: "", printedText: segment, basis: basis, servingConversion: conversion))
        }
        guard !found.isEmpty else { return }
        if rowsStarted {
            let referenceOnly = found.allSatisfy { $0.basis == .referenceIntake }
            if !(referenceOnly && !headers.contains { $0.basis == .referenceIntake }) {
                declineReasons.append("multiple_panels")
                return
            }
        }
        for header in found {
            var numbered = header
            numbered.headerID = "header_\(headers.count + 1)"
            headers.append(numbered)
        }
        lastLineWasHeader = true
    }

    mutating func consumeRow(rawLine: String, content: String) {
        let details = Patterns.value.matchDetails(in: content)
        let label: String
        if let first = details.first {
            label = String(content[content.startIndex..<first.range.lowerBound])
        } else {
            label = content
        }
        let cleanedLabel = label
            .trimmingCharacters(in: .whitespaces.union(CharacterSet(charactersIn: "\u{3000}\t:：-–·•")))
        let values = details.map { match -> PrintedValue in
            let printed = String(content[match.range]).trimmingCharacters(in: .whitespaces)
            let comparator: LabelComparator
            switch match.groups[1] {
            case "<=", "≤": comparator = .lessOrEqual
            case nil: comparator = .equal
            default: comparator = .less
            }
            return PrintedValue(printedText: printed, comparator: comparator, decimalText: match.groups[2] ?? "", unit: match.groups[3])
        }
        let indented = rawLine.hasPrefix("\u{3000}") || rawLine.hasPrefix("  ") || rawLine.hasPrefix(" \t")
        if !cleanedLabel.isEmpty {
            rowsStarted = true
            if var last = rows.last, last.values.isEmpty,
               RowClassifier.classify(last.label) == nil,
               RowClassifier.classify(cleanedLabel) == nil || RowClassifier.classify(last.label + " " + cleanedLabel) != nil {
                last.label += " " + cleanedLabel
                last.values = values
                rows[rows.count - 1] = last
            } else {
                rows.append(RowDraft(label: cleanedLabel, indented: indented, values: values))
            }
        } else if !values.isEmpty {
            guard !rows.isEmpty else {
                declineReasons.append("values_without_row")
                return
            }
            rows[rows.count - 1].values += values
        }
    }

    /// Text between the first opening and the last closing parenthesis, so nested
    /// quantities such as `(¼ pack (68g))` stay whole.
    static func outermostParenthesised(_ text: String) -> String? {
        guard let open = text.firstIndex(where: { $0 == "(" || $0 == "（" }),
              let close = text.lastIndex(where: { $0 == ")" || $0 == "）" }), open < close else { return nil }
        let inner = text[text.index(after: open)..<close].trimmingCharacters(in: .whitespaces)
        return inner.isEmpty ? nil : inner
    }

    static func basis(of segment: String) -> LabelBasis? {
        if Patterns.referenceIntake.contains(segment) { return .referenceIntake }
        if Patterns.per100ml.contains(segment) { return .per100ml }
        if Patterns.per100g.contains(segment) { return .per100g }
        if Patterns.perServing.contains(segment) { return .perServing }
        return nil
    }

    static func servingSize(printed: String, quantityText: String) -> LabelServingSize {
        let source = Patterns.parenthesised.firstMatch(in: quantityText)?[1] ?? quantityText
        if let groups = Patterns.servingQuantity.firstMatch(in: source) ?? Patterns.servingQuantity.firstMatch(in: quantityText),
           let number = groups[1], let unit = groups[2] {
            return LabelServingSize(printedText: printed, decimalText: number, unit: unit, canonicalUnit: LabelVocabulary.canonicalUnit(unit))
        }
        return LabelServingSize(printedText: printed, decimalText: nil, unit: nil, canonicalUnit: nil)
    }

    // MARK: Binding

    func finish(route: String, inputSHA256: String, language: LabelLanguage) -> LabelCaptureCandidate {
        func decline(_ reasons: [String]) -> LabelCaptureCandidate {
            .declined(route: route, inputSHA256: inputSHA256, language: language, reasons: reasons)
        }
        if !declineReasons.isEmpty { return decline(declineReasons) }
        if rows.isEmpty { return decline(["no_table"]) }
        let amountHeaders = headers.filter { $0.basis != .referenceIntake }
        let referenceHeaders = headers.filter { $0.basis == .referenceIntake }
        if amountHeaders.isEmpty { return decline(["no_basis_header"]) }
        let byBasis = Dictionary(grouping: headers, by: \.basis)
        for (_, group) in byBasis where group.count > 1 {
            let texts = Set(group.map { $0.printedText.lowercased().replacingOccurrences(of: " ", with: "") })
            if texts.count < group.count { return decline(["duplicate_basis"]) }
        }

        var cells: [LabelCell] = []
        var warnings: [String] = []
        var lastTopLevel: String?
        for (index, row) in rows.enumerated() {
            let classified = RowClassifier.classify(row.label)
            let rowKey: String
            let parent: String?
            switch classified {
            case let .some(match):
                rowKey = match.key
                if let fixed = match.fixedParent {
                    parent = fixed
                } else if match.ofWhich || row.indented {
                    parent = lastTopLevel
                } else {
                    parent = nil
                }
            case nil:
                rowKey = "row_\(index + 1)"
                parent = (RowClassifier.hasOfWhich(row.label) || row.indented) ? lastTopLevel : nil
                warnings.append("unrecognised_row: \(row.label)")
            }
            if parent == nil { lastTopLevel = rowKey == "energy" ? nil : rowKey }
            if row.values.isEmpty {
                warnings.append("row_without_values: \(row.label)")
                continue
            }
            let hint = RowClassifier.unitHint(row.label)
            var amounts: [PrintedValue] = []
            var percentages: [PrintedValue] = []
            for var value in row.values {
                if value.unit == nil { value.unit = hint }
                guard let unit = value.unit else {
                    return decline([classified?.row == .energy ? "energy_without_unit" : "value_without_unit"])
                }
                guard let canonical = LabelVocabulary.canonicalUnit(unit) else { return decline(["unrecognised_unit"]) }
                if canonical == "%" { percentages.append(value) } else { amounts.append(value) }
            }
            if !percentages.isEmpty, percentages.count != referenceHeaders.count {
                return decline(["count_mismatch"])
            }
            var groups: [(key: String, values: [PrintedValue])] = []
            if classified?.row == .energy {
                for value in amounts {
                    let canonical = LabelVocabulary.canonicalUnit(value.unit ?? "") ?? ""
                    guard LabelVocabulary.allowedUnits(for: .energy).contains(canonical) else { return decline(["unrecognised_unit"]) }
                    let key = canonical == "kJ" ? "energy_kj" : "energy_kcal"
                    if let position = groups.firstIndex(where: { $0.key == key }) {
                        groups[position].values.append(value)
                    } else {
                        groups.append((key, [value]))
                    }
                }
            } else {
                if let match = classified {
                    for value in amounts {
                        let canonical = LabelVocabulary.canonicalUnit(value.unit ?? "") ?? ""
                        guard LabelVocabulary.allowedUnits(for: match.row).contains(canonical) else { return decline(["unrecognised_unit"]) }
                    }
                }
                groups = amounts.isEmpty ? [] : [(rowKey, amounts)]
            }
            for group in groups where group.values.count != amountHeaders.count {
                _ = group
                return decline(["count_mismatch"])
            }
            let nutrientFor: (String) -> String = { key in classified == nil ? "unrecognised" : key }
            for group in groups {
                for (header, value) in zip(amountHeaders, group.values) {
                    cells.append(Self.cell(rowID: group.key, parent: parent, nutrient: nutrientFor(group.key), label: row.label, header: header, value: value, servingSize: servingSize))
                }
            }
            // An energy percentage refers to the kcal value when one is printed (UK %RI convention).
            let energyKeys = groups.map(\.key)
            let percentKey = classified?.row == .energy ? (energyKeys.contains("energy_kcal") ? "energy_kcal" : (energyKeys.first ?? "energy_kcal")) : rowKey
            for (header, value) in zip(referenceHeaders, percentages) {
                cells.append(Self.cell(rowID: percentKey, parent: parent, nutrient: nutrientFor(percentKey), label: row.label, header: header, value: value, servingSize: servingSize))
            }
        }
        if cells.isEmpty { return decline(["no_table"]) }
        let orderedHeaders = headers
        return LabelCaptureCandidate(
            route: route,
            inputSHA256: inputSHA256,
            declined: false,
            declineReasons: [],
            wouldMarkReady: warnings.isEmpty,
            language: language,
            servingSize: servingSize,
            servingsPerPack: servingsPerPack,
            headers: orderedHeaders,
            cells: cells,
            warnings: warnings
        )
    }

    static func cell(rowID: String, parent: String?, nutrient: String, label: String, header: LabelHeader, value: PrintedValue, servingSize: LabelServingSize?) -> LabelCell {
        let unit = value.unit ?? ""
        let conversion: String
        if header.basis == .perServing {
            conversion = header.servingConversion ?? servingSize.flatMap { size in
                size.decimalText.flatMap { number in size.unit.map { number + $0 } }
            } ?? "unknown"
        } else {
            conversion = "not_applicable"
        }
        return LabelCell(
            rowID: rowID,
            parentRowID: parent,
            nutrient: nutrient,
            printedLabel: label,
            headerID: header.headerID,
            basis: header.basis,
            printedText: value.printedText,
            comparator: value.comparator,
            decimalText: value.decimalText,
            unit: unit,
            canonicalUnit: LabelVocabulary.canonicalUnit(unit) ?? unit,
            servingConversion: conversion
        )
    }
}

// MARK: - Row classification

enum RowClassifier {
    struct Match: Equatable {
        var key: String
        var row: LabelVocabulary.Row
        var fixedParent: String?
        var ofWhich: Bool
    }

    static func hasOfWhich(_ label: String) -> Bool {
        label.lowercased().hasPrefix("of which")
    }

    static func unitHint(_ label: String) -> String? {
        Patterns.labelUnitHint.firstMatch(in: label)?[1]
    }

    static func classify(_ label: String) -> Match? {
        let compact = label.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "\u{3000}", with: "")
        for entry in LabelVocabulary.chineseRows where compact == entry.label {
            return Match(key: key(for: entry.row), row: entry.row, fixedParent: entry.parent, ofWhich: false)
        }
        var text = label.lowercased()
        var ofWhich = false
        if text.hasPrefix("of which") {
            ofWhich = true
            text = String(text.dropFirst("of which".count))
        }
        text = Patterns.parenthesised.split(text).joined(separator: " ")
        text = text.trimmingCharacters(in: .whitespaces.union(CharacterSet(charactersIn: ":*-–")))
        text = text.split(separator: " ").joined(separator: " ")
        guard let row = LabelVocabulary.englishRows[text] else { return nil }
        return Match(key: key(for: row), row: row, fixedParent: nil, ofWhich: ofWhich)
    }

    static func key(for row: LabelVocabulary.Row) -> String {
        switch row {
        case .energy: "energy"
        case let .nutrient(key): key
        }
    }
}
