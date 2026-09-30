import FoodLedgerDomain

/// Versioned explicit confirmation of a composition estimate, never provider compatibility.
public enum FoodConfirmationPolicy {
    public static let version = "food_confirmation_v3"

    public static func isGenericEstimate(_ input: PopulatedFoodConfirmation, candidate: PopulatedFoodCandidate) -> Bool {
        if FoodNamedServingPolicy.applies(input, candidate: candidate) { return true }
        let source = candidate.candidate
        let evidence = input.evidence.filter { source.evidenceIDs.contains($0.evidenceID) }
        let provenance = source.nutrients.entries.flatMap { $0.value.provenance }
        return evidence.contains { $0.kind == .genericSearch }
            && !provenance.isEmpty
            && provenance.allSatisfy {
                $0.sourceKind == .genericCompositionDataset
                    && $0.sourceReleaseID == source.sourceReleaseID && $0.recordID == source.recordID
            }
    }

    public static func unresolvedIdentity(_ identity: DecisiveIdentity, allowingEstimate: Bool) -> [IdentityContradiction] {
        var missing: [IdentityContradiction] = []
        if !allowingEstimate {
            if identity.preparation.kind == .unknown { missing.append(.preparation) }
            if identity.bone == .unknown { missing.append(.bone) }
            if identity.skin == .unknown { missing.append(.skin) }
            if identity.drained == .unknown { missing.append(.drained) }
            if identity.packingMedium == .unknown { missing.append(.packingMedium) }
            if identity.fortification == .unknown { missing.append(.fortification) }
        }
        if identity.servingBasis == .unknown { missing.append(.servingBasis) }
        return missing
    }
}
