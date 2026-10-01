import Foundation
import FoodLedgerDomain

/// One deterministic application interpretation. No source identity, nutrition or
/// conversion is asserted by language. The legacy parse remains available for diagnostics.
public struct FoodQueryInterpretation: Equatable, Sendable {
    public static let version = "food-query-interpretation-v1"
    public struct Component: Equatable, Sendable {
        public let text: String
        /// UTF-16 offsets in originalText, not code-point or Character offsets.
        public let startUTF16: Int
        public let lengthUTF16: Int
    }
    public let originalText: String
    public let baseline: ParsedFoodQuery
    public let parsedQuery: ParsedFoodQuery
    public let allowsDiscovery: Bool
    public let preparation: PreparationKind?
    public let components: [Component]
    public let quantitySuggestion: ParsedFoodQuery.Quantity?
    public var needsCompositionReview: Bool { !components.isEmpty || baseline.reasons.contains("recipe_unknown") }
    public var retrievalText: String {
        // Component modifiers must remain attached in original wording, not promoted
        // to global constraints. A description is not a verified decomposition.
        let terms = FoodQueryPreparationPolicy.foodTerms(for: parsedQuery)
        if needsCompositionReview, let method = baseline.attributes["preparation"],
           method != parsedQuery.attributes["preparation"],
           !terms.lowercased().contains(method) { return terms + " " + method }
        return terms
    }

    public init(_ original: String) {
        originalText = original
        let baseline = FoodQueryParser.parse(original)
        self.baseline = baseline
        let relaxed: Set<String> = ["recipe_unknown", "multiple_foods_or_recipe", "portion_requires_confirmation",
            "fraction_requires_portion_confirmation", "unresolved_number", "quantity_is_not_exact",
            "quantity_scope_ambiguous", "competing_quantities", "count_and_mass_need_basis_confirmation",
            "percentage_meaning_unknown", "identity_requires_review"]
        // Named words are discovery terms, not a claim that the user described food.
        let stop: Set<String> = ["half", "a", "an", "of", "and", "with", "g", "kg", "ml", "l",
            "grams", "count", "servings", "about", "less", "than", "more", "under", "over"]
        let words = original.lowercased().split { !$0.isLetter }.map(String.init)
        let meaningful = words.contains { $0.count >= 2 && !stop.contains($0) }
        let reasons = Set(baseline.reasons)
        let signedNegative = original.range(of: #"(?<![\w])[−–—-]\s*(?:\d|[½¼¾]|\.\d)"#, options: .regularExpression) != nil
        allowsDiscovery = meaningful && !signedNegative && baseline.route != .reject &&
            (baseline.allowsCandidateDiscovery || reasons.isSubset(of: relaxed))

        let regex = try! NSRegularExpression(pattern: #"\b(?:with|plus|containing|without|and)\b|(?<!\d),|,(?!\d)"#, options: .caseInsensitive)
        // Recognised edible-portion phrases and bread names are identity wording,
        // not recipe components. Retain their established parser behaviour.
        let bread = ["rye and wheat bread", "rye and wholemeal bread"].contains(baseline.food ?? "")
        let separators = bread ? [] : regex.matches(in: original, range: NSRange(original.startIndex..., in: original)).filter { match in
            guard let literal = Range(match.range, in: original),
                  let suffix = Range(NSRange(location: match.range.location + match.range.length,
                    length: original.utf16.count - match.range.location - match.range.length), in: original) else { return true }
            let connector = original[literal].lowercased()
            let descriptor = String(original[suffix]).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if ["with", "without"].contains(connector),
               baseline.attributes["skin"] != nil || baseline.attributes["edible_portion"] != nil,
               descriptor.range(of: #"^(?:skin|seed)\b"#, options: .regularExpression) != nil { return false }
            if connector == ",", ["raw", "uncooked", "cooked", "boiled", "roasted", "drained", "whole", "pasteurised", "average"].contains(descriptor) { return false }
            return true
        }
        var parts: [Component] = []
        if let first = separators.first {
            let starts = [0] + separators.map { $0.range.location + $0.range.length }
            let ends = separators.map { $0.range.location } + [original.utf16.count]
            for (start, end) in zip(starts, ends) {
                guard let range = Range(NSRange(location: start, length: end - start), in: original) else { continue }
                let text = String(original[range]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty { parts.append(Component(text: text, startUTF16: start, lengthUTF16: end - start)) }
            }
            // Only preparation within the first component can constrain the main food.
            let prefix = String(original.prefix(utf16Count: first.range.location))
            let head = FoodQueryParser.parse(prefix)
            preparation = FoodQueryPreparationPolicy.kind(for: head)
        } else { preparation = FoodQueryPreparationPolicy.kind(for: baseline) }
        components = parts
        let bound = original.range(of: #"\b(?:less than|more than|under|over|below|above|up to|at most|at least|about|roughly|approximately|around|between)\b|[≤≥<>≈£$€¥]"#,
            options: [.regularExpression, .caseInsensitive]) != nil
        let automatic = allowsDiscovery && !bound && parts.isEmpty ? baseline.quantity : nil
        var attributes = baseline.attributes
        if !parts.isEmpty {
            if let first = parts.first { attributes = FoodQueryParser.parse(first.text).attributes }
        }
        var food = baseline.food
        // A recovered scalar is review-only. No food dictionary or source-serving assumption.
        var suggestion: ParsedFoodQuery.Quantity?
        if automatic == nil, allowsDiscovery, !bound, parts.isEmpty,
           let match = try? NSRegularExpression(pattern: #"^\s*(half|(?:\d+(?:\.\d+)?|\.\d+)(?:/\d+)?|½)\s+(?:of\s+)?(?:an?\s+)?(.+)$"#, options: .caseInsensitive).firstMatch(in: original, range: NSRange(original.startIndex..., in: original)),
           let numberRange = Range(match.range(at: 1), in: original),
           let targetRange = Range(match.range(at: 2), in: original),
           let value = FoodAmountTextParser.parse(String(original[numberRange])) {
            let target = String(original[targetRange])
            let targetParse = FoodQueryParser.parse(target)
            if targetParse.quantity == nil, targetParse.allowsCandidateDiscovery,
               target.range(of: #"\b(?:sugar|ice|fat|percent|price|g|kg|ml|l|mg|mcg|ug|oz|ounces?|lb|lbs|pounds?|cups?|bowls?|servings?|pieces?|kcal|kj|cm)\b"#, options: [.regularExpression, .caseInsensitive]) == nil {
                suggestion = .init(value: value, unit: "count")
                food = targetParse.food
                attributes = targetParse.attributes
            }
        }
        parsedQuery = ParsedFoodQuery(original: original, food: food, attributes: attributes,
            quantity: automatic, route: baseline.route, reasons: baseline.reasons)
        quantitySuggestion = suggestion
    }
}

private extension String {
    func prefix(utf16Count: Int) -> Substring {
        guard let range = Range(NSRange(location: 0, length: utf16Count), in: self) else { return self[...] }
        return self[range]
    }
}
