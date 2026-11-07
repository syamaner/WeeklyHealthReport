import FoodLabelPhotoCapture
import FoodLedgerApplication
import Foundation
import PastedLabelAITextEvalCore

/// `PastedLabelAITextEval send` (docs/pasted-label-ai-text-v1.md 5.2 items 1 and 3): one label's
/// call, built with the shipped text request builder, with the spend reservation and the response
/// cache. In A2 the only transport is `DirectoryFakeTransport`.
///
/// 0. The pre-send panel detector runs on the text, as in the product (4.7): a detected US,
///    Australian or New Zealand panel is declined before any request is built, and nothing is spent.
/// 1. The request body is built by `OpenRouterPastedLabelAITextRequest`; its SHA-256 keys the cache.
/// 2. A cached response is returned as it was recorded, with its original cost, and charges nothing.
/// 3. Otherwise the text route checker runs over the same transport, W is priced from the
///    catalogue's prices, and W is reserved in the spend ledger (refused past a stop).
/// 4. One attempt is sent; the reservation settles to the reported cost, to unknown (charged at
///    W), or to zero when nothing was sent. A responded call is cached.
public enum SendCommand {
    public struct Options: Sendable {
        public let labelID: String
        public let textURL: URL
        public let route: PastedLabelAITextRoute.Route
        public let cell: String
        public let ledgerURL: URL
        public let cacheDirectory: URL
        public let fakeTransportDirectory: URL
        public let cellStop: Decimal
        public let programmeStop: Decimal
        /// W includes the reasoning limit unless the endpoint is known to count it inside `max_tokens`.
        public let reasoningBilledSeparately: Bool
        public let timeout: TimeInterval

        public init(labelID: String, textURL: URL, route: PastedLabelAITextRoute.Route, cell: String, ledgerURL: URL, cacheDirectory: URL,
                    fakeTransportDirectory: URL, cellStop: Decimal = 5, programmeStop: Decimal = 25, reasoningBilledSeparately: Bool = true,
                    timeout: TimeInterval = 60) {
            self.labelID = labelID; self.textURL = textURL; self.route = route; self.cell = cell; self.ledgerURL = ledgerURL
            self.cacheDirectory = cacheDirectory; self.fakeTransportDirectory = fakeTransportDirectory; self.cellStop = cellStop
            self.programmeStop = programmeStop; self.reasoningBilledSeparately = reasoningBilledSeparately; self.timeout = timeout
        }
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
        /// `responded`, `transport_failed:<reason>`, `not_sent:<reason>`, `refused:<stop>`, or
        /// `declined_before_send:<markers>` when the pre-send panel detector declined the text.
        public var attempt: String
        public var status: Int?
        /// The raw reply body, verbatim (UTF-8).
        public var response: String?
        /// The reported cost, nil when unknown.
        public var costUSD: String?
        /// What the ledger charged: the reported cost, or W when unknown.
        public var chargedUSD: String
        public var reservedUSD: String?
        public var latencySeconds: Double?
        public var promptTokens: Int?
        public var completionTokens: Int?

        enum CodingKeys: String, CodingKey {
            case cell, model, endpoint, cached, attempt, status, response
            case labelID = "label_id", routeCandidate = "route_candidate", promptVersion = "prompt_version"
            case instructionSHA256 = "instruction_sha256", schemaSHA256 = "schema_sha256", textSHA256 = "text_sha256"
            case requestSHA256 = "request_sha256", costUSD = "cost_usd", chargedUSD = "charged_usd", reservedUSD = "reserved_usd"
            case latencySeconds = "latency_seconds", promptTokens = "prompt_tokens", completionTokens = "completion_tokens"
        }
    }

    public enum Failure: Error, CustomStringConvertible {
        case unreadableText, textRefused(String), catalogue(String), cache(String)
        public var description: String {
            switch self {
            case .unreadableText: "the text file is not UTF-8"
            case let .textRefused(reason): "the text was refused before any request: \(reason)"
            case let .catalogue(reason): "the catalogue check failed, nothing sent: \(reason)"
            case let .cache(reason): "the response cache failed: \(reason)"
            }
        }
    }

    static func timestamp(_ date: Date = Date()) -> String { ISO8601DateFormatter().string(from: date) }

