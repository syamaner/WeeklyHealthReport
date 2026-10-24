import Foundation

public struct FoodIntakeContribution: Sendable {
    public let quantity: PositiveQuantity
    public let basis: ResolutionBasis
    public let nutrients: NutrientSet?
    public let quantityIsEstimate: Bool
    public init(quantity: PositiveQuantity, basis: ResolutionBasis, nutrients: NutrientSet?, quantityIsEstimate: Bool = false) {
        self.quantity = quantity; self.basis = basis; self.nutrients = nutrients; self.quantityIsEstimate = quantityIsEstimate
    }

    /// Whether the quantity can be scaled against the basis: the same predicate the summary
    /// applies, exposed so callers never keep a second scaling rule.
    public var isScalable: Bool { FoodIntakeSummary.scale(quantity: quantity, basis: basis) != nil }
}

public struct FoodIntakeTotal: Equatable, Sendable {
    public let key: NutrientKey
    public let knownAmount: Double?
    public let incompleteContributions: Int
    public let includesEstimates: Bool
    /// The sum overflowed (v4): `knownAmount` is nil and every contribution counts as incomplete,
    /// exactly as in v3, but the total is distinguishable from a day where nothing is known.
    public let overflowed: Bool

    public init(key: NutrientKey, knownAmount: Double?, incompleteContributions: Int, includesEstimates: Bool, overflowed: Bool = false) {
        self.key = key; self.knownAmount = knownAmount
        self.incompleteContributions = incompleteContributions; self.includesEstimates = includesEstimates
        self.overflowed = overflowed
    }
}

/// `food-intake-summary-v4`: v3 plus the `overflowed` flag (food daily export contract v1, #287).
/// v3 is v2 plus one rule: a contribution whose value is calculated (`NutrientDerivation.isCalculated`,
/// pasted-label conversions) sets `includesEstimates`. Values the user corrected or entered
/// (`manual_declaration`) do not (owner decision 13).
public struct FoodIntakeSummary: Equatable, Sendable {
    public static let version = "food-intake-summary-v4"
    public let itemCount: Int
    public let totals: [FoodIntakeTotal]

    public init(contributions: [FoodIntakeContribution]) {
        itemCount = contributions.count
        totals = NutrientKey.allCases.map { key in
            var sum = 0.0, known = 0, missing = 0
            var estimated = false
            for contribution in contributions {
                guard let scale = Self.scale(quantity: contribution.quantity, basis: contribution.basis),
                      let entry = contribution.nutrients?.entries.first(where: { $0.key == key }) else {
                    missing += 1; continue
                }
                estimated = estimated || contribution.quantityIsEstimate
                let amount: Double
                switch entry.value {
                case let .measured(value):
                    amount = value.amount
                    estimated = estimated || NutrientDerivation.isCalculated(entry.value)
                case let .augmented(value): amount = value.amount; estimated = true
                case .bounded, .unknown: missing += 1; continue
                }
                let scaled = amount * scale
                guard scaled.isFinite, (sum + scaled).isFinite else {
                    // An overflow invalidates the subtotal, not just one contribution.
                    return FoodIntakeTotal(key: key, knownAmount: nil, incompleteContributions: contributions.count, includesEstimates: estimated,
                                           overflowed: true)
                }
                sum += scaled; known += 1
            }
            return FoodIntakeTotal(key: key, knownAmount: known == 0 ? nil : sum,
                                   incompleteContributions: missing, includesEstimates: estimated)
        }
    }

    /// The factor from the basis to the quantity, or nil when the units differ or the basis is unknown.
    public static func scale(quantity: PositiveQuantity, basis: ResolutionBasis) -> Double? {
        let value: Double, unit: QuantityUnit
        switch basis {
        case .per100Grams: value = 100; unit = .grams
        case .per100Millilitres: value = 100; unit = .millilitres
        case let .perServing(portion), let .perUnit(portion), let .named(_, portion):
            value = portion.value; unit = portion.unit
        case .unknown: return nil
        }
        guard unit == quantity.unit else { return nil }
        let scale = quantity.value / value
        return scale.isFinite ? scale : nil
    }
}
