import Foundation

/// `label-photo-vision-locate-v1` matcher (docs/label-photo-ai-prefill-v1.md section 6.1).
///
/// Pure: Foundation only, no Vision, image, clock or network. The Vision adapter supplies the
/// recognised lines and a function that returns the box of a substring of one line; the matcher
/// decides, for each printed value the model returned, whether it appears exactly once on the
/// photo in its row label's line band and its header's column. Being found is corroboration,
/// never verification. L0 measures this file; L1 carries it into the package unchanged and pins
/// it by SHA-256.
public enum LabelValueMatcher {
    public static let version = "label-photo-vision-locate-v1"
    /// A value belongs to its row label only within this share of the local label spacing.
    public static let rowOffsetLimit = 1.0 / 3.0

    /// A normalised rectangle in image space (0...1 on both axes; Vision's origin, bottom left).
    public struct Box: Equatable, Sendable, Codable {
        public let x: Double, y: Double, width: Double, height: Double
        public init(x: Double, y: Double, width: Double, height: Double) {
            self.x = x; self.y = y; self.width = width; self.height = height
        }
        public var midX: Double { x + width / 2 }
        public var midY: Double { y + height / 2 }
    }

    /// One recognised line of text and its box.
    public struct Line: Equatable, Sendable {
        public let text: String
        public let box: Box
        public init(text: String, box: Box) { self.text = text; self.box = box }
    }

    /// One value to locate: its row label, its column header's printed text and its own printed
    /// text, all as the model returned them. Serving lines have no row label or header.
    public struct Query: Equatable, Sendable {
        public let id: String
        public let rowLabel: String?
        public let headerText: String?
        public let printedText: String
        public init(id: String, rowLabel: String?, headerText: String?, printedText: String) {
            self.id = id; self.rowLabel = rowLabel; self.headerText = headerText; self.printedText = printedText
        }
    }

    public enum Status: String, Sendable, Codable { case found, notFound = "not_found", ambiguous }

    public struct Location: Equatable, Sendable {
        public let id: String
        public let status: Status
        public let region: Box?
    }

    /// The box of `range` (original indices) within `lines[index]`, or the line's box.
    public typealias SubBox = (_ index: Int, _ range: Range<String.Index>) -> Box?

