import Foundation
import FoodLedgerDomain

/// Whether a capture may read a page beyond `FoodDocumentBounds.current` in part (#508 phase 3,
/// `food-document-block-selection-v1`). The reviewer decides it for each capture (source order,
/// docs/web-lookup-part-read-phase3-gate.md section 5); under `refused` such a page is refused.
public enum FoodDocumentPartReadPermission: Sendable, Equatable {
    case refused, permitted
}

public protocol FoodDocumentCapturing: Sendable {
    func capture(_ url: URL, partRead: FoodDocumentPartReadPermission) async throws -> CapturedFoodDocument
}

public protocol FoodProposalExtracting: Sendable {
    func extract(foodTerms: String, documents: [CapturedFoodDocument], key: String) async throws -> FoodProposalExtraction
}

public protocol FoodProposalSelecting: Sendable {
    func select(foodTerms: String, documents: [CapturedFoodDocument], validation: FoodProposalValidation,
                key: String) async throws -> FoodProposalSelection
}

public enum FoodSourceLeadPurpose: Equatable, Sendable {
    case primaryProduct, representativeEstimate
}

public enum FoodSourceLeadDecision: Equatable, Sendable {
    case selected(index: Int, purpose: FoodSourceLeadPurpose, reason: String)
    case abstain(reason: String)
}

public protocol FoodSourceLeadSelecting: Sendable {
    func chooseSource(foodTerms: String, leads: [FoodWebLead], key: String) async throws -> FoodSourceLeadDecision
}

public struct GenericFoodProposalReview: Equatable, Sendable {
    /// The offer table of #508 (contract section 8.3), recorded by manifest v3 as its choice policy.
    public static let choicePolicyVersion = FoodProposalReviewGateRecordV3.choicePolicyVersion
    public let foodTerms: String
    public let discovery: FoodWebDiscoveryResult?
    public let documents: [CapturedFoodDocument]
    public let validation: FoodProposalValidation
    public let selection: FoodProposalSelection?
    public let rankingUnavailable: Bool
    /// Why the check did not produce a usable answer, when it was attempted and failed (#500).
    public let selectionFailure: FoodProposalSelectionFailure?
    public let attemptedSourceURL: URL?
    public let sourceAttempts: [URL]
    public let representativeSourceOnly: Bool

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
    /// The candidates the person may confirm (#508 phase 2 gate, section 3). Always computed from
    /// the recorded answer, the validation and the query; no caller can supply it.
    public var offer: FoodProposalOffer { FoodProposalOffer(review: self) }
    /// Only an offered candidate can be prepared; a pre-selection never authorises a save.
    public func permitsConfirmation(of proposal: BoundFoodProposal) -> Bool {
        offer.candidates.contains(proposal)
    }

