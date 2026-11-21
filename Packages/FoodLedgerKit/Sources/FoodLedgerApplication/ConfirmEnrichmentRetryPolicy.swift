import Foundation
import FoodLedgerDomain

/// Retries for Confirm enrichment (docs/confirm-enrichment-openrouter-v1.md CE1.3, the network
/// resilience rule): only transport errors, timeouts, HTTP 408, 429, 500, 502, 503 and 504, and
/// provider-overloaded answers; exponential backoff with jitter honouring `Retry-After` in seconds and
/// HTTP-date forms; at most 3 attempts within a 60 s whole-call deadline and 30 s per attempt. Content
/// failures are never retried. Pure: the time and jitter come in.
public enum ConfirmEnrichmentRetryPolicy {
    public static let maxAttempts = 3
    public static let attemptTimeout: TimeInterval = 30
    public static let deadline: TimeInterval = 60
    public static let baseDelay: TimeInterval = 1
    public static let retryableStatuses: Set<Int> = [408, 429, 500, 502, 503, 504]
    /// OpenRouter error codes that mean the provider is overloaded, in an envelope without `choices`.
    public static let overloadedCodes: Set<Int> = [502, 503, 529]

    public enum Outcome: Equatable, Sendable {
        case transportError
        case timedOut
        case httpStatus(Int, retryAfter: String?)
        case providerOverloaded(retryAfter: String?)
        case contentFailure
    }

    public enum Decision: Equatable, Sendable {
        case retry(after: TimeInterval)
        case stop
    }

    public static func isRetryable(_ outcome: Outcome) -> Bool {
        switch outcome {
        case .transportError, .timedOut, .providerOverloaded: true
        case let .httpStatus(status, _): retryableStatuses.contains(status)
        case .contentFailure: false
        }
    }

    /// Whether a 200 body is a provider-overloaded envelope: an error object with an overloaded code
    /// and no `choices`.
    public static func isOverloadedEnvelope(_ body: Data) -> Bool {
        guard let root = try? JSONSerialization.jsonObject(with: body) as? [String: Any], root["choices"] == nil,
              let error = root["error"] as? [String: Any], let code = (error["code"] as? NSNumber)?.intValue else { return false }
        return overloadedCodes.contains(code)
    }

    /// `Retry-After` as seconds from `now`: a non-negative integer or an IMF-fixdate; nil otherwise.
    public static func retryAfter(_ text: String?, now: Date) -> TimeInterval? {
        LabelPhotoRetryPolicy.retryAfter(text, now: now)
    }

    /// The time an attempt starting `elapsed` seconds into the call may take.
    public static func attemptTimeout(elapsed: TimeInterval) -> TimeInterval {
        max(0, min(attemptTimeout, deadline - elapsed))
    }

    /// After attempt `number` (1-based) ended with `outcome`: wait and retry, or stop. The wait is
    /// `Retry-After` when given, else `baseDelay * 2^(number-1)` with up to that much jitter added; a
    /// wait that leaves no time before the deadline stops.
    public static func next(afterAttempt number: Int, outcome: Outcome, elapsed: TimeInterval, now: Date,
                            jitter: Double) -> Decision {
        guard number < maxAttempts, isRetryable(outcome) else { return .stop }
        let header: String?
        switch outcome {
        case let .httpStatus(_, retryAfter), let .providerOverloaded(retryAfter): header = retryAfter
        default: header = nil
        }
        let backoff = baseDelay * pow(2, Double(number - 1))
        let wait = retryAfter(header, now: now) ?? backoff + backoff * min(1, max(0, jitter))
        guard elapsed + wait < deadline else { return .stop }
        return .retry(after: wait)
    }
}
