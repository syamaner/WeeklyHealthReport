import FoodLabelPhotoCapture
import FoodLedgerApplication
import Foundation
@testable import PastedLabelAITextEvalCore
@testable import PastedLabelAITextEvalHarness
import XCTest

/// A3's live mode without a network (docs/pasted-label-ai-text-v1.md 5.2 item 1, 5.3, T4, T5): the
/// connection choice, the environment key that is never written or printed, and the retries, each
/// attempt under its own reservation, over a scripted transport and an injected clock and sleeper.
final class LiveModeTests: XCTestCase {
    static let key = "sk-or-v1-synthetic-test-key-0123456789abcdef"
    var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("eval-live-\(UUID().uuidString)", isDirectory: true)
        try Fixtures.write(to: root)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    func options(_ transport: ScriptedTransport, clock: TestClock, label: String = "uk-synthetic-01", maxAttempts: Int = 3) throws -> SendCommand.Options {
        let key = try EnvironmentKey(environment: [EnvironmentKey.variable: Self.key])
        let policy = SendRetryPolicy(maxAttempts: maxAttempts, sleep: { clock.sleep($0) }, jitter: { 0 }, now: { clock.now })
        return SendCommand.Options(labelID: label, textURL: root.appendingPathComponent("texts/\(label).txt"),
                                   route: PastedLabelAITextRoute.gemini4ArgonVertexUS, cell: "cell-a",
                                   ledgerURL: root.appendingPathComponent("ledger.json"), cacheDirectory: root.appendingPathComponent("cache"),
                                   connection: .transport(transport, keys: key), retry: policy)
    }

