import Foundation
import FoodLedgerDomain

/// Interleaves source-local ranks with exact names first; never compares unlike scores.
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
            captureMethodVersion: LedgerText("composite-interleaved-search-v2"), originalPayload: .text(request.text)
        )
        let shared = GenericFoodSearchRequest(text: request.text, identity: request.identity, capturedAt: request.capturedAt,
                                             locale: request.locale, captureEvidence: evidence, additionalEvidence: request.additionalEvidence)
        var routes: [GenericFoodConfirmationRoute] = []
        var fallback: GenericFoodNoResultRoute?
        var suggestions: [String] = []
        for source in sources {
            switch try source.search(shared) {
            case let .confirmation(route):
                if route.reuse != nil { return .confirmation(route) }
                routes.append(route)
            case let .noResult(route):
                if fallback == nil { fallback = route }
                for query in route.suggestedQueries where !suggestions.contains(query) { suggestions.append(query) }
            }
        }
        guard let first = routes.first else {
            return .noResult(GenericFoodNoResultRoute(evidence: evidence, additionalEvidence: request.additionalEvidence, guidance: fallback?.guidance, suggestedQueries: Array(suggestions.prefix(3))))
        }
        var interleaved: [GenericFoodMatch] = []
        for rank in 0..<(routes.map { $0.matches.count }.max() ?? 0) {
            for route in routes where rank < route.matches.count { interleaved.append(route.matches[rank]) }
        }
        let matches = interleaved.filter(\.isExactName) + interleaved.filter { !$0.isExactName }
        var releases: [SourceRelease] = []
        for release in routes.flatMap({ $0.confirmation.sourceReleases }) {
            if let existing = releases.first(where: { $0.sourceReleaseID == release.sourceReleaseID }) {
                guard existing == release else { throw FoodLedgerValidationError.duplicateValue("source release identity") }
            } else { releases.append(release) }
        }
        return .confirmation(GenericFoodConfirmationRoute(
            confirmation: try PopulatedFoodConfirmation(
                evidence: first.confirmation.evidence, sourceReleases: releases, candidates: matches.map(\.candidate),
                expectedIdentity: matches[0].candidate.candidate.identity, expectedEdibleQuantity: matches[0].candidate.candidate.edibleQuantity
            ), matches: matches
        ))
    }
}
