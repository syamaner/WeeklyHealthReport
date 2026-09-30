import Foundation
import FoodLedgerApplication
import FoodLedgerDomain

/// Runtime food enrichment, with independently verified source values and exact-key authority.
public struct GeminiFoodSearch: FoodSearchEnriching {
    private let credentials: any FoodWebCredentialAuthorizing
    private let reviewer: any FoodGroundedSourceReviewing
    private let admission: any FoodSourceCandidateAdmitting
    private let locale: LedgerText
    private let clock: any LedgerClock
    private let ids: any LedgerIDGenerating
    private let timeout: Duration

    public init(credentials: any FoodWebCredentialAuthorizing, reviewer: any FoodGroundedSourceReviewing,
                admission: any FoodSourceCandidateAdmitting, locale: LedgerText,
                clock: any LedgerClock = SystemLedgerClock(), ids: any LedgerIDGenerating = RandomLedgerIDGenerator(),
                timeout: Duration = GeminiGroundedSourceReview.deadline) {
        self.credentials = credentials; self.reviewer = reviewer; self.admission = admission
        self.locale = locale; self.clock = clock; self.ids = ids
        self.timeout = min(max(timeout, .milliseconds(1)), GeminiGroundedSourceReview.deadline)
    }

    public func enrich(_ query: FoodSearchRemoteQuery) async throws -> GenericFoodSearchOutcome {
        try Task.checkCancellation()
        guard FoodQueryParser.parse(query.foodTerms).allowsCandidateDiscovery else { throw FoodSearchEnrichmentError.invalidQuery }
        let expires = ContinuousClock.now.advanced(by: timeout)
        return try await withThrowingTaskGroup(of: GenericFoodSearchOutcome.self) { group in
            group.addTask { try await run(query, expires: expires) }
            group.addTask { try await Task.sleep(for: timeout); throw FoodSearchEnrichmentError.unavailable }
            defer { group.cancelAll() }
            let result = try await group.next()!
            try Self.check(expires)
            return result
        }
    }

    private func run(_ query: FoodSearchRemoteQuery, expires: ContinuousClock.Instant) async throws -> GenericFoodSearchOutcome {
        let grant = try await credentials.credentialForRequest()
        try Self.check(expires)
        do {
            let review: FoodGroundedSourceReview
            var sourceFailure: FoodSourceReviewFailure?
            do { review = try await reviewer.review(foodTerms: query.foodTerms, key: grant.key) }
            catch let partial as FoodGroundedSourcePartialFailure {
                review = FoodGroundedSourceReview(discovery: partial.discovery, source: nil)
                sourceFailure = partial.reason
            }
            try Self.check(expires)
            guard await credentials.isCurrent(grant) else { throw FoodSearchEnrichmentError.unavailable }
            let evidence = try CaptureEvidence(evidenceID: ids.makeID(EvidenceTag.self), kind: .genericSearch,
                capturedAt: clock.now(), locale: locale, captureMethod: LedgerText("gemini_grounded_source_search"),
                captureMethodVersion: LedgerText("gemini-source-candidates-v1"), originalPayload: .text(LedgerText(query.foodTerms)))
            let outcome: GenericFoodSearchOutcome
            var admitted: GenericFoodConfirmationRoute?
            if let source = review.source {
                do { admitted = try admission.admit(source, query: query, evidence: evidence) }
                catch { sourceFailure = .invalidContent }
            }
            if let route = admitted {
                outcome = .confirmation(GenericFoodConfirmationRoute(confirmation: route.confirmation, matches: route.matches,
                    reuse: route.reuse, sourceDiscovery: review.discovery, sourceReviewFailure: sourceFailure))
            } else {
                outcome = .noResult(GenericFoodNoResultRoute(evidence: evidence,
                    guidance: "No compatible nutrition was verified from a supported source page. Available food results remain usable.",
                    sourceDiscovery: review.discovery, sourceReviewFailure: sourceFailure))
            }
            try Self.check(expires)
            guard await credentials.isCurrent(grant) else { throw FoodSearchEnrichmentError.unavailable }
            return outcome
        } catch {
            try Self.check(expires)
            guard await credentials.isCurrent(grant) else { throw FoodSearchEnrichmentError.unavailable }
            if error as? FoodWebDiscoveryError == .credentialRejected {
                await credentials.reject(grant)
                throw FoodSearchEnrichmentError.credentialRejected
            }
            if let error = error as? FoodSearchEnrichmentError { throw error }
            switch error as? FoodWebDiscoveryError {
            case .permissionDenied: throw FoodSearchEnrichmentError.permissionDenied
            case .quotaExceeded: throw FoodSearchEnrichmentError.quotaExceeded
            case .invalidQuery: throw FoodSearchEnrichmentError.invalidQuery
            case .invalidResponse: throw FoodSearchEnrichmentError.invalidResponse
            default: break
            }
            if error as? FoodSourceAcquisitionError == .quotaExceeded { throw FoodSearchEnrichmentError.quotaExceeded }
            throw FoodSearchEnrichmentError.unavailable
        }
    }

    private static func check(_ expires: ContinuousClock.Instant) throws {
        try Task.checkCancellation()
        guard ContinuousClock.now < expires else { throw FoodSearchEnrichmentError.unavailable }
    }
}
