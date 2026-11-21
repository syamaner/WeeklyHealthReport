import FoodLedgerDomain

/// CE1 section 12 and docs/confirm-enrichment-openrouter-v1-phase.md section 9.
public enum EvalNutrientBars {
    public enum Group: String, CaseIterable, Sendable {
        case energy, macronutrients, fibreAndSodium = "fibre_and_sodium", micronutrients, unmeasured

        var limit: Double? {
            switch self {
            case .energy, .macronutrients: 0.20
            case .fibreAndSodium: 0.35
            case .micronutrients: 0.50
            case .unmeasured: nil
            }
        }
    }

    public struct Rule: Equatable, Sendable {
        public let group: Group
        public let floor: Double?
    }

    public static func rule(_ key: NutrientKey) -> Rule {
        switch key {
        case .energyConsumed: Rule(group: .energy, floor: 5)
        case .carbohydrates, .protein, .fatTotal, .fatSaturated, .fatMonounsaturated, .fatPolyunsaturated, .sugar:
            Rule(group: .macronutrients, floor: 0.5)
        case .fiber: Rule(group: .fibreAndSodium, floor: 0.5)
        case .sodium: Rule(group: .fibreAndSodium, floor: 5)
        case .cholesterol, .water, .caffeine: Rule(group: .unmeasured, floor: nil)
        // Annex XIII, Part A of Regulation (EU) No 1169/2011, in each key's canonical unit.
        case .vitaminA: micronutrient(800)
        case .thiaminB1: micronutrient(1.1)
        case .riboflavinB2: micronutrient(1.4)
        case .niacinB3: micronutrient(16)
        case .pantothenicAcidB5: micronutrient(6)
        case .vitaminB6: micronutrient(1.4)
        case .biotinB7: micronutrient(50)
        case .folateB9: micronutrient(200)
        case .vitaminB12: micronutrient(2.5)
        case .vitaminC: micronutrient(80)
        case .vitaminD: micronutrient(5)
        case .vitaminE: micronutrient(12)
        case .vitaminK: micronutrient(75)
        case .calcium: micronutrient(800)
        case .chloride: micronutrient(800)
        case .iron: micronutrient(14)
        case .magnesium: micronutrient(375)
        case .phosphorus: micronutrient(700)
        case .potassium: micronutrient(2_000)
        case .zinc: micronutrient(10)
        case .chromium: micronutrient(40)
        case .copper: micronutrient(1)
        case .iodine: micronutrient(150)
        case .manganese: micronutrient(2)
        case .molybdenum: micronutrient(50)
        case .selenium: micronutrient(55)
        }
    }

    private static func micronutrient(_ referenceIntake: Double) -> Rule {
        Rule(group: .micronutrients, floor: referenceIntake / 10)
    }

    public static func relativeError(key: NutrientKey, estimate: Double, declared: Double) -> Double? {
        guard let floor = rule(key).floor, estimate.isFinite, estimate >= 0, declared.isFinite, declared >= 0 else { return nil }
        return abs(estimate - declared) / max(declared, floor)
    }

    public static func hiddenKeys(declared: Set<NutrientKey>, caseIndex: Int) -> [NutrientKey] {
        guard caseIndex >= 0 else { return [] }
        let ordered = declared.sorted { $0.rawValue < $1.rawValue }
        let macros = ordered.filter { rule($0).group == .macronutrients }
        let micros = ordered.filter { rule($0).group == .micronutrients }
        let macro = macros.isEmpty ? nil : macros[caseIndex % macros.count]
        let micro = micros.isEmpty ? nil : micros[caseIndex % micros.count]
        return [.energyConsumed, macro, .fiber, .sodium, micro].compactMap { key in
            guard let key, declared.contains(key) else { return nil }
            return key
        }
    }

    /// Open Food Facts stores declared salt in grams per 100 g or 100 ml.
    public static func sodiumMilligrams(saltGrams: Double) -> Double? {
        let sodium = saltGrams / 2.5 * 1_000
        return sodium.isFinite && sodium >= 0 ? sodium : nil
    }
}
