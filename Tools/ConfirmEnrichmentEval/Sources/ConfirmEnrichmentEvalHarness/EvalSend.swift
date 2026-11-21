import ConfirmEnrichmentEvalCore
import FoodConfirmEnrichment
import FoodLedgerApplication
import FoodLedgerDomain
import Foundation

/// `send` (docs/confirm-enrichment-openrouter-v1-phase.md section 9, CE-T15): for each case, the app's
/// own request through the app's own adapter, under the tool-local gate. The tool runs its own loop over
/// the pure `ConfirmEnrichmentRetryPolicy` and the CE-T15 ledger, not `ConfirmEnrichmentSession`, so the
/// app's daily caps do not apply and the retry behaviour the latency bar measures is the app's:
///
/// 1. The route check once per run, through the app's `ConfirmEnrichmentRouteChecker`; W from its prices.
/// 2. Before every call, a reservation of W in the CE-T15 ledger ($0.05 per call, $5 for the programme).
/// 3. The call; its reported cost settles the reservation (unreported: charged at W).
/// 4. At most 3 attempts, with backoff that honours `Retry-After`.
/// 5. The first request stop (section 9): the run's first case that sends must return the checked
///    shape, and its reported prompt tokens must be within the route's ceiling; otherwise the run stops
///    for the owner. Whether the body (with `max_tokens` where the route sends it) was accepted is
///    recorded in the private folder only.
///
/// Raw responses are written under the private folder only. The returned lines name cases by hash and
/// hold closed codes and counts only (G11).
public struct EvalSender: Sendable {
    public let part: ConfirmEnrichmentPart
    let transport: any ConfirmEnrichmentHTTPTransporting
    let keys: any FoodWebKeyStoring
    let ledger: EvalSpendLedger
    let privateFolder: URL
    let candidates: EvalCandidates
    let routes: ConfirmEnrichmentSession.Routes
    let wait: @Sendable (TimeInterval) async -> Void
    let now: @Sendable () -> Date

    public init(part: ConfirmEnrichmentPart, transport: any ConfirmEnrichmentHTTPTransporting, keys: any FoodWebKeyStoring,
                ledger: EvalSpendLedger, privateFolder: URL, candidates: EvalCandidates = EvalCandidates(),
                routes: ConfirmEnrichmentSession.Routes = ConfirmEnrichmentRoutes.all,
                wait: @escaping @Sendable (TimeInterval) async -> Void = { try? await Task.sleep(nanoseconds: UInt64(max(0, $0) * 1e9)) },
                now: @escaping @Sendable () -> Date = { Date() }) {
        self.part = part; self.transport = transport; self.keys = keys; self.ledger = ledger; self.privateFolder = privateFolder
        self.candidates = candidates; self.routes = routes; self.wait = wait; self.now = now
    }

    struct Built {
        let body: Data
        let check: @Sendable (Data) -> Bool
    }

    func build(_ evalCase: EvalCase) throws -> Built? {
        let state = try candidates.state(for: evalCase, privateFolder: privateFolder)
        let route = routes.route(part)
        switch part {
        case .details:
            guard let request = try EvalRequests.details(state, route: route) else { return nil }
            return Built(body: request.body) { bytes in
                if case .success = ConfirmDetailsResponseCheck.check(bytes, request: request.inputs, models: route.acceptedModels,
                                                                     provider: route.provider) { return true }
                return false
            }
        case .nutrients:
            guard let request = try EvalRequests.nutrients(state, route: route) else { return nil }
            return Built(body: request.body) { bytes in
                if case .success = ConfirmNutrientResponseCheck.check(bytes, request: request.inputs, models: route.acceptedModels,
                                                                      provider: route.provider) { return true }
                return false
            }
        }
    }

    func attempt(_ body: Data, timeout: TimeInterval) async -> ConfirmEnrichmentAttemptResult {
        switch part {
        case .details:
            await OpenRouterJevFoodDetailsAdapter(egress: EvalGate(), transport: transport, keys: keys, route: routes.details)
                .attempt(body, timeout: timeout)
        case .nutrients:
            await OpenRouterNutrientEstimateAdapter(egress: EvalGate(), transport: transport, keys: keys, route: routes.nutrients)
                .attempt(body, timeout: timeout)
        }
    }

