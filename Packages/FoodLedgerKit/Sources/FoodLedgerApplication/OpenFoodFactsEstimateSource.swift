import Foundation
import FoodLedgerDomain

/// The Open Food Facts route of the label estimate (`off-label-estimate-v1`, #464,
/// docs/off-label-estimate-v1.md rule 1): one closed predicate, used by
/// `LabelEstimateOffer.applies`, the save guard and reopen, never re-implemented. The stored
/// candidate is the evidence of record (owner decision 1): the product is never re-fetched and the
/// response bytes are not kept, so nothing here re-reads a source.
public enum OpenFoodFactsEstimateSource {
    public static let sourceID = "open-food-facts"
    /// The record namespace of a personal-library rescan row (`BarcodeCaptureCoordinator`).
    static let libraryRecordPrefix = "personal-library:"

    /// Rule 1: an Open Food Facts search or barcode candidate, or a personal-library rescan row of
    /// one, named as a plain dark chocolate on a per 100 g basis. Per 100 ml products, mixed
    /// provenance and any other source are refused; a correction is the caller's (`admitsChoice`).
    public static func applies(_ input: PopulatedFoodConfirmation, candidate: PopulatedFoodCandidate) -> Bool {
        let source = candidate.candidate
        guard source.identity.servingBasis == .per100Grams,
              let release = input.sourceReleases.first(where: { $0.sourceReleaseID == source.sourceReleaseID }),
              release.sourceID.value == sourceID,
              isProductCandidate(source),
              !source.evidenceIDs.isEmpty else { return false }
        let evidence = input.evidence.filter { source.evidenceIDs.contains($0.evidenceID) }
        guard evidence.count == source.evidenceIDs.count, evidence.allSatisfy(isProductEvidence) else { return false }
        return LabelEstimateCompatibility.offersEstimate(name: candidate.name.value, basis: source.identity.servingBasis)
    }

    /// Every stated value carries Open Food Facts provenance naming the candidate's release and its
    /// record; for a personal-library rescan row (whose record is the library entry), every stated
    /// value names one and the same Open Food Facts record. At least one value is stated. Also the
    /// route discriminator of a saved layer's first decision.
    public static func isProductCandidate(_ candidate: ProviderNeutralCandidate) -> Bool {
        let stated = candidate.nutrients.entries.compactMap { entry -> [NutrientProvenance]? in
            if case .unknown = entry.value { return nil }
            return entry.value.provenance
        }
        guard !stated.isEmpty, stated.allSatisfy({ !$0.isEmpty }) else { return false }
        let provenance = stated.flatMap { $0 }
        guard provenance.allSatisfy({
            $0.sourceKind == .exactProductDataset && $0.sourceID.value == sourceID && $0.sourceReleaseID == candidate.sourceReleaseID
        }) else { return false }
        if candidate.recordID.value.hasPrefix(libraryRecordPrefix) {
            guard let record = provenance.first?.recordID else { return false }
            return !record.value.hasPrefix(libraryRecordPrefix) && provenance.allSatisfy { $0.recordID == record }
        }
        return provenance.allSatisfy { $0.recordID == candidate.recordID }
    }

    /// Owner decision 6 (docs/off-label-estimate-v1.md): a food details correction that only fills
    /// in or changes food details (preparation, bone, skin, drained, packing medium, unfortified or
    /// not stated fortification, or the description) keeps the estimate, because the estimate
    /// depends only on the name, the cocoa % and the values. The corrected name, brand, every
    /// nutrient value, the basis and the item class must equal the selected candidate's exactly.
    /// A fortified product or another item class (a supplement, say) drops it: the bundled
    /// reference rows are unfortified plain foods and would understate or misdescribe it.
    public static func isIdentityOnlyCorrection(_ correction: FoodCorrection, of candidate: PopulatedFoodCandidate) -> Bool {
        correction.name == candidate.name && correction.brand == candidate.brand
            && correction.nutrients == candidate.candidate.nutrients
            && correction.identity.servingBasis == candidate.candidate.identity.servingBasis
            && correction.identity.fortification != .fortified
            && (correction.itemClass ?? candidate.itemClass) == candidate.itemClass
    }

    /// Whether a new Open Food Facts entry's correction, if any, still admits the estimate layer:
    /// none, or an identity-only one (decision 6). Shared by Confirm and the save.
    public static func admitsLayer(_ state: FoodConfirmationState) -> Bool {
        guard applies(state.input, candidate: state.selectedCandidate) else { return false }
        guard let correction = state.correction else { return true }
        return isIdentityOnlyCorrection(correction, of: state.selectedCandidate)
    }

    /// The evidence is a scanned barcode or a typed search text.
    static func isProductEvidence(_ evidence: CaptureEvidence) -> Bool {
        switch (evidence.kind, evidence.originalPayload) {
        case (.barcode, .barcode), (.genericSearch, .text): true
        default: false
        }
    }
}
