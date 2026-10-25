import Foundation

/// Spend rules for label photo reading (docs/label-photo-ai-prefill-v1.md E9, E10 and 17.5).
/// Pure: prices, the day and the recorded counts come in; no clock, network or storage.
///
/// - Per tap, $0.05 in total across every attempt that sent bytes. Before each attempt its worst
///   case W (6,000 prompt tokens at the prompt price, plus `maxTokens` at the completion price,
///   plus the reasoning limit as well when the endpoint bills reasoning outside `maxTokens`) must
///   fit in what the tap has left. An attempt is charged its reported cost, or W when none is
///   reported (including one cut by Cancel).
/// - Per local calendar day, at most 30 reads and $0.50. A tap with any attempt lacking a reported
///   cost counts as $0.05 toward the day.
/// - A tap whose reported cost exceeds $0.05, or whose reported prompt tokens exceed 6,000, pauses
///   reading for the rest of that day.
/// - A day record that cannot be read fails closed: reading is unavailable, as if the limit were
///   reached.
public enum LabelPhotoSpendPolicy {
    public static let perTapLimit = Decimal(string: "0.05")!
    public static let dailyCostLimit = Decimal(string: "0.50")!
    public static let dailyReadLimit = 30
    public static let promptTokenCeiling = 6_000
    public static let maxTokens = 1_200
    public static let reasoningLimit = 500

    /// Prices per token, from the day's catalogue check, and whether the endpoint bills
    /// reasoning tokens outside `max_tokens` (confirmed for the endpoint in L3).
    public struct Prices: Equatable, Sendable {
        public let promptPerToken: Decimal
        public let completionPerToken: Decimal
        public let reasoningBilledSeparately: Bool
        public init(promptPerToken: Decimal, completionPerToken: Decimal, reasoningBilledSeparately: Bool) {
            self.promptPerToken = promptPerToken; self.completionPerToken = completionPerToken
            self.reasoningBilledSeparately = reasoningBilledSeparately
        }
    }

    /// One attempt that sent bytes: its reported cost and prompt tokens, when the reply had them.
    public struct Attempt: Equatable, Sendable {
        public let reportedCost: Decimal?
        public let promptTokens: Int?
        public init(reportedCost: Decimal?, promptTokens: Int?) { self.reportedCost = reportedCost; self.promptTokens = promptTokens }
    }

    public static func worstCase(_ prices: Prices) -> Decimal {
        let completion = maxTokens + (prices.reasoningBilledSeparately ? reasoningLimit : 0)
        return Decimal(promptTokenCeiling) * prices.promptPerToken + Decimal(completion) * prices.completionPerToken
    }

    /// What the tap's attempts have been charged so far.
    public static func charged(_ attempts: [Attempt], prices: Prices) -> Decimal {
        attempts.reduce(Decimal(0)) { $0 + ($1.reportedCost ?? worstCase(prices)) }
    }

    /// Whether another attempt may start within the tap's $0.05.
    public static func mayStartAttempt(after attempts: [Attempt], prices: Prices) -> Bool {
        charged(attempts, prices: prices) + worstCase(prices) <= perTapLimit
    }

    /// One local day's counts, as the spend ledger stores them.
    public struct Day: Equatable, Sendable, Codable {
        public let day: String
        public let reads: Int
        public let cost: Decimal
        public let paused: Bool
        public init(day: String, reads: Int, cost: Decimal, paused: Bool) {
            self.day = day; self.reads = reads; self.cost = cost; self.paused = paused
        }
        public static func empty(_ day: String) -> Day { Day(day: day, reads: 0, cost: 0, paused: false) }
    }

    /// The local calendar day of `date` under the injected calendar (its time zone included).
    public static func dayKey(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    public enum Admission: Equatable, Sendable { case allowed, limitReached, paused }

    /// Whether a new read may start today. `stored` is the ledger's record, or nil when it could
    /// not be read (fail closed). A record for an earlier day means a fresh day.
    public static func admission(today: String, stored: Day?, ledgerReadable: Bool) -> Admission {
        guard ledgerReadable else { return .limitReached }
        guard let stored, stored.day == today else { return .allowed }
        if stored.paused { return .paused }
        if stored.reads >= dailyReadLimit || stored.cost >= dailyCostLimit { return .limitReached }
        return .allowed
    }

    /// The day after a finished tap (success, failure or Cancel) that sent at least one attempt.
    public static func record(_ attempts: [Attempt], today: String, stored: Day?) -> Day {
        let base = stored?.day == today ? stored! : Day.empty(today)
        guard !attempts.isEmpty else { return base }
        let unknown = attempts.contains { $0.reportedCost == nil }
        let reported = attempts.reduce(Decimal(0)) { $0 + ($1.reportedCost ?? 0) }
        let tapCost = unknown ? perTapLimit : reported
        let overCap = reported > perTapLimit
        let overInput = attempts.contains { ($0.promptTokens ?? 0) > promptTokenCeiling }
        return Day(day: today, reads: base.reads + 1, cost: base.cost + tapCost, paused: base.paused || overCap || overInput)
    }
}
