import Foundation

/// `label-photo-vision-locate-v1` matcher (docs/label-photo-ai-prefill-v1.md section 6.1).
///
/// Pure: Foundation only, no Vision, image, clock or network. The Vision adapter supplies the
/// recognised lines and a function that returns the box of a substring of one line; the matcher
/// decides, for each printed value the model returned, whether it appears exactly once on the
/// photo in its row label's line band and its header's column. Being found is corroboration,
/// never verification. L0 measures this file; L1 carries it into the package unchanged and pins
/// it by SHA-256.
public enum LabelValueMatcher {
    public static let version = "label-photo-vision-locate-v1"
    /// A value belongs to its row label only within this share of the local label spacing.
    public static let rowOffsetLimit = 1.0 / 3.0

    /// A normalised rectangle in image space (0...1 on both axes; Vision's origin, bottom left).
    public struct Box: Equatable, Sendable, Codable {
        public let x: Double, y: Double, width: Double, height: Double
        public init(x: Double, y: Double, width: Double, height: Double) {
            self.x = x; self.y = y; self.width = width; self.height = height
        }
        public var midX: Double { x + width / 2 }
        public var midY: Double { y + height / 2 }
    }

    /// One recognised line of text and its box.
    public struct Line: Equatable, Sendable {
        public let text: String
        public let box: Box
        public init(text: String, box: Box) { self.text = text; self.box = box }
    }

    /// One value to locate: its row label, its column header's printed text and its own printed
    /// text, all as the model returned them. Serving lines have no row label or header.
    public struct Query: Equatable, Sendable {
        public let id: String
        public let rowLabel: String?
        public let headerText: String?
        public let printedText: String
        public init(id: String, rowLabel: String?, headerText: String?, printedText: String) {
            self.id = id; self.rowLabel = rowLabel; self.headerText = headerText; self.printedText = printedText
        }
    }

    public enum Status: String, Sendable, Codable { case found, notFound = "not_found", ambiguous }

    public struct Location: Equatable, Sendable {
        public let id: String
        public let status: Status
        public let region: Box?
    }

    /// The box of `range` (original indices) within `lines[index]`, or the line's box.
    public typealias SubBox = (_ index: Int, _ range: Range<String.Index>) -> Box?

