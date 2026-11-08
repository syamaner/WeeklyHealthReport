import FoodLabelPhotoCapture
import FoodLedgerApplication
import Foundation
import PastedLabelAITextEvalCore

/// `PastedLabelAITextEval send` (docs/pasted-label-ai-text-v1.md 5.2 items 1 and 3): one label's
/// tap, built with the shipped text request builder, with the spend reservation and the response
/// cache. It runs over one of two connections, chosen explicitly: the directory fake transport
/// (`--fake-transport DIR`, A2), or the shipped live transport through `LiveTransport` with the key
/// from the environment only (`--live`, A3, T1 and T4).
///
/// 0. The pre-send panel detector runs on the text, as in the product (4.7): a detected US,
///    Australian or New Zealand panel is declined before any request is built, and nothing is spent.
/// 1. The request body is built by `OpenRouterPastedLabelAITextRequest` with the chosen prompt
///    version (`prompt-v1` by default, revision 11); its SHA-256 keys the cache, so each version
///    has its own entries.
/// 2. A cached response is returned as it was recorded, with its original cost, and charges nothing.
/// 3. Otherwise the text route checker runs over the same transport, W is priced from the
///    catalogue's prices.
/// 4. Each attempt first reserves a fresh W in the spend ledger (refused past a stop), then sends,
///    then settles that reservation to the reported cost, to unknown (charged at W), or to zero
///    when nothing was sent. A transient failure (a transport failure, HTTP 429 or 5xx) is retried
///    under `SendRetryPolicy` (up to three attempts over the live transport, one over the fake), so
///    no retry ever sends outside its own reservation. The tap's cost, charge, W and latency cover
///    every attempt (5.3). A tap whose final reply is an HTTP 200 passing the envelope is cached.
/// 5. A fresh run (`--fresh-run NAME`, revision 16) measures run-to-run noise: it never reads the
///    default cache entry and keeps its own, keyed by the request SHA-256 and the run name, so the
///    same request body is sent again, under the same reservation, retries and ledger, once per run.
///    A repeat of the same fresh run is a cache hit; the default entry is never read or written.
public enum SendCommand {
    /// A fresh run's name: a lower-case letter, then up to fifteen lower-case letters, digits or
    /// single hyphens, with no trailing hyphen (`r2`, `r3`, `noise-a`). It becomes part of a cache
    /// file name and of a cell's suite, so the grammar is closed.
    public static func isFreshRunName(_ name: String) -> Bool {
        name.range(of: #"\A[a-z](?:[a-z0-9]|-(?=[a-z0-9])){0,15}\z"#, options: .regularExpression) != nil
    }

    public struct Options: Sendable {
        public let labelID: String
        public let textURL: URL
        public let route: PastedLabelAITextRoute.Route
        public let cell: String
        public let ledgerURL: URL
        public let cacheDirectory: URL
        public let connection: Connection
        public let cellStop: Decimal
        public let programmeStop: Decimal
        /// W includes the reasoning limit unless the endpoint is known to count it inside `max_tokens`.
        public let reasoningBilledSeparately: Bool
        /// The per-attempt timeout.
        public let timeout: TimeInterval
        /// The retry rule; by default one attempt over the fake transport and `standard` otherwise.
        public let retry: SendRetryPolicy
        /// The instruction the request builder sends; `prompt-v1` unless chosen (revision 11).
        public let promptVersion: OpenRouterPastedLabelAITextRequest.PromptVersion
        /// The fresh run this tap belongs to (revision 16), nil for the default run.
        public let freshRun: String?

        public init(labelID: String, textURL: URL, route: PastedLabelAITextRoute.Route, cell: String, ledgerURL: URL, cacheDirectory: URL,
                    connection: Connection, cellStop: Decimal = 5, programmeStop: Decimal = 25, reasoningBilledSeparately: Bool = true,
                    timeout: TimeInterval = 60, retry: SendRetryPolicy? = nil,
                    promptVersion: OpenRouterPastedLabelAITextRequest.PromptVersion = OpenRouterPastedLabelAITextRequest.defaultPromptVersion,
                    freshRun: String? = nil) {
            self.promptVersion = promptVersion
            self.freshRun = freshRun
            self.labelID = labelID; self.textURL = textURL; self.route = route; self.cell = cell; self.ledgerURL = ledgerURL
            self.cacheDirectory = cacheDirectory; self.connection = connection; self.cellStop = cellStop
            self.programmeStop = programmeStop; self.reasoningBilledSeparately = reasoningBilledSeparately; self.timeout = timeout
            if let retry { self.retry = retry } else if case .fake = connection { self.retry = .single } else { self.retry = .standard }
        }

        /// The A2 form: the directory fake transport.
        public init(labelID: String, textURL: URL, route: PastedLabelAITextRoute.Route, cell: String, ledgerURL: URL, cacheDirectory: URL,
                    fakeTransportDirectory: URL, cellStop: Decimal = 5, programmeStop: Decimal = 25, reasoningBilledSeparately: Bool = true,
                    timeout: TimeInterval = 60, retry: SendRetryPolicy? = nil,
                    promptVersion: OpenRouterPastedLabelAITextRequest.PromptVersion = OpenRouterPastedLabelAITextRequest.defaultPromptVersion) {
            self.init(labelID: labelID, textURL: textURL, route: route, cell: cell, ledgerURL: ledgerURL, cacheDirectory: cacheDirectory,
                      connection: .fake(directory: fakeTransportDirectory), cellStop: cellStop, programmeStop: programmeStop,
                      reasoningBilledSeparately: reasoningBilledSeparately, timeout: timeout, retry: retry, promptVersion: promptVersion)
        }
    }

    /// The transport and key store `send` uses.
    public enum Connection: Sendable {
        /// `DirectoryFakeTransport` over the directory, with the placeholder key: nothing is sent.
        case fake(directory: URL)
        /// An injected transport and key store: the live one from `LiveTransport`, or a scripted one in tests.
        case transport(any LabelPhotoHTTPTransporting, keys: any FoodWebKeyStoring)
    }

    /// What `send` prints: everything promptfoo and `score` need, and nothing secret.
    public struct Output: Codable, Equatable, Sendable {
        public var labelID: String
        public var cell: String
        public var routeCandidate: String
        public var model: String
        public var endpoint: String
        public var promptVersion: String
        public var instructionSHA256: String
        public var schemaSHA256: String
        public var textSHA256: String
        public var requestSHA256: String
        public var cached: Bool
        /// `responded`, `transport_failed:<reason>`, `not_sent:<reason>`, `refused:<stop>`,
        /// `catalogue_failed:<reason>` (nothing reserved or sent), or
        /// `declined_before_send:<markers>` when the pre-send panel detector declined the text.
        public var attempt: String
        public var status: Int?
        /// The raw reply body, verbatim (UTF-8).
        public var response: String?
        /// The reported cost of this invocation's call, nil when unknown or when served from the cache.
        public var costUSD: String?
        /// What the ledger charged this invocation: the reported cost, W when unknown, 0 when cached.
        public var chargedUSD: String
        /// On a cache hit, the original tap's recorded cost (nil when it was unknown). The statistics
        /// count a cached tap at this cost once, as its original tap; nothing is charged again.
        public var cachedCostUSD: String?
        public var reservedUSD: String?
        public var latencySeconds: Double?
        public var promptTokens: Int?
        public var completionTokens: Int?
        /// The W this tap reserved (on a cache hit, the original tap's), nil when it reserved nothing.
        /// The statistics charge an unknown cost at this W (Qodo re-review finding 1).
        public var reservedWUSD: String? = nil
        /// How many attempts this tap reserved and made (A3 retries); nil in an A2 record.
        public var attempts: Int? = nil
        /// Each attempt's outcome in order: `responded:<status>`, `transport_failed:<reason>` or
        /// `not_sent:<reason>`. Never a header, a key or a body.
        public var attemptOutcomes: [String]? = nil
        /// Why a transient failure was not retried further: `attempts_exhausted`,
        /// `retry_after_over_cap`, `refused:<stop>` (the next reservation was refused), `cancelled`
        /// or `not_sent:<reason>`; nil when the last attempt was not a transient failure.
        public var retryStop: String? = nil
        /// The fresh run this record belongs to (revision 16); nil (absent) for the default run and
        /// in every older record.
        public var freshRun: String? = nil

        enum CodingKeys: String, CodingKey {
            case cell, model, endpoint, cached, attempt, status, response
            case labelID = "label_id", routeCandidate = "route_candidate", promptVersion = "prompt_version"
            case instructionSHA256 = "instruction_sha256", schemaSHA256 = "schema_sha256", textSHA256 = "text_sha256"
            case requestSHA256 = "request_sha256", costUSD = "cost_usd", chargedUSD = "charged_usd", reservedUSD = "reserved_usd"
            case cachedCostUSD = "cached_cost_usd", reservedWUSD = "reserved_w_usd"
            case attempts, attemptOutcomes = "attempt_outcomes", retryStop = "retry_stop", freshRun = "fresh_run"
            case latencySeconds = "latency_seconds", promptTokens = "prompt_tokens", completionTokens = "completion_tokens"
        }
    }

    public enum Failure: Error, CustomStringConvertible {
        case unreadableText, textRefused(String), catalogue(String), cache(String), badFreshRun(String)
        public var description: String {
            switch self {
            case let .badFreshRun(name): "bad fresh run name \(name): a lower-case letter, then up to 15 lower-case letters, digits or single hyphens"
            case .unreadableText: "the text file is not UTF-8"
            case let .textRefused(reason): "the text was refused before any request: \(reason)"
            case let .catalogue(reason): "the catalogue check failed, nothing sent: \(reason)"
            case let .cache(reason): "the response cache failed: \(reason)"
            }
        }
    }

    static func timestamp(_ date: Date = Date()) -> String { ISO8601DateFormatter().string(from: date) }

    public static func run(_ options: Options) async throws -> Output {
        // The run name is checked before the text is read or anything is built, reserved or sent.
        if let name = options.freshRun, !isFreshRunName(name) { throw Failure.badFreshRun(name) }
        guard let textData = FileManager.default.contents(atPath: options.textURL.path), let text = String(data: textData, encoding: .utf8) else {
            throw Failure.unreadableText
        }
        let request = try OpenRouterPastedLabelAITextRequest(route: options.route, promptVersion: options.promptVersion)
        let detector = PastedLabelAITextPanelDetector.detect(text: text)
        if detector.declines {
            return Output(labelID: options.labelID, cell: options.cell, routeCandidate: options.route.candidateID, model: options.route.model,
                          endpoint: options.route.endpoint, promptVersion: request.promptVersion.rawValue,
                          instructionSHA256: request.promptVersion.instructionSHA256,
                          schemaSHA256: OpenRouterPastedLabelAITextRequest.wireSchemaSHA256, textSHA256: EvalCase.sha256(textData),
                          requestSHA256: "", cached: false,
                          attempt: "declined_before_send:" + detector.markers.map(\.rawValue).joined(separator: ","), status: nil, response: nil,
                          costUSD: nil, chargedUSD: "0", cachedCostUSD: nil, reservedUSD: nil, latencySeconds: 0, promptTokens: nil,
                          completionTokens: nil, freshRun: options.freshRun)
        }
        let body: Data
        do { body = try request.body(text) } catch { throw Failure.textRefused("\(error)") }
        let requestSHA = EvalCase.sha256(body)
        var output = Output(labelID: options.labelID, cell: options.cell, routeCandidate: options.route.candidateID, model: options.route.model,
                            endpoint: options.route.endpoint, promptVersion: request.promptVersion.rawValue,
                            instructionSHA256: request.promptVersion.instructionSHA256,
                            schemaSHA256: OpenRouterPastedLabelAITextRequest.wireSchemaSHA256, textSHA256: EvalCase.sha256(textData),
                            requestSHA256: requestSHA, cached: false, attempt: "", status: nil, response: nil, costUSD: nil, chargedUSD: "0",
                            cachedCostUSD: nil, reservedUSD: nil, latencySeconds: nil, promptTokens: nil, completionTokens: nil,
                            freshRun: options.freshRun)
        let cache = ResponseCache(directory: options.cacheDirectory)
        // The cache key: the body's SHA-256 for the default run, and that SHA joined to the run name
        // for a fresh run, so a fresh run neither reads nor overwrites the default entry (revision 16).
        let cacheKey = ResponseCache.key(requestSHA, freshRun: options.freshRun)
        // One caller per cache key at a time, across processes (Qodo finding 6 on A2): the cache
        // check, the reservation, the send and the store run under a lock file named by the key, so
        // concurrent identical sends make one call and the others read its cache entry.
        return try await ResponseCache.withRequestLock(options.cacheDirectory, cacheKey) {
            if var cached = try cache.load(cacheKey) {
                // Nothing is charged this time; the original cost is kept apart (Qodo finding 7 on A2).
                cached.cached = true
                cached.cell = options.cell
                cached.labelID = options.labelID
                cached.freshRun = options.freshRun
                cached.cachedCostUSD = cached.costUSD
                cached.costUSD = nil
                cached.chargedUSD = "0"
                cached.reservedWUSD = cached.reservedWUSD ?? cached.reservedUSD
                cached.reservedUSD = nil
                return cached
            }
            return try await sendOnce(options, text: text, request: request, cacheKey: cacheKey, cache: cache, output: output)
        }
    }

    static func sendOnce(_ options: Options, text: String, request: OpenRouterPastedLabelAITextRequest, cacheKey: String,
                         cache: ResponseCache, output start: Output) async throws -> Output {
        var output = start
        let transport: any LabelPhotoHTTPTransporting
        let keys: any FoodWebKeyStoring
        switch options.connection {
        case let .fake(directory):
            transport = DirectoryFakeTransport(directory: directory, labelID: options.labelID); keys = FakeTransportKey()
        case let .transport(injected, injectedKeys):
            transport = injected; keys = injectedKeys
        }
        let checker = OpenRouterPastedLabelAITextRouteChecker(transport: transport, clock: SystemLedgerClock(),
                                                              reasoningBilledSeparately: options.reasoningBilledSeparately)
        let check: LabelPhotoManifest.CatalogueCheck
        // A catalogue failure is a structured record, not an error exit, so it is told apart from a
        // tap that reserved W (Qodo re-review finding 3): nothing was reserved or sent, so it costs 0.
        do { check = try await checker.check(options.route) } catch {
            output.attempt = "catalogue_failed:\(error)"
            return output
        }
        guard let prompt = Decimal(string: check.promptPrice, locale: Locale(identifier: "en_US_POSIX")),
              let completion = Decimal(string: check.completionPrice, locale: Locale(identifier: "en_US_POSIX")) else {
            output.attempt = "catalogue_failed:unreadable prices"
            return output
        }
        let prices = LabelPhotoSpendPolicy.Prices(promptPerToken: prompt, completionPerToken: completion,
                                                  reasoningBilledSeparately: options.reasoningBilledSeparately,
                                                  maxOutputTokens: options.route.maxOutputTokens)
        // W from this request's own prompt bound (A2 gate finding 2); a bound past the ceiling is refused.
        let promptBound = request.promptTokenBound(text)
        guard let worstCase = PastedLabelAITextSpendPolicy.worstCase(prices, reasoningLimit: options.route.reasoningTokenBound,
                                                                     promptTokenBound: promptBound) else {
            output.attempt = "refused:\(EvalSpendLedger.Refusal.promptBoundOverCeiling)"
            return output
        }
        output.reservedUSD = "\(worstCase)"
        let ledger = try EvalSpendLedger(url: options.ledgerURL, cellStop: options.cellStop, programmeStop: options.programmeStop)
        let attempt = OpenRouterPastedLabelAITextAttempt(transport: transport, keys: keys, request: request)
        let policy = options.retry
        let started = policy.now()
        var reservations = 0
        var charged = Decimal(0)
        var reported = Decimal(0)
        var anyResponded = false
        var costUnknown = false
        var outcomes: [String] = []
        var last: PastedLabelAITextAttemptResult?
        attempts: while true {
            // Every attempt reserves its own W first, so a retry never sends outside a reservation.
            let reservation: String
            do {
                reservation = try ledger.reserve(cell: options.cell, caseID: options.labelID, model: options.route.model, worstCase: worstCase,
                                                 at: timestamp(policy.now()), id: UUID().uuidString)
            } catch let refusal as EvalSpendLedger.Refusal {
                if reservations == 0 {
                    output.attempt = "refused:\(refusal)"
                    return output
                }
                output.retryStop = "refused:\(refusal)"
                break attempts
            }
            reservations += 1
            let result = await attempt.attempt(text: text, timeout: options.timeout)
            switch result {
            case let .notSent(reason):
                try ledger.settle(id: reservation, .notSent, returnedModel: nil, generationID: nil, at: timestamp(policy.now()))
                outcomes.append("not_sent:\(reason.rawValue)")
                // Only the first attempt's not-sent outcome names the tap; a later one ends the retries.
                if reservations > 1 { output.retryStop = "not_sent:\(reason.rawValue)"; break attempts }
                output.attempt = "not_sent:\(reason.rawValue)"
            case let .transportFailed(reason):
                try ledger.settle(id: reservation, .unknownNoGeneration, returnedModel: nil, generationID: nil, at: timestamp(policy.now()))
                outcomes.append("transport_failed:\(reason.rawValue)")
                output.attempt = "transport_failed:\(reason.rawValue)"
                output.status = nil; output.response = nil; output.promptTokens = nil; output.completionTokens = nil
                charged += worstCase
                costUnknown = true
            case let .responded(response):
                let object = (try? JSONSerialization.jsonObject(with: response.body)) as? [String: Any]
                let usage = PastedLabelAITextEnvelope.usage(response.body)
                let cost = usage.flatMap { $0.costUSD == LabelPhotoManifest.Usage.unknownCost ? nil : Decimal(string: $0.costUSD) }
                // An HTTP error that returned no generation (no `id`, no `usage`) does not count towards
                // the three-unknown stop; a 200 without a cost does (photo precedent, 17 October 2026).
                let noGeneration = response.status != 200 && object?["id"] == nil && object?["usage"] == nil
                try ledger.settle(id: reservation, cost.map(EvalSpendLedger.Settlement.reported) ?? (noGeneration ? .unknownNoGeneration : .unknown), returnedModel: object?["model"] as? String,
                                  generationID: object?["id"] as? String, at: timestamp(policy.now()), promptTokens: usage?.promptTokens,
                                  promptTokenBound: promptBound)
                outcomes.append("responded:\(response.status)")
                output.attempt = "responded"
                output.status = response.status
                output.response = String(decoding: response.body, as: UTF8.self)
                output.promptTokens = usage?.promptTokens
                output.completionTokens = usage?.completionTokens
                anyResponded = true
                if let cost { charged += cost; reported += cost } else { charged += worstCase; costUnknown = true }
            }
            last = result
            switch policy.decide(afterAttempt: reservations, result: result, now: policy.now(), jitter: policy.jitter()) {
            case let .stop(reason):
                output.retryStop = reason
                break attempts
            case let .retry(delay):
                do { try await policy.sleep(delay) } catch { output.retryStop = "cancelled"; break attempts }
                if Task.isCancelled { output.retryStop = "cancelled"; break attempts }
            }
        }
        output.latencySeconds = policy.now().timeIntervalSince(started)
        output.attempts = reservations
        output.attemptOutcomes = outcomes
        output.reservedWUSD = "\(worstCase * Decimal(reservations))"
        output.reservedUSD = output.reservedWUSD
        output.chargedUSD = "\(charged)"
        // The tap's reported cost covers every attempt (5.3); one unknown attempt makes it unknown,
        // and the statistics then charge the tap at its W over all attempts.
        output.costUSD = anyResponded && !costUnknown ? "\(reported)" : nil
        // Only an HTTP 200 reply that passes the envelope check is cached (A2 gate finding 8),
        // so a failed or rejected reply is never replayed as if it had answered.
        if case let .responded(response) = last, response.status == 200,
           case .answered = PastedLabelAITextEnvelope.check(response, route: options.route) {
            try cache.store(cacheKey, output)
        }
        return output
    }
}

/// The response cache (5.2 item 3): one file per request body, named by the body's SHA-256, in a
/// directory the operator names (the private folder in A3). A fresh run's entry is named by the
/// SHA-256 and the run name, `<sha>.fresh-<run>.json` (revision 16). A cached response keeps its
/// original recorded cost and latency.
public struct ResponseCache: Sendable {
    public let directory: URL
    public init(directory: URL) { self.directory = directory }

