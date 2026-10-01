import FoodLedgerDomain

public protocol FoodSearchCoverageAssessing: Sendable {
    func assess(_ outcome: GenericFoodSearchOutcome, for request: GenericFoodSearchRequest) -> [FoodSearchCandidateCoverage]
}

/// Conservative development policy. Lexical matching never establishes strong identity.
/// Only an exact, previously confirmed local alias is strong; no save rule is relaxed.
public struct ConservativeFoodSearchCoverageAssessment: FoodSearchCoverageAssessing {
    public static let version = "food_search_coverage_v1"
    public static let requiredNutrients: [NutrientKey] = [.energyConsumed, .protein, .carbohydrates, .fatTotal, .sodium]
    public init() {}

    public func assess(_ outcome: GenericFoodSearchOutcome, for request: GenericFoodSearchRequest) -> [FoodSearchCandidateCoverage] {
        guard case let .confirmation(route) = outcome else { return [] }
        return route.matches.map { match in
            let candidate = match.candidate.candidate
            let incompatible = Self.hasHardContradiction(candidate, request: request)
            let complete = Self.requiredNutrients.allSatisfy { key in
                guard let entry = candidate.nutrients.entries.first(where: { $0.key == key }), entry.status == .resolved else { return false }
                switch entry.value {
                case .measured, .augmented: return true
                case .bounded, .unknown: return false
                }
            }
            let basis = Self.basis(candidate.identity.servingBasis, quantity: request.parsedQuery.quantity)
            let preparationUnknown = Self.requestedPreparation(request) != nil && candidate.identity.preparation.kind == .unknown
            return FoodSearchCandidateCoverage(
                match: incompatible ? .incompatible : route.reuse != nil && match.isExactName && !preparationUnknown ? .strong : .uncertain,
                nutrition: complete ? .complete : .incomplete,
                basis: incompatible ? .incompatible : preparationUnknown ? .unknown : basis,
                quantity: request.parsedQuery.quantity == nil ? .needsUserInput : .ready)
        }
    }

    /// Unknown metadata remains eligible for explicit review; known contradictions do not.
    public static func hasHardContradiction(_ candidate: ProviderNeutralCandidate, request: GenericFoodSearchRequest) -> Bool {
        let expected = request.identity
        let actual = candidate.identity
        if let value = requestedPreparation(request), value.kind != .unknown, actual.preparation.kind != .unknown, value != actual.preparation { return true }
        if let value = expected.bone, value != .unknown, actual.bone != .unknown, value != actual.bone { return true }
        if let value = expected.skin, value != .unknown, actual.skin != .unknown, value != actual.skin { return true }
        if let value = expected.drained, value != .unknown, actual.drained != .unknown, value != actual.drained { return true }
        if let value = expected.fortification, value != .unknown, actual.fortification != .unknown, value != actual.fortification { return true }
        if let value = expected.packingMedium, value != .unknown, actual.packingMedium != .unknown, value != actual.packingMedium { return true }
        if let value = expected.servingBasis, value != .unknown, actual.servingBasis != .unknown, value != actual.servingBasis { return true }
        if let value = expected.edibleQuantity, value != .unknown, candidate.edibleQuantity != .unknown, value != candidate.edibleQuantity { return true }
        return false
    }

    static func requestedPreparation(_ request: GenericFoodSearchRequest) -> PreparationState? {
        if let explicit = request.identity.preparation, explicit.kind != .unknown { return explicit }
        guard let kind = request.interpretation.preparation else { return nil }
        return try? PreparationState(kind: kind)
    }

    private static func basis(_ basis: ResolutionBasis, quantity: ParsedFoodQuery.Quantity?) -> FoodSearchCandidateCoverage.Basis {
        let unit: String
        switch basis {
        case .per100Grams: unit = "g"
        case .per100Millilitres: unit = "ml"
        case let .perServing(amount), let .perUnit(amount), let .named(_, amount):
            switch amount.unit { case .grams: unit = "g"; case .millilitres: unit = "ml"; case .count: unit = "count" }
        case .unknown: return .unknown
        }
        guard let quantity else { return .compatible }
        // Source basis only: do not infer density or reusable portion weight here.
        return quantity.unit == unit ? .compatible : .incompatible
    }
}
