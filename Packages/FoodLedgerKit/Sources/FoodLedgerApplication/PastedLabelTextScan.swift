import Foundation

/// The scalar-level reading of a sent text that the pasted label AI text checks share
/// (docs/pasted-label-ai-text-v1.md 4.3 items 1 to 3): lines, value tokens under the 4.3 token
/// grammar, token boundaries and whole words. Pure and deterministic; every offset is a count of
/// Unicode scalars from the start of the text.
public struct PastedLabelTextScan: Sendable {
    /// One value token: its printed range (trailing `*` and `†` included), the end of its core
    /// (without those marks), its comparator (`=`, `<` or `<=`), its number as printed and
    /// normalised (thousands separators removed, the decimal mark written `.`; digits as printed),
    /// and its printed and canonical unit (nil for a bare number).
    public struct Token: Equatable, Sendable, Codable {
        public let start: Int
        public let end: Int
        public let coreEnd: Int
        public let comparator: String
        public let numberText: String
        public let decimalText: String
        public let unit: String?
        public let canonicalUnit: String?
        public var range: Range<Int> { start..<end }
    }

    /// A line: the range of its scalars, without its line break.
    public struct Line: Equatable, Sendable {
        public let start: Int
        public let end: Int
    }

    /// A not-declared marker (revision 14, D30): a dash or `Trace`/`Tr` of
    /// `PastedLabelAITextValueGrammar`'s marker lists, standing alone between token boundaries.
    /// Its range includes trailing `*` and `†`; `text` is the marker as printed, without them. It
    /// is never a value token, so nothing that reads tokens (the unit check, bound words, row
    /// starts, block ends) sees it; only the locator's cells do.
    public struct Marker: Equatable, Sendable, Codable {
        public let start: Int
        public let end: Int
        public let coreEnd: Int
        public let text: String
        public var range: Range<Int> { start..<end }
    }

    public let scalars: [Unicode.Scalar]
    public let lines: [Line]
    /// Every value token of the text, in text order.
    public let tokens: [Token]
    /// Every not-declared marker of the text, in text order (none inside a value token).
    public let markers: [Marker]

    public init(_ text: String) {
        let scalars = Array(text.unicodeScalars)
        self.scalars = scalars
        let lines = Self.splitLines(scalars)
        self.lines = lines
        let tokens = lines.flatMap { Self.tokens(scalars, line: $0) }
        self.tokens = tokens
        self.markers = lines.flatMap { Self.markers(scalars, line: $0, tokens: tokens) }
    }

    // MARK: Not-declared markers (revision 14, D30)

    /// The marker literal starting at `index`, if any: a dash exactly, or `trace` before `tr`
    /// with ASCII letters compared in any case. The result is its length in scalars.
    static func markerLength(_ scalars: [Unicode.Scalar], at index: Int, limit: Int) -> Int? {
        for dash in PastedLabelAITextValueGrammar.notDeclaredDashes where starts(scalars, at: index, with: dash, limit: limit) {
            return dash.unicodeScalars.count
        }
        for word in PastedLabelAITextValueGrammar.notDeclaredWords {
            let pattern = Array(word.unicodeScalars)
            guard index + pattern.count <= limit else { continue }
            let matches = pattern.indices.allSatisfy { offset in
                let scalar = scalars[index + offset]
                return scalar.isASCII && Character(scalar).lowercased() == String(pattern[offset])
            }
            if matches { return pattern.count }
        }
        return nil
    }

