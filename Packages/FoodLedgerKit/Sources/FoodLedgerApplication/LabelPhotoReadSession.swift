import Foundation

/// One app session's label photo reads (docs/label-photo-ai-prefill-v1.md E4, E7, E9 to E11 and
/// 17.5). For each Read tap, in order:
///
/// 1. The day's admission from the spend ledger (an unreadable ledger fails closed; a paused day or
///    a full allowance sends nothing).
/// 2. On the session's first tap only, the catalogue check before any image request: the route's
///    slug, endpoint, image input, zero data retention and prices must match, and the worst case
///    of one attempt must fit the tap's $0.05; any mismatch or failure ends the tap with nothing
///    sent. A pass is kept for the session.
/// 3. Attempts, each only when the tap's remaining budget covers a whole worst case, with the
///    retry policy's delay and clamped timeout, until an answer, a non-retryable failure, the
///    attempt or deadline limit, or Cancel.
/// 4. The tap's attempts recorded on the day (E10), Cancel included.
///
/// It never retries across a user action, never reads in the background and holds no image.
public actor LabelPhotoReadSession {
    public enum Outcome: Equatable, Sendable {
        /// The checked reply and the request record (instruction, schema, limits and the catalogue check).
        case answered(LabelPhotoWireReply, request: LabelPhotoManifest.Request)
        case failed(LabelImageReadingFailure)
    }

    let route: LabelPhotoRoute.Route
    let checker: any LabelPhotoRouteChecking
    let attempter: any LabelPhotoAttempting
    let ledger: any LabelPhotoSpendLedger
    let keys: any FoodWebKeyStoring
    let clock: any LedgerClock
    let calendar: Calendar
    let sleeper: any LabelPhotoSleeping
    let jitter: @Sendable () -> Double
    /// A fresh identifier for each tap's reservation (injected: no concrete generator here).
    let tapIDs: @Sendable () -> String
    /// Whether the endpoint bills reasoning outside `max_tokens` (an explicit composition choice; 17.18).
    let reasoningBilledSeparately: Bool
    /// The catalogue check that passed, and the local day it passed on (prices are per day).
    private(set) var catalogue: (check: LabelPhotoManifest.CatalogueCheck, day: String)?
    /// Set before the first suspension of a tap, so a second tap waits for nothing and sends nothing.
    private(set) var inFlight = false
    /// A spend ledger write failed: every further read this session is refused (fails closed).
    private(set) var ledgerFailed = false

    public init(route: LabelPhotoRoute.Route = LabelPhotoRoute.current, checker: any LabelPhotoRouteChecking, attempter: any LabelPhotoAttempting,
                ledger: any LabelPhotoSpendLedger, keys: any FoodWebKeyStoring, clock: any LedgerClock, calendar: Calendar,
                sleeper: any LabelPhotoSleeping, jitter: @escaping @Sendable () -> Double, tapIDs: @escaping @Sendable () -> String,
                reasoningBilledSeparately: Bool = false) {
        self.tapIDs = tapIDs
        self.route = route; self.checker = checker; self.attempter = attempter; self.ledger = ledger; self.keys = keys; self.clock = clock
        self.calendar = calendar; self.sleeper = sleeper; self.jitter = jitter; self.reasoningBilledSeparately = reasoningBilledSeparately
    }

    /// The catalogue check as a route identity and prices, or nil when it does not match the route.
    public static func prices(_ check: LabelPhotoManifest.CatalogueCheck, route: LabelPhotoRoute.Route,
                       reasoningBilledSeparately: Bool) -> LabelPhotoSpendPolicy.Prices? {
        guard check.slug == route.model, check.endpoint == route.endpoint, check.inputModalities.contains("image"),
              check.zeroDataRetention, let prompt = Decimal(string: check.promptPrice), let completion = Decimal(string: check.completionPrice),
              prompt >= 0, completion >= 0 else { return nil }
        let prices = LabelPhotoSpendPolicy.Prices(promptPerToken: prompt, completionPerToken: completion,
                                                  reasoningBilledSeparately: reasoningBilledSeparately)
        return LabelPhotoSpendPolicy.worstCase(prices) <= LabelPhotoSpendPolicy.perTapLimit ? prices : nil
    }

    /// Whether a tap may start today, from the spend ledger (7.2, section 9), and whether this
    /// session already found the route unavailable today.
    public struct Status: Equatable, Sendable {
        public enum Day: Equatable, Sendable {
            /// Open, with today's counted reads ("Today: n of 30").
            case open(reads: Int)
            case limitReached
            case paused
            /// The spend ledger cannot be read: the route fails closed, as the daily limit.
            case unreadable
        }
        public let day: Day
        public let routeUnavailable: Bool
        public init(day: Day, routeUnavailable: Bool) { self.day = day; self.routeUnavailable = routeUnavailable }
    }

    public func status() -> Status {
        let today = LabelPhotoSpendPolicy.dayKey(clock.now(), calendar: calendar)
        let stored = ledger.load()
        let day: Status.Day
        if ledgerFailed {
            day = .unreadable
        } else {
            switch (stored, LabelPhotoSpendPolicy.admission(today: today, stored: stored)) {
            case (.unreadable, _): day = .unreadable
            case (_, .paused): day = .paused
            case (_, .limitReached): day = .limitReached
            case (.absent, .allowed): day = .open(reads: 0)
            case let (.day(record), .allowed): day = .open(reads: LabelPhotoSpendPolicy.current(today: today, stored: record).reads)
            }
        }
        return Status(day: day, routeUnavailable: routeUnavailableOn == today)
    }

    /// The local day on which this session's catalogue check failed: no further tap that day
    /// checks again or sends anything (the route unavailable state, section 9).
    private(set) var routeUnavailableOn: String?

    /// `progress` is told the number of each attempt as it starts (1, 2, 3), for the Retrying copy.
    public func read(_ image: PreparedLabelImage, progress: (@Sendable (Int) -> Void)? = nil) async -> Outcome {
        // No suspension before this point: a concurrent tap is refused, never interleaved.
        guard !inFlight else { return .failed(.failed) }
        guard !ledgerFailed else { return .failed(.dailyLimit) }
        inFlight = true
        defer { inFlight = false }
        let started = clock.now()
        let today = LabelPhotoSpendPolicy.dayKey(started, calendar: calendar)
        switch LabelPhotoSpendPolicy.admission(today: today, stored: ledger.load()) {
        case .allowed: break
        case .limitReached: return .failed(.dailyLimit)
        case .paused: return .failed(.paused)
        }
        // The key must be present and well formed before anything leaves, the catalogue GETs included.
        guard let key = try? keys.load(), FoodWebKeySyntax.isValid(key) else { return .failed(.keyMissing) }
        if Task.isCancelled { return .failed(.cancelled) }
        // E7 / M3: on the session's first tap, and again on the first tap of a new local day. A
        // failure is kept for the rest of that day in this session.
        guard routeUnavailableOn != today else { return .failed(.routeUnavailable) }
        let check: LabelPhotoManifest.CatalogueCheck
        if let cached = catalogue, cached.day == today {
            check = cached.check
        } else {
            let fresh: LabelPhotoManifest.CatalogueCheck
            do {
                fresh = try await checker.check(route)
            } catch let LabelPhotoRouteCheckFailure.transport(failure) {
                // Not the route's fault: said as offline or a connection failure, and not kept.
                return .failed(Task.isCancelled ? .cancelled : failure.readingFailure)
            } catch {
                if !Task.isCancelled { routeUnavailableOn = today }
                return .failed(Task.isCancelled ? .cancelled : .routeUnavailable)
            }
            if Task.isCancelled { return .failed(.cancelled) }
            guard Self.prices(fresh, route: route, reasoningBilledSeparately: reasoningBilledSeparately) != nil else {
                routeUnavailableOn = today
                return .failed(.routeUnavailable)
            }
            catalogue = (fresh, today)
            check = fresh
        }
        guard let prices = Self.prices(check, route: route, reasoningBilledSeparately: reasoningBilledSeparately) else {
            return .failed(.routeUnavailable)
        }
        // Reserve the tap before the first send (E10, #326 review), with the admission, in one
        // atomic update of the ledger as it is now: a kill mid-attempt leaves it counted, another
        // session's taps are never overwritten, and an unreadable ledger is never written.
        // The reservation is tagged with this tap's ID, and settled on the day it was written.
        let tap = tapIDs()
        let reservedOn: String
        do {
            reservedOn = try ledger.update { stored in
                switch LabelPhotoSpendPolicy.admission(today: today, stored: stored) {
                case .allowed: break
                case .limitReached: throw Refusal.limitReached
                case .paused: throw Refusal.paused
                }
                guard case let .day(day) = stored else { return LabelPhotoSpendPolicy.reservation(today: today, stored: nil, tap: tap) }
                return LabelPhotoSpendPolicy.reservation(today: today, stored: day, tap: tap)
            }.day
        } catch Refusal.paused {
            return .failed(.paused)
        } catch Refusal.limitReached {
            return .failed(.dailyLimit)
        } catch {
            ledgerFailed = true
            return .failed(.dailyLimit)
        }
        var attempts: [LabelPhotoSpendPolicy.Attempt] = []
        var outcome: Outcome = .failed(.failed)
        var number = 0
        let requestedAt = PastedLabelBasisChoice.milliseconds(started)
        loop: while true {
            guard LabelPhotoSpendPolicy.mayStartAttempt(after: attempts, prices: prices) else {
                if attempts.isEmpty { outcome = .failed(.routeUnavailable) }
                break loop
            }
            if Task.isCancelled { outcome = .failed(.cancelled); break loop }
            let timeout = LabelPhotoRetryPolicy.attemptTimeout(elapsed: clock.now().timeIntervalSince(started))
            // No time left in the whole-call deadline: no attempt starts.
            guard timeout > 0 else { outcome = .failed(.timedOut); break loop }
            number += 1
            progress?(number)
            let result = await attempter.attempt(image, timeout: timeout)
            switch result {
            case let .notSent(failure):
                number -= 1
                outcome = .failed(Task.isCancelled ? .cancelled : failure)
                break loop
            case let .answered(wireText, model, provider, generationID, finishReason, usage):
                attempts.append(.init(reportedCost: usage.costUSD == LabelPhotoManifest.Usage.unknownCost ? nil : Decimal(string: usage.costUSD),
                                      promptTokens: usage.promptTokens))
                if Task.isCancelled { outcome = .failed(.cancelled); break loop }
                let reply = LabelPhotoWireReply(wireText: wireText, model: model, provider: provider, generationID: generationID,
                                                finishReason: finishReason, attempts: number, usage: usage, requestedAt: requestedAt,
                                                completedAt: PastedLabelBasisChoice.milliseconds(clock.now()))
                outcome = .answered(reply, request: attempter.manifestRequest(catalogue: check))
                break loop
            case let .failed(retryOutcome, failure, reportedCost, promptTokens):
                // Every attempt that sent bytes counts, a cancelled one included (17.5 M4).
                attempts.append(.init(reportedCost: reportedCost, promptTokens: promptTokens))
                outcome = .failed(Task.isCancelled ? .cancelled : failure)
                if Task.isCancelled { break loop }
                let now = clock.now()
                switch LabelPhotoRetryPolicy.next(afterAttempt: number, outcome: retryOutcome, elapsed: now.timeIntervalSince(started),
                                                  now: now, jitter: jitter()) {
                case .stop: break loop
                case let .retry(after, _):
                    do { try await sleeper.sleep(seconds: after) } catch { outcome = .failed(.cancelled); break loop }
                }
            }
        }
        // Reconcile the reservation to the tap's cost (up or down), or release it if nothing was
        // sent, as a delta on the ledger as it is now. A failed write is retried once; if it still
        // fails, or the ledger has become unreadable, the reservation stays and the route closes
        // for the session.
        // Idempotent: only a tap still open on its reservation's day is settled, so a retry after a
        // write that was stored but reported as failed changes nothing.
        let settle: (LabelPhotoSpendPolicy.Stored) throws -> LabelPhotoSpendPolicy.Day = { stored in
            guard case let .day(day) = stored else { throw Refusal.unreadable }
            let settled = attempts.isEmpty ? LabelPhotoSpendPolicy.released(day, reservedOn: reservedOn, tap: tap)
                : LabelPhotoSpendPolicy.reconciled(day, reservedOn: reservedOn, tap: tap, attempts: attempts, prices: prices)
            return settled ?? day
        }
        do { try ledger.update(settle) } catch Refusal.unreadable {
            ledgerFailed = true
        } catch {
            do { try ledger.update(settle) } catch { ledgerFailed = true }
        }
        return outcome
    }

    enum Refusal: Error { case limitReached, paused, unreadable }
}