    /// `headers` and `rowLabels` are every header's and row label's printed text in the table, so a
    /// value can be assigned to its nearest one; `columnCount` is the number of value columns the
    /// reading has (headers with or without printed text).
    ///
    /// Precondition for the order pass: `queries` list each column's values in the table's printed
    /// row order, top to bottom, as the reading's rows are. The pass checks this against the row
    /// labels found on the photo and places nothing when they disagree or cannot be checked.
    public static func locate(_ queries: [Query], lines: [Line], headers: [String], rowLabels: [String], columnCount: Int,
                              subBox: SubBox) -> [Location] {
        let normalised = lines.map(Normalised.init)
        func box(_ match: Match) -> Box { subBox(match.line, match.range) ?? lines[match.line].box }
        // Each header and row label found exactly once, so a candidate value can be assigned to
        // its nearest header (by x) and its nearest row label (by y). Nearest rather than a fixed
        // band copes with tilted photos and with Vision reading labels and values as separate lines.
        // Headers are found by plain containment, because they are often printed on one line
        // ("每份 每100公克"); a row label may not follow a letter or ideograph.
        func unique(_ texts: [String], rule: Rule) -> [String: Box] {
            var boxes: [String: Box] = [:]
            for text in Set(texts) {
                let found = occurrences(of: text, in: normalised, rule: rule)
                if found.count == 1 { boxes[Normalised(text).key] = box(found[0]) }
            }
            return boxes
        }
        let headerBoxes = unique(headers, rule: .line)
        let rowBoxes = unique(rowLabels, rule: .label)
        func nearest(_ boxes: [String: Box], to value: Box, by distance: (Box, Box) -> Double) -> String? {
            boxes.sorted { $0.key < $1.key }.min { distance($0.value, value) < distance($1.value, value) }?.key
        }
        func inHeader(_ query: Query, _ value: Box) -> Bool {
            guard let header = query.headerText.map({ Normalised($0).key }), headerBoxes[header] != nil,
                  headerBoxes.count > 1 else { return true }
            return nearest(headerBoxes, to: value) { abs($0.midX - $1.midX) } == header
        }

        // Row geometry. A value belongs to a row label only when that label is its nearest and its
        // vertical offset from the label is under `rowOffsetLimit` of the local spacing (the gap to
        // the nearer neighbouring label; the one neighbour at the table's edges). A value nearest
        // the label but further off has drifted: it could be this row's or the neighbour's, so it
        // makes the value ambiguous, never found. 1/3 is chosen so that a value drifted by more
        // than a third of a row is never accepted on either row (a drift of 0.05 at a spacing of
        // 0.08 sits 0.375 of a row from the neighbour, which "about 0.4" would have accepted).
        let rowsTopDown = rowBoxes.sorted { $0.value.midY > $1.value.midY }
        func spacing(_ label: String) -> Double? {
            guard let index = rowsTopDown.firstIndex(where: { $0.key == label }), rowsTopDown.count > 1 else { return nil }
            var gaps: [Double] = []
            if index > 0 { gaps.append(rowsTopDown[index - 1].value.midY - rowsTopDown[index].value.midY) }
            if index + 1 < rowsTopDown.count { gaps.append(rowsTopDown[index].value.midY - rowsTopDown[index + 1].value.midY) }
            return gaps.min()
        }
        enum RowFit { case other, near, drifted }
        func rowFit(_ label: String, _ value: Box) -> RowFit {
            guard let own = rowBoxes[label], let gap = spacing(label),
                  nearest(rowBoxes, to: value, by: { abs($0.midY - $1.midY) }) == label else { return .other }
            return abs(value.midY - own.midY) < rowOffsetLimit * gap ? .near : .drifted
        }
        func rowKey(_ query: Query) -> String? {
            guard let label = query.rowLabel.map({ Normalised($0).key }), rowBoxes[label] != nil, rowBoxes.count > 1 else { return nil }
            return label
        }
        // Number tokens on a row, outside its label, for the unlisted column rule: with one value
        // column, a row holding more numbers than the reading lists for it has a second column the
        // reading does not know, so a match there is not trusted. Tokens come from the value
        // tokenizer, so "1,234公克" is one number.
        func numberTokens(onRow label: String) -> [Box] {
            guard let own = rowBoxes[label] else { return [] }
            var boxes: [Box] = []
            for (number, line) in normalised.enumerated() {
                for token in valueTokens(line.characters) {
                    let tokenBox = box(Match(line: number, range: line.origin[token.start].lowerBound..<line.origin[token.end - 1].upperBound))
                    let insideLabel = tokenBox.midX >= own.x && tokenBox.midX <= own.x + own.width
                    if !insideLabel, rowFit(label, tokenBox) == .near { boxes.append(tokenBox) }
                }
            }
            return boxes
        }
        let listedPerRow = Dictionary(grouping: queries.compactMap(rowKey), by: { $0 }).mapValues(\.count)

        // The value's column is confirmed when the reading has one value column, or when at least
        // two headers are located and the value's own header is one of them. With more than one
        // column and no confirmed column, a value is never found (S4 of the #320 re-check).
        func columnConfirmed(_ query: Query) -> Bool {
            if columnCount <= 1 { return true }
            guard headerBoxes.count > 1, let header = query.headerText.map({ Normalised($0).key }) else { return false }
            return headerBoxes[header] != nil
        }

        // First pass: the row and column filters, trying each tier of matches in turn. An
        // ambiguous result keeps its candidates (after both filters) for the order pass.
        struct First { let location: Location; let candidates: [Box] }
        // R1 of the #320 sweep: a number matched alone (its unit read as a separate line) counts
        // only when a line just to its right, in the same row band, reads as the reading's unit.
        func unitBeside(_ value: Box, unit: String) -> Bool {
            lines.indices.contains { index in
                let other = lines[index].box, text = normalised[index].characters
                guard starts(text, at: 0, with: unit) else { return false }
                let next = unit.count < text.count ? text[unit.count] : nil
                if let next, next.isLetter || isDigit(next) { return false }
                return other.x >= value.x + value.width / 2 && other.x - (value.x + value.width) < 0.1
                    && abs(other.midY - value.midY) < max(other.height, value.height) / 2
            }
        }
        let first: [First] = queries.map { query in
            let isLine = query.rowLabel == nil
            let wanted = valueTokens(Normalised(query.printedText).characters)
            for (tierIndex, tier) in matchTiers(query.printedText, isLine: isLine, in: normalised).enumerated() {
                var candidates = tier.map { box($0) }.filter { inHeader(query, $0) }
                if !isLine, !candidates.isEmpty {
                    // A reading with no unit, or a value matched by its number alone without its unit
                    // beside it, is never found: it can only be ambiguous.
                    let unit = wanted.count == 1 ? wanted[0].unit : ""
                    if unit.isEmpty {
                        return First(location: Location(id: query.id, status: .ambiguous, region: nil), candidates: [])
                    }
                    if tierIndex == 1 {
                        let beside = candidates.filter { unitBeside($0, unit: unit) }
                        if beside.isEmpty {
                            return First(location: Location(id: query.id, status: .ambiguous, region: nil), candidates: [])
                        }
                        candidates = beside
                    }
                }
                if isLine {
                    // Serving lines carry their own words; no row or column to confirm.
                    switch candidates.count {
                    case 0: continue
                    case 1: return First(location: Location(id: query.id, status: .found, region: rounded(candidates[0])), candidates: candidates)
                    default: return First(location: Location(id: query.id, status: .ambiguous, region: nil), candidates: candidates)
                    }
                }
                if candidates.isEmpty { continue }
                guard let label = rowKey(query), spacing(label) != nil else {
                    // The value's own row cannot be confirmed: its label was not located exactly once
                    // (or is the only label located). It is never found. Candidates near another
                    // located label belong to that row and are dropped; any candidate at all makes
                    // the value ambiguous (the order pass then needs a located label, so it stays so).
                    let own = query.rowLabel.map { Normalised($0).key }
                    let elsewhere = candidates.filter { candidate in
                        rowBoxes.keys.contains { $0 != own && rowFit($0, candidate) == .near }
                    }
                    let remaining = candidates.filter { !elsewhere.contains($0) }
                    return First(location: Location(id: query.id, status: .ambiguous, region: nil), candidates: remaining)
                }
                let near = candidates.filter { rowFit(label, $0) == .near }
                let drifted = candidates.filter { rowFit(label, $0) == .drifted }
                if near.isEmpty && drifted.isEmpty { continue }
                let unlisted = columnCount <= 1 && numberTokens(onRow: label).count > (listedPerRow[label] ?? 0)
                if near.count == 1 && drifted.isEmpty && !unlisted && columnConfirmed(query) {
                    return First(location: Location(id: query.id, status: .found, region: rounded(near[0])), candidates: near)
                }
                return First(location: Location(id: query.id, status: .ambiguous, region: nil), candidates: near + drifted)
            }
            return First(location: Location(id: query.id, status: .notFound, region: nil), candidates: [])
        }

        // Second pass, order within the column. It may only turn a first-pass **ambiguous** value
        // into found; it never changes a found or not found value. A value whose text repeats in
        // its column is placed by rank only when all of these hold:
        // - its column is known: the reading has one value column, or the headers separate them;
        // - the column holds exactly as many occurrences of that text as the reading has values
        //   with that text in that column;
        // - every one of those values has its row label found exactly once, and the labels run top
        //   to bottom in the queries' order (the precondition above);
        // - the occurrence of the value's rank is one of its own first-pass candidates, within the
        //   row offset limit of its own label, on a row with no unlisted number.
        // Otherwise the value stays ambiguous.
        func columnKey(_ query: Query) -> String? {
            if columnCount <= 1 { return "" }
            guard headerBoxes.count > 1, let header = query.headerText.map({ Normalised($0).key }),
                  headerBoxes[header] != nil else { return nil }
            return header
        }
        return queries.enumerated().map { index, query in
            let result = first[index]
            guard result.location.status == .ambiguous, query.rowLabel != nil, let key = columnKey(query) else { return result.location }
            let needle = Normalised(query.printedText).key
            let expected = queries.indices.filter { other in
                queries[other].rowLabel != nil && columnKey(queries[other]) == key
                    && Normalised(queries[other].printedText).key == needle
            }
            let labelBoxes = expected.compactMap { queries[$0].rowLabel.flatMap { rowBoxes[Normalised($0).key] } }
            let inOrder = labelBoxes.count == expected.count && zip(labelBoxes, labelBoxes.dropFirst()).allSatisfy { $0.midY > $1.midY }
            let observed = (matchTiers(query.printedText, isLine: false, in: normalised).first ?? []).map { box($0) }
                .filter { inHeader(query, $0) }
                .sorted { $0.midY > $1.midY }
            guard inOrder, expected.count > 1, expected.count == observed.count, let rank = expected.firstIndex(of: index),
                  result.candidates.contains(observed[rank]), let label = rowKey(query), rowFit(label, observed[rank]) == .near,
                  !(columnCount <= 1 && numberTokens(onRow: label).count > (listedPerRow[label] ?? 0)) else { return result.location }
            return Location(id: query.id, status: .found, region: rounded(observed[rank]))
        }
    }

