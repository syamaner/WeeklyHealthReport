import Foundation

/// The frozen data tables behind decline gate v2 (`docs/pasted-nutrition-label-v1.md` section 8.2).
///
/// Gate v2 is written in Python. It classifies Han characters with Python's GB 2312 and CP950
/// codecs and matches supplement markers with Python `re`, neither of which Swift has. Both are
/// frozen as resource files generated once by
/// `Tools/NutritionLabelCaptureEvaluation/export_swift_parity.py tables`, and this type only
/// reads them. It never hashes them: the SHA-256 of each file is recorded in
/// `LabelDeclineGate`'s version block and checked by the package tests.
struct LabelGateTables: Sendable {
    /// Simplified-only code points (in GB 2312, not in CP950, not a shared variant) over `HAN_RANGES`.
    let simplifiedOnly: Set<UInt32>
    /// Python `re` `\s`.
    let space: Set<UInt32>
    /// For each pattern character: every scalar Python `re.IGNORECASE` matches it with, and that
    /// scalar's Python `str.lower()`.
    let folds: [UInt32: [UInt32: [UInt32]]]
    /// Python `re` `\w` (`str.isalnum()` or `_`), as sorted closed ranges.
    let wordRanges: [ClosedRange<UInt32>]
    /// The Python pattern the classes were generated for.
    let markerPattern: String

    static let shared: LabelGateTables = {
        do {
            return try LabelGateTables(
                simplifiedOnlyText: resourceText(LabelDeclineGate.simplifiedOnlyTableResource),
                markerClassesText: resourceText(LabelDeclineGate.markerClassesTableResource)
            )
        } catch {
            // The tables are bundled with the target; a missing or malformed table is a build defect.
            fatalError("Decline gate v2 tables are unreadable: \(error)")
        }
    }()

    enum TableError: Error, Equatable {
        case missingResource(String)
        case malformed(String)
    }

    static func resourceData(_ name: String) throws -> Data {
        let parts = name.split(separator: ".", maxSplits: 1).map(String.init)
        guard parts.count == 2,
              let url = Bundle.module.url(forResource: parts[0], withExtension: parts[1], subdirectory: "Resources")
                ?? Bundle.module.url(forResource: parts[0], withExtension: parts[1]),
              let data = try? Data(contentsOf: url) else {
            throw TableError.missingResource(name)
        }
        return data
    }

    static func resourceText(_ name: String) throws -> String {
        guard let text = String(data: try resourceData(name), encoding: .utf8) else { throw TableError.malformed(name) }
        return text
    }

    init(simplifiedOnlyText: String, markerClassesText: String) throws {
        var simplified = Set<UInt32>()
        for line in simplifiedOnlyText.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let value = UInt32(line, radix: 16) else { throw TableError.malformed("simplified-only line \(line)") }
            simplified.insert(value)
        }
        var space = Set<UInt32>()
        var folds: [UInt32: [UInt32: [UInt32]]] = [:]
        var words: [ClosedRange<UInt32>] = []
        var pattern: String?
        for line in markerClassesText.split(separator: "\n", omittingEmptySubsequences: true) {
            if line.hasPrefix("pattern ") {
                pattern = String(line.dropFirst("pattern ".count))
                continue
            }
            let fields = line.split(separator: " ").map(String.init)
            switch fields.first {
            case "space":
                for field in fields.dropFirst() {
                    guard let value = UInt32(field, radix: 16) else { throw TableError.malformed("space \(field)") }
                    space.insert(value)
                }
            case "fold":
                guard fields.count >= 2, let key = UInt32(fields[1], radix: 16) else { throw TableError.malformed(String(line)) }
                var map: [UInt32: [UInt32]] = [:]
                for entry in fields.dropFirst(2) {
                    let halves = entry.split(separator: ":").map(String.init)
                    guard halves.count == 2, let from = UInt32(halves[0], radix: 16) else { throw TableError.malformed(entry) }
                    let lowered = try halves[1].split(separator: ".").map { piece -> UInt32 in
                        guard let value = UInt32(piece, radix: 16) else { throw TableError.malformed(entry) }
                        return value
                    }
                    map[from] = lowered
                }
                folds[key] = map
            case "word":
                guard fields.count == 3, let low = UInt32(fields[1], radix: 16), let high = UInt32(fields[2], radix: 16), low <= high else {
                    throw TableError.malformed(String(line))
                }
                words.append(low...high)
            default:
                continue
            }
        }
        guard let pattern, !space.isEmpty, !folds.isEmpty, !words.isEmpty else { throw TableError.malformed("marker classes are incomplete") }
        self.simplifiedOnly = simplified
        self.space = space
        self.folds = folds
        self.wordRanges = words.sorted { $0.lowerBound < $1.lowerBound }
        self.markerPattern = pattern
    }

    func isWord(_ value: UInt32) -> Bool {
        var low = 0
        var high = wordRanges.count - 1
        while low <= high {
            let middle = (low + high) / 2
            let range = wordRanges[middle]
            if value < range.lowerBound {
                high = middle - 1
            } else if value > range.upperBound {
                low = middle + 1
            } else {
                return true
            }
        }
        return false
    }
}

