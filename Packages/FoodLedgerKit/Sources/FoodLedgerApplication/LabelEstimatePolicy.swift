import Foundation
import FoodLedgerDomain

/// Which bundled generic rows may estimate a labelled bar's unprinted nutrients
/// (`label-estimate-compatibility-v1`, #383, docs/label-estimate-merge-v1.md rules 1 to 3).
/// A per-row predicate: the result never depends on which other rows are present.
public enum LabelEstimateCompatibility {
    public static let version = "label-estimate-compatibility-v1"

    /// USDA SR Legacy 2018-04-01 FDC 170273 "Chocolate, dark, 70-85% cacao solids": the
    /// owner-approved estimate for bars above 85% and below 100% cocoa.
    public static let nearestBandRecordID =
        "usda-legacy:2018-04-01:sha256:0fe8ae486a2c8eb42cb96413f058deb51863a46c8fb8eeb4b1fb45006dd338ef:fdc:170273"

    public enum PrefillOrigin: String, Codable, Sendable {
        case name
        case pastedText = "pasted_text"
        case typed
    }

    /// Rule 1 (route aside, which the caller checks): a chocolate that is not milk, white or
    /// ruby, on a basis with a known mass.
    public static func offersEstimate(name: String, basis: ResolutionBasis) -> Bool {
        let terms = Set(GenericFoodRankingPolicy.terms(name))
        return terms.contains("chocolate") && terms.isDisjoint(with: CocoaPercentPolicy.chocolateTypes)
            && LabelEstimateMerge.grams(in: basis) != nil
    }

    /// Rule 2: one stated cocoa percentage from the name, else from the pasted label text.
    /// A range, several values or none give no pre-fill.
    public static func prefill(name: String, pastedText: String?) -> (value: Double, origin: PrefillOrigin)? {
        if let value = statedPercent(name) { return (value, .name) }
        if let pastedText, let value = statedPercent(pastedText) { return (value, .pastedText) }
        return nil
    }

    /// Rule 2: the confirmed or typed value is 1 to 100, whole or one decimal place.
    public static func isValidPercent(_ value: Double) -> Bool {
        value.isFinite && value >= 1 && value <= 100 && (value * 10).rounded() == value * 10
    }

    /// Rule 3 for one row and a confirmed percentage.
    public static func isCompatible(_ row: PopulatedFoodCandidate, cocoaPercent p: Double) -> Bool {
        guard isValidPercent(p), isBundledGeneric(row.candidate.nutrients) else { return false }
        let terms = Set(GenericFoodRankingPolicy.terms(row.name.value))
        guard terms.contains("chocolate"), terms.isDisjoint(with: CocoaPercentPolicy.chocolateTypes) else { return false }
        let recordID = row.candidate.recordID.value
        if p == 100, recordID == CocoaPercentPolicy.estimate100RecordID { return true }
        if p > 85, p < 100, recordID == nearestBandRecordID { return true }
        if case let .declared(lower, upper)? = CocoaPercentPolicy.band(row), lower <= upper {
            return (lower...upper).contains(p)
        }
        return false
    }

    /// Every stated value comes from a bundled generic composition release; personal-library
    /// rows and aliases carry other provenance and are refused.
    static func isBundledGeneric(_ nutrients: NutrientSet) -> Bool {
        let provenance = nutrients.entries.flatMap(\.value.provenance)
        return !provenance.isEmpty && provenance.allSatisfy { $0.sourceKind == .genericCompositionDataset && $0.recordID != nil }
    }

    private static func statedPercent(_ text: String) -> Double? {
        let lowered = text.lowercased()
        var values: Set<Double> = []
        if case let .declared(lower, upper)? = CocoaPercentPolicy.band(name: text, description: nil, recordID: nil) {
            guard lower == upper else { return nil }
            values.insert(lower)
        }
        // Labels usually write "Cocoa solids: 70% minimum" rather than "70% cocoa".
        let pattern = #"(?:cocoa|cacao)\s+solids[^0-9%\n]{0,12}(\d+(?:\.\d+)?)\s*%"#
        if let regex = try? NSRegularExpression(pattern: pattern) {
            for match in regex.matches(in: lowered, range: NSRange(lowered.startIndex..., in: lowered)) {
                guard let range = Range(match.range(at: 1), in: lowered), let value = Double(lowered[range]) else { continue }
                values.insert(value)
            }
        }
        guard values.count == 1, let value = values.first, isValidPercent(value) else { return nil }
        return value
    }
}