    // MARK: Values as tokens (#320 re-check, S1 to S4 and the same family)

    /// One printed value read from a normalised line: its comparator (`=`, `<`, `<=`, `>`, `>=`),
    /// its number (thousands separators removed), its unit from a closed list (or none), its
    /// normalised character span, whether it is part of a range, and whether it ends its line.
    struct ValueToken: Equatable {
        let comparator: String, number: String, unit: String
        let start: Int, end: Int
        let range: Bool, endsLine: Bool
    }

    /// Units, longest first; a Latin unit followed by a Latin letter is not a unit.
    static let units = ["kcal", "mcg", "大卡", "千卡", "千焦", "公克", "毫克", "微克", "毫升", "公斤", "公升", "kj", "cal", "μg", "mg", "ml", "kg",
                        "g", "l", "%", "克"]
    /// Bound words and marks before a value (after NFKC, so ＜ is <), longest first.
    static let prefixComparators: [(String, String)] = [
        ("lessthan", "<"), ("morethan", ">"), ("不超過", "<="), ("<=", "<="), (">=", ">="), ("少於", "<"), ("未滿", "<"), ("低於", "<"),
        ("小於", "<"), ("不足", "<"), ("大於", ">"), ("高於", ">"), ("超過", ">"), ("≤", "<="), ("≦", "<="), ("≥", ">="), ("≧", ">="),
        ("<", "<"), (">", ">"),
    ]
    /// Bound words straight after a value's unit.
    static let suffixComparators: [(String, String)] = [("以下", "<="), ("以上", ">="), ("以內", "<=")]
    /// Range marks between two values (after NFKC, so ～ is ~).
    static let rangeMarks: Set<Character> = ["-", "~", "〜", "至", "到", "–", "—", "‐", "−"]

