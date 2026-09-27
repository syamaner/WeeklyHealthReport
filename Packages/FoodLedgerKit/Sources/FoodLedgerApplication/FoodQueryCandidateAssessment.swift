import FoodLedgerDomain

/// Evidence-based ranking hints only: no nutrient changes or product-identity assertions.
public enum FoodQueryCandidateAssessment {
    public static func fatPer100Grams(_ candidate: PopulatedFoodCandidate) -> Double? {
        guard candidate.candidate.identity.servingBasis == .per100Grams,
              let entry = candidate.candidate.nutrients.entries.first(where: { $0.key == .fatTotal }),
              entry.status == .resolved else { return nil }
        switch entry.value {
        case let .measured(value), let .augmented(value):
            guard value.unit == .grams else { return nil }
            return value.amount
        case .bounded, .unknown: return nil
        }
    }
    public static func matchesFat(query: ParsedFoodQuery, candidate: PopulatedFoodCandidate) -> Bool {
        guard let requested = query.attributes["fat_percent"].flatMap(Double.init),
              let actual = fatPer100Grams(candidate) else { return false }
        return abs(actual - requested) < 0.000001
    }
    public static func note(query: ParsedFoodQuery, candidate: PopulatedFoodCandidate) -> String? {
        let requestedTerms = Set(GenericFoodRankingPolicy.terms(query.food ?? query.original))
        let candidateTerms = Set(GenericFoodRankingPolicy.terms(candidate.name.value))
        let typeNote: String? = requestedTerms.contains("greek") && requestedTerms.contains("style") != candidateTerms.contains("style")
            ? "Tentative alternative: Greek yoghurt and Greek-style yoghurt are different types. Compare the catalogue name before accepting." : nil
        guard let requested = query.attributes["fat_percent"] else { return typeNote }
        if let typeNote { return typeNote + " Requested \(requested)% fat is not an exact product-variant match." }
        guard let actual = fatPer100Grams(candidate) else {
            return "Requested \(requested)% fat; source fat on a 100g basis is unavailable. Variant not verified."
        }
        if matchesFat(query: query, candidate: candidate) {
            return "Source reports \(actual)g fat per 100g, matching your requested percentage. Product variant still needs review."
        }
        return "Alternative: source reports \(actual)g fat per 100g; you requested \(requested)% fat."
    }
}
