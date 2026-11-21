import Foundation

/// The result of one B response row (CE1.6 rule 2; phase gate section 2.3). The merge-time codes
/// (`label_estimate`, `energy_mismatch`) are never in a capture's rows: they are in the choices item.
public enum ConfirmNutrientRowResult: String, Codable, Sendable, CaseIterable {
    case kept
    case unknownNutrient = "unknown_nutrient"
    case unit
    case value
    case impossibleValue = "impossible_value"
    case exceedsParent = "exceeds_parent"
    case duplicateNutrient = "duplicate_nutrient"
}

/// The nutrient basis a B request is made on. B is offered only for these two (CE1 section 2).
public enum ConfirmNutrientBasis: String, Codable, Sendable, CaseIterable {
    case per100Grams = "per_100_g"
    case per100Millilitres = "per_100_ml"
}

/// The pure request-and-reply row checks of CE1.6 rule 2. They depend only on the stored request (the
/// eligible keys, the basis and the known values) and the reply, so verification on reopen gives the
/// stored rows again.
public enum ConfirmNutrientRowCheck {
    /// One row as received: the nutrient text, the number as text, the unit text.
    public struct ReceivedRow: Equatable, Sendable {
        public let nutrient: String
        public let value: String
        public let unit: String

        public init(nutrient: String, value: String, unit: String) {
            self.nutrient = nutrient
            self.value = value
            self.unit = unit
        }
    }

    /// The largest amount a stored value may hold; anything larger is not a usable value.
    static let largestValue: Double = 1_000_000_000
    static let maximumKcal: Double = 900
    /// The child-parent pairs CE1.6 rule 2 checks.
    public static let parents: [NutrientKey: NutrientKey] = [
        .fatSaturated: .fatTotal, .fatMonounsaturated: .fatTotal, .fatPolyunsaturated: .fatTotal,
        .sugar: .carbohydrates
    ]

    /// Each row's result, in reply order. Codes are tried in this order: `unknown_nutrient`,
    /// `duplicate_nutrient` (every row of a repeated key), `unit`, `value`, `impossible_value`, then
    /// `exceeds_parent` against a known parent or a kept row of the same reply.
    public static func results(rows: [ReceivedRow], eligible: Set<NutrientKey>, basis: ConfirmNutrientBasis,
                               known: [NutrientKey: Double]) -> [ConfirmNutrientRowResult] {
        let counts = Dictionary(rows.map { ($0.nutrient, 1) }, uniquingKeysWith: +)
        var results: [ConfirmNutrientRowResult] = rows.map { row in
            guard let key = NutrientKey(rawValue: row.nutrient), eligible.contains(key) else { return .unknownNutrient }
            if counts[row.nutrient, default: 0] > 1 { return .duplicateNutrient }
            guard row.unit == key.canonicalUnit.rawValue else { return .unit }
            guard let amount = Double(row.value), amount.isFinite, amount >= 0, amount <= largestValue else { return .value }
            if isImpossible(amount, key: key, basis: basis) { return .impossibleValue }
            return .kept
        }
        // Parents: a known parent, else a kept row of the same reply.
        var keptAmounts: [NutrientKey: Double] = [:]
        for (index, row) in rows.enumerated() where results[index] == .kept {
            if let key = NutrientKey(rawValue: row.nutrient), let amount = Double(row.value) { keptAmounts[key] = amount }
        }
        for (index, row) in rows.enumerated() where results[index] == .kept {
            guard let key = NutrientKey(rawValue: row.nutrient), let parent = parents[key], let amount = Double(row.value),
                  let parentAmount = known[parent] ?? keptAmounts[parent] else { continue }
            if amount > parentAmount { results[index] = .exceedsParent }
        }
        return results
    }

    static func isImpossible(_ amount: Double, key: NutrientKey, basis: ConfirmNutrientBasis) -> Bool {
        if key == .energyConsumed { return amount > maximumKcal }
        guard basis == .per100Grams else { return false }
        switch key.canonicalUnit {
        case .grams: return amount > 100
        case .milligrams: return amount > 100_000
        case .micrograms: return amount > 100_000_000
        case .kilocalories, .millilitres: return false
        }
    }

    /// The merge-time parent check (phase gate section 2.4): B keys whose kept value is above a parent
    /// that the chosen label layer supplies.
    public static func mergeParentDropped(kept: [NutrientKey: Double], layer: [NutrientKey: Double]) -> Set<NutrientKey> {
        Set(kept.compactMap { key, amount in
            guard let parent = parents[key], let parentAmount = layer[parent] else { return nil }
            return amount > parentAmount ? key : nil
        })
    }
}

/// The CE1.6 rule 3 energy check, with its own constants so the domain never imports the frozen
/// label parser. A parity test pins these against `LabelArithmeticChecks`.
public enum EstimateEnergyCheck {
    public static let proteinKcalPerGram: Double = 4
    public static let carbohydrateKcalPerGram: Double = 4
    public static let fatKcalPerGram: Double = 9
    public static let fibreKcalPerGram: Double = 2
    public static let absoluteToleranceKcal: Double = 15
    public static let relativeTolerance: Double = 0.10

    /// The general form, and with fibre known the UK form (carbohydrate excludes fibre, fibre at
    /// 2 kcal/g) and the Taiwan form (carbohydrate includes fibre). Any form passing is enough.
    public static func passes(energy: Double, protein: Double, carbohydrate: Double, fat: Double, fibre: Double?) -> Bool {
        var forms = [proteinKcalPerGram * protein + carbohydrateKcalPerGram * carbohydrate + fatKcalPerGram * fat]
        if let fibre {
            forms.append(proteinKcalPerGram * protein + carbohydrateKcalPerGram * carbohydrate + fatKcalPerGram * fat
                         + fibreKcalPerGram * fibre)
            forms.append(proteinKcalPerGram * protein + carbohydrateKcalPerGram * (carbohydrate - fibre)
                         + fibreKcalPerGram * fibre + fatKcalPerGram * fat)
        }
        let allowed = max(absoluteToleranceKcal, relativeTolerance * energy)
        return forms.contains { abs($0 - energy) <= allowed }
    }

    /// The estimated keys among energy, protein, carbohydrate and fat to drop: none unless all four are
    /// available after the merge, at least one is an estimate, and no form passes.
    public static func dropped(merged: [NutrientKey: Double], estimated: Set<NutrientKey>) -> Set<NutrientKey> {
        let four: [NutrientKey] = [.energyConsumed, .protein, .carbohydrates, .fatTotal]
        guard let energy = merged[.energyConsumed], let protein = merged[.protein],
              let carbohydrate = merged[.carbohydrates], let fat = merged[.fatTotal],
              !estimated.isDisjoint(with: four) else { return [] }
        if passes(energy: energy, protein: protein, carbohydrate: carbohydrate, fat: fat, fibre: merged[.fiber]) { return [] }
        return estimated.intersection(four)
    }
}