    /// The markers of one line. A marker starts and ends at a token boundary (trailing `*` and
    /// `†` allowed), lies outside every value token, and is not followed on its line, past
    /// whitespace, by a letter that does not start another marker: so a list dash before a row
    /// label (`- of which sugars`) and a word such as `Trace elements` are not markers.
    static func markers(_ scalars: [Unicode.Scalar], line: Line, tokens: [Token]) -> [Marker] {
        let lineTokens = tokens.filter { $0.start >= line.start && $0.start < line.end }
        func standsAlone(_ start: Int) -> (core: Int, end: Int)? {
            guard boundaryBefore(scalars, start, line: line), let length = markerLength(scalars, at: start, limit: line.end) else { return nil }
            let core = start + length
            var end = core
            while end < line.end, scalars[end] == "*" || scalars[end] == "†" { end += 1 }
            guard boundaryAfter(scalars, end, line: line) else { return nil }
            return (core, end)
        }
        var out: [Marker] = []
        var index = line.start
        while index < line.end {
            guard !lineTokens.contains(where: { $0.range.contains(index) }), let found = standsAlone(index) else {
                index += 1
                continue
            }
            var next = found.end
            while next < line.end, scalars[next].properties.isWhitespace { next += 1 }
            if next < line.end, scalars[next].properties.isAlphabetic, standsAlone(next) == nil {
                index = found.end
                continue
            }
            var core = String.UnicodeScalarView()
            core.append(contentsOf: scalars[index..<found.core])
            out.append(Marker(start: index, end: found.end, coreEnd: found.core, text: String(core)))
            index = found.end
        }
        return out
    }

    // MARK: Lines

