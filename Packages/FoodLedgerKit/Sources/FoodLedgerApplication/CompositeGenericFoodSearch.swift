import Foundation
import FoodLedgerDomain

/// Interleaves source-local ranks with exact names first; never compares unlike scores.
/// v9: regional sources follow the default sources, by source, unless promoted.
public final class CompositeGenericFoodSearch: GenericFoodSearching, @unchecked Sendable {
    public static let version = "composite-generic-ranking-v9"
    private let sources: [any GenericFoodSearching]
    private let regionalSources: [any GenericFoodSearching]
    private let promotesRegional: (GenericFoodSearchRequest) -> Bool
    private let ids: any LedgerIDGenerating
    /// `regionalSources` (Taiwan TFDA) are searched after `sources`. Their rows follow
    /// every default-source row within each preparation and fat tier unless
    /// `promotesRegional` returns true, in which case all sources interleave as in v8.
    public init(sources: [any GenericFoodSearching], regionalSources: [any GenericFoodSearching] = [],
                promotesRegional: @escaping (GenericFoodSearchRequest) -> Bool = { _ in false },
                ids: any LedgerIDGenerating) {
        self.sources = sources
        self.regionalSources = regionalSources
        self.promotesRegional = promotesRegional
        self.ids = ids
    }

    public func search(_ request: GenericFoodSearchRequest) throws -> GenericFoodSearchOutcome {
        let evidence = try request.captureEvidence ?? CaptureEvidence(
            evidenceID: ids.makeID(EvidenceTag.self), kind: .genericSearch, capturedAt: request.capturedAt,
            locale: request.locale, captureMethod: LedgerText("typed_generic_food_search"),
            captureMethodVersion: LedgerText(Self.version), originalPayload: .text(request.text)
        )
        let shared = GenericFoodSearchRequest(text: request.text, identity: request.identity, capturedAt: request.capturedAt,
                                             locale: request.locale, captureEvidence: evidence, additionalEvidence: request.additionalEvidence)
        var routes: [GenericFoodConfirmationRoute] = []
        var regionalRoutes = Set<Int>()
        var fallback: GenericFoodNoResultRoute?
        var suggestions: [String] = []
        let deferRegional = !promotesRegional(request)
        for (index, source) in (sources + regionalSources).enumerated() {
            switch try source.search(shared) {
            case let .confirmation(route):
                if route.reuse != nil { return .confirmation(route) }
                if index >= sources.count && deferRegional { regionalRoutes.insert(routes.count) }
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
        var regional: [Bool] = []
        for rank in 0..<(routes.map { $0.matches.count }.max() ?? 0) {
            for (index, route) in routes.enumerated() where rank < route.matches.count {
                interleaved.append(route.matches[rank]); regional.append(regionalRoutes.contains(index))
            }
        }
        // The same representation policy runs before source truncation and across sources.
        // Source-local interleaving is only the stable tiebreak for equal preferences.
        let food = request.retrievalText
        let lexical = interleaved.enumerated().sorted { lhs, rhs in
            let leftUnverified = FoodPreparationDiscoveryPolicy.isUnverified(requested: request.identity.preparation,
                actual: lhs.element.candidate.candidate.identity.preparation.kind)
            let rightUnverified = FoodPreparationDiscoveryPolicy.isUnverified(requested: request.identity.preparation,
                actual: rhs.element.candidate.candidate.identity.preparation.kind)
            if leftUnverified != rightUnverified { return !leftUnverified }
            // Deferred regional rows follow by source; no score is compared across sources.
            if regional[lhs.offset] != regional[rhs.offset] { return !regional[lhs.offset] }
            if lhs.element.isExactName != rhs.element.isExactName { return lhs.element.isExactName }
            let a = GenericFoodRankingPolicy.preference(name: lhs.element.candidate.name.value,
                food: food, requestedText: request.text.value)
            let b = GenericFoodRankingPolicy.preference(name: rhs.element.candidate.name.value,
                food: food, requestedText: request.text.value)
            return a == b ? lhs.offset < rhs.offset : GenericFoodRankingPolicy.prefers(a, over: b)
        }.map(\.element)
        let fatRanked = lexical.filter { FoodQueryCandidateAssessment.matchesFat(query: request.parsedQuery, candidate: $0.candidate) } + lexical.filter { !FoodQueryCandidateAssessment.matchesFat(query: request.parsedQuery, candidate: $0.candidate) }
        let matches = fatRanked.filter { !FoodPreparationDiscoveryPolicy.isUnverified(requested: request.identity.preparation, actual: $0.candidate.candidate.identity.preparation.kind) }
            + fatRanked.filter { FoodPreparationDiscoveryPolicy.isUnverified(requested: request.identity.preparation, actual: $0.candidate.candidate.identity.preparation.kind) }
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
