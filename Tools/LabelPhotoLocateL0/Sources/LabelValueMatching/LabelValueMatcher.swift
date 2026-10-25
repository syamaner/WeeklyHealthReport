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
    /// value can be assigned to its nearest one.
    public static func locate(_ queries: [Query], lines: [Line], headers: [String], rowLabels: [String],
                              subBox: SubBox) -> [Location] {
        let normalised = lines.map(Normalised.init)
        func box(_ match: Match) -> Box { subBox(match.line, match.range) ?? lines[match.line].box }
        // Each header and row label found exactly once, so a candidate value can be assigned to
        // its nearest header (by x) and its nearest row label (by y). Nearest rather than a fixed
        // band copes with tilted photos and with Vision reading labels and values as separate lines.
        func unique(_ texts: [String]) -> [String: Box] {
            var boxes: [String: Box] = [:]
            for text in Set(texts) {
                let found = occurrences(of: text, in: normalised, rule: .label)
                if found.count == 1 { boxes[Normalised(text).key] = box(found[0]) }
            }
            return boxes
        }
        let headerBoxes = unique(headers)
        let rowBoxes = unique(rowLabels)
        func nearest(_ boxes: [String: Box], to value: Box, by distance: (Box, Box) -> Double) -> String? {
            boxes.sorted { $0.key < $1.key }.min { distance($0.value, value) < distance($1.value, value) }?.key
        }
        return queries.map { query in
            let isLine = query.rowLabel == nil
            for needle in needles(query.printedText, isLine: isLine) {
                var candidates = occurrences(of: needle, in: normalised, rule: isLine ? .line : .value).map { ($0, box($0)) }
                if let label = query.rowLabel.map({ Normalised($0).key }), rowBoxes[label] != nil, rowBoxes.count > 1 {
                    candidates = candidates.filter { nearest(rowBoxes, to: $0.1) { abs($0.midY - $1.midY) } == label }
                }
                if let header = query.headerText.map({ Normalised($0).key }), headerBoxes[header] != nil, headerBoxes.count > 1 {
                    candidates = candidates.filter { nearest(headerBoxes, to: $0.1) { abs($0.midX - $1.midX) } == header }
                }
                switch candidates.count {
                case 0: continue
                case 1: return Location(id: query.id, status: .found, region: rounded(candidates[0].1))
                default: return Location(id: query.id, status: .ambiguous, region: nil)
                }
            }
            return Location(id: query.id, status: .notFound, region: nil)
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
