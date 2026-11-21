import FoodLedgerApplication
import FoodLedgerDomain
import Foundation

// The two Confirm enrichment adapters (docs/confirm-enrichment-openrouter-v1-phase.md sections 3.1, 3.2
// and 4; contract tests G5 and G6). Each makes one HTTP attempt per call: it reads the key on every
// attempt, asks the O1 gate on every attempt with its own use, sends the body bytes exactly as given
// with the key only in the Authorization header, and reports the status, body and `Retry-After`. The
// response checks are application code (section 3.2); the adapter checks only the status, the byte
// limit and the transport failure class. It holds no content rule.

enum OpenRouterConfirmEnrichmentAttempt {
    static func attempt(_ body: Data, timeout: TimeInterval, route: ConfirmEnrichmentRoute, use: OpenRouterUse, maximumBytes: Int,
                        keys: any FoodWebKeyStoring, egress: any OpenRouterEgressPermitting,
                        transport: any ConfirmEnrichmentHTTPTransporting) async -> ConfirmEnrichmentAttemptResult {
        if Task.isCancelled { return .notSent(.cancelled) }
        // CE-T1: each adapter sends only to its own route-version address, whatever route it is given.
        let allowed = use == .confirmEnrichmentDetails ? ConfirmEnrichmentRoutes.detailsURL : ConfirmEnrichmentRoutes.nutrientURL
        guard route.endpoint == allowed else { return .notSent(.notPermitted) }
        guard egress.permits(use) else { return .notSent(.notPermitted) }
        guard let key = try? keys.load(), FoodWebKeySyntax.isValid(key), let url = URL(string: route.endpoint) else {
            return .notSent(.noKey)
        }
        // CE1 section 7: a request holding the key anywhere but the Authorization header is refused
        // and sends nothing.
        guard body.range(of: Data(key.utf8)) == nil else { return .notSent(.noKey) }
        let request = ConfirmEnrichmentHTTPRequest(
            method: "POST", url: url,
            headers: ["Authorization": "Bearer " + key, "Content-Type": "application/json", "Accept": "application/json"], body: body)
        do {
            let response = try await transport.send(request, timeout: timeout, maximumBodyBytes: maximumBytes)
            guard !response.exceededLimit, response.body.count <= maximumBytes else { return .transportFailed(.tooLarge) }
            return .sent(status: response.status, body: response.body, retryAfter: response.header("Retry-After"))
        } catch let error as ConfirmEnrichmentTransportError {
            switch error {
            case .offline: return .transportFailed(.offline)
            case .timedOut: return .transportFailed(.timedOut)
            case .cancelled: return .transportFailed(.cancelled)
            case .failed: return .transportFailed(.connectionFailed)
            }
        } catch {
            return .transportFailed(Task.isCancelled ? .cancelled : .connectionFailed)
        }
    }
}
