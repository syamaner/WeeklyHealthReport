import Foundation
import FoodLedgerDomain

/// Discovery alternatives only. Never resolves a source's unknown preparation.
public enum FoodPreparationDiscoveryPolicy {
    public static let version = "food-preparation-discovery-v1"

    public static func accepts(requested: PreparationState?, actual: PreparationState,
                               sourceName: String, query: ParsedFoodQuery) -> Bool {
        guard let requested else { return true }
        if requested == actual { return true }
        guard actual.kind == .unknown, query.requiresRecipeReview,
              requested.kind == .raw || requested.kind == .cooked else { return false }
        let words = Set(sourceName.lowercased().split { !$0.isLetter }.map(String.init))
        // A source label can veto a contradiction without establishing its metadata.
        if requested.kind == .cooked { return words.isDisjoint(with: ["raw", "uncooked"]) }
        return words.isDisjoint(with: FoodQueryPreparationPolicy.cookingWords)
    }

    public static func isUnverified(requested: PreparationState?, actual: PreparationKind) -> Bool {
        guard let requested, requested.kind != .unknown else { return false }
        return actual == .unknown
    }
}