/// Fills a label's unknown nutrients from one compatible generic row (`label-estimate-merge-v1`,
/// #383, docs/label-estimate-merge-v1.md rule 4). Known, bounded and printed-zero label values
/// always win; generic values are scaled to the label's basis and keep their provenance.
public enum LabelEstimateMerge {
    public static let version = "label-estimate-merge-v1"
    public static let basisTransformID = "label-estimate-basis-scale"

    public struct Result: Equatable, Sendable {
        public let nutrients: NutrientSet
        /// Keys filled from the generic row, in catalogue order.
        public let filledKeys: [NutrientKey]
    }

    /// Nil when either basis has no gram mass (rule 1) or the generic row is not per 100 g.
    public static func merge(label: NutrientSet, labelBasis: ResolutionBasis,
                             generic: NutrientSet, genericBasis: ResolutionBasis) throws -> Result? {
        guard let labelGrams = grams(in: labelBasis), genericBasis == .per100Grams else { return nil }
        let factor = labelGrams / 100
        var entries: [NutrientEntry] = []
        var filled: [NutrientKey] = []
        for (labelEntry, genericEntry) in zip(label.entries, generic.entries) {
            guard case .unknown = labelEntry.value, let value = try scaled(genericEntry.value, by: factor) else {
                entries.append(labelEntry)
                continue
            }
            entries.append(try NutrientEntry(key: labelEntry.key, value: value))
            filled.append(labelEntry.key)
        }
        return Result(nutrients: try NutrientSet(entries: entries), filledKeys: filled)
    }

    static func grams(in basis: ResolutionBasis) -> Double? {
        switch basis {
        case .per100Grams: 100
        case let .perServing(quantity), let .perUnit(quantity), let .named(_, quantity):
            quantity.unit == .grams ? quantity.value : nil
        case .per100Millilitres, .unknown: nil
        }
    }

    private static func scaled(_ value: NutrientValue, by factor: Double) throws -> NutrientValue? {
        switch value {
        case let .measured(exact), let .augmented(exact):
            return .augmented(try ExactNutrientValue(amount: exact.amount * factor, unit: exact.unit,
                                                     sourceValue: exact.sourceValue, provenance: try provenance(exact.provenance, factor)))
        case let .bounded(bounds):
            return .bounded(try NutrientBounds(lower: bounds.lower.map { $0 * factor }, upper: bounds.upper.map { $0 * factor },
                                               lowerClosed: bounds.lowerClosed, upperClosed: bounds.upperClosed, origin: .augmented,
                                               unit: bounds.unit, sourceValue: bounds.sourceValue,
                                               provenance: try provenance(bounds.provenance, factor)))
        case .unknown:
            return nil
        }
    }

    /// The generic provenance verbatim, plus the basis scale when the bases differ.
    private static func provenance(_ provenance: [NutrientProvenance], _ factor: Double) throws -> [NutrientProvenance] {
        guard factor != 1 else { return provenance }
        let transform = NutrientTransform(transformID: try LedgerText(basisTransformID), transformVersion: try LedgerText("v1"))
        return provenance.map {
            NutrientProvenance(sourceKind: $0.sourceKind, sourceID: $0.sourceID, sourceReleaseID: $0.sourceReleaseID,
                               recordID: $0.recordID, evidenceID: $0.evidenceID, capturedAt: $0.capturedAt,
                               responseHash: $0.responseHash, manifestReference: $0.manifestReference,
                               decisionID: $0.decisionID, assertionID: $0.assertionID, transforms: $0.transforms + [transform])
        }
    }
}