    static func starts(_ characters: [Character], at index: Int, with word: String) -> Bool {
        let pattern = Array(word)
        guard index >= 0, index + pattern.count <= characters.count else { return false }
        return Array(characters[index..<(index + pattern.count)]) == pattern
    }

    /// Every value token of a normalised line. A number starts at an ASCII digit not preceded by a
    /// digit, a point or a separator between digits, and runs over digits, a point followed by a
    /// digit, and a comma between digits; "1,234" is one number, so "234" is never found inside it.
    static func valueTokens(_ c: [Character]) -> [ValueToken] {
        var tokens: [ValueToken] = []
        var index = 0
        var lastEnd = -1
        while index < c.count {
            let continues = index > 0 && (isDigit(c[index - 1]) || c[index - 1] == "." || (c[index - 1] == "," && index >= 2 && isDigit(c[index - 2])))
            guard isDigit(c[index]), !continues else { index += 1; continue }
            var end = index
            while end < c.count, isDigit(c[end]) || ((c[end] == "." || c[end] == ",") && end + 1 < c.count && isDigit(c[end + 1]) && end > index) {
                end += 1
            }
            var number = String(c[index..<end]).replacingOccurrences(of: ",", with: "")
            var start = index, comparator = "="
            if index > 0, c[index - 1] == "-" || c[index - 1] == "−", lastEnd != index - 1 {
                number = "-" + number; start = index - 1
            }
            for (word, kind) in prefixComparators where starts(c, at: start - word.count, with: word) {
                start -= word.count; comparator = kind; break
            }
            var unitEnd = end, unit = ""
            for candidate in units where starts(c, at: end, with: candidate) {
                let next = end + candidate.count < c.count ? c[end + candidate.count] : nil
                let latin = candidate.unicodeScalars.allSatisfy(\.isASCII) && candidate != "%"
                if latin, let next, next.isASCII, next.isLetter { continue }
                unit = candidate; unitEnd = end + candidate.count; break
            }
            var tokenEnd = unitEnd
            for (word, kind) in suffixComparators where starts(c, at: unitEnd, with: word) {
                if comparator == "=" { comparator = kind }
                tokenEnd = unitEnd + word.count; break
            }
            let rangeBefore = start > 0 && rangeMarks.contains(c[start - 1]) && lastEnd == start - 1
            let rangeAfter = tokenEnd + 1 < c.count && rangeMarks.contains(c[tokenEnd])
                && (isDigit(c[tokenEnd + 1]) || prefixComparators.contains { starts(c, at: tokenEnd + 1, with: $0.0) })
            tokens.append(ValueToken(comparator: comparator, number: number, unit: unit, start: start, end: tokenEnd,
                                     range: rangeBefore || rangeAfter, endsLine: tokenEnd == c.count))
            if rangeBefore, let previous = tokens.indices.dropLast().last {
                let p = tokens[previous]
                tokens[previous] = ValueToken(comparator: p.comparator, number: p.number, unit: p.unit, start: p.start, end: p.end, range: true,
                                              endsLine: p.endsLine)
            }
            lastEnd = tokenEnd
            index = tokenEnd
        }
        return tokens
    }

