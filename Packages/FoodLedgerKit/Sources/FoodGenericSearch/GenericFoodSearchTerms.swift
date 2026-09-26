import Foundation

/// Retrieval-only spelling equivalents. Original evidence and identity are unchanged.
/// Complete token coverage is required; these terms never infer a recipe or a cut.
enum GenericFoodSearchTerms {
    static let version = "food-lexical-terms-v3"
    private static let connectors: Set<String> = ["and", "with", "the", "of", "in", "from", "a", "an"]
    private static let equivalents = [
        "apples": "apple", "bananas": "banana", "eggs": "egg",
        "potatoes": "potato", "tomatoes": "tomato", "carrots": "carrot",
        "onions": "onion", "beans": "bean", "peas": "pea", "lentils": "lentil",
        "chickpeas": "chickpea", "zucchini": "courgette", "courgettes": "courgette"
    ]

    static func tokens(_ text: String) -> Set<String> { Set(terms(text)) }

    private static func terms(_ text: String) -> [String] {
        let normalized = CoFIDGenericFoodSearch.normalized(text)
            .replacingOccurrences(of: "rib eye", with: "ribeye")
            .replacingOccurrences(of: "chick peas", with: "chickpea")
            .replacingOccurrences(of: "chick pea", with: "chickpea")
            .replacingOccurrences(of: "peas chick", with: "chickpea")
            .replacingOccurrences(of: "pea chick", with: "chickpea")
        return normalized.split(separator: " ").map(String.init)
            .filter { !connectors.contains($0) }.map { equivalents[$0] ?? $0 }
    }

    /// The comma-delimited primary name must be wholly contained in the query.
    /// Ingredient mentions in chocolate, milk or banana bread do not earn this bonus.
    static func primaryNameMatches(_ name: String, query: Set<String>) -> Bool {
        let head = tokens(String(name.split(separator: ",", maxSplits: 1).first ?? ""))
        return !head.isEmpty && head.isSubset(of: query)
    }

    static func suggestions(for text: String, names: [String]) -> [String] {
        let query = tokens(text)
        guard !query.isEmpty, query.count <= 5 else { return [] }
        let entries = names.map(tokens)
        let vocabulary = Set(entries.flatMap { $0 })
        let unknown = query.filter { !vocabulary.contains($0) }
        guard unknown.count == 1, let miss = unknown.first, miss.count >= 5 else { return [] }
        let retained = query.subtracting([miss])
        let replacements = vocabulary.filter { word in
            word.count >= 5 && oneEdit(miss, word) && entries.contains { retained.union([word]).isSubset(of: $0) }
        }.sorted()
        // Suggestions require another explicit search, never silently alter evidence.
        return replacements.prefix(3).map { replacement in
            terms(text).map { $0 == miss ? replacement : $0 }.joined(separator: " ")
        }
    }

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
