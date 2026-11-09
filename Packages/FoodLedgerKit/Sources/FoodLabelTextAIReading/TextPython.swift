import Foundation

// A copy of the Python `str` and `re` behaviours `label-photo-wire-mapping-v1` reproduces
// (`FoodLabelPhotoReading/LabelPhotoWireMapping.swift`, `PythonText` and its serving patterns),
// which are internal to a pinned file this target may not import. The text mapping's copy of
// `parseValue` and its serving lines read through these, so parity with the photo copy holds
// (contract test 26).

/// The few Python `str` and `re` behaviours the mapping depends on.
enum TextPython {
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

    // MARK: Serving lines (copied with the grammar)

    /// `PRINTED_MASS.search`: `(\d+(?:\.\d+)?)\s*(g|ml|mL|公克|毫升|克)(?![A-Za-z])`, leftmost.
    static func printedMass(_ text: String) -> (number: String, unit: String)? {
        let characters = Array(text)
        for start in characters.indices where isDigit(characters[start]) {
            for end in TextPython.decimalEnds(characters, from: start, separators: ["."]) {
                let unitStart = TextPython.skipSpace(characters, from: end)
                for unit in ["g", "ml", "mL", "公克", "毫升", "克"] where TextPython.starts(characters, at: unitStart, with: unit) {
                    let next = unitStart + unit.count
                    if next < characters.count, TextPython.isASCIILetter(characters[next]) { continue }
                    return (String(characters[start..<end]), unit)
                }
            }
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
                let digits = TextPython.skipSpace(c, from: position)
                guard digits < c.count, isDigit(c[digits]) else { continue }
                for end in TextPython.decimalEnds(c, from: digits, separators: ["."]) {
                    let mark = TextPython.skipSpace(c, from: end)
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
            for word in ["about", "approx.", "approx", "approximately"] where TextPython.startsCaseless(c, at: start, with: word) {
                attempts.append((start + word.count, true))
            }
            attempts.append((start, false))
            for (position, approximate) in attempts {
                let digits = TextPython.skipSpace(c, from: position)
                guard digits < c.count, isDigit(c[digits]) else { continue }
                for end in TextPython.decimalEnds(c, from: digits, separators: ["."]) {
                    let word = TextPython.skipSpace(c, from: end)
                    if TextPython.startsCaseless(c, at: word, with: "serving") { return (String(c[digits..<end]), approximate) }
                }
            }
        }
        return nil
    }

    /// `SERVINGS_EN_TRAILING.search` (case-insensitive):
    /// `servings?\s+per\s+(?:container|pack(?:age)?)\D*?(about\s+)?(\d+(?:\.\d+)?)`, leftmost.
    static func servingsEnTrailing(_ text: String) -> (number: String, approximate: Bool)? {
        let c = Array(text)
        for start in c.indices where TextPython.startsCaseless(c, at: start, with: "serving") {
            var afterWord = [start + 7]
            if TextPython.startsCaseless(c, at: start + 7, with: "s") { afterWord.insert(start + 8, at: 0) }
            for position in afterWord {
                guard position < c.count, TextPython.isSpace(c[position]) else { continue }
                let per = TextPython.skipSpace(c, from: position)
                guard TextPython.startsCaseless(c, at: per, with: "per"), per + 3 < c.count, TextPython.isSpace(c[per + 3]) else { continue }
                let noun = TextPython.skipSpace(c, from: per + 3)
                var ends: [Int] = []
                if TextPython.startsCaseless(c, at: noun, with: "container") { ends.append(noun + 9) }
                if TextPython.startsCaseless(c, at: noun, with: "package") { ends.append(noun + 7) }
                if TextPython.startsCaseless(c, at: noun, with: "pack") { ends.append(noun + 4) }
                for end in ends {
                    // `\D*?` is lazy: the shortest run of non-digits after which the rest matches.
                    var lazy = end
                    while lazy <= c.count {
                        if let match = aboutThenNumber(c, from: lazy) { return match }
                        guard lazy < c.count, !isDigit(c[lazy]) else { break }
                        lazy += 1
                    }
                }
            }
        }
        return nil
    }

    static func aboutThenNumber(_ c: [Character], from index: Int) -> (number: String, approximate: Bool)? {
        var attempts: [(Int, Bool)] = []
        if TextPython.startsCaseless(c, at: index, with: "about"), index + 5 < c.count, TextPython.isSpace(c[index + 5]) {
            attempts.append((TextPython.skipSpace(c, from: index + 5), true))
        }
        attempts.append((index, false))
        for (position, approximate) in attempts where position < c.count && isDigit(c[position]) {
            guard let end = TextPython.decimalEnds(c, from: position, separators: ["."]).first else { continue }
            return (String(c[position..<end]), approximate)
        }
        return nil
    }
}
