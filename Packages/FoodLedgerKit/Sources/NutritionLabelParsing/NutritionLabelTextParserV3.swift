import Foundation

/// `nutrition-label-text-parser-v3` (`docs/pasted-nutrition-label-reader-v3.md`), the reader
/// behind the pasted nutrition label route. It is parser v2 (`NutritionLabelTextParser`, kept
/// unchanged as the frozen evaluation reference and the non-regression baseline of section 5.5)
/// plus, in this first PR of section 8:
///
/// - the lines before the table (3.1): decorated titles, rule lines, serving-label variants
///   (每1份量), split serving and pack lines joined under the conditions of rule 3, pack-line
///   variants (本包裝包含, 本包裝 N 份), serving and pack on one line, and leading row markers;
/// - the row-name alias table `taiwan-row-aliases-v1` (section 4);
/// - the Taiwan unit rule (3.9): a mandatory Taiwan row printed in a unit other than the
///   template's is not read;
/// - layout precedence (3.0, `LabelLayout`) and gate input coverage on every consumed but
///   unbound line (3.0).
///
/// The safety rule of v3 (section 2): it may leave a value, a row or the table unread; it never
/// binds a value to the wrong row, column, basis or unit. Like v2 it has no network, clock,
/// randomness or hashing dependency.
public struct NutritionLabelTextParserV3: Sendable {
    public static let version = "nutrition-label-text-parser-v3"
    public static let aliasVersion = TaiwanRowAliases.version

    public init() {}

    public func parse(_ text: String, route: String = "A", inputSHA256: String) -> LabelCaptureCandidate {
        let normalised = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\u{00A0}", with: " ")
        let language = NutritionLabelTextParser.language(of: normalised)
        if NutritionLabelTextParser.hasUnsupportedScript(normalised)
            || (language == .unknown && !normalised.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) {
            return .declined(route: route, inputSHA256: inputSHA256, language: language, reasons: ["unsupported_language"])
        }
        var state = ParseStateV3()
        for rawLine in normalised.components(separatedBy: "\n") {
            state.consume(rawLine)
            if !state.declineReasons.isEmpty { break }
        }
        return state.finish(route: route, inputSHA256: inputSHA256, language: language)
    }
}

// MARK: - Patterns of parser v3