    /// The matches tried in order for one printed text; the first tier with any match decides.
    ///
    /// A value (one token, not a range) matches a printed token with the same comparator, number
    /// and unit (tier 1); or, when Vision read the unit on its own line, a printed token with the
    /// same comparator and number, no unit, that ends its line (tier 2). A different unit on the
    /// same line, a dropped or added comparator, a dropped or added decimal point, a number inside
    /// a longer number, and a value inside a range never match. Any other printed text (a range,
    /// several values) matches only by its whole text, bounded by non-digits.
    ///
    /// A serving line matches by its whole text, bounded by non-digits; or, when Vision split the
    /// line, by its quantity's token with a unit (tier 1 only).
    static func matchTiers(_ printed: String, isLine: Bool, in lines: [Normalised]) -> [[Match]] {
        let model = Normalised(printed)
        let modelTokens = valueTokens(model.characters)
        func tokenMatches(_ accept: (ValueToken, ValueToken) -> Bool, against wanted: ValueToken) -> [Match] {
            var found: [Match] = []
            for (number, line) in lines.enumerated() {
                for token in valueTokens(line.characters) where !token.range && accept(token, wanted) {
                    found.append(Match(line: number, range: line.origin[token.start].lowerBound..<line.origin[token.end - 1].upperBound))
                }
            }
            return found
        }
        func same(_ printed: ValueToken, _ wanted: ValueToken) -> Bool {
            printed.comparator == wanted.comparator && printed.number == wanted.number && printed.unit == wanted.unit
        }
        func unitSplit(_ printed: ValueToken, _ wanted: ValueToken) -> Bool {
            !wanted.unit.isEmpty && printed.unit.isEmpty && printed.endsLine && printed.comparator == wanted.comparator
                && printed.number == wanted.number
        }
        let whole = occurrences(of: printed, in: lines, rule: .bounded)
        if isLine {
            guard let quantity = modelTokens.first, modelTokens.count == 1, !quantity.unit.isEmpty, !quantity.range else { return [whole] }
            return [whole, tokenMatches(same, against: quantity)]
        }
        guard modelTokens.count == 1, let wanted = modelTokens.first, !wanted.range else { return [whole] }
        return [tokenMatches(same, against: wanted), tokenMatches(unitSplit, against: wanted)]
    }

