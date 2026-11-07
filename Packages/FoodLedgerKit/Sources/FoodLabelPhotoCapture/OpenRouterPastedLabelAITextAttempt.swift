import FoodLedgerApplication
import Foundation

/// The `PastedLabelAITextAttempting` adapter (docs/pasted-label-ai-text-v1.md 11.1, T1 to T4): one
/// attempt over an injected transport, returning the raw reply bytes only. It never decodes the
/// text wire. It refuses, before sending anything, a cancelled task, an empty text, a text over
/// 8,000 scalars and a missing or malformed key. In A2 only a fake transport is ever wired. The
/// caller applies `PastedLabelAITextEnvelope` (in the application layer) to the raw reply.
public struct OpenRouterPastedLabelAITextAttempt: PastedLabelAITextAttempting {
    public static let maximumResponseBytes = PastedLabelAITextEnvelope.maximumResponseBytes

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
