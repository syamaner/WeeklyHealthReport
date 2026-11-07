import Foundation

// The pure envelope check of the pasted label AI text route (docs/pasted-label-ai-text-v1.md T3,
// 11.1; A2 gate finding 6): in the application layer, Foundation only, so the A5 orchestrator and
// the evaluation tool call one check. The infrastructure adapter returns raw bytes only. Its usage,
// number and provider readings equal the photo attempt's (`OpenRouterLabelPhotoAttempt`), which a
// parity test checks.

/// The pure envelope check of a raw text-route reply (E5, E12 as on the photo route; T3). The
/// attempt returns bytes only; the caller applies this check, and only an `answered` envelope's
/// content bytes go to `PastedLabelAITextReading`. A reply is an answer only when it is at most
/// 200,000 bytes, HTTP 200, holds exactly one choice whose `finish_reason` is `stop`, carries no
/// tool call or refusal, names the requested model exactly and the pinned endpoint's provider, has
/// a generation ID, and its message content is a string of at most 65,536 bytes. The content is
/// not decoded here. Anything else is a failed read with nothing shown.
public enum PastedLabelAITextEnvelope {
    /// The reply cap, as on the photo route (E12).
    public static let maximumResponseBytes = 200_000

    public enum Outcome: Equatable, Sendable {
        case answered(content: Data, model: String, provider: String, generationID: String, usage: LabelPhotoManifest.Usage)
        case failed(LabelPhotoRetryPolicy.Outcome, failure: LabelImageReadingFailure, usage: LabelPhotoManifest.Usage?)

        /// The reported cost, nil when unknown (never zero for an unreported cost).
        public var reportedCost: Decimal? {
            let usage: LabelPhotoManifest.Usage? = switch self {
            case let .answered(_, _, _, _, usage): usage
            case let .failed(_, _, usage): usage
            }
            guard let cost = usage?.costUSD, cost != LabelPhotoManifest.Usage.unknownCost else { return nil }
            return Decimal(string: cost, locale: Locale(identifier: "en_US_POSIX"))
        }
    }

    /// The usage a raw reply reports, whatever else it holds; a missing cost is unknown, never zero.
    public static func usage(_ body: Data) -> LabelPhotoManifest.Usage? {
        ((try? JSONSerialization.jsonObject(with: body)) as? [String: Any]).map(usage(in:))
    }

    public static func check(_ response: PastedLabelAITextRawResponse, route: PastedLabelAITextRoute.Route) -> Outcome {
        let retryAfter = response.headers.first { $0.key.caseInsensitiveCompare("Retry-After") == .orderedSame }?.value
        guard !response.exceededLimit, response.body.count <= maximumResponseBytes else {
            return .failed(.contentFailure, failure: .oversize, usage: nil)
        }
        let object = (try? JSONSerialization.jsonObject(with: response.body)) as? [String: Any]
        let usage = object.map(usage(in:))
        func failed(_ outcome: LabelPhotoRetryPolicy.Outcome, _ failure: LabelImageReadingFailure) -> Outcome {
            .failed(outcome, failure: failure, usage: usage)
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
        // T3: the response's model and provider must match the request; no snapshot is pinned yet.
        guard let model = object["model"] as? String, model == route.model else { return failed(.contentFailure, .wrongModel) }
        guard let provider = object["provider"] as? String,
              normalisedProvider(provider) == normalisedProvider(route.providerName) else {
            return failed(.contentFailure, .wrongProvider)
        }
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
              let generationID = object["id"] as? String, !generationID.isEmpty, let usage else {
            return failed(.contentFailure, .unreadableAnswer)
        }
        return .answered(content: Data(content.utf8), model: model, provider: provider, generationID: generationID, usage: usage)
    }

    // MARK: Usage and identity (as the photo route reads them)

    /// The reported usage; a missing, negative or non-numeric cost is unknown, never zero.
    public static func usage(in object: [String: Any]) -> LabelPhotoManifest.Usage {
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

    /// The provider name trimmed, lower-cased and spaced with hyphens (photo spec 17.21): no
    /// prefix or family match.
    public static func normalisedProvider(_ value: Any?) -> String? {
        guard let name = value as? String else { return nil }
        return name.trimmingCharacters(in: .whitespaces).lowercased().replacingOccurrences(of: " ", with: "-")
    }
}
