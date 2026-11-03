import Foundation
import NutritionLabelParsing

/// The UK English reader (`docs/pasted-nutrition-label-uk-english-v1-p2.md`):
/// `nutrition-label-text-parser-uk-v1` is normalisation rules N1 to N4, then the frozen parser v3
/// through its public API, then guard rules G1 to G3. It mirrors parser v3's three entry points,
/// each normalising the pasted text first and guarding after; `inputSHA256` is always the hash
/// of the pasted text, never of the normalised one. Meant for English text: the reader adapter
/// sends every other language to the pinned reader.
public struct NutritionLabelTextParserUK: Sendable {
    public static let version = "nutrition-label-text-parser-uk-v1"

    private let parser = NutritionLabelTextParserV3()

    public init() {}

    public func parse(_ text: String, route: String = "A", inputSHA256: String) -> LabelCaptureCandidate {
        let lines = Self.lines(text)
        return UKReadingGuard.apply(parser.parse(lines.joined(separator: "\n"), route: route, inputSHA256: inputSHA256), normalisedLines: lines)
    }

    public func parse(_ text: String, route: String = "A", inputSHA256: String, assertedBases: [LabelBasis]) -> LabelCaptureCandidate {
        let lines = Self.lines(text)
        return UKReadingGuard.apply(parser.parse(lines.joined(separator: "\n"), route: route, inputSHA256: inputSHA256, assertedBases: assertedBases),
                                    normalisedLines: lines)
    }

    /// Parser v3's unheaded shape of the normalised text, or nil when the guard would decline it.
    public func unheadedShape(_ text: String, route: String = "A", inputSHA256: String) -> NutritionLabelTextParserV3.UnheadedShape? {
        let lines = Self.lines(text)
        let normalised = lines.joined(separator: "\n")
        let candidate = parser.parse(normalised, route: route, inputSHA256: inputSHA256)
        guard UKReadingGuard.declineCode(candidate, normalisedLines: lines) == nil else { return nil }
        return parser.unheadedShape(normalised, route: route, inputSHA256: inputSHA256)
    }

    /// The normalised lines of the text, with parser v3's line endings and no-break spaces folded first.
    public static func lines(_ text: String) -> [String] {
        let folded = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\u{00A0}", with: " ")
        return UKTextNormalisation.lines(folded)
    }
}