    /// `headers` and `rowLabels` are every header's and row label's printed text in the table, so a
    /// value can be assigned to its nearest one; `columnCount` is the number of value columns the
    /// reading has (headers with or without printed text).
    ///
    /// Precondition for the order pass: `queries` list each column's values in the table's printed
    /// row order, top to bottom, as the reading's rows are. The pass checks this against the row
    /// labels found on the photo and places nothing when they disagree or cannot be checked.
    public static func locate(_ queries: [Query], lines: [Line], headers: [String], rowLabels: [String], columnCount: Int,
                              subBox: SubBox) -> [Location] {
        let normalised = lines.map(Normalised.init)
        func box(_ match: Match) -> Box { subBox(match.line, match.range) ?? lines[match.line].box }
        // Each header and row label found exactly once, so a candidate value can be assigned to
        // its nearest header (by x) and its nearest row label (by y). Nearest rather than a fixed
        // band copes with tilted photos and with Vision reading labels and values as separate lines.
        // Headers are found by plain containment, because they are often printed on one line
        // ("每份 每100公克"); a row label may not follow a letter or ideograph.
        func unique(_ texts: [String], rule: Rule) -> [String: Box] {
            var boxes: [String: Box] = [:]
            for text in Set(texts) {
                let found = occurrences(of: text, in: normalised, rule: rule)
                if found.count == 1 { boxes[Normalised(text).key] = box(found[0]) }
            }
            return boxes
        }
        let headerBoxes = unique(headers, rule: .line)
        let rowBoxes = unique(rowLabels, rule: .label)
        func nearest(_ boxes: [String: Box], to value: Box, by distance: (Box, Box) -> Double) -> String? {
            boxes.sorted { $0.key < $1.key }.min { distance($0.value, value) < distance($1.value, value) }?.key
        }
        func inHeader(_ query: Query, _ value: Box) -> Bool {
            guard let header = query.headerText.map({ Normalised($0).key }), headerBoxes[header] != nil,
                  headerBoxes.count > 1 else { return true }
            return nearest(headerBoxes, to: value) { abs($0.midX - $1.midX) } == header
        }

        // Row geometry. A value belongs to a row label only when that label is its nearest and its
        // vertical offset from the label is under `rowOffsetLimit` of the local spacing (the gap to
        // the nearer neighbouring label; the one neighbour at the table's edges). A value nearest
        // the label but further off has drifted: it could be this row's or the neighbour's, so it
        // makes the value ambiguous, never found. 1/3 is chosen so that a value drifted by more
        // than a third of a row is never accepted on either row (a drift of 0.05 at a spacing of
        // 0.08 sits 0.375 of a row from the neighbour, which "about 0.4" would have accepted).
        let rowsTopDown = rowBoxes.sorted { $0.value.midY > $1.value.midY }
        func spacing(_ label: String) -> Double? {
            guard let index = rowsTopDown.firstIndex(where: { $0.key == label }), rowsTopDown.count > 1 else { return nil }
            var gaps: [Double] = []
            if index > 0 { gaps.append(rowsTopDown[index - 1].value.midY - rowsTopDown[index].value.midY) }
            if index + 1 < rowsTopDown.count { gaps.append(rowsTopDown[index].value.midY - rowsTopDown[index + 1].value.midY) }
            return gaps.min()
        }
        enum RowFit { case other, near, drifted }
        func rowFit(_ label: String, _ value: Box) -> RowFit {
            guard let own = rowBoxes[label], let gap = spacing(label),
                  nearest(rowBoxes, to: value, by: { abs($0.midY - $1.midY) }) == label else { return .other }
            return abs(value.midY - own.midY) < rowOffsetLimit * gap ? .near : .drifted
        }
        func rowKey(_ query: Query) -> String? {
            guard let label = query.rowLabel.map({ Normalised($0).key }), rowBoxes[label] != nil, rowBoxes.count > 1 else { return nil }
            return label
        }
        // Number tokens (a run of digits and points) on a row, outside its label, for the unlisted
        // column rule: with one value column, a row holding more numbers than the reading lists for
        // it has a second column the reading does not know, so a match there is not trusted.
        func numberTokens(onRow label: String) -> [Box] {
            guard let own = rowBoxes[label] else { return [] }
            var boxes: [Box] = []
            for (number, line) in normalised.enumerated() {
                var start: Int?
                for position in 0...line.characters.count {
                    let digit = position < line.characters.count && (isDigit(line.characters[position]) || line.characters[position] == ".")
                    if digit, start == nil { start = position }
                    if !digit, let first = start {
                        let token = box(Match(line: number, range: line.origin[first].lowerBound..<line.origin[position - 1].upperBound))
                        let insideLabel = token.midX >= own.x && token.midX <= own.x + own.width
                        if !insideLabel, rowFit(label, token) == .near { boxes.append(token) }
                        start = nil
                    }
                }
            }
            return boxes
        }
        let listedPerRow = Dictionary(grouping: queries.compactMap(rowKey), by: { $0 }).mapValues(\.count)

        // First pass: the row and column filters, trying each needle in turn. An ambiguous result
        // keeps its candidates (after both filters) for the order pass.
        struct First { let location: Location; let candidates: [Box] }
        let first: [First] = queries.map { query in
            let isLine = query.rowLabel == nil
            for needle in needles(query.printedText, isLine: isLine) {
                let candidates = occurrences(of: needle, in: normalised, rule: isLine ? .line : .value).map { box($0) }
                    .filter { inHeader(query, $0) }
                if isLine {
                    // Serving lines carry their own words; no row to confirm.
                    switch candidates.count {
                    case 0: continue
                    case 1: return First(location: Location(id: query.id, status: .found, region: rounded(candidates[0])), candidates: candidates)
                    default: return First(location: Location(id: query.id, status: .ambiguous, region: nil), candidates: candidates)
                    }
                }
                guard let label = rowKey(query), spacing(label) != nil else {
                    // The value's own row cannot be confirmed: its label was not located exactly once
                    // (or is the only label located). It is never found. Candidates near another
                    // located label belong to that row and are dropped; any candidate at all makes
                    // the value ambiguous (the order pass then needs a located label, so it stays so).
                    if candidates.isEmpty { continue }
                    let own = query.rowLabel.map { Normalised($0).key }
                    let elsewhere = candidates.filter { candidate in
                        rowBoxes.keys.contains { $0 != own && rowFit($0, candidate) == .near }
                    }
                    let remaining = candidates.filter { !elsewhere.contains($0) }
                    return First(location: Location(id: query.id, status: .ambiguous, region: nil), candidates: remaining)
                }
                let near = candidates.filter { rowFit(label, $0) == .near }
                let drifted = candidates.filter { rowFit(label, $0) == .drifted }
                if near.isEmpty && drifted.isEmpty { continue }
                let unlisted = columnCount <= 1 && numberTokens(onRow: label).count > (listedPerRow[label] ?? 0)
                if near.count == 1 && drifted.isEmpty && !unlisted {
                    return First(location: Location(id: query.id, status: .found, region: rounded(near[0])), candidates: near)
                }
                return First(location: Location(id: query.id, status: .ambiguous, region: nil), candidates: near + drifted)
            }
            return First(location: Location(id: query.id, status: .notFound, region: nil), candidates: [])
        }

        // Second pass, order within the column. It may only turn a first-pass **ambiguous** value
        // into found; it never changes a found or not found value. A value whose text repeats in
        // its column is placed by rank only when all of these hold:
        // - its column is known: the reading has one value column, or the headers separate them;
        // - the column holds exactly as many occurrences of that text as the reading has values
        //   with that text in that column;
        // - every one of those values has its row label found exactly once, and the labels run top
        //   to bottom in the queries' order (the precondition above);
        // - the occurrence of the value's rank is one of its own first-pass candidates, within the
        //   row offset limit of its own label, on a row with no unlisted number.
        // Otherwise the value stays ambiguous.
        func columnKey(_ query: Query) -> String? {
            if columnCount <= 1 { return "" }
            guard headerBoxes.count > 1, let header = query.headerText.map({ Normalised($0).key }),
                  headerBoxes[header] != nil else { return nil }
            return header
        }
        return queries.enumerated().map { index, query in
            let result = first[index]
            guard result.location.status == .ambiguous, query.rowLabel != nil, let key = columnKey(query) else { return result.location }
            let needle = Normalised(query.printedText).key
            let expected = queries.indices.filter { other in
                queries[other].rowLabel != nil && columnKey(queries[other]) == key
                    && Normalised(queries[other].printedText).key == needle
            }
            let labelBoxes = expected.compactMap { queries[$0].rowLabel.flatMap { rowBoxes[Normalised($0).key] } }
            let inOrder = labelBoxes.count == expected.count && zip(labelBoxes, labelBoxes.dropFirst()).allSatisfy { $0.midY > $1.midY }
            let observed = occurrences(of: needle, in: normalised, rule: .value).map { box($0) }
                .filter { inHeader(query, $0) }
                .sorted { $0.midY > $1.midY }
            guard inOrder, expected.count > 1, expected.count == observed.count, let rank = expected.firstIndex(of: index),
                  result.candidates.contains(observed[rank]), let label = rowKey(query), rowFit(label, observed[rank]) == .near,
                  !(columnCount <= 1 && numberTokens(onRow: label).count > (listedPerRow[label] ?? 0)) else { return result.location }
            return Location(id: query.id, status: .found, region: rounded(observed[rank]))
        }
    }

