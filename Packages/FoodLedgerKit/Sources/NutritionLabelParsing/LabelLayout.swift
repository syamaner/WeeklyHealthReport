import Foundation

/// Layout precedence of parser v3 (`docs/pasted-nutrition-label-reader-v3.md` section 3.0,
/// decision 19): one closed, ordered list of pure predicates over the table body. The body
/// (the row lines left after the lines-before-the-table rules) is classified into exactly one
/// layout; a body that satisfies more than one predicate, or none, declines `layout_ambiguous`.
/// There is no protocol or plug-in per layout, and adding a layout is a new parser version.
///
/// Parser v3 accumulates across the PRs of section 8 until it is frozen (section 5.1). PR 1 lists
/// inline and stacked; the flattened-line layout (3.4) is appended by the PR that builds its
/// reader. Until PR 2 adds the stacked sequence rule (3.2), a stacked body is bound exactly as
/// parser v2 binds a row label standing alone with its values on the following lines.
enum LabelLayout: String, CaseIterable, Sendable {
    case inline
    case stacked

    /// The closed precedence list, tested in this order.
    static let precedence: [LabelLayout] = [.inline, .stacked]

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
            }
        }
        return sawLabelWithValues
    }

    /// Stacked (3.2): row labels stand on lines with no values and values stand on lines with
    /// no label.
    static func isStacked(_ lines: [Line]) -> Bool {
        !lines.contains { if case .labelWithValues = $0 { true } else { false } }
            && lines.contains(.labelOnly) && lines.contains(.valuesOnly)
    }

    static func matches(_ layout: LabelLayout, _ lines: [Line]) -> Bool {
        switch layout {
        case .inline: isInline(lines)
        case .stacked: isStacked(lines)
        }
    }

    /// The one layout the body satisfies, or nil when it satisfies more than one or none.
    static func classify(_ lines: [Line]) -> LabelLayout? {
        let matched = precedence.filter { matches($0, lines) }
        return matched.count == 1 ? matched[0] : nil
    }
}
