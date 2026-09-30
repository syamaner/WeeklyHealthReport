import Foundation
import FoodLedgerDomain

/// The remote port cannot receive ledger history, capture evidence or credentials.
public struct FoodSearchRemoteQuery: Equatable, Sendable {
    public let foodTerms: String
    public init(foodTerms: String) throws {
        let terms = foodTerms.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !terms.isEmpty, terms.count <= 300 else { throw FoodSearchEnrichmentError.invalidQuery }
        self.foodTerms = terms
    }
}

/// Implementations return only candidates that passed their versioned source admission.
/// A citation-only response cannot implement this contract by inventing nutrients.
public protocol FoodSearchEnriching: Sendable {
    func enrich(_ query: FoodSearchRemoteQuery) async throws -> GenericFoodSearchOutcome
}

public enum FoodSearchEnrichmentError: Error, Equatable, Sendable {
    case credentialRejected, permissionDenied, quotaExceeded, unavailable, invalidResponse, invalidQuery
}

public struct FoodSearchStageFailure: Equatable, Sendable {
    public let stage: FoodSearchStage
    public let reason: FoodSearchEnrichmentError
}

/// Facts about an accepted stage, after validation and deduplication. No relevance scores.
public struct FoodSearchStageReport: Equatable, Sendable {
    public let stage: FoodSearchStage
    public let addedCandidateIDs: [FoodSearchCandidateID]
    public let failure: FoodSearchEnrichmentError?
    public let sourceReviewFailure: FoodSourceReviewFailure?
    public let hasSourceLinks: Bool
    public init(stage: FoodSearchStage, addedCandidateIDs: [FoodSearchCandidateID] = [],
                failure: FoodSearchEnrichmentError? = nil, sourceReviewFailure: FoodSourceReviewFailure? = nil,
                hasSourceLinks: Bool = false) {
        self.stage = stage; self.addedCandidateIDs = addedCandidateIDs; self.failure = failure
        self.sourceReviewFailure = sourceReviewFailure; self.hasSourceLinks = hasSourceLinks
    }
}

public struct ProgressiveFoodSearchSnapshot: Equatable, Sendable {
    public let outcome: GenericFoodSearchOutcome?
    public let pending: FoodSearchStage?
    public let failures: [FoodSearchStageFailure]
    public let reports: [FoodSearchStageReport]
    public init(outcome: GenericFoodSearchOutcome?, pending: FoodSearchStage?, failures: [FoodSearchStageFailure],
                reports: [FoodSearchStageReport] = []) {
        self.outcome = outcome; self.pending = pending; self.failures = failures; self.reports = reports
    }
}

/// Owns task lifecycle on the same executor as its consumer, without a UI dependency.
@MainActor
public final class ProgressiveFoodSearchCoordinator {
    public private(set) var snapshot = ProgressiveFoodSearchSnapshot(outcome: nil, pending: nil, failures: [])
    public var onUpdate: (@MainActor (ProgressiveFoodSearchSnapshot) -> Void)?
    private let local: any GenericFoodSearching
    private let database: (any FoodSearchEnriching)?
    private let gemini: (any FoodSearchEnriching)?
    private let ids: any LedgerIDGenerating
    private var fallbackEvidence: GenericFoodSearchOutcome?
    private let assessment: any FoodSearchCoverageAssessing
    private var services: FoodSearchServiceAvailability
    private var session: FoodSearchSession
    private var request: GenericFoodSearchRequest?
    private var task: Task<Void, Never>?

    public init(local: any GenericFoodSearching, database: (any FoodSearchEnriching)? = nil,
                gemini: (any FoodSearchEnriching)? = nil,
                services: FoodSearchServiceAvailability = .init(onlineDatabase: .disabled, gemini: .disabled),
                assessment: any FoodSearchCoverageAssessing = ConservativeFoodSearchCoverageAssessment(),
                sessionID: UUID = UUID(), ids: any LedgerIDGenerating = RandomLedgerIDGenerator()) {
        self.local = local
        self.database = database
        self.gemini = gemini
        self.services = services
        self.assessment = assessment
        self.ids = ids
        session = FoodSearchSession(sessionID: sessionID)
    }

    deinit { task?.cancel() }

    /// No network work occurs until after the synchronous local snapshot is published.
    public func search(_ request: GenericFoodSearchRequest) {
        cancel()
        self.request = request
        snapshot = ProgressiveFoodSearchSnapshot(outcome: nil, pending: .local, failures: [])
        let parsedPreparation = FoodQueryPreparationPolicy.kind(for: request.parsedQuery)
        let explicitPreparation = request.identity.preparation?.kind
        let conflicts = parsedPreparation != nil && explicitPreparation != nil && explicitPreparation != .unknown && parsedPreparation != explicitPreparation
        guard request.parsedQuery.allowsCandidateDiscovery, !conflicts else {
            snapshot = ProgressiveFoodSearchSnapshot(outcome: nil, pending: nil,
                failures: [.init(stage: .local, reason: .invalidQuery)])
            onUpdate?(snapshot)
            return
        }
        let available = FoodSearchServiceAvailability(
            onlineDatabase: database == nil ? .unavailable : services.onlineDatabase,
            gemini: gemini == nil ? .unavailable : services.gemini)
        let token = session.begin(services: available)
        do {
            let evidence = try request.captureEvidence ?? CaptureEvidence(evidenceID: ids.makeID(EvidenceTag.self),
                kind: .genericSearch, capturedAt: request.capturedAt, locale: request.locale,
                captureMethod: LedgerText("typed_generic_food_search"), captureMethodVersion: LedgerText("progressive-search-v1"),
                originalPayload: .text(request.text))
            fallbackEvidence = .noResult(GenericFoodNoResultRoute(evidence: evidence, additionalEvidence: request.additionalEvidence))
            let localRequest = GenericFoodSearchRequest(text: request.text, identity: request.identity,
                capturedAt: request.capturedAt, locale: request.locale, captureEvidence: evidence,
                additionalEvidence: request.additionalEvidence)
            receive(try local.search(localRequest), token: token)
        } catch {
            if fallbackEvidence == nil {
                session.cancel()
                snapshot = ProgressiveFoodSearchSnapshot(outcome: nil, pending: nil,
                    failures: [.init(stage: .local, reason: .invalidResponse)])
                onUpdate?(snapshot)
            } else { fail(token, error: error) }
        }
    }

