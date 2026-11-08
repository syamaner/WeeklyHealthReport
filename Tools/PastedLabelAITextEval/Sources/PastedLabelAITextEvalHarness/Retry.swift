import FoodLedgerApplication
import Foundation

/// The retry rule of `send` (A3; the owner's rule that every external call retries with backoff and
/// honours `Retry-After`). Only a transient failure is retried: a transport failure other than a
/// cancellation, HTTP 429, or an HTTP 5xx. A 200 (whether or not it passes the envelope check), a
/// 4xx other than 429, a reply that passed the envelope and anything not sent are never retried.
///
/// The wait before attempt n + 1 is the larger of the `Retry-After` header (seconds or an HTTP date,
/// read by the shipped `LabelPhotoRetryPolicy.retryAfter`) and the backoff `baseDelay × 2^(n-1)`
/// scaled by (0.5 + jitter / 2). A `Retry-After` longer than `maximumWait` is honoured by stopping,
/// never by retrying sooner. At most `maxAttempts` attempts are made in all.
///
/// The clock, the sleeper and the jitter are injected, so tests never wait. Every attempt is a
/// fresh reservation of W in the spend ledger (see `SendCommand`), so a retry never sends outside
/// a reservation.
public struct SendRetryPolicy: Sendable {
    public static let maximumAttempts = 3
    public static let baseDelay: TimeInterval = 1
    public static let maximumWait: TimeInterval = 30

    public let maxAttempts: Int
    public let baseDelay: TimeInterval
    public let maximumWait: TimeInterval
    public let sleep: @Sendable (TimeInterval) async throws -> Void
    public let jitter: @Sendable () -> Double
    public let now: @Sendable () -> Date

    public init(maxAttempts: Int = Self.maximumAttempts, baseDelay: TimeInterval = Self.baseDelay, maximumWait: TimeInterval = Self.maximumWait,
                sleep: @escaping @Sendable (TimeInterval) async throws -> Void = SendRetryPolicy.taskSleep,
                jitter: @escaping @Sendable () -> Double = { Double.random(in: 0..<1) },
                now: @escaping @Sendable () -> Date = { Date() }) {
        self.maxAttempts = min(max(maxAttempts, 1), Self.maximumAttempts)
        self.baseDelay = baseDelay
        self.maximumWait = min(maximumWait, Self.maximumWait)
        self.sleep = sleep; self.jitter = jitter; self.now = now
    }

    /// Up to three attempts over the live transport.
    public static var standard: SendRetryPolicy { SendRetryPolicy() }
    /// One attempt: the directory fake transport answers the same every time, so a retry there would
    /// only repeat the same reply and charge W again.
    public static var single: SendRetryPolicy { SendRetryPolicy(maxAttempts: 1) }

    @Sendable public static func taskSleep(_ seconds: TimeInterval) async throws {
        try await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000))
    }

    public enum Decision: Equatable, Sendable {
        case retry(after: TimeInterval)
        /// Stop; the reason is set when a transient failure was not retried (`attempts_exhausted`,
        /// `retry_after_over_cap`), nil when the result was not retryable.
        case stop(String?)
    }

    public static func isTransient(_ result: PastedLabelAITextAttemptResult) -> Bool {
        switch result {
        case .notSent: false
        case let .transportFailed(reason): reason != .cancelled
        case let .responded(response): response.status == 429 || (500...599).contains(response.status)
        }
    }

    /// After attempt `attempt` (1-based) ended with `result`.
    public func decide(afterAttempt attempt: Int, result: PastedLabelAITextAttemptResult, now: Date, jitter: Double) -> Decision {
        guard Self.isTransient(result) else { return .stop(nil) }
        guard attempt < maxAttempts else { return .stop("attempts_exhausted") }
        var header: String?
        if case let .responded(response) = result {
            header = response.headers.first { $0.key.caseInsensitiveCompare("Retry-After") == .orderedSame }?.value
        }
        let retryAfter = LabelPhotoRetryPolicy.retryAfter(header, now: now)
        if let retryAfter, retryAfter > maximumWait { return .stop("retry_after_over_cap") }
        let backoff = baseDelay * pow(2, Double(attempt - 1)) * (0.5 + min(max(jitter, 0), 1) / 2)
        return .retry(after: min(max(retryAfter ?? 0, backoff), maximumWait))
    }
}
