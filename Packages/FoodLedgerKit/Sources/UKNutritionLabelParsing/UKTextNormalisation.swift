import Foundation
import NutritionLabelParsing

/// The UK reader's closed normalisation rules N1 to N4 (`docs/pasted-nutrition-label-uk-english-v1-p2.md`
/// section 2), N5 (`docs/pasted-nutrition-label-uk-english-v1-p2b.md` section 2), and N6 and N7
/// (`docs/pasted-nutrition-label-uk-english-v2-p1.md` section 3), applied to English text only,
/// after the region stage and before parser v3. Each rule moves, joins or respells printed tokens;
/// none adds, drops or changes a digit run, decimal separator or comparator. A line no rule
/// matches is returned byte for byte. Part of `nutrition-label-text-parser-uk-v3`: any change
/// here is a new parser version.
public enum UKTextNormalisation {
    /// The normalised text, its lines joined with `\n` exactly as the input's lines were split.
    public static func normalise(_ text: String) -> String {
        lines(text).joined(separator: "\n")
    }

    /// The normalised lines: N4 splits first, then each line gets at most one of N1, N2, N3, N5.
    /// The language is checked on `text` itself; the UK parser passes the pasted text's decision
    /// through `lines(_:english:)` instead.
    public static func lines(_ text: String) -> [String] {
        lines(text.components(separatedBy: "\n"),
              english: NutritionLabelTextParserV3().parse(text, inputSHA256: "").language == .english).lines
    }

    /// The normalised lines of English text (`english` is the pasted text's language decision, so
    /// the region stage and normalisation always agree), and the number of row pairs N7 wrote, if
    /// it fired. Order: N7 on the whole text; then N4 splits and each line gets at most one of
    /// N1, N2, N3, N5; then N6 on the heading line. Anything not English is untouched.
    public static func lines(_ input: [String], english: Bool) -> (lines: [String], n7Pairs: Int?) {
        guard english else { return (input, nil) }
        let joined = joinOneCellPerLine(input)
        var out: [String] = []
        for line in joined?.lines ?? input {
            for piece in splitGluedTitle(line) {
                out.append(rewrite(piece, above: out))
            }
        }
        return (headingWithoutPer(out), joined?.pairs)
    }

    // MARK: N6 a heading without "per"

