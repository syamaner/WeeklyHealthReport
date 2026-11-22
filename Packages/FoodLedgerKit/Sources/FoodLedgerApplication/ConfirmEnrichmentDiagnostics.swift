import Foundation
import FoodLedgerDomain

/// One Confirm enrichment request as Developer tools shows it, in memory for the app session only
/// (docs/confirm-enrichment-openrouter-v1.md CE1.7, Developer tools): the use, route, model, provider,
/// the request field names sent, the request and response hashes, latency, attempts, reported cost,
/// the threshold and the outcome. It never holds the key, a request or response body, or a value.
public struct ConfirmEnrichmentDiagnostics: Equatable, Sendable {
    public let use: OpenRouterUse
    public let routeVersion: String
    public let endpoint: String
    /// The model the answer named, or the route's request model when nothing answered.
    public let model: String
    public let provider: String
    /// Sorted names of the fields the request carries (description fields only where they hold a value).
    public let requestFields: [String]
    public let requestSHA256: String
    /// The hash of the last response read, from the cache or the wire; nil when none was read.
    public let responseSHA256: String?
    /// From the first attempt to the last reply, through the injected elapsed timing; nil when nothing was sent.
    public let latencyMilliseconds: Int?
    public let attempts: Int
    /// The sum of the costs the responses reported, in micro-dollars; nil when none was reported.
    public let reportedCostMicroUSD: Int?
    /// A's confidence threshold (CE-D3); nil for B.
    public let threshold: String?
    public let fromCache: Bool
    /// A fixed code: `answered`, `answered_from_cache`, or the failure's name.
    public let outcome: String

    public init(use: OpenRouterUse, routeVersion: String, endpoint: String, model: String, provider: String, requestFields: [String],
                requestSHA256: String, responseSHA256: String?, latencyMilliseconds: Int?, attempts: Int, reportedCostMicroUSD: Int?,
                threshold: String?, fromCache: Bool, outcome: String) {
        self.use = use; self.routeVersion = routeVersion; self.endpoint = endpoint; self.model = model; self.provider = provider
        self.requestFields = requestFields; self.requestSHA256 = requestSHA256; self.responseSHA256 = responseSHA256
        self.latencyMilliseconds = latencyMilliseconds; self.attempts = attempts; self.reportedCostMicroUSD = reportedCostMicroUSD
        self.threshold = threshold; self.fromCache = fromCache; self.outcome = outcome
    }

    /// A's field names: the description fields that hold a value, the details known when any, and the facts asked.
    public static func fieldNames(_ inputs: ConfirmDetailsRequestInputs) -> [String] {
        (descriptionFields(inputs.description) + (inputs.knownDetails.isEmpty ? [] : ["known_details"]) + ["asked"]).sorted()
    }

    /// B's field names: the description fields that hold a value, the details when any, the basis, the
    /// known values when any, and the nutrients asked.
    public static func fieldNames(_ inputs: ConfirmNutrientRequestInputs) -> [String] {
        (descriptionFields(inputs.description) + (inputs.identity.isEmpty ? [] : ["identity"]) + ["basis"]
            + (inputs.known.isEmpty ? [] : ["known"]) + ["eligible"]).sorted()
    }

    static func descriptionFields(_ description: ConfirmEnrichmentDescription) -> [String] {
        let fields: [(String, String?)] = [
            ("name", description.name), ("brand", description.brand), ("variant", description.variant),
            ("category", description.category), ("product_type", description.productType), ("state", description.state),
            ("source", description.source.rawValue)
        ]
        return fields.compactMap { name, value in value == nil ? nil : "description." + name }
    }

    /// The outcome code of a failure.
    public static func outcome(_ failure: ConfirmEnrichmentSession.Failure) -> String {
        switch failure {
        case .silent: "silent"
        case .notAvailable: "not_available"
        case .limitReached: "limit_reached"
        case .notPermitted: "not_permitted"
        case .notPermittedAfterSending: "not_permitted_after_sending"
        case .cancelled: "cancelled"
        }
    }
}

/// Where the session reports each request's diagnostics. The app forwards them to Developer tools.
public protocol ConfirmEnrichmentDiagnosticsRecording: Sendable {
    func record(_ diagnostics: ConfirmEnrichmentDiagnostics)
}
