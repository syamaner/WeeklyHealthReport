import Foundation
import FoodLedgerApplication
import FoodGenericSearch
import FoodLedgerTestSupport
import XCTest

/// #500: the web lookup model-call retry loop in the OpenRouter adapter, with a scripted
/// transport, an injected clock and a recording sleeper. No network, no real waiting.
final class OpenRouterFoodRetryTests: XCTestCase {
    private let key = "synthetic-test-key-never-real-12345"
    private let leads = [FoodWebLead(title: "Synthetic food", url: URL(string: "https://example.com/food")!)]

    func testTransientFailuresAreResentWithIdenticalBytesUntilSuccess() async throws {
        let script = Script([.status(503, retryAfter: nil), .urlError(.timedOut), .ok(try success())])
        let decision = try await provider(script).chooseSource(foodTerms: "synthetic food", leads: leads, key: key)
        XCTAssertEqual(decision, .selected(index: 0, purpose: .primaryProduct, reason: "exact_product_primary_lead"))
        let requests = await script.requests
        XCTAssertEqual(requests.count, 3)
        for request in requests.dropFirst() {
            XCTAssertEqual(request.url, requests[0].url)
            XCTAssertEqual(request.httpMethod, requests[0].httpMethod)
            XCTAssertEqual(request.httpBody, requests[0].httpBody)
            XCTAssertEqual(request.allHTTPHeaderFields, requests[0].allHTTPHeaderFields)
        }
        let waits = await script.waits
        XCTAssertEqual(waits, [1, 2])
    }

    func testEveryRetryableClassIsRetriedAndStopsAfterThreeAttempts() async throws {
        let transient: [Step] = [.urlError(.notConnectedToInternet), .urlError(.timedOut)]
            + [408, 429, 500, 502, 503, 504].map { .status($0, retryAfter: nil) }
            + [.envelope(code: 503)]
        let expected: [FoodWebDiscoveryError] = [.connectionFailed, .timedOut, .serviceUnavailable, .quotaExceeded,
            .serviceUnavailable, .serviceUnavailable, .serviceUnavailable, .serviceUnavailable, .serviceUnavailable]
        for (step, error) in zip(transient, expected) {
            let fresh = Script([step, step, step, step])
            do { _ = try await provider(fresh).chooseSource(foodTerms: "synthetic food", leads: leads, key: key); XCTFail("Expected failure") }
            catch let thrown { XCTAssertEqual(thrown as? FoodWebDiscoveryError, error, "\(step)") }
            let count = await fresh.requests.count
            XCTAssertEqual(count, 3, "\(step)")
        }
    }

    func testKeyRejectionCreditLimitRejectedRequestsAndContentFailuresAreNeverRetried() async throws {
        let steps: [(Step, FoodWebDiscoveryError)] = [
            (.status(401, retryAfter: nil), .credentialRejected), (.status(403, retryAfter: nil), .permissionDenied),
            (.status(402, retryAfter: "1"), .quotaExceeded), (.status(400, retryAfter: nil), .requestRejected),
            (.status(404, retryAfter: nil), .requestRejected), (.status(422, retryAfter: nil), .requestRejected),
            (.envelope(code: 401), .credentialRejected), (.envelope(code: 402), .quotaExceeded),
            (.ok(try success(model: "other/model")), .invalidResponse),
            (.ok(Data(key.utf8)), .invalidResponse), (.envelopeWithChoices(code: 503), .serviceUnavailable),
            (.transportRejected, .invalidResponse)]
        for (step, expected) in steps {
            let script = Script([step, .ok(try success())])
            do { _ = try await provider(script).chooseSource(foodTerms: "synthetic food", leads: leads, key: key); XCTFail("Expected failure \(step)") }
            catch { XCTAssertEqual(error as? FoodWebDiscoveryError, expected, "\(step)") }
            let count = await script.requests.count
            XCTAssertEqual(count, 1, "\(step)")
            let waits = await script.waits
            XCTAssertTrue(waits.isEmpty)
        }
    }

    func testRetryAfterIsHonouredAndALongWaitIsNotMade() async throws {
        let honoured = Script([.status(429, retryAfter: "7"), .ok(try success())])
        _ = try await provider(honoured).chooseSource(foodTerms: "synthetic food", leads: leads, key: key)
        let waits = await honoured.waits
        XCTAssertEqual(waits, [7])
        let long = Script([.status(429, retryAfter: "60"), .ok(try success())])
        do { _ = try await provider(long).chooseSource(foodTerms: "synthetic food", leads: leads, key: key); XCTFail("Expected failure") }
        catch { XCTAssertEqual(error as? FoodWebDiscoveryError, .quotaExceeded) }
        let count = await long.requests.count
        XCTAssertEqual(count, 1)
    }

