import Foundation

/// The flattened-line layout of parser v3 (`docs/pasted-nutrition-label-reader-v3.md` section
/// 3.4, decision 6): a whole table copied onto one line. The line is tokenised into serving and
/// pack phrases, basis phrases, label tokens (maximal Han runs that are not units) and value
/// tokens, with no guessing:
///
/// - a **well-formed value** is an optional comparator, ASCII digits with at most one decimal
///   point and no grouping, optional spaces and a unit, followed by a separator, a label or the end;
/// - **every digit run** belongs to a well-formed value, a serving or pack phrase or a basis
///   phrase; any other digit run is **malformed** (a thousands separator in any form, a second
///   decimal point, two values with no separator, a number with no unit, a stray number,
///   full-width digits);
/// - the line is a table only when **every** label is followed by exactly N value-or-malformed
///   tokens (N amount columns, plus the reference column when one is printed) before the next
///   label, `%` stands in the same position on every row when a reference header is printed and
///   nowhere otherwise, and nothing that is not a row stands after the first label. Anything else
///   declines `flattened_table_ambiguous`.
///
/// A row holding a malformed token is not read in any column (3.4 rule 5); a row whose segment
/// holds a bound word or mark that is not a recognised bound on one of its values is not read
/// either (the unexplained-bound rule of 8.1). The basis comes only from basis phrases before the
/// first label (rule 8); a basis phrase after it declines `multiple_panels`. Pure: no state.
enum FlattenedLine {
    static let ambiguousCode = "flattened_table_ambiguous"
    /// At least this many labels from the alias table, each followed by a value with a unit,
    /// make a line a flattened table (3.4).
    static let minimumLabels = 3

    struct Phrase: Equatable {
        var printed: String
    }

    struct Header: Equatable {
        var printed: String
        var basis: LabelBasis
    }

    enum Cell: Equatable {
        /// A well-formed amount or `%` value.
        case value(decimal: String, unit: String, comparator: LabelComparator, printed: String)
        /// `*` printed in the reference-intake position (the Taiwan template's mandatory rows).
        case star
        /// A digit run that is not a well-formed value.
        case malformed(String)
    }

    struct Row: Equatable {
        var label: String
        var cells: [Cell]
        /// The printed text of the row's segment, for gate input coverage.
        var printed: String
        /// A bound word or mark in the segment that no value consumed.
        var unexplained: Bool
        /// Another symbol in the segment (a tilde, a stray mark): the row is not read.
        var junk = false
        var malformed: Bool { junk || cells.contains { if case .malformed = $0 { true } else { false } } }
    }

    struct Table: Equatable {
        var serving: Phrase?
        var pack: Phrase?
        /// Basis phrases printed before the first label, in order.
        var headers: [Header]
        var rows: [Row]
        /// Text consumed without being bound (titles, 項目), for gate input coverage.
        var unbound: [String]
    }

    enum Outcome: Equatable {
        /// Not a flattened line: fewer than three alias labels each followed by a value.
        case notFlattened
        case declined(String)
        /// Basis phrases of its own after headers printed on earlier lines: a second panel.
        case secondPanel
        case table(Table)
    }

    // MARK: Tokens

    enum Token: Equatable {
        case label(String)
        case value(decimal: String, unit: String, comparator: LabelComparator, printed: String)
        case malformed(String)
        case star
        case serving(String)
        case pack(String)
        case basis(String, LabelBasis)
        /// A title word or 項目 (the item column's heading): consumed, never bound.
        case heading(String)
        /// A bound word or mark that no value consumed.
        case bound(String)
        /// Latin text that is not a unit, or another symbol: never part of a clean flattened table.
        case latin(String)
        case other(String)
    }

    static let separators: Set<Character> = [" ", "\t", "\u{3000}", "/", "／", ",", "，", "、", "；", ";", "(", ")", "（", "）", "。",
                                              ":", "：", "|", "-", "–", "—", "_", "=", "【", "】", "[", "]",
                                              // Title decoration and bullets (3.1 rules 1 and 5) carry no value.
                                              "★", "☆", "◎", "●", "▲", "■", "◆", "•", "·"]
    /// Units, longest first within each script, exactly as parser v3's value pattern lists them.
    static let latinUnits = ["kcal", "Kcal", "KCAL", "kCal", "kJ", "kj", "KJ", "Kj", "Cal", "cal", "mcg", "mg", "µg", "μg", "mL", "ml", "g"]
    static let hanUnits = ["大卡", "千卡", "公克", "毫克", "微克", "毫升", "克"]

