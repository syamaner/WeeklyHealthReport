import Foundation
import FoodLedgerDomain

/// Admission of photo and pasted label values at save (P19): the composite routes a candidate
/// to exactly one source verifier and refuses a mixed one. `PanelSourceAdmission` (pinned) stays
/// the pasted route's; it would claim a photo candidate through its `user_verified_panel` values,
/// which is why this composite decides first.
public enum LabelSourceAdmission {
    public enum Route: Equatable, Sendable { case photo, pasted, refused }

    /// Whether either label source's admission applies.
    public static func applies(_ input: PopulatedFoodConfirmation, candidate: PopulatedFoodCandidate) -> Bool {
        claimsPhoto(input, candidate: candidate) || PanelSourceAdmission.applies(input, candidate: candidate)
    }

    /// Which verifier a candidate goes to. A candidate with any photo evidence, release or value
    /// goes to the photo verifier only if nothing in it names the pasted source; a candidate that
    /// names both is refused.
    public static func route(_ input: PopulatedFoodConfirmation, candidate: PopulatedFoodCandidate) -> Route {
        let photo = claimsPhoto(input, candidate: candidate)
        let pasted = claimsPasted(input, candidate: candidate)
        switch (photo, pasted) {
        case (true, false): return .photo
        case (false, _): return PanelSourceAdmission.applies(input, candidate: candidate) ? .pasted : .refused
        case (true, true): return .refused
        }
    }

    /// Fails closed: the routed verifier must accept the candidate.
    public static func verify(_ input: PopulatedFoodConfirmation, candidate: PopulatedFoodCandidate, encoder: any CanonicalEncoding,
                              digester: any Digesting, conversions: (any PastedLabelConversionChecking)?) -> Bool {
        switch route(input, candidate: candidate) {
        case .photo:
            return photoValuesNameOnlyThisRelease(input, candidate: candidate)
                && LabelPhotoSource.verify(input, candidate: candidate, encoder: encoder, digester: digester, conversions: conversions)
        case .pasted:
            return PanelSourceAdmission.verify(input, candidate: candidate, encoder: encoder, digester: digester, conversions: conversions)
        case .refused:
            return false
        }
    }

    static func claimsPhoto(_ input: PopulatedFoodConfirmation, candidate: PopulatedFoodCandidate) -> Bool {
        let source = candidate.candidate
        let named = { (id: ExternalIdentifier) in input.sourceReleases.first { $0.sourceReleaseID == id }?.sourceID.value }
        return PanelSourceAdmission.provenance(source).contains { $0.sourceID.value == LabelPhotoSource.sourceID
                || named($0.sourceReleaseID) == LabelPhotoSource.sourceID }
            || named(source.sourceReleaseID) == LabelPhotoSource.sourceID
            || LabelPhotoSource.hasPhotoEvidence(input, candidate: candidate)
    }

    static func claimsPasted(_ input: PopulatedFoodConfirmation, candidate: PopulatedFoodCandidate) -> Bool {
        let source = candidate.candidate
        let pasted = PastedLabelSource.sourceID
        let named = { (id: ExternalIdentifier) in input.sourceReleases.first { $0.sourceReleaseID == id }?.sourceID.value }
        return PanelSourceAdmission.provenance(source).contains { $0.sourceID.value == pasted || named($0.sourceReleaseID) == pasted }
            || named(source.sourceReleaseID) == pasted
            || input.evidence.contains { source.evidenceIDs.contains($0.evidenceID) && PastedLabelEvidenceManifest.isVersion($0.captureMethodVersion.value) }
    }

    /// Every panel or manual value of a photo candidate names the photo source and its release.
    static func photoValuesNameOnlyThisRelease(_ input: PopulatedFoodConfirmation, candidate: PopulatedFoodCandidate) -> Bool {
        let source = candidate.candidate
        return PanelSourceAdmission.provenance(source).allSatisfy { value in
            (value.sourceKind == .userVerifiedPanel || value.sourceKind == .manualDeclaration)
                && value.sourceID.value == LabelPhotoSource.sourceID && value.sourceReleaseID == source.sourceReleaseID
        }
    }
}