/// Gate v2's supplement-marker pattern, matched with Python `re` semantics:
/// `food\s+supplement|dietary\s+supplement|supplement\s+facts|\bsoft\s?gels?\b|\bcaplets?\b|营养补充|營養補充`
/// with `re.IGNORECASE`, over Unicode scalars.
///
/// `NSRegularExpression` (ICU) differs from Python here: ICU's `\s` leaves out U+000B, U+001C to
/// U+001F and U+0085, ICU's `\w` counts combining marks as word characters while Python's does not
/// (and Python counts `²` and other numeric characters), and ICU's case folding matches different
/// characters (Python matches `ſ` with `s` and `İ` and `ı` with `i`). This matcher reads Python's
/// own classes from `LabelGateTables` and backtracks exactly like Python over the closed pattern,
/// so it agrees with gate v2 on every input.
struct SupplementMarkerMatcher: Sendable {
    enum Token: Sendable {
        case boundary
        case literal([UInt32])
        case spaces(minimum: Int, maximum: Int?)
        case optional(UInt32)
    }

    static let pattern = #"food\s+supplement|dietary\s+supplement|supplement\s+facts|\bsoft\s?gels?\b|\bcaplets?\b|营养补充|營養補充"#

    static let alternatives: [[Token]] = [
        [.literal(scalars("food")), .spaces(minimum: 1, maximum: nil), .literal(scalars("supplement"))],
        [.literal(scalars("dietary")), .spaces(minimum: 1, maximum: nil), .literal(scalars("supplement"))],
        [.literal(scalars("supplement")), .spaces(minimum: 1, maximum: nil), .literal(scalars("facts"))],
        [.boundary, .literal(scalars("soft")), .spaces(minimum: 0, maximum: 1), .literal(scalars("gel")), .optional(0x73), .boundary],
        [.boundary, .literal(scalars("caplet")), .optional(0x73), .boundary],
        [.literal(scalars("营养补充"))],
        [.literal(scalars("營養補充"))],
    ]

    let tables: LabelGateTables

    private static func scalars(_ text: String) -> [UInt32] { text.unicodeScalars.map(\.value) }

    /// Every non-overlapping match, left to right, as Python `finditer` returns them, each lowered
    /// with Python `str.lower()`.
    func loweredMatches(in text: String) -> [String] {
        let input = text.unicodeScalars.map(\.value)
        var results: [String] = []
        var position = 0
        while position < input.count {
            var matchedEnd: Int?
            for alternative in Self.alternatives {
                if let end = match(alternative, 0, position, input) {
                    matchedEnd = end
                    break
                }
            }
            if let end = matchedEnd, end > position {
                results.append(lowered(input[position..<end]))
                position = end
            } else {
                position += 1
            }
        }
        return results
    }

    private func match(_ tokens: [Token], _ index: Int, _ position: Int, _ input: [UInt32]) -> Int? {
        guard index < tokens.count else { return position }
        switch tokens[index] {
        case .boundary:
            let before = position > 0 && tables.isWord(input[position - 1])
            let after = position < input.count && tables.isWord(input[position])
            return before != after ? match(tokens, index + 1, position, input) : nil
        case .literal(let characters):
            guard position + characters.count <= input.count else { return nil }
            for (offset, character) in characters.enumerated() where !matches(input[position + offset], character) {
                return nil
            }
            return match(tokens, index + 1, position + characters.count, input)
        case let .spaces(minimum, maximum):
            var count = 0
            while position + count < input.count, tables.space.contains(input[position + count]), maximum.map({ count < $0 }) ?? true {
                count += 1
            }
            guard count >= minimum else { return nil }
            for taken in stride(from: count, through: minimum, by: -1) {
                if let end = match(tokens, index + 1, position + taken, input) { return end }
            }
            return nil
        case .optional(let character):
            if position < input.count, matches(input[position], character), let end = match(tokens, index + 1, position + 1, input) {
                return end
            }
            return match(tokens, index + 1, position, input)
        }
    }

    private func matches(_ scalar: UInt32, _ character: UInt32) -> Bool {
        tables.folds[character]?[scalar] != nil
    }

    /// Python `str.lower()` of the matched text. Every matched scalar is either a pattern
    /// character's case-insensitive equivalent (lowered from the table) or a `\s` or Han
    /// character, which Python leaves unchanged.
    private func lowered(_ scalars: ArraySlice<UInt32>) -> String {
        var view = String.UnicodeScalarView()
        for scalar in scalars {
            let mapped = tables.folds.values.lazy.compactMap { $0[scalar] }.first ?? [scalar]
            for value in mapped {
                if let unicode = Unicode.Scalar(value) { view.append(unicode) }
            }
        }
        return String(view)
    }
}

/// Python's ordering of `str` values: lexicographic by code point.
func pythonStringPrecedes(_ left: String, _ right: String) -> Bool {
    left.unicodeScalars.map(\.value).lexicographicallyPrecedes(right.unicodeScalars.map(\.value))
}
