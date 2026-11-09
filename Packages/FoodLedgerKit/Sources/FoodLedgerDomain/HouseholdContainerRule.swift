import Foundation

/// The household-container rule shared by the search interpretation
/// (`food-query-interpretation-v3` and `v4`, docs/food-query-parser-v10.md and
/// docs/food-query-interpretation-v4.md) and the list grammar (`food-list-lexical-v6` and `v7`,
/// docs/food-list-lexical-v6.md and docs/food-list-lexical-v7.md), so the two cannot drift
/// (#335, #353, #359).
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

    // MARK: food-list-lexical-v7 and food-query-interpretation-v4 (#359)

    /// Whether a leading household `unit` leaves the food text, given whether a written amount
    /// comes before it. With an amount ("2 mugs tea", "250 ml mug of milk") this is
    /// `leavesFoodText`. With no amount the unit is a portion only when "of" follows it ("mugs
    /// of tea"), so a food name that starts with a unit ("cup noodles", "mug cake") keeps it.
    public static func measureLeavesFoodText(unit: String, followedByOf: Bool, rest: String, afterAmount: Bool) -> Bool {
        (afterAmount || followedByOf) && leavesFoodText(unit: unit, followedByOf: followedByOf, rest: rest)
    }

    /// The household measures the list grammar recognises from `food-list-lexical-v7`: the v6
    /// containers, the other containers (bottles, jars, tubs, cans, tins, cartons, bowls, bags,
    /// sachets, plates) and the other household measures (slices, scoops, portions, servings,
    /// packets, dollops and spoons in their written forms). Singular and plural, whole words,
    /// case-insensitive. A closed list; widening it needs a further version. Pieces stay a count.
    public static let listMeasurePatternV7 = #"cups?|mugs?|glass(?:es)?|pots?|packs?|packets?|bottles?|jars?|tubs?|cans?|tins?|cartons?|bowls?|bags?|sachets?|plates?|slices?|scoops?|portions?|servings?|dollops?|(?:tea|table)\s+spoons?|(?:tea|table)?spoonfuls?|(?:tea|table)?spoons?|tsps?|tbsps?"#

    /// A leading `food-list-lexical-v7` household measure phrase in `text` ("slices of bread"
    /// gives "slices of " and "bread"), or nil when the text does not start with one that leaves
    /// the food text under `measureLeavesFoodText`, or when no food follows it ("2 slices", "a jar
    /// of"). `afterAmount` says whether a written amount came before the text.
    public static func leadingListMeasure(in text: String, afterAmount: Bool) -> (unit: String, phrase: String, rest: String)? {
        // An abbreviation may carry a full stop ("2 tsp. sugar"), as the unit token allows.
        let pattern = #"(?i)^("# + listMeasurePatternV7 + #")\b\.?\s*(of\b\s*)?"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let phraseRange = Range(match.range, in: text),
              let unitRange = Range(match.range(at: 1), in: text) else { return nil }
        let rest = text[phraseRange.upperBound...].trimmingCharacters(in: .whitespaces)
        let unit = String(text[unitRange])
        guard rest.range(of: #"\p{L}"#, options: .regularExpression) != nil,
              measureLeavesFoodText(unit: unit, followedByOf: match.range(at: 2).location != NSNotFound,
                                    rest: rest, afterAmount: afterAmount) else { return nil }
        return (unit, String(text[phraseRange]), rest)
    }
}