    /// The cache key of a request body's SHA-256 in the default run or in a fresh run.
    public static func key(_ requestSHA: String, freshRun: String?) -> String {
        guard let freshRun else { return requestSHA }
        return "\(requestSHA).fresh-\(freshRun)"
    }

    /// A SHA-256, alone or followed by `.fresh-` and a valid run name; nothing else names a file.
    static func isKey(_ key: String) -> Bool {
        let parts = key.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
        guard EvalCase.isSHA256Hex(String(parts[0])) else { return false }
        guard parts.count == 2 else { return true }
        let suffix = String(parts[1])
        return suffix.hasPrefix("fresh-") && SendCommand.isFreshRunName(String(suffix.dropFirst("fresh-".count)))
    }

    func file(_ key: String) -> URL { directory.appendingPathComponent("\(key).json") }

    /// Runs `body` holding an exclusive `flock` on `<directory>/<key>.lock`, polled without blocking
    /// a thread, so another process or task with the same cache key waits its turn.
    static func withRequestLock<T>(_ directory: URL, _ key: String, _ body: () async throws -> T) async throws -> T {
        guard isKey(key) else { throw SendCommand.Failure.cache("bad key") }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let descriptor = open(directory.appendingPathComponent("\(key).lock").path, O_CREAT | O_RDWR, 0o600)
        guard descriptor >= 0 else { throw SendCommand.Failure.cache("cannot open the request lock") }
        defer { close(descriptor) }
        while flock(descriptor, LOCK_EX | LOCK_NB) != 0 {
            guard errno == EWOULDBLOCK else { throw SendCommand.Failure.cache("cannot take the request lock") }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        defer { flock(descriptor, LOCK_UN) }
        return try await body()
    }

    public func load(_ key: String) throws -> SendCommand.Output? {
        guard Self.isKey(key), let data = FileManager.default.contents(atPath: file(key).path) else { return nil }
        do { return try JSONDecoder().decode(SendCommand.Output.self, from: data) } catch {
            throw SendCommand.Failure.cache("unreadable cache entry \(key)")
        }
    }

    public func store(_ key: String, _ output: SendCommand.Output) throws {
        guard Self.isKey(key) else { throw SendCommand.Failure.cache("bad key") }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(output).write(to: file(key), options: .atomic)
    }
}
