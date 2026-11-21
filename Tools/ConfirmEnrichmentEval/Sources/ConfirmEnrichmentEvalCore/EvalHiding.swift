import FoodLedgerApplication
import FoodLedgerDomain
import Foundation

/// CE1 section 12: for B, known values are hidden per case (energy, a macro, fibre, sodium and one
/// micronutrient at a time) and the model's estimate is compared with the hidden declared value. Hiding
/// turns each hidden key into an eligible unknown (`not_declared`) on the candidate before the app's own
/// request builder runs, so the request is exactly the one the app would send for that candidate.
public enum EvalHiding {
    public static func hide(_ nutrients: NutrientSet, keys: Set<NutrientKey>) throws -> NutrientSet {
        guard !keys.isEmpty else { return nutrients }
        return try NutrientSet(entries: nutrients.entries.map { entry in
            keys.contains(entry.key) ? try NutrientEntry(key: entry.key, value: .unknown(.notDeclared)) : entry
        })
    }

    /// The declared amount of a hidden key, kept privately for the scorer (PR 4a); nil when it was not known.
    public static func declared(_ nutrients: NutrientSet, key: NutrientKey) -> Double? {
        guard let entry = nutrients.entries.first(where: { $0.key == key }) else { return nil }
        switch entry.value {
        case let .measured(exact), let .augmented(exact): return exact.amount
        case .bounded, .unknown: return nil
        }
    }
}
