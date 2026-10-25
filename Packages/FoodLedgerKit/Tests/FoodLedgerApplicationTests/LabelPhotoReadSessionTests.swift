import FoodLedgerApplication
import Foundation
import XCTest

/// The read orchestrator (docs/label-photo-ai-prefill-v1.md E4, E7, E9 to E11, 17.5; contract
/// tests 9, 21, 22 and 26 as the orchestrator applies them). Fakes only: no network.
final class LabelPhotoReadSessionTests: XCTestCase {
    final class Clock: LedgerClock, @unchecked Sendable {
        var value = Date(timeIntervalSince1970: 1_792_900_000)
        func now() -> Date { value }
    }

    final class Checker: LabelPhotoRouteChecking, @unchecked Sendable {
        var result: Result<LabelPhotoManifest.CatalogueCheck, Error>
        var calls = 0
        init(_ result: Result<LabelPhotoManifest.CatalogueCheck, Error>) { self.result = result }
        func check(_ route: LabelPhotoRoute.Route) async throws -> LabelPhotoManifest.CatalogueCheck { calls += 1; return try result.get() }
    }

    final class Attempter: LabelPhotoAttempting, @unchecked Sendable {
        var script: [LabelPhotoAttemptResult]
        var timeouts: [TimeInterval] = []
        var cancelDuring: Int?
        /// When set, an attempt waits here until the test resumes it (an attempt that never returns).
        var hold: CheckedContinuation<Void, Never>?
        var holds = false
        var during: (() -> Void)?
        let clock: Clock
        init(_ script: [LabelPhotoAttemptResult], clock: Clock) { self.script = script; self.clock = clock }
        func attempt(_ image: PreparedLabelImage, timeout: TimeInterval) async -> LabelPhotoAttemptResult {
            timeouts.append(timeout)
            if holds { holds = false; await withCheckedContinuation { hold = $0 } }
            during?()
            clock.value += 5
            if cancelDuring == timeouts.count { withUnsafeCurrentTask { $0?.cancel() } }
            return script.isEmpty ? .failed(.contentFailure, failure: .failed, reportedCost: nil, promptTokens: nil) : script.removeFirst()
        }
        func manifestRequest(catalogue: LabelPhotoManifest.CatalogueCheck) -> LabelPhotoManifest.Request {
            LabelPhotoManifest.Request(model: catalogue.slug, endpoint: catalogue.endpoint, reasoningLimit: 500, maxOutputTokens: 1_200,
                                       instructionVersion: "label-photo-instruction-v1", instructionSHA256: String(repeating: "a", count: 64),
                                       wireSchemaVersion: "label-photo-wire-schema-v1", wireSchemaSHA256: String(repeating: "b", count: 64),
                                       catalogueCheck: catalogue)
        }
    }

    final class Sleeper: LabelPhotoSleeping, @unchecked Sendable {
        var sleeps: [TimeInterval] = []
        var fail = false
        /// Extra seconds the clock moves during a sleep (the device was suspended).
        var overrun: TimeInterval = 0
        let clock: Clock
        init(clock: Clock) { self.clock = clock }
        func sleep(seconds: TimeInterval) async throws {
            if fail { throw CancellationError() }
            sleeps.append(seconds); clock.value += seconds + overrun
        }
    }

    final class Ledger: LabelPhotoSpendLedger, @unchecked Sendable {
        struct WriteFailed: Error {}
        var stored: LabelPhotoSpendPolicy.Stored = .absent
        var failsWrites = false
        /// Fails only this many further writes, then succeeds.
        var failNextWrites = 0
        var writes = 0
        private let lock = NSLock()
        func load() -> LabelPhotoSpendPolicy.Stored { lock.withLock { stored } }
        @discardableResult
        func update(_ transform: (LabelPhotoSpendPolicy.Stored) throws -> LabelPhotoSpendPolicy.Day) throws -> LabelPhotoSpendPolicy.Day {
            try lock.withLock {
                let day = try transform(stored)
                if failsWrites { throw WriteFailed() }
                if failNextWrites > 0 { failNextWrites -= 1; throw WriteFailed() }
                writes += 1; stored = .day(day)
                return day
            }
        }
        var day: LabelPhotoSpendPolicy.Day? { if case let .day(day) = stored { day } else { nil } }
    }

    final class Keys: FoodWebKeyStoring, @unchecked Sendable {
        var key: String? = "sk-or-v1-0123456789abcdef0123456789abcdef"
        func load() throws -> String? { key }
        func save(_ key: String) throws { self.key = key }
        func delete() throws { key = nil }
    }