    static func isLineBreak(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x0A, 0x0B, 0x0C, 0x0D, 0x85, 0x2028, 0x2029: true
        default: false
        }
    }

    /// Lines split at LF, VT, FF, CR, NEL, U+2028 and U+2029, with CR LF one break.
    static func splitLines(_ scalars: [Unicode.Scalar]) -> [Line] {
        var lines: [Line] = []
        var start = 0
        var index = 0
        while index < scalars.count {
            if isLineBreak(scalars[index]) {
                lines.append(Line(start: start, end: index))
                if scalars[index] == "\r", index + 1 < scalars.count, scalars[index + 1] == "\n" { index += 1 }
                start = index + 1
            }
            index += 1
        }
        lines.append(Line(start: start, end: scalars.count))
        return lines
    }

    public func line(containing offset: Int) -> Line? {
        lines.first { $0.start <= offset && offset <= $0.end }
    }

    public func isBlank(_ line: Line) -> Bool {
        (line.start..<line.end).allSatisfy { scalars[$0].properties.isWhitespace }
    }

    public func text(_ range: Range<Int>) -> String {
        var out = String.UnicodeScalarView()
        out.append(contentsOf: scalars[range])
        return String(out)
    }

    // MARK: Boundaries (4.3 item 2)

    /// The characters that bound a token besides whitespace and a boundary `,` or `，`: the 4.3
    /// list `( ) [ ] ; : / |`, their full-width forms `（ ） ［ ］ ； ： ／ ｜` (coordinator
    /// amendment to 4.3 item 2, A1 of #416: full-width punctuation is the normal separator in
    /// Taiwan text), and the ideographic comma and full stop `、` and `。`.
    static let boundaryMarks: Set<Unicode.Scalar> = [
        "(", ")", "[", "]", ";", ":", "/", "|",
        "\u{FF08}", "\u{FF09}", "\u{FF3B}", "\u{FF3D}", "\u{FF1B}", "\u{FF1A}", "\u{FF0F}", "\u{FF5C}",
        "\u{3001}", "\u{3002}"
    ]

    /// Whether the scalar at `index` is a token boundary: whitespace (U+00A0 and U+202F included),
    /// one of `boundaryMarks`, or a `,` or full-width `，` (U+FF0C) that is not between two digits
    /// (a `,` between two digits is a decimal mark or a thousands separator, never a boundary; a
    /// `，` between two digits is neither, so a token cannot end there). A CJK letter is never a
    /// boundary, so a value glued to one is not a whole token.
    static func isBoundary(_ scalars: [Unicode.Scalar], at index: Int) -> Bool {
        let scalar = scalars[index]
        if scalar.properties.isWhitespace || isLineBreak(scalar) || boundaryMarks.contains(scalar) { return true }
        if scalar == "," || scalar == "\u{FF0C}" {
            let digitBefore = index > 0 && PastedLabelAITextValueGrammar.isDigit(scalars[index - 1])
            let digitAfter = index + 1 < scalars.count && PastedLabelAITextValueGrammar.isDigit(scalars[index + 1])
            return !(digitBefore && digitAfter)
        }
        return false
    }

    /// A token may start at `index`: the line's start, or a boundary just before it.
    static func boundaryBefore(_ scalars: [Unicode.Scalar], _ index: Int, line: Line) -> Bool {
        index == line.start || isBoundary(scalars, at: index - 1)
    }

    /// A token may end at `index` (exclusive): the line's end, or a boundary at it.
    static func boundaryAfter(_ scalars: [Unicode.Scalar], _ index: Int, line: Line) -> Bool {
        index == line.end || isBoundary(scalars, at: index)
    }

    static func starts(_ scalars: [Unicode.Scalar], at index: Int, with literal: String, limit: Int) -> Bool {
        let pattern = Array(literal.unicodeScalars)
        guard index >= 0, index + pattern.count <= limit else { return false }
        for (offset, scalar) in pattern.enumerated() where scalars[index + offset] != scalar { return false }
        return true
    }

    // MARK: Value tokens (4.3 item 2)

    /// The value tokens of one line: at each position where a token may start, the longest
    /// grammar match that also ends at a boundary; the scan resumes after a token.
    static func tokens(_ scalars: [Unicode.Scalar], line: Line) -> [Token] {
        var out: [Token] = []
        var index = line.start
        while index < line.end {
            if boundaryBefore(scalars, index, line: line), let token = match(scalars, at: index, line: line, requireEndBoundary: true) {
                out.append(token)
                index = token.end
            } else {
                index += 1
            }
        }
        return out
    }

    /// The grammar match starting at `start`, with or without the end boundary. The start
    /// boundary is the caller's (the whole-word rule asks for a token next to a CJK word).
    static func match(_ scalars: [Unicode.Scalar], at start: Int, line: Line, requireEndBoundary: Bool) -> Token? {
        let limit = line.end
        var position = start
        var comparator = "="
        for candidate in PastedLabelAITextValueGrammar.comparators
        where starts(scalars, at: position, with: candidate.printed, limit: limit) {
            comparator = candidate.value
            position += candidate.printed.unicodeScalars.count
            while position < limit, PastedLabelAITextValueGrammar.isTokenSpace(scalars[position]) { position += 1 }
            break
        }
        guard let number = number(scalars, at: position, limit: limit) else { return nil }
        let numberEnd = number.end
        var unitStart = numberEnd
        while unitStart < limit, PastedLabelAITextValueGrammar.isTokenSpace(scalars[unitStart]) { unitStart += 1 }
        func footnoted(_ end: Int) -> Int {
            var end = end
            while end < limit, scalars[end] == "*" || scalars[end] == "†" { end += 1 }
            return end
        }
        for unit in PastedLabelAITextValueGrammar.unitsLongestFirst where starts(scalars, at: unitStart, with: unit, limit: limit) {
            let coreEnd = unitStart + unit.unicodeScalars.count
            let end = footnoted(coreEnd)
            if requireEndBoundary, !boundaryAfter(scalars, end, line: line) { continue }
            return Token(start: start, end: end, coreEnd: coreEnd, comparator: comparator, numberText: number.printed,
                         decimalText: number.decimal, unit: unit, canonicalUnit: PastedLabelAITextValueGrammar.canonicalUnit(unit))
        }
        let end = footnoted(numberEnd)
        if requireEndBoundary, !boundaryAfter(scalars, end, line: line) { return nil }
        return Token(start: start, end: end, coreEnd: numberEnd, comparator: comparator, numberText: number.printed,
                     decimalText: number.decimal, unit: nil, canonicalUnit: nil)
    }

    /// A number at `start`: Nd digits with at most one decimal mark (`.`, or a `,` between two
    /// digits that is not a thousands separator). A `,` followed by exactly three digits and then
    /// a non-digit (or the line's end) is a thousands separator, before any decimal mark.
    static func number(_ scalars: [Unicode.Scalar], at start: Int, limit: Int) -> (end: Int, printed: String, decimal: String)? {
        let isDigit = PastedLabelAITextValueGrammar.isDigit
        guard start < limit, isDigit(scalars[start]) else { return nil }
        var index = start
        var decimal = String.UnicodeScalarView()
        func digits() {
            while index < limit, isDigit(scalars[index]) { decimal.append(scalars[index]); index += 1 }
        }
        digits()
        var marked = false
        while index < limit, !marked {
            let scalar = scalars[index]
            if scalar == "," {
                let groupEnd = index + 4
                let threeDigits = groupEnd <= limit && (index + 1..<groupEnd).allSatisfy { isDigit(scalars[$0]) }
                if threeDigits && (groupEnd == limit || !isDigit(scalars[groupEnd])) {
                    index += 1
                    digits()
                    continue
                }
            }
            if scalar == "." || scalar == ",", index + 1 < limit, isDigit(scalars[index + 1]) {
                decimal.append(".")
                index += 1
                digits()
                marked = true
                continue
            }
            break
        }
        var printed = String.UnicodeScalarView()
        printed.append(contentsOf: scalars[start..<index])
        return (index, String(printed), String(decimal))
    }

    // MARK: Bounds outside a token (review F2)

    /// Whether a token's printed bound may be lost or contradicted by a qualifier outside it.
    ///
    /// A token that printed no comparator is under attention when its left neighbour, past
    /// whitespace and punctuation (P*, `:` and `：` included; Qodo finding 3 on #421), is a
    /// comparator word of the closed list in any case (`Less than`, `LESS THAN`), a math symbol
    /// (Unicode Sm: `≦`, `~`, `=` and the like) or a bound word of either direction; or when its
    /// right neighbour, past spaces and punctuation on its line, is a bound word of either direction
    /// (Qodo findings on #421 at 21e2d76; lower bounds added in A2).
    ///
    /// A token that printed its own comparator (`<`, `<=`, an upper bound) already carries its
    /// bound, so a bound word or symbol that agrees with it (`<= 0.5g or less`, `少於5毫克以下`) adds no
    /// attention. One that contradicts it (`<5g or more`, `少於5毫克以上`, `at least <5g`), or a math
    /// symbol that is not an upper bound, stays under attention (A2 gate finding 4). The closed
    /// comparator lists of the grammar are unchanged.
    public func comparatorOutside(_ token: Token) -> Bool {
        let ownBound = token.comparator != "="
        if let direction = boundWordAfter(token) {
            if !ownBound || direction == .lower { return true }
        }
        var index = token.start - 1
        while index >= 0, scalars[index].properties.isWhitespace || Self.isLineBreak(scalars[index]) || Self.isPunctuation(scalars[index]) {
            index -= 1
        }
        guard index >= 0 else { return false }
        if scalars[index].properties.generalCategory == .mathSymbol {
            return !ownBound || !Self.upperBoundSymbols.contains(scalars[index])
        }
        let start = max(0, index - 15)
        let before = text(start..<(index + 1)).lowercased()
        let upper = PastedLabelAITextValueGrammar.comparators.map { $0.printed.lowercased() } + Self.leftBoundWords
        for (words, direction) in [(upper, BoundDirection.upper), (Self.leftLowerBoundWords, .lower)] {
            for word in words where before.hasSuffix(word) {
                // A CJK word needs no word start; an English word must start one.
                let wordStart = index + 1 - word.unicodeScalars.count
                guard Self.isCJK(word.unicodeScalars.first!) || wordStart == 0 || !scalars[wordStart - 1].properties.isAlphabetic else { continue }
                if !ownBound || direction == .lower { return true }
            }
        }
        return false
    }

    enum BoundDirection { case upper, lower }

    /// Upper-bound bound words checked to the left of a token, lower-cased (English in any case).
    static let leftBoundWords = ["未滿", "少於", "低於", "不到", "小於", "less than", "fewer than", "under", "below", "up to", "max", "maximum",
                                 "not more than", "no more than"]
    /// Lower-bound bound words checked to the left of a token (A2).
    static let leftLowerBoundWords = ["超過", "大於", "高於", "不少於", "至少", "more than", "greater than", "at least", "over", "above", "min",
                                      "minimum", "not less than", "no less than"]
    /// Upper-bound bound words checked to the right of a token, past spaces and punctuation on its line.
    static let rightBoundWords = ["以下", "以內", "or less", "max", "maximum", "or under", "or below"]
    /// Lower-bound bound words checked to the right of a token (A2).
    static let rightLowerBoundWords = ["以上", "or more", "or over", "or above", "or greater", "min", "minimum"]
    /// Math symbols that state an upper bound, so agree with a token's own `<` or `<=`.
    static let upperBoundSymbols: Set<Unicode.Scalar> = ["<", "≤", "≦", "＜", "\u{2272}", "\u{2A7D}"]

    /// The direction of a bound word to the right of a token, if any.
    func boundWordAfter(_ token: Token) -> BoundDirection? {
        guard let line = line(containing: token.start) else { return nil }
        var index = token.end
        while index < line.end, scalars[index].properties.isWhitespace || Self.isPunctuation(scalars[index]) { index += 1 }
        guard index < line.end else { return nil }
        let after = text(index..<min(line.end, index + 16)).lowercased()
        // Longest first across both lists, so `minimum` is read whole.
        let words = (Self.rightBoundWords.map { ($0, BoundDirection.upper) } + Self.rightLowerBoundWords.map { ($0, BoundDirection.lower) })
            .sorted { $0.0.unicodeScalars.count > $1.0.unicodeScalars.count }
        for (word, direction) in words where after.hasPrefix(word) {
            if Self.isCJK(word.unicodeScalars.first!) { return direction }
            let end = index + word.unicodeScalars.count
            if end >= line.end || !scalars[end].properties.isAlphabetic { return direction }
        }
        return nil
    }

    // MARK: Whole words (4.3 item 3)

    static func isPunctuation(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.properties.generalCategory {
        case .connectorPunctuation, .dashPunctuation, .openPunctuation, .closePunctuation, .initialPunctuation, .finalPunctuation,
             .otherPunctuation: true
        default: false
        }
    }

    /// Script=Han, Hiragana or Katakana, as the platform's ICU reads the Script property.
    static func isCJK(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case ..<0x2E80: return false
        case 0x3041...0x3096, 0x30A1...0x30FA, 0x3400...0x4DBF, 0x4E00...0x9FFF: return true
        default: break
        }
        return String(Character(scalar)).range(of: #"^[\p{Script=Han}\p{Script=Hiragana}\p{Script=Katakana}]$"#,
                                              options: .regularExpression) != nil
    }

    /// Whether a value token ends exactly at `index` (exclusive) on `line`, starting anywhere on it.
    func tokenEnds(at index: Int, line: Line) -> Bool {
        (line.start..<index).contains { start in
            guard let token = Self.match(scalars, at: start, line: line, requireEndBoundary: false) else { return false }
            return token.coreEnd == index || token.end == index
        }
    }

    /// The left neighbour of a word starting at `start`, under the rule of the word's first scalar.
    func leftNeighbourAllows(_ start: Int, edge: Unicode.Scalar, line: Line) -> Bool {
        if start == line.start { return true }
        let neighbour = scalars[start - 1]
        if neighbour.properties.isWhitespace || Self.isPunctuation(neighbour) { return true }
        guard Self.isCJK(edge) else { return false }
        return !Self.isCJK(neighbour) || tokenEnds(at: start, line: line)
    }

    /// The right neighbour of a word ending at `end` (exclusive), under the rule of its last scalar.
    func rightNeighbourAllows(_ end: Int, edge: Unicode.Scalar, line: Line) -> Bool {
        if end == line.end { return true }
        let neighbour = scalars[end]
        if neighbour.properties.isWhitespace || Self.isPunctuation(neighbour) { return true }
        guard Self.isCJK(edge) else { return false }
        return !Self.isCJK(neighbour) || Self.match(scalars, at: end, line: line, requireEndBoundary: false) != nil
    }

    /// Every occurrence of `word` as whole words, in text order. A word never spans a line break.
    public func wholeWordOccurrences(of word: String) -> [Range<Int>] {
        let pattern = Array(word.unicodeScalars)
        guard let first = pattern.first, let last = pattern.last else { return [] }
        var out: [Range<Int>] = []
        for line in lines where line.end - line.start >= pattern.count {
            var start = line.start
            while start + pattern.count <= line.end {
                if Self.starts(scalars, at: start, with: word, limit: line.end),
                   leftNeighbourAllows(start, edge: first, line: line),
                   rightNeighbourAllows(start + pattern.count, edge: last, line: line) {
                    out.append(start..<(start + pattern.count))
                }
                start += 1
            }
        }
        return out
    }
}
