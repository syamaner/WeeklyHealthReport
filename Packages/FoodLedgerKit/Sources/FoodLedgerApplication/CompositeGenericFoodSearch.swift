import Foundation
import FoodLedgerDomain

/// Keeps source records separate and exact saved reuse first. No cross-source score comparison.
public final class CompositeGenericFoodSearch: GenericFoodSearching, @unchecked Sendable {
    private let sources: [any GenericFoodSearching]
    private let ids: any LedgerIDGenerating
    public init(sources: [any GenericFoodSearching], ids: any LedgerIDGenerating) {
        self.sources = sources
        self.ids = ids
    }

    public func search(_ request: GenericFoodSearchRequest) throws -> GenericFoodSearchOutcome {
        let evidence = try request.captureEvidence ?? CaptureEvidence(
            evidenceID: ids.makeID(EvidenceTag.self), kind: .genericSearch, capturedAt: request.capturedAt,
            locale: request.locale, captureMethod: LedgerText("typed_generic_food_search"),
            captureMethodVersion: LedgerText("composite-offline-search-v1"), originalPayload: .text(request.text)
        )
        let shared = GenericFoodSearchRequest(text: request.text, identity: request.identity, capturedAt: request.capturedAt,
                                             locale: request.locale, captureEvidence: evidence, additionalEvidence: request.additionalEvidence)
        var routes: [GenericFoodConfirmationRoute] = []
        var fallback: GenericFoodNoResultRoute?
        for source in sources {
            switch try source.search(shared) {
            case let .confirmation(route):
                if route.reuse != nil { return .confirmation(route) }
                routes.append(route)
            case let .noResult(route):
                if fallback == nil { fallback = route }
            }
        }
        guard let first = routes.first else {
            return .noResult(fallback ?? GenericFoodNoResultRoute(evidence: evidence, additionalEvidence: request.additionalEvidence))
        }
        let matches = routes.flatMap(\.matches)
        var releases: [SourceRelease] = []
        for release in routes.flatMap({ $0.confirmation.sourceReleases }) {
            if let existing = releases.first(where: { $0.sourceReleaseID == release.sourceReleaseID }) {
                guard existing == release else { throw FoodLedgerValidationError.duplicateValue("source release identity") }
            } else { releases.append(release) }
        }
        return .confirmation(GenericFoodConfirmationRoute(
            confirmation: try PopulatedFoodConfirmation(
                evidence: first.confirmation.evidence, sourceReleases: releases, candidates: matches.map(\.candidate),
                expectedIdentity: first.confirmation.expectedIdentity, expectedEdibleQuantity: first.confirmation.expectedEdibleQuantity
            ), matches: matches
        ))
    }
}
