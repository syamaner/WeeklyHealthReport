import Foundation
import FoodLedgerDomain

/// The tag of a reservation's `request_id` in the day record.
public enum ConfirmEnrichmentRequestTag {}

/// One app session's Confirm enrichment requests (docs/confirm-enrichment-openrouter-v1.md CE1.1 to
/// CE1.3 and section 6; phase gate sections 2.5, 2.6 and 6). For each request, in order:
///
/// 0. The preconditions, a state read: the part is available, OpenRouter and enrichment are on, the
///    key is valid in this session and the app is active. Otherwise nothing, cached or not.
/// 1. The cache, unless `Ask again`: a hit whose bytes still pass the checks sends and counts nothing.
///    A Confirm opened by re-log or quick add stops here (cache only).
/// 2. The ledger's admission (an unreadable record closes the day, written at once).
/// 3. The gate for the part's use.
/// 4. The route check when due (first request of the session and of each local day, and after a check
///    that could not connect), asking the gate for the catalogue use first.
/// 5. The reservation, at the whole per-request cap.
/// 6. Attempts within the whole-request cap, the 60 s deadline and 30 s per attempt, with backoff.
/// 7. The reconcile or release, retried once; then the part closes for the app session.
///
/// A cancelled or late answer is discarded and never cached. It never validates a key and never runs
/// in the background.
public actor ConfirmEnrichmentSession {
    public struct Routes: Sendable {
        public let details: ConfirmEnrichmentRoute
        public let nutrients: ConfirmEnrichmentRoute
        public init(details: ConfirmEnrichmentRoute, nutrients: ConfirmEnrichmentRoute) {
            self.details = details; self.nutrients = nutrients
        }
        public func route(_ part: ConfirmEnrichmentPart) -> ConfirmEnrichmentRoute {
            part == .details ? details : nutrients
        }
    }

    /// The switch and key states the view model reads (gate section 6, preconditions).
    public struct Preconditions: Equatable, Sendable {
        public let openRouterOn: Bool
        public let enrichmentOn: Bool
        public let keyState: OpenRouterKeyState
        public init(openRouterOn: Bool, enrichmentOn: Bool, keyState: OpenRouterKeyState) {
            self.openRouterOn = openRouterOn; self.enrichmentOn = enrichmentOn; self.keyState = keyState
        }
        var hold: Bool { openRouterOn && enrichmentOn && keyState == .valid }
    }

    /// Automatic on Confirm, a tap of `Ask again` (skips the cache), or a Confirm opened by re-log or
    /// quick add (the cache only, never a send).
    public enum Mode: Equatable, Sendable { case automatic, askAgain, cacheOnly }

    /// Why a request ended with nothing to show, mapped to CE1 section 6's one note.
    public enum Failure: Equatable, Sendable {
        /// No note: a precondition, the deny gate, the cache-only mode or an answer that kept nothing.
        case silent
        /// `Suggestions are not available right now.`
        case notAvailable
        /// `Today's limit for suggestions is reached.`
        case limitReached
        /// The gate refused before anything was sent: nothing on automatic Confirm, O1's blocked row on
        /// the Ask again row.
        case notPermitted
        /// The gate refused a retry after an earlier attempt was sent.
        case notPermittedAfterSending
        case cancelled
    }

    public enum DetailsOutcome: Equatable, Sendable {
        case answered(ConfirmDetailsSuggestion)
        case failed(Failure)
    }

    public enum NutrientOutcome: Equatable, Sendable {
        case answered(ConfirmNutrientSuggestion)
        case failed(Failure)
    }

    public static let debounceSeconds: TimeInterval = 1.5

    let availability: ConfirmEnrichmentAvailability
    let routes: Routes
    let detailsAdapter: any FoodDetailsSuggesting
    let nutrientAdapter: any NutrientEstimateSuggesting
    let checker: any ConfirmEnrichmentRouteChecking
    let cache: any ConfirmEnrichmentCaching
    let ledger: any ConfirmEnrichmentSpendLedger
    let egress: any OpenRouterEgressPermitting
    let delaying: any ConfirmEnrichmentDelaying
    let timing: any ConfirmEnrichmentElapsedTiming
    let jitter: any ConfirmEnrichmentJittering
    let clock: any LedgerClock
    let timeZone: TimeZone
    let ids: any LedgerIDGenerating
    let encoder: any CanonicalEncoding
    let digester: any Digesting

    private var active = true
    /// The day each part's route check passed on, with its prices.
    private var checked: [ConfirmEnrichmentPart: (day: String, prices: ConfirmEnrichmentPrices)] = [:]
    /// The day each part was found unavailable on (a failed check or a day whose prices exceed the cap).
    private var unavailableOn: [ConfirmEnrichmentPart: String] = [:]
    /// Parts whose settlement write failed twice: closed for this app session.
    private var closed: Set<ConfirmEnrichmentPart> = []

    public init(availability: ConfirmEnrichmentAvailability, routes: Routes, details: any FoodDetailsSuggesting,
                nutrients: any NutrientEstimateSuggesting, checker: any ConfirmEnrichmentRouteChecking, cache: any ConfirmEnrichmentCaching,
                ledger: any ConfirmEnrichmentSpendLedger, egress: any OpenRouterEgressPermitting, delaying: any ConfirmEnrichmentDelaying,
                timing: any ConfirmEnrichmentElapsedTiming, jitter: any ConfirmEnrichmentJittering, clock: any LedgerClock,
                timeZone: TimeZone, ids: any LedgerIDGenerating, encoder: any CanonicalEncoding = FoundationCanonicalJSONEncoder(),
                digester: any Digesting) {
        self.availability = availability; self.routes = routes; detailsAdapter = details; nutrientAdapter = nutrients
        self.checker = checker; self.cache = cache; self.ledger = ledger; self.egress = egress; self.delaying = delaying
        self.timing = timing; self.jitter = jitter; self.clock = clock; self.timeZone = timeZone; self.ids = ids
        self.encoder = encoder; self.digester = digester
    }

    public nonisolated var routeValues: Routes { routes }

    // MARK: Lifecycle

    /// The scene left the foreground: nothing more is sent until it returns (CE1.1 rule 2).
    public func appBecameInactive() { active = false }
    public func appBecameActive() { active = true }
    public var isActive: Bool { active }

    /// The 1.5 s debounce. False when cancelled or when the app left the foreground.
    public func debounce() async -> Bool {
        do { try await delaying.wait(seconds: Self.debounceSeconds) } catch { return false }
        return active && !Task.isCancelled
    }

    /// Whether anything may happen for `part` at all: availability and the preconditions.
    public nonisolated func mayRun(_ part: ConfirmEnrichmentPart, preconditions: Preconditions) -> Bool {
        availability.isAvailable(part) && preconditions.hold
    }

    // MARK: Requests

    public func details(_ request: ConfirmEnrichmentPolicy.DetailsRequest, mode: Mode, preconditions: Preconditions,
                        locale: LedgerText, entryState: PersonalFoodDatabaseState? = nil) async -> DetailsOutcome {
        let route = routes.details
        let check: @Sendable (Data) -> ConfirmDetailsResponseCheck.Parsed? = { bytes in
            guard case let .success(parsed) = ConfirmDetailsResponseCheck.check(bytes, request: request.inputs,
                                                                                models: route.acceptedModels, provider: route.provider) else { return nil }
            return parsed
        }
        switch await perform(.details, body: request.body, subject: request.subjectSHA256, mode: mode, preconditions: preconditions,
                             valid: { check($0) != nil }) {
        case let .failed(failure): return .failed(failure)
        case let .answer(bytes, receivedAt, model, fromCache):
            guard let parsed = check(bytes) else { return .failed(.notAvailable) }
            // CE1.4: a raw or cooked preparation that disagrees with a Your food database entry's state
            // under I1.1's agreement rule is not pre-filled.
            let applied = ConfirmDetailsResponseCheck.applied(parsed.answers).filter { fact in
                guard fact == ConfirmDetailsFact.preparation.rawValue, let entryState,
                      let choice = parsed.answers.first(where: { $0.fact == fact })?.choice,
                      let preparation = PersonalFoodDatabaseIdentityFacts.Preparation(rawValue: choice) else { return true }
                return PersonalFoodDatabaseIdentityFacts.preparationAgrees(preparation, state: entryState)
            }
            do {
                let capture = try ConfirmEnrichmentCaptureBuilder.details(
                    request: request, route: route, response: bytes, parsed: parsed, applied: applied, model: model,
                    receivedAt: receivedAt, locale: locale, id: ids.makeID(EvidenceTag.self), encoder: encoder, digester: digester)
                var facts: [ConfirmDetailsFact: String] = [:]
                for fact in applied {
                    if let typed = ConfirmDetailsFact(rawValue: fact), let choice = parsed.answers.first(where: { $0.fact == fact })?.choice {
                        facts[typed] = choice
                    }
                }
                return .answered(ConfirmDetailsSuggestion(subjectSHA256: request.subjectSHA256, capture: capture, applied: facts,
                                                          model: model, receivedAt: capture.capturedAt, fromCache: fromCache))
            } catch {
                return .failed(.notAvailable)
            }
        }
    }

    public func nutrients(_ request: ConfirmEnrichmentPolicy.NutrientRequest, mode: Mode, preconditions: Preconditions,
                          locale: LedgerText) async -> NutrientOutcome {
        let route = routes.nutrients
        let check: @Sendable (Data) -> ConfirmNutrientResponseCheck.Parsed? = { bytes in
            guard case let .success(parsed) = ConfirmNutrientResponseCheck.check(bytes, request: request.inputs,
                                                                                 models: route.acceptedModels, provider: route.provider) else { return nil }
            return parsed
        }
        switch await perform(.nutrients, body: request.body, subject: request.subjectSHA256, mode: mode, preconditions: preconditions,
                             valid: { check($0) != nil }) {
        case let .failed(failure): return .failed(failure)
        case let .answer(bytes, receivedAt, model, fromCache):
            guard let parsed = check(bytes) else { return .failed(.notAvailable) }
            let rows = ConfirmNutrientResponseCheck.captureRows(parsed, request: request.inputs)
            do {
                let capture = try ConfirmEnrichmentCaptureBuilder.nutrients(
                    request: request, route: route, response: bytes, rows: rows, generationID: parsed.usage.generationID, model: model,
                    receivedAt: receivedAt, locale: locale, id: ids.makeID(EvidenceTag.self), encoder: encoder, digester: digester)
                return .answered(ConfirmNutrientSuggestion(subjectSHA256: request.subjectSHA256, capture: capture, inputs: request.inputs,
                                                           rows: rows, model: model, receivedAt: capture.capturedAt, fromCache: fromCache))
            } catch {
                return .failed(.notAvailable)
            }
        }
    }

    // MARK: The request loop

    enum Raw: Equatable, Sendable {
        case answer(Data, receivedAt: Date, model: String, fromCache: Bool)
        case failed(Failure)
    }

    enum Refusal: Error { case refused }

    private func today() -> String { ConfirmEnrichmentSpendPolicy.dayKey(clock.now(), timeZone: timeZone) }

    private func stopped() -> Bool { Task.isCancelled || !active }

    func perform(_ part: ConfirmEnrichmentPart, body: Data, subject: String, mode: Mode, preconditions: Preconditions,
                 valid: @Sendable (Data) -> Bool) async -> Raw {
        guard mayRun(part, preconditions: preconditions), active else { return .failed(.silent) }
        let route = routes.route(part)
        // 1. The cache.
        if mode != .askAgain, let hit = cache.answer(subject: subject, part: part, now: clock.now()) {
            if (try? digester.sha256(hit.response))?.value == hit.responseSHA256, valid(hit.response) {
                return .answer(hit.response, receivedAt: hit.receivedAt, model: hit.model, fromCache: true)
            }
            cache.remove(subject: subject, part: part)
        }
        guard mode != .cacheOnly else { return .failed(.silent) }
        guard !closed.contains(part) else { return .failed(.limitReached) }
        let today = today()
        // 2. The ledger's admission. An unreadable record closes the day, written at once.
        let stored = ledger.read()
        if case .unreadable = stored {
            _ = try? ledger.update { ConfirmEnrichmentSpendPolicy.current(today: today, stored: $0) }
            return .failed(.limitReached)
        }
        switch ConfirmEnrichmentSpendPolicy.admission(part, day: ConfirmEnrichmentSpendPolicy.current(today: today, stored: stored)) {
        case .allowed: break
        case .limitReached, .paused: return .failed(.limitReached)
        }
        // 3. The gate for the request use.
        guard egress.permits(part.use) else { return .failed(.notPermitted) }
        // 4. The route check, when due.
        guard unavailableOn[part] != today else { return .failed(.notAvailable) }
        let prices: ConfirmEnrichmentPrices
        if let passed = checked[part], passed.day == today {
            prices = passed.prices
        } else {
            guard egress.permits(part.catalogueUse) else { return .failed(.notPermitted) }
            switch await checker.check(part, catalogueUse: part.catalogueUse) {
            case let .passed(dayPrices):
                guard ConfirmEnrichmentSpendPolicy.routeFits(route, prices: dayPrices) else {
                    unavailableOn[part] = today
                    return .failed(.notAvailable)
                }
                checked[part] = (today, dayPrices)
                prices = dayPrices
            case .connectionFailed: return .failed(stopped() ? .cancelled : .notAvailable)
            case .notPermitted: return .failed(stopped() ? .cancelled : .notPermitted)
            case .unavailable:
                unavailableOn[part] = today
                return .failed(.notAvailable)
            }
        }
        if stopped() { return .failed(.cancelled) }
        let w = ConfirmEnrichmentSpendPolicy.worstCase(route, prices: prices)
        // 5. The reservation at the whole cap, in one atomic update.
        guard let requestID = try? ids.makeID(ConfirmEnrichmentRequestTag.self).rawValue else { return .failed(.notAvailable) }
        let reservedOn: String
        do {
            reservedOn = try ledger.update { stored in
                let day = ConfirmEnrichmentSpendPolicy.current(today: today, stored: stored)
                guard let reserved = ConfirmEnrichmentSpendPolicy.reserved(part, requestID: requestID, day: day) else { throw Refusal.refused }
                return reserved
            }.localDay
        } catch {
            return .failed(.limitReached)
        }
        // 6. Attempts.
        var attempts: [ConfirmEnrichmentSpendPolicy.Attempt] = []
        var outcome: Raw = .failed(.notAvailable)
        let started = timing.now()
        func elapsed() -> TimeInterval {
            let duration = timing.now() - started
            return Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
        }
        loop: while true {
            guard ConfirmEnrichmentSpendPolicy.mayStartAttempt(attempts, w: w, part: part) else { break loop }
            if stopped() { outcome = .failed(.cancelled); break loop }
            let timeout = ConfirmEnrichmentRetryPolicy.attemptTimeout(elapsed: elapsed())
            guard timeout > 0 else { break loop }
            let result = part == .details ? await detailsAdapter.attempt(body, timeout: timeout)
                : await nutrientAdapter.attempt(body, timeout: timeout)
            let retryOutcome: ConfirmEnrichmentRetryPolicy.Outcome
            switch result {
            case let .notSent(reason):
                switch reason {
                case .notPermitted: outcome = .failed(attempts.isEmpty ? .notPermitted : .notPermittedAfterSending)
                case .cancelled: outcome = .failed(.cancelled)
                case .noKey: outcome = .failed(.silent)
                }
                break loop
            case let .transportFailed(failure):
                attempts.append(.init(reportedMicroUSD: nil, promptTokens: nil))
                markSent(requestID)
                if failure == .cancelled || stopped() { outcome = .failed(.cancelled); break loop }
                outcome = .failed(.notAvailable)
                switch failure {
                case .timedOut: retryOutcome = .timedOut
                case .tooLarge: retryOutcome = .contentFailure
                case .offline, .connectionFailed, .cancelled: retryOutcome = .transportError
                }
            case let .sent(status, bytes, retryAfter):
                let usage = (try? JSONSerialization.jsonObject(with: bytes) as? [String: Any]).map(ConfirmEnrichmentUsageParse.usage)
                attempts.append(.init(reportedMicroUSD: usage?.cost.map(ConfirmEnrichmentSpendPolicy.microUSD), promptTokens: usage?.promptTokens))
                markSent(requestID)
                // A late answer is discarded and never cached (CE1.1 rule 4).
                if stopped() { outcome = .failed(.cancelled); break loop }
                if status == 200, !ConfirmEnrichmentRetryPolicy.isOverloadedEnvelope(bytes) {
                    guard valid(bytes),
                          let model = (try? JSONSerialization.jsonObject(with: bytes) as? [String: Any])?["model"] as? String else {
                        outcome = .failed(.notAvailable)
                        break loop
                    }
                    let receivedAt = ConfirmEnrichmentTime.truncated(clock.now())
                    outcome = .answer(bytes, receivedAt: receivedAt, model: model, fromCache: false)
                    cache.store(ConfirmEnrichmentCachedAnswer(
                        subjectSHA256: subject, part: part, response: bytes,
                        responseSHA256: (try? digester.sha256(bytes).value) ?? "", model: model, provider: route.provider,
                        costMicroUSD: attempts.last?.reportedMicroUSD, receivedAt: receivedAt), now: clock.now())
                    break loop
                }
                outcome = .failed(.notAvailable)
                retryOutcome = status == 200 ? .providerOverloaded(retryAfter: retryAfter) : .httpStatus(status, retryAfter: retryAfter)
            }
            switch ConfirmEnrichmentRetryPolicy.next(afterAttempt: attempts.count, outcome: retryOutcome, elapsed: elapsed(),
                                                     now: clock.now(), jitter: jitter.fraction()) {
            case .stop: break loop
            case let .retry(after):
                do { try await delaying.wait(seconds: after) } catch { outcome = .failed(.cancelled); break loop }
            }
        }
        // 7. Settle: reconcile what was sent, or release a reservation that sent nothing.
        let sentAttempts = attempts
        let settle: (ConfirmEnrichmentSpendPolicy.Stored) throws -> ConfirmEnrichmentSpendPolicy.Day = { stored in
            guard case let .day(day) = stored else { throw Refusal.refused }
            guard day.localDay == reservedOn else { return day }
            let settled = sentAttempts.isEmpty ? ConfirmEnrichmentSpendPolicy.released(requestID, day: day)
                : ConfirmEnrichmentSpendPolicy.reconciled(requestID, attempts: sentAttempts, w: w, route: route, day: day)
            return settled ?? day
        }
        do { try ledger.update(settle) } catch {
            do { try ledger.update(settle) } catch { closed.insert(part) }
        }
        return outcome
    }

    private func markSent(_ requestID: String) {
        _ = try? ledger.update { stored in
            guard case let .day(day) = stored else { throw Refusal.refused }
            return ConfirmEnrichmentSpendPolicy.attemptSent(requestID, day: day)
        }
    }
}

/// One Confirm's request record (CE1.1 rule 3): A once per subject; B for its first subject and once
/// more for a second subject after details change; a third subject only on a tap of `Ask again`, which
/// is offered once a subject of that part has been asked.
public struct ConfirmEnrichmentConfirmTracker: Equatable, Sendable {
    public private(set) var asked: [ConfirmEnrichmentPart: [String]] = [:]

    public init() {}

    public func mayAskAutomatically(_ part: ConfirmEnrichmentPart, subject: String) -> Bool {
        let subjects = asked[part] ?? []
        guard !subjects.contains(subject) else { return false }
        return subjects.count < (part == .nutrients ? 2 : 1)
    }

    public mutating func recordAsked(_ part: ConfirmEnrichmentPart, subject: String) {
        if !(asked[part] ?? []).contains(subject) { asked[part, default: []].append(subject) }
    }

    public func offersAskAgain(_ part: ConfirmEnrichmentPart) -> Bool { !(asked[part] ?? []).isEmpty }
}