    func testWholeCallDeadlineStopsRetriesAndShortensTheLastAttempt() async throws {
        let late = Script([.status(503, retryAfter: nil), .ok(try success())], secondsPerAttempt: 119.5)
        do { _ = try await provider(late).chooseSource(foodTerms: "synthetic food", leads: leads, key: key); XCTFail("Expected failure") }
        catch { XCTAssertEqual(error as? FoodWebDiscoveryError, .serviceUnavailable) }
        let lateCount = await late.requests.count
        XCTAssertEqual(lateCount, 1)
        let slow = Script([.urlError(.timedOut), .ok(try success())], secondsPerAttempt: 90)
        _ = try await provider(slow).chooseSource(foodTerms: "synthetic food", leads: leads, key: key)
        let timeouts = await slow.requests.map(\.timeoutInterval)
        XCTAssertEqual(timeouts, [90, 29])
    }

    func testALateWakeUpNeverStartsAnAttemptPastTheDeadline() async throws {
        let late = Script([.status(503, retryAfter: nil), .ok(try success())], secondsPerAttempt: 100, extraSleep: 25)
        do { _ = try await provider(late).chooseSource(foodTerms: "synthetic food", leads: leads, key: key); XCTFail("Expected failure") }
        catch { XCTAssertEqual(error as? FoodWebDiscoveryError, .serviceUnavailable) }
        let count = await late.requests.count
        XCTAssertEqual(count, 1)
        let shortened = Script([.status(503, retryAfter: nil), .ok(try success())], secondsPerAttempt: 100, extraSleep: 1)
        _ = try await provider(shortened).chooseSource(foodTerms: "synthetic food", leads: leads, key: key)
        let timeouts = await shortened.requests.map(\.timeoutInterval)
        XCTAssertEqual(timeouts, [90, 18])
        // A wake-up that leaves less than the minimum attempt time sends nothing further.
        let tooLittle = Script([.status(503, retryAfter: nil), .ok(try success())], secondsPerAttempt: 100, extraSleep: 5)
        do { _ = try await provider(tooLittle).chooseSource(foodTerms: "synthetic food", leads: leads, key: key); XCTFail("Expected failure") }
        catch { XCTAssertEqual(error as? FoodWebDiscoveryError, .serviceUnavailable) }
        let tooLittleCount = await tooLittle.requests.count
        XCTAssertEqual(tooLittleCount, 1)
    }

    func testARetryableStatusIsRetriedWhateverItsBody() async throws {
        let bodies = [Data([0xff, 0xfe, 0x00]), Data(key.utf8), Data(repeating: 0x41, count: 300_000)]
        for body in bodies {
            let script = Script([.statusBody(503, body), .statusBody(429, body), .ok(try success())])
            let decision = try await provider(script).chooseSource(foodTerms: "synthetic food", leads: leads, key: key)
            XCTAssertEqual(decision, .selected(index: 0, purpose: .primaryProduct, reason: "exact_product_primary_lead"))
            let count = await script.requests.count
            XCTAssertEqual(count, 3)
        }
        // A non-retryable status with an echoed key still fails closed and is never retried.
        let echoed = Script([.statusBody(400, Data(key.utf8)), .ok(try success())])
        do { _ = try await provider(echoed).chooseSource(foodTerms: "synthetic food", leads: leads, key: key); XCTFail("Expected failure") }
        catch { XCTAssertEqual(error as? FoodWebDiscoveryError, .invalidResponse) }
        let echoedCount = await echoed.requests.count
        XCTAssertEqual(echoedCount, 1)
    }

    func testCancellationDuringTheWaitSendsNothingFurther() async throws {
        let script = Script([.status(503, retryAfter: nil), .ok(try success())], blockSleep: true)
        let provider = provider(script)
        let leads = leads, key = key
        let task = Task { try await provider.chooseSource(foodTerms: "synthetic food", leads: leads, key: key) }
        await script.waitUntilSleeping()
        task.cancel()
        do { _ = try await task.value; XCTFail("Expected cancellation") }
        catch { XCTAssertTrue(error is CancellationError, "\(error)") }
        let count = await script.requests.count
        XCTAssertEqual(count, 1)
    }