    public init(foodTerms: String, discovery: FoodWebDiscoveryResult?, documents: [CapturedFoodDocument],
                validation: FoodProposalValidation, selection: FoodProposalSelection?, rankingUnavailable: Bool = false,
                selectionFailure: FoodProposalSelectionFailure? = nil,
                attemptedSourceURL: URL? = nil, sourceAttempts: [URL] = [], representativeSourceOnly: Bool = false) {
        self.foodTerms = foodTerms; self.discovery = discovery; self.documents = documents
        self.validation = validation; self.selection = selection
        // A recorded failure always means the check is unavailable.
        self.rankingUnavailable = rankingUnavailable || selectionFailure != nil
        self.selectionFailure = selectionFailure
        self.attemptedSourceURL = attemptedSourceURL
        self.sourceAttempts = sourceAttempts.isEmpty ? attemptedSourceURL.map { [$0] } ?? [] : sourceAttempts
        self.representativeSourceOnly = representativeSourceOnly
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
    public let sourceAttempts: [URL]
    public init(discovery: FoodWebDiscoveryResult?, reason: Reason, attemptedSourceURL: URL? = nil, sourceAttempts: [URL] = []) {
        self.discovery = discovery; self.reason = reason; self.attemptedSourceURL = attemptedSourceURL
        self.sourceAttempts = sourceAttempts.isEmpty ? attemptedSourceURL.map { [$0] } ?? [] : sourceAttempts
    }
}

public enum GenericFoodProposalReviewError: Error, Equatable, Sendable {
    case noSourceLinks, alreadyRunning
}

public protocol GenericFoodProposalReviewing: Sendable {
    func review(foodTerms: String, sourceURL: URL?, key: String) async throws -> GenericFoodProposalReview
}

/// One discovery; at most two distinct selected source captures. A second source
/// is considered only after empty extraction or recoverable acquisition failure.
/// Source order for part-read pages (#508): a supplied address, a run with no source selector and
/// the second capture may read a page in part; the first capture of a discovery run may only when
/// no other admissible lead exists, so a larger page first yields to the next lead.
/// No repeated discovery, cross-source merging or ledger writes. Transient model-call retries,
/// where composed, live inside the provider adapter (#500); this orchestration never repeats a step.
public actor GenericFoodProposalReviewer: GenericFoodProposalReviewing {
    private let discovery: any FoodWebDiscovering
    private let capture: any FoodDocumentCapturing
    private let extraction: any FoodProposalExtracting
    private let sourceSelection: (any FoodSourceLeadSelecting)?
    private let selection: (any FoodProposalSelecting)?
    private let timeout: Duration
    /// The Settings › OpenRouter gate, asked as `webLookup` before each page capture and each model
    /// call (docs/openrouter-single-consent-v1-amendment.md O1.2). Required: missing wiring does not compile.
    private let egress: any OpenRouterEgressPermitting
    private var active = false

    public init(egress: any OpenRouterEgressPermitting,
                discovery: any FoodWebDiscovering, capture: any FoodDocumentCapturing,
                extraction: any FoodProposalExtracting, sourceSelection: (any FoodSourceLeadSelecting)? = nil,
                selection: (any FoodProposalSelecting)? = nil,
                timeout: Duration = .seconds(150)) {
        self.egress = egress
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
        guard sourceURL == nil, sourceSelection != nil else {
            return try await runSingle(terms: terms, sourceURL: sourceURL, key: key)
        }
        let original: FoodWebDiscoveryResult
        let attempts: [URL]
        let excluded: Set<URL>
        var firstReview: GenericFoodProposalReview?
        var firstFailure: GenericFoodProposalPartialFailure?
        do {
            let first = try await runSingle(terms: terms, sourceURL: nil, key: key)
            guard first.validation.candidates.isEmpty, first.validation.rejected.isEmpty,
                  first.validation.extractorPreferredId == "none", let found = first.discovery,
                  let attempted = first.attemptedSourceURL else { return first }
            firstReview = first
            original = found; attempts = first.sourceAttempts
            excluded = Set([attempted] + first.documents.compactMap { URL(string: $0.url) })
        } catch let failure as GenericFoodProposalPartialFailure {
            guard case let .acquisition(reason) = failure.reason,
                  [.unsupportedContent, .unavailable, .responseTooLarge].contains(reason),
                  let found = failure.discovery, let attempted = failure.attemptedSourceURL else { throw failure }
            firstFailure = failure
            original = found; attempts = [attempted]; excluded = [attempted]
        }
        try Task.checkCancellation()
        let remaining = Self.admissibleLeads(original, excluding: excluded)
        guard !remaining.isEmpty else {
            if let firstReview { return firstReview }
            if let firstFailure { throw firstFailure }
            throw GenericFoodProposalPartialFailure(discovery: original, reason: .sourceNotSuggested,
                attemptedSourceURL: attempts.last)
        }
        let narrowed = FoodWebDiscoveryResult(leads: Array(remaining.prefix(3)), searchSuggestionsHTML: nil,
            responseText: original.responseText)
        do {
            let next = try await runSingle(terms: terms, sourceURL: nil, key: key, existingDiscovery: narrowed)
            return GenericFoodProposalReview(foodTerms: next.foodTerms, discovery: original, documents: next.documents,
                validation: next.validation, selection: next.selection, rankingUnavailable: next.rankingUnavailable,
                selectionFailure: next.selectionFailure,
                attemptedSourceURL: next.attemptedSourceURL, sourceAttempts: attempts + next.sourceAttempts,
                representativeSourceOnly: next.representativeSourceOnly)
        } catch let failure as GenericFoodProposalPartialFailure {
            if case .sourceNotSuggested = failure.reason, let firstReview { return firstReview }
            throw GenericFoodProposalPartialFailure(discovery: original, reason: failure.reason,
                attemptedSourceURL: failure.attemptedSourceURL ?? attempts.last,
                sourceAttempts: attempts + failure.sourceAttempts)
        }
    }

    /// Throws `.notPermitted` when Settings › OpenRouter is off, before a page fetch or model call.
    private func permit() throws {
        guard egress.permits(.webLookup) else { throw FoodWebDiscoveryError.notPermitted }
    }

    /// Errors rethrown unwrapped, never turned into a partial failure, a selection failure or an
    /// acquisition failure: cancellation, a rejected key and a refusal (O1.2).
    static func passesThrough(_ error: any Error) -> Bool {
        error is CancellationError || [.credentialRejected, .notPermitted].contains(error as? FoodWebDiscoveryError)
    }

    /// The second-lead pool: every lead of the discovery result that is not excluded and that the
    /// link policy admits. The part-read predicate uses the same filter, so they cannot drift.
    static func admissibleLeads(_ result: FoodWebDiscoveryResult, excluding excluded: Set<URL>) -> [FoodWebLead] {
        result.leads.filter { !excluded.contains($0.url) && FoodWebLinkPolicy.isAllowed($0.url) }
    }

    /// Evaluated once before the first capture of a discovery run with a selector (#508, contract section 7).
    static func hasAnotherAdmissibleLead(_ result: FoodWebDiscoveryResult, besides selected: URL) -> Bool {
        !admissibleLeads(result, excluding: [selected]).isEmpty
    }

    private func runSingle(terms: String, sourceURL: URL?, key: String,
                           existingDiscovery: FoodWebDiscoveryResult? = nil) async throws -> GenericFoodProposalReview {
        try Task.checkCancellation()
        let result: FoodWebDiscoveryResult?
        let url: URL
        var representativeSourceOnly = false
        let partRead: FoodDocumentPartReadPermission
        if let sourceURL { url = sourceURL; result = nil; partRead = .permitted }
        else {
            let found: FoodWebDiscoveryResult
            if let existingDiscovery { found = existingDiscovery }
            else { try permit(); found = try await discovery.discover(foodTerms: terms, key: key) }
            try Task.checkCancellation()
            let offered = Array(found.leads.filter { FoodWebLinkPolicy.isAllowed($0.url) }.prefix(3))
            guard let first = offered.first else {
                throw GenericFoodProposalReviewError.noSourceLinks
            }
            result = found
            if let sourceSelection {
                let decision: FoodSourceLeadDecision
                try permit()
                do { decision = try await sourceSelection.chooseSource(foodTerms: terms, leads: offered, key: key) }
                catch {
                    try Task.checkCancellation()
                    if Self.passesThrough(error) { throw error }
                    throw GenericFoodProposalPartialFailure(discovery: found, reason: .provider(error as? FoodWebDiscoveryError ?? .invalidResponse))
                }
                try Task.checkCancellation()
                switch decision {
                case let .selected(index, purpose, _):
                    guard offered.indices.contains(index) else {
                        throw GenericFoodProposalPartialFailure(discovery: found, reason: .provider(.invalidResponse))
                    }
                    url = offered[index].url
                    representativeSourceOnly = purpose == .representativeEstimate
                case .abstain:
                    throw GenericFoodProposalPartialFailure(discovery: found, reason: .sourceNotSuggested)
                }
                partRead = existingDiscovery != nil || !Self.hasAnotherAdmissibleLead(found, besides: url) ? .permitted : .refused
            } else { url = first.url; partRead = .permitted }
        }
        guard !FoodSourceMarketPolicy.hasExplicitConflict(foodTerms: terms, url: url) else {
            throw GenericFoodProposalPartialFailure(discovery: result, reason: .sourceMarketConflict)
        }
        let document: CapturedFoodDocument
        // Outside the capture handler, so a refusal never reaches the second-lead retry (O1.2).
        try permit()
        do { document = try await capture.capture(url, partRead: partRead) }
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
        try permit()
        do { extracted = try await extraction.extract(foodTerms: terms, documents: [document], key: key) }
        catch {
            try Task.checkCancellation()
            if Self.passesThrough(error) { throw error }
            throw GenericFoodProposalPartialFailure(discovery: result, reason: .provider(error as? FoodWebDiscoveryError ?? .invalidResponse), attemptedSourceURL: url)
        }
        try Task.checkCancellation()
        let validation: FoodProposalValidation
        do { validation = try FoodProposalBinding.validate(extracted, documents: [document]) }
        catch { throw GenericFoodProposalPartialFailure(discovery: result, reason: .invalidProposal, attemptedSourceURL: url) }
        var selected: FoodProposalSelection?
        var selectionFailure: FoodProposalSelectionFailure?
        // The check runs whenever a candidate is choosable, including competing panels (#508).
        if let selection, validation.candidates.contains(where: \.choosable) {
            try permit()
            do {
                let suggested = try await selection.select(foodTerms: terms, documents: [document], validation: validation, key: key)
                // Rebind even a substituted selector to this request's offered candidates.
                selected = suggested.probabilities.isEmpty && suggested.rawConfidence == nil
                    ? try FoodProposalSelection(unscoredChoice: suggested.choice, validation: validation)
                    : try FoodProposalSelection(choice: suggested.choice, probabilities: suggested.probabilities,
                        rawConfidence: suggested.rawConfidence, validation: validation)
            } catch {
                try Task.checkCancellation()
                if Self.passesThrough(error) { throw error }
                selectionFailure = FoodProposalSelectionFailure(error)
            }
        }
        try Task.checkCancellation()
        return GenericFoodProposalReview(foodTerms: terms, discovery: result, documents: [document],
                                         validation: validation, selection: selected, selectionFailure: selectionFailure, attemptedSourceURL: url, representativeSourceOnly: representativeSourceOnly)
    }
}

/// The offer table of contract #508 section 8.3, keyed on the answer the check recorded. Offerable
/// means choosable (the domain rule) with no basis conflict with the query; identity and conflict
/// are evaluated only between offerable candidates, never read from `BoundFoodProposal.status`.
public struct FoodProposalOffer: Equatable, Sendable {
    /// Offered candidates in extraction order.
    public let candidates: [BoundFoodProposal]
    /// The model's named candidate, shown as the pre-selection; `nil` when a pick is required.
    public let preselectedID: String?
    /// True for a `clarify` answer with competing panels: the warning line of answer O4 applies.
    public let warns: Bool
    public var isEmpty: Bool { candidates.isEmpty }
    public var requiresPick: Bool { !candidates.isEmpty && preselectedID == nil }