    static let wholeQuantity = UKPattern(#"(?i)^\d+(?:[.,]\d+)?\s*(?:g|ml)$"#)
    static let hundredQuantity = UKPattern(#"(?i)^100\s*(?:g|ml)$"#)
    static let quantityWithServingWord = UKPattern(
        #"(?i)^(?:\d+(?:[.,]\d+)?\s*(?:g|ml)\s+(?:"# + UKVocabulary.servingWords.joined(separator: "|")
            + #")|(?:1|one|1/\d+\s+of\s+a)\s+(?:"# + UKVocabulary.servingWords.joined(separator: "|")
            + #")\s*\(\s*\d+(?:[.,]\d+)?\s*(?:g|ml)\s*\))$"#)

    /// On the heading line only: a whole `100 g` or `100 ml` cell gains `Per`, so does a weight or
    /// volume with a closed serving word, and an empty first cell (left by S5) becomes
    /// `Typical values`. No digit, unit or comparator changes.
    static func headingWithoutPer(_ lines: [String]) -> [String] {
        guard let heading = UKTableRegion.headingIndex(lines) else { return lines }
        var cells = lines[heading].components(separatedBy: "\t")
        guard cells.count >= 2 else { return lines }
        var changed = false
        for index in cells.indices.dropFirst() {
            let cell = UKTableRegion.trimmed(cells[index])
            if hundredQuantity.contains(cell) || quantityWithServingWord.contains(cell) {
                cells[index] = "Per " + cell
                changed = true
            }
        }
        if UKTableRegion.trimmed(cells[0]).isEmpty, cells.dropFirst().contains(where: { headerPhrase.contains($0) }) {
            cells[0] = "Typical values"
            changed = true
        }
        guard changed else { return lines }
        var out = lines
        out[heading] = cells.joined(separator: "\t")
        return out
    }

    // MARK: N7 one cell per line

    static let valueCell = UKPattern(
        #"(?i)^(?:less than|<)?\s*\d+(?:[.,]\d+)?\s*(?:kj|kcal|mcg|mg|µg|μg|ml|g)?(?:\s*/\s*(?:less than|<)?\s*\d+(?:[.,]\d+)?\s*(?:kj|kcal|mcg|mg|µg|μg|ml|g)?)?$"#)
    static let markerCells: Set<String> = ["trace", "tr", "-", "nil"]
    static let referenceBasis = UKPattern(#"(?i)%\s*RI|\bRI\b|reference intake|%\s*DV|daily value|\bNRV\b"#)

    /// The whole one-cell-per-line shape (optional title lines, a title heading with an optional
    /// empty second cell, exactly one basis line, then label and value line pairs to the end),
    /// blank lines allowed anywhere, rewritten as tabbed lines; nil when anything breaks it.
    static func joinOneCellPerLine(_ input: [String]) -> (lines: [String], pairs: Int)? {
        let lines = input.map(UKTableRegion.trimmed).filter { !$0.isEmpty }
        var index = 0
        var titles: [String] = []
        // 1 and 2: title lines, then the heading's title cell (the last title before the basis line).
        while index < lines.count {
            let cells = lines[index].components(separatedBy: "\t").map(UKTableRegion.trimmed)
            guard cells.count <= 2, UKTableRegion.isTableTitle(cells[0]), cells.count == 1 || cells[1].isEmpty else { break }
            titles.append(cells[0])
            index += 1
        }
        guard let headingTitle = titles.popLast(), index < lines.count else { return nil }
        // 3: exactly one basis line.
        let basis = lines[index]
        guard !basis.contains("\t"), headerPhrase.contains(basis), !referenceBasis.contains(basis) else { return nil }
        index += 1
        // 4 and 5: label and value pairs to the end of the kept text.
        var rows: [String] = []
        while index < lines.count {
            let label = lines[index]
            guard index + 1 < lines.count else { return nil }
            let cell = lines[index + 1]
            guard !label.contains("\t"), !label.contains(where: \.isNumber), !headerPhrase.contains(label),
                  !cell.contains("\t"), valueCell.contains(cell) || markerCells.contains(cell.lowercased()) else { return nil }
            rows.append(label + "\t" + cell)
            index += 2
        }
        guard rows.count >= 2 else { return nil }
        return (titles + [headingTitle + "\t" + basis] + rows, rows.count)
    }

    static func rewrite(_ line: String, above: [String]) -> String {
        if let n1 = respellHeaderUnit(line) { return n1 }
        if let n2 = moveLabelUnit(line) { return n2 }
        if let n3 = plainSubRowMarker(line, above: above) { return n3 }
        if let n5 = dropRedundantEnergyUnit(line) { return n5 }
        return line
    }

    // MARK: N1 header unit spelling

    static let headerPhrase = UKPattern(UKVocabulary.headerPhrasePattern)
    static let gramSpelling = UKPattern(#"(?i)(?<![\d.,])100\s*(?:gm|gms|gr|grs|gram|grams|gramme|grammes)(?![\p{L}])"#)
    static let millilitreSpelling = UKPattern(#"(?i)(?<![\d.,])100\s*(?:mls|millilitre|millilitres|milliliter|milliliters)(?![\p{L}])"#)

    static func respellHeaderUnit(_ line: String) -> String? {
        guard headerPhrase.contains(line), gramSpelling.contains(line) || millilitreSpelling.contains(line) else { return nil }
        return millilitreSpelling.replacing(in: gramSpelling.replacing(in: line, with: "100g"), with: "100ml")
    }

    // MARK: N2 unit in the row label

    static let value = UKPattern(UKVocabulary.valuePattern)
    static let bracketedLabelUnits = ["KJ", "Kj", "Kcal", "KCAL", "kCal", "μg"]
    static let bareLabelUnits = ["g", "mg", "µg", "μg", "mcg", "kJ", "kj", "KJ", "Kj", "kcal", "Kcal", "KCAL", "kCal"]
    static let separators = CharacterSet(charactersIn: " \t|")

    static func moveLabelUnit(_ line: String) -> String? {
        let values = value.matches(line)
        guard let first = values.first, !line.contains("/") else { return nil }
        // Every value is a bare number (a comparator allowed), separated only by spaces, tabs or `|`.
        guard values.allSatisfy({ $0.groups[3] == nil }) else { return nil }
        var cursor = first.range.upperBound
        for match in values.dropFirst() {
            guard line[cursor..<match.range.lowerBound].unicodeScalars.allSatisfy(separators.contains) else { return nil }
            cursor = match.range.upperBound
        }
        guard line[cursor...].unicodeScalars.allSatisfy(separators.contains) else { return nil }
        let label = String(line[..<first.range.lowerBound])
        guard let (stripped, unit) = labelUnit(label) else { return nil }
        // The unit goes straight after each number (the value pattern's match also takes the
        // spaces that follow it).
        var out = stripped
        var previous = first.range.lowerBound
        for number in value.groupRanges(line, group: 2).compactMap({ $0 }) {
            out += line[previous..<number.upperBound] + unit
            previous = number.upperBound
        }
        out += line[previous...]
        return out
    }

    /// The label without its one trailing unit token, and that unit; nil unless the label ends
    /// with exactly one unit from N2's closed list and holds no other unit token.
    static func labelUnit(_ label: String) -> (String, String)? {
        let trimmed = label.trimmingCharacters(in: CharacterSet(charactersIn: " \t:"))
        var unit: String?
        var rest = trimmed
        for candidate in bracketedLabelUnits where trimmed.hasSuffix("(\(candidate))") {
            unit = candidate
            rest = String(trimmed.dropLast(candidate.count + 2))
        }
        if unit == nil, let last = trimmed.split(whereSeparator: { $0 == " " || $0 == "\t" }).last,
           bareLabelUnits.contains(String(last)), trimmed.count > last.count {
            unit = String(last)
            rest = String(trimmed.dropLast(last.count))
        }
        guard let unit else { return nil }
        let name = rest.trimmingCharacters(in: CharacterSet(charactersIn: " \t:"))
        guard !name.isEmpty, name.contains(where: \.isLetter), UKReadingGuard.unitTokens(in: name).isEmpty else { return nil }
        // Keep the label's own separator before the values.
        let trailing = String(label.reversed().prefix { $0 == " " || $0 == "\t" || $0 == ":" }.reversed())
        return (name + (trailing.isEmpty ? " " : trailing), unit)
    }

    // MARK: N5 redundant energy label unit

    static let energyLabelUnits = ["kJ", "kj", "KJ", "Kj", "kcal", "Kcal", "KCAL", "kCal"]

    /// Parser v3's canonical energy unit: `kJ`, `kcal` and `cal` stay distinct.
    static func canonicalEnergyUnit(_ unit: String) -> String? {
        switch unit.lowercased() {
        case "kj": "kJ"
        case "kcal": "kcal"
        case "cal": "cal"
        default: nil
        }
    }

    /// `Energy kJ  1520 kJ  456 kJ` becomes `Energy  1520 kJ  456 kJ`: the label is exactly an
    /// energy label plus one unit token that every value on the line repeats, separated only by
    /// spaces, tabs or `|`. Any other line is untouched.
    static func dropRedundantEnergyUnit(_ line: String) -> String? {
        let values = value.matches(line)
        guard let first = values.first, !line.contains("/") else { return nil }
        var cursor = first.range.upperBound
        for match in values.dropFirst() {
            guard line[cursor..<match.range.lowerBound].unicodeScalars.allSatisfy(separators.contains) else { return nil }
            cursor = match.range.upperBound
        }
        guard line[cursor...].unicodeScalars.allSatisfy(separators.contains) else { return nil }
        let label = String(line[..<first.range.lowerBound])
        let trimmed = label.trimmingCharacters(in: CharacterSet(charactersIn: " \t:"))
        let words = trimmed.split(whereSeparator: { $0 == " " || $0 == "\t" })
        guard words.count == 2, let unit = words.last.map(String.init), energyLabelUnits.contains(unit),
              UKVocabulary.energyLabels.contains(words[0].lowercased()), let canonical = canonicalEnergyUnit(unit) else { return nil }
        guard values.allSatisfy({ match in match.groups[3].flatMap(canonicalEnergyUnit) == canonical }) else { return nil }
        let trailing = String(label.reversed().prefix { $0 == " " || $0 == "\t" || $0 == ":" }.reversed())
        return String(words[0]) + (trailing.isEmpty ? " " : trailing) + line[first.range.lowerBound...]
    }

    // MARK: N3 sub-row markers

    static let dashedOfWhich = UKPattern(#"(?i)\b(of\s+which)\s*(?:\x{2014}|\bare\b)\s*"#)
    static let underscoredOfWhich = UKPattern(#"(?i)^(\s*)_+\s*(of\s+which)"#)
    static let bracketedSubRow = UKPattern(#"(?i)^(\s*)\(\s*(?:of\s+which\s+)?([a-z-]+)\s*\)"#)

    static func plainSubRowMarker(_ line: String, above: [String]) -> String? {
        if dashedOfWhich.contains(line) { return dashedOfWhich.replacing(in: line, with: "$1 ") }
        if underscoredOfWhich.contains(line) { return underscoredOfWhich.replacing(in: line, with: "$1$2") }
        if let match = bracketedSubRow.matches(line).first, let name = match.groups[2]?.lowercased(),
           let parent = UKVocabulary.subRowParents[name], nearestTopLevelRow(above) == parent {
            return (match.groups[1] ?? "") + "of which " + (match.groups[2] ?? "") + line[match.range.upperBound...]
        }
        return nil
    }

    static func nearestTopLevelRow(_ lines: [String]) -> String? {
        for line in lines.reversed() {
            let lowered = line.trimmingCharacters(in: .whitespaces).lowercased()
            if lowered.hasPrefix("of which") || lowered.hasPrefix("(") || lowered.hasPrefix("-") || lowered.hasPrefix("_") { continue }
            if let top = UKVocabulary.topLevelRows.first(where: { lowered.hasPrefix($0.prefix) }) { return top.row }
        }
        return nil
    }

    // MARK: N4 a title glued to the first row

    static let titles = ["average nutritional information", "nutritional information", "typical values", "average values", "nutrition"]

    static func splitGluedTitle(_ line: String) -> [String] {
        let lowered = line.lowercased()
        for title in titles where lowered.hasPrefix(title) {
            let rest = line.dropFirst(title.count)
            guard let first = rest.first, first == " " || first == "\t" else { return [line] }
            let row = rest.drop { $0 == " " || $0 == "\t" }
            guard UKVocabulary.energyLabels.contains(where: { row.lowercased().hasPrefix($0) }),
                  row.dropFirst("energy".count).first.map({ !$0.isLetter }) ?? true else { return [line] }
            return [String(line.prefix(title.count)), String(row)]
        }
        return [line]
    }
}