    func ledger() throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("ledger.json"))) as? [String: Any])
    }

    func entries() throws -> [[String: Any]] { try XCTUnwrap(ledger()["entries"] as? [[String: Any]]) }

    static var w: Decimal { HarnessTests.ukW }
    static let answer = ScriptedTransport.Step.reply(200, [:], Fixtures.reply(cost: "0.004")["body"] as! String)
    static func failure(_ status: Int, _ headers: [String: String] = [:], cost: String? = "0.001") -> ScriptedTransport.Step {
        .reply(status, headers, #"{"error": {"code": \#(status), "message": "synthetic"}"# + (cost.map { #", "usage": {"cost": \#($0)}"# } ?? "") + "}")
    }

    // MARK: Retries and reservations

    func testA503ThenAnAnswerRetriesUnderTwoReservationsAndTheTapCoversBoth() async throws {
        let clock = TestClock()
        let transport = ScriptedTransport([Self.failure(503), Self.answer])
        let output = try await SendCommand.run(try options(transport, clock: clock))
        XCTAssertEqual(output.attempt, "responded")
        XCTAssertEqual(output.status, 200)
        XCTAssertEqual(output.attempts, 2)
        XCTAssertEqual(output.attemptOutcomes, ["responded:503", "responded:200"])
        XCTAssertNil(output.retryStop)
        XCTAssertEqual(output.costUSD, "0.005", "the tap's cost covers both attempts (5.3)")
        XCTAssertEqual(output.chargedUSD, "0.005")
        XCTAssertEqual(output.reservedWUSD, "\(Self.w * 2)", "one W per attempt")
        XCTAssertEqual(clock.sleeps, [0.5], "backoff 1 s scaled by (0.5 + jitter / 2) with jitter 0")
        XCTAssertEqual(try XCTUnwrap(output.latencySeconds), 0.5, accuracy: 1e-9, "the tap's latency includes the wait")
        XCTAssertEqual(transport.posts, 2)
        let settled = try entries()
        XCTAssertEqual(settled.count, 2, "each attempt has its own reservation")
        XCTAssertEqual(settled.map { $0["kind"] as? String }, [EvalSpendLedger.settledKind, EvalSpendLedger.settledKind])
        XCTAssertEqual(settled.map { $0["cost_usd"] as? String }, ["0.001", "0.004"])
        // The answered tap is cached with its whole cost, and is not charged again.
        let cached = try await SendCommand.run(try options(ScriptedTransport([]), clock: clock))
        XCTAssertTrue(cached.cached)
        XCTAssertEqual(cached.cachedCostUSD, "0.005")
        XCTAssertEqual(cached.reservedWUSD, "\(Self.w * 2)")
        XCTAssertEqual(try entries().count, 2)
    }

    func testRetryAfterIsHonouredInSecondsAndAsAnHTTPDate() async throws {
        let clock = TestClock()
        let date = Self.httpDate(clock.now.addingTimeInterval(5))
        let transport = ScriptedTransport([Self.failure(429, ["retry-after": "7"]), Self.failure(502, ["Retry-After": date]), Self.answer])
        let output = try await SendCommand.run(try options(transport, clock: clock))
        XCTAssertEqual(output.attempt, "responded")
        XCTAssertEqual(output.attempts, 3)
        XCTAssertEqual(clock.sleeps.count, 2)
        XCTAssertEqual(clock.sleeps[0], 7, accuracy: 1e-9, "Retry-After seconds, larger than the backoff")
        // The date was 5 s ahead when written; 7 s have passed since, so the backoff (1 s) applies.
        XCTAssertEqual(clock.sleeps[1], 1, accuracy: 1e-9)
        XCTAssertEqual(transport.posts, 3)
        XCTAssertEqual(try entries().count, 3)
    }

    func testAnHTTPDateRetryAfterInTheFutureIsWaited() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let response = PastedLabelAITextRawResponse(status: 503, headers: ["Retry-After": Self.httpDate(now.addingTimeInterval(12))], body: Data(),
                                                    exceededLimit: false)
        XCTAssertEqual(SendRetryPolicy.standard.decide(afterAttempt: 1, result: .responded(response), now: now, jitter: 0), .retry(after: 12))
    }

    func testARetryAfterPastTheCapStopsRatherThanRetryingSooner() async throws {
        let clock = TestClock()
        let transport = ScriptedTransport([Self.failure(429, ["Retry-After": "120"]), Self.answer])
        let output = try await SendCommand.run(try options(transport, clock: clock))
        XCTAssertEqual(output.attempts, 1)
        XCTAssertEqual(output.status, 429)
        XCTAssertEqual(output.retryStop, "retry_after_over_cap")
        XCTAssertEqual(clock.sleeps, [])
        XCTAssertEqual(transport.posts, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("cache/\(output.requestSHA256).json").path))
    }

    func testTransportFailuresAreRetriedAtMostThreeTimesEachChargedAtW() async throws {
        let clock = TestClock()
        let transport = ScriptedTransport([.fail(.timedOut), .fail(.failed), .fail(.offline), Self.answer])
        let output = try await SendCommand.run(try options(transport, clock: clock))
        XCTAssertEqual(output.attempt, "transport_failed:offline")
        XCTAssertEqual(output.attempts, 3)
        XCTAssertEqual(output.attemptOutcomes, ["transport_failed:timed_out", "transport_failed:failed", "transport_failed:offline"])
        XCTAssertEqual(output.retryStop, "attempts_exhausted")
        XCTAssertNil(output.costUSD, "unknown, never zero")
        XCTAssertEqual(output.chargedUSD, "\(Self.w * 3)")
        XCTAssertEqual(output.reservedWUSD, "\(Self.w * 3)")
        XCTAssertEqual(clock.sleeps, [0.5, 1], "exponential backoff")
        XCTAssertEqual(transport.posts, 3, "never a fourth attempt")
        XCTAssertEqual(try entries().map { $0["kind"] as? String }, Array(repeating: EvalSpendLedger.noGenerationKind, count: 3))
        XCTAssertEqual(try ledger()["unknown_cost_calls"] as? Int, 0, "an error with no generation is not a counted unknown")
        XCTAssertEqual(try ledger()["charged_usd"] as? String, "\(Self.w * 3)", "but it is still charged at W")
    }

    func testAnHTTPErrorWithoutAGenerationIsNotACountedUnknownButOneWithAGenerationIs() async throws {
        let transport = ScriptedTransport([Self.failure(503, cost: nil),
                                           .reply(503, [:], #"{"id": "gen-synthetic", "error": {"code": 503, "message": "synthetic"}}"#),
                                           Self.answer])
        let output = try await SendCommand.run(try options(transport, clock: TestClock()))
        XCTAssertEqual(output.attempts, 3)
        XCTAssertEqual(try entries().map { $0["kind"] as? String },
                       [EvalSpendLedger.noGenerationKind, EvalSpendLedger.unknownKind, EvalSpendLedger.settledKind])
        XCTAssertEqual(try ledger()["unknown_cost_calls"] as? Int, 1)
    }

    func testARetryIsNeverSentOutsideAReservation() async throws {
        // Two unknown-cost calls already: the first attempt is reserved, fails with an unknown cost
        // after returning a generation, and the ledger's unknown-cost stop then refuses the retry's
        // reservation, so nothing more is sent.
        var existing = EvalSpendLedger.fresh()
        existing["entries"] = (0..<2).map { _ in ["purpose": "route-c", "cost_usd": NSNull(), "kind": "answer"] as [String: Any] }
        try JSONSerialization.data(withJSONObject: existing).write(to: root.appendingPathComponent("ledger.json"))
        let transport = ScriptedTransport([.reply(503, [:], #"{"id": "gen-synthetic", "error": {"code": 503, "message": "synthetic"}}"#),
                                           Self.answer])
        let output = try await SendCommand.run(try options(transport, clock: TestClock()))
        XCTAssertEqual(output.attempt, "responded", "the tap keeps the outcome of the attempt it made")
        XCTAssertEqual(output.attempts, 1)
        XCTAssertEqual(output.retryStop, "refused:the ledger's unknown-cost stop is reached")
        XCTAssertEqual(output.chargedUSD, "\(Self.w)")
        XCTAssertEqual(transport.posts, 1)
        XCTAssertEqual(try entries().filter { $0["purpose"] as? String == EvalSpendLedger.purpose }.count, 1)
    }

    func testNonTransientRepliesAreNeverRetried() async throws {
        let wrongModel = (Fixtures.reply(cost: "0.004")["body"] as! String).replacingOccurrences(of: "google/gemini-4-argon", with: "other/model")
        let overloaded200 = #"{"error": {"code": 503, "message": "overloaded"}, "usage": {"cost": 0.001}}"#
        for step in [Self.failure(400), Self.failure(401), Self.failure(403), Self.failure(408), Self.failure(404),
                     ScriptedTransport.Step.reply(200, [:], wrongModel), .reply(200, [:], overloaded200), Self.answer, .fail(.cancelled)] {
            try? FileManager.default.removeItem(at: root.appendingPathComponent("cache"))
            let transport = ScriptedTransport([step, Self.answer])
            let clock = TestClock()
            let output = try await SendCommand.run(try options(transport, clock: clock))
            XCTAssertEqual(output.attempts, 1, "\(step)")
            XCTAssertNil(output.retryStop, "\(step)")
            XCTAssertEqual(transport.posts, 1, "\(step)")
            XCTAssertEqual(clock.sleeps, [], "\(step)")
        }
    }

    func testAMissingKeyIsNotSentAndNotRetried() async throws {
        struct NoKey: FoodWebKeyStoring {
            func load() throws -> String? { nil }
            func save(_ key: String) throws {}
            func delete() throws {}
        }
        let transport = ScriptedTransport([Self.answer])
        var opts = try options(transport, clock: TestClock())
        opts = SendCommand.Options(labelID: opts.labelID, textURL: opts.textURL, route: opts.route, cell: opts.cell, ledgerURL: opts.ledgerURL,
                                   cacheDirectory: opts.cacheDirectory, connection: .transport(transport, keys: NoKey()), retry: opts.retry)
        let output = try await SendCommand.run(opts)
        XCTAssertEqual(output.attempt, "not_sent:key_missing")
        XCTAssertEqual(output.chargedUSD, "0")
        XCTAssertNil(output.costUSD)
        XCTAssertEqual(transport.posts, 0)
        XCTAssertEqual(try entries().first?["kind"] as? String, EvalSpendLedger.notSentKind)
    }

    func testTheFakeTransportMakesOneAttemptByDefault() throws {
        let fake = SendCommand.Options(labelID: "x", textURL: root, route: PastedLabelAITextRoute.gemini4ArgonVertexUS, cell: "c", ledgerURL: root,
                                       cacheDirectory: root, fakeTransportDirectory: root)
        XCTAssertEqual(fake.retry.maxAttempts, 1)
        let live = SendCommand.Options(labelID: "x", textURL: root, route: PastedLabelAITextRoute.gemini4ArgonVertexUS, cell: "c", ledgerURL: root,
                                       cacheDirectory: root, connection: .transport(ScriptedTransport([]), keys: FakeTransportKey()))
        XCTAssertEqual(live.retry.maxAttempts, 3)
        XCTAssertEqual(SendRetryPolicy(maxAttempts: 9).maxAttempts, 3, "never more than three attempts")
        XCTAssertEqual(SendRetryPolicy(maximumWait: 600).maximumWait, 30, "never a longer wait than the cap")
    }

    func testTheBackoffDoublesWithJitter() {
        let policy = SendRetryPolicy.standard
        let busy = PastedLabelAITextAttemptResult.responded(.init(status: 500, headers: [:], body: Data(), exceededLimit: false))
        let now = Date()
        XCTAssertEqual(policy.decide(afterAttempt: 1, result: busy, now: now, jitter: 0), .retry(after: 0.5))
        XCTAssertEqual(policy.decide(afterAttempt: 1, result: busy, now: now, jitter: 1), .retry(after: 1))
        XCTAssertEqual(policy.decide(afterAttempt: 2, result: busy, now: now, jitter: 0.5), .retry(after: 1.5))
        XCTAssertEqual(policy.decide(afterAttempt: 3, result: busy, now: now, jitter: 0), .stop("attempts_exhausted"))
        XCTAssertEqual(policy.decide(afterAttempt: 1, result: .notSent(.keyMissing), now: now, jitter: 0), .stop(nil))
    }

    // MARK: The key (T4)

    func testTheKeyIsSentOnlyInThePostsAuthorizationAndNeverPrintedOrWritten() async throws {
        let clock = TestClock()
        let transport = ScriptedTransport([Self.failure(503), Self.answer])
        let answered = try await SendCommand.run(try options(transport, clock: clock))
        XCTAssertEqual(answered.attempt, "responded")
        let failing = ScriptedTransport([.fail(.timedOut), .fail(.failed), .fail(.failed)])
        let failed = try await SendCommand.run(try options(failing, clock: clock, label: "uk-no-cost"))
        XCTAssertEqual(failed.attempts, 3)
        // On the wire: only the POSTs carry it, as a bearer token; the catalogue GETs carry no Authorization.
        for request in transport.requests + failing.requests {
            if request.method == "POST" {
                XCTAssertEqual(request.headers["Authorization"], "Bearer \(Self.key)")
            } else {
                XCTAssertNil(request.headers["Authorization"], request.url.absoluteString)
                XCTAssertFalse(request.url.absoluteString.contains(Self.key))
            }
        }
        // Never in what `send` prints, the cache, the ledger, the lock files or anything else written.
        let encoder = JSONEncoder()
        for output in [answered, failed] {
            XCTAssertFalse(String(decoding: try encoder.encode(output), as: UTF8.self).contains(Self.key))
            XCTAssertFalse("\(output)".contains(Self.key))
        }
        let files = try XCTUnwrap(FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)).compactMap { $0 as? URL }
        XCTAssertTrue(files.contains { $0.lastPathComponent == "ledger.json" })
        XCTAssertTrue(files.contains { $0.pathExtension == "json" && $0.path.contains("/cache/") })
        for file in files where !file.hasDirectoryPath {
            let data = try Data(contentsOf: file)
            XCTAssertNil(data.range(of: Data(Self.key.utf8)), file.path)
        }
        // Nor in the key store's own descriptions.
        let store = try EnvironmentKey(environment: [EnvironmentKey.variable: Self.key])
        var dumped = ""
        dump(store, to: &dumped)
        for text in ["\(store)", String(reflecting: store), dumped, "\(SendTransportChoice.live(store))"] {
            XCTAssertFalse(text.contains(Self.key), text)
        }
        try store.save("another-key-value-0123456789")
        try store.delete()
        XCTAssertEqual(try store.load(), Self.key, "save and delete do nothing")
    }

    func testTheConnectionChoiceAndTheKeyAreCheckedBeforeAnything() throws {
        let environment = [EnvironmentKey.variable: Self.key]
        func usage(_ fake: String?, _ live: Bool, _ environment: [String: String]) -> String? {
            do { _ = try SendTransportChoice.choose(fakeTransport: fake, live: live, environment: environment); return nil } catch {
                return "\(error)"
            }
        }
        XCTAssertEqual(usage("/tmp/fake", true, environment), "send takes --fake-transport DIR or --live, not both")
        XCTAssertEqual(usage(nil, false, environment), "send needs exactly one of --fake-transport DIR and --live")
        XCTAssertNil(usage("/tmp/fake", false, [:]), "the fake transport needs no key")
        XCTAssertNil(usage(nil, true, environment))
        for bad in [[:], [EnvironmentKey.variable: ""], [EnvironmentKey.variable: "   "]] {
            XCTAssertEqual(usage(nil, true, bad), "send --live: OPENROUTER_API_KEY is not set or is empty; --live reads the key from the environment only")
        }
        let malformed = "short key with spaces"
        let message = try XCTUnwrap(usage(nil, true, [EnvironmentKey.variable: malformed]))
        XCTAssertEqual(message, "send --live: OPENROUTER_API_KEY is not a well-formed key (its value is not shown)")
        XCTAssertFalse(message.contains(malformed))
        guard case let .live(key) = try SendTransportChoice.choose(fakeTransport: nil, live: true, environment: environment) else {
            return XCTFail("expected the live choice")
        }
        XCTAssertEqual(try key.load(), Self.key)
        guard case let .fake(directory) = try SendTransportChoice.choose(fakeTransport: "/tmp/fake", live: false, environment: [:]) else {
            return XCTFail("expected the fake choice")
        }
        XCTAssertEqual(directory, "/tmp/fake")
    }

    static func httpDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"
        return formatter.string(from: date)
    }
}

