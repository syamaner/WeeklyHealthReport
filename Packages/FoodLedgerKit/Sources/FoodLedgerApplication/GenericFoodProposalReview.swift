import Foundation
import FoodLedgerDomain

public protocol FoodDocumentCapturing: Sendable {
    func capture(_ url: URL) async throws -> CapturedFoodDocument
}

public protocol FoodProposalExtracting: Sendable {
    func extract(foodTerms: String, documents: [CapturedFoodDocument], key: String) async throws -> FoodProposalExtraction
}

public protocol FoodProposalSelecting: Sendable {
    func select(foodTerms: String, documents: [CapturedFoodDocument], validation: FoodProposalValidation,
                key: String) async throws -> FoodProposalSelection
}

public enum FoodSourceLeadDecision: Equatable, Sendable {
    case selected(index: Int, reason: String)
    case abstain(reason: String)
}

public protocol FoodSourceLeadSelecting: Sendable {
    func chooseSource(foodTerms: String, leads: [FoodWebLead], key: String) async throws -> FoodSourceLeadDecision
}

public struct GenericFoodProposalReview: Equatable, Sendable {
    public static let choicePolicyVersion = "food-proposal-review-choice-v2"
    public let foodTerms: String
    public let discovery: FoodWebDiscoveryResult?
    public let documents: [CapturedFoodDocument]
    public let validation: FoodProposalValidation
    public let selection: FoodProposalSelection?
    public let rankingUnavailable: Bool
    public let attemptedSourceURL: URL?

    /// Literal binding is insufficient when the model declines applicability.
    /// A suggestion only permits explicit review; it never authorises a save.
    public var suggestedChoice: String {
        guard !rankingUnavailable, let selection else {
            return validation.extractorPreferredId == "none" ? "none" : "clarify"
        }
        if let proposal = validation.candidates.first(where: { $0.id == selection.choice }),
           FoodProposalQueryPolicy.hasBasisConflict(query: foodTerms, basis: proposal.candidate.basis) { return "clarify" }
        return selection.choice
    }
    public func permitsConfirmation(of proposal: BoundFoodProposal) -> Bool {
        selection != nil && !rankingUnavailable && proposal.id == suggestedChoice && proposal.selectionEligible && validation.candidates.contains(proposal)
    }

    public init(foodTerms: String, discovery: FoodWebDiscoveryResult?, documents: [CapturedFoodDocument],
                validation: FoodProposalValidation, selection: FoodProposalSelection?, rankingUnavailable: Bool = false,
                attemptedSourceURL: URL? = nil) {
        self.foodTerms = foodTerms; self.discovery = discovery; self.documents = documents
        self.validation = validation; self.selection = selection
        self.rankingUnavailable = rankingUnavailable
        self.attemptedSourceURL = attemptedSourceURL
    }
}

public struct GenericFoodProposalPartialFailure: Error, Sendable {
    public enum Reason: Sendable {
        case acquisition(FoodSourceAcquisitionError)
        case provider(FoodWebDiscoveryError)
        case invalidProposal
        case sourceNotSuggested
        case sourceMarketConflict
    }
    public let discovery: FoodWebDiscoveryResult?
    public let reason: Reason
    public let attemptedSourceURL: URL?
    public init(discovery: FoodWebDiscoveryResult?, reason: Reason, attemptedSourceURL: URL? = nil) {
        self.discovery = discovery; self.reason = reason; self.attemptedSourceURL = attemptedSourceURL
    }
}

public enum GenericFoodProposalReviewError: Error, Equatable, Sendable {
    case noSourceLinks, alreadyRunning
}

public protocol GenericFoodProposalReviewing: Sendable {
    func review(foodTerms: String, sourceURL: URL?, key: String) async throws -> GenericFoodProposalReview
}

