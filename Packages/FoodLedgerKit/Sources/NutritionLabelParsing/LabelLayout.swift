import Foundation

/// Layout precedence of parser v3 (`docs/pasted-nutrition-label-reader-v3.md` section 3.0,
/// decision 19): one closed, ordered list of pure predicates over the table body. The body
/// (the row lines left after the lines-before-the-table rules) is classified into exactly one
/// layout; a body that satisfies more than one predicate, or none, declines `layout_ambiguous`.
/// There is no protocol or plug-in per layout, and adding a layout is a new parser version.
///
/// Parser v3 accumulates across the PRs of section 8 until it is frozen (section 5.1). PR 1 listed
/// inline and stacked; PR 3 appends the flattened-line layout (3.4, `FlattenedLine`). A stacked body is read under the sequence rule and template order of 3.2 (PR 2,
/// `ParseStateV3.firstStackedDeviation`): rows before the first deviation are bound as parser v2
/// binds a row label standing alone with its values on the following lines; that row and every
/// row after it are not read.
enum LabelLayout: String, CaseIterable, Sendable {
    case inline
    case stacked
    case flattened

    /// The closed precedence list, tested in this order.
    static let precedence: [LabelLayout] = [.inline, .stacked, .flattened]

    static let ambiguousCode = "layout_ambiguous"

    /// One consumed row line of the body, as the parser saw it.
    enum Line: Equatable, Sendable {
        /// A row label with at least one value on the same line. `secondLabel` is true when a
        /// recognised row label stands after the first value (two rows on one line).
        case labelWithValues(secondLabel: Bool)
        /// A row label with no value on its line.
        case labelOnly
        /// Values with no label on their line.
        case valuesOnly
        /// A whole table on one line (3.4): at least three alias labels, each followed by a value.
        case flattened
    }

    /// Inline (parser v2's shape): each row label and its values on one line, possibly
    /// continued as v2 allows: a value-only line only ever continues a row whose own label line
    /// carried values (the kJ and kcal continuation, or v2's flagged continuation). A label line
    /// with no values may stand alone (a two-line label or a row printed without values) as
    /// long as no value-only line follows it. No line carries two row labels.
    static func isInline(_ lines: [Line]) -> Bool {
        var lastLabel: Line?
        var sawLabelWithValues = false
        for line in lines {
            switch line {
            case let .labelWithValues(secondLabel):
                if secondLabel { return false }
                sawLabelWithValues = true
                lastLabel = line
            case .labelOnly:
                lastLabel = line
            case .valuesOnly:
                guard case .labelWithValues = lastLabel else { return false }
            case .flattened:
                return false
            }
        }
        return sawLabelWithValues
    }

    /// Stacked (3.2): row labels stand on lines with no values and values stand on lines with
    /// no label.
    static func isStacked(_ lines: [Line]) -> Bool {
        !lines.contains { if case .labelWithValues = $0 { true } else { false } } && !lines.contains(.flattened)
            && lines.contains(.labelOnly) && lines.contains(.valuesOnly)
    }

    /// Flattened (3.4): exactly one flattened line; any other body line is a label with no values
    /// (a heading such as a flavour name), which binds nothing.
    static func isFlattened(_ lines: [Line]) -> Bool {
        lines.filter { $0 == .flattened }.count == 1 && lines.allSatisfy { $0 == .flattened || $0 == .labelOnly }
    }

    static func matches(_ layout: LabelLayout, _ lines: [Line]) -> Bool {
        switch layout {
        case .inline: isInline(lines)
        case .stacked: isStacked(lines)
        case .flattened: isFlattened(lines)
        }
    }

    /// The one layout the body satisfies, or nil when it satisfies more than one or none.
    static func classify(_ lines: [Line]) -> LabelLayout? {
        let matched = precedence.filter { matches($0, lines) }
        return matched.count == 1 ? matched[0] : nil
    }
}
