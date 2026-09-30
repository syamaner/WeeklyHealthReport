import Foundation

/// Bounded permission to look for a named dish, not to confirm a recipe or intake.
public enum FoodQueryDiscoveryPolicy {
    public static let version = "food-query-discovery-v3"
    public static let recipeReviewMessage = "Results are possible matches for your dish. Ingredients, proportions and the consumed amount still need your review; the amount has not been filled in."

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
