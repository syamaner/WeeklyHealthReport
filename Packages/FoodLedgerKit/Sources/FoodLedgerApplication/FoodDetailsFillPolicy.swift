import Foundation
import FoodLedgerDomain

/// Whether a food details correction only fills in blanks (docs/confirm-rules-review-v1.md
/// rule 2.1, #470). Two layers, so the comparison exists once:
/// - **value-preserving:** name, brand, every nutrient value and the serving basis equal the
///   selected source's. The Open Food Facts estimate rule (off-label-estimate-v1 decision 6)
///   is built on this layer.
/// - **fill-only:** also the variant and declared fortificants equal, every food detail that
///   differs was unknown both in the source and in the current identity, and the item class is
///   unchanged except `food` to `fortifiedFood` for a fortified fill.
/// Pure application policy: it never reads a reason or claim text.
public enum FoodDetailsFillPolicy {
    /// Fixed reasons, persisted as data (rules 1.5, 2.2 and 3.1), not UI copy.
    public static let packagedAsSoldReason = "Packaged product, eaten as sold"
    public static let filledReason = "Food details added"
    public static let carriedReason = "Food details from your last entry"

    /// Frozen packing medium names (rule 2.3), stored as `.named` values.
    public static let packingAsSold = "as sold"
    public static let packingNotApplicable = "not applicable"

    public static func isValuePreserving(_ correction: FoodCorrection, of candidate: PopulatedFoodCandidate) -> Bool {
        correction.name == candidate.name && correction.brand == candidate.brand
            && correction.nutrients == candidate.candidate.nutrients
            && correction.identity.servingBasis == candidate.candidate.identity.servingBasis
    }

    /// The live form (Confirm and the Food details sheet). `current` is the identity the
    /// correction replaces: the existing correction, else the reopened saved product, else the
    /// source, in the order the reducer uses.
    public static func isFill(_ correction: FoodCorrection, of candidate: PopulatedFoodCandidate,
                              current: DecisiveIdentity) -> Bool {
        guard isValuePreserving(correction, of: candidate),
              correction.variant == candidate.variant,
              correction.identity.declaredFortificants == candidate.candidate.identity.declaredFortificants
                || (correction.identity.fortification == .fortified && candidate.candidate.identity.fortification == .unknown
                    && correction.identity.declaredFortificants.isEmpty)
        else { return false }
        let itemClass = correction.itemClass ?? candidate.itemClass
        let classAllowed = itemClass == candidate.itemClass
            || (candidate.itemClass == .food && itemClass == .fortifiedFood && correction.identity.fortification == .fortified)
        return classAllowed && fillsOnly(correction.identity, source: candidate.candidate.identity, current: current)
    }

    /// The live form against the state's current identity.
    public static func isFill(_ correction: FoodCorrection, in state: FoodConfirmationState) -> Bool {
        isFill(correction, of: state.selectedCandidate, current: currentIdentity(state))
    }

    public static func currentIdentity(_ state: FoodConfirmationState) -> DecisiveIdentity {
        state.correction?.identity ?? state.reopened?.productVersion.identity ?? state.selectedCandidate.candidate.identity
    }

    /// The stored form (re-log and quick add, rule 2.1): typed fields of a saved entry only. The
    /// saved product's food details fill in its source's blanks, the basis is the source's, the
    /// values are the source's (or its estimate layer merge), and the fill is not fortified.
    /// True only when there is something to carry.
    public static func isStoredFill(_ saved: StoredFoodConfirmation) -> Bool {
        let source = saved.candidateDecision.candidate
        let product = saved.productVersion.identity
        guard product != source.identity,
              product.servingBasis == source.identity.servingBasis,
              product.fortification != .fortified, product.declaredFortificants.isEmpty,
              source.identity.declaredFortificants.isEmpty,
              saved.productVersion.itemClass == .food || saved.productVersion.itemClass == .drink
                || saved.productVersion.itemClass == .water,
              saved.resolutionVersion.nutrients == source.nutrients || FoodEntryEstimateStatus.isPartlyEstimated(saved)
        else { return false }
        return fillsOnly(product, source: source.identity, current: source.identity)
    }

    /// The correction a re-log or quick add starts with (rule 3.1): the saved food details on the
    /// rebuilt source, with its name, brand, variant, item class and values unchanged. Nil when
    /// nothing may be carried or the rebuilt state has a difference to decide (rule 3.3): details
    /// that are only missing are not differences to decide, as on Confirm.
    public static func carriedFill(from saved: StoredFoodConfirmation, into state: FoodConfirmationState) -> FoodCorrection? {
        guard isStoredFill(saved), state.correction == nil, state.reopened == nil,
              FoodLogPolicy.pendingDifferences(state).allSatisfy({
                  answersOnlyBlank($0, source: state.selectedCandidate.candidate.identity, saved: saved.productVersion.identity)
              }),
              let reason = try? LedgerText(carriedReason) else { return nil }
        let candidate = state.selectedCandidate
        let correction = FoodCorrection(name: candidate.name, brand: candidate.brand, variant: candidate.variant,
                                        identity: saved.productVersion.identity, itemClass: candidate.itemClass,
                                        nutrients: candidate.candidate.nutrients, reason: reason)
        return isFill(correction, in: state) ? correction : nil
    }

