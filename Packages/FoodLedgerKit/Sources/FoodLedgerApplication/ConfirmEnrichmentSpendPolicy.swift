import Foundation
import FoodLedgerDomain

/// Spend rules for Confirm enrichment (docs/confirm-enrichment-openrouter-v1.md CE1.3; phase gate
/// section 2.6), the shape of `LabelPhotoSpendPolicy`. Pure: prices, the day and the counts come in.
/// Money is an integer count of micro-dollars, rounded up.
///
/// - W per attempt: the prompt ceiling at the prompt price plus the completion ceiling (and the
///   reasoning limit where billed separately) at the completion price, from the day's catalogue check.
/// - Whole-request cap: an attempt starts only when the request's attempts charged so far plus W are
///   at most $0.01 (A) or $0.02 (B).
/// - Day cap: a request starts only when fewer than 100 requests are counted today and the settled
///   cost plus every open reservation plus this request's cap is at most $0.50.
/// - A reservation writes the whole per-request cap before the first attempt; the reconcile moves it
///   to the attempts' reported costs (unreported attempts at W), up or down, never clamped.
/// - One pause trigger, per part, at reconcile: an attempt reported above W, a request whose reported
///   total is above its cap, or an attempt whose reported prompt tokens are above the route's ceiling.
/// - An unreadable record becomes today's record with 100 requests, written at once (fail closed).
/// - A stored day on or after today is kept, so a clock moved back never resets the allowance.
public enum ConfirmEnrichmentSpendPolicy {
    public static let schema = "confirm-enrichment-day-v1"
    public static let dailyRequestLimit = 100
    public static let dailyCapMicroUSD = 500_000

    /// One open reservation.
    public struct OpenRequest: Codable, Equatable, Sendable {
        public let requestID: String
        public let part: ConfirmEnrichmentPart
        public let chargedMicroUSD: Int
        public let attemptsSent: Int

        enum CodingKeys: String, CodingKey, CaseIterable {
            case part
            case requestID = "request_id"
            case chargedMicroUSD = "charged_microusd"
            case attemptsSent = "attempts_sent"
        }

        public init(requestID: String, part: ConfirmEnrichmentPart, chargedMicroUSD: Int, attemptsSent: Int) {
            self.requestID = requestID; self.part = part; self.chargedMicroUSD = chargedMicroUSD; self.attemptsSent = attemptsSent
        }

