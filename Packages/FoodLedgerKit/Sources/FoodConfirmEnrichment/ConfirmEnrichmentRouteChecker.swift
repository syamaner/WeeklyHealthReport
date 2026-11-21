import FoodLedgerApplication
import FoodLedgerDomain
import Foundation

/// The on-the-day catalogue check of Confirm enrichment (docs/confirm-enrichment-openrouter-v1.md CE1.4,
/// CE1.5 and CE-T6; phase gate sections 2.6, 6 and test G14): two keyless GETs of OpenRouter's public
/// catalogue, the model's endpoint listing and the zero-data-retention listing, with no Authorization
/// header, no body and no user data. It asks the O1 gate before each fetch with the catalogue use its
/// caller passes, and a refusal sends nothing more. The listing must name the route's model with
/// exactly one endpoint of the pinned tag and prices the spend policy can bound, and the ZDR listing
/// must hold the same model on the same endpoint.
public struct ConfirmEnrichmentRouteChecker: ConfirmEnrichmentRouteChecking {
    public static let maximumResponseBytes = 8_000_000
    public static let timeout: TimeInterval = 15

    let egress: any OpenRouterEgressPermitting
    let transport: any ConfirmEnrichmentHTTPTransporting
    let routes: ConfirmEnrichmentSession.Routes

    public init(egress: any OpenRouterEgressPermitting, transport: any ConfirmEnrichmentHTTPTransporting,
                routes: ConfirmEnrichmentSession.Routes = ConfirmEnrichmentRoutes.all) {
        self.egress = egress; self.transport = transport; self.routes = routes
    }

    /// The model's endpoint listing address, from the route's own slug.
    public static func endpointsURL(_ route: ConfirmEnrichmentRoute) -> URL? {
        let parts = route.model.split(separator: "/", omittingEmptySubsequences: false)
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789-._")
        guard parts.count == 2, parts.allSatisfy({ !$0.isEmpty && $0.unicodeScalars.allSatisfy(allowed.contains) }) else { return nil }
        return URL(string: "https://openrouter.ai/api/v1/models/\(parts[0])/\(parts[1])/endpoints")
    }

    enum Fetch { case body(Data), connectionFailed, notPermitted, unavailable }

    func fetch(_ url: URL, use: OpenRouterUse) async -> Fetch {
        guard egress.permits(use) else { return .notPermitted }
        let request = ConfirmEnrichmentHTTPRequest(method: "GET", url: url, headers: ["Accept": "application/json"], body: nil)
        do {
            let response = try await transport.send(request, timeout: Self.timeout, maximumBodyBytes: Self.maximumResponseBytes)
            guard response.status == 200, !response.exceededLimit else { return .unavailable }
            return .body(response.body)
        } catch {
            // A transport failure is not the route's fault: the next request checks again.
            return .connectionFailed
        }
    }

    public func check(_ part: ConfirmEnrichmentPart, catalogueUse: OpenRouterUse) async -> ConfirmEnrichmentRouteCheckResult {
        let route = routes.route(part)
        guard catalogueUse == part.catalogueUse, let endpoints = Self.endpointsURL(route),
              let zdr = URL(string: ConfirmEnrichmentRoutes.zeroDataRetentionURL) else { return .unavailable }
        let listing: Data
        switch await fetch(endpoints, use: catalogueUse) {
        case let .body(data): listing = data
        case .connectionFailed: return .connectionFailed
        case .notPermitted: return .notPermitted
        case .unavailable: return .unavailable
        }
        let retention: Data
        switch await fetch(zdr, use: catalogueUse) {
        case let .body(data): retention = data
        case .connectionFailed: return .connectionFailed
        case .notPermitted: return .notPermitted
        case .unavailable: return .unavailable
        }
        guard let prices = Self.parse(listing: listing, zeroDataRetention: retention, route: route) else { return .unavailable }
        return .passed(prices)
    }

    /// Pure: the day's prices the two listings give the route, or nil when the route must not run.
    public static func parse(listing: Data, zeroDataRetention: Data, route: ConfirmEnrichmentRoute) -> ConfirmEnrichmentPrices? {
        guard let root = (try? JSONSerialization.jsonObject(with: listing)) as? [String: Any],
              let model = root["data"] as? [String: Any], let slug = model["id"] as? String,
              route.acceptedModels.contains(slug) || slug == route.model,
              let endpoints = model["endpoints"] as? [[String: Any]] else { return nil }
        let matches = endpoints.filter { $0["tag"] as? String == route.providerEndpoint }
        guard matches.count == 1, let pricing = matches[0]["pricing"] as? [String: Any],
              let prompt = (pricing["prompt"] as? String).flatMap(price),
              let completion = (pricing["completion"] as? String).flatMap(price),
              pricesAreModelled(pricing, prompt: prompt, completion: completion,
                                reasoningBilledSeparately: route.reasoningBilledSeparately) else { return nil }
        guard let zdrRoot = (try? JSONSerialization.jsonObject(with: zeroDataRetention)) as? [String: Any],
              let entries = zdrRoot["data"] as? [[String: Any]],
              entries.contains(where: { $0["model_id"] as? String == route.model && $0["tag"] as? String == route.providerEndpoint })
        else { return nil }
        return ConfirmEnrichmentPrices(promptPerTokenUSD: prompt, completionPerTokenUSD: completion)
    }

    /// Pricing fields beside prompt and completion, as label photo bounds them (E7, 17.21): cached input
    /// at or below the prompt rate; modalities and tools the request never sends at any price; internal
    /// reasoning at or below the completion rate, and non-zero only when W includes the reasoning limit;
    /// a discount from 0 up to 1 (W ignores it, so W stays the larger bound). Any other field fails closed
    /// unless it is zero.
    static let inputAtMostPrompt: Set<String> = ["input_cache_read", "input_cache_write", "input_cache_write_1h"]
    static let neverSent: Set<String> = ["image", "audio", "input_audio_cache", "web_search"]

    static func pricesAreModelled(_ pricing: [String: Any], prompt: Decimal, completion: Decimal, reasoningBilledSeparately: Bool) -> Bool {
        for (name, value) in pricing where name != "prompt" && name != "completion" {
            if name == "discount" {
                guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
                      number.doubleValue.isFinite, number.doubleValue >= 0, number.doubleValue < 1 else { return false }
                continue
            }
            guard let text = value as? String, let amount = price(text) else { return false }
            if name == "internal_reasoning" {
                if amount > completion || (amount > 0 && !reasoningBilledSeparately) { return false }
            } else if inputAtMostPrompt.contains(name) {
                if amount > prompt { return false }
            } else if !neverSent.contains(name), amount != 0 {
                return false
            }
        }
        return true
    }

    /// The largest per-token price admitted: USD 0.001 (1,000 per million tokens), far above any listed
    /// model, so a larger price is malformed and fails the route closed before W is worked out.
    static let maximumPricePerToken = Decimal(string: "0.001")!

    /// A price as a non-negative decimal written as plain decimal text, at most the ceiling; nil for
    /// anything else (a comma, trailing text, spaces, a sign or an exponent fails closed).
    static func price(_ text: String) -> Decimal? {
        guard text.range(of: #"^[0-9]+(\.[0-9]+)?$"#, options: .regularExpression) != nil,
              let value = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")), !value.isNaN,
              value >= 0, value <= maximumPricePerToken else { return nil }
        return value
    }
}
