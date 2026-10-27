import Foundation

/// Spend rules for label photo reading (docs/label-photo-ai-prefill-v1.md E9, E10 and 17.5).
/// Pure: prices, the day and the recorded counts come in; no clock, network or storage.
///
/// - Per tap, $0.05 in total across every attempt that sent bytes. Before each attempt its worst
///   case W (6,000 prompt tokens at the prompt price, plus `maxTokens` at the completion price,
///   plus the reasoning limit as well when the endpoint bills reasoning outside `maxTokens`) must
///   fit in what the tap has left. An attempt is charged its reported cost, or W when none is
///   reported (including one cut by Cancel).
/// - Per local calendar day, at most 30 reads and $0.50. A tap is admitted only while the day's
///   cost plus a whole tap's $0.05 stays within $0.50, so the day never exceeds it. A tap with
///   any attempt lacking a reported cost counts as at least $0.05 toward the day (E10): the larger
///   of $0.05 and its reported costs plus W for each unreported attempt. Otherwise a tap counts its
///   reported cost.
/// - A stored day later than today (the clock moved back) is treated as the same day: the
///   allowance never resets early.
/// - A tap whose reported cost exceeds $0.05, or whose reported prompt tokens exceed 6,000, pauses
///   reading for the rest of that day.
/// - A day record that cannot be read fails closed: reading is unavailable, as if the limit were
///   reached.
public enum LabelPhotoSpendPolicy {
    public static let perTapLimit = Decimal(string: "0.05")!
    public static let dailyCostLimit = Decimal(string: "0.50")!
    public static let dailyReadLimit = 30
    public static let promptTokenCeiling = 6_000
    /// Route v1's `max_tokens`; each route now carries its own (`LabelPhotoRoute.Route.maxOutputTokens`).
    public static let maxTokens = 1_200
    public static let reasoningLimit = 500

    /// Prices per token, from the day's catalogue check, and whether the endpoint bills
    /// reasoning tokens outside `max_tokens` (confirmed for the endpoint in L3).
    public struct Prices: Equatable, Sendable {
        public let promptPerToken: Decimal
        public let completionPerToken: Decimal
        public let reasoningBilledSeparately: Bool
        /// The route's `max_tokens` (17.21): 1,200 for route v1, 2,400 for route v2.
        public let maxOutputTokens: Int
        public init(promptPerToken: Decimal, completionPerToken: Decimal, reasoningBilledSeparately: Bool,
                    maxOutputTokens: Int = LabelPhotoSpendPolicy.maxTokens) {
            self.promptPerToken = promptPerToken; self.completionPerToken = completionPerToken
            self.reasoningBilledSeparately = reasoningBilledSeparately; self.maxOutputTokens = maxOutputTokens
        }
    }

    /// One attempt that sent bytes: its reported cost and prompt tokens, when the reply had them.
    public struct Attempt: Equatable, Sendable {
        public let reportedCost: Decimal?
        public let promptTokens: Int?
        public init(reportedCost: Decimal?, promptTokens: Int?) { self.reportedCost = reportedCost; self.promptTokens = promptTokens }
    }