    /// Caller invokes on query/preparation edits, navigation, selection or decline.
    /// Existing results remain an immutable review snapshot; no late result may publish.
    public func cancel() {
        session.cancel()
        task?.cancel()
        task = nil
        request = nil
        fallbackEvidence = nil
        snapshot = ProgressiveFoodSearchSnapshot(outcome: snapshot.outcome, pending: nil, failures: snapshot.failures, reports: snapshot.reports)
    }

    public func setServices(_ services: FoodSearchServiceAvailability) {
        guard self.services != services else { return }
        let wasActive = request != nil
        cancel()
        self.services = services
        if wasActive { onUpdate?(snapshot) }
    }

    private func receive(_ incoming: GenericFoodSearchOutcome, token: FoodSearchStageToken) {
        guard session.pending == token, let request else { return }
        do {
            if case let .confirmation(route) = incoming {
                guard token.stage == .local || route.reuse == nil,
                      !route.matches.contains(where: { ConservativeFoodSearchCoverageAssessment.hasHardContradiction($0.candidate.candidate, request: request) }) else {
                    throw FoodSearchEnrichmentError.invalidResponse
                }
            }
            let merged = try FoodSearchResultMerger.merge(snapshot.outcome ?? (token.stage == .local ? nil : fallbackEvidence), incoming)
            let coverage = assessment.assess(merged, for: request)
            guard case let .accepted(next) = session.complete(token, candidates: coverage) else { return }
            let priorIDs = Set(Self.candidateIDs(snapshot.outcome))
            let added = Self.candidateIDs(merged).filter { !priorIDs.contains($0) }
            let discovery: FoodWebDiscoveryResult?
            let reviewFailure: FoodSourceReviewFailure?
            switch incoming {
            case let .confirmation(route): discovery = route.sourceDiscovery; reviewFailure = route.sourceReviewFailure
            case let .noResult(route): discovery = route.sourceDiscovery; reviewFailure = route.sourceReviewFailure
            }
            let report = FoodSearchStageReport(stage: token.stage, addedCandidateIDs: added,
                sourceReviewFailure: reviewFailure, hasSourceLinks: discovery?.leads.isEmpty == false)
            snapshot = ProgressiveFoodSearchSnapshot(outcome: merged, pending: next?.stage, failures: snapshot.failures,
                reports: snapshot.reports + [report])
            onUpdate?(snapshot)
            if let next { launch(next) }
        } catch { fail(token, error: error) }
    }

    private func fail(_ token: FoodSearchStageToken, error: Error) {
        guard case let .accepted(next) = session.fail(token) else { return }
        let reason = error as? FoodSearchEnrichmentError ?? (error is FoodLedgerValidationError ? .invalidResponse : .unavailable)
        if reason == .credentialRejected {
            switch token.stage {
            case .gemini: services = .init(onlineDatabase: services.onlineDatabase, gemini: .unavailable)
            case .onlineDatabase: services = .init(onlineDatabase: .unavailable, gemini: services.gemini)
            case .local: break
            }
        }
        snapshot = ProgressiveFoodSearchSnapshot(outcome: snapshot.outcome, pending: next?.stage,
            failures: snapshot.failures + [.init(stage: token.stage, reason: reason)],
            reports: snapshot.reports + [.init(stage: token.stage, failure: reason)])
        onUpdate?(snapshot)
        if let next { launch(next) }
    }

    private static func candidateIDs(_ outcome: GenericFoodSearchOutcome?) -> [FoodSearchCandidateID] {
        if case let .confirmation(route) = outcome { return route.matches.map(\.searchID) }
        return []
    }

    private func launch(_ token: FoodSearchStageToken) {
        // A subscriber can cancel or start another query while observing an update.
        guard session.pending == token, let request else { return }
        let provider = token.stage == .onlineDatabase ? database : gemini
        guard let provider else { fail(token, error: FoodSearchEnrichmentError.unavailable); return }
        let query: FoodSearchRemoteQuery
        do {
            var terms = request.text.value
            // The selected preparation is a displayed food-search term, not ledger metadata.
            if FoodQueryPreparationPolicy.kind(for: request.parsedQuery) == nil,
               let preparation = request.identity.preparation, preparation.kind != .unknown {
                terms += " " + (preparation.method?.value ?? preparation.kind.rawValue.replacingOccurrences(of: "_", with: " "))
            }
            query = try FoodSearchRemoteQuery(foodTerms: terms)
        } catch { fail(token, error: error); return }
        task = Task { [weak self] in
            do {
                let result = try await provider.enrich(query)
                guard !Task.isCancelled else { return }
                self?.receive(result, token: token)
            } catch {
                guard !Task.isCancelled else { return }
                self?.fail(token, error: error)
            }
        }
    }
}
