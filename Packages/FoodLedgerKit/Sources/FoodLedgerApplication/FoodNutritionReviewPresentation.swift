import Foundation
import FoodLedgerDomain

/// A compact projection of existing source values and intake totals. No arithmetic
/// or missing-value inference is performed by the view.
public struct FoodNutritionReviewPresentation: Equatable, Sendable {
    public struct Row: Equatable, Sendable {
        public let key: NutrientKey
        public let title: String
        public let value: String
    }
    public static let mainKeys: [NutrientKey] = [.energyConsumed, .protein, .carbohydrates, .fatTotal]
    public let title: String
    public let basis: String
    public let mainRows: [Row]
    public let otherRows: [Row]
    public let isConsumed: Bool
    public let includesEstimates: Bool

    public init(nutrients: NutrientSet, sourceBasis: ResolutionBasis, edibleQuantity: PositiveQuantity?, totals: [FoodIntakeTotal]) {
        let compatible = edibleQuantity.map { Self.compatible($0.unit, with: sourceBasis) } ?? false
        isConsumed = compatible
        title = compatible ? "Nutrition for amount eaten" : "Nutrition"
        basis = compatible ? "For \(Self.number(edibleQuantity!.value)) \(edibleQuantity!.unit.rawValue) eaten" : Self.basisLabel(sourceBasis)
        includesEstimates = compatible && totals.contains { $0.includesEstimates }
        let rows = NutrientKey.allCases.map { key in
            let entry = nutrients.entries.first { $0.key == key }
            let value: String
            if compatible {
                if let amount = totals.first(where: { $0.key == key })?.knownAmount {
                    value = Self.consumedValue(amount, key: key)
                } else if let entry, case .bounded = entry.value { value = "Unavailable · source is bounded" }
                else { value = Self.unknownValue }
            } else { value = entry.map(Self.sourceValue) ?? Self.unknownValue }
            return Row(key: key, title: Self.label(key), value: value)
        }
        mainRows = Self.mainKeys.compactMap { key in rows.first { $0.key == key } }
        otherRows = rows.filter { !Self.mainKeys.contains($0.key) }
    }

    /// Display name in sentence case. Display copy only: stored keys and export names never change.
    /// Exhaustive, so a new key needs a deliberate name.
    public static func label(_ key: NutrientKey) -> String {
        switch key {
        case .energyConsumed: "Energy"
        case .protein: "Protein"
        case .carbohydrates: "Carbohydrates"
        case .fatTotal: "Fat"
        case .fatSaturated: "Saturated fat"
        case .fatMonounsaturated: "Monounsaturated fat"
        case .fatPolyunsaturated: "Polyunsaturated fat"
        case .fiber: "Fibre"
        case .sugar: "Sugar"
        case .cholesterol: "Cholesterol"
        case .vitaminA: "Vitamin A"
        case .thiaminB1: "Thiamin (B1)"
        case .riboflavinB2: "Riboflavin (B2)"
        case .niacinB3: "Niacin (B3)"
        case .pantothenicAcidB5: "Pantothenic acid (B5)"
        case .vitaminB6: "Vitamin B6"
        case .biotinB7: "Biotin (B7)"
        case .folateB9: "Folate (B9)"
        case .vitaminB12: "Vitamin B12"
        case .vitaminC: "Vitamin C"
        case .vitaminD: "Vitamin D"
        case .vitaminE: "Vitamin E"
        case .vitaminK: "Vitamin K"
        case .calcium: "Calcium"
        case .chloride: "Chloride"
        case .iron: "Iron"
        case .magnesium: "Magnesium"
        case .phosphorus: "Phosphorus"
        case .potassium: "Potassium"
        case .sodium: "Sodium"
        case .zinc: "Zinc"
        case .chromium: "Chromium"
        case .copper: "Copper"
        case .iodine: "Iodine"
        case .manganese: "Manganese"
        case .molybdenum: "Molybdenum"
        case .selenium: "Selenium"
        case .water: "Water"
        case .caffeine: "Caffeine"
        }
    }
    public static func sourceValue(_ entry: NutrientEntry) -> String {
        switch entry.value {
        case let .measured(value), let .augmented(value): "\(number(value.amount)) \(value.unit.rawValue)"
        case let .bounded(value):
            if let lower = value.lower, let upper = value.upper { "\(value.lowerClosed ? "[" : "(")\(number(lower))–\(number(upper))\(value.upperClosed ? "]" : ")") \(value.unit.rawValue)" }
            else if let upper = value.upper { "\(value.upperClosed ? "≤" : "<") \(number(upper)) \(value.unit.rawValue)" }
            else if let lower = value.lower { "\(value.lowerClosed ? "≥" : ">") \(number(lower)) \(value.unit.rawValue)" }
            else { "Bounded · see source" }
        case .unknown: unknownValue
        }
    }
    /// An unknown nutrient value, worded as in the Food Log and the saved entry.
    public static let unknownValue = "Unknown"
    /// The amount eaten in the shared display format: whole kcal, other units to one decimal.
    /// A positive amount too small to show is "Less than 0.1 g", never a zero.
    public static func consumedValue(_ amount: Double, key: NutrientKey) -> String {
        let unit = key.canonicalUnit.rawValue
        if key == .energyConsumed {
            return amount > 0 && amount < 0.5 ? "Less than 1 \(unit)" : "\(FoodDisplayNumber.kcal(amount)) \(unit)"
        }
        let smallest = 0.1
        return amount > 0 && amount < smallest / 2
            ? "Less than \(FoodDisplayNumber.amount(smallest)) \(unit)" : "\(FoodDisplayNumber.amount(amount)) \(unit)"
    }
    public static func number(_ value: Double) -> String {
        value.formatted(.number.precision(.significantDigits(1...6)))
    }
    public static func basisLabel(_ basis: ResolutionBasis) -> String {
        switch basis {
        case .per100Grams: "Per 100 g"
        case .per100Millilitres: "Per 100 mL"
        case let .perServing(q): "Per serving (\(number(q.value)) \(q.unit.rawValue))"
        case let .perUnit(q): "Per unit (\(number(q.value)) \(q.unit.rawValue))"
        case let .named(name, q): "\(name.value) (\(number(q.value)) \(q.unit.rawValue))"
        case .unknown: "Source basis not provided"
        }
    }
    private static func compatible(_ unit: QuantityUnit, with basis: ResolutionBasis) -> Bool {
        switch basis {
        case .per100Grams: unit == .grams
        case .per100Millilitres: unit == .millilitres
        case let .perServing(q), let .perUnit(q), let .named(_, q): unit == q.unit
        case .unknown: false
        }
    }
}
