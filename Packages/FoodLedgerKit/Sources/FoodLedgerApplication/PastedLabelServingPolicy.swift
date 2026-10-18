import FoodLedgerDomain

/// Closed serving policy for pasted labels (`pasted-label-serving-v1`; contract section 6.3), a
/// sibling of `food-source-declared-serving-v1`. A pasted label whose stored column is per
/// serving can be logged in servings:
/// - case 2, `perServing(q)` with q in grams or millilitres: servings are converted through the
///   printed serving size (n servings = n × q), recorded as a quantity conversion whose method
///   is this policy's version; an amount in q's unit is also accepted, as for any basis;
/// - case 3, `perServing(1 count)` (no readable serving size): servings only.
/// Nothing is inferred: no weight is ever given to a case 3 serving. The source must be a
/// pasted-label release; save verification of its manifest still runs before policy.
public enum PastedLabelServingPolicy {
    public static let version = "pasted-label-serving-v1"

    /// The stored column's serving quantity when the policy applies.
    public static func serving(_ input: PopulatedFoodConfirmation, candidate: PopulatedFoodCandidate) -> PositiveQuantity? {
        let source = candidate.candidate
        guard case let .perServing(serving) = source.identity.servingBasis,
              input.sourceReleases.contains(where: { $0.sourceReleaseID == source.sourceReleaseID
                  && $0.sourceID.value == PastedLabelSource.sourceID }),
              input.evidence.contains(where: { source.evidenceIDs.contains($0.evidenceID)
                  && $0.captureMethodVersion.value == PastedLabelManifest.version }) else { return nil }
        return serving
    }

    public static func applies(_ input: PopulatedFoodConfirmation, candidate: PopulatedFoodCandidate) -> Bool {
        serving(input, candidate: candidate) != nil
    }

    /// Case 3: the serving has no weight or volume, so only servings are offered.
    public static func servingsOnly(_ input: PopulatedFoodConfirmation, candidate: PopulatedFoodCandidate) -> Bool {
        serving(input, candidate: candidate)?.unit == .count
    }

    /// The conversion recorded for n servings in case 2: n × q in q's unit, citing the pasted
    /// release and its manifest evidence. Nil in case 3, where servings are stored as counted.
    public static func conversion(servings: PositiveQuantity, serving: PositiveQuantity,
                                  candidate: PopulatedFoodCandidate) throws -> QuantityConversionDraft? {
        guard servings.unit == .count, serving.unit != .count else { return nil }
        return QuantityConversionDraft(convertedQuantity: try PositiveQuantity(value: servings.value * serving.value, unit: serving.unit),
            methodVersion: try LedgerText(version), sourceReleaseID: candidate.candidate.sourceReleaseID,
            evidenceID: candidate.candidate.evidenceIDs.first)
    }
}

extension FoodConfirmationState {
    /// The pasted-label serving quantity when `pasted-label-serving-v1` applies to the selection.
    public var pastedLabelServing: PositiveQuantity? { PastedLabelServingPolicy.serving(input, candidate: selectedCandidate) }

    /// Whether the entered amount is in servings under `pasted-label-serving-v1`.
    var logsPastedLabelServings: Bool { pastedLabelServing != nil && quantity.unit == .count }

    /// Servings must be a plain count: no direct weight, plate or conversion other than the
    /// policy's own (kept on a reopened entry). Case 3 accepts nothing but servings.
    var pastedLabelServingMisuse: Bool {
        guard let serving = pastedLabelServing else { return false }
        if quantity.unit != .count { return serving.unit == .count }
        return quantity.directWeight != nil || quantity.plateChoice != .foodOnly
            || (quantity.conversion.map { $0.methodVersion.value != PastedLabelServingPolicy.version } ?? false)
    }

    /// The quantity the save path records. Servings of a pasted label carry the policy's
    /// conversion in case 2, recomputed from the count (never a stale draft), and none in case 3.
    func policyQuantity() throws -> FoodQuantityDraft {
        guard logsPastedLabelServings, let serving = pastedLabelServing else { return quantity }
        guard !pastedLabelServingMisuse else { throw FoodLedgerValidationError.invalidUnit }
        var draft = quantity
        draft.conversion = try PastedLabelServingPolicy.conversion(servings: quantity.calculationInput(), serving: serving,
                                                                   candidate: selectedCandidate)
        return draft
    }
}