    /// A pending question the carried fill may answer: only one about a food detail the source left
    /// unknown and the saved entry filled in. A real mismatch (basis, quantity, or a detail the
    /// source states) is still decided on Confirm.
    public static func answersOnlyBlank(_ facet: IdentityContradiction, source: DecisiveIdentity, saved: DecisiveIdentity) -> Bool {
        switch facet {
        case .preparation: source.preparation.kind == .unknown && saved.preparation.kind != .unknown
        case .bone: source.bone == .unknown && saved.bone != .unknown
        case .skin: source.skin == .unknown && saved.skin != .unknown
        case .drained: source.drained == .unknown && saved.drained != .unknown
        case .packingMedium: source.packingMedium == .unknown && saved.packingMedium != .unknown
        case .fortification: source.fortification == .unknown && saved.fortification != .unknown
        case .servingBasis, .edibleQuantity: false
        }
    }

    /// Every food detail either equals the source's, or the source did not know it and the
    /// current identity either did not know it either or already says the same.
    static func fillsOnly(_ value: DecisiveIdentity, source: DecisiveIdentity, current: DecisiveIdentity) -> Bool {
        // Unchanged from the current answer, or filling a detail neither the source nor the current
        // answer knows. Resetting a known answer to unknown and then refilling it is not a fill.
        func facet<T: Equatable>(_ new: T, _ old: T, _ now: T, unknown: T) -> Bool {
            new == now || (old == unknown && now == unknown)
        }
        return facet(value.preparation.kind == .unknown ? nil : value.preparation,
                     source.preparation.kind == .unknown ? nil : source.preparation,
                     current.preparation.kind == .unknown ? nil : current.preparation, unknown: nil)
            && facet(value.bone, source.bone, current.bone, unknown: .unknown)
            && facet(value.skin, source.skin, current.skin, unknown: .unknown)
            && facet(value.drained, source.drained, current.drained, unknown: .unknown)
            && facet(value.packingMedium, source.packingMedium, current.packingMedium, unknown: .unknown)
            && facet(value.fortification, source.fortification, current.fortification, unknown: .unknown)
    }
}

/// Rule 1 (docs/confirm-rules-review-v1.md, owner decision 1): the one-tap "Packaged product,
/// eaten as sold" answer for an Open Food Facts product.
public enum PackagedAsSoldPolicy {
    /// Offered on a new Open Food Facts Confirm while food details are missing, no inline
    /// difference is pending and no correction has been made yet.
    public static func offers(_ state: FoodConfirmationState) -> Bool {
        guard state.reopened == nil, state.correction == nil,
              OpenFoodFactsEstimateSource.isProductCandidate(state.selectedCandidate.candidate),
              state.input.evidence.contains(where: OpenFoodFactsEstimateSource.isProductEvidence),
              !state.unresolvedIdentity.isEmpty else { return false }
        // Only while no difference is pending at all: applying a correction clears decided answers,
        // so a decided Not sure (an estimate) must never be dropped by the tap (invariant review).
        return FoodLogPolicy.pendingDifferences(state).isEmpty
    }

    /// As sold; bone, skin and drained not applicable; packing medium "as sold"; fortified Yes or
    /// No; serving basis, name, brand, variant and values unchanged. Yes makes the item class
    /// `fortifiedFood`, as the record model requires.
    public static func correction(for state: FoodConfirmationState, fortified: Bool) throws -> FoodCorrection {
        let candidate = state.selectedCandidate
        let identity = try DecisiveIdentity(
            preparation: PreparationState(kind: .asSold),
            bone: .notApplicable, skin: .notApplicable, drained: .notApplicable,
            packingMedium: .named(LedgerText(FoodDetailsFillPolicy.packingAsSold)),
            fortification: fortified ? .fortified : .unfortified,
            servingBasis: candidate.candidate.identity.servingBasis)
        return FoodCorrection(name: candidate.name, brand: candidate.brand, variant: candidate.variant,
                              identity: identity, itemClass: fortified ? .fortifiedFood : candidate.itemClass,
                              nutrients: candidate.candidate.nutrients,
                              reason: try LedgerText(FoodDetailsFillPolicy.packagedAsSoldReason))
    }
}