    public static func worstCase(_ prices: Prices) -> Decimal {
        let completion = prices.maxOutputTokens + (prices.reasoningBilledSeparately ? reasoningLimit : 0)
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
        /// Taps reserved and not yet settled (#326 re-check): a settle acts only on its own open
        /// tap, so a retried settle never applies twice.
        public let openTaps: [String]
        public init(day: String, reads: Int, cost: Decimal, paused: Bool, openTaps: [String] = []) {
            self.day = day; self.reads = reads; self.cost = cost; self.paused = paused; self.openTaps = openTaps
        }

        enum CodingKeys: String, CodingKey { case day, reads, cost, paused, openTaps }

        public init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            day = try c.decode(String.self, forKey: .day); reads = try c.decode(Int.self, forKey: .reads)
            cost = try c.decode(Decimal.self, forKey: .cost); paused = try c.decode(Bool.self, forKey: .paused)
            openTaps = try c.decodeIfPresent([String].self, forKey: .openTaps) ?? []
        }
        public static func empty(_ day: String) -> Day { Day(day: day, reads: 0, cost: 0, paused: false) }
    }

    /// The local calendar day of `date` under the injected calendar (its time zone included).
    public static func dayKey(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    public enum Admission: Equatable, Sendable { case allowed, limitReached, paused }

    /// The spend ledger's stored day: none yet (a fresh day), a day, or a record that could not be
    /// read, which fails closed.
    public enum Stored: Equatable, Sendable {
        case absent
        case day(Day)
        case unreadable
    }

    /// The day `stored` counts against: its own when it is today or later (a clock moved back
    /// never resets the allowance), otherwise a fresh day.
    static func current(today: String, stored: Day?) -> Day {
        guard let stored, stored.day >= today else { return Day.empty(today) }
        return stored
    }

    /// Whether a new read may start today.
    public static func admission(today: String, stored: Stored) -> Admission {
        let day: Day
        switch stored {
        case .unreadable: return .limitReached
        case .absent: day = Day.empty(today)
        case let .day(record): day = current(today: today, stored: record)
        }
        if day.paused { return .paused }
        if day.reads >= dailyReadLimit || day.cost + perTapLimit > dailyCostLimit { return .limitReached }
        return .allowed
    }

    /// What one tap costs the day (E10): its reported cost; with any unreported attempt, the larger
    /// of $0.05 and its reported costs plus W for each unreported attempt.
    public static func tapCost(_ attempts: [Attempt], prices: Prices) -> Decimal {
        let charged = charged(attempts, prices: prices)
        return attempts.contains { $0.reportedCost == nil } ? max(perTapLimit, charged) : charged
    }

    /// The day with a tap reserved before its first send (#326 review): one read and a whole tap's
    /// $0.05, so a tap cut short by a crash or a kill still counts. `record` later reconciles it.
    public static func reservation(today: String, stored: Day?, tap: String = "") -> Day {
        let base = current(today: today, stored: stored)
        return Day(day: base.day, reads: base.reads + 1, cost: base.cost + perTapLimit, paused: base.paused,
                   openTaps: tap.isEmpty ? base.openTaps : base.openTaps + [tap])
    }

    /// The reconcile of an open tap on the day its reservation was written (the day the
    /// reservation's update returned, which may be later than today when the clock moved back).
    /// Nil when the tap is no longer open on that day: nothing to do, so a retry never applies twice.
    public static func reconciled(_ now: Day, reservedOn: String, tap: String, attempts: [Attempt], prices: Prices) -> Day? {
        guard now.day == reservedOn, now.openTaps.contains(tap) else { return nil }
        let settled = reconciled(Day(day: now.day, reads: now.reads, cost: now.cost, paused: now.paused), today: reservedOn,
                                 attempts: attempts, prices: prices)
        return Day(day: settled.day, reads: settled.reads, cost: settled.cost, paused: settled.paused,
                   openTaps: now.openTaps.filter { $0 != tap })
    }

    /// The release of an open tap that sent nothing, on the day its reservation was written.
    public static func released(_ now: Day, reservedOn: String, tap: String) -> Day? {
        guard now.day == reservedOn, now.openTaps.contains(tap) else { return nil }
        let settled = released(now, today: reservedOn)
        return Day(day: settled.day, reads: settled.reads, cost: settled.cost, paused: settled.paused,
                   openTaps: now.openTaps.filter { $0 != tap })
    }

    /// The reservation turned into the tap's cost, as a delta on the day as it is now (#326
    /// re-check): another session's taps since the reservation are kept. Reads are unchanged (the
    /// reservation already counted this one); the cost moves from $0.05 to the tap's cost, up or
    /// down; a reported cost over $0.05 or an input over the ceiling pauses the day. A day other
    /// than the tap's is left as it is.
    public static func reconciled(_ now: Day, today: String, attempts: [Attempt], prices: Prices) -> Day {
        guard now.day == today else { return now }
        let reported = attempts.reduce(Decimal(0)) { $0 + ($1.reportedCost ?? 0) }
        let overCap = reported > perTapLimit
        let overInput = attempts.contains { ($0.promptTokens ?? 0) > promptTokenCeiling }
        return Day(day: now.day, reads: now.reads, cost: max(0, now.cost - perTapLimit + tapCost(attempts, prices: prices)),
                   paused: now.paused || overCap || overInput)
    }

    /// A reservation released by a tap that sent nothing: one read and $0.05 fewer, as a delta.
    public static func released(_ now: Day, today: String) -> Day {
        guard now.day == today else { return now }
        return Day(day: now.day, reads: max(0, now.reads - 1), cost: max(0, now.cost - perTapLimit), paused: now.paused)
    }

    /// The day after a finished tap (success, failure or Cancel) that sent at least one attempt.
    public static func record(_ attempts: [Attempt], prices: Prices, today: String, stored: Day?) -> Day {
        let base = current(today: today, stored: stored)
        guard !attempts.isEmpty else { return base }
        let reported = attempts.reduce(Decimal(0)) { $0 + ($1.reportedCost ?? 0) }
        let overCap = reported > perTapLimit
        let overInput = attempts.contains { ($0.promptTokens ?? 0) > promptTokenCeiling }
        return Day(day: base.day, reads: base.reads + 1, cost: base.cost + tapCost(attempts, prices: prices),
                   paused: base.paused || overCap || overInput)
    }
}
