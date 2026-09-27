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
        matchesFat(query: query, fatPer100Grams: fatPer100Grams(candidate))
    }
    /// Adapter ranking may use a declared value before constructing bounded candidates.
    public static func matchesFat(query: ParsedFoodQuery, fatPer100Grams actual: Double?) -> Bool {
        guard let requested = query.attributes["fat_percent"].flatMap(Double.init),
              let actual else { return false }
        return abs(actual - requested) < 0.000001
    }
    public static func note(query: ParsedFoodQuery, candidate: PopulatedFoodCandidate) -> String? {
        guard let requested = query.attributes["fat_percent"] else { return nil }
        guard let actual = fatPer100Grams(candidate) else {
            return "Requested \(requested)% fat; source fat on a 100g basis is unavailable. Variant not verified."
        }
        if matchesFat(query: query, candidate: candidate) {
            return "Source reports \(actual)g fat per 100g, matching your requested percentage. Product variant still needs review."
        }
        return "Alternative: source reports \(actual)g fat per 100g; you requested \(requested)% fat."
    }
}
