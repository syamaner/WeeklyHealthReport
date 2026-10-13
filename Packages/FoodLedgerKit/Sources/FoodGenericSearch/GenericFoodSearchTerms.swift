import Foundation
import FoodLedgerApplication

/// Retrieval-only spelling equivalents. Original evidence and identity are unchanged.
/// Complete token coverage is required; these terms never infer a recipe or a cut.
enum GenericFoodSearchTerms {
    static let version = FoodLexicalPlurals.version
    /// Catalogue retrieval terms (CoFID, USDA, TFDA and their ranking), plurals folded.
    static func tokens(_ text: String) -> Set<String> { Set(terms(text)) }
    /// `food-lexical-terms-v8` terms for live source admission and page identity,
    /// which keep their own versions and are not changed by plural folding.
    static func literalTokens(_ text: String) -> Set<String> { Set(GenericFoodRankingPolicy.literalTerms(text)) }
    private static func terms(_ text: String) -> [String] { GenericFoodRankingPolicy.terms(text) }

    /// The comma-delimited primary name must be wholly contained in the query.
    /// Ingredient mentions in chocolate, milk or banana bread do not earn this bonus.
    static func primaryNameMatches(_ name: String, query: Set<String>) -> Bool {
        let head = tokens(String(name.split(separator: ",", maxSplits: 1).first ?? ""))
        return !head.isEmpty && head.isSubset(of: query)
    }

    /// A use/serving suggestion does not identify the requested food. This bounded
    /// pancake rule distinguishes the finished food from syrup and uncooked products.
    /// Explicit searches for those products remain eligible; no source facts change.
    /// `literal` keeps food-lexical-terms-v8 candidate terms for live sources, whose
    /// query terms are literal too.
    static func acceptsFoodForm(name: String, query: Set<String>, literal: Bool) -> Bool {
        guard query.contains("pancake") else { return true }
        let candidate = literal ? literalTokens(name) : tokens(name)
        let productForms: [Set<String>] = [["syrup", "syrups"], ["mix", "mixes"], ["batter"]]
        return productForms.allSatisfy { candidate.isDisjoint(with: $0) || !query.isDisjoint(with: $0) }
    }

    static func suggestions(for text: String, names: [String]) -> [String] {
        let query = tokens(text)
        guard !query.isEmpty, query.count <= 5 else { return [] }
        let entries = names.map(tokens)
        let vocabulary = Set(entries.flatMap { $0 })
        let unknown = query.filter { !vocabulary.contains($0) }
        guard unknown.count == 1, let miss = unknown.first, miss.count >= 5 else { return [] }
        let retained = query.subtracting([miss])
        // Matching uses folded terms; the suggestion is built from the user's own
        // literal terms and a source spelling, so a folded form ("french fry") is
        // never shown. Only the corrected token changes.
        let literalQuery = GenericFoodRankingPolicy.literalTerms(text)
        let typed = literalQuery.filter { fold($0) == miss }
        var spellings: [String: String] = [:]
        for word in Set(names.flatMap(GenericFoodRankingPolicy.literalTerms)) where word.count >= 5
            && typed.contains(where: { oneEdit($0, word) }) && entries.contains(where: { retained.union([fold(word)]).isSubset(of: $0) }) {
            // One spelling per folded word, so "walnut" and "walnuts" are not both offered.
            spellings[fold(word)] = min(spellings[fold(word)] ?? word, word)
        }
        // Suggestions require another explicit search, never silently alter evidence.
        return spellings.values.sorted().prefix(3).map { replacement in
            literalQuery.map { fold($0) == miss ? replacement : $0 }.joined(separator: " ")
        }
    }

    private static func fold(_ literal: String) -> String { terms(literal).first ?? literal }

    private static func oneEdit(_ a: String, _ b: String) -> Bool {
        let x = Array(a), y = Array(b)
        guard abs(x.count - y.count) <= 1 else { return false }
        var i = 0, j = 0, edits = 0
        while i < x.count && j < y.count {
            if x[i] == y[j] { i += 1; j += 1; continue }
            edits += 1
            if edits > 1 { return false }
            if x.count >= y.count { i += 1 }
            if y.count >= x.count { j += 1 }
        }
        return edits + (x.count - i) + (y.count - j) == 1
    }
}
