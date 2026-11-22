import FoodLedgerApplication
import Foundation

/// The route versions of Confirm enrichment v1 (docs/confirm-enrichment-openrouter-v1.md CE1.4 and CE1.5;
/// phase gate sections 1, 2.6 and 3.3 item 3). The only file in the package that holds the OpenRouter
/// addresses, as constants used by gated request sites (a reviewed exemption in check-boundaries.sh).
/// A route changes only by a route version bump; `confirm-details-route-v1` is frozen only after the
/// evaluation's first request shows whether System One accepts `max_tokens` (section 9).
public enum ConfirmEnrichmentRoutes {
    public static let detailsURL = "https://openrouter.ai/api/v1/systemone"
    public static let nutrientURL = "https://openrouter.ai/api/v1/chat/completions"
    /// The keyless catalogue listings of E7, read by the route checker (PR 3).
    public static let detailsEndpointsURL = "https://openrouter.ai/api/v1/models/typesafe/jev-1.13/endpoints"
    public static let nutrientEndpointsURL = "https://openrouter.ai/api/v1/models/openai/gpt-6.1-sol/endpoints"
    public static let zeroDataRetentionURL = "https://openrouter.ai/api/v1/endpoints/zdr"

    /// `confirm-details-route-v1`: Jev through System One.
    public static let details = ConfirmEnrichmentRoute(
        part: .details, version: "confirm-details-route-v1", model: "typesafe/jev-1.13",
        acceptedModels: ["typesafe/jev-1.13", "typesafe/jev-1.13-20260917"], provider: "TypeSafe", providerEndpoint: "typesafe",
        endpoint: detailsURL, promptCeilingTokens: 8_000, completionCeilingTokens: 400, reasoningLimitTokens: 0,
        reasoningBilledSeparately: false, sendsMaxTokens: true)

    /// `confirm-nutrient-route-v1`: GPT-6.1 Sol on Azure (CE-D2).
    public static let nutrients = ConfirmEnrichmentRoute(
        part: .nutrients, version: "confirm-nutrient-route-v1", model: "openai/gpt-6.1-sol",
        acceptedModels: ["openai/gpt-6.1-sol"], provider: "Azure", providerEndpoint: "azure",
        endpoint: nutrientURL, promptCeilingTokens: 6_000, completionCeilingTokens: 1_200, reasoningLimitTokens: 500,
        reasoningBilledSeparately: true, sendsMaxTokens: true)

    public static let all = ConfirmEnrichmentSession.Routes(details: details, nutrients: nutrients)
}
