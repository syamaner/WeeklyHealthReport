import Foundation
import NutritionLabelParsing

/// The UK reader's closed guard rules G1 to G3 (`docs/pasted-nutrition-label-uk-english-v1-p2.md`
/// section 3) and G4 (`docs/pasted-nutrition-label-uk-english-v2-p1.md` section 3). The guard only
/// ever returns its candidate unchanged or a decline: it never moves a value, basis or row. G4 runs
/// first, so its code takes precedence over parser codes; G3 also reads the set-aside text. Part of
/// `nutrition-label-text-parser-uk-v3`.
public enum UKReadingGuard {
    public static let headerBasisUnrecognised = "uk_header_basis_unrecognised"
    public static let conflictingUnits = "uk_orphan_unit"
    /// The application's identity decline code (`PastedLabelIdentity.basisStateNotSupported`).
    public static let basisStateNotSupported = "basis_state_not_supported"
    public static let regionInconsistent = "uk_region_inconsistent"

    /// The guarded candidate: `candidate` itself, or a decline with the first rule that fires.
    public static func apply(_ candidate: LabelCaptureCandidate, normalisedLines lines: [String], setAside: [String] = [],
                             n7Pairs: Int? = nil) -> LabelCaptureCandidate {
        guard let code = declineCode(candidate, normalisedLines: lines, setAside: setAside, n7Pairs: n7Pairs) else { return candidate }
        return .declined(route: candidate.route, inputSHA256: candidate.inputSHA256, language: candidate.language, reasons: [code])
    }

    static func declineCode(_ candidate: LabelCaptureCandidate, normalisedLines lines: [String], setAside: [String] = [],
                            n7Pairs: Int? = nil) -> String? {
        // G4 (a) a count line left inside the table; (b) N7's pairs against the rows parser v3 saw.
        if lines.contains(where: UKTableRegion.isCountStatement) { return regionInconsistent }
        if let n7Pairs, !candidate.declined, valueCount(candidate) != n7Pairs { return regionInconsistent }
        if !candidate.declined, candidate.headers.contains(where: { $0.basis == .perServing && namesHundred($0.printedText) }) {
            return headerBasisUnrecognised
        }
        if lines.contains(where: hasConflictingUnits) { return conflictingUnits }
        if (lines + setAside).contains(where: carriesIdentityMarker) { return basisStateNotSupported }
        return nil
    }

    /// What parser v3 made of N7's values, duplicates kept: every bound cell plus every unread row.
    static func valueCount(_ candidate: LabelCaptureCandidate) -> Int {
        candidate.cells.count + candidate.warnings.filter { $0.hasPrefix("row_not_read: ") }.count
    }

    // MARK: G1 header basis

    static let standaloneHundred = UKPattern(#"(?<![\d.,])100(?![\d.,])"#)
    static let bracketedHundredUnit = UKPattern(#"(?i)(?<![\d.,])100(?![\d.,])\s*(?:g|ml)(?![\p{L}])"#)

    /// A per serving header that names 100 of something outside its brackets, or 100 of anything
    /// but grams or millilitres inside them.
    static func namesHundred(_ printed: String) -> Bool {
        let (outside, inside) = splitOutermostBrackets(printed)
        if standaloneHundred.contains(outside) { return true }
        return inside.contains { standaloneHundred.matches($0).count > bracketedHundredUnit.matches($0).count }
    }

    static func splitOutermostBrackets(_ text: String) -> (outside: String, inside: [String]) {
        var outside = ""
        var inside: [String] = []
        var current = ""
        var depth = 0
        for character in text {
            switch character {
            case "(", "（":
                if depth > 0 { current.append(character) }
                depth += 1
            case ")" where depth > 0, "）" where depth > 0:
                depth -= 1
                if depth == 0 { inside.append(current); current = ""; outside.append(" ") } else { current.append(character) }
            default:
                if depth > 0 { current.append(character) } else { outside.append(character) }
            }
        }
        if depth > 0 { outside += current }
        return (outside, inside)
    }

    // MARK: G2 conflicting units on a line

    static let value = UKPattern(UKVocabulary.valuePattern)
    static let unitToken = UKPattern("(?<![\\p{L}\\p{N}])(" + UKVocabulary.unitTokens.joined(separator: "|") + ")(?![\\p{L}])")
    static let slashJoined = UKPattern(#"\d\s*/\s*\d"#)

    static func unitTokens(in text: String) -> [String] {
        unitToken.matches(text).compactMap { $0.groups[1] }
    }

    static func canonical(_ unit: String) -> String {
        unit.lowercased().replacingOccurrences(of: "μ", with: "µ")
    }

    /// `100g/ml` names one per 100 basis for a solid or a liquid (`per 100g/ml`), not two units.
    static let gramsOrMillilitres = UKPattern(#"(?i)(?<![\d.,])100\s*g\s*/\s*ml(?![\p{L}])"#)

    static func hasConflictingUnits(_ raw: String) -> Bool {
        let line = gramsOrMillilitres.replacing(in: raw, with: "100g")
        let values = value.matches(line)
        guard let first = values.first else { return false }
        let labelUnits = unitTokens(in: String(line[..<first.range.lowerBound]))
        // (a) a unit token after the first value with no number of its own.
        var gaps = ""
        var cursor = first.range.upperBound
        for match in values.dropFirst() {
            gaps += line[cursor..<match.range.lowerBound] + " "
            cursor = match.range.upperBound
        }
        gaps += line[cursor...]
        if !unitTokens(in: gaps).isEmpty { return true }
        // (b) more than one unit token in the label.
        if labelUnits.count > 1 { return true }
        guard let labelUnit = labelUnits.first.map(canonical) else { return false }
        // (c) a value carrying a unit other than the label's (percentages aside).
        if values.contains(where: { match in match.groups[3].map { $0 != "%" && canonical($0) != labelUnit } ?? false }) { return true }
        // (d) numbers joined by `/` under a label unit.
        return slashJoined.contains(String(line[first.range.lowerBound...]))
    }

    // MARK: G3 identity on every line

    static func carriesIdentityMarker(_ line: String) -> Bool {
        if UKVocabulary.identitySymbolMarkers.contains(where: line.contains) { return true }
        let words = line.lowercased().split { !$0.isLetter }
        return words.contains { word in
            UKVocabulary.identityWordMarkers.contains(String(word)) || isCompoundCookingWord(String(word))
        }
    }

    /// Identity v3's rule I1 on one lower-cased letter run.
    static func isCompoundCookingWord(_ word: String) -> Bool {
        UKVocabulary.identityCompoundPrefixes.contains { prefix in
            word.hasPrefix(prefix) && UKVocabulary.identityCompoundCookingWords.contains(String(word.dropFirst(prefix.count)))
        }
    }
}