    /// The texts tried in order: the whole printed text; then, when Vision splits a line, the
    /// part from the first digit or comparator ("每一份量 185 公克" to "185公克"); then, for a
    /// value only, its number alone ("5.0 公克" to "5.0", when the unit was read as its own line).
    /// The first text with any candidate decides.
    static func needles(_ printed: String, isLine: Bool) -> [String] {
        let text = Normalised(printed).key
        var found = [text]
        if let start = text.firstIndex(where: { isDigit($0) || "<≤≦>".contains($0) }) {
            found.append(String(text[start...]))
            if !isLine {
                let number = text[start...].prefix { isDigit($0) || $0 == "." || "<≤≦>".contains($0) }
                found.append(String(number))
            }
        }
        var unique: [String] = []
        for needle in found where !needle.isEmpty && !unique.contains(needle) { unique.append(needle) }
        return unique
    }

    // MARK: Normalisation and occurrence rules

    /// NFKC (full-width digits and letters to half-width), whitespace removed, lower case, with a
    /// map from each normalised character back to the original indices.
    struct Normalised {
        let characters: [Character]
        let origin: [Range<String.Index>]
        init(_ line: Line) { self.init(line.text) }
        var key: String { String(characters) }
        init(_ text: String) {
            var characters: [Character] = [], origin: [Range<String.Index>] = []
            var index = text.startIndex
            while index < text.endIndex {
                let next = text.index(after: index)
                for character in String(text[index..<next]).precomposedStringWithCompatibilityMapping.lowercased()
                where !character.isWhitespace {
                    characters.append(character); origin.append(index..<next)
                }
                index = next
            }
            self.characters = characters; self.origin = origin
        }
    }

