import Foundation
import FoodLedgerDomain

/// Retry rules for one web lookup model call (#500, docs/generic-food-proposal-integration-v1.md
/// "Model call retry amendment"). Pure: the outcome, elapsed time, `Retry-After` text, the current
/// date and a jitter value in [0, 1) come in, so tests drive every path without a clock or a network.
///
/// Only transport errors, timeouts and HTTP 408, 429, 500, 502, 503 and 504 are retried, by
/// resending the identical request to the same endpoint, with exponential backoff and jitter that
/// honours `Retry-After` in its seconds and HTTP-date forms: at most 3 attempts within a 120 s
/// whole-call deadline, 90 s per attempt, never a wait longer than 10 s, and no attempt started
/// with less than 15 s left. Key rejection (401,
/// 403), credit limits (402), rejected requests and content failures are never retried. Website
/// page fetches are not model calls and keep their no-retry rule.
public enum FoodWebModelCallRetryPolicy {
    public static let maxAttempts = 3
    public static let attemptTimeout: TimeInterval = 90
    public static let deadline: TimeInterval = 120
    public static let baseDelay: TimeInterval = 1
    /// A `Retry-After` longer than this is not waited for; the call stops instead.
    public static let maxDelay: TimeInterval = 10
    /// No attempt is started with less than this left before the deadline: a billed request
    /// that could not finish is never sent. The 15 s floor is a conservative judgement for
    /// #500, not a measured reply time.
    public static let minimumAttemptTime: TimeInterval = 15
    public static let retryableStatuses: Set<Int> = [408, 429, 500, 502, 503, 504]

    public enum Outcome: Equatable, Sendable {
        case transportError
        case timedOut
        /// An HTTP error status, or an OpenRouter error code carried in an HTTP 200 envelope,
        /// with the reply's `Retry-After` header text if any.
        case httpStatus(Int, retryAfter: String?)
        /// Anything else: unreadable replies, refusals, wrong model or provider, rejected input.
        case notRetryable
    }

    public enum Stop: Equatable, Sendable { case notRetryable, attemptsExhausted, deadline, waitTooLong }

    public enum Decision: Equatable, Sendable {
        /// Wait `after` seconds, then resend with at most `timeout` seconds for that attempt, so the
        /// whole call ends by the deadline by construction.
        case retry(after: TimeInterval, timeout: TimeInterval)
        case stop(Stop)
    }

    public static func isRetryable(_ outcome: Outcome) -> Bool {
        switch outcome {
        case .transportError, .timedOut: return true
        case let .httpStatus(status, _): return retryableStatuses.contains(status)
        case .notRetryable: return false
        }
    }

    /// `Retry-After` as a delay in seconds: a non-negative integer, or an HTTP-date (IMF-fixdate)
    /// measured from `now`; nil when absent or unreadable. A date in the past is zero.
    public static func retryAfter(_ text: String?, now: Date) -> TimeInterval? {
        guard let text = text?.trimmingCharacters(in: .whitespaces), !text.isEmpty else { return nil }
        if let seconds = Int(text) { return seconds >= 0 ? TimeInterval(seconds) : nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"
        guard let date = formatter.date(from: text) else { return nil }
        return max(0, date.timeIntervalSince(now))
    }

    /// The time an attempt starting `elapsed` seconds into the call may take.
    public static func attemptTimeout(elapsed: TimeInterval) -> TimeInterval {
        max(0, min(attemptTimeout, deadline - elapsed))
    }

    /// After attempt `attempt` (1-based) ended with `outcome`, `elapsed` seconds into the call.
    /// The delay is the larger of `Retry-After` and the backoff `baseDelay × 2^(attempt-1)` scaled
    /// by (0.5 + jitter / 2). The call stops when the delay exceeds `maxDelay` or the next attempt
    /// would start with less than `minimumAttemptTime` left before the deadline.
    public static func next(afterAttempt attempt: Int, outcome: Outcome, elapsed: TimeInterval, now: Date,
                            jitter: Double) -> Decision {
        guard isRetryable(outcome) else { return .stop(.notRetryable) }
        guard attempt < maxAttempts else { return .stop(.attemptsExhausted) }
        let header: String?
        if case let .httpStatus(_, retryAfter) = outcome { header = retryAfter } else { header = nil }
        let jitter = jitter.isFinite ? min(max(jitter, 0), 1) : 0
        let backoff = baseDelay * pow(2, Double(attempt - 1)) * (0.5 + jitter / 2)
        let delay = max(retryAfter(header, now: now) ?? 0, backoff)
        guard delay <= maxDelay else { return .stop(.waitTooLong) }
        guard deadline - (elapsed + delay) >= minimumAttemptTime else { return .stop(.deadline) }
        return .retry(after: delay, timeout: attemptTimeout(elapsed: elapsed + delay))
    }
}

/// Why the check of whether a source suits the food did not produce a usable answer (#500).
/// Carried in the review result and shown in Developer tools; never the key or any payload.
/// The raw values are diagnostic labels only and are not persisted.
public enum FoodProposalSelectionFailure: String, CaseIterable, Equatable, Sendable {
    case transport = "transport"
    case timedOut = "timed_out"
    /// A rate or credit limit (HTTP 429 after retries, or 402).
    case rateLimited = "rate_limited"
    case serverError = "server_error"
    case invalidResponse = "invalid_response"
    /// The answer named a choice that was not among the offered candidates.
    case choiceNotOffered = "choice_not_offered"
    /// The request or model configuration was refused (HTTP 400, 403, 404 or 422).
    case requestRejected = "request_rejected"

    /// Classifies a selection call's error. Credential rejection and cancellation are not
    /// failures of the check and are handled by the caller before this.
    public init(_ error: any Error) {
        switch error {
        case let error as FoodWebDiscoveryError:
            switch error {
            case .connectionFailed: self = .transport
            case .timedOut: self = .timedOut
            case .quotaExceeded: self = .rateLimited
            case .serviceUnavailable: self = .serverError
            case .requestRejected, .permissionDenied, .invalidQuery, .credentialRejected: self = .requestRejected
            case .invalidResponse: self = .invalidResponse
            }
        case let error as GenericFoodProposalError where error == .invalidSelection: self = .choiceNotOffered
        default: self = .invalidResponse
        }
    }

    /// Whether a fresh lookup of the same food can reasonably succeed.
    public var canLookUpAgain: Bool { self != .requestRejected }
}
