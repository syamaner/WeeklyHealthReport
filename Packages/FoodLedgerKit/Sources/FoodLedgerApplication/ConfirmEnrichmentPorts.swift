import Foundation
import FoodLedgerDomain

// Confirm enrichment v1 ports (docs/confirm-enrichment-openrouter-v1-phase.md section 4). Each port is
// consumer-owned and passes a shared contract suite in FoodLedgerTestSupport. No framework, URL, HTTP,
// file or clock type crosses a port: bodies and answers are `Data`, times come from injected ports.

/// The two parts of Confirm enrichment: A (food details through Jev) and B (unknown nutrients).
public enum ConfirmEnrichmentPart: String, Codable, Sendable, CaseIterable {
    case details
    case nutrients

    /// The request use the O1 gate is asked for.
    public var use: OpenRouterUse {
        switch self {
        case .details: .confirmEnrichmentDetails
        case .nutrients: .confirmEnrichmentNutrients
        }
    }

    /// The catalogue check use the O1 gate is asked for before each catalogue fetch.
    public var catalogueUse: OpenRouterUse {
        switch self {
        case .details: .confirmEnrichmentDetailsCatalogueCheck
        case .nutrients: .confirmEnrichmentNutrientsCatalogueCheck
        }
    }

    /// The whole-request cap in micro-dollars: $0.01 for A and $0.04 for B (CE1.3; gate section 2.6). B was
    /// raised from $0.02 on 22 November 2026 by the owner, when today's prices put its W at about $0.029.
    public var perRequestCapMicroUSD: Int {
        switch self {
        case .details: 10_000
        case .nutrients: 40_000
        }
    }
}

/// One route version's fixed values, passed in from `ConfirmEnrichmentRoutes` at the composition root,
/// so no application file holds an OpenRouter address (gate section 3.3 item 3). It holds no prices:
/// those come from the day's catalogue check.
public struct ConfirmEnrichmentRoute: Equatable, Sendable {
    public let part: ConfirmEnrichmentPart
    /// `confirm-details-route-v1` or `confirm-nutrient-route-v1`.
    public let version: String
    /// The request model slug.
    public let model: String
    /// The model slugs a response may name (the request slug and any dated slug pinned by the route).
    public let acceptedModels: Set<String>
    /// The provider a response must name.
    public let provider: String
    /// The pinned endpoint (the provider block's `only` and `order`).
    public let providerEndpoint: String
    /// The request address, recorded in a capture's `endpoint` field.
    public let endpoint: String
    public let promptCeilingTokens: Int
    public let completionCeilingTokens: Int
    /// Zero when the route has no separate reasoning limit.
    public let reasoningLimitTokens: Int
    /// Whether reasoning tokens are billed outside the completion ceiling.
    public let reasoningBilledSeparately: Bool
    /// Whether `max_tokens` is sent; when it is not, the completion ceiling is the response byte limit.
    public let sendsMaxTokens: Bool

    public init(part: ConfirmEnrichmentPart, version: String, model: String, acceptedModels: Set<String>, provider: String,
                providerEndpoint: String, endpoint: String, promptCeilingTokens: Int, completionCeilingTokens: Int,
                reasoningLimitTokens: Int, reasoningBilledSeparately: Bool, sendsMaxTokens: Bool) {
        self.part = part; self.version = version; self.model = model; self.acceptedModels = acceptedModels
        self.provider = provider; self.providerEndpoint = providerEndpoint; self.endpoint = endpoint
        self.promptCeilingTokens = promptCeilingTokens; self.completionCeilingTokens = completionCeilingTokens
        self.reasoningLimitTokens = reasoningLimitTokens; self.reasoningBilledSeparately = reasoningBilledSeparately
        self.sendsMaxTokens = sendsMaxTokens
    }
}

/// Prices per token from the day's catalogue check, in US dollars.
public struct ConfirmEnrichmentPrices: Equatable, Sendable {
    public let promptPerTokenUSD: Decimal
    public let completionPerTokenUSD: Decimal

    public init(promptPerTokenUSD: Decimal, completionPerTokenUSD: Decimal) {
        self.promptPerTokenUSD = promptPerTokenUSD; self.completionPerTokenUSD = completionPerTokenUSD
    }
}

/// What one route check returned (CE-T6, gate section 6 step 4).
public enum ConfirmEnrichmentRouteCheckResult: Equatable, Sendable {
    /// The endpoint is listed with zero data retention and data collection denied, at these prices.
    case passed(ConfirmEnrichmentPrices)
    /// The catalogue could not be reached: checked again on the next request.
    case connectionFailed
    /// The gate refused a catalogue fetch: nothing more was sent and the part stays available.
    case notPermitted
    /// Any other failure: the part is unavailable for the local day.
    case unavailable
}

/// The on-the-day catalogue check. It asks the gate before each of its two keyless fetches with the
/// catalogue use it is given.
public protocol ConfirmEnrichmentRouteChecking: Sendable {
    func check(_ part: ConfirmEnrichmentPart, catalogueUse: OpenRouterUse) async -> ConfirmEnrichmentRouteCheckResult
}

/// Why an attempt sent nothing.
public enum ConfirmEnrichmentNotSentReason: Equatable, Sendable {
    case notPermitted
    case noKey
    case cancelled
}

/// A failure after bytes may have left the device.
public enum ConfirmEnrichmentTransportFailure: Equatable, Sendable {
    case offline, timedOut, connectionFailed, cancelled
    /// The reply passed the response byte limit while being read.
    case tooLarge
}

