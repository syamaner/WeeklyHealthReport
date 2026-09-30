import FoodLedgerDomain

public struct FoodSearchCandidateID: Hashable, Sendable {
    public let sourceReleaseID: ExternalIdentifier
    public let recordID: ExternalIdentifier

    public init(_ match: GenericFoodMatch) {
        sourceReleaseID = match.candidate.candidate.sourceReleaseID
        recordID = match.candidate.candidate.recordID
    }
}

/// Append-only presentation order. No source identity, nutrient or evidence repair.
public enum FoodSearchResultMerger {
    public static func merge(
        _ current: GenericFoodSearchOutcome?, _ incoming: GenericFoodSearchOutcome
    ) throws -> GenericFoodSearchOutcome {
        let outcomes = [current, incoming].compactMap { $0 }
        var evidence: [CaptureEvidence] = []
        var releases: [SourceRelease] = []
        var matches: [GenericFoodMatch] = []
        var fallback: GenericFoodNoResultRoute?
        var suggestions: [String] = []
        var reuse: BarcodeReuseReference?
        var sourceDiscovery: FoodWebDiscoveryResult?
        var sourceReviewFailure: FoodSourceReviewFailure?
        for outcome in outcomes {
            switch outcome {
            case let .noResult(route):
                if let discovery = route.sourceDiscovery {
                    sourceDiscovery = discovery; sourceReviewFailure = route.sourceReviewFailure
                }
                if fallback == nil { fallback = route }
                try appendUnique(route.retainedEvidence, to: &evidence, id: \.evidenceID)
                for query in route.suggestedQueries where !suggestions.contains(query) { suggestions.append(query) }
            case let .confirmation(route):
                if let discovery = route.sourceDiscovery {
                    sourceDiscovery = discovery; sourceReviewFailure = route.sourceReviewFailure
                }
                guard route.matches.map(\.candidate) == route.confirmation.candidates else {
                    throw FoodLedgerValidationError.invalidBasis
                }
                try appendUnique(route.confirmation.evidence, to: &evidence, id: \.evidenceID)
                try appendUnique(route.confirmation.sourceReleases, to: &releases, id: \.sourceReleaseID)
                if matches.isEmpty { reuse = route.reuse }
                for match in route.matches {
                    if let existing = matches.first(where: { FoodSearchCandidateID($0) == FoodSearchCandidateID(match) }) {
                        guard sameSourceRecord(existing.candidate, match.candidate) else {
                            throw FoodLedgerValidationError.duplicateValue("conflicting source record")
                        }
                    } else { matches.append(match) }
                }
            }
        }
        if let first = matches.first {
            return .confirmation(GenericFoodConfirmationRoute(
                confirmation: try PopulatedFoodConfirmation(evidence: evidence, sourceReleases: releases,
                    candidates: matches.map(\.candidate), expectedIdentity: first.candidate.candidate.identity,
                    expectedEdibleQuantity: first.candidate.candidate.edibleQuantity),
                matches: matches, reuse: matches.count == 1 ? reuse : nil, sourceDiscovery: sourceDiscovery, sourceReviewFailure: sourceReviewFailure))
        }
        guard let fallback else { throw FoodLedgerValidationError.empty("search outcome") }
        return .noResult(GenericFoodNoResultRoute(evidence: fallback.evidence,
            additionalEvidence: evidence.filter { $0.evidenceID != fallback.evidence.evidenceID },
            guidance: fallback.guidance, suggestedQueries: Array(suggestions.prefix(3)), sourceDiscovery: sourceDiscovery, sourceReviewFailure: sourceReviewFailure))
    }

    /// Capture occurrences and ranking hints may differ for the same immutable record.
    /// Keep the first row and its candidate evidence links; retain all batch evidence.
    /// Nutrient provenance and every source fact must still agree exactly.
    private static func sameSourceRecord(_ lhs: PopulatedFoodCandidate, _ rhs: PopulatedFoodCandidate) -> Bool {
        let a = lhs.candidate
        let b = rhs.candidate
        return lhs.name == rhs.name && lhs.brand == rhs.brand && lhs.variant == rhs.variant
            && lhs.barcode == rhs.barcode && lhs.itemClass == rhs.itemClass && lhs.packFacts == rhs.packFacts
            && a.sourceReleaseID == b.sourceReleaseID && a.recordID == b.recordID
            && a.identity == b.identity && a.edibleQuantity == b.edibleQuantity && a.nutrients == b.nutrients
    }

    private static func appendUnique<T: Equatable, ID: Equatable>(
        _ values: [T], to result: inout [T], id: KeyPath<T, ID>
    ) throws {
        for value in values {
            if let existing = result.first(where: { $0[keyPath: id] == value[keyPath: id] }) {
                guard existing == value else { throw FoodLedgerValidationError.duplicateValue("conflicting search provenance") }
            } else { result.append(value) }
        }
    }
}

public extension GenericFoodMatch {
    var searchID: FoodSearchCandidateID { FoodSearchCandidateID(self) }
}
