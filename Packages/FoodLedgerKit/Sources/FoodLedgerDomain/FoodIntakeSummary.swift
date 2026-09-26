import Foundation

public struct FoodIntakeContribution: Sendable {
    public let quantity: PositiveQuantity
    public let basis: ResolutionBasis
    public let nutrients: NutrientSet?
    public init(quantity: PositiveQuantity, basis: ResolutionBasis, nutrients: NutrientSet?) {
        self.quantity = quantity; self.basis = basis; self.nutrients = nutrients
    }
}

public struct FoodIntakeTotal: Equatable, Sendable {
    public let key: NutrientKey
    public let knownAmount: Double?
    public let incompleteContributions: Int
    public let includesEstimates: Bool
}

public struct FoodIntakeSummary: Equatable, Sendable {
    public static let version = "food-intake-summary-v1"
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
                let amount: Double
                switch entry.value {
                case let .measured(value): amount = value.amount
                case let .augmented(value): amount = value.amount; estimated = true
                case .bounded, .unknown: missing += 1; continue
                }
                let scaled = amount * scale
                guard scaled.isFinite, (sum + scaled).isFinite else {
                    // An overflow invalidates the subtotal, not just one contribution.
                    return FoodIntakeTotal(key: key, knownAmount: nil, incompleteContributions: contributions.count, includesEstimates: estimated)
                }
                sum += scaled; known += 1
            }
            return FoodIntakeTotal(key: key, knownAmount: known == 0 ? nil : sum,
                                   incompleteContributions: missing, includesEstimates: estimated)
        }
    }

    private static func scale(quantity: PositiveQuantity, basis: ResolutionBasis) -> Double? {
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
