import FoodLedgerApplication
import Foundation

/// The on-the-day catalogue check (docs/label-photo-ai-prefill-v1.md E7, 17.5 M3; contract test
/// 22): two free GETs of OpenRouter's public catalogue, with no Authorization header, no body and
/// no user data. The model's endpoint listing gives the slug, image input, the endpoint and its
/// prices; the zero-data-retention listing must hold the same model on the same endpoint. Any
/// failure throws, and the read session then sends nothing.
public struct OpenRouterLabelRouteChecker: LabelPhotoRouteChecking {
    public static let zeroDataRetentionURL = URL(string: "https://openrouter.ai/api/v1/endpoints/zdr")!
    /// The live ZDR listing was 1,098,446 bytes on 26 October 2026 and grows with the catalogue, so
    /// the cap leaves room (17.21); a larger reply still fails closed.
    public static let maximumResponseBytes = 8_000_000
    public static let timeout: TimeInterval = 15

    public enum CheckError: Error, Equatable, Sendable {
        case unavailable, malformed
    }

    let transport: any LabelPhotoHTTPTransporting
    let clock: any LedgerClock
    /// Whether the session's W includes the reasoning limit (17.21): a non-zero reasoning price is
    /// admitted only then.
    let reasoningBilledSeparately: Bool

    public init(transport: any LabelPhotoHTTPTransporting, clock: any LedgerClock, reasoningBilledSeparately: Bool = false) {
        self.transport = transport; self.clock = clock; self.reasoningBilledSeparately = reasoningBilledSeparately
    }

    public static func endpointsURL(_ route: LabelPhotoRoute.Route) -> URL? {
        let parts = route.model.split(separator: "/", omittingEmptySubsequences: false)
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789-._")
        guard parts.count == 2, parts.allSatisfy({ !$0.isEmpty && $0.unicodeScalars.allSatisfy(allowed.contains) }) else { return nil }
        return URL(string: "https://openrouter.ai/api/v1/models/\(parts[0])/\(parts[1])/endpoints")
    }

    static func get(_ url: URL) -> LabelPhotoHTTPRequest {
        LabelPhotoHTTPRequest(method: "GET", url: url, headers: ["Accept": "application/json"], body: nil)
    }

    public func check(_ route: LabelPhotoRoute.Route) async throws -> LabelPhotoManifest.CatalogueCheck {
        guard let url = Self.endpointsURL(route) else { throw CheckError.malformed }
        let listing = try await fetch(url)
        let zeroDataRetention = try await fetch(Self.zeroDataRetentionURL)
        return try Self.parse(listing: listing, zeroDataRetention: zeroDataRetention, route: route,
                              at: PastedLabelBasisChoice.milliseconds(clock.now()), reasoningBilledSeparately: reasoningBilledSeparately)
    }

    func fetch(_ url: URL) async throws -> Data {
        let response: LabelPhotoHTTPResponse
        do {
            response = try await transport.send(Self.get(url), timeout: Self.timeout, maximumBodyBytes: Self.maximumResponseBytes)
        } catch let error as LabelPhotoTransportError {
            // A transport failure is reported as such, never as the route being unavailable.
            switch error {
            case .offline: throw LabelPhotoRouteCheckFailure.transport(.offline)
            case .timedOut: throw LabelPhotoRouteCheckFailure.transport(.timedOut)
            case .cancelled: throw LabelPhotoRouteCheckFailure.transport(.cancelled)
            case .failed: throw LabelPhotoRouteCheckFailure.transport(.connectionFailed)
            }
        }
        guard response.status == 200, !response.exceededLimit else { throw CheckError.unavailable }
        return response.body
    }

