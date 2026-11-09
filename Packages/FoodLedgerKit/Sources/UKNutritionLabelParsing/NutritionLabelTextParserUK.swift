import Foundation
import NutritionLabelParsing

/// The UK English reader (`docs/pasted-nutrition-label-uk-english-v2-p1.md`):
/// `nutrition-label-text-parser-uk-v3` is the language check on the pasted text, region rules S1
/// to S7 (run S2, S3, S1, S7, S6, S5, S4), normalisation rules N1 to N7, the frozen parser v3 through its public API, guard rules
/// G1 to G4 and the set-aside report. uk-v1 and uk-v2, never admitted or stored, are retired. It
/// mirrors parser v3's three entry points; `inputSHA256` is always the hash of the pasted text,
/// never of the kept or normalised one. Meant for English text: the reader adapter sends every
/// other language to the pinned reader, and a text that is not English passes through unchanged.
public struct NutritionLabelTextParserUK: Sendable {
    public static let version = "nutrition-label-text-parser-uk-v3"

    private let parser = NutritionLabelTextParserV3()

    public init() {}

    /// The stages' output for one pasted text.
    public struct Prepared: Equatable, Sendable {
        public let english: Bool
        public let region: UKRegion
        public let lines: [String]
        /// When N7 fired: the values its row lines hold after normalisation, duplicates kept.
        public let n7Pairs: Int?

        var text: String { lines.joined(separator: "\n") }
        var setAsideTexts: [String] { region.setAside.map(\.text) }
    }

    public func parse(_ text: String, route: String = "A", inputSHA256: String) -> LabelCaptureCandidate {
        let prepared = Self.prepare(text)
        if let code = prepared.region.declineCode { return Self.declined(route, inputSHA256, code) }
        return Self.finish(parser.parse(prepared.text, route: route, inputSHA256: inputSHA256), prepared)
    }

    public func parse(_ text: String, route: String = "A", inputSHA256: String, assertedBases: [LabelBasis]) -> LabelCaptureCandidate {
        let prepared = Self.prepare(text)
        if let code = prepared.region.declineCode { return Self.declined(route, inputSHA256, code) }
        return Self.finish(parser.parse(prepared.text, route: route, inputSHA256: inputSHA256, assertedBases: assertedBases), prepared)
    }

    /// Parser v3's unheaded shape of the prepared text, or nil when the region stage or the guard
    /// would decline it.
    public func unheadedShape(_ text: String, route: String = "A", inputSHA256: String) -> NutritionLabelTextParserV3.UnheadedShape? {
        let prepared = Self.prepare(text)
        guard prepared.region.declineCode == nil else { return nil }
        let candidate = parser.parse(prepared.text, route: route, inputSHA256: inputSHA256)
        guard UKReadingGuard.declineCode(candidate, normalisedLines: prepared.lines, setAside: prepared.setAsideTexts,
                                         n7Pairs: prepared.n7Pairs) == nil else { return nil }
        return parser.unheadedShape(prepared.text, route: route, inputSHA256: inputSHA256)
    }

    /// The set-aside list for `text`, for the harness and, from P5, Developer tools.
    public func setAside(_ text: String) -> [UKSetAsideEntry] {
        Self.prepare(text).region.setAside
    }

    /// The normalised lines of the text, after the region stage (compatibility with uk-v2's callers).
    public static func lines(_ text: String) -> [String] {
        prepare(text).lines
    }

    /// Folds parser v3's line endings and no-break spaces, decides the language once on the pasted
    /// text, then runs the region stage and normalisation on English text only.
    public static func prepare(_ text: String) -> Prepared {
        let folded = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\u{00A0}", with: " ")
        let foldedLines = folded.components(separatedBy: "\n")
        let english = NutritionLabelTextParserV3().parse(folded, inputSHA256: "").language == .english
        guard english else {
            return Prepared(english: false, region: UKRegion(kept: foldedLines, setAside: [], declineCode: nil, reportedRows: []),
                            lines: foldedLines, n7Pairs: nil)
        }
        let region = UKTableRegion.apply(foldedLines)
        let normalised = UKTextNormalisation.lines(region.kept, english: true)
        // G4 (b) counts, with duplicates, the values N7's row lines hold after normalisation (a kJ
        // and kcal pair cell is two; a marker is one), to compare with the cells parser v3 bound
        // plus its unread rows.
        let values = normalised.n7Pairs.map { _ in
            normalised.lines.filter { $0.contains("\t") }.dropFirst().reduce(0) { total, line in
                let cell = line.components(separatedBy: "\t").dropFirst().joined(separator: "\t")
                return total + max(1, UKTextNormalisation.value.matches(cell).count)
            }
        }
        return Prepared(english: true, region: region, lines: normalised.lines, n7Pairs: values)
    }

    static func declined(_ route: String, _ inputSHA256: String, _ code: String) -> LabelCaptureCandidate {
        .declined(route: route, inputSHA256: inputSHA256, language: .english, reasons: [code])
    }

    static func finish(_ candidate: LabelCaptureCandidate, _ prepared: Prepared) -> LabelCaptureCandidate {
        let guarded = UKReadingGuard.apply(candidate, normalisedLines: prepared.lines, setAside: prepared.setAsideTexts,
                                           n7Pairs: prepared.n7Pairs)
        return UKSetAsideReport.apply(guarded, reportedRows: prepared.region.reportedRows)
    }
}

/// The set-aside report (`docs/pasted-nutrition-label-uk-english-v2-p1.md` section 2): after the
/// guard passes, one `row_not_read: uk_set_aside: <printed label>` warning per row S2 set aside,
/// so the person sees them under "Printed but not read". Never runs on a declined candidate. Like
/// any parser v3 warning, a reported row means the candidate would not mark ready; no other field
/// changes.
public enum UKSetAsideReport {
    public static let reason = "uk_set_aside"

    public static func apply(_ candidate: LabelCaptureCandidate, reportedRows: [String]) -> LabelCaptureCandidate {
        guard !candidate.declined, !reportedRows.isEmpty else { return candidate }
        var out = candidate
        out.warnings += reportedRows.map { "row_not_read: \(reason): \($0)" }
        out.wouldMarkReady = false
        return out
    }
}
