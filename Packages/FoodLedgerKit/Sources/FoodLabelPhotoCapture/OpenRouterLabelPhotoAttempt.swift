import FoodLabelPhotoReading
import FoodLedgerApplication
import Foundation

/// One attempt of the label photo read over an injected transport (docs/label-photo-ai-prefill-v1.md
/// E5, E8, E11, E12, 17.5; contract tests 8 and 21). It sends the prepared bytes once and checks
/// the reply; the read session decides on retries, spend and Cancel.
///
/// A reply is an answer only when it is at most 200,000 bytes, HTTP 200, holds exactly one choice
/// whose `finish_reason` is `stop`, carries no tool call or refusal, names the requested model
/// (exactly, or its dated snapshot) and the pinned endpoint's provider, has a generation ID, and
/// its message content decodes under the strict wire schema. Anything else is a failed read with
/// nothing shown.
public struct OpenRouterLabelPhotoAttempt: LabelPhotoAttempting {
    public static let maximumResponseBytes = 200_000

    let transport: any LabelPhotoHTTPTransporting
    let keys: any FoodWebKeyStoring
    let request: OpenRouterLabelPhotoRequest

    public init(transport: any LabelPhotoHTTPTransporting, keys: any FoodWebKeyStoring, request: OpenRouterLabelPhotoRequest) {
        self.transport = transport; self.keys = keys; self.request = request
    }

    public func attempt(_ image: PreparedLabelImage, timeout: TimeInterval) async -> LabelPhotoAttemptResult {
        if Task.isCancelled { return .notSent(.cancelled) }
        guard let key = try? keys.load(), FoodWebKeySyntax.isValid(key) else { return .notSent(.keyMissing) }
        guard let http = try? request.httpRequest(image, key: key) else { return .notSent(.failed) }
        let response: LabelPhotoHTTPResponse
        do {
            response = try await transport.send(http, timeout: timeout, maximumBodyBytes: Self.maximumResponseBytes)
        } catch let error as LabelPhotoTransportError {
            switch error {
            case .timedOut: return .failed(.timedOut, failure: .timedOut, reportedCost: nil, promptTokens: nil)
            case .cancelled: return .failed(.transportError, failure: .cancelled, reportedCost: nil, promptTokens: nil)
            case .offline: return .failed(.transportError, failure: .offline, reportedCost: nil, promptTokens: nil)
            case .failed: return .failed(.transportError, failure: .providerUnavailable, reportedCost: nil, promptTokens: nil)
            }
        } catch {
            let failure: LabelImageReadingFailure = Task.isCancelled ? .cancelled : .providerUnavailable
            return .failed(.transportError, failure: failure, reportedCost: nil, promptTokens: nil)
        }
        return Self.classify(response, route: request.route)
    }

    public func manifestRequest(catalogue: LabelPhotoManifest.CatalogueCheck) -> LabelPhotoManifest.Request {
        request.manifestRequest(catalogue: catalogue)
    }

    // MARK: Response checks (pure)

