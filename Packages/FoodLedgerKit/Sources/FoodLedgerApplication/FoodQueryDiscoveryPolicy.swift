import Foundation

/// Bounded permission to look for a named dish, not to confirm a recipe or intake.
public enum FoodQueryDiscoveryPolicy {
    public static let version = "food-query-discovery-v2"
    public static let recipeReviewMessage = "Results are possible matches for your dish. Ingredients, proportions and the consumed amount still need your review; the amount has not been filled in."

    public static func allowsNamedDishDiscovery(_ query: ParsedFoodQuery) -> Bool {
        guard query.route == .clarify, !query.reasons.isEmpty,
              Set(query.reasons).isSubset(of: ["recipe_unknown", "multiple_foods_or_recipe"]),
              let food = query.food else { return false }
        // Retain every word for retrieval. These observed prefixes do not assert
        // a brand match or establish the ingredients of a homemade recipe.
        let patterns = [
            #"^(?:homemade |baxters )?(?:(?:red )?lentils? (?:and|&) tomato|tomato (?:and|&) (?:red )?lentils?) soup$"#,
            #"^(?:homemade )?porridge (?:made )?with (?:water|milk)$"#
        ]
        return patterns.contains { food.range(of: $0, options: .regularExpression) != nil }
    }
}
