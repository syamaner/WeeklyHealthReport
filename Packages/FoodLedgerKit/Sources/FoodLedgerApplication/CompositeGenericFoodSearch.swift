import Foundation
import FoodLedgerDomain

/// Interleaves source-local ranks with exact names first; never compares unlike scores.
/// v9: regional sources follow the default sources, by source, unless promoted.
/// v11 (docs/ciqual-2025-admission-v1.md section 5): a reference-only group (Ciqual) follows
/// every other row, is never promoted and gets its own cocoa tier keys, so removing its rows
/// from any v11 output gives the v10 output exactly.
/// Your food database (import v1, phase 1 plan section 5.1): an optional route searched after the
/// default sources and before the regional ones, always group 0, whose no-result route never
/// supplies guidance or suggestions. With no database rows the output is v11 exactly.
public final class CompositeGenericFoodSearch: GenericFoodSearching, @unchecked Sendable {
    public static let version = "composite-generic-ranking-v11"
    private let sources: [any GenericFoodSearching]
    private let regionalSources: [any GenericFoodSearching]
    private let referenceSources: [any GenericFoodSearching]
    private let databaseSource: (any GenericFoodSearching)?
    private let promotesRegional: (GenericFoodSearchRequest) -> Bool
    private let ids: any LedgerIDGenerating
    /// `regionalSources` (Taiwan TFDA) are searched after `sources`. Their rows follow
    /// every default-source row within each preparation and fat tier unless
    /// `promotesRegional` returns true, in which case all sources interleave as in v8.
    /// `referenceSources` (Ciqual) are searched last; their rows follow every other row within
    /// each preparation and fat tier whatever `promotesRegional` returns.
    public init(sources: [any GenericFoodSearching], regionalSources: [any GenericFoodSearching] = [],
                referenceSources: [any GenericFoodSearching] = [],
                databaseSource: (any GenericFoodSearching)? = nil,
                promotesRegional: @escaping (GenericFoodSearchRequest) -> Bool = { _ in false },
                ids: any LedgerIDGenerating) {
        self.sources = sources
        self.regionalSources = regionalSources
        self.referenceSources = referenceSources
        self.databaseSource = databaseSource
        self.promotesRegional = promotesRegional
        self.ids = ids
    }

    /// Whether this composite searches Your food database (phase 1 plan section 5.1).
    public var searchesPersonalFoodDatabase: Bool { databaseSource != nil }

