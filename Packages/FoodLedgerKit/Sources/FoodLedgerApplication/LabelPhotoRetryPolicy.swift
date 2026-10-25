import Foundation

/// Retry rules for one label photo read (docs/label-photo-ai-prefill-v1.md E11 and 17.5). Pure:
/// the outcome, elapsed time, `Retry-After` text, the current date and a jitter value in [0, 1)
/// come in, so tests drive every path without a clock or a network.
///
/// Only transport errors, timeouts, HTTP 408, 429, 500, 502, 503 and 504, and a provider-overloaded
/// answer are retried, with exponential backoff and jitter, honouring `Retry-After` in its
/// seconds and HTTP-date forms; at most 3 attempts within a 90 s whole-call deadline, 45 s per
/// attempt. Content failures (schema, truncation, refusal, wrong model or provider) never are.
/// The spend policy decides separately whether the tap's budget allows another attempt.
public enum LabelPhotoRetryPolicy {
    public static let maxAttempts = 3
    public static let attemptTimeout: TimeInterval = 45
    public static let deadline: TimeInterval = 90
    public static let baseDelay: TimeInterval = 1
    public static let retryableStatuses: Set<Int> = [408, 429, 500, 502, 503, 504]
    /// OpenRouter error codes that mean the provider is overloaded (17.5).
    public static let overloadedCodes: Set<Int> = [502, 503, 529]

    public enum Outcome: Equatable, Sendable {
        case transportError
        case timedOut
        /// An HTTP reply with an error status, and its `Retry-After` header text if any.
        case httpStatus(Int, retryAfter: String?)
        /// An OpenRouter error object (in an HTTP error or a 200 envelope) with its numeric code,
        /// whether the reply carried `choices`, and its `Retry-After` header text if any.
        case providerError(code: Int?, hasChoices: Bool, retryAfter: String?)
        /// Schema-invalid output, truncation, refusal, tool calls, wrong model or provider.
        case contentFailure
    }

    /// The exact definition of a provider-overloaded answer (17.5).
    public static func isOverloaded(code: Int?, hasChoices: Bool) -> Bool {
        guard let code, !hasChoices else { return false }
        return overloadedCodes.contains(code)
    }

    public static func isRetryable(_ outcome: Outcome) -> Bool {
        switch outcome {
        case .transportError, .timedOut: return true
        case let .httpStatus(status, _): return retryableStatuses.contains(status)
        case let .providerError(code, hasChoices, _): return isOverloaded(code: code, hasChoices: hasChoices)
        case .contentFailure: return false
        }
    }

    /// `Retry-After` as a delay in seconds: a non-negative integer, or an HTTP-date (IMF-fixdate)
    /// measured from `now`; nil when absent or unreadable. A date in the past is zero.
    public static func retryAfter(_ text: String?, now: Date) -> TimeInterval? {
        guard let text = text?.trimmingCharacters(in: .whitespaces), !text.isEmpty else { return nil }
        if let seconds = Int(text), seconds >= 0 { return TimeInterval(seconds) }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"
        guard let date = formatter.date(from: text) else { return nil }
        return max(0, date.timeIntervalSince(now))
    }

    public enum Decision: Equatable, Sendable {
        /// Wait `after` seconds, then make the next attempt with at most `timeout` seconds, so the
        /// whole call ends by the deadline by construction.
        case retry(after: TimeInterval, timeout: TimeInterval)
        case stop(Stop)
    }

    /// The time an attempt starting `elapsed` seconds into the call may take: the per-attempt
    /// limit, or what is left of the deadline when that is less.
    public static func attemptTimeout(elapsed: TimeInterval) -> TimeInterval {
        max(0, min(attemptTimeout, deadline - elapsed))
    }

    public enum Stop: Equatable, Sendable { case notRetryable, attemptsExhausted, deadline }

    /// After attempt `attempt` (1-based) ended with `outcome`, `elapsed` seconds into the call.
    /// The delay is the larger of `Retry-After` and the backoff `baseDelay × 2^(attempt-1)`
    /// scaled by (0.5 + jitter / 2); the call stops when the next attempt could not start before
    /// the deadline.
    public static func next(afterAttempt attempt: Int, outcome: Outcome, elapsed: TimeInterval, now: Date,
                            jitter: Double) -> Decision {
        guard isRetryable(outcome) else { return .stop(.notRetryable) }
        guard attempt < maxAttempts else { return .stop(.attemptsExhausted) }
        let header: String?
        switch outcome {
        case let .httpStatus(_, retryAfter), let .providerError(_, _, retryAfter): header = retryAfter
        default: header = nil
        }
        let backoff = baseDelay * pow(2, Double(attempt - 1)) * (0.5 + min(max(jitter, 0), 1) / 2)
        let delay = max(retryAfter(header, now: now) ?? 0, backoff)
        guard elapsed + delay < deadline else { return .stop(.deadline) }
        return .retry(after: delay, timeout: attemptTimeout(elapsed: elapsed + delay))
    }
}