    struct Match { let line: Int; let range: Range<String.Index> }

    enum Rule {
        /// A value: not preceded or followed by a digit or decimal point ("5公克" is not in "15公克").
        case value
        /// A row label or header: not preceded by a letter or ideograph ("脂肪" is not in "飽和脂肪").
        case label
        /// A serving line: plain containment.
        case line
    }

    static func occurrences(of needle: String, in lines: [Normalised], rule: Rule) -> [Match] {
        let pattern = Normalised(needle).characters
        guard !pattern.isEmpty else { return [] }
        var found: [Match] = []
        for (number, line) in lines.enumerated() where line.characters.count >= pattern.count {
            for start in 0...(line.characters.count - pattern.count)
            where Array(line.characters[start..<(start + pattern.count)]) == pattern {
                let before = start > 0 ? line.characters[start - 1] : nil
                let after = start + pattern.count < line.characters.count ? line.characters[start + pattern.count] : nil
                guard admits(rule, before: before, after: after) else { continue }
                found.append(Match(line: number, range: line.origin[start].lowerBound..<line.origin[start + pattern.count - 1].upperBound))
            }
        }
        return found
    }

    static func admits(_ rule: Rule, before: Character?, after: Character?) -> Bool {
        func numeric(_ character: Character?) -> Bool { character.map { isDigit($0) || $0 == "." } ?? false }
        switch rule {
        case .value: return !numeric(before) && !numeric(after)
        case .label: return !(before.map { $0.isLetter } ?? false)
        case .line: return true
        }
    }

    /// ASCII digits only (after NFKC): Han numerals such as 一 are words on a label, not values.
    static func isDigit(_ character: Character) -> Bool { character.isASCII && character.isNumber }

    static func rounded(_ box: Box) -> Box {
        func four(_ value: Double) -> Double { (min(max(value, 0), 1) * 10_000).rounded() / 10_000 }
        return Box(x: four(box.x), y: four(box.y), width: four(box.width), height: four(box.height))
    }
}
