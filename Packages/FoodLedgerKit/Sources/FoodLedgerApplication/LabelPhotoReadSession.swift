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
    let clock: any LedgerClock
    let calendar: Calendar
    let sleeper: any LabelPhotoSleeping
    let jitter: @Sendable () -> Double
    /// Whether the endpoint bills reasoning outside `max_tokens` (L3 confirms it for the route).
    let reasoningBilledSeparately: Bool
    private(set) var catalogue: LabelPhotoManifest.CatalogueCheck?

    public init(route: LabelPhotoRoute.Route = LabelPhotoRoute.v1, checker: any LabelPhotoRouteChecking, attempter: any LabelPhotoAttempting,
                ledger: any LabelPhotoSpendLedger, clock: any LedgerClock, calendar: Calendar, sleeper: any LabelPhotoSleeping,
                jitter: @escaping @Sendable () -> Double, reasoningBilledSeparately: Bool = false) {
        self.route = route; self.checker = checker; self.attempter = attempter; self.ledger = ledger; self.clock = clock
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

    public func read(_ image: PreparedLabelImage) async -> Outcome {
        let started = clock.now()
        let today = LabelPhotoSpendPolicy.dayKey(started, calendar: calendar)
        switch LabelPhotoSpendPolicy.admission(today: today, stored: ledger.load()) {
        case .allowed: break
        case .limitReached: return .failed(.dailyLimit)
        case .paused: return .failed(.paused)
        }
        if Task.isCancelled { return .failed(.cancelled) }
        // E7 / M3: once per session, before the first image request.
        let check: LabelPhotoManifest.CatalogueCheck
        if let cached = catalogue {
            check = cached
        } else {
            guard let fresh = try? await checker.check(route), !Task.isCancelled else {
                return .failed(Task.isCancelled ? .cancelled : .routeUnavailable)
            }
            guard Self.prices(fresh, route: route, reasoningBilledSeparately: reasoningBilledSeparately) != nil else {
                return .failed(.routeUnavailable)
            }
            catalogue = fresh
            check = fresh
        }
        guard let prices = Self.prices(check, route: route, reasoningBilledSeparately: reasoningBilledSeparately) else {
            return .failed(.routeUnavailable)
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
            number += 1
            let elapsed = clock.now().timeIntervalSince(started)
            let result = await attempter.attempt(image, timeout: LabelPhotoRetryPolicy.attemptTimeout(elapsed: elapsed))
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
        if !attempts.isEmpty {
            let stored: LabelPhotoSpendPolicy.Day? = if case let .day(day) = ledger.load() { day } else { nil }
            try? ledger.store(LabelPhotoSpendPolicy.record(attempts, prices: prices, today: today, stored: stored))
        }
        return outcome
    }
}
