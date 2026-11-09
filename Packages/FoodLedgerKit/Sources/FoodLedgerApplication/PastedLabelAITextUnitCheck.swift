import Foundation

/// The unit rule of `pasted-label-ai-text-mapping-v4` (unchanged from v1; v2 changes only the value
/// grammar, revision 10, v3 the not-declared markers, revision 14, and v4 the star markers, revision 15) (docs/pasted-label-ai-text-v1.md 4.2, D10
/// and D16): the model's unit for a bare number is accepted only when the sent text states that
/// unit for the values. A unit is stated by a unit-only token (a unit of the closed list that
/// starts and ends at a token boundary, is not part of a value token, and has no digit just
/// before it past spaces):
/// - in the row's label: the located label and the rest of its line up to the first value token
///   (`Fat (g) 5 2`, `Energy kJ/kcal`); or
/// - in the column's header: the located header text (`(g)`, `g`, `mg`).
/// A number with a unit in a header (`per 100 g`, `100g`, `per 30 g serving`) is the basis
/// quantity, a value token, and never states a unit (D16). When the row's label states any unit,
/// the model's unit must be one of the row's; only a row that states none takes the header's.
/// The check never supplies a unit. Pure and deterministic.
public enum PastedLabelAITextUnitCheck {
    /// The mapping version whose unit rule this is.
    public static let mappingVersion = "pasted-label-ai-text-mapping-v4"

    public enum Outcome: String, Equatable, Sendable, Codable, CaseIterable {
        /// The printed value carries its own unit, and the model's unit (if any) is the same unit.
        case printed
        /// A bare number whose unit the row's label states.
        case statedInRowLabel = "stated_in_row_label"
        /// A bare number whose unit the column's header states.
        case statedInHeader = "stated_in_header"
        /// A bare number whose model unit the text does not state for the values.
        case notStated = "not_stated"
        /// The model's unit differs from the unit printed with the value.
        case conflict
        /// A bare number with no model unit. It must never become a value: the mapping leaves it
        /// unread (a not-read cell, never zero, review F9) and puts a blocking `unit_not_stated` item
        /// on that cell so the user is prompted to enter it (A2 gate finding 3). `needsAttention`
        /// stays false here because no unit is checked; the mapping adds the item.
        case missing
        /// The printed text is not one value token (`unknown`, `trace`): no unit to check.
        case notAValue = "not_a_value"

        /// `unit_not_stated` under `pasted-label-ai-text-attention-v1`.
        public var needsAttention: Bool { self == .notStated || self == .conflict }
    }

    /// The canonical units the unit-only tokens of `range` state, in text order, without repeats.
    public static func statedUnits(in scan: PastedLabelTextScan, range: Range<Int>) -> [String] {
        var out: [String] = []
        var index = range.lowerBound
        while index < range.upperBound {
            guard let line = scan.line(containing: index) else { break }
            let limit = min(range.upperBound, line.end)
            var matched = false
            if index < limit, PastedLabelTextScan.boundaryBefore(scan.scalars, index, line: line),
               !scan.tokens.contains(where: { $0.range.contains(index) }), !digitBefore(scan, index, line: line) {
                for unit in PastedLabelAITextValueGrammar.unitsLongestFirst
                where PastedLabelTextScan.starts(scan.scalars, at: index, with: unit, limit: limit) {
                    let end = index + unit.unicodeScalars.count
                    guard PastedLabelTextScan.boundaryAfter(scan.scalars, end, line: line),
                          let canonical = PastedLabelAITextValueGrammar.canonicalUnit(unit) else { continue }
                    if !out.contains(canonical) { out.append(canonical) }
                    index = end
                    matched = true
                    break
                }
            }
            if !matched { index += 1 }
        }
        return out
    }

    /// Whether a digit sits just before `index`, past spaces, on its line (review F3): `per100 g`
    /// and `每100 公克` are basis quantities even where the number is not a value token.
    static func digitBefore(_ scan: PastedLabelTextScan, _ index: Int, line: PastedLabelTextScan.Line) -> Bool {
        var position = index - 1
        // Spaces and opening brackets are skipped, so `per 100 g`, `per100 g` and `Per 100 (g)` all read
        // the `g` as the basis quantity's unit, never as a unit stated for the values (D16).
        let openers: Set<Unicode.Scalar> = ["(", "[", "\u{FF08}", "\u{FF3B}"]
        while position >= line.start,
              scan.scalars[position].properties.isWhitespace || openers.contains(scan.scalars[position]) { position -= 1 }
        return position >= line.start && PastedLabelAITextValueGrammar.isDigit(scan.scalars[position])
    }

    /// The row label's region: the located label and the rest of its line up to the first value token.
    public static func rowLabelRegion(in scan: PastedLabelTextScan, label: Range<Int>) -> Range<Int> {
        guard let line = scan.line(containing: label.lowerBound) else { return label }
        let firstToken = scan.tokens.first { $0.start >= label.upperBound && $0.start < line.end }?.start ?? line.end
        return label.lowerBound..<max(label.upperBound, firstToken)
    }

    /// The outcome for one value: its printed text, the model's unit member, and the located row
    /// label and header spans (nil when not located, which states nothing).
    public static func check(scan: PastedLabelTextScan, printedValue: String, modelUnit: String?,
                             rowLabel: Range<Int>?, header: Range<Int>?) -> Outcome {
        let valueScan = PastedLabelTextScan(printedValue)
        guard valueScan.tokens.count == 1, let token = valueScan.tokens.first, token.start == 0,
              token.end == valueScan.scalars.count else { return .notAValue }
        let model = modelUnit.flatMap { $0.isEmpty ? nil : $0 }
        if let printed = token.canonicalUnit {
            guard let model else { return .printed }
            return PastedLabelAITextValueGrammar.canonicalUnit(model) == printed ? .printed : .conflict
        }
        guard let model else { return .missing }
        guard let canonical = PastedLabelAITextValueGrammar.canonicalUnit(model) else { return .notStated }
        let rowUnits = rowLabel.map { statedUnits(in: scan, range: rowLabelRegion(in: scan, label: $0)) } ?? []
        if !rowUnits.isEmpty { return rowUnits.contains(canonical) ? .statedInRowLabel : .notStated }
        let headerUnits = header.map { statedUnits(in: scan, range: $0) } ?? []
        return headerUnits.contains(canonical) ? .statedInHeader : .notStated
    }

    /// The outcome for every value of a located answer, in the locator's value order. `units`
    /// holds the model's unit member per row and value (nil where it is absent).
    public static func check(text: String, rows: [PastedLabelTextLocator.Row],
                             units: [[String?]], located: PastedLabelTextLocator.Result) -> [Outcome] {
        let scan = PastedLabelTextScan(text)
        let headerSpans = Dictionary(located.headers.compactMap { result in result.status.range.map { (result.id, $0) } },
                                     uniquingKeysWith: { first, _ in first })
        return located.values.map { value in
            let row = rows[value.rowIndex]
            let unit = value.rowIndex < units.count && value.valueIndex < units[value.rowIndex].count ? units[value.rowIndex][value.valueIndex] : nil
            let label = located.rows[value.rowIndex].label.range
            return check(scan: scan, printedValue: row.values[value.valueIndex].printedText, modelUnit: unit, rowLabel: label,
                         header: value.attention.contains(.headerNotLocated) ? nil : headerSpans[value.headerID])
        }
    }
}
