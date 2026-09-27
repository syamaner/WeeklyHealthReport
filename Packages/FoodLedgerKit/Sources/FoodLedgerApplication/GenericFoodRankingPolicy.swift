import Foundation

/// Shared, source-neutral presentation preferences. These never establish food identity.
/// Explicit selection, preparation and nutrition contracts remain separate.
public enum GenericFoodRankingPolicy {
    public static let version = "generic-representation-ranking-v2"
    public struct Preference: Equatable, Sendable {
        let primaryFood: Bool
        let unrequestedSpecialisations: Int
        let ordinaryRepresentation: Int
        let additionalTerms: Int
    }
    // Representation descriptors apply to every family, with no food-name branches.
    private static let specialised: Set<String> = [
        "style", "human", "colostrum", "transitional", "sheep", "sheeps", "goat", "bison", "game",
        "evaporated", "condensed", "powder", "powdered", "dry", "dried", "dehydrated",
        "fruit", "flavoured", "flavored", "sweetened", "chocolate", "vanilla", "strawberry",
        "blueberry", "raspberry", "apricot", "pineapple", "coconut", "mango", "lemon", "red"
    ]
    private static let ordinary: Set<String> = ["plain", "average", "regular", "whole", "white"]
    private static let preparation: Set<String> = ["raw", "cooked", "uncooked", "boiled", "broiled", "grilled", "roasted"]
    public static func preference(name: String, food: String, requestedText: String) -> Preference {
        let query = tokens(food), requested = tokens(requestedText), candidate = tokens(name)
        let head = tokens(String(name.split(separator: ",", maxSplits: 1).first ?? ""))
        let extras = candidate.subtracting(requested)
        return Preference(primaryFood: !head.isEmpty && head.isSubset(of: query),
            unrequestedSpecialisations: extras.intersection(specialised).count,
            ordinaryRepresentation: candidate.intersection(ordinary).count + (candidate.contains("whole") ? 1 : 0),
            additionalTerms: extras.subtracting(preparation).count)
    }
    public static func prefers(_ lhs: Preference, over rhs: Preference) -> Bool {
        if lhs.primaryFood != rhs.primaryFood { return lhs.primaryFood }
        if lhs.unrequestedSpecialisations != rhs.unrequestedSpecialisations {
            return lhs.unrequestedSpecialisations < rhs.unrequestedSpecialisations
        }
        if lhs.ordinaryRepresentation != rhs.ordinaryRepresentation {
            return lhs.ordinaryRepresentation > rhs.ordinaryRepresentation
        }
        return lhs.additionalTerms < rhs.additionalTerms
    }
    private static func tokens(_ text: String) -> Set<String> { Set(terms(text)) }

    /// Canonical lexical terms shared by retrieval and ranking; original evidence is never rewritten.
    public static func terms(_ text: String) -> [String] {
        let folded = text.folding(options: [.diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        let aliases = ["aubergines": "aubergine", "eggplant": "aubergine", "eggplants": "aubergine",
            "garbanzo": "chickpea", "garbanzos": "chickpea", "yogurt": "yoghurt", "yogurts": "yoghurt"]
        let words = folded.lowercased().split { !$0.isASCII || !$0.isLetter && !$0.isNumber }
        let normalized = words.map { aliases[String($0)] ?? String($0) }.joined(separator: " ")
            .replacingOccurrences(of: "rib eye", with: "ribeye")
            .replacingOccurrences(of: "chick peas", with: "chickpea")
            .replacingOccurrences(of: "chick pea", with: "chickpea")
            .replacingOccurrences(of: "peas chick", with: "chickpea")
            .replacingOccurrences(of: "pea chick", with: "chickpea")
        let equivalents = [
        "clementines": "clementine", "oranges": "orange", "mandarins": "mandarin",
        "tangerines": "tangerine", "grapes": "grape", "pears": "pear",
        "peaches": "peach", "plums": "plum", "apricots": "apricot",
        "strawberries": "strawberry", "raspberries": "raspberry",
        "blueberries": "blueberry", "blackberries": "blackberry", "cherries": "cherry",
        "apples": "apple", "bananas": "banana", "eggs": "egg", "whites": "white", "yolks": "yolk",
        "potatoes": "potato", "tomatoes": "tomato", "carrots": "carrot",
        "onions": "onion", "beans": "bean", "peas": "pea", "lentils": "lentil",
        "chickpeas": "chickpea", "zucchini": "courgette", "courgettes": "courgette"
        ]
        let connectors: Set<String> = ["and", "with", "the", "of", "in", "from", "a", "an"]
        return normalized.split(separator: " ").map(String.init)
            .filter { !connectors.contains($0) }.map { equivalents[$0] ?? $0 }
    }
}