    /// The reported cost of a reply in whole micro-dollars, rounded up; nil when it reports none.
    static func reportedCost(_ body: Data) -> Int? {
        guard let root = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              let cost = ((root["usage"] as? [String: Any])?["cost"] as? NSNumber),
              CFGetTypeID(cost) != CFBooleanGetTypeID(), let decimal = Decimal(string: cost.stringValue) else { return nil }
        return ConfirmEnrichmentSpendPolicy.microUSD(decimal)
    }

    func save(_ bytes: Data, hash: String, attempt: Int) {
        let folder = privateFolder.appendingPathComponent("responses", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? bytes.write(to: folder.appendingPathComponent("\(hash)-\(part.rawValue)-\(attempt).json"), options: .atomic)
    }

    /// The reported prompt tokens of a reply; nil when it reports none.
    static func promptTokens(_ body: Data) -> Int? {
        guard let root = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              let tokens = (root["usage"] as? [String: Any])?["prompt_tokens"] as? NSNumber,
              CFGetTypeID(tokens) != CFBooleanGetTypeID() else { return nil }
        return tokens.intValue
    }

    /// The first request's record, private folder only: part, whether `max_tokens` was sent and
    /// whether the body was accepted, and the reported prompt tokens. Never a body or a response.
    func saveFirstRequest(accepted: Bool, promptTokens: Int?) {
        let route = routes.route(part)
        let record: [String: Any] = ["part": part.rawValue, "route": route.version, "max_tokens_sent": route.sendsMaxTokens,
                                     "accepted": accepted, "prompt_tokens": promptTokens.map { $0 as Any } ?? NSNull(),
                                     "prompt_ceiling": route.promptCeilingTokens]
        try? FileManager.default.createDirectory(at: privateFolder, withIntermediateDirectories: true)
        if let data = try? JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]) {
            try? data.write(to: privateFolder.appendingPathComponent("first-request-\(part.rawValue).json"), options: .atomic)
        }
    }

    /// Runs every case and returns the console lines. Stops at the first ledger refusal.
    public func run(_ list: EvalCaseList) async -> [String] {
        var lines: [String] = []
        var counts: [EvalConsole.Outcome: Int] = [:]
        func record(_ hash: String, _ outcome: EvalConsole.Outcome, _ attempts: Int) {
            counts[outcome, default: 0] += 1
            lines.append(EvalConsole.caseLine(hash: hash, part: part.rawValue, outcome: outcome, attempts: attempts))
        }
        let route = routes.route(part)
        let w: Int
        switch await ConfirmEnrichmentRouteChecker(egress: EvalGate(), transport: transport, routes: routes)
            .check(part, catalogueUse: part.catalogueUse) {
        case let .passed(prices):
            w = ConfirmEnrichmentSpendPolicy.worstCase(route, prices: prices)
            if !ConfirmEnrichmentSpendPolicy.routeFits(route, prices: prices) {
                // A W above the part's app cap is a stop for the owner (section 9): the part could never run in the app.
                lines.append(EvalConsole.stopLine("worst_case_above_app_cap"))
                return lines
            }
        case .connectionFailed: return lines + [EvalConsole.stopLine("route_check_connection_failed")]
        case .notPermitted: return lines + [EvalConsole.stopLine("route_check_not_permitted")]
        case .unavailable: return lines + [EvalConsole.stopLine("route_unavailable")]
        }
        var firstRequestChecked = false
        caseLoop: for evalCase in list.cases {
            guard let hash = try? EvalHashes.hash(evalCase) else { continue }
            let built: Built
            do {
                guard let made = try build(evalCase) else { record(hash, .notEligible, 0); continue }
                built = made
            } catch is ConfirmEnrichmentPolicy.BuildFailure {
                record(hash, .buildRefused, 0); continue
            } catch {
                record(hash, .caseUnreadable, 0); continue
            }
            let started = now()
            var attempts = 0
            var charged: [ConfirmEnrichmentSpendPolicy.Attempt] = []
            var outcome: EvalConsole.Outcome = .transportFailed
            var lastBody: Data?
            attemptLoop: while attempts < ConfirmEnrichmentRetryPolicy.maxAttempts {
                // As the app's session: an attempt starts only within the whole-request cap and while the
                // 60 s deadline leaves time for it.
                guard ConfirmEnrichmentSpendPolicy.mayStartAttempt(charged, w: w, part: part) else { break attemptLoop }
                let timeout = ConfirmEnrichmentRetryPolicy.attemptTimeout(elapsed: now().timeIntervalSince(started))
                guard timeout > 0 else { break attemptLoop }
                let reservation: String
                do {
                    reservation = try ledger.reserve(part: part.rawValue, caseHash: hash, worstCaseMicroUSD: w)
                } catch let refusal as EvalSpendLedger.Refusal {
                    record(hash, .refusedByLedger, attempts)
                    lines.append(EvalConsole.stopLine(refusal.description))
                    break caseLoop
                } catch {
                    record(hash, .refusedByLedger, attempts)
                    lines.append(EvalConsole.stopLine("ledger_unwritable"))
                    break caseLoop
                }
                let result = await attempt(built.body, timeout: timeout)
                let retry: ConfirmEnrichmentRetryPolicy.Outcome
                switch result {
                case .notSent:
                    _ = try? ledger.release(reservation)
                    outcome = .notSent
                    break attemptLoop
                case let .transportFailed(failure):
                    attempts += 1
                    charged.append(.init(reportedMicroUSD: nil, promptTokens: nil))
                    guard (try? ledger.settle(reservation, reportedMicroUSD: nil)) != nil else {
                        record(hash, .refusedByLedger, attempts)
                        lines.append(EvalConsole.stopLine("ledger_unwritable"))
                        break caseLoop
                    }
                    outcome = .transportFailed
                    // As the app: a cancelled attempt ends the request.
                    if failure == .cancelled { break attemptLoop }
                    retry = failure == .timedOut ? .timedOut : failure == .tooLarge ? .contentFailure : .transportError
                case let .sent(status, body, retryAfter):
                    attempts += 1
                    charged.append(.init(reportedMicroUSD: Self.reportedCost(body), promptTokens: Self.promptTokens(body)))
                    guard (try? ledger.settle(reservation, reportedMicroUSD: Self.reportedCost(body))) != nil else {
                        record(hash, .refusedByLedger, attempts)
                        lines.append(EvalConsole.stopLine("ledger_unwritable"))
                        break caseLoop
                    }
                    save(body, hash: hash, attempt: attempts)
                    lastBody = body
                    if status == 200, !ConfirmEnrichmentRetryPolicy.isOverloadedEnvelope(body) {
                        outcome = built.check(body) ? .answered : .failedChecks
                        break attemptLoop
                    }
                    outcome = .failedChecks
                    retry = status == 200 ? .providerOverloaded(retryAfter: retryAfter) : .httpStatus(status, retryAfter: retryAfter)
                }
                switch ConfirmEnrichmentRetryPolicy.next(afterAttempt: attempts, outcome: retry, elapsed: now().timeIntervalSince(started),
                                                         now: now(), jitter: Double.random(in: 0...1)) {
                case .stop: break attemptLoop
                case let .retry(after): await wait(after)
                }
            }
            record(hash, outcome, attempts)
            // Section 9: the first case that sent decides whether the run may go on.
            if attempts > 0, !firstRequestChecked {
                firstRequestChecked = true
                let tokens = lastBody.flatMap(Self.promptTokens)
                saveFirstRequest(accepted: outcome == .answered, promptTokens: tokens)
                if outcome != .answered {
                    lines.append(EvalConsole.stopLine("first_request_not_accepted"))
                    break caseLoop
                }
                if let tokens, tokens > route.promptCeilingTokens {
                    lines.append(EvalConsole.stopLine("first_request_prompt_over_ceiling"))
                    break caseLoop
                }
            }
        }
        lines.append(EvalConsole.summaryLine(part: part.rawValue, counts: counts))
        return lines
    }
}