    public static func run(_ options: Options) async throws -> Output {
        guard let textData = FileManager.default.contents(atPath: options.textURL.path), let text = String(data: textData, encoding: .utf8) else {
            throw Failure.unreadableText
        }
        let request = try OpenRouterPastedLabelAITextRequest(route: options.route)
        let detector = PastedLabelAITextPanelDetector.detect(text: text)
        if detector.declines {
            return Output(labelID: options.labelID, cell: options.cell, routeCandidate: options.route.candidateID, model: options.route.model,
                          endpoint: options.route.endpoint, promptVersion: OpenRouterPastedLabelAITextRequest.promptVersion,
                          instructionSHA256: OpenRouterPastedLabelAITextRequest.instructionSHA256,
                          schemaSHA256: OpenRouterPastedLabelAITextRequest.wireSchemaSHA256, textSHA256: EvalCase.sha256(textData),
                          requestSHA256: "", cached: false,
                          attempt: "declined_before_send:" + detector.markers.map(\.rawValue).joined(separator: ","), status: nil, response: nil,
                          costUSD: nil, chargedUSD: "0", reservedUSD: nil, latencySeconds: 0, promptTokens: nil, completionTokens: nil)
        }
        let body: Data
        do { body = try request.body(text) } catch { throw Failure.textRefused("\(error)") }
        let requestSHA = EvalCase.sha256(body)
        var output = Output(labelID: options.labelID, cell: options.cell, routeCandidate: options.route.candidateID, model: options.route.model,
                            endpoint: options.route.endpoint, promptVersion: OpenRouterPastedLabelAITextRequest.promptVersion,
                            instructionSHA256: OpenRouterPastedLabelAITextRequest.instructionSHA256,
                            schemaSHA256: OpenRouterPastedLabelAITextRequest.wireSchemaSHA256, textSHA256: EvalCase.sha256(textData),
                            requestSHA256: requestSHA, cached: false, attempt: "", status: nil, response: nil, costUSD: nil, chargedUSD: "0",
                            reservedUSD: nil, latencySeconds: nil, promptTokens: nil, completionTokens: nil)
        let cache = ResponseCache(directory: options.cacheDirectory)
        if var cached = try cache.load(requestSHA) {
            cached.cached = true
            cached.cell = options.cell
            cached.labelID = options.labelID
            return cached
        }
        let transport = DirectoryFakeTransport(directory: options.fakeTransportDirectory, labelID: options.labelID)
        let checker = OpenRouterPastedLabelAITextRouteChecker(transport: transport, clock: SystemLedgerClock(),
                                                              reasoningBilledSeparately: options.reasoningBilledSeparately)
        let check: LabelPhotoManifest.CatalogueCheck
        do { check = try await checker.check(options.route) } catch { throw Failure.catalogue("\(error)") }
        guard let prompt = Decimal(string: check.promptPrice, locale: Locale(identifier: "en_US_POSIX")),
              let completion = Decimal(string: check.completionPrice, locale: Locale(identifier: "en_US_POSIX")) else {
            throw Failure.catalogue("unreadable prices")
        }
        let prices = LabelPhotoSpendPolicy.Prices(promptPerToken: prompt, completionPerToken: completion,
                                                  reasoningBilledSeparately: options.reasoningBilledSeparately,
                                                  maxOutputTokens: options.route.maxOutputTokens)
        let worstCase = PastedLabelAITextSpendPolicy.worstCase(prices, reasoningLimit: options.route.reasoningLimit)
        output.reservedUSD = "\(worstCase)"
        let ledger = try EvalSpendLedger(url: options.ledgerURL, cellStop: options.cellStop, programmeStop: options.programmeStop)
        let reservation: String
        do {
            reservation = try ledger.reserve(cell: options.cell, caseID: options.labelID, model: options.route.model, worstCase: worstCase,
                                             at: timestamp(), id: UUID().uuidString)
        } catch let refusal as EvalSpendLedger.Refusal {
            output.attempt = "refused:\(refusal)"
            return output
        }
        let attempt = OpenRouterPastedLabelAITextAttempt(transport: transport, keys: FakeTransportKey(), request: request)
        let started = Date()
        let result = await attempt.attempt(text: text, timeout: options.timeout)
        output.latencySeconds = Date().timeIntervalSince(started)
        switch result {
        case let .notSent(reason):
            try ledger.settle(id: reservation, .notSent, returnedModel: nil, generationID: nil, at: timestamp())
            output.attempt = "not_sent:\(reason.rawValue)"
        case let .transportFailed(reason):
            try ledger.settle(id: reservation, .unknown, returnedModel: nil, generationID: nil, at: timestamp())
            output.attempt = "transport_failed:\(reason.rawValue)"
            output.chargedUSD = "\(worstCase)"
        case let .responded(response):
            let object = (try? JSONSerialization.jsonObject(with: response.body)) as? [String: Any]
            let usage = PastedLabelAITextEnvelope.usage(response.body)
            let cost = usage.flatMap { $0.costUSD == LabelPhotoManifest.Usage.unknownCost ? nil : Decimal(string: $0.costUSD) }
            try ledger.settle(id: reservation, cost.map(EvalSpendLedger.Settlement.reported) ?? .unknown, returnedModel: object?["model"] as? String,
                              generationID: object?["id"] as? String, at: timestamp())
            output.attempt = "responded"
            output.status = response.status
            output.response = String(decoding: response.body, as: UTF8.self)
            output.costUSD = cost.map { "\($0)" }
            output.chargedUSD = "\(cost ?? worstCase)"
            output.promptTokens = usage?.promptTokens
            output.completionTokens = usage?.completionTokens
            try cache.store(requestSHA, output)
        }
        return output
    }
}

/// The response cache (5.2 item 3): one file per request body, named by the body's SHA-256, in a
/// directory the operator names (the private folder in A3). A cached response keeps its original
/// recorded cost and latency.
public struct ResponseCache: Sendable {
    public let directory: URL
    public init(directory: URL) { self.directory = directory }

    func file(_ sha: String) -> URL { directory.appendingPathComponent("\(sha).json") }

    public func load(_ sha: String) throws -> SendCommand.Output? {
        guard EvalCase.isSHA256Hex(sha), let data = FileManager.default.contents(atPath: file(sha).path) else { return nil }
        do { return try JSONDecoder().decode(SendCommand.Output.self, from: data) } catch {
            throw SendCommand.Failure.cache("unreadable cache entry \(sha)")
        }
    }

    public func store(_ sha: String, _ output: SendCommand.Output) throws {
        guard EvalCase.isSHA256Hex(sha) else { throw SendCommand.Failure.cache("bad key") }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(output).write(to: file(sha), options: .atomic)
    }
}
