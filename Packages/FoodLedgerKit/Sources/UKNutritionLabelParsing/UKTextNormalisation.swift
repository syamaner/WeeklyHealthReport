import Foundation
import NutritionLabelParsing

/// The UK reader's closed normalisation rules N1 to N4 (`docs/pasted-nutrition-label-uk-english-v1-p2.md`
/// section 2), applied to English text only, before parser v3. Each rule moves or respells printed
/// tokens; none adds, drops or changes a digit run, decimal separator or comparator. A line no
/// rule matches is returned byte for byte. Part of `nutrition-label-text-parser-uk-v1`: any change
/// here is a new parser version.
public enum UKTextNormalisation {
    /// The normalised text, its lines joined with `\n` exactly as the input's lines were split.
    public static func normalise(_ text: String) -> String {
        lines(text).joined(separator: "\n")
    }

    /// The normalised lines: N4 splits first, then each line gets at most one of N1, N2, N3.
    public static func lines(_ text: String) -> [String] {
        // English text only (parser v3's language, through its public API); anything else is untouched.
        guard NutritionLabelTextParserV3().parse(text, inputSHA256: "").language == .english else { return text.components(separatedBy: "\n") }
        var out: [String] = []
        for line in text.components(separatedBy: "\n") {
            for piece in splitGluedTitle(line) {
                out.append(rewrite(piece, above: out))
            }
        }
        return out
    }

    static func rewrite(_ line: String, above: [String]) -> String {
        if let n1 = respellHeaderUnit(line) { return n1 }
        if let n2 = moveLabelUnit(line) { return n2 }
        if let n3 = plainSubRowMarker(line, above: above) { return n3 }
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
