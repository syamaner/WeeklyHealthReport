import FoodLedgerApplication
import FoodLedgerDomain
import Foundation

// One B attempt (docs/confirm-enrichment-openrouter-v1-phase.md sections 3.1 and 4): asks OpenRouterEgressPermitting
// for `confirmEnrichmentNutrients` on every attempt, through OpenRouterConfirmEnrichmentAttempt.

/// B: the pinned chat model route (CE1.5, CE-D2), use `confirmEnrichmentNutrients`.
public struct OpenRouterNutrientEstimateAdapter: NutrientEstimateSuggesting {
    let egress: any OpenRouterEgressPermitting
    let transport: any ConfirmEnrichmentHTTPTransporting
    let keys: any FoodWebKeyStoring
    let route: ConfirmEnrichmentRoute

    public init(egress: any OpenRouterEgressPermitting, transport: any ConfirmEnrichmentHTTPTransporting, keys: any FoodWebKeyStoring,
                route: ConfirmEnrichmentRoute = ConfirmEnrichmentRoutes.nutrients) {
        self.egress = egress; self.transport = transport; self.keys = keys; self.route = route
    }

    public func attempt(_ body: Data, timeout: TimeInterval) async -> ConfirmEnrichmentAttemptResult {
        await OpenRouterConfirmEnrichmentAttempt.attempt(
            body, timeout: timeout, route: route, use: .confirmEnrichmentNutrients,
            maximumBytes: ConfirmEnrichmentVersions.nutrientResponseByteLimit, keys: keys, egress: egress, transport: transport)
    }
}
