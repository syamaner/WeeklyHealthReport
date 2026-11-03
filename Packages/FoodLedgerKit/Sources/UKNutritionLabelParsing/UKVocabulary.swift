import Foundation

/// The UK reader's copies of the parser v3 vocabulary it needs (`docs/pasted-nutrition-label-uk-english-v1-p2.md`
/// section 1). Parser v3's own tables are internal to `NutritionLabelParsing` and frozen, so the
/// UK target holds these copies; `UKVocabularyParityTests` asserts each one matches parser v3.
public enum UKVocabulary {
    /// Parser v3's value pattern (`PatternsV3.value`), copied: what a number "of its own" is.
    public static let valuePattern =
        #"(?<![\p{L}\p{N}.,])(less than|<=|≤|≦|＜|<|少於|未滿)?\s*(\d+(?:[.,]\d+)?)\s*(kJ|kj|KJ|Kj|kcal|Kcal|KCAL|kCal|Cal|cal|mcg|mg|µg|μg|mL|ml|g|%|大卡|千卡|公克|毫克|微克|毫升|克)?(?!(?!以[下上])\p{L})"#
    /// Parser v3's header phrase pattern (`Patterns.headerPhrase`), copied.
    public static let headerPhrasePattern =
        #"(?i)\bper\b|每份|每\s*100|每日參考值|%\s*RI|\bRI\b|reference intake|%\s*DV|daily value|\bNRV\b"#
    /// The English unit tokens of the value pattern, excluding `%`.
    public static let unitTokens: [String] = ["kJ", "kj", "KJ", "Kj", "kcal", "Kcal", "KCAL", "kCal", "Cal", "cal",
                                             "mcg", "mg", "µg", "μg", "mL", "ml", "g"]
    /// Energy row labels (lower-cased) as parser v3's English rows name them.
    public static let energyLabels: [String] = ["energy"]
    /// Sub-row names N3 may restore from brackets, with their parent row.
    public static let subRowParents: [String: String] = [
        "saturates": "fat", "mono-unsaturates": "fat", "polyunsaturates": "fat",
        "sugars": "carbohydrate", "polyols": "carbohydrate", "starch": "carbohydrate",
    ]
    /// Top-level English row label starts (lower-cased), for N3's nearest parent.
    public static let topLevelRows: [(prefix: String, row: String)] = [
        ("total fat", "fat"), ("fat", "fat"), ("total carbohydrate", "carbohydrate"), ("carbohydrate", "carbohydrate"),
        ("energy", "energy"), ("protein", "protein"), ("fibre", "fibre"), ("fiber", "fibre"), ("salt", "salt"), ("sodium", "sodium"),
    ]
    /// Identity v2's markers (`pasted-label-identity-v2`), copied for guard G3: whole words, then
    /// symbols. `PastedLabelBasisStateV2` in `FoodLedgerApplication` holds the same list; a parity
    /// test keeps them equal, so a change to identity v2 is also a new UK parser version.
    public static let identityWordMarkers: [String] = [
        "prepared", "drained", "preparation", "reconstituted", "reconstitution", "rehydrated", "diluted", "dilution",
        "cooked", "cooking", "baked", "grilled", "fried", "microwaved", "heated", "boiled", "steamed", "roasted", "toasted",
        "brewed", "infused", "soaked", "poached", "braised", "barbecued", "made", "served", "instructions", "consumed", "with",
    ]
    public static let identitySymbolMarkers: [String] = ["+"]
}

/// A compiled regular expression over `String`, UTF-16 safe.
struct UKPattern: @unchecked Sendable {
    let expression: NSRegularExpression

    init(_ pattern: String) {
        // Compile-time literals covered by tests.
        expression = try! NSRegularExpression(pattern: pattern)
    }

    func contains(_ text: String) -> Bool {
        expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }

    func matches(_ text: String) -> [(range: Range<String.Index>, groups: [String?])] {
        expression.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match in
            guard let range = Range(match.range, in: text) else { return nil }
            let groups = (0..<match.numberOfRanges).map { index in Range(match.range(at: index), in: text).map { String(text[$0]) } }
            return (range, groups)
        }
    }

    /// The range of capture group `group` in each match, nil where that group did not take part.
    func groupRanges(_ text: String, group: Int) -> [Range<String.Index>?] {
        expression.matches(in: text, range: NSRange(text.startIndex..., in: text)).map { Range($0.range(at: group), in: text) }
    }

    func replacing(in text: String, with template: String) -> String {
        expression.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: template)
    }
}