        public init(from decoder: any Decoder) throws {
            try ConfirmEnrichmentStrictObject.require(CodingKeys.self, in: decoder)
            let c = try decoder.container(keyedBy: CodingKeys.self)
            requestID = try c.decode(String.self, forKey: .requestID)
            part = try c.decode(ConfirmEnrichmentPart.self, forKey: .part)
            chargedMicroUSD = try c.decode(Int.self, forKey: .chargedMicroUSD)
            attemptsSent = try c.decode(Int.self, forKey: .attemptsSent)
            guard !requestID.isEmpty, chargedMicroUSD >= 0, attemptsSent >= 0 else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid open request"))
            }
        }
    }

    /// `confirm-enrichment-day-v1`.
    public struct Day: Codable, Equatable, Sendable {
        public let localDay: String
        public let requests: Int
        public let settledMicroUSD: Int
        public let paused: [ConfirmEnrichmentPart]
        public let openRequests: [OpenRequest]

        enum CodingKeys: String, CodingKey, CaseIterable {
            case schema, requests, paused
            case localDay = "local_day"
            case settledMicroUSD = "settled_microusd"
            case openRequests = "open_requests"
        }

        public init(localDay: String, requests: Int = 0, settledMicroUSD: Int = 0, paused: [ConfirmEnrichmentPart] = [],
                    openRequests: [OpenRequest] = []) {
            self.localDay = localDay; self.requests = requests; self.settledMicroUSD = settledMicroUSD
            self.paused = ConfirmEnrichmentPart.allCases.filter(paused.contains)
            self.openRequests = openRequests
        }

        public init(from decoder: any Decoder) throws {
            try ConfirmEnrichmentStrictObject.require(CodingKeys.self, in: decoder)
            let c = try decoder.container(keyedBy: CodingKeys.self)
            guard try c.decode(String.self, forKey: .schema) == ConfirmEnrichmentSpendPolicy.schema else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unknown schema"))
            }
            localDay = try c.decode(String.self, forKey: .localDay)
            requests = try c.decode(Int.self, forKey: .requests)
            settledMicroUSD = try c.decode(Int.self, forKey: .settledMicroUSD)
            paused = try c.decode([ConfirmEnrichmentPart].self, forKey: .paused)
            openRequests = try c.decode([OpenRequest].self, forKey: .openRequests)
            guard localDay.range(of: #"^[0-9]{4}-[0-9]{2}-[0-9]{2}$"#, options: .regularExpression) != nil,
                  requests >= 0, settledMicroUSD >= 0, Set(paused).count == paused.count,
                  Set(openRequests.map(\.requestID)).count == openRequests.count else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Inconsistent day record"))
            }
        }

        public func encode(to encoder: any Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(ConfirmEnrichmentSpendPolicy.schema, forKey: .schema)
            try c.encode(localDay, forKey: .localDay)
            try c.encode(requests, forKey: .requests)
            try c.encode(settledMicroUSD, forKey: .settledMicroUSD)
            try c.encode(paused, forKey: .paused)
            try c.encode(openRequests, forKey: .openRequests)
        }

        /// What today's open reservations hold.
        public var openMicroUSD: Int { openRequests.reduce(0) { $0 + $1.chargedMicroUSD } }
    }

    /// The ledger's stored state, as label photo's `Stored`.
    public enum Stored: Equatable, Sendable {
        case absent
        case day(Day)
        case unreadable
    }

    /// One attempt that sent bytes: its reported cost and prompt tokens, when the reply had them.
    public struct Attempt: Equatable, Sendable {
        public let reportedMicroUSD: Int?
        public let promptTokens: Int?
        public init(reportedMicroUSD: Int?, promptTokens: Int?) {
            self.reportedMicroUSD = reportedMicroUSD; self.promptTokens = promptTokens
        }
    }

    public enum Admission: Equatable, Sendable { case allowed, limitReached, paused }

    // MARK: Money

    /// US dollars to whole micro-dollars, rounded up.
    public static func microUSD(_ usd: Decimal) -> Int {
        var scaled = usd * 1_000_000
        var rounded = Decimal()
        NSDecimalRound(&rounded, &scaled, 0, .up)
        return NSDecimalNumber(decimal: rounded).intValue
    }

    /// The local calendar day of `date` in `timeZone`.
    public static func dayKey(_ date: Date, timeZone: TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// W for one attempt, in whole micro-dollars rounded up.
    public static func worstCase(_ route: ConfirmEnrichmentRoute, prices: ConfirmEnrichmentPrices) -> Int {
        let completion = route.completionCeilingTokens + (route.reasoningBilledSeparately ? route.reasoningLimitTokens : 0)
        return microUSD(Decimal(route.promptCeilingTokens) * prices.promptPerTokenUSD
                        + Decimal(completion) * prices.completionPerTokenUSD)
    }

    /// Whether the day's prices let the part run at all: W within the per-request cap.
    public static func routeFits(_ route: ConfirmEnrichmentRoute, prices: ConfirmEnrichmentPrices) -> Bool {
        worstCase(route, prices: prices) <= route.part.perRequestCapMicroUSD
    }

    /// What a request's attempts have been charged: each attempt's reported cost, or W.
    public static func attemptsCharged(_ attempts: [Attempt], w: Int) -> Int {
        attempts.reduce(0) { $0 + ($1.reportedMicroUSD ?? w) }
    }

    /// Whether another attempt may start within the whole-request cap.
    public static func mayStartAttempt(_ attempts: [Attempt], w: Int, part: ConfirmEnrichmentPart) -> Bool {
        attemptsCharged(attempts, w: w) + w <= part.perRequestCapMicroUSD
    }

    // MARK: The day

    /// The day `stored` counts against today. An unreadable record becomes a closed day (fail closed).
    public static func current(today: String, stored: Stored) -> Day {
        switch stored {
        case .absent: return Day(localDay: today)
        case .unreadable: return Day(localDay: today, requests: dailyRequestLimit)
        case let .day(day): return day.localDay >= today ? day : Day(localDay: today)
        }
    }

    /// Whether a new request for `part` may start today.
    public static func admission(_ part: ConfirmEnrichmentPart, day: Day) -> Admission {
        if day.paused.contains(part) { return .paused }
        if day.requests >= dailyRequestLimit
            || day.settledMicroUSD + day.openMicroUSD + part.perRequestCapMicroUSD > dailyCapMicroUSD { return .limitReached }
        return .allowed
    }

    /// The day with a request reserved at its whole cap, or nil when the request may not start.
    public static func reserved(_ part: ConfirmEnrichmentPart, requestID: String, day: Day) -> Day? {
        guard admission(part, day: day) == .allowed, !day.openRequests.contains(where: { $0.requestID == requestID }) else { return nil }
        return Day(localDay: day.localDay, requests: day.requests + 1, settledMicroUSD: day.settledMicroUSD, paused: day.paused,
                   openRequests: day.openRequests + [OpenRequest(requestID: requestID, part: part,
                                                                 chargedMicroUSD: part.perRequestCapMicroUSD, attemptsSent: 0)])
    }

    /// One more attempt sent for an open request; unchanged when it is no longer open.
    public static func attemptSent(_ requestID: String, day: Day) -> Day {
        Day(localDay: day.localDay, requests: day.requests, settledMicroUSD: day.settledMicroUSD, paused: day.paused,
            openRequests: day.openRequests.map {
                $0.requestID == requestID
                    ? OpenRequest(requestID: $0.requestID, part: $0.part, chargedMicroUSD: $0.chargedMicroUSD, attemptsSent: $0.attemptsSent + 1)
                    : $0
            })
    }

    /// The reconcile of an open request: its charge becomes the attempts' cost, settled on the day it
    /// was reserved, and the part pauses on the trigger. Nil when the request is no longer open on
    /// that day (a retry, or a day change), so nothing applies twice.
    public static func reconciled(_ requestID: String, attempts: [Attempt], w: Int, route: ConfirmEnrichmentRoute,
                                  day: Day) -> Day? {
        guard let open = day.openRequests.first(where: { $0.requestID == requestID }) else { return nil }
        let charge = attemptsCharged(attempts, w: w)
        let reported = attempts.compactMap(\.reportedMicroUSD)
        let pause = reported.contains { $0 > w }
            || reported.reduce(0, +) > open.part.perRequestCapMicroUSD
            || attempts.contains { ($0.promptTokens ?? 0) > route.promptCeilingTokens }
        return Day(localDay: day.localDay, requests: day.requests, settledMicroUSD: day.settledMicroUSD + charge,
                   paused: pause ? day.paused + [open.part] : day.paused,
                   openRequests: day.openRequests.filter { $0.requestID != requestID })
    }

    /// The release of an open request that sent nothing: no request counted, nothing charged.
    public static func released(_ requestID: String, day: Day) -> Day? {
        guard day.openRequests.contains(where: { $0.requestID == requestID && $0.attemptsSent == 0 }) else { return nil }
        return Day(localDay: day.localDay, requests: max(0, day.requests - 1), settledMicroUSD: day.settledMicroUSD,
                   paused: day.paused, openRequests: day.openRequests.filter { $0.requestID != requestID })
    }
}
