import Foundation

/// The two ports of the pasted label AI text route (docs/pasted-label-ai-text-v1.md 11.1).
///
/// - `PastedLabelAITextAttempting` takes the sent text and returns the raw response bytes. Its
///   adapter (in `FoodLabelPhotoCapture`, beside the OpenRouter transport) never decodes the text
///   wire, so no edge to the reading target appears.
/// - `PastedLabelAITextReading` takes the sent text and the model's raw answer bytes (the message
///   content) and returns a candidate with its attention inputs. Its adapter is
///   `FoodLabelTextAIReading`, which calls the frozen gate, conversions and checks.
///
/// Fakes and the real adapters pass the same contract suites (contract test 28,
/// `FoodLedgerTestSupport.PastedLabelAITextPortContracts`).

/// Why an attempt sent nothing (nothing is charged).
public enum PastedLabelAITextNotSent: String, Equatable, Sendable, Codable, CaseIterable {
    case cancelled
    case keyMissing = "key_missing"
    /// An empty or all-whitespace text.
    case textEmpty = "text_empty"
    /// More than `PastedLabelManifest.maximumTextScalars` Unicode scalars (T9).
    case textTooLong = "text_too_long"
    /// The request could not be built (a resource changed, or the key would appear in the body).
    case requestRefused = "request_refused"
}

/// A transport failure after the request may have been sent.
public enum PastedLabelAITextTransportFailure: String, Equatable, Sendable, Codable, CaseIterable {
    case timedOut = "timed_out", cancelled, offline, failed
}

/// The raw HTTP reply, exactly as received (at most the adapter's byte cap).
public struct PastedLabelAITextRawResponse: Equatable, Sendable {
    public let status: Int
    public let headers: [String: String]
    public let body: Data
    public let exceededLimit: Bool

    public init(status: Int, headers: [String: String], body: Data, exceededLimit: Bool) {
        self.status = status; self.headers = headers; self.body = body; self.exceededLimit = exceededLimit
    }
}

public enum PastedLabelAITextAttemptResult: Equatable, Sendable {
    /// Bytes were sent and a reply came back; nothing in it has been decoded.
    case responded(PastedLabelAITextRawResponse)
    /// Bytes may have been sent; no reply.
    case transportFailed(PastedLabelAITextTransportFailure)
    /// Nothing was sent.
    case notSent(PastedLabelAITextNotSent)

    public var sentBytes: Bool {
        switch self {
        case .responded, .transportFailed: true
        case .notSent: false
        }
    }
}

/// One attempt: the text in, the raw reply out, within `timeout` seconds. It must stop at once
/// when its task is cancelled, and refuse an empty text or one over 8,000 scalars before sending.
public protocol PastedLabelAITextAttempting: Sendable {
    /// The route every attempt is sent under.
    var route: PastedLabelAITextRoute.Route { get }
    func attempt(text: String, timeout: TimeInterval) async -> PastedLabelAITextAttemptResult
}

/// The text and the model's answer bytes in, the reading out. Pure and deterministic: the same
/// inputs always give the same result, and no value comes from anywhere but the answer, checked
/// against the text.
public protocol PastedLabelAITextReading: Sendable {
    func reading(text: String, textSHA256: String, answer: Data) -> PastedLabelAITextReadingResult
}
