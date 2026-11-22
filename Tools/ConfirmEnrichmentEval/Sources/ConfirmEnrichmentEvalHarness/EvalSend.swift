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
    let evidenceFolder: URL
    let fake: Bool
    let candidates: EvalCandidates
    let routes: ConfirmEnrichmentSession.Routes
    let wait: @Sendable (TimeInterval) async -> Void
    let now: @Sendable () -> Date

    public init(part: ConfirmEnrichmentPart, transport: any ConfirmEnrichmentHTTPTransporting, keys: any FoodWebKeyStoring,
                ledger: EvalSpendLedger, privateFolder: URL, evidenceFolder: URL? = nil, fake: Bool = false,
                candidates: EvalCandidates = EvalCandidates(),
                routes: ConfirmEnrichmentSession.Routes = ConfirmEnrichmentRoutes.all,
                wait: @escaping @Sendable (TimeInterval) async -> Void = { try? await Task.sleep(nanoseconds: UInt64(max(0, $0) * 1e9)) },
                now: @escaping @Sendable () -> Date = { Date() }) {
        self.part = part; self.transport = transport; self.keys = keys; self.ledger = ledger; self.privateFolder = privateFolder
        self.evidenceFolder = evidenceFolder ?? privateFolder
        self.fake = fake
        self.candidates = candidates; self.routes = routes; self.wait = wait; self.now = now
    }

    struct Built {
        let hash: String
        let body: Data
        let check: (Data) -> Bool
    }

    func requests(_ list: EvalCaseList, route: ConfirmEnrichmentRoute) throws -> [Built] {
        let plan = EvalPlan(candidates: candidates, folder: privateFolder)
        switch part {
        case .details:
            return try plan.details(list, route: route).compactMap { item in
                guard let request = item.request else { return nil }
                return Built(hash: item.hash, body: request.body) { bytes in
                    let checked = ConfirmDetailsResponseCheck.check(bytes, request: request.inputs,
                                                                    models: route.acceptedModels, provider: route.provider)
                    if case .success = checked { return true }
                    return false
                }
            }
        case .nutrients:
            return try plan.nutrients(list, route: route).map { item in
                let request = item.request
                return Built(hash: item.hash, body: request.body) { bytes in
                    let checked = ConfirmNutrientResponseCheck.check(bytes, request: request.inputs,
                                                                     models: route.acceptedModels, provider: route.provider)
                    if case .success = checked { return true }
                    return false
                }
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
    public static func reportedCost(_ body: Data) -> Int? {
        guard let root = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              let cost = ((root["usage"] as? [String: Any])?["cost"] as? NSNumber),
              CFGetTypeID(cost) != CFBooleanGetTypeID(), let decimal = Decimal(string: cost.stringValue) else { return nil }
        // A negative report reaches the ledger as negative, which charges the call at W and stops the run.
        if decimal < 0 { return -1 }
        return ConfirmEnrichmentSpendPolicy.microUSD(decimal)
    }

    /// The most a run of `requests` planned requests can charge while every attempt reports at most W:
    /// per request, at most `maxAttempts` attempts at W, and never more than the whole-request cap, since an
    /// attempt starts only while the charge so far plus W fits the cap. A report above W (which the route's
    /// W should rule out) is not covered and can still stop a claimed run. Nil on overflow.
    public static func sealedWorstCase(requests: Int, w: Int, part: ConfirmEnrichmentPart) -> Int? {
        guard requests >= 0, w >= 0 else { return nil }
        let attempts = w.multipliedReportingOverflow(by: ConfirmEnrichmentRetryPolicy.maxAttempts)
        guard !attempts.overflow else { return nil }
        let perRequest = min(attempts.partialValue, max(w, part.perRequestCapMicroUSD))
        let total = perRequest.multipliedReportingOverflow(by: requests)
        return total.overflow ? nil : total.partialValue
    }

    func save(_ bytes: Data, hash: String, attempt: Int) throws {
        let folder = evidenceFolder.appendingPathComponent("responses", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = EvalRequestEvidence.responseURL(folder: evidenceFolder, hash: hash, part: part, attempt: attempt)
        try bytes.write(to: url, options: .atomic)
    }

    /// The reported prompt tokens of a reply; nil when it reports none.
    static func promptTokens(_ body: Data) -> Int? {
        guard let root = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              let tokens = (root["usage"] as? [String: Any])?["prompt_tokens"] as? NSNumber,
              CFGetTypeID(tokens) != CFBooleanGetTypeID() else { return nil }
        return Int(exactly: tokens.doubleValue)
    }

    /// The first request's record, private folder only: part, whether `max_tokens` was sent and
    /// whether the body was accepted, and the reported prompt tokens. Never a body or a response.
    func saveFirstRequest(accepted: Bool, outcome: String, promptTokens: Int?, requestHash: String) {
        let route = routes.route(part)
        let record: [String: Any] = ["part": part.rawValue, "route": route.version, "max_tokens_sent": route.sendsMaxTokens,
                                     "accepted": accepted, "outcome": outcome, "prompt_tokens": promptTokens.map { $0 as Any } ?? NSNull(),
                                     "prompt_ceiling": route.promptCeilingTokens, "request_sha256": requestHash]
        try? FileManager.default.createDirectory(at: evidenceFolder, withIntermediateDirectories: true)
        // The first request of the folder: kept, never overwritten by a later run.
        let url = evidenceFolder.appendingPathComponent("first-request-\(part.rawValue).json")
        guard !FileManager.default.fileExists(atPath: url.path),
              let data = try? JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]) else { return }
        try? data.write(to: url, options: .withoutOverwriting)
    }

    /// Runs every case and returns the console lines. Stops at the first ledger refusal.
    public func run(_ list: EvalCaseList, firstRequestOnly: Bool = false, sealed: Bool = false) async -> [String] {
        var lines: [String] = []
        var counts: [EvalConsole.Outcome: Int] = [:]
        func record(_ hash: String, _ outcome: EvalConsole.Outcome, _ attempts: Int) {
            counts[outcome, default: 0] += 1
            lines.append(EvalConsole.caseLine(hash: hash, part: part.rawValue, outcome: outcome, attempts: attempts))
        }
        let route = routes.route(part)
        let planned: [Built]
        do {
            planned = try requests(list, route: route)
        } catch {
            return [EvalConsole.stopLine("request_plan_unavailable")]
        }
        guard !planned.isEmpty else { return [EvalConsole.stopLine("first_request_missing")] }
        if sealed && (firstRequestOnly || fake) { return [EvalConsole.stopLine("sealed_run_requires_live_full_send")] }
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
        let runID = UUID()
        var firstRequestChecked = false
        if sealed {
            // A sealed part is sent once and a claim is never given back, so the claim is made only when the
            // programme stop leaves room for every planned request at its worst (`sealedWorstCase`). Nothing
            // is claimed or sent when it does not.
            let need = Self.sealedWorstCase(requests: planned.count, w: w, part: part)
            let headroom: Int
            do {
                headroom = try ledger.headroomMicroUSD()
            } catch let refusal as EvalSpendLedger.Refusal {
                return [EvalConsole.stopLine(refusal.description)]
            } catch {
                return [EvalConsole.stopLine("ledger_unreadable")]
            }
            guard let need, need <= headroom else {
                return [EvalConsole.budgetLine(part: part.rawValue, needMicroUSD: need, headroomMicroUSD: headroom),
                        EvalConsole.stopLine("sealed_budget_insufficient")]
            }
            do {
                try EvalCompletedRun.claimSealed(part: part, folder: evidenceFolder)
            } catch {
                return [EvalConsole.stopLine("sealed_run_already_claimed_or_unwritable")]
            }
        }
        caseLoop: for built in planned {
            let hash = built.hash
            let started = now()
            var attempts = 0
            var charged: [ConfirmEnrichmentSpendPolicy.Attempt] = []
            var outcome: EvalConsole.Outcome = .transportFailed
            var lastBody: Data?
            var elapsedAtLastAttempt: TimeInterval = 0
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
                    elapsedAtLastAttempt = now().timeIntervalSince(started)
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
                    elapsedAtLastAttempt = now().timeIntervalSince(started)
                    attempts += 1
                    charged.append(.init(reportedMicroUSD: Self.reportedCost(body), promptTokens: Self.promptTokens(body)))
                    guard (try? ledger.settle(reservation, reportedMicroUSD: Self.reportedCost(body))) != nil else {
                        record(hash, .refusedByLedger, attempts)
                        lines.append(EvalConsole.stopLine("ledger_unwritable"))
                        break caseLoop
                    }
                    do {
                        try save(body, hash: hash, attempt: attempts)
                    } catch {
                        return lines + [EvalConsole.stopLine("response_unwritable")]
                    }
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
                case let .retry(after):
                    guard ConfirmEnrichmentSpendPolicy.mayStartAttempt(charged, w: w, part: part) else { break attemptLoop }
                    await wait(after)
                }
            }
            guard attempts > 0 else {
                record(hash, outcome, attempts)
                lines.append(EvalConsole.stopLine("planned_request_not_sent"))
                break caseLoop
            }
            do {
                let total = ConfirmEnrichmentSpendPolicy.attemptsCharged(charged, w: w)
                let cost = charged.contains { ($0.reportedMicroUSD ?? w) < 0 } ? nil : total
                let timing = EvalScoring.Timing(costMicroUSD: cost, elapsedSeconds: elapsedAtLastAttempt)
                do {
                    let response = outcome == .answered ? lastBody : nil
                    let evidence = try EvalRequestEvidence(runID: runID, request: built.body, response: response,
                                                           attempt: attempts, timing: timing)
                    try evidence.write(folder: evidenceFolder, hash: hash, part: part)
                } catch {
                    return lines + [EvalConsole.stopLine("request_evidence_unwritable")]
                }
            }
            record(hash, outcome, attempts)
            // Section 9: the first case that sent decides whether the run may go on.
            if attempts > 0, !firstRequestChecked {
                firstRequestChecked = true
                let tokens = lastBody.flatMap(Self.promptTokens)
                guard let requestHash = try? EvalRequestEvidence.hash(built.body) else {
                    return lines + [EvalConsole.stopLine("first_request_hash_failed")]
                }
                saveFirstRequest(accepted: outcome == .answered, outcome: outcome.rawValue,
                                 promptTokens: tokens, requestHash: requestHash)
                // A transport failure never judged the body: its own stop, so it does not read as a refusal.
                if outcome == .transportFailed {
                    lines.append(EvalConsole.stopLine("first_request_transport_failed"))
                    break caseLoop
                }
                if outcome != .answered {
                    lines.append(EvalConsole.stopLine("first_request_not_accepted"))
                    break caseLoop
                }
                guard let tokens else {
                    lines.append(EvalConsole.stopLine("first_request_prompt_unreported"))
                    break caseLoop
                }
                if tokens < 0 || tokens > route.promptCeilingTokens {
                    lines.append(EvalConsole.stopLine("first_request_prompt_over_ceiling"))
                    break caseLoop
                }
                if firstRequestOnly {
                    lines.append(EvalConsole.firstRequestLine(part: part, maxTokensSent: route.sendsMaxTokens, sha256: requestHash))
                    break caseLoop
                }
            }
        }
        if !firstRequestChecked { lines.append(EvalConsole.stopLine("first_request_missing")) }
        if !firstRequestOnly && !lines.contains(where: { $0.hasPrefix("stop ") }) {
            do {
                try EvalCompletedRun.write(runID: runID, list: list, folder: evidenceFolder, part: part, fake: fake)
            } catch {
                lines.append(EvalConsole.stopLine("completion_record_unwritable"))
            }
        }
        lines.append(EvalConsole.summaryLine(part: part.rawValue, counts: counts))
        return lines
    }
}