    // MARK: Normalisation and occurrence rules

    /// NFKC (full-width digits and letters to half-width), whitespace removed, lower case, with a
    /// map from each normalised character back to the original indices.
    struct Normalised {
        let characters: [Character]
        let origin: [Range<String.Index>]
        init(_ line: Line) { self.init(line.text) }
        var key: String { String(characters) }
        init(_ text: String) {
            var characters: [Character] = [], origin: [Range<String.Index>] = []
            var index = text.startIndex
            while index < text.endIndex {
                let next = text.index(after: index)
                for character in String(text[index..<next]).precomposedStringWithCompatibilityMapping.lowercased()
                where !character.isWhitespace {
                    characters.append(character); origin.append(index..<next)
                }
                index = next
            }
            self.characters = characters; self.origin = origin
        }
    }

    struct Match { let line: Int; let range: Range<String.Index> }

    enum Rule {
        /// A value: not preceded or followed by a digit or decimal point ("5公克" is not in "15公克").
        case value
        /// A row label or header: not preceded by a letter or ideograph ("脂肪" is not in "飽和脂肪").
        case label
        /// A serving line: plain containment.
        case line
        /// Whole printed text: not preceded or followed by a digit, a point or a separator.
        case bounded
    }

    static func occurrences(of needle: String, in lines: [Normalised], rule: Rule) -> [Match] {
        let pattern = Normalised(needle).characters
        guard !pattern.isEmpty else { return [] }
        var found: [Match] = []
        for (number, line) in lines.enumerated() where line.characters.count >= pattern.count {
            for start in 0...(line.characters.count - pattern.count)
            where Array(line.characters[start..<(start + pattern.count)]) == pattern {
                let before = start > 0 ? line.characters[start - 1] : nil
                let after = start + pattern.count < line.characters.count ? line.characters[start + pattern.count] : nil
                guard admits(rule, before: before, after: after) else { continue }
                found.append(Match(line: number, range: line.origin[start].lowerBound..<line.origin[start + pattern.count - 1].upperBound))
            }
        }
        return found
    }

    static func admits(_ rule: Rule, before: Character?, after: Character?) -> Bool {
        func numeric(_ character: Character?) -> Bool { character.map { isDigit($0) || $0 == "." } ?? false }
        switch rule {
        case .value: return !numeric(before) && !numeric(after)
        case .label: return !(before.map { $0.isLetter } ?? false)
        case .line: return true
        case .bounded:
            func edge(_ character: Character?) -> Bool { character.map { isDigit($0) || $0 == "." || $0 == "," } ?? false }
            return !edge(before) && !edge(after)
        }
    }

    /// ASCII digits only (after NFKC): Han numerals such as 一 are words on a label, not values.
    static func isDigit(_ character: Character) -> Bool { character.isASCII && character.isNumber }

    static func rounded(_ box: Box) -> Box {
        func four(_ value: Double) -> Double { (min(max(value, 0), 1) * 10_000).rounded() / 10_000 }
        return Box(x: four(box.x), y: four(box.y), width: four(box.width), height: four(box.height))
    }
}