    static let none = FoodProposalOffer(candidates: [], preselectedID: nil, warns: false)
    private init(candidates: [BoundFoodProposal], preselectedID: String?, warns: Bool) {
        self.candidates = candidates; self.preselectedID = preselectedID; self.warns = warns
    }

    init(review: GenericFoodProposalReview) {
        guard let selection = review.selection, !review.rankingUnavailable else { self = .none; return }
        let offerable = review.validation.candidates.filter {
            $0.choosable && !FoodProposalQueryPolicy.hasBasisConflict(query: review.foodTerms, basis: $0.candidate.basis)
        }
        if selection.choice == "clarify" {
            for anchor in offerable {
                let group = offerable.filter { FoodProposalBinding.sameIdentity($0.candidate, anchor.candidate) }
                let conflicting = group.filter { member in
                    group.contains { $0.id != member.id && FoodProposalBinding.conflicting(member.candidate, $0.candidate) }
                }
                if conflicting.count >= 2 { self.init(candidates: conflicting, preselectedID: nil, warns: true); return }
            }
            self = .none; return
        }
        guard let named = offerable.first(where: { $0.id == selection.choice }) else { self = .none; return }
        self.init(candidates: offerable.filter { FoodProposalBinding.sameIdentity($0.candidate, named.candidate) },
                  preselectedID: named.id, warns: false)
    }
}
