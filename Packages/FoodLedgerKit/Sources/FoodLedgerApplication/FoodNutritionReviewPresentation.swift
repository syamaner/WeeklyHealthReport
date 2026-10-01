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
                    value = "\(Self.number(amount)) \(key.canonicalUnit.rawValue)"
                } else if let entry, case .bounded = entry.value { value = "Unavailable · source is bounded" }
                else { value = "Not provided" }
            } else { value = entry.map(Self.sourceValue) ?? "Not provided" }
            return Row(key: key, title: Self.label(key), value: value)
        }
        mainRows = Self.mainKeys.compactMap { key in rows.first { $0.key == key } }
        otherRows = rows.filter { !Self.mainKeys.contains($0.key) }
    }

    public static func label(_ key: NutrientKey) -> String {
        switch key {
        case .energyConsumed: "Energy"
        case .protein: "Protein"
        case .carbohydrates: "Carbohydrate"
        case .fatTotal: "Fat"
        default: key.rawValue.replacingOccurrences(of: "_", with: " ").capitalized
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
        case .unknown: "Not provided"
        }
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
