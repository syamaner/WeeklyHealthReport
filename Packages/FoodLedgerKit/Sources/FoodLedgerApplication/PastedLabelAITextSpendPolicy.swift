import Foundation

/// One route's share of the shared day record (`LabelPhotoSpendPolicy.Day`, version
/// `label-ai-spend-day-v1`): its reads and cost (already counted in the day's totals), its own
/// pause and its open taps.
public struct LabelAISpendRouteShare: Equatable, Sendable, Codable {
    public let reads: Int
    public let cost: Decimal
    public let paused: Bool
    public let openTaps: [String]

    public init(reads: Int, cost: Decimal, paused: Bool, openTaps: [String]) {
        self.reads = reads; self.cost = cost; self.paused = paused; self.openTaps = openTaps
    }

    public static let none = LabelAISpendRouteShare(reads: 0, cost: 0, paused: false, openTaps: [])

    enum CodingKeys: String, CodingKey, CaseIterable { case reads, cost, paused, openTaps }

    /// Strict: every member present, so a truncated share is corrupt rather than zero.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        reads = try c.decode(Int.self, forKey: .reads); cost = try c.decode(Decimal.self, forKey: .cost)
        paused = try c.decode(Bool.self, forKey: .paused); openTaps = try c.decode([String].self, forKey: .openTaps)
    }
}

/// Spend rules for the pasted label AI text route (docs/pasted-label-ai-text-v1.md 4.2, D14, D17,
/// T11; contract tests 11 and 20). Pure, over the one day record the photo route also writes:
///
/// - **One shared cap (D14):** at most 30 reads and $0.50 a day across both routes. A text tap is
///   admitted only while the day's total reads are under 30 and its total cost plus a whole text
///   tap's cap stays within $0.50.
/// - **Its own per-read cap:** `perTapLimit`, and its own prompt-token ceiling, sized for 8,000
///   scalars of Traditional Chinese. Both are provisional until A3 measures the evaluation's costs
///   (T11); a change is reviewed with the route.
/// - **Its own pause (D17):** a text read whose reported cost passes its cap, or whose prompt
///   tokens pass its ceiling, pauses only the text route for the day. The photo pause never stops
///   a text read, and the text pause never stops a photo read.
/// - **Unknown is never zero:** an attempt with no reported cost is charged its worst case W, and a
///   tap with any such attempt counts at least the whole per-tap cap (as photo E10).
/// - **Fails closed:** an unreadable record admits nothing; a stored day later than today counts
///   as today, so the allowance never resets early.
public enum PastedLabelAITextSpendPolicy {
    public typealias Day = LabelPhotoSpendPolicy.Day
    public typealias Prices = LabelPhotoSpendPolicy.Prices
    public typealias Attempt = LabelPhotoSpendPolicy.Attempt
    public typealias Admission = LabelPhotoSpendPolicy.Admission
    public typealias Stored = LabelPhotoSpendPolicy.Stored

    /// The text route's per-read cap (provisional, T11).
    public static let perTapLimit = Decimal(string: "0.05")!
    /// The prompt-token ceiling W prices: 8,000 scalars of Traditional Chinese, about one token per
    /// scalar, plus the instruction and schema (provisional, T11).
    public static let promptTokenCeiling = 12_000

    public static func worstCase(_ prices: Prices, reasoningLimit: Int) -> Decimal {
        let completion = prices.maxOutputTokens + (prices.reasoningBilledSeparately ? reasoningLimit : 0)
        return Decimal(promptTokenCeiling) * prices.promptPerToken + Decimal(completion) * prices.completionPerToken
    }

    public static func charged(_ attempts: [Attempt], worstCase: Decimal) -> Decimal {
        attempts.reduce(Decimal(0)) { $0 + ($1.reportedCost ?? worstCase) }
    }

    /// Whether another attempt may start within the tap's cap.
    public static func mayStartAttempt(after attempts: [Attempt], worstCase: Decimal) -> Bool {
        charged(attempts, worstCase: worstCase) + worstCase <= perTapLimit
    }

    /// What a tap costs the day: its reported cost; with any unreported attempt, the larger of the
    /// cap and its reported costs plus W for each unreported attempt.
    public static func tapCost(_ attempts: [Attempt], worstCase: Decimal) -> Decimal {
        let charged = charged(attempts, worstCase: worstCase)
        return attempts.contains { $0.reportedCost == nil } ? max(perTapLimit, charged) : charged
    }

    static func current(today: String, stored: Day?) -> Day {
        guard let stored, stored.day >= today else { return Day.empty(today) }
        return stored
    }

    /// Whether a new text read may start today.
    public static func admission(today: String, stored: Stored) -> Admission {
        let day: Day
        switch stored {
        case .unreadable: return .limitReached
        case .absent: day = Day.empty(today)
        case let .day(record): day = current(today: today, stored: record)
        }
        if day.text.paused { return .paused }
        if day.reads >= LabelPhotoSpendPolicy.dailyReadLimit || day.cost + perTapLimit > LabelPhotoSpendPolicy.dailyCostLimit {
            return .limitReached
        }
        return .allowed
    }

    /// The day with a text tap reserved before its first send: one read and the whole text cap, in
    /// both the shared totals and the text share, so a tap cut short by a crash still counts.
    public static func reservation(today: String, stored: Day?, tap: String) -> Day {
        let base = current(today: today, stored: stored)
        let text = LabelAISpendRouteShare(reads: base.text.reads + 1, cost: base.text.cost + perTapLimit, paused: base.text.paused,
                                          openTaps: base.text.openTaps + [tap])
        return Day(day: base.day, reads: base.reads + 1, cost: base.cost + perTapLimit, paused: base.paused, openTaps: base.openTaps, text: text)
    }

    /// The reservation of an open text tap turned into its cost, as a delta on the day as it is now
    /// (other taps since the reservation are kept). Nil when the tap is not open on that day, so a
    /// retried settle never applies twice. An over-cap or over-ceiling read pauses only the text route.
    public static func reconciled(_ now: Day, reservedOn: String, tap: String, attempts: [Attempt], worstCase: Decimal) -> Day? {
        guard now.day == reservedOn, now.text.openTaps.contains(tap) else { return nil }
        let reported = attempts.reduce(Decimal(0)) { $0 + ($1.reportedCost ?? 0) }
        let overCap = reported > perTapLimit
        let overInput = attempts.contains { ($0.promptTokens ?? 0) > promptTokenCeiling }
        let delta = (attempts.isEmpty ? 0 : tapCost(attempts, worstCase: worstCase)) - perTapLimit
        let textCost = max(0, now.text.cost + delta)
        let text = LabelAISpendRouteShare(reads: now.text.reads, cost: textCost, paused: now.text.paused || overCap || overInput,
                                          openTaps: now.text.openTaps.filter { $0 != tap })
        return Day(day: now.day, reads: now.reads, cost: max(textCost, now.cost + delta), paused: now.paused, openTaps: now.openTaps, text: text)
    }

    /// The release of an open text tap that sent nothing: one read and the cap fewer, in both.
    public static func released(_ now: Day, reservedOn: String, tap: String) -> Day? {
        guard now.day == reservedOn, now.text.openTaps.contains(tap) else { return nil }
        let text = LabelAISpendRouteShare(reads: max(0, now.text.reads - 1), cost: max(0, now.text.cost - perTapLimit), paused: now.text.paused,
                                          openTaps: now.text.openTaps.filter { $0 != tap })
        return Day(day: now.day, reads: max(text.reads, now.reads - 1), cost: max(text.cost, now.cost - perTapLimit), paused: now.paused,
                   openTaps: now.openTaps, text: text)
    }
}
