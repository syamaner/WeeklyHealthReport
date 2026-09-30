import FoodLedgerDomain

/// Source adapters must prove page/product/panel correspondence before producing candidates.
/// No implementation may replace explicit selection or the domain's identity/save requirements.
public protocol FoodSourceCandidateAdmitting: Sendable {
    func admit(_ source: FoodReviewedSource, query: FoodSearchRemoteQuery,
               evidence: CaptureEvidence) throws -> GenericFoodConfirmationRoute?
}