/// A clock that moves only when the sleeper is called, so retries never wait in tests.
final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current = Date(timeIntervalSince1970: 1_800_000_000)
    private var recorded: [TimeInterval] = []

    var now: Date { lock.withLock { current } }
    var sleeps: [TimeInterval] { lock.withLock { recorded } }

    func sleep(_ seconds: TimeInterval) {
        lock.withLock { recorded.append(seconds); current = current.addingTimeInterval(seconds) }
    }
}

/// A scripted transport: the catalogue GETs answer from the fixtures, and each POST takes the next
/// step. It records every request, so tests can check what carried the key. No network.
final class ScriptedTransport: LabelPhotoHTTPTransporting, @unchecked Sendable {
    enum Step: CustomStringConvertible {
        case reply(Int, [String: String], String)
        case fail(LabelPhotoTransportError)
        var description: String {
            switch self {
            case let .reply(status, _, body): "reply \(status) \(body.prefix(40))"
            case let .fail(error): "fail \(error)"
            }
        }
    }

    private let lock = NSLock()
    private var steps: [Step]
    private var recorded: [LabelPhotoHTTPRequest] = []

    init(_ steps: [Step]) { self.steps = steps }

    var requests: [LabelPhotoHTTPRequest] { lock.withLock { recorded } }
    var posts: Int { requests.filter { $0.method == "POST" }.count }

    func send(_ request: LabelPhotoHTTPRequest, timeout: TimeInterval, maximumBodyBytes: Int) async throws -> LabelPhotoHTTPResponse {
        lock.withLock { recorded.append(request) }
        if request.method == "GET" {
            let object = request.url == OpenRouterLabelRouteChecker.zeroDataRetentionURL ? Fixtures.zdr : Fixtures.listing
            return LabelPhotoHTTPResponse(status: 200, headers: [:], body: try JSONSerialization.data(withJSONObject: object), exceededLimit: false)
        }
        let step: Step? = lock.withLock { steps.isEmpty ? nil : steps.removeFirst() }
        switch step {
        case nil: throw LabelPhotoTransportError.failed
        case let .fail(error): throw error
        case let .reply(status, headers, body):
            return LabelPhotoHTTPResponse(status: status, headers: headers, body: Data(body.utf8), exceededLimit: false)
        }
    }
}
