import Foundation
import NutritionLabelParsing

/// The UK reader's closed guard rules G1 to G3 (`docs/pasted-nutrition-label-uk-english-v1-p2.md`
/// section 3). The guard only ever returns its candidate unchanged or a decline: it never moves a
/// value, basis or row. Part of `nutrition-label-text-parser-uk-v2`.
public enum UKReadingGuard {
    public static let headerBasisUnrecognised = "uk_header_basis_unrecognised"
    public static let conflictingUnits = "uk_orphan_unit"
    /// The application's identity decline code (`PastedLabelIdentity.basisStateNotSupported`).
    public static let basisStateNotSupported = "basis_state_not_supported"

    /// The guarded candidate: `candidate` itself, or a decline with the first rule that fires.
    public static func apply(_ candidate: LabelCaptureCandidate, normalisedLines lines: [String]) -> LabelCaptureCandidate {
        guard let code = declineCode(candidate, normalisedLines: lines) else { return candidate }
        return .declined(route: candidate.route, inputSHA256: candidate.inputSHA256, language: candidate.language, reasons: [code])
    }

    static func declineCode(_ candidate: LabelCaptureCandidate, normalisedLines lines: [String]) -> String? {
        if !candidate.declined, candidate.headers.contains(where: { $0.basis == .perServing && namesHundred($0.printedText) }) {
            return headerBasisUnrecognised
        }
        if lines.contains(where: hasConflictingUnits) { return conflictingUnits }
        if lines.contains(where: carriesIdentityMarker) { return basisStateNotSupported }
        return nil
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
        return words.contains { UKVocabulary.identityWordMarkers.contains(String($0)) }
    }
}
