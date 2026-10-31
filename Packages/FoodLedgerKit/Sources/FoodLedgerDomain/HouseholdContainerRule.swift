import Foundation

/// The household-container rule shared by the search interpretation
/// (`food-query-interpretation-v3`, docs/food-query-parser-v10.md) and the list grammar
/// (`food-list-lexical-v6`, docs/food-list-lexical-v6.md), so the two cannot drift (#335, #353).
///
/// It decides only whether a leading container word names a portion that leaves the food text.
/// It never produces an amount: a container gives no count, volume or portion size, and each
/// caller leaves the amount for the user to enter.
public enum HouseholdContainerRule {
    /// Units that are a portion with or without "of" ("1 cup rice", "2 mugs tea"), except before
    /// "cake" or "cakes": a mug cake is a food in its own right, as a cup cake is.
    public static let unitsWithoutOf: Set<String> = ["cup", "cups", "mug", "mugs"]
    /// Units that also start food names (pot noodle, glass noodles, bottle gourd, pack choi), so
    /// they are a portion only when "of" follows them ("a pot of yoghurt").
    public static let unitsNeedingOf: Set<String> = ["pot", "pots", "glass", "glasses", "bottle", "bottles", "pack", "packs"]
    /// The containers the list grammar recognises (`food-list-lexical-v6`): cups, mugs, glasses,
    /// pots and packs, singular and plural. A closed list; widening it needs a further version.
    public static let listContainerUnits: Set<String> = ["cup", "cups", "mug", "mugs", "glass", "glasses", "pot", "pots", "pack", "packs"]

    /// Whether a leading household `unit` leaves the food text, given whether "of" follows it and
    /// the text after it (and after "of", when present). Units outside the two guarded sets are
    /// unaffected by this rule and always leave it.
    public static func leavesFoodText(unit: String, followedByOf: Bool, rest: String) -> Bool {
        let unit = unit.lowercased()
        if unitsWithoutOf.contains(unit),
           rest.range(of: #"^cakes?\b"#, options: [.regularExpression, .caseInsensitive]) != nil { return false }
        if unitsNeedingOf.contains(unit), !followedByOf { return false }
        return true
    }

    /// A leading list container phrase in `text` ("mugs of tea" gives "mugs of " and "tea"), or
    /// nil when the text does not start with one that leaves the food text, or when no food
    /// follows it ("2 mugs", "a mug of"). Matching is case-insensitive and on whole words, so
    /// "cupcakes", "potatoes" and "packed lunch" are not containers.
    public static func leadingListContainer(in text: String) -> (unit: String, phrase: String, rest: String)? {
        let pattern = #"(?i)^(cups?|mugs?|glass(?:es)?|pots?|packs?)\b\s*(of\b\s*)?"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let phraseRange = Range(match.range, in: text),
              let unitRange = Range(match.range(at: 1), in: text) else { return nil }
        let rest = text[phraseRange.upperBound...].trimmingCharacters(in: .whitespaces)
        let unit = String(text[unitRange])
        guard rest.range(of: #"\p{L}"#, options: .regularExpression) != nil,
              leavesFoodText(unit: unit, followedByOf: match.range(at: 2).location != NSNotFound, rest: rest) else { return nil }
        return (unit, String(text[phraseRange]), rest)
    }
}