/// One discovery and optional source choice (unless a URL was supplied), one
/// capture/extraction and optional candidate selection. No retries or ledger writes.
public actor GenericFoodProposalReviewer: GenericFoodProposalReviewing {
    private let discovery: any FoodWebDiscovering
    private let capture: any FoodDocumentCapturing
    private let extraction: any FoodProposalExtracting
    private let sourceSelection: (any FoodSourceLeadSelecting)?
    private let selection: (any FoodProposalSelecting)?
    private let timeout: Duration
    private var active = false

    public init(discovery: any FoodWebDiscovering, capture: any FoodDocumentCapturing,
                extraction: any FoodProposalExtracting, sourceSelection: (any FoodSourceLeadSelecting)? = nil,
                selection: (any FoodProposalSelecting)? = nil,
                timeout: Duration = .seconds(150)) {
        self.discovery = discovery; self.capture = capture; self.extraction = extraction; self.selection = selection
        self.sourceSelection = sourceSelection
        self.timeout = min(max(timeout, .milliseconds(1)), .seconds(150))
    }

    public func review(foodTerms: String, sourceURL: URL? = nil, key: String) async throws -> GenericFoodProposalReview {
        let terms = foodTerms.trimmingCharacters(in: .whitespacesAndNewlines)
        guard FoodWebKeySyntax.isValid(key) else { throw FoodWebDiscoveryError.credentialRejected }
        guard !terms.isEmpty, terms.count <= 300, !terms.contains(key),
              sourceURL.map({ !$0.absoluteString.contains(key) && FoodWebLinkPolicy.isAllowed($0) }) ?? true else {
            throw FoodWebDiscoveryError.invalidQuery
        }
        guard !active else { throw GenericFoodProposalReviewError.alreadyRunning }
        active = true; defer { active = false }
        let timeout = timeout
        return try await withThrowingTaskGroup(of: GenericFoodProposalReview.self) { group in
            group.addTask { try await self.run(terms: terms, sourceURL: sourceURL, key: key) }
            group.addTask { try await Task.sleep(for: timeout); throw FoodWebDiscoveryError.timedOut }
            defer { group.cancelAll() }
            let result = try await group.next()!
            try Task.checkCancellation()
            return result
        }
    }

    private func run(terms: String, sourceURL: URL?, key: String) async throws -> GenericFoodProposalReview {
        try Task.checkCancellation()
        let result: FoodWebDiscoveryResult?
        let url: URL
        if let sourceURL { url = sourceURL; result = nil }
        else {
            let found = try await discovery.discover(foodTerms: terms, key: key)
            try Task.checkCancellation()
            let offered = Array(found.leads.filter { FoodWebLinkPolicy.isAllowed($0.url) }.prefix(3))
            guard let first = offered.first else {
                throw GenericFoodProposalReviewError.noSourceLinks
            }
            result = found
            if let sourceSelection {
                let decision: FoodSourceLeadDecision
                do { decision = try await sourceSelection.chooseSource(foodTerms: terms, leads: offered, key: key) }
                catch {
                    try Task.checkCancellation()
                    if error is CancellationError || error as? FoodWebDiscoveryError == .credentialRejected { throw error }
                    throw GenericFoodProposalPartialFailure(discovery: found, reason: .provider(error as? FoodWebDiscoveryError ?? .invalidResponse))
                }
                try Task.checkCancellation()
                switch decision {
                case let .selected(index, _):
                    guard offered.indices.contains(index) else {
                        throw GenericFoodProposalPartialFailure(discovery: found, reason: .provider(.invalidResponse))
                    }
                    url = offered[index].url
                case .abstain:
                    throw GenericFoodProposalPartialFailure(discovery: found, reason: .sourceNotSuggested)
                }
            } else { url = first.url }
        }
        guard !FoodSourceMarketPolicy.hasExplicitConflict(foodTerms: terms, url: url) else {
            throw GenericFoodProposalPartialFailure(discovery: result, reason: .sourceMarketConflict)
        }
        let document: CapturedFoodDocument
        do { document = try await capture.capture(url) }
        catch {
            try Task.checkCancellation()
            if error is CancellationError { throw error }
            throw GenericFoodProposalPartialFailure(discovery: result, reason: .acquisition(error as? FoodSourceAcquisitionError ?? .invalidResponse), attemptedSourceURL: url)
        }
        try Task.checkCancellation()
        try document.validate()
        if let finalURL = URL(string: document.url), FoodSourceMarketPolicy.hasExplicitConflict(foodTerms: terms, url: finalURL) {
            throw GenericFoodProposalPartialFailure(discovery: result, reason: .sourceMarketConflict, attemptedSourceURL: url)
        }
        guard !document.blocks.contains(where: { $0.text.contains(key) }) else { throw GenericFoodProposalError.invalidDocument }
        let extracted: FoodProposalExtraction
        do { extracted = try await extraction.extract(foodTerms: terms, documents: [document], key: key) }
        catch {
            try Task.checkCancellation()
            if error is CancellationError || error as? FoodWebDiscoveryError == .credentialRejected { throw error }
            throw GenericFoodProposalPartialFailure(discovery: result, reason: .provider(error as? FoodWebDiscoveryError ?? .invalidResponse), attemptedSourceURL: url)
        }
        try Task.checkCancellation()
        let validation: FoodProposalValidation
        do { validation = try FoodProposalBinding.validate(extracted, documents: [document]) }
        catch { throw GenericFoodProposalPartialFailure(discovery: result, reason: .invalidProposal, attemptedSourceURL: url) }
        var selected: FoodProposalSelection?
        var rankingUnavailable = false
        if let selection, validation.candidates.contains(where: \.selectionEligible) {
            do {
                let suggested = try await selection.select(foodTerms: terms, documents: [document], validation: validation, key: key)
                // Rebind even a substituted selector to this request's offered candidates.
                selected = suggested.probabilities.isEmpty && suggested.rawConfidence == nil
                    ? try FoodProposalSelection(unscoredChoice: suggested.choice, validation: validation)
                    : try FoodProposalSelection(choice: suggested.choice, probabilities: suggested.probabilities,
                        rawConfidence: suggested.rawConfidence, validation: validation)
            } catch {
                try Task.checkCancellation()
                if error is CancellationError || error as? FoodWebDiscoveryError == .credentialRejected { throw error }
                rankingUnavailable = true
            }
        }
        try Task.checkCancellation()
        return GenericFoodProposalReview(foodTerms: terms, discovery: result, documents: [document],
                                         validation: validation, selection: selected, rankingUnavailable: rankingUnavailable, attemptedSourceURL: url)
    }
}