enum PatternsV3 {
    /// `每[一1]?份量` (3.1 rule 3); byte-identical to `PastedLabelServingSizeGrammarV3.labelPattern`.
    static let servingSize = LabelPattern(#"(?i)^(?:serving\s+size|portion\s+size|每[一1]?份量)\s*[:：]?\s*(.+)$"#)
    /// A serving label standing alone on its line.
    static let servingLabelAlone = LabelPattern(#"(?i)^(?:serving\s+size|portion\s+size|每[一1]?份量)\s*[:：]?$"#)
    /// A serving quantity and nothing else.
    static let servingQuantityAlone = LabelPattern(#"^(\d+(?:\.\d+)?)\s*(g|ml|mL|公克|毫升|克)$"#)
    /// The pack phrase inside a serving line (5.6); byte-identical to the grammar copy.
    static let packPhrase = LabelPattern(#"本包裝包?含?\s*約?\s*\d+(?:\.\d+)?\s*份|(?i:servings?\s+per\s+(?:container|pack|package))"#)
    /// Pack lines: parser v2's English forms, and 本包裝(包)?含? with an optional 約 (3.1 rule 4).
    static let servingsPerPack = [
        Patterns.servingsPerPack[0],
        Patterns.servingsPerPack[1],
        LabelPattern(#"^本包裝包?含?\s*(約)?\s*(\d+(?:\.\d+)?)\s*份"#),
    ]
    /// A pack label standing alone, and the "N份" line that may follow it.
    static let packLabelAlone = LabelPattern(#"^本包裝包?含?\s*(約)?\s*[:：]?$"#)
    static let packQuantityAlone = LabelPattern(#"^(約)?\s*(\d+(?:\.\d+)?)\s*份$"#)
    /// A pack phrase found inside a serving line: Chinese, or English with its number.
    static let chinesePackPhrase = LabelPattern(#"^本包裝包?含?\s*(約)?\s*(\d+(?:\.\d+)?)\s*份"#)
    static let englishPackPhrase = LabelPattern(#"(?i)^servings?\s+per\s+(?:container|pack|package)\s*[:：]?\s*(about\s+)?(\d+(?:\.\d+)?)"#)
    /// The Chinese title, optionally followed by an English title from the existing title words
    /// or by one bracketed group (3.1 rule 1).
    static let chineseTitle = LabelPattern(
        #"(?i)^(?:營養標示|營養成分)[:：]?\s*(?:(?:nutrition(?:al)?(?: information| facts| declaration)?|typical values?|nutrition information typical values)[:：]?|[(（]([^)）]*)[)）])?$"#)
    /// Decoration removed at either end of a title line: ★ ☆ ◎ ● ▲ ■ ◆ 【 】 [ ] = and spaces.
    static let titleDecoration = CharacterSet(charactersIn: "★☆◎●▲■◆【】[]= \u{3000}\t")
    /// A rule line: only `=`, `-`, `─`, `_`, `*` and spaces.
    static let ruleLine = LabelPattern(#"^[=\-─_*\s　]+$"#)
    /// Leading row markers (3.1 rule 5), longest first; `-` and `*` only before a Han character.
    static let rowMarkers = [">>", ">", "•", "·", "▲", "●"]
    static let hanMarkers: [Character] = ["-", "*"]
    static let hanRun = LabelPattern(#"\p{Han}+"#)
    /// "More than" before a number: the reader has no such comparator, so such a value is never
    /// read as exact (it makes its row unread).
    static let greaterThan = LabelPattern(#"(?i)(?:[>≥＞≧]|超過|大於|多於|more\s+than|greater\s+than)\s*\d"#)
    /// The same marks standing at the end of a label ("鈉 >", "超過").
    static let trailingGreaterThan = LabelPattern(#"(?i)\s*(?:[>≥＞≧]+|超過|大於|多於|more\s+than|greater\s+than)$"#)
}

// MARK: - Parse state

struct RowDraftV3 {
    var label: String
    var indented: Bool
    var values: [PrintedValue]
    var labelLineHadValues: Bool
    var attachedAfterValues = false
    /// The printed lines of the row, for gate input coverage when the row is not bound.
    var lines: [String]
    /// The row's label line started with a row marker (3.1 rule 5).
    var marked = false
    /// A value of the row was printed as "more than" (`>3公克`): the row is not read.
    var malformed = false
}

struct ParseStateV3 {
    enum Pending: Equatable {
        case servingLabel(String)
        case packLabel(String, approximate: Bool)
    }

    struct Join: Equatable {
        var label: String
        var quantity: String
    }

    var headers: [LabelHeader] = []
    var rows: [RowDraftV3] = []
    var servingSize: LabelServingSize?
    var servingsPerPack: LabelServingsPerPack?
    var declineReasons: [String] = []
    var lastLineWasHeader = false
    var rowsStarted = false
    /// Body lines for layout precedence.
    var body: [LabelLayout.Line] = []
    /// Every line consumed without being bound to the candidate (3.0, gate input coverage).
    var unbound: [String] = []
    /// A serving or pack label standing alone before the table, waiting for its next non-empty line.
    var pending: Pending?
    /// A label standing alone after the first row: its quantity line, if next, is consumed unbound.
    var swallowQuantity: Pending?
    /// Split lines joined before the first row, applied at the end only outside stacked tables.
    var servingJoin: Join?
    var packJoin: (join: Join, approximate: Bool, decimal: String)?

    var servingClaimed: Bool { servingSize != nil || servingJoin != nil }
    var packClaimed: Bool { servingsPerPack != nil || packJoin != nil }

    mutating func consume(_ rawLine: String) {
        let content = rawLine.trimmingCharacters(in: .whitespaces.union(CharacterSet(charactersIn: "\u{3000}")))
        guard !content.isEmpty else { return }

        if let label = pending {
            pending = nil
            if consumeJoin(label, content) { return }
            unbound.append(Self.text(of: label))
        }
        if let label = swallowQuantity {
            swallowQuantity = nil
            if Self.quantityLine(for: label, content) != nil {
                unbound.append(content)
                return
            }
        }
        if PatternsV3.ruleLine.contains(content) {
            unbound.append(content)
            return
        }
        if content.hasPrefix("*") || content.hasPrefix("＊") || content.hasPrefix("†") {
            if !(content.hasPrefix("*") && Self.markedRow(content) != nil && !repeatsReadRow(content)) {
                unbound.append(content)
                return
            }
        }
        for pattern in PatternsV3.servingsPerPack {
            if let groups = pattern.firstMatch(in: content), let number = groups[2] {
                if !packClaimed {
                    servingsPerPack = LabelServingsPerPack(printedText: content, decimalText: number, approximate: groups[1] != nil)
                } else {
                    unbound.append(content)
                }
                lastLineWasHeader = false
                return
            }
        }
        if let groups = PatternsV3.packLabelAlone.firstMatch(in: content) {
            lastLineWasHeader = false
            label(.packLabel(content, approximate: groups[1] != nil))
            return
        }
        if PatternsV3.servingLabelAlone.contains(content) {
            lastLineWasHeader = false
            label(.servingLabel(content))
            return
        }
        if let groups = PatternsV3.servingSize.firstMatch(in: content), let rest = groups[1] {
            if !servingClaimed {
                servingSize = Self.servingSize(printed: content, value: rest)
                if !packClaimed, let pack = Self.packCount(inServingLine: content, value: rest) {
                    servingsPerPack = pack
                }
            } else {
                unbound.append(content)
            }
            lastLineWasHeader = false
            return
        }
        if Self.isTitle(content) {
            if rowsStarted, content.contains("營養標示") || content.lowercased().hasPrefix("nutrition") {
                declineReasons.append("multiple_panels")
            }
            unbound.append(content)
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

    /// A serving or pack label standing alone: before the first row it waits for its quantity
    /// line; after it, the serving line is not read and its quantity line is consumed unbound.
    mutating func label(_ label: Pending) {
        let claimed: Bool
        switch label {
        case .servingLabel: claimed = servingClaimed
        case .packLabel: claimed = packClaimed
        }
        if rowsStarted || claimed {
            unbound.append(Self.text(of: label))
            swallowQuantity = label
        } else {
            pending = label
        }
    }

    /// 3.1 rule 3 (and rule 4 for the pack line): the next non-empty line is joined only when it
    /// is that line's quantity and nothing else, and both come before the first row label. The
    /// remaining conditions (not stacked, no `stacked_sequence` row) are applied in `finish`.
    mutating func consumeJoin(_ label: Pending, _ content: String) -> Bool {
        guard !rowsStarted, let groups = Self.quantityLine(for: label, content) else { return false }
        switch label {
        case let .servingLabel(text):
            servingJoin = Join(label: text, quantity: content)
        case let .packLabel(text, approximate):
            guard let number = groups[2] else { return false }
            packJoin = (Join(label: text, quantity: content), approximate || groups[1] != nil, number)
        }
        lastLineWasHeader = false
        return true
    }

    static func quantityLine(for label: Pending, _ content: String) -> [String?]? {
        switch label {
        case .servingLabel: PatternsV3.servingQuantityAlone.firstMatch(in: content)
        case .packLabel: PatternsV3.packQuantityAlone.firstMatch(in: content)
        }
    }

    static func text(of label: Pending) -> String {
        switch label {
        case let .servingLabel(text): text
        case let .packLabel(text, _): text
        }
    }

    /// The joined printed text: the label line and the quantity line, each trimmed, joined by
    /// one ASCII space (3.1 rule 3; serving v3 scans exactly this string).
    static func joined(_ join: Join) -> String {
        join.label.trimmingCharacters(in: .whitespaces) + " " + join.quantity.trimmingCharacters(in: .whitespaces)
    }

    /// 3.1 rule 1: a title after removing decoration at either end. A bracket group after the
    /// Chinese title never carries a value: one with a digit or a basis phrase is not a title.
    static func isTitle(_ content: String) -> Bool {
        let stripped = content.trimmingCharacters(in: PatternsV3.titleDecoration)
        guard !stripped.isEmpty else { return false }
        if Patterns.title.contains(stripped) { return true }
        guard let groups = PatternsV3.chineseTitle.firstMatch(in: stripped) else { return false }
        if let bracket = groups[1] {
            if bracket.contains(where: \.isNumber) || ParseState.basis(of: bracket) != nil { return false }
        }
        return true
    }

    // MARK: Serving lines

    /// The serving value cut at the first pack phrase (5.6 step 3): it ends at the start of the
    /// match, with trailing spaces and `,` `，` `、` `/` `／` removed.
    static func cutAtPackPhrase(_ value: String) -> String {
        guard let match = PatternsV3.packPhrase.matchDetails(in: value).first else { return value }
        var head = String(value[..<match.range.lowerBound])
        while let last = head.last, last.isWhitespace || ",，、/／".contains(last) { head.removeLast() }
        return head
    }

    /// The serving size of a v3 serving line: the quantity located exactly as v2 does, in the
    /// value cut at the pack phrase.
    static func servingSize(printed: String, value: String) -> LabelServingSize {
        let cut = cutAtPackPhrase(value)
        let source = Patterns.parenthesised.firstMatch(in: cut)?[1] ?? cut
        if let groups = Patterns.servingQuantity.firstMatch(in: source) ?? Patterns.servingQuantity.firstMatch(in: cut),
           let number = groups[1], let unit = groups[2] {
            return LabelServingSize(printedText: printed, decimalText: number, unit: unit, canonicalUnit: LabelVocabulary.canonicalUnit(unit))
        }
        return LabelServingSize(printedText: printed, decimalText: nil, unit: nil, canonicalUnit: nil)
    }

    /// 3.1 rule 4: the pack count from a pack phrase on the serving line, read as printed.
    static func packCount(inServingLine line: String, value: String) -> LabelServingsPerPack? {
        guard let match = PatternsV3.packPhrase.matchDetails(in: value).first else { return nil }
        let phrase = String(value[match.range.lowerBound...])
        for pattern in [PatternsV3.chinesePackPhrase, PatternsV3.englishPackPhrase] {
            if let groups = pattern.firstMatch(in: phrase), let number = groups[2] {
                return LabelServingsPerPack(printedText: line, decimalText: number, approximate: groups[1] != nil)
            }
        }
        return nil
    }

    // MARK: Headers and rows

    mutating func consumeHeader(_ content: String) {
        var segments = Patterns.headerSplit.split(content).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if segments.count == 1 {
            segments = Patterns.headerBoundary.split(content).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        }
        var found: [LabelHeader] = []
        for segment in segments {
            guard let basis = ParseState.basis(of: segment) else {
                unbound.append(segment)
                continue
            }
            var conversion: String?
            if basis == .perServing {
                if let quantity = ParseState.outermostParenthesised(segment) {
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

    /// 3.1 rule 5: a closed set of leading row markers, removed before classification; the
    /// marker counts as indentation. `-` and `*` are markers only before a Han character, and a
    /// line starting with `*` is a row only when what follows is a recognised row (otherwise it
    /// stays a footnote, as in parser v2).
    static func markedRow(_ content: String) -> String? {
        for marker in PatternsV3.rowMarkers where content.hasPrefix(marker) {
            let rest = String(content.dropFirst(marker.count)).trimmingCharacters(in: .whitespaces.union(CharacterSet(charactersIn: "\u{3000}")))
            // A marker is removed only when a row label follows it: `>` before a number is
            // "more than", never a marker (`>3公克` stays as printed and is never read as exact).
            return startsWithLabel(rest) ? rest : nil
        }
        guard let first = content.first, PatternsV3.hanMarkers.contains(first) else { return nil }
        let rest = String(content.dropFirst())
        guard let next = rest.first, next.unicodeScalars.first.map({ (0x4E00...0x9FFF).contains($0.value) }) == true else { return nil }
        if first == "*" {
            let label = Patterns.value.matchDetails(in: rest).first.map { String(rest[..<$0.range.lowerBound]) } ?? rest
            guard RowClassifierV3.isRowLabel(label.trimmingCharacters(in: .whitespaces)) else { return nil }
        }
        return rest
    }

    /// Whether a text starts with a row label: a letter before its first value.
    static func startsWithLabel(_ text: String) -> Bool {
        let label = Patterns.value.matchDetails(in: text).first.map { String(text[..<$0.range.lowerBound]) } ?? text
        return label.trimmingCharacters(in: .whitespaces).first?.isLetter == true
    }

    /// A `*` line naming a row that is already read (a reference footnote such as `*鈉 2000毫克`
    /// after the table) is a footnote, never a second row.
    func repeatsReadRow(_ content: String) -> Bool {
        guard let rest = Self.markedRow(content) else { return false }
        let label = (Patterns.value.matchDetails(in: rest).first.map { String(rest[..<$0.range.lowerBound]) } ?? rest)
            .trimmingCharacters(in: .whitespaces)
        guard let key = RowClassifierV3.classify(label)?.key else { return false }
        return rows.contains { RowClassifierV3.classify($0.label)?.key == key }
    }

    mutating func consumeRow(rawLine: String, content original: String) {
        var content = original
        var marked = false
        if let rest = Self.markedRow(original) {
            content = rest
            marked = true
        }
        let details = Patterns.value.matchDetails(in: content)
        let label: String
        if let first = details.first {
            label = String(content[content.startIndex..<first.range.lowerBound])
        } else {
            label = content
        }
        var cleanedLabel = label
            .trimmingCharacters(in: .whitespaces.union(CharacterSet(charactersIn: "\u{3000}\t:：-–·•")))
        // "More than" is not a value the reader can hold: its marks never stay in a label, and the
        // row that receives such a value is not read (`row_not_read: malformed_value`).
        let moreThan = PatternsV3.greaterThan.contains(content)
        if let mark = PatternsV3.trailingGreaterThan.matchDetails(in: cleanedLabel).first {
            cleanedLabel = String(cleanedLabel[..<mark.range.lowerBound])
                .trimmingCharacters(in: .whitespaces.union(CharacterSet(charactersIn: "\u{3000}\t:：-–·•")))
        }
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
            body.append(values.isEmpty ? .labelOnly : .labelWithValues(secondLabel: Self.hasSecondLabel(content, values: details)))
            if var last = rows.last, last.values.isEmpty,
               RowClassifierV3.classify(last.label) == nil,
               RowClassifierV3.classify(cleanedLabel) == nil || RowClassifierV3.classify(last.label + " " + cleanedLabel) != nil {
                last.label += " " + cleanedLabel
                last.values = values
                last.labelLineHadValues = !values.isEmpty
                last.lines.append(original)
                last.malformed = last.malformed || moreThan
                rows[rows.count - 1] = last
            } else {
                rows.append(RowDraftV3(label: cleanedLabel, indented: indented, values: values, labelLineHadValues: !values.isEmpty,
                                       lines: [original], marked: marked, malformed: moreThan))
            }
        } else if !values.isEmpty {
            guard !rows.isEmpty else {
                declineReasons.append("values_without_row")
                return
            }
            body.append(.valuesOnly)
            // As parser v2 (`ParseState.consumeRow`): a value-only line attaches to the last row;
            // after a label line that carried values it blocks ready unless it is the energy
            // row's kJ and kcal continuation.
            var last = rows[rows.count - 1]
            if last.labelLineHadValues, !Self.isStackedEnergy(row: last, adding: values) {
                last.attachedAfterValues = true
            }
            last.values += values
            last.lines.append(original)
            last.malformed = last.malformed || moreThan
            rows[rows.count - 1] = last
        } else {
            unbound.append(original)
        }
    }

    /// Whether a line holds two rows after its first value: any Han text between two values
    /// (`脂肪 10公克 其中飽和脂肪 3公克`; no substring alias matching), or a gap that names a row in
    /// the alias or English table.
    static func hasSecondLabel(_ content: String, values: [(range: Range<String.Index>, groups: [String?])]) -> Bool {
        let gaps = gaps(content, values: values)
        if gaps.dropLast().contains(where: { PatternsV3.hanRun.contains($0) }) { return true }
        let trim = CharacterSet.whitespaces.union(CharacterSet(charactersIn: "\u{3000}\t:：-–·•/,，、;；|()（）*＊†>▲●"))
        for gap in gaps {
            let text = gap.trimmingCharacters(in: trim)
            if text.isEmpty { continue }
            if RowClassifierV3.isRowLabel(text) { return true }
            if PatternsV3.hanRun.matches(in: text).contains(where: RowClassifierV3.isRowLabel) { return true }
        }
        return false
    }

    /// The texts after each value of a line (the last one runs to the end of the line).
    static func gaps(_ content: String, values: [(range: Range<String.Index>, groups: [String?])]) -> [String] {
        guard let first = values.first else { return [] }
        var gaps: [String] = []
        var cursor = first.range.upperBound
        for value in values.dropFirst() {
            gaps.append(String(content[cursor..<value.range.lowerBound]))
            cursor = value.range.upperBound
        }
        gaps.append(String(content[cursor...]))
        return gaps
    }

    /// Whether a line has Han text between two of its values (the non-regression allow-list).
    static func hasHanBetweenValues(_ line: String) -> Bool {
        gaps(line, values: Patterns.value.matchDetails(in: line)).dropLast().contains { PatternsV3.hanRun.contains($0) }
    }

    static func isStackedEnergy(row: RowDraftV3, adding values: [PrintedValue]) -> Bool {
        guard RowClassifierV3.classify(row.label)?.row == .energy else { return false }
        let energyUnits = LabelVocabulary.allowedUnits(for: .energy)
        let existing = Set(row.values.compactMap { $0.unit.flatMap(LabelVocabulary.canonicalUnit) })
        let added = values.map { $0.unit.flatMap(LabelVocabulary.canonicalUnit) }
        let addsEnergy = added.contains { unit in unit.map { energyUnits.contains($0) && !existing.contains($0) } ?? false }
        let allowed = added.allSatisfy { unit in
            guard let unit else { return false }
            if unit == "%" { return !existing.contains("%") }
            return energyUnits.contains(unit) && !existing.contains(unit)
        }
        return addsEnergy && allowed
    }

    // MARK: Binding

    mutating func finish(route: String, inputSHA256: String, language: LabelLanguage) -> LabelCaptureCandidate {
        func decline(_ reasons: [String]) -> LabelCaptureCandidate {
            .declined(route: route, inputSHA256: inputSHA256, language: language, reasons: reasons)
        }
        if let label = pending {
            unbound.append(Self.text(of: label))
            pending = nil
        }
        // Layout precedence (3.0) on a body that carries values.
        var layout: LabelLayout?
        if declineReasons.isEmpty, body.contains(where: { $0 != .labelOnly }) {
            layout = LabelLayout.classify(body)
            if layout == nil { declineReasons.append(LabelLayout.ambiguousCode) }
        }

        var warnings: [String] = []
        // 3.1 rules 3 and 4: a split serving or pack line is joined only outside stacked tables
        // and with no `stacked_sequence` unread row; otherwise it is not read. Such a row only
        // arises in a stacked table (3.2), so refusing every stacked table covers both conditions.
        let joinAllowed = layout != nil && layout != .stacked
        if let join = servingJoin {
            if joinAllowed {
                let printed = Self.joined(join)
                let groups = PatternsV3.servingSize.firstMatch(in: printed)
                servingSize = Self.servingSize(printed: printed, value: groups?[1] ?? join.quantity)
                warnings.append(Self.joinedWarning)
            } else {
                unbound += [join.label, join.quantity]
            }
        }
        if let (join, approximate, decimal) = packJoin {
            if joinAllowed {
                servingsPerPack = LabelServingsPerPack(printedText: Self.joined(join), decimalText: decimal, approximate: approximate)
                warnings.append(Self.joinedPackWarning)
            } else {
                unbound += [join.label, join.quantity]
            }
        }

        let amountHeaders = headers.filter { $0.basis != .referenceIntake }
        let referenceHeaders = headers.filter { $0.basis == .referenceIntake }
        var cells: [LabelCell] = []
        var lastTopLevel: String?
        // A marker counts as indentation only after a marker-free top-level row, so bullets on
        // every row never chain one row under another (3.1 rule 5).
        var lastTopLevelMarked = false
        var bindingDecline: [String]?
        if declineReasons.isEmpty, !rows.isEmpty, !amountHeaders.isEmpty {
            let byBasis = Dictionary(grouping: headers, by: \.basis)
            for (_, group) in byBasis where group.count > 1 {
                let texts = Set(group.map { $0.printedText.lowercased().replacingOccurrences(of: " ", with: "") })
                if texts.count < group.count { bindingDecline = ["duplicate_basis"] }
            }
        }
        if declineReasons.isEmpty, bindingDecline == nil, !rows.isEmpty, !amountHeaders.isEmpty {
            rowLoop: for (index, row) in rows.enumerated() {
                let classified = RowClassifierV3.classify(row.label)
                let indented = row.indented || (row.marked && lastTopLevel != nil && !lastTopLevelMarked)
                let rowKey: String
                let parent: String?
                switch classified {
                case let .some(match):
                    rowKey = match.key
                    if let fixed = match.fixedParent {
                        parent = fixed
                    } else if match.isTaiwanAlias {
                        // The alias table names every Taiwan row's parent (section 4): a top-level
                        // row stays top-level however it is indented or marked (3.1 rule 5).
                        parent = nil
                    } else if match.ofWhich || indented {
                        parent = lastTopLevel
                    } else {
                        parent = nil
                    }
                case nil:
                    rowKey = "row_\(index + 1)"
                    parent = (RowClassifier.hasOfWhich(row.label) || indented) ? lastTopLevel : nil
                    warnings.append("unrecognised_row: \(row.label)")
                }
                if parent == nil {
                    lastTopLevel = rowKey == "energy" ? nil : rowKey
                    lastTopLevelMarked = row.marked
                }
                if row.values.isEmpty {
                    warnings.append("row_without_values: \(row.label)")
                    unbound += row.lines
                    continue
                }
                if row.malformed {
                    warnings.append("row_not_read: malformed_value: \(row.label)")
                    unbound += row.lines
                    continue
                }
                if row.attachedAfterValues {
                    warnings.append("values_after_complete_row: \(row.label)")
                }
                let hint = RowClassifier.unitHint(row.label)
                var amounts: [PrintedValue] = []
                var percentages: [PrintedValue] = []
                for var value in row.values {
                    if value.unit == nil { value.unit = hint }
                    guard let unit = value.unit else {
                        bindingDecline = [classified?.row == .energy ? "energy_without_unit" : "value_without_unit"]
                        break rowLoop
                    }
                    guard let canonical = LabelVocabulary.canonicalUnit(unit) else { bindingDecline = ["unrecognised_unit"]; break rowLoop }
                    if canonical == "%" { percentages.append(value) } else { amounts.append(value) }
                }
                if let match = classified {
                    for value in amounts {
                        let canonical = LabelVocabulary.canonicalUnit(value.unit ?? "") ?? ""
                        guard LabelVocabulary.allowedUnits(for: match.row).contains(canonical) else {
                            bindingDecline = ["unrecognised_unit"]
                            break rowLoop
                        }
                    }
                    // 3.9: a mandatory Taiwan row whose unit is not the template's is not read
                    // (energy reads kcal or kJ, as under v1).
                    if let template = match.templateUnit, amounts.contains(where: { value in
                        !TaiwanRowAliases.readableUnits(template: template).contains(LabelVocabulary.canonicalUnit(value.unit ?? "") ?? "")
                    }) {
                        warnings.append("row_not_read: unit_off_template: \(row.label)")
                        unbound += row.lines
                        continue
                    }
                }
                if !percentages.isEmpty, percentages.count != referenceHeaders.count {
                    bindingDecline = ["count_mismatch"]
                    break rowLoop
                }
                var groups: [(key: String, values: [PrintedValue])] = []
                if classified?.row == .energy {
                    for value in amounts {
                        let canonical = LabelVocabulary.canonicalUnit(value.unit ?? "") ?? ""
                        let key = canonical == "kJ" ? "energy_kj" : "energy_kcal"
                        if let position = groups.firstIndex(where: { $0.key == key }) {
                            groups[position].values.append(value)
                        } else {
                            groups.append((key, [value]))
                        }
                    }
                } else {
                    groups = amounts.isEmpty ? [] : [(rowKey, amounts)]
                }
                if groups.contains(where: { $0.values.count != amountHeaders.count }) {
                    bindingDecline = ["count_mismatch"]
                    break rowLoop
                }
                let nutrientFor: (String) -> String = { key in classified == nil ? "unrecognised" : key }
                for group in groups {
                    for (header, value) in zip(amountHeaders, group.values) {
                        cells.append(ParseState.cell(rowID: group.key, parent: parent, nutrient: nutrientFor(group.key), label: row.label,
                                                     header: header, value: value, servingSize: servingSize))
                    }
                }
                let energyKeys = groups.map(\.key)
                let percentKey = classified?.row == .energy ? (energyKeys.contains("energy_kcal") ? "energy_kcal" : (energyKeys.first ?? "energy_kcal")) : rowKey
                for (header, value) in zip(referenceHeaders, percentages) {
                    cells.append(ParseState.cell(rowID: percentKey, parent: parent, nutrient: nutrientFor(percentKey), label: row.label,
                                                 header: header, value: value, servingSize: servingSize))
                }
            }
        }

        // 3.0, gate input coverage: the gate's own marker and script functions over every
        // consumed but unbound line; a hit declines with the gate's existing code.
        let coverage = Self.coverageDeclines(unbound + [servingSize?.printedText, servingsPerPack?.printedText].compactMap { $0 })
        if !coverage.isEmpty { return decline(coverage) }
        if !declineReasons.isEmpty { return decline(declineReasons) }
        if rows.isEmpty { return decline(["no_table"]) }
        if amountHeaders.isEmpty { return decline(["no_basis_header"]) }
        if let bindingDecline { return decline(bindingDecline) }
        if cells.isEmpty { return decline(["no_table"]) }
        return LabelCaptureCandidate(
            route: route,
            inputSHA256: inputSHA256,
            declined: false,
            declineReasons: [],
            wouldMarkReady: warnings.isEmpty,
            language: language,
            servingSize: servingSize,
            servingsPerPack: servingsPerPack,
            headers: headers,
            cells: cells,
            warnings: warnings
        )
    }

    /// One warning per joined line, each at most once: the serving line (3.1 rule 3, the string
    /// serving v3 relies on) and the pack line (rule 4).
    static let joinedWarning = "serving_line_joined"
    static let joinedPackWarning = "serving_line_joined: servings_per_pack"

    /// `unsupported_script` (G1) and `not_a_food_nutrition_panel` (G2), in gate rule order, when
    /// the gate's own functions find a hit in a consumed but unbound line.
    static func coverageDeclines(_ lines: [String]) -> [String] {
        var reasons: [String] = []
        if !LabelDeclineGate.scriptFindings(lines).isEmpty { reasons.append(LabelGateReason.unsupportedScript.rawValue) }
        if lines.contains(where: { !LabelDeclineGate.supplementMarkers(in: $0).isEmpty }) {
            reasons.append(LabelGateReason.notAFoodNutritionPanel.rawValue)
        }
        return reasons
    }
}
