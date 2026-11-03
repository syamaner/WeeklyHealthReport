import Foundation

/// Bounded permission to look for a named dish, not to confirm a recipe or intake.
/// v4 (#370, unified food search contract v73): one exact leading or trailing whole-dish amount
/// may pre-fill Confirm, as it does for a plain search. The recipe stays unconfirmed.
public enum FoodQueryDiscoveryPolicy {
    public static let version = "food-query-discovery-v4"
    /// Shown only while a named dish has no amount; an exact amount in the description or the
    /// amount chip removes it.
    public static let recipeReviewMessage = "Results are possible matches for your dish. Ingredients, proportions and the consumed amount still need your review; the amount has not been filled in."

    /// The written mass or volume forms a named dish may start or end with. Only units the parser
    /// already reads as an exact amount; household measures, counts and bounds never qualify.
    private static let amount = #"(?:\d+(?:\.\d+)?|\.\d+)\s*(?:kilograms?|kg|grams?|g|millilitres?|milliliters?|ml|litres?|liters?|l)"#

    /// v4: the whole-dish amount for a named dish whose description starts or ends with one exact
    /// mass or volume, separated from the dish by spaces only ("200g porridge made with milk",
    /// "lentil and tomato soup 300g"). Nil when the dish is not eligible for discovery, when the
    /// description holds any other number, when the amount sits inside the description or after a
    /// comma ("porridge made with milk, 200 g"), or when a trailing volume follows a "with"
    /// ingredient ("porridge made with milk 200 ml"), where it may be the ingredient's amount.
    /// The amount is read by the parser's own unit rules; nothing is converted or estimated.
    public static func namedDishAmount(_ query: ParsedFoodQuery) -> ParsedFoodQuery.Quantity? {
        guard allowsNamedDishDiscovery(query) else { return nil }
        let text = query.original.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let numbers = try? NSRegularExpression(pattern: #"\d+(?:\.\d+)?|\.\d+"#),
              numbers.numberOfMatches(in: text, range: NSRange(text.startIndex..., in: text)) == 1 else { return nil }
        let leading = text.range(of: "^" + amount + #"(?=\s+\p{L})"#, options: .regularExpression)
        let trailing = text.range(of: #"(?<=\p{L})\s+"# + amount + "$", options: .regularExpression)
        guard let range = leading ?? trailing else { return nil }
        let literal = text[range].trimmingCharacters(in: .whitespaces)
        let probe = FoodQueryParser.parse(literal + " rice")
        guard probe.route == .search, probe.food == "rice", let quantity = probe.quantity,
              quantity.unit == "g" || quantity.unit == "ml" else { return nil }
        if leading == nil, quantity.unit == "ml",
           text[..<range.lowerBound].range(of: #"\bwith\b"#, options: .regularExpression) != nil { return nil }
        return quantity
    }

    public static func allowsNamedDishDiscovery(_ query: ParsedFoodQuery) -> Bool {
        guard query.route == .clarify, !query.reasons.isEmpty,
              Set(query.reasons).isSubset(of: ["recipe_unknown", "multiple_foods_or_recipe"]),
              let food = query.food else { return false }
        // Retain every word for retrieval. These observed prefixes do not assert
        // a brand match or establish the ingredients of a homemade recipe.
        // A dish followed by a bounded ingredient list is eligible for discovery,
        // not component decomposition. Keep every word (including uncertain dictation)
        // in retrieval and retain the original query for any enabled provider.
        let dish = #"(?:(?:scallion(?: n)? |spring onion |egg )?pancakes?|dan bing|oyster omelette|omelette|fried rice|beef noodle soup|dumplings?|toast|sandwich|steak|bubble tea|milk tea|fried chicken)"#
        let ingredient = #"(?:(?:fried |sliced )?(?:egg|cheese)|mushrooms?|pork|cabbage|bok choy|chicken|beef|tofu|basil|noodles|sauce|(?:tapioca )?pearls)"#
        let composedDish = #"^(?:taiwanese )?(?:breakfast )?"# + dish + #" with "#
            + ingredient + #"(?:(?: and | & )"# + ingredient + #"){0,3}$"#
        let patterns = [
            composedDish,
            #"^(?:homemade |baxters )?(?:(?:red )?lentils? (?:and|&) tomato|tomato (?:and|&) (?:red )?lentils?) soup$"#,
            #"^(?:homemade )?porridge (?:made )?with (?:water|milk)$"#
        ]
        return patterns.contains { food.range(of: $0, options: .regularExpression) != nil }
    }
}