    func testDisabledRetryAndKeyValidationMakeExactlyOneAttempt() async throws {
        let disabled = Script([.status(503, retryAfter: nil), .ok(try success())])
        let single = OpenRouterFoodProvider(egress: PermittingOpenRouterEgress(), transport: { try await disabled.send($0) })
        do { _ = try await single.chooseSource(foodTerms: "synthetic food", leads: leads, key: key); XCTFail("Expected failure") }
        catch { XCTAssertEqual(error as? FoodWebDiscoveryError, .serviceUnavailable) }
        let disabledCount = await disabled.requests.count
        XCTAssertEqual(disabledCount, 1)
        let validation = Script([.status(503, retryAfter: nil), .ok(Data(#"{"data":{}}"#.utf8))])
        do { try await provider(validation).validate(key: key); XCTFail("Expected failure") }
        catch { XCTAssertEqual(error as? FoodWebDiscoveryError, .serviceUnavailable) }
        let validationCount = await validation.requests.count
        XCTAssertEqual(validationCount, 1)
    }

    // MARK: - Fixtures

    // MARK: O1 consent (docs/openrouter-single-consent-v1-amendment.md O1.2, O1.6 test 2)

    /// A refusal on attempt 2 of a retried request, asked after the backoff wait: exactly one send,
    /// exactly one wait, `.notPermitted`, and nothing after the refusal.
    func testARefusalAfterTheBackoffWaitEndsWithOneSendAndOneWait() async throws {
        let script = Script([.status(503, retryAfter: nil), .ok(try success())])
        let egress = RecordingOpenRouterEgress(permits: true, then: [false])
        do { _ = try await provider(script, egress: egress).chooseSource(foodTerms: "synthetic food", leads: leads, key: key); XCTFail("Expected a refusal") }
        catch { XCTAssertEqual(error as? FoodWebDiscoveryError, .notPermitted) }
        let count = await script.requests.count
        XCTAssertEqual(count, 1)
        let waits = await script.waits
        XCTAssertEqual(waits.count, 1)
        XCTAssertEqual(egress.uses, [.webLookup, .webLookup])
    }

    private func provider(_ script: Script, egress: any OpenRouterEgressPermitting = PermittingOpenRouterEgress()) -> OpenRouterFoodProvider {
        OpenRouterFoodProvider(egress: egress, retry: OpenRouterFoodRetry(enabled: true, now: { script.clock.now },
            sleep: { try await script.sleep($0) }, jitter: { 1 })) { try await script.send($0) }
    }

    private func success(model: String = "openai/gpt-6-luna") throws -> Data {
        let content = String(decoding: try JSONSerialization.data(withJSONObject: ["version": "offline-lead-selection-v2",
            "decision": "select", "selected_index": 0, "reason": "exact_product_primary_lead"], options: .sortedKeys), as: UTF8.self)
        return try JSONSerialization.data(withJSONObject: ["model": model, "provider": "Azure",
            "choices": [["finish_reason": "stop", "message": ["role": "assistant", "content": content]]]])
    }

    enum Step: CustomStringConvertible {
        case ok(Data), status(Int, retryAfter: String?), statusBody(Int, Data), urlError(URLError.Code), envelope(code: Int), envelopeWithChoices(code: Int), transportRejected
        var description: String {
            switch self {
            case .ok: "ok"
            case let .status(status, _): "status \(status)"
            case let .statusBody(status, _): "status \(status) with body"
            case let .urlError(code): "url error \(code.rawValue)"
            case .transportRejected: "transport rejected the reply"
            case let .envelope(code): "envelope \(code)"
            case let .envelopeWithChoices(code): "envelope with choices \(code)"
            }
        }
    }

    final class ManualClock: @unchecked Sendable {
        private let lock = NSLock()
        private var value = Date(timeIntervalSince1970: 1_800_000_000)
        var now: Date { lock.lock(); defer { lock.unlock() }; return value }
        func advance(_ seconds: TimeInterval) { lock.lock(); value += seconds; lock.unlock() }
    }

    actor Script {
        nonisolated let clock = ManualClock()
        private var steps: [Step]
        private let secondsPerAttempt: TimeInterval
        private let blockSleep: Bool
        private let extraSleep: TimeInterval
        private(set) var requests: [URLRequest] = []
        private(set) var waits: [TimeInterval] = []
        private var sleeping: CheckedContinuation<Void, Never>?
        private var sleepStarted = false

        init(_ steps: [Step], secondsPerAttempt: TimeInterval = 0, blockSleep: Bool = false, extraSleep: TimeInterval = 0) {
            self.steps = steps; self.secondsPerAttempt = secondsPerAttempt; self.blockSleep = blockSleep
            self.extraSleep = extraSleep
        }

        func send(_ request: URLRequest) throws -> OpenRouterFoodHTTPReply {
            requests.append(request)
            clock.advance(secondsPerAttempt)
            let step = steps.isEmpty ? .status(500, retryAfter: nil) : steps.removeFirst()
            switch step {
            case let .ok(data): return .init(status: 200, data: data)
            case let .status(status, retryAfter): return .init(status: status, data: Data("{}".utf8), retryAfter: retryAfter)
            case let .statusBody(status, data): return .init(status: status, data: data)
            case let .urlError(code): throw URLError(code)
            case .transportRejected: throw FoodWebDiscoveryError.invalidResponse
            case let .envelope(code):
                return .init(status: 200, data: Data(#"{"error":{"code":\#(code),"message":"synthetic"}}"#.utf8))
            case let .envelopeWithChoices(code):
                return .init(status: 200, data: Data(#"{"error":{"code":\#(code)},"choices":[]}"#.utf8))
            }
        }

        func sleep(_ seconds: TimeInterval) async throws {
            waits.append(seconds)
            clock.advance(seconds + extraSleep)
            if blockSleep {
                sleepStarted = true
                if let sleeping { self.sleeping = nil; sleeping.resume() }
                try await Task.sleep(nanoseconds: 60_000_000_000)
            }
        }

        func waitUntilSleeping() async {
            if sleepStarted { return }
            await withCheckedContinuation { sleeping = $0 }
        }
    }
}
