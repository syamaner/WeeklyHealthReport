import Foundation

/// Retrieval-only spelling equivalents. Original evidence and identity are unchanged.
/// Complete token coverage is required; these terms never infer a recipe or a cut.
enum GenericFoodSearchTerms {
    static let version = "food-lexical-terms-v2"
    private static let connectors: Set<String> = ["and", "with", "the", "of", "in", "from", "a", "an"]
    private static let equivalents = [
        "apples": "apple", "bananas": "banana", "eggs": "egg",
        "potatoes": "potato", "tomatoes": "tomato", "carrots": "carrot",
        "onions": "onion", "beans": "bean", "peas": "pea", "lentils": "lentil"
    ]

    static func tokens(_ text: String) -> Set<String> {
        let normalized = CoFIDGenericFoodSearch.normalized(text)
            .replacingOccurrences(of: "rib eye", with: "ribeye")
        return Set(normalized.split(separator: " ").map(String.init)
            .filter { !connectors.contains($0) }.map { equivalents[$0] ?? $0 })
    }
}
