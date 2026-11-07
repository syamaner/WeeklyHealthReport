import FoodLedgerApplication
import Foundation

/// The `PastedLabelAITextAttempting` adapter (docs/pasted-label-ai-text-v1.md 11.1, T1 to T4): one
/// attempt over an injected transport, returning the raw reply bytes only. It never decodes the
/// text wire. It refuses, before sending anything, a cancelled task, an empty text, a text over
/// 8,000 scalars and a missing or malformed key. In A2 only a fake transport is ever wired.
public struct OpenRouterPastedLabelAITextAttempt: PastedLabelAITextAttempting {
    public static let maximumResponseBytes = OpenRouterLabelPhotoAttempt.maximumResponseBytes

    let transport: any LabelPhotoHTTPTransporting
    let keys: any FoodWebKeyStoring
    let request: OpenRouterPastedLabelAITextRequest

    public var route: PastedLabelAITextRoute.Route { request.route }

    public init(transport: any LabelPhotoHTTPTransporting, keys: any FoodWebKeyStoring, request: OpenRouterPastedLabelAITextRequest) {
        self.transport = transport; self.keys = keys; self.request = request
    }

    public func attempt(text: String, timeout: TimeInterval) async -> PastedLabelAITextAttemptResult {
        if Task.isCancelled { return .notSent(.cancelled) }
        do { try OpenRouterPastedLabelAITextRequest.admit(text) } catch OpenRouterPastedLabelAITextRequest.BuildError.textTooLong {
            return .notSent(.textTooLong)
        } catch { return .notSent(.textEmpty) }
        guard let key = try? keys.load(), FoodWebKeySyntax.isValid(key) else { return .notSent(.keyMissing) }
        guard let http = try? request.httpRequest(text, key: key) else { return .notSent(.requestRefused) }
        do {
            let response = try await transport.send(http, timeout: timeout, maximumBodyBytes: Self.maximumResponseBytes)
            return .responded(PastedLabelAITextRawResponse(status: response.status, headers: response.headers, body: response.body,
                                                           exceededLimit: response.exceededLimit))
        } catch let error as LabelPhotoTransportError {
            switch error {
            case .timedOut: return .transportFailed(.timedOut)
            case .cancelled: return .transportFailed(.cancelled)
            case .offline: return .transportFailed(.offline)
            case .failed: return .transportFailed(.failed)
            }
        } catch {
            return .transportFailed(Task.isCancelled ? .cancelled : .failed)
        }
    }
}

/// The pure envelope check of a raw text-route reply (E5, E12 as on the photo route; T3). The
/// attempt returns bytes only; the caller applies this check, and only an `answered` envelope's
/// content bytes go to `PastedLabelAITextReading`. A reply is an answer only when it is at most
/// 200,000 bytes, HTTP 200, holds exactly one choice whose `finish_reason` is `stop`, carries no
/// tool call or refusal, names the requested model exactly and the pinned endpoint's provider, has
/// a generation ID, and its message content is a string of at most 65,536 bytes. The content is
/// not decoded here. Anything else is a failed read with nothing shown.
public enum PastedLabelAITextEnvelope {
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
        ((try? JSONSerialization.jsonObject(with: body)) as? [String: Any]).map(OpenRouterLabelPhotoAttempt.usage(in:))
    }

    public static func check(_ response: PastedLabelAITextRawResponse, route: PastedLabelAITextRoute.Route) -> Outcome {
        let retryAfter = response.headers.first { $0.key.caseInsensitiveCompare("Retry-After") == .orderedSame }?.value
        guard !response.exceededLimit, response.body.count <= OpenRouterPastedLabelAITextAttempt.maximumResponseBytes else {
            return .failed(.contentFailure, failure: .oversize, usage: nil)
        }
        let object = (try? JSONSerialization.jsonObject(with: response.body)) as? [String: Any]
        let usage = object.map(OpenRouterLabelPhotoAttempt.usage(in:))
        func failed(_ outcome: LabelPhotoRetryPolicy.Outcome, _ failure: LabelImageReadingFailure) -> Outcome {
            .failed(outcome, failure: failure, usage: usage)
        }
        let choices = object?["choices"] as? [Any]
        let hasChoices = !(choices ?? []).isEmpty
        let errorCode = ((object?["error"] as? [String: Any])?["code"]).flatMap(OpenRouterLabelPhotoAttempt.integer)
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
              OpenRouterLabelPhotoAttempt.normalisedProvider(provider) == OpenRouterLabelPhotoAttempt.normalisedProvider(route.providerName) else {
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
}
