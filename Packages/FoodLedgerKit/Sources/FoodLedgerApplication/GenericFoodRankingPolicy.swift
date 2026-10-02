import Foundation

/// Shared, source-neutral lexical eligibility and presentation preferences.
/// These never establish food identity.
/// Explicit selection, preparation and nutrition contracts remain separate.
public enum GenericFoodRankingPolicy {
    public static let version = "generic-representation-ranking-v6"
    public struct Preference: Equatable, Sendable {
        let primaryFood: Bool
        let parentheticalOnlyTerms: Int
        let unrequestedSpecialisations: Int
        let unrequestedForms: Int
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
    private static let forms: Set<String> = ["crumbled", "sliced", "diced", "chopped", "peeled"]
    private static let ordinary: Set<String> = ["plain", "average", "regular", "whole", "white"]
    private static let preparation: Set<String> = ["raw", "cooked", "uncooked", "boiled", "broiled", "grilled", "roasted"]
    public static func preference(name: String, food: String, requestedText: String) -> Preference {
        // This exact annotation is source metadata, never an identity rewrite.
        let rankingName = name.replacingOccurrences(
            of: #"(?i)\s*\(Includes foods for USDA's Food Distribution Program\)"#,
            with: "", options: .regularExpression)
        let query = tokens(food), requested = tokens(requestedText), candidate = tokens(rankingName)
        let head = tokens(String(name.split(separator: ",", maxSplits: 1).first ?? ""))
        let extras = candidate.subtracting(requested)
        let direct = tokens(outsideParentheses(name))
        return Preference(primaryFood: !head.isEmpty && head.isSubset(of: query),
            parentheticalOnlyTerms: query.intersection(candidate).subtracting(direct).count,
            unrequestedSpecialisations: extras.intersection(specialised).count,
            unrequestedForms: extras.intersection(forms).count,
            ordinaryRepresentation: candidate.intersection(ordinary).count + (candidate.contains("whole") ? 1 : 0),
            additionalTerms: extras.subtracting(preparation).count)
    }
    public static func prefers(_ lhs: Preference, over rhs: Preference) -> Bool {
        if lhs.primaryFood != rhs.primaryFood { return lhs.primaryFood }
        if lhs.parentheticalOnlyTerms != rhs.parentheticalOnlyTerms {
            return lhs.parentheticalOnlyTerms < rhs.parentheticalOnlyTerms
        }
        if lhs.unrequestedSpecialisations != rhs.unrequestedSpecialisations {
            return lhs.unrequestedSpecialisations < rhs.unrequestedSpecialisations
        }
        if lhs.unrequestedForms != rhs.unrequestedForms {
            return lhs.unrequestedForms < rhs.unrequestedForms
        }
        if lhs.ordinaryRepresentation != rhs.ordinaryRepresentation {
            return lhs.ordinaryRepresentation > rhs.ordinaryRepresentation
        }
        return lhs.additionalTerms < rhs.additionalTerms
    }
    // Parenthetical mentions remain eligible, but do not outrank directly named food/cuts.
    // This is lexical presentation only; it does not infer species or change source facts.
    private static func outsideParentheses(_ text: String) -> String {
        var depth = 0
        var result = ""
        for character in text {
            if character == "(" { depth += 1; result.append(" ") }
            else if character == ")" { depth = max(0, depth - 1); result.append(" ") }
            else if depth == 0 { result.append(character) }
        }
        return result
    }

    /// A bounded rejection rule, not a general food-identity classifier. A known
    /// derivative in the comma-delimited primary name must itself be requested.
    /// Original source names, evidence and identity checks remain unchanged.
    public static func allowsDerivativeFoodName(_ name: String, query: String) -> Bool {
        let families: [Set<String>] = [
            ["bread"], ["roll", "rolls"], ["bun", "buns"], ["relish"]
        ]
        let head = tokens(String(name.split(separator: ",", maxSplits: 1).first ?? ""))
        let requested = tokens(query)
        return families.allSatisfy { family in
            head.isDisjoint(with: family) || !requested.isDisjoint(with: family)
        }
    }

    private static func tokens(_ text: String) -> Set<String> { Set(terms(text)) }

    /// Canonical lexical terms shared by retrieval and ranking; original evidence is never rewritten.
    public static func terms(_ text: String) -> [String] {
        let folded = text.folding(options: [.diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        let aliases = ["aubergines": "aubergine", "eggplant": "aubergine", "eggplants": "aubergine",
            "garbanzo": "chickpea", "garbanzos": "chickpea", "yogurt": "yoghurt", "yogurts": "yoghurt"]
        let words = folded.lowercased().split { !$0.isLetter && !$0.isNumber }
        let normalized = words.map { aliases[String($0)] ?? String($0) }.joined(separator: " ")
            .replacingOccurrences(of: "rib eye", with: "ribeye")
            .replacingOccurrences(of: "chick peas", with: "chickpea")
            .replacingOccurrences(of: "chick pea", with: "chickpea")
            .replacingOccurrences(of: "peas chick", with: "chickpea")
            .replacingOccurrences(of: "pea chick", with: "chickpea")
        let equivalents = [
        "syrups": "syrup", "pancakes": "pancake", "clementines": "clementine", "oranges": "orange", "mandarins": "mandarin",
        "tangerines": "tangerine", "grapes": "grape", "pears": "pear",
        "peaches": "peach", "plums": "plum", "apricots": "apricot",
        "strawberries": "strawberry", "raspberries": "raspberry",
        "blueberries": "blueberry", "blackberries": "blackberry", "cherries": "cherry",
        "apples": "apple", "bananas": "banana", "eggs": "egg", "whites": "white", "yolks": "yolk",
        "potatoes": "potato", "tomatoes": "tomato", "carrots": "carrot",
        "onions": "onion", "beans": "bean", "peas": "pea", "lentils": "lentil",
        "roast": "roasted", "slice": "sliced", "slices": "sliced",
        "seeds": "seed", "chickpeas": "chickpea", "zucchini": "courgette", "courgettes": "courgette"
        ]
        let connectors: Set<String> = ["and", "with", "the", "of", "in", "from", "a", "an"]
        return normalized.split(separator: " ").map(String.init)
            .filter { !connectors.contains($0) }.map { equivalents[$0] ?? $0 }
    }
}
