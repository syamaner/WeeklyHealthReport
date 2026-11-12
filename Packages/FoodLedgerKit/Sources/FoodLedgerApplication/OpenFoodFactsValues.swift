import Foundation
import FoodLedgerDomain

/// Open Food Facts values label v1 (docs/off-values-label-v1.md): which estimated values are an
/// Open Food Facts product's own, so presentation can name the source instead of a bare
/// "Estimate". Pure; it changes no stored value and no estimate status.
public enum OpenFoodFactsValues {
    /// An `augmented` value, or a bound of `augmented` origin, whose provenance names only the
    /// Open Food Facts product dataset (rule 1).
    public static func isProductValue(_ value: NutrientValue) -> Bool {
        switch value {
        case .augmented: break
        case let .bounded(bounds) where bounds.origin == .augmented: break
        default: return false
        }
        let provenance = value.provenance
        return !provenance.isEmpty && provenance.allSatisfy {
            $0.sourceKind == .exactProductDataset && $0.sourceID.value == OpenFoodFactsEstimateSource.sourceID
        }
    }

    /// The keys whose value is an Open Food Facts value (rule 3).
    public static func productValueKeys(_ nutrients: NutrientSet) -> Set<NutrientKey> {
        Set(nutrients.entries.filter { isProductValue($0.value) }.map(\.key))
    }

    /// The values' only estimates are Open Food Facts values: at least one, every other
    /// `augmented` value or bound is one too, and no measured value is calculated (rule 2).
    public static func areTheOnlyEstimates(_ nutrients: NutrientSet) -> Bool {
        var any = false
        for entry in nutrients.entries {
            switch entry.value {
            case .augmented:
                guard isProductValue(entry.value) else { return false }
                any = true
            case let .bounded(bounds) where bounds.origin == .augmented:
                guard isProductValue(entry.value) else { return false }
                any = true
            case .measured:
                if NutrientDerivation.isCalculated(entry.value) { return false }
            case .bounded, .unknown: continue
            }
        }
        return any
    }

    /// The row and Recent foods rule (rule 2): "Open Food Facts estimate" replaces "Estimate" only
    /// when the entry would read "Estimate" for no reason other than its Open Food Facts values.
    /// The caller also requires that the entry reads "Estimate" at all and is not "Partly estimated".
    public static func namesSource(valuesAreOnlyEstimates: Bool, isEstimate: Bool, quantityIsEstimate: Bool,
                                   energyBoundIsCalculated: Bool) -> Bool {
        valuesAreOnlyEstimates && !isEstimate && !quantityIsEstimate && !energyBoundIsCalculated
    }
}
