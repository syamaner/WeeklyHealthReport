import Foundation
import FoodLedgerDomain

extension NutrientSet {
    /// The same values with every provenance naming `sourceID` instead. The label photo route's
    /// values come from the shared pasted derivation (docs/label-photo-ai-prefill-v1.md 17.1),
    /// which names its own source; nothing else about a value changes.
    func relabelling(sourceID: ExternalIdentifier) throws -> NutrientSet {
        func provenance(_ list: [NutrientProvenance]) -> [NutrientProvenance] {
            list.map { NutrientProvenance(sourceKind: $0.sourceKind, sourceID: sourceID, sourceReleaseID: $0.sourceReleaseID,
                                          recordID: $0.recordID, evidenceID: $0.evidenceID, capturedAt: $0.capturedAt,
                                          responseHash: $0.responseHash, manifestReference: $0.manifestReference, decisionID: $0.decisionID,
                                          assertionID: $0.assertionID, transforms: $0.transforms) }
        }
        func value(_ value: NutrientValue) throws -> NutrientValue {
            switch value {
            case let .measured(exact):
                .measured(try ExactNutrientValue(amount: exact.amount, unit: exact.unit, sourceValue: exact.sourceValue,
                                                 provenance: provenance(exact.provenance)))
            case let .augmented(exact):
                .augmented(try ExactNutrientValue(amount: exact.amount, unit: exact.unit, sourceValue: exact.sourceValue,
                                                  provenance: provenance(exact.provenance)))
            case let .bounded(bounds):
                .bounded(try NutrientBounds(lower: bounds.lower, upper: bounds.upper, lowerClosed: bounds.lowerClosed,
                                            upperClosed: bounds.upperClosed, origin: bounds.origin, unit: bounds.unit,
                                            sourceValue: bounds.sourceValue, provenance: provenance(bounds.provenance)))
            case .unknown: value
            }
        }
        return try NutrientSet(entries: entries.map { entry in
            try NutrientEntry(key: entry.key, value: value(entry.value), status: entry.status,
                              conflictCandidates: entry.conflictCandidates.map(value))
        })
    }
}