    static let good = LabelPhotoManifest.CatalogueCheck(at: 1, slug: "google/gemini-4-argon", endpoint: "google-vertex",
        inputModalities: ["text", "image"], zeroDataRetention: true, promptPrice: "0.000002", completionPrice: "0.00001")
    static let usage = LabelPhotoManifest.Usage(promptTokens: 2_000, completionTokens: 600, reasoningTokens: nil, costUSD: "0.01")
    static let answer = LabelPhotoAttemptResult.answered(wireText: "{}", model: "google/gemini-4-argon", provider: "Google Vertex",
                                                         generationID: "gen-1", finishReason: "stop", usage: usage)
    static func failed(_ outcome: LabelPhotoRetryPolicy.Outcome, cost: Decimal? = nil) -> LabelPhotoAttemptResult {
        .failed(outcome, failure: .providerUnavailable, reportedCost: cost, promptTokens: nil)
    }

    var image: PreparedLabelImage {
        try! PreparedLabelImageFactory.make(bytes: Data([1, 2, 3]), pixelWidth: 10, pixelHeight: 10, jpegQuality: "0.85",
                                            digester: SHA256Digester())
    }

    var calendar: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "Asia/Taipei")!; return c }

    func makeSession(_ script: [LabelPhotoAttemptResult], checker: Checker = Checker(.success(good)), ledger: Ledger = Ledger(),
                     keys: Keys = Keys(), clock: Clock = Clock())
        -> (LabelPhotoReadSession, Attempter, Checker, Ledger, Sleeper) {
        let attempter = Attempter(script, clock: clock)
        let sleeper = Sleeper(clock: clock)
        let session = LabelPhotoReadSession(checker: checker, attempter: attempter, ledger: ledger, keys: keys, clock: clock,
                                            calendar: calendar, sleeper: sleeper, jitter: { 0 })
        return (session, attempter, checker, ledger, sleeper)
    }

    // MARK: Catalogue check (test 22)

    func testTheCatalogueCheckRunsOncePerSessionBeforeAnyImageRequest() async {
        let (session, attempter, checker, _, _) = makeSession([Self.answer, Self.answer])
        guard case let .answered(_, request) = await session.read(image) else { return XCTFail() }
        XCTAssertEqual(request.catalogueCheck, Self.good, "the answer carries the session's catalogue check")
        guard case .answered = await session.read(image) else { return XCTFail() }
        XCTAssertEqual(checker.calls, 1)
        XCTAssertEqual(attempter.timeouts.count, 2)
    }

    func testACatalogueFailureOrMismatchSendsNothing() async {
        let mismatches = [
            LabelPhotoManifest.CatalogueCheck(at: 1, slug: "google/gemini-4-argon", endpoint: "google-ai-studio", inputModalities: ["image"],
                                              zeroDataRetention: true, promptPrice: "0.000002", completionPrice: "0.00001"),
            LabelPhotoManifest.CatalogueCheck(at: 1, slug: "google/gemini-4-argon", endpoint: "google-vertex", inputModalities: ["text"],
                                              zeroDataRetention: true, promptPrice: "0.000002", completionPrice: "0.00001"),
            LabelPhotoManifest.CatalogueCheck(at: 1, slug: "google/gemini-4-argon", endpoint: "google-vertex", inputModalities: ["image"],
                                              zeroDataRetention: false, promptPrice: "0.000002", completionPrice: "0.00001"),
            // Prices whose worst case exceeds $0.05.
            LabelPhotoManifest.CatalogueCheck(at: 1, slug: "google/gemini-4-argon", endpoint: "google-vertex", inputModalities: ["image"],
                                              zeroDataRetention: true, promptPrice: "0.00001", completionPrice: "0.00004"),
        ]
        for check in mismatches {
            let (session, attempter, _, ledger, _) = makeSession([Self.answer], checker: Checker(.success(check)))
            let outcome = await session.read(image)
            XCTAssertEqual(outcome, .failed(.routeUnavailable))
            XCTAssertTrue(attempter.timeouts.isEmpty, "nothing sent")
            XCTAssertNil(ledger.day)
        }
        let (session, attempter, _, _, _) = makeSession([Self.answer], checker: Checker(.failure(URLError(.notConnectedToInternet))))
        let outcome = await session.read(image)
        XCTAssertEqual(outcome, .failed(.routeUnavailable))
        XCTAssertTrue(attempter.timeouts.isEmpty)
    }

    // MARK: Admission (tests 10 and 26)

    func testTheDaysAdmissionComesFirst() async {
        let unreadable = Ledger(); unreadable.stored = .unreadable
        let (closed, attempter, checker, _, _) = makeSession([Self.answer], ledger: unreadable)
        let closedOutcome = await closed.read(image)
        XCTAssertEqual(closedOutcome, .failed(.dailyLimit))
        XCTAssertEqual(checker.calls, 0)
        XCTAssertTrue(attempter.timeouts.isEmpty)
        let paused = Ledger(); paused.stored = .day(.init(day: "2026-10-25", reads: 1, cost: 0.01, paused: true))
        let (pausedSession, _, _, _, _) = makeSession([Self.answer], ledger: paused)
        let pausedOutcome = await pausedSession.read(image)
        XCTAssertEqual(pausedOutcome, .failed(.paused))
    }

    func testAnAnswerIsRecordedAndAnInputOverTheCeilingPausesTheDay() async {
        let over = LabelPhotoManifest.Usage(promptTokens: 6_001, completionTokens: 600, reasoningTokens: nil, costUSD: "0.01")
        let (session, _, _, ledger, _) = makeSession([.answered(wireText: "{}", model: "google/gemini-4-argon", provider: "Google Vertex",
                                                            generationID: "gen-1", finishReason: "stop", usage: over)])
        guard case let .answered(reply, _) = await session.read(image) else { return XCTFail() }
        XCTAssertEqual(reply.attempts, 1)
        XCTAssertEqual(ledger.day?.reads, 1)
        XCTAssertEqual(ledger.day?.cost, Decimal(string: "0.01"))
        XCTAssertEqual(ledger.day?.paused, true)
        let next = await session.read(image)
        XCTAssertEqual(next, .failed(.paused))
    }

    // MARK: Retry and the per-tap budget (tests 9 and 21)

    func testRetryableFailuresRetryWithTheClampedTimeout() async {
        let (session, attempter, _, ledger, sleeper) = makeSession([Self.failed(.httpStatus(503, retryAfter: "3"), cost: 0), Self.answer])
        guard case let .answered(reply, _) = await session.read(image) else { return XCTFail() }
        XCTAssertEqual(reply.attempts, 2)
        XCTAssertEqual(sleeper.sleeps, [3])
        XCTAssertEqual(attempter.timeouts, [45, 45])
        // A rejected attempt reported at zero, then $0.01: the day counts $0.01.
        XCTAssertEqual(ledger.day?.cost, Decimal(string: "0.01"))
    }

    func testContentFailuresAreNeverRetried() async {
        let (session, attempter, _, _, _) = makeSession([.failed(.contentFailure, failure: .unreadableAnswer, reportedCost: Decimal(string: "0.01"),
                                                            promptTokens: 2_000), Self.answer])
        let outcome = await session.read(image)
        XCTAssertEqual(outcome, .failed(.unreadableAnswer))
        XCTAssertEqual(attempter.timeouts.count, 1)
    }

    func testNoAttemptStartsPastTheTapBudget() async {
        // Unreported failures are charged W ($0.024): two fit in $0.05, a third would not.
        let (session, attempter, _, ledger, _) = makeSession([Self.failed(.transportError), Self.failed(.transportError), Self.answer])
        let outcome = await session.read(image)
        XCTAssertEqual(outcome, .failed(.providerUnavailable))
        XCTAssertEqual(attempter.timeouts.count, 2)
        XCTAssertEqual(ledger.day?.cost, Decimal(string: "0.05"), "E10: a tap with an unreported attempt counts at least $0.05")
    }

    // MARK: Cancel

    func testCancelStopsAtOnceAndIsCharged() async {
        let (session, attempter, _, ledger, sleeper) = makeSession([Self.failed(.transportError), Self.answer])
        attempter.cancelDuring = 1
        let prepared = image
        let outcome = await Task { [session, prepared] in await session.read(prepared) }.value
        XCTAssertEqual(outcome, .failed(.cancelled))
        XCTAssertEqual(attempter.timeouts.count, 1)
        XCTAssertTrue(sleeper.sleeps.isEmpty)
        XCTAssertEqual(ledger.day?.reads, 1)
        XCTAssertEqual(ledger.day?.cost, Decimal(string: "0.05"))
        // Cancelled while waiting to retry: no further attempt.
        let (waiting, waitingAttempter, _, _, waitingSleeper) = makeSession([Self.failed(.transportError), Self.answer])
        waitingSleeper.fail = true
        let waited = await waiting.read(image)
        XCTAssertEqual(waited, .failed(.cancelled))
        XCTAssertEqual(waitingAttempter.timeouts.count, 1)
    }

    // MARK: #326 review: reservation, fail closed, concurrency, deadline, key, day

    func testTheTapIsReservedBeforeTheFirstSendAndSurvivesAnAttemptThatNeverReturns() async throws {
        let ledger = Ledger(); ledger.stored = .day(.init(day: "2026-10-25", reads: 3, cost: Decimal(string: "0.10")!, paused: false))
        let (session, attempter, _, _, _) = makeSession([Self.answer], ledger: ledger)
        attempter.holds = true
        let prepared = image
        let task = Task { [session, prepared] in await session.read(prepared) }
        while attempter.hold == nil { await Task.yield() }
        // The attempt is in flight and has not returned: the reservation is already stored.
        XCTAssertEqual(ledger.day, .init(day: "2026-10-25", reads: 4, cost: Decimal(string: "0.15")!, paused: false))
        attempter.hold?.resume()
        _ = await task.value
        // Reconciled down to the reported $0.01.
        XCTAssertEqual(ledger.day, .init(day: "2026-10-25", reads: 4, cost: Decimal(string: "0.11")!, paused: false))
    }

    func testTheReservationIsReconciledUpwards() async {
        let dear = LabelPhotoManifest.Usage(promptTokens: 2_000, completionTokens: 600, reasoningTokens: nil, costUSD: "0.07")
        let (session, _, _, ledger, _) = makeSession([.answered(wireText: "{}", model: "google/gemini-4-argon", provider: "Google Vertex",
                                                                generationID: "g", finishReason: "stop", usage: dear)])
        _ = await session.read(image)
        XCTAssertEqual(ledger.day?.cost, Decimal(string: "0.07"))
        XCTAssertEqual(ledger.day?.paused, true, "a reported cost over $0.05 pauses the day")
    }

    func testAFailedLedgerWriteClosesTheRouteForTheSession() async {
        let ledger = Ledger(); ledger.failsWrites = true
        let (session, attempter, _, _, _) = makeSession([Self.answer, Self.answer], ledger: ledger)
        let first = await session.read(image)
        XCTAssertEqual(first, .failed(.dailyLimit))
        XCTAssertTrue(attempter.timeouts.isEmpty, "nothing is sent without a reservation")
        ledger.failsWrites = false
        let second = await session.read(image)
        XCTAssertEqual(second, .failed(.dailyLimit), "refused for the rest of the session")
        XCTAssertTrue(attempter.timeouts.isEmpty)
        // A write that fails at the end of a tap also closes the route, keeping the reservation.
        let late = Ledger()
        let (lateSession, lateAttempter, _, _, _) = makeSession([Self.answer, Self.answer], ledger: late)
        lateAttempter.during = { late.failsWrites = true }
        _ = await lateSession.read(image)
        XCTAssertEqual(late.day?.cost, Decimal(string: "0.05"), "the reservation stays")
        late.failsWrites = false
        let after = await lateSession.read(image)
        XCTAssertEqual(after, .failed(.dailyLimit))
    }

    func testAConcurrentTapIsRefusedSoTheDayCannotBeExceeded() async {
        let ledger = Ledger(); ledger.stored = .day(.init(day: "2026-10-25", reads: 29, cost: Decimal(string: "0.45")!, paused: false))
        let (session, attempter, _, _, _) = makeSession([Self.answer, Self.answer], ledger: ledger)
        attempter.holds = true
        let prepared = image
        let first = Task { [session, prepared] in await session.read(prepared) }
        while attempter.hold == nil { await Task.yield() }
        let second = await session.read(prepared)
        XCTAssertEqual(second, .failed(.failed))
        attempter.hold?.resume()
        _ = await first.value
        XCTAssertEqual(attempter.timeouts.count, 1)
        XCTAssertEqual(ledger.day?.reads, 30)
        let third = await session.read(prepared)
        XCTAssertEqual(third, .failed(.dailyLimit))
    }

    func testAnUnreadableLedgerAtTheEndIsNeverOverwritten() async {
        let ledger = Ledger()
        let (session, attempter, _, _, _) = makeSession([Self.answer], ledger: ledger)
        attempter.during = { ledger.stored = .unreadable }
        _ = await session.read(image)
        XCTAssertEqual(ledger.stored, .unreadable)
        let next = await session.read(image)
        XCTAssertEqual(next, .failed(.dailyLimit))
    }

    func testNoAttemptStartsWithNoTimeLeft() async {
        let (session, attempter, _, _, sleeper) = makeSession([Self.failed(.httpStatus(503, retryAfter: "1"), cost: 0), Self.answer])
        sleeper.overrun = 90   // suspended past the whole-call deadline while waiting to retry
        let outcome = await session.read(image)
        XCTAssertEqual(outcome, .failed(.timedOut))
        XCTAssertEqual(attempter.timeouts.count, 1)
    }

    func testAMissingOrMalformedKeySendsNothingNotEvenTheCatalogueCheck() async {
        for key in [nil, "short", String(repeating: "k", count: 30) + " x"] as [String?] {
            let keys = Keys(); keys.key = key
            let (session, attempter, checker, ledger, _) = makeSession([Self.answer], keys: keys)
            let outcome = await session.read(image)
            XCTAssertEqual(outcome, .failed(.keyMissing))
            XCTAssertEqual(checker.calls, 0)
            XCTAssertTrue(attempter.timeouts.isEmpty)
            XCTAssertNil(ledger.day)
        }
    }

    func testTheCatalogueCheckRunsAgainOnANewLocalDay() async {
        let clock = Clock()
        let (session, _, checker, _, _) = makeSession([Self.answer, Self.answer, Self.answer], clock: clock)
        _ = await session.read(image)
        _ = await session.read(image)
        XCTAssertEqual(checker.calls, 1)
        clock.value += 86_400
        _ = await session.read(image)
        XCTAssertEqual(checker.calls, 2)
    }

    // MARK: #326 re-check: two sessions on one ledger, and the retried write

    func testTwoSessionsOnOneLedgerKeepEachOthersSpend() async {
        // Start 10 / $0.10. A reserves; B reserves; B finishes at $0.01; A finishes unreported.
        let ledger = Ledger(); ledger.stored = .day(.init(day: "2026-10-25", reads: 10, cost: Decimal(string: "0.10")!, paused: false))
        let (a, attemptsA, _, _, _) = makeSession([Self.failed(.transportError), Self.failed(.transportError)], ledger: ledger)
        let (b, attemptsB, _, _, _) = makeSession([Self.answer], ledger: ledger)
        attemptsA.holds = true; attemptsB.holds = true
        let prepared = image
        let tapA = Task { [a, prepared] in await a.read(prepared) }
        while attemptsA.hold == nil { await Task.yield() }
        let tapB = Task { [b, prepared] in await b.read(prepared) }
        while attemptsB.hold == nil { await Task.yield() }
        XCTAssertEqual(ledger.day, .init(day: "2026-10-25", reads: 12, cost: Decimal(string: "0.20")!, paused: false), "both reserved")
        attemptsB.hold?.resume()
        _ = await tapB.value
        attemptsA.hold?.resume()
        _ = await tapA.value
        XCTAssertEqual(ledger.day, .init(day: "2026-10-25", reads: 12, cost: Decimal(string: "0.16")!, paused: false))
    }

    func testAReleaseNeverWipesAnotherSessionsReservation() async {
        let ledger = Ledger(); ledger.stored = .day(.init(day: "2026-10-25", reads: 10, cost: Decimal(string: "0.10")!, paused: false))
        let (a, attemptsA, _, _, _) = makeSession([Self.answer], ledger: ledger)
        let (b, _, _, _, _) = makeSession([.notSent(.cancelled)], ledger: ledger)
        attemptsA.holds = true
        let prepared = image
        let tapA = Task { [a, prepared] in await a.read(prepared) }
        while attemptsA.hold == nil { await Task.yield() }
        _ = await b.read(prepared)   // reserves, sends nothing, releases
        XCTAssertEqual(ledger.day, .init(day: "2026-10-25", reads: 11, cost: Decimal(string: "0.15")!, paused: false), "A's reservation kept")
        attemptsA.hold?.resume()
        _ = await tapA.value
        XCTAssertEqual(ledger.day, .init(day: "2026-10-25", reads: 11, cost: Decimal(string: "0.11")!, paused: false))
    }

    func testAFailedReconcileWriteIsRetriedOnce() async {
        let ledger = Ledger()
        let (session, attempter, _, _, _) = makeSession([Self.answer, Self.answer], ledger: ledger)
        attempter.during = { ledger.failNextWrites = 1 }
        _ = await session.read(image)
        XCTAssertEqual(ledger.day?.cost, Decimal(string: "0.01"), "reconciled on the retry")
        attempter.during = nil
        guard case .answered = await session.read(image) else { return XCTFail("the route stays open") }
    }
}