    public func search(_ request: GenericFoodSearchRequest) throws -> GenericFoodSearchOutcome {
        let evidence = try request.captureEvidence ?? CaptureEvidence(
            evidenceID: ids.makeID(EvidenceTag.self), kind: .genericSearch, capturedAt: request.capturedAt,
            locale: request.locale, captureMethod: LedgerText("typed_generic_food_search"),
            captureMethodVersion: LedgerText(Self.version), originalPayload: .text(request.text)
        )
        let shared = GenericFoodSearchRequest(text: request.text, identity: request.identity, capturedAt: request.capturedAt,
                                             locale: request.locale, captureEvidence: evidence, additionalEvidence: request.additionalEvidence)
        var routes: [GenericFoodConfirmationRoute] = []
        // Deferral group per route: 0 default, 1 deferred regional, 2 reference-only.
        var routeGroups: [Int] = []
        var fallback: GenericFoodNoResultRoute?
        var suggestions: [String] = []
        let deferRegional = !promotesRegional(request)
        // (source, group, is the database route), in search order.
        var ordered: [(any GenericFoodSearching, Int, Bool)] = sources.map { ($0, 0, false) }
        if let databaseSource { ordered.append((databaseSource, 0, true)) }
        ordered += regionalSources.map { ($0, deferRegional ? 1 : 0, false) }
        ordered += referenceSources.map { ($0, 2, false) }
        for (source, routeGroup, isDatabase) in ordered {
            switch try source.search(shared) {
            case let .confirmation(route):
                // The database route never carries reuse; a reuse short-circuit is a source's own.
                if route.reuse != nil && !isDatabase { return .confirmation(route) }
                routeGroups.append(routeGroup)
                routes.append(route)
            case let .noResult(route):
                // A database no-result (none installed, locked, no match) is never guidance.
                guard !isDatabase else { continue }
                if fallback == nil { fallback = route }
                for query in route.suggestedQueries where !suggestions.contains(query) { suggestions.append(query) }
            }
        }
        guard let first = routes.first else {
            return .noResult(GenericFoodNoResultRoute(evidence: evidence, additionalEvidence: request.additionalEvidence, guidance: fallback?.guidance, suggestedQueries: Array(suggestions.prefix(3))))
        }
        var interleaved: [GenericFoodMatch] = []
        var group: [Int] = []
        for rank in 0..<(routes.map { $0.matches.count }.max() ?? 0) {
            // Reference-only routes come last in the route list, so at each rank they follow
            // every other route and the relative offsets of the other rows are those of v10.
            for (index, route) in routes.enumerated() where rank < route.matches.count {
                interleaved.append(route.matches[rank]); group.append(routeGroups[index])
            }
        }
        // The same representation policy runs before source truncation and across sources.
        // Source-local interleaving is only the stable tiebreak for equal preferences.
        let food = request.retrievalText
        // Cocoa tiers rank after deferral, before name preference. Keys are computed within the
        // reference-only group and, apart, over every other row exactly as v10 computed them, so
        // a reference row's band never changes another row's tier.
        let cocoa = CocoaPercentPolicy.requested(request.parsedQuery).map { value in
            Self.tierKeys(interleaved.map { CocoaPercentPolicy.band($0.candidate) }, reference: group.map { $0 == 2 }, requested: value)
        }
        let lexical = interleaved.enumerated().sorted { lhs, rhs in
            let leftUnverified = FoodPreparationDiscoveryPolicy.isUnverified(requested: request.identity.preparation,
                actual: lhs.element.candidate.candidate.identity.preparation.kind)
            let rightUnverified = FoodPreparationDiscoveryPolicy.isUnverified(requested: request.identity.preparation,
                actual: rhs.element.candidate.candidate.identity.preparation.kind)
            if leftUnverified != rightUnverified { return !leftUnverified }
            // Deferred regional rows, then reference-only rows, follow by group; no score is
            // compared across sources.
            if group[lhs.offset] != group[rhs.offset] { return group[lhs.offset] < group[rhs.offset] }
            if let cocoa, cocoa[lhs.offset] != cocoa[rhs.offset] { return cocoa[lhs.offset] < cocoa[rhs.offset] }
            if lhs.element.isExactName != rhs.element.isExactName { return lhs.element.isExactName }
            let a = GenericFoodRankingPolicy.preference(name: lhs.element.candidate.name.value,
                food: food, requestedText: request.text.value)
            let b = GenericFoodRankingPolicy.preference(name: rhs.element.candidate.name.value,
                food: food, requestedText: request.text.value)
            return a == b ? lhs.offset < rhs.offset : GenericFoodRankingPolicy.prefers(a, over: b)
        }.map(\.element)
        let fatRanked = lexical.filter { FoodQueryCandidateAssessment.matchesFat(query: request.parsedQuery, candidate: $0.candidate) } + lexical.filter { !FoodQueryCandidateAssessment.matchesFat(query: request.parsedQuery, candidate: $0.candidate) }
        let partitioned = fatRanked.filter { !FoodPreparationDiscoveryPolicy.isUnverified(requested: request.identity.preparation, actual: $0.candidate.candidate.identity.preparation.kind) }
            + fatRanked.filter { FoodPreparationDiscoveryPolicy.isUnverified(requested: request.identity.preparation, actual: $0.candidate.candidate.identity.preparation.kind) }
        let matches = try Self.dedupeDatabaseRows(partitioned)
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

    /// Import v1 section 5 under v11 (phase 1 plan section 5.1 item 4): only a pair where exactly one
    /// row came from the database route is deduped. The database copy, with its context and
    /// `pfc-resolution-v1` metadata, takes the position of whichever copy sorted first; the other
    /// is dropped when the record facts agree, and differing facts throw. Other rows are untouched.
    static func dedupeDatabaseRows(_ rows: [GenericFoodMatch]) throws -> [GenericFoodMatch] {
        var result: [GenericFoodMatch] = []
        for row in rows {
            guard let index = result.firstIndex(where: {
                $0.searchID == row.searchID && ($0.personalDatabase == nil) != (row.personalDatabase == nil)
            }) else { result.append(row); continue }
            guard FoodSearchRecordEquality.sameSourceRecord(result[index].candidate, row.candidate) else {
                throw FoodLedgerValidationError.duplicateValue("conflicting source record")
            }
            if row.personalDatabase != nil { result[index] = row }
        }
        return result
    }

    /// Tier keys for the non-reference rows over those rows only (the v10 pool), and for the
    /// reference-only rows over theirs; rows are compared by cocoa only within one group.
    static func tierKeys(_ bands: [CocoaPercentPolicy.Band?], reference: [Bool], requested value: Double) -> [CocoaPercentPolicy.TierKey] {
        var keys = Array(repeating: CocoaPercentPolicy.TierKey(tier: 4, distance: 0), count: bands.count)
        for isReference in [false, true] {
            let indices = bands.indices.filter { reference[$0] == isReference }
            let pooled = CocoaPercentPolicy.tierKeys(indices.map { bands[$0] }, requested: value)
            for (position, index) in indices.enumerated() { keys[index] = pooled[position] }
        }
        return keys
    }
}
