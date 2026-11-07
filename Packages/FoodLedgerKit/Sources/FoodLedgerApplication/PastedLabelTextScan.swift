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

    public let scalars: [Unicode.Scalar]
    public let lines: [Line]
    /// Every value token of the text, in text order.
    public let tokens: [Token]

    public init(_ text: String) {
        let scalars = Array(text.unicodeScalars)
        self.scalars = scalars
        let lines = Self.splitLines(scalars)
        self.lines = lines
        self.tokens = lines.flatMap { Self.tokens(scalars, line: $0) }
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

    /// Whether a token that printed no comparator has, as its left neighbour past whitespace, a
    /// comparator word of the closed list in any case (`Less than`, `LESS THAN`) or a math symbol
    /// (Unicode Sm: `≦`, `~`, `=` and the like). The token then may have lost its bound.
    public func comparatorOutside(_ token: Token) -> Bool {
        guard token.comparator == "=" else { return false }
        var index = token.start - 1
        while index >= 0, scalars[index].properties.isWhitespace || Self.isLineBreak(scalars[index]) { index -= 1 }
        guard index >= 0 else { return false }
        if scalars[index].properties.generalCategory == .mathSymbol { return true }
        let start = max(0, index - 15)
        let before = text(start..<(index + 1)).lowercased()
        for comparator in PastedLabelAITextValueGrammar.comparators {
            let word = comparator.printed.lowercased()
            guard before.hasSuffix(word) else { continue }
            let wordStart = index + 1 - word.unicodeScalars.count
            if wordStart == 0 || !scalars[wordStart - 1].properties.isAlphabetic { return true }
        }
        return false
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