    static let servingPhrase = LabelPattern(#"^每[一1]?份量\s*[:：]?\s*\d+(?:\.\d+)?\s*(?:公克|毫升|克|g|ml|mL)(?![A-Za-z])(?:\s*[(（][^)）\d]*\d*[^)）]*[)）])?"#)
    static let packPhrase = LabelPattern(#"^本包裝包?含?\s*約?\s*\d+(?:\.\d+)?\s*份"#)
    static let basisPhrase = LabelPattern(#"^(?:每日參考值百分比|每日參考值|每\s*100\s*(?:公克|克|毫升)|每份)"#)
    static let headings = ["營養標示", "營養成分", "營養成份", "項目"]
    static let lessComparator = LabelPattern(#"^(?:less than|<=|≤|≦|＜|<|少於|未滿)\s*(?=[0-9０-９])"#)
    static let moreComparator = LabelPattern(#"^(?:more than|>=|≥|≧|＞|>|超過|大於|多於)\s*(?=[0-9０-９])"#)
    static let number = LabelPattern(#"^[0-9０-９]+(?:[.．][0-9０-９]+)*"#)
    static let titleBracket = LabelPattern(#"^\s*[(（][^)）0-9０-９]*[)）]"#)
    static let voluntaryBracket = LabelPattern(#"[(（](?:自願標示者|自願標示)[)）]"#)

    /// Bound words of the closed vocabulary (8.1) written in Han, longest first.
    static let stuckBoundWords = ["超過", "大於", "多於", "未滿", "少於", "以下", "以上"]

    /// A label printed with a leading 其中 ("of which") names its row when the rest is an exact
    /// alias (`其中飽和脂肪`); otherwise the label stays as printed. Exact match only.
    static func normalisedLabel(_ run: String) -> String {
        guard run.hasPrefix("其中"), TaiwanRowAliases.entry(String(run.dropFirst(2))) != nil else { return run }
        return String(run.dropFirst(2))
    }

    static func isHan(_ character: Character) -> Bool {
        character.unicodeScalars.allSatisfy { (0x4E00...0x9FFF).contains($0.value) || (0x3400...0x4DBF).contains($0.value) }
    }

    static func isLatin(_ character: Character) -> Bool {
        character.isASCII && character.isLetter || character == "µ" || character == "μ"
    }

    static func tokens(_ line: String) -> [Token] {
        // The voluntary bracket belongs to the fibre label (taiwan-row-aliases-v1 normalisation).
        let text = voluntaryBracket.split(line).joined()
        var out: [Token] = []
        var index = text.startIndex
        var seenLabel = false
        func rest() -> String { String(text[index...]) }
        func advance(_ count: Int) { index = text.index(index, offsetBy: count) }
        while index < text.endIndex {
            let character = text[index]
            if separators.contains(character) { advance(1); continue }
            let remaining = rest()
            if let match = servingPhrase.matchDetails(in: remaining).first {
                out.append(.serving(String(remaining[match.range])))
                advance(remaining.distance(from: remaining.startIndex, to: match.range.upperBound))
                continue
            }
            if let match = packPhrase.matchDetails(in: remaining).first {
                out.append(.pack(String(remaining[match.range])))
                advance(remaining.distance(from: remaining.startIndex, to: match.range.upperBound))
                continue
            }
            if remaining.hasPrefix("每"), !remaining.hasPrefix("每份量"), !remaining.hasPrefix("每一份量"), !remaining.hasPrefix("每1份量"),
               let match = basisPhrase.matchDetails(in: remaining).first {
                let printed = String(remaining[match.range])
                if let basis = ParseState.basis(of: printed) { out.append(.basis(printed, basis)) } else { out.append(.other(printed)) }
                advance(remaining.distance(from: remaining.startIndex, to: match.range.upperBound))
                continue
            }
            if !seenLabel, let heading = headings.first(where: remaining.hasPrefix) {
                // A title may carry one bracket naming the energy unit or a row (`營養標示(熱量)`,
                // 3.1 rule 1); a bracket with a digit is never part of a title.
                var consumed = heading
                if let match = titleBracket.matchDetails(in: String(remaining.dropFirst(heading.count))).first {
                    consumed += String(remaining.dropFirst(heading.count))[match.range]
                }
                out.append(.heading(consumed))
                advance(consumed.count)
                continue
            }
            var comparator = LabelComparator.equal
            var comparatorText = ""
            var moreThan = false
            if let match = lessComparator.matchDetails(in: remaining).first {
                comparatorText = String(remaining[match.range])
                let mark = comparatorText.trimmingCharacters(in: .whitespaces)
                comparator = ["<=", "≤", "≦"].contains(mark) ? .lessOrEqual : .less
            } else if let match = moreComparator.matchDetails(in: remaining).first {
                comparatorText = String(remaining[match.range])
                moreThan = true
            }
            let afterComparator = String(remaining.dropFirst(comparatorText.count))
            if let match = number.matchDetails(in: afterComparator).first {
                let digits = String(afterComparator[match.range])
                var consumed = comparatorText.count + digits.count
                var tail = String(afterComparator[match.range.upperBound...])
                var spaces = 0
                while let first = tail.first, first == " " || first == "\u{3000}" { tail.removeFirst(); spaces += 1 }
                var unit: String?
                if let han = hanUnits.first(where: tail.hasPrefix) {
                    unit = han
                } else if let latin = latinUnits.first(where: tail.hasPrefix) {
                    let after = tail.dropFirst(latin.count).first
                    if after.map(isLatin) != true { unit = latin }
                } else if tail.hasPrefix("%") || tail.hasPrefix("％") {
                    unit = String(tail.first!)
                }
                // Well-formed: ASCII digits, at most one decimal point, a unit, then a separator,
                // a label, `以下` (at most) or the end.
                var wellFormed = digits.allSatisfy { $0.isASCII } && digits.filter { $0 == "." }.count <= 1 && !digits.contains("．")
                var suffix = ""
                if let unit {
                    consumed += spaces + unit.count
                    tail.removeFirst(unit.count)
                    if tail.hasPrefix("以下") {
                        suffix = "以下"
                    } else if tail.hasPrefix("以上") {
                        suffix = "以上"
                        moreThan = true
                    }
                    consumed += suffix.count
                    tail.removeFirst(suffix.count)
                    if let next = tail.first, !(separators.contains(next) || isHan(next)) { wellFormed = false }
                    if unit == "％" { wellFormed = false }
                } else {
                    wellFormed = false
                }
                let printed = String(remaining.prefix(consumed))
                if wellFormed, !moreThan, let unit {
                    let decimal = String(digits)
                    let bound: LabelComparator = suffix == "以下" ? .lessOrEqual : comparator
                    if suffix == "以下", comparator != .equal {
                        out.append(.malformed(printed))
                    } else {
                        out.append(.value(decimal: decimal, unit: unit, comparator: bound, printed: printed.trimmingCharacters(in: .whitespaces)))
                    }
                } else {
                    out.append(.malformed(printed.trimmingCharacters(in: .whitespaces)))
                }
                advance(consumed)
                continue
            }
            if character == "*" || character == "＊" {
                out.append(.star)
                advance(1)
                continue
            }
            if isHan(character) {
                var run = ""
                var cursor = index
                while cursor < text.endIndex, isHan(text[cursor]) {
                    run.append(text[cursor])
                    cursor = text.index(after: cursor)
                }
                // A bound word standing on its own (以上, 以下, 超過 …) is a mark, not a label.
                let marks = BoundVocabulary.tokens(run)
                if !marks.isEmpty, BoundVocabulary.isMarkOnly(run) {
                    out.append(.bound(run))
                } else if let mark = stuckBoundWords.first(where: { run.hasSuffix($0) && run.count > $0.count }) {
                    // A bound word stuck to the label (`鈉超過50毫克`, `糖未滿0.5公克`) is never part
                    // of the label: the label reads alone and the mark leaves the row unread.
                    out.append(.label(normalisedLabel(String(run.dropLast(mark.count)))))
                    out.append(.bound(mark))
                    seenLabel = true
                } else {
                    out.append(.label(normalisedLabel(run)))
                    seenLabel = true
                }
                index = cursor
                continue
            }
            if isLatin(character) {
                var run = ""
                var cursor = index
                while cursor < text.endIndex, isLatin(text[cursor]) || text[cursor] == " " && cursor < text.index(before: text.endIndex)
                        && isLatin(text[text.index(after: cursor)]) {
                    run.append(text[cursor])
                    cursor = text.index(after: cursor)
                }
                out.append(BoundVocabulary.isMarkOnly(run) ? .bound(run) : .latin(run))
                index = cursor
                continue
            }
            let single = String(character)
            out.append(BoundVocabulary.isMarkOnly(single) ? .bound(single) : .other(single))
            advance(1)
        }
        return out
    }

    // MARK: Reading

    /// Reads one line under 3.4. `existingHeaders` are the basis headers printed on lines before
    /// it; a line with basis phrases of its own after printed headers is a second panel.
    /// `asserted` are the user's bases for amount columns printed with no basis header (reader v3
    /// section 8.4.2): they stand before any printed reference-intake basis, in column order.
    static func read(_ line: String, existingHeaders: [LabelBasis], asserted: [LabelBasis]? = nil) -> Outcome {
        guard line.contains(where: isHan) else { return .notFlattened }
        let tokens = tokens(line)
        // Detection: at least three alias labels, each followed directly by a value with a unit.
        var labelled = 0
        for (position, token) in tokens.enumerated() {
            guard case let .label(text) = token, TaiwanRowAliases.entry(text) != nil, position + 1 < tokens.count,
                  case let .value(_, unit, _, _) = tokens[position + 1], LabelVocabulary.canonicalUnit(unit) != "%" else { continue }
            labelled += 1
        }
        guard labelled >= minimumLabels else { return .notFlattened }

        var table = Table(serving: nil, pack: nil, headers: [], rows: [], unbound: [])
        var current: Row?
        for token in tokens {
            switch token {
            case let .label(text):
                if let row = current { table.rows.append(row) }
                current = Row(label: text, cells: [], printed: text, unexplained: false)
            case let .value(decimal, unit, comparator, printed):
                guard current != nil else { return .declined(ambiguousCode) }
                current!.cells.append(.value(decimal: decimal, unit: unit, comparator: comparator, printed: printed))
                current!.printed += " " + printed
            case let .malformed(printed):
                guard current != nil else { return .declined(ambiguousCode) }
                current!.cells.append(.malformed(printed))
                current!.printed += " " + printed
            case .star:
                guard current != nil else { return .declined(ambiguousCode) }
                current!.cells.append(.star)
                current!.printed += " *"
            case let .serving(printed):
                guard current == nil, table.serving == nil else { return .declined(ambiguousCode) }
                table.serving = Phrase(printed: printed)
            case let .pack(printed):
                guard current == nil, table.pack == nil else { return .declined(ambiguousCode) }
                table.pack = Phrase(printed: printed)
            case let .basis(printed, basis):
                // Rule 8: the basis comes only from a phrase before the first row; one after it is
                // a second panel.
                guard current == nil else { return .declined("multiple_panels") }
                table.headers.append(Header(printed: printed, basis: basis))
            case let .heading(text):
                table.unbound.append(text)
            case let .bound(text):
                guard current != nil else { return .declined(ambiguousCode) }
                current!.unexplained = true
                current!.printed += " " + text
            case let .other(text):
                guard current != nil else { return .declined(ambiguousCode) }
                current!.junk = true
                current!.printed += " " + text
            case .latin:
                return .declined(ambiguousCode)
            }
        }
        if let row = current { table.rows.append(row) }

        if !table.headers.isEmpty, !existingHeaders.isEmpty { return .secondPanel }
        var bases = table.headers.isEmpty ? existingHeaders : table.headers.map(\.basis)
        if let asserted, !bases.contains(where: { $0 != .referenceIntake }) { bases = asserted + bases }
        guard bases.contains(where: { $0 != .referenceIntake }) else { return .declined("no_basis_header") }
        let referencePositions = Set(bases.indices.filter { bases[$0] == .referenceIntake })
        for row in table.rows {
            // Rule 4: every label is followed by exactly N value-or-malformed tokens.
            guard row.cells.count == bases.count else { return .declined(ambiguousCode) }
            // Rule 6: `%` (or `*`) only in the reference position, and something there on every row.
            for (position, cell) in row.cells.enumerated() {
                let percent: Bool
                switch cell {
                case .star: percent = true
                case let .value(_, unit, _, _): percent = LabelVocabulary.canonicalUnit(unit) == "%"
                case .malformed: continue
                }
                if percent != referencePositions.contains(position) { return .declined(ambiguousCode) }
            }
        }
        return .table(table)
    }
}
