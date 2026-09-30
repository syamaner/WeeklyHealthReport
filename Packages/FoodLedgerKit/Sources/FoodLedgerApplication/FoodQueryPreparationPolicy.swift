import Foundation
import FoodLedgerDomain

/// Query intent only: never supplies or rewrites a source record's preparation.
public enum FoodQueryPreparationPolicy {
    public static let version = "food-query-preparation-v1"
    // "Roast" may name a raw cut (e.g. rib roast); do not infer its state.
    static let cookingWords: Set<String> = [
        "cooked", "roasted", "boiled", "grilled", "broiled", "fried",
        "baked", "steamed", "braised", "poached", "stewed"
    ]

    public static func kind(for parsed: ParsedFoodQuery) -> PreparationKind? {
        guard parsed.allowsCandidateDiscovery else { return nil }
        if let value = parsed.attributes["preparation"], let kind = PreparationKind(rawValue: value) {
            return kind == .named || kind == .unknown ? nil : kind
        }
        let words = Set(([parsed.attributes["preparation"], parsed.food].compactMap { $0 }.joined(separator: " "))
            .lowercased().split { !$0.isLetter }.map(String.init))
        return words.isDisjoint(with: cookingWords) ? nil : .cooked
    }

    /// Keep extracted cooking methods as lexical constraints. Coarse raw/cooked
    /// state is filtered separately; it is not a synonym for a specific method.
    public static func foodTerms(for parsed: ParsedFoodQuery) -> String {
        let food = parsed.food ?? parsed.original
        guard let method = parsed.attributes["preparation"],
              PreparationKind(rawValue: method) == nil else { return food }
        return food + " " + method
    }
}