/// One HTTP attempt (gate section 4). `.sent` carries no generation ID, cost or token count: those come
/// from the one pure usage parse of the bytes, which a cache hit also runs.
public enum ConfirmEnrichmentAttemptResult: Equatable, Sendable {
    case notSent(ConfirmEnrichmentNotSentReason)
    case sent(status: Int, body: Data, retryAfter: String?)
    case transportFailed(ConfirmEnrichmentTransportFailure)
}

/// A (Jev through System One): one attempt with the exact body bytes, within `timeout` seconds.
public protocol FoodDetailsSuggesting: Sendable {
    func attempt(_ body: Data, timeout: TimeInterval) async -> ConfirmEnrichmentAttemptResult
}

/// B (the pinned chat model route): one attempt with the exact body bytes, within `timeout` seconds.
public protocol NutrientEstimateSuggesting: Sendable {
    func attempt(_ body: Data, timeout: TimeInterval) async -> ConfirmEnrichmentAttemptResult
}

/// One validated answer kept on the device (CE1.2): exactly the response bytes, their hash, model,
/// provider, cost and the time received. Never the request body, key, amount or any other date.
public struct ConfirmEnrichmentCachedAnswer: Equatable, Sendable {
    public let subjectSHA256: String
    public let part: ConfirmEnrichmentPart
    public let response: Data
    public let responseSHA256: String
    public let model: String
    public let provider: String
    public let costMicroUSD: Int?
    /// Whole milliseconds.
    public let receivedAt: Date

    public init(subjectSHA256: String, part: ConfirmEnrichmentPart, response: Data, responseSHA256: String, model: String,
                provider: String, costMicroUSD: Int?, receivedAt: Date) {
        self.subjectSHA256 = subjectSHA256; self.part = part; self.response = response; self.responseSHA256 = responseSHA256
        self.model = model; self.provider = provider; self.costMicroUSD = costMicroUSD; self.receivedAt = receivedAt
    }
}

/// The per-subject cache. Every implementation applies `ConfirmEnrichmentCachePolicy`; a read failure
/// is a miss, never a reason to send twice.
public protocol ConfirmEnrichmentCaching: Sendable {
    func answer(subject: String, part: ConfirmEnrichmentPart, now: Date) -> ConfirmEnrichmentCachedAnswer?
    func store(_ answer: ConfirmEnrichmentCachedAnswer, now: Date)
    func remove(subject: String, part: ConfirmEnrichmentPart)
    func clear()
}

/// The day record port (gate section 2.6): reads a stored state and applies one atomic update. A
/// transform that throws stores nothing.
public protocol ConfirmEnrichmentSpendLedger: Sendable {
    func read() -> ConfirmEnrichmentSpendPolicy.Stored
    @discardableResult
    func update(_ transform: (ConfirmEnrichmentSpendPolicy.Stored) throws -> ConfirmEnrichmentSpendPolicy.Day) throws
        -> ConfirmEnrichmentSpendPolicy.Day
}

/// The Your food database fields CE1 section 7 sends that a candidate does not carry, read locally from
/// the active release by the candidate's record ID. No egress.
public struct PersonalFoodDescriptionFields: Equatable, Sendable {
    public let category: String
    public let productType: String
    /// Nil when the entry's state is unknown.
    public let state: String?
    /// CE-D5: the entry has reviewed `identity_facts`, so A is skipped for it.
    public let hasCatalogueFacts: Bool

    public init(category: String, productType: String, state: String?, hasCatalogueFacts: Bool) {
        self.category = category; self.productType = productType; self.state = state; self.hasCatalogueFacts = hasCatalogueFacts
    }
}

public protocol PersonalFoodDatabaseEntryReading: Sendable {
    func descriptionFields(recordID: ExternalIdentifier) -> PersonalFoodDescriptionFields?
}

/// Cancellable waits, for the 1.5 s debounce and the backoff.
public protocol ConfirmEnrichmentDelaying: Sendable {
    func wait(seconds: TimeInterval) async throws
}

/// Monotonic elapsed time, for the 60 s whole-call and 30 s attempt deadlines.
public protocol ConfirmEnrichmentElapsedTiming: Sendable {
    func now() -> Duration
}

/// A fraction from 0 to 1, for backoff jitter.
public protocol ConfirmEnrichmentJittering: Sendable {
    func fraction() -> Double
}

/// Whether each part may run in this build (gate section 6). The live root sets it from
/// `OpenRouterUse.isInForce`, so a part whose uses are not in force never starts; only the Debug
/// scripted branch sets it with literals.
public struct ConfirmEnrichmentAvailability: Equatable, Sendable {
    public let details: Bool
    public let nutrients: Bool

    public init(details: Bool, nutrients: Bool) {
        self.details = details; self.nutrients = nutrients
    }

    /// The live value: a part is available only when both of its uses are in force.
    public static var inForce: ConfirmEnrichmentAvailability {
        let details = ConfirmEnrichmentPart.details.use.isInForce && ConfirmEnrichmentPart.details.catalogueUse.isInForce
        let nutrients = ConfirmEnrichmentPart.nutrients.use.isInForce && ConfirmEnrichmentPart.nutrients.catalogueUse.isInForce
        // One line: the boundary check refuses an initialiser split across lines (gate section 6).
        return ConfirmEnrichmentAvailability(details: details, nutrients: nutrients)
    }

    public func isAvailable(_ part: ConfirmEnrichmentPart) -> Bool {
        switch part {
        case .details: details
        case .nutrients: nutrients
        }
    }
}
