import Foundation
import FoodLedgerDomain

/// Part-read selection `food-document-block-selection-v1` (#508, contract section 5.2, settled in
/// docs/web-lookup-part-read-phase3-gate.md section 3). A pure rule over the blocks of a full
/// projection: it keeps every nutrition table or definition list with its context, nearest heading
/// and the first `h1`, all or nothing, then fills with JSON-LD. It never parses locators, reads a
/// host, uses a model, truncates a block or produces a value. Every value below is closed under the
/// policy identifier; changing one is a new policy version. Imports: Foundation and the domain only
/// (`check-boundaries.sh`).
public enum FoodDocumentBlockSelection {
    public static let policy = FoodDocumentPartialRead.selectionPolicy
    public static let bounds = FoodDocumentPartialRead.selectionPolicyBounds
    public static let contextBefore = 12
    public static let contextAfter = 6
    /// Equal to `FoodProposalEvidenceCatalog.maximumExcerptCharacters`; restated as a policy literal.
    public static let longContextBlockCharacters = 1_400
    public static let nutritionBlockThreshold = 3
    public static let headingKinds: Set<String> = ["h1", "h2", "h3", "h4", "h5", "h6"]
    public static let structuredDataKind = "json_ld"
    /// Latin-script terms: ASCII-folded, with no ASCII letter on either side.
    public static let latinTerms: [String] = [
        "energy", "calorie", "calories", "kcal", "kj", "protein", "proteins", "fat", "fats", "saturates", "saturated",
        "carbohydrate", "carbohydrates", "carbs", "sugar", "sugars", "fibre", "fiber", "salt", "sodium"
    ]
    /// Chinese terms: plain substrings (no word separators in Chinese text).
    public static let chineseTerms: [String] = [
        "熱量", "热量", "能量", "蛋白質", "蛋白质", "脂肪", "碳水化合物", "糖", "膳食纖維", "膳食纤维", "鈉", "钠"
    ]

    /// One block of the full projection: its kind, normalised text and structural unit key
    /// (`nil` when it belongs to no table or definition unit).
    public struct Block: Equatable, Sendable {
        public let kind: String
        public let text: String
        public let unit: String?
        public init(kind: String, text: String, unit: String?) { self.kind = kind; self.text = text; self.unit = unit }
    }

    /// The kept positions in document order, or `nil` when the page is refused (no nutrition unit,
    /// or the required set does not fit). Throws only `CancellationError`.
    public static func select(_ blocks: [Block]) throws -> [Int]? {
        try Task.checkCancellation()
        var units: [String: [Int]] = [:]
        var unitOrder: [String] = []
        for (index, block) in blocks.enumerated() {
            guard let unit = block.unit else { continue }
            if units[unit] == nil { unitOrder.append(unit) }
            units[unit, default: []].append(index)
        }
        // The nearest heading before each position, found in one pass over the page.
        var headingBefore = [Int?](repeating: nil, count: blocks.count)
        var lastHeading: Int?
        for (index, block) in blocks.enumerated() {
            headingBefore[index] = lastHeading
            if headingKinds.contains(block.kind) { lastHeading = index }
        }
        var required = Set<Int>()
        var nutritionUnits = 0
        for unit in unitOrder {
            try Task.checkCancellation()
            let members = units[unit] ?? []
            // Count matches only up to the threshold, checking cancellation as the matching runs.
            var matched = 0
            for (offset, member) in members.enumerated() where matched < nutritionBlockThreshold {
                if offset % 64 == 0 { try Task.checkCancellation() }
                if matches(blocks[member].text) { matched += 1 }
            }
            guard matched >= nutritionBlockThreshold, let first = members.first, let last = members.last else { continue }
            nutritionUnits += 1
            for index in first...last where blocks[index].kind != structuredDataKind { required.insert(index) }
            var position = first - 1
            while position >= 0, position >= first - contextBefore {
                if blocks[position].kind != structuredDataKind {
                    if blocks[position].text.count > longContextBlockCharacters { break }
                    required.insert(position)
                }
                position -= 1
            }
            position = last + 1
            while position < blocks.count, position <= last + contextAfter {
                if blocks[position].kind != structuredDataKind {
                    if blocks[position].text.count > longContextBlockCharacters { break }
                    required.insert(position)
                }
                position += 1
            }
            if let heading = headingBefore[first] { required.insert(heading) }
        }
        guard nutritionUnits > 0 else { return nil }
        if let identity = blocks.firstIndex(where: { $0.kind == "h1" }) { required.insert(identity) }
        var keptBlocks = required.count
        var keptCharacters = required.reduce(0) { $0 + blocks[$1].text.count }
        guard keptBlocks <= bounds.blocks, keptCharacters <= bounds.characters else { return nil }
        for (index, block) in blocks.enumerated() where block.kind == structuredDataKind {
            try Task.checkCancellation()
            let characters = block.text.count
            guard keptBlocks + 1 <= bounds.blocks, keptCharacters + characters <= bounds.characters else { continue }
            required.insert(index); keptBlocks += 1; keptCharacters += characters
        }
        return required.sorted()
    }

    /// True when the text holds an ASCII digit and a vocabulary term under its script's rule.
    public static func matches(_ text: String) -> Bool {
        let scalars = Array(text.unicodeScalars).map(asciiLowercased)
        guard scalars.contains(where: { (48...57).contains($0.value) }) else { return false }
        for term in latinTerms {
            let needle = Array(term.unicodeScalars)
            if contains(needle, in: scalars, isolated: true) { return true }
        }
        for term in chineseTerms where contains(Array(term.unicodeScalars), in: scalars, isolated: false) { return true }
        return false
    }

    private static func asciiLowercased(_ scalar: Unicode.Scalar) -> Unicode.Scalar {
        (65...90).contains(scalar.value) ? Unicode.Scalar(scalar.value + 32)! : scalar
    }

    private static func isASCIILetter(_ scalar: Unicode.Scalar) -> Bool {
        (97...122).contains(scalar.value) || (65...90).contains(scalar.value)
    }

    private static func contains(_ needle: [Unicode.Scalar], in haystack: [Unicode.Scalar], isolated: Bool) -> Bool {
        guard !needle.isEmpty, haystack.count >= needle.count else { return false }
        for start in 0...(haystack.count - needle.count)
        where needle.indices.allSatisfy({ haystack[start + $0] == needle[$0] }) {
            guard isolated else { return true }
            let before = start == 0 || !isASCIILetter(haystack[start - 1])
            let afterIndex = start + needle.count
            let after = afterIndex == haystack.count || !isASCIILetter(haystack[afterIndex])
            if before && after { return true }
        }
        return false
    }
}