    /// Pure: the catalogue check the two listings describe for the route. The read session then
    /// compares it with the route and the spend bound (`LabelPhotoReadSession.prices`).
    public static func parse(listing: Data, zeroDataRetention: Data, route: LabelPhotoRoute.Route, at: Int64,
                             reasoningBilledSeparately: Bool = false) throws
        -> LabelPhotoManifest.CatalogueCheck {
        guard let root = (try? JSONSerialization.jsonObject(with: listing)) as? [String: Any],
              let model = root["data"] as? [String: Any], let slug = model["id"] as? String,
              let endpoints = model["endpoints"] as? [[String: Any]] else { throw CheckError.malformed }
        let modalities = ((model["architecture"] as? [String: Any])?["input_modalities"] as? [String]) ?? []
        let matches = endpoints.filter { $0["tag"] as? String == route.endpoint }
        guard matches.count == 1, let pricing = matches[0]["pricing"] as? [String: Any],
              let prompt = (pricing["prompt"] as? String).flatMap(decimalText),
              let completion = (pricing["completion"] as? String).flatMap(decimalText) else { throw CheckError.malformed }
        guard pricesAreModelled(pricing, completion: completion, reasoningBilledSeparately: reasoningBilledSeparately) else {
            throw CheckError.unavailable
        }
        guard let zdrRoot = (try? JSONSerialization.jsonObject(with: zeroDataRetention)) as? [String: Any],
              let zdrEntries = zdrRoot["data"] as? [[String: Any]] else { throw CheckError.malformed }
        let listed = zdrEntries.contains { entry in
            entry["model_id"] as? String == route.model && entry["tag"] as? String == route.endpoint
        }
        return LabelPhotoManifest.CatalogueCheck(at: at, slug: slug, endpoint: route.endpoint, inputModalities: modalities,
                                                 zeroDataRetention: listed, promptPrice: prompt, completionPrice: completion)
    }

    /// The live pricing object's fields, as listed on 26 October 2026 (17.21), and how each one
    /// stands against W, which prices 6,000 prompt tokens and the completion (plus reasoning when
    /// it is billed separately). Any field not named here fails the route closed.
    ///
    /// - `image`, `input_cache_read`, `input_cache_write`: input priced at or below the prompt
    ///   rate. Image tokens are counted in the prompt tokens, and a cached input can only cost
    ///   less, so W already covers them. A rate above the prompt rate fails closed.
    /// - `audio`, `input_audio_cache`, `web_search`: modalities and tools the request never sends
    ///   (no audio, no plugins or tools), so they cannot be charged. Any well-formed price passes.
    /// - `internal_reasoning`: at or below the completion rate, and non-zero only when the session
    ///   bills reasoning separately.
    /// - `discount`: a number from 0 up to, but not including, 1. W ignores it, so W stays the
    ///   undiscounted, larger bound.
    static let inputAtMostPrompt: Set<String> = ["image", "input_cache_read", "input_cache_write"]
    static let neverSent: Set<String> = ["audio", "input_audio_cache", "web_search"]

    static func pricesAreModelled(_ pricing: [String: Any], completion: String, reasoningBilledSeparately: Bool) -> Bool {
        guard let completion = Decimal(string: completion),
              let promptText = pricing["prompt"] as? String, let prompt = decimalText(promptText).flatMap({ Decimal(string: $0) }) else {
            return false
        }
        for (name, value) in pricing where name != "prompt" && name != "completion" {
            if name == "discount" {
                guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
                      number.doubleValue.isFinite, number.doubleValue >= 0, number.doubleValue < 1 else { return false }
                continue
            }
            guard let text = value as? String, let price = decimalText(text).flatMap({ Decimal(string: $0) }) else { return false }
            if name == "internal_reasoning" {
                if price > completion || (price > 0 && !reasoningBilledSeparately) { return false }
            } else if inputAtMostPrompt.contains(name) {
                if price > prompt { return false }
            } else if !neverSent.contains(name), price != 0 {
                return false
            }
        }
        return true
    }

    /// A price as plain decimal text, or nil when it is not a non-negative number.
    static func decimalText(_ text: String) -> String? {
        guard let value = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")), value >= 0, "\(value)" != "NaN" else { return nil }
        return "\(value)"
    }
}
