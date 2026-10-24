import Foundation

public struct FoodIntakeContribution: Sendable {
    public let quantity: PositiveQuantity
    public let basis: ResolutionBasis
    public let nutrients: NutrientSet?
    public let quantityIsEstimate: Bool
    /// A plain water entry in a day aggregation (v5, #304): its known values other than water (the
    /// reference's exact zeros) are left out of the day's totals, so water never makes a nutrient
    /// known or zero, and it is not a food entry. Its water and its unknown values (minerals,
    /// vitamins, caffeine) count as before. A single entry's own totals do not set this flag.
    public let isPlainWater: Bool
    public init(quantity: PositiveQuantity, basis: ResolutionBasis, nutrients: NutrientSet?, quantityIsEstimate: Bool = false,
                isPlainWater: Bool = false) {
        self.quantity = quantity; self.basis = basis; self.nutrients = nutrients; self.quantityIsEstimate = quantityIsEstimate
        self.isPlainWater = isPlainWater
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

/// `food-intake-summary-v6`: v5 plus one rule (#307, count-portion-estimate-v1, C6 and C13): a contribution
/// whose quantity is a source-backed estimate (a count portion guide size or the whole-milk volume
/// rule, `FoodQuantityEstimate`) sets `includesEstimates`, as an estimated weight already did.
/// v5 is v4 plus one rule (#304, health-food-and-water-v1.3): a plain water
/// contribution (`isPlainWater`) adds nothing to any total except water and makes no nutrient known;
/// its unknown values stay incomplete. `foodItemCount` counts the entries that are not plain water.
/// v4 is v3 plus the `overflowed` flag (food daily export contract v1, #287).
/// v3 is v2 plus one rule: a contribution whose value is calculated (`NutrientDerivation.isCalculated`,
/// pasted-label conversions) sets `includesEstimates`. Values the user corrected or entered
/// (`manual_declaration`) do not (owner decision 13).
public struct FoodIntakeSummary: Equatable, Sendable {
    public static let version = "food-intake-summary-v6"
    /// Every current entry, plain water included.
    public let itemCount: Int
    /// Current entries that are not plain water (v5).
    public let foodItemCount: Int
    public let totals: [FoodIntakeTotal]

    public init(contributions: [FoodIntakeContribution]) {
        itemCount = contributions.count
        foodItemCount = contributions.filter { !$0.isPlainWater }.count
        totals = NutrientKey.allCases.map { key in
            var sum = 0.0, known = 0, missing = 0
            var estimated = false
            for contribution in contributions {
                if contribution.isPlainWater, key != .water, Self.isKnown(key, in: contribution) { continue }
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

    /// Whether the contribution states a known amount for the key, scaled or not.
    private static func isKnown(_ key: NutrientKey, in contribution: FoodIntakeContribution) -> Bool {
        switch contribution.nutrients?.entries.first(where: { $0.key == key })?.value {
        case .measured, .augmented: true
        case .bounded, .unknown, nil: false
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
