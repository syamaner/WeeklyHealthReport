import FoodLedgerApplication
import FoodLedgerDomain
import Foundation

// One A attempt (docs/confirm-enrichment-openrouter-v1-phase.md sections 3.1 and 4): asks OpenRouterEgressPermitting
// for `confirmEnrichmentDetails` on every attempt, through OpenRouterConfirmEnrichmentAttempt.

/// A: Jev through OpenRouter's System One endpoint (CE1.4), use `confirmEnrichmentDetails`.
public struct OpenRouterJevFoodDetailsAdapter: FoodDetailsSuggesting {
    let egress: any OpenRouterEgressPermitting
    let transport: any ConfirmEnrichmentHTTPTransporting
    let keys: any FoodWebKeyStoring
    let route: ConfirmEnrichmentRoute

    public init(egress: any OpenRouterEgressPermitting, transport: any ConfirmEnrichmentHTTPTransporting, keys: any FoodWebKeyStoring,
                route: ConfirmEnrichmentRoute = ConfirmEnrichmentRoutes.details) {
        self.egress = egress; self.transport = transport; self.keys = keys; self.route = route
    }

    public func attempt(_ body: Data, timeout: TimeInterval) async -> ConfirmEnrichmentAttemptResult {
        await OpenRouterConfirmEnrichmentAttempt.attempt(
            body, timeout: timeout, route: route, use: .confirmEnrichmentDetails,
            maximumBytes: ConfirmEnrichmentVersions.detailsResponseByteLimit, keys: keys, egress: egress, transport: transport)
    }
}