    public static func classify(_ response: LabelPhotoHTTPResponse, route: LabelPhotoRoute.Route) -> LabelPhotoAttemptResult {
        let retryAfter = response.header("Retry-After")
        guard !response.exceededLimit, response.body.count <= maximumResponseBytes else {
            return .failed(.contentFailure, failure: .oversize, reportedCost: nil, promptTokens: nil)
        }
        let object = (try? JSONSerialization.jsonObject(with: response.body)) as? [String: Any]
        let usage = object.map(usage(in:))
        let cost = usage.flatMap { $0.costUSD == LabelPhotoManifest.Usage.unknownCost ? nil : Decimal(string: $0.costUSD) }
        let promptTokens = usage?.promptTokens
        func failed(_ outcome: LabelPhotoRetryPolicy.Outcome, _ failure: LabelImageReadingFailure) -> LabelPhotoAttemptResult {
            .failed(outcome, failure: failure, reportedCost: cost, promptTokens: promptTokens)
        }
        let choices = object?["choices"] as? [Any]
        let hasChoices = !(choices ?? []).isEmpty
        let errorCode = ((object?["error"] as? [String: Any])?["code"]).flatMap(integer)
        guard response.status == 200 else {
            if LabelPhotoRetryPolicy.isOverloaded(code: errorCode, hasChoices: hasChoices) {
                return failed(.providerError(code: errorCode, hasChoices: hasChoices, retryAfter: retryAfter), .providerUnavailable)
            }
            let outcome = LabelPhotoRetryPolicy.Outcome.httpStatus(response.status, retryAfter: retryAfter)
            let failure: LabelImageReadingFailure = switch response.status {
            case 401, 403: .keyRejected
            case 429: .quotaLimited
            case _ where LabelPhotoRetryPolicy.isRetryable(outcome): .providerUnavailable
            default: .failed
            }
            return failed(outcome, failure)
        }
        guard let object else { return failed(.contentFailure, .unreadableAnswer) }
        if object["error"] != nil {
            let outcome = LabelPhotoRetryPolicy.Outcome.providerError(code: errorCode, hasChoices: hasChoices, retryAfter: retryAfter)
            return failed(outcome, LabelPhotoRetryPolicy.isRetryable(outcome) ? .providerUnavailable : .failed)
        }
        guard let choices, choices.count == 1, let choice = choices[0] as? [String: Any],
              let message = choice["message"] as? [String: Any] else {
            return failed(.contentFailure, .unreadableAnswer)
        }
        guard modelMatches(requested: route.model, returned: object["model"]) else { return failed(.contentFailure, .wrongModel) }
        guard let returned = normalisedProvider(object["provider"]), returned == normalisedProvider(route.providerName) else { return failed(.contentFailure, .wrongProvider) }
        if let calls = message["tool_calls"], !(calls is NSNull), !((calls as? [Any])?.isEmpty ?? false) {
            return failed(.contentFailure, .failed)
        }
        if let refusal = message["refusal"], !(refusal is NSNull) { return failed(.contentFailure, .refused) }
        switch choice["finish_reason"] as? String {
        case "stop": break
        case "length": return failed(.contentFailure, .truncated)
        case "content_filter": return failed(.contentFailure, .refused)
        default: return failed(.contentFailure, .failed)
        }
        guard let content = message["content"] as? String, content.utf8.count <= LabelPhotoManifest.maximumWireBytes,
              LabelPhotoWire.decode(content) != nil,
              let generationID = object["id"] as? String, !generationID.isEmpty,
              let model = object["model"] as? String, let provider = object["provider"] as? String,
              let usage else {
            return failed(.contentFailure, .unreadableAnswer)
        }
        return .answered(wireText: content, model: model, provider: provider, generationID: generationID, finishReason: "stop",
                         usage: usage)
    }

    /// The reported usage; a missing, negative or non-numeric cost is unknown, never zero.
    static func usage(in object: [String: Any]) -> LabelPhotoManifest.Usage {
        let usage = object["usage"] as? [String: Any] ?? [:]
        let details = usage["completion_tokens_details"] as? [String: Any]
        let cost = usage["cost"].flatMap(decimal).flatMap { $0 >= 0 ? $0 : nil }
        return LabelPhotoManifest.Usage(promptTokens: usage["prompt_tokens"].flatMap(integer),
                                        completionTokens: usage["completion_tokens"].flatMap(integer),
                                        reasoningTokens: details?["reasoning_tokens"].flatMap(integer),
                                        costUSD: cost.map { "\($0)" } ?? LabelPhotoManifest.Usage.unknownCost)
    }

    static func integer(_ value: Any) -> Int? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        let double = number.doubleValue
        guard double.rounded() == double, abs(double) < 1e15 else { return nil }
        return Int(double)
    }

    static func decimal(_ value: Any) -> Decimal? {
        if let number = value as? NSNumber {
            guard CFGetTypeID(number) != CFBooleanGetTypeID(), number.doubleValue.isFinite else { return nil }
            return Decimal(string: number.stringValue, locale: Locale(identifier: "en_US_POSIX"))
        }
        if let text = value as? String { return Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")) }
        return nil
    }

    /// The dated slugs OpenRouter may return for each admitted model, pinned at E13 qualification
    /// (append-only; a change is reviewed like any route change). Empty until L5 records them.
    public static let pinnedSnapshots: [String: Set<String>] = [LabelPhotoRoute.v1.model: []]

    /// E5 (the #326 review, decision Q1): the response names the requested model exactly, or one of
    /// its pinned dated slugs. No pattern is matched, so no family member can pass for it.
    static func modelMatches(requested: String, returned: Any?) -> Bool {
        guard let returned = returned as? String, !requested.isEmpty else { return false }
        return returned == requested || pinnedSnapshots[requested]?.contains(returned) == true
    }

    /// OpenRouter returns the provider's display name; it must equal the route's provider name
    /// exactly once both are trimmed, lower-cased and spaced with hyphens (17.21). No prefix or
    /// family match: "Google AI Studio" is not "Google".
    static func normalisedProvider(_ value: Any?) -> String? {
        guard let name = value as? String else { return nil }
        return name.trimmingCharacters(in: .whitespaces).lowercased().replacingOccurrences(of: " ", with: "-")
    }
}
