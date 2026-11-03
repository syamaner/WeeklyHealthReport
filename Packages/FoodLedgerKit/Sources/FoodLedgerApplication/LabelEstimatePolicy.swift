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

    /// The origin saved with the confirmed percentage (a domain type, `CocoaPercentOrigin`).
    public typealias PrefillOrigin = CocoaPercentOrigin

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
        LabelEstimateAssertion.isValidCocoaPercent(value)
    }

    /// Rule 3 for one row and a confirmed percentage.
    public static func isCompatible(_ row: PopulatedFoodCandidate, cocoaPercent p: Double) -> Bool {
        isCompatible(name: row.name.value, variant: row.variant?.value, recordID: row.candidate.recordID.value,
                     nutrients: row.candidate.nutrients, cocoaPercent: p)
    }

    /// Rule 3 from a row's stored facts, so save and reopen share one rule (reopen has the
    /// decision's record and nutrients and the name and variant on the cocoa assertion).
    public static func isCompatible(name: String, variant: String?, recordID: String, nutrients: NutrientSet,
                                    cocoaPercent p: Double) -> Bool {
        guard isValidPercent(p), isBundledGeneric(nutrients) else { return false }
        let terms = Set(GenericFoodRankingPolicy.terms(name))
        guard terms.contains("chocolate"), terms.isDisjoint(with: CocoaPercentPolicy.chocolateTypes) else { return false }
        if p == 100, recordID == CocoaPercentPolicy.estimate100RecordID { return true }
        if p > 85, p < 100, recordID == nearestBandRecordID { return true }
        if case let .declared(lower, upper)? = CocoaPercentPolicy.band(name: name, description: variant, recordID: recordID),
           lower <= upper {
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

/// The estimate a user chose on Confirm before Log (docs/label-estimate-merge-v1.md section 5):
/// one compatible generic row with its evidence and release, and the confirmed cocoa percentage.
public struct LabelEstimateChoice: Equatable, Sendable {
    public let generic: PopulatedFoodCandidate
    public let evidence: [CaptureEvidence]
    public let sourceRelease: SourceRelease
    public let cocoaPercent: Double
    public let origin: CocoaPercentOrigin

    public init(generic: PopulatedFoodCandidate, evidence: [CaptureEvidence], sourceRelease: SourceRelease,
                cocoaPercent: Double, origin: CocoaPercentOrigin) {
        self.generic = generic
        self.evidence = evidence
        self.sourceRelease = sourceRelease
        self.cocoaPercent = cocoaPercent
        self.origin = origin
    }
}

/// The checks shared by save and reopen of an estimate layer (sections 5 and 6). The bundle is
/// never re-read: the stored generic row and its stored release are the whole input.
enum LabelEstimateLayer {
    /// The merged nutrients for a label candidate and a generic row, or nil when the label offers no
    /// estimate, the row is not a bundled generic row of `release`, or a copied value would name
    /// another release or record. Rule 3 itself is the caller's (`isCompatible`).
    static func merged(label: PopulatedFoodCandidate, generic: ProviderNeutralCandidate, release: SourceRelease,
                       cocoaPercent: Double) throws -> NutrientSet? {
        guard LabelEstimateCompatibility.offersEstimate(name: label.name.value, basis: label.candidate.identity.servingBasis),
              LabelEstimateCompatibility.isValidPercent(cocoaPercent),
              LabelEstimateCompatibility.isBundledGeneric(generic.nutrients),
              release.sourceReleaseID == generic.sourceReleaseID, generic.sourceReleaseID != label.candidate.sourceReleaseID,
              generic.nutrients.entries.flatMap(\.value.provenance).allSatisfy({
                  $0.sourceReleaseID == generic.sourceReleaseID && $0.recordID == generic.recordID
              }) else { return nil }
        return try LabelEstimateMerge.merge(label: label.candidate.nutrients, labelBasis: label.candidate.identity.servingBasis,
                                            generic: generic.nutrients, genericBasis: generic.identity.servingBasis)?.nutrients
    }

    /// Section 6 steps 2 to 4: the nutrients a saved label entry must carry. The label candidate's
    /// own without a layer; with one, its merge with the stored generic decision under the single
    /// stored cocoa assertion. Nil when the layer, or a cocoa assertion without a layer, does not verify.
    static func expectedNutrients(_ saved: StoredFoodConfirmation, label: PopulatedFoodCandidate) throws -> NutrientSet? {
        let asserted = saved.assertions.compactMap(\.labelEstimate)
        guard let layer = saved.estimate else { return asserted.isEmpty ? label.candidate.nutrients : nil }
        let generic = layer.candidateDecision.candidate
        guard asserted.count == 1, let assertion = asserted.first,
              assertion.compatibilityVersion.value == LabelEstimateCompatibility.version,
              assertion.mergeVersion.value == LabelEstimateMerge.version,
              layer.candidateDecision.outcome == .selectedForEstimate,
              layer.evidence.map(\.evidenceID) == generic.evidenceIDs,
              saved.resolutionVersion.decisionIDs == [saved.candidateDecision.candidateDecisionID, layer.candidateDecision.candidateDecisionID],
              LabelEstimateCompatibility.isCompatible(name: assertion.genericName.value, variant: assertion.genericVariant?.value,
                  recordID: generic.recordID.value, nutrients: generic.nutrients, cocoaPercent: assertion.cocoaPercent)
        else { return nil }
        return try merged(label: label, generic: generic, release: layer.sourceRelease, cocoaPercent: assertion.cocoaPercent)
    }
}

extension StoredLabelEstimate {
    /// Reader assembly (section 5): no layer for a single decision; for two, the second decision with
    /// its evidence and its release, which is taken out of the label's releases. More than two
    /// decisions, or a layer without its evidence or release, is an integrity failure.
    public static func assembled(decisions: [CandidateDecision], evidence: [[CaptureEvidence]],
                                 releases: inout [SourceRelease]) throws -> StoredLabelEstimate? {
        // selected_for_estimate is only ever a layer's second decision.
        guard decisions.first?.outcome != .selectedForEstimate else {
            throw FoodLedgerStoreError.integrityFailure("incomplete label estimate layer")
        }
        guard decisions.count > 1 else { return nil }
        let decision = decisions[1]
        guard decisions.count == 2, evidence.count == 2, decision.outcome == .selectedForEstimate, evidence[1].map(\.evidenceID) == decision.candidate.evidenceIDs,
              decisions[0].candidate.sourceReleaseID != decision.candidate.sourceReleaseID,
              let index = releases.firstIndex(where: { $0.sourceReleaseID == decision.candidate.sourceReleaseID }) else {
            throw FoodLedgerStoreError.integrityFailure("incomplete label estimate layer")
        }
        return StoredLabelEstimate(candidateDecision: decision, evidence: evidence[1], sourceRelease: releases.remove(at: index))
    }
}
