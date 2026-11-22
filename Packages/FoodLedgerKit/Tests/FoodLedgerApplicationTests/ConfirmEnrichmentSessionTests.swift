import Foundation
import XCTest
@testable import FoodLedgerApplication
import FoodLedgerDomain
import FoodLedgerTestSupport

/// Confirm enrichment's session (docs/confirm-enrichment-openrouter-v1-phase.md sections 2.5, 2.6, 6 and 7:
/// G1, G3's session cases, G5 with scripted adapters, G13, G15 and G17's session cases), over the test
/// doubles in FoodLedgerTestSupport.
final class ConfirmEnrichmentSessionTests: XCTestCase {
    static let route = ConfirmEnrichmentRoute(
        part: .nutrients, version: ConfirmEnrichmentVersions.nutrientRoute, model: ConfirmEnrichmentFixtures.model,
        acceptedModels: [ConfirmEnrichmentFixtures.model], provider: ConfirmEnrichmentFixtures.provider, providerEndpoint: "azure",
        endpoint: ConfirmEnrichmentFixtures.endpoint, promptCeilingTokens: 6_000, completionCeilingTokens: 1_200,
        reasoningLimitTokens: 500, reasoningBilledSeparately: true, sendsMaxTokens: true)
    static let detailsRoute = ConfirmEnrichmentRoute(
        part: .details, version: ConfirmEnrichmentVersions.detailsRoute, model: "typesafe/jev-1.13", acceptedModels: ["typesafe/jev-1.13"],
        provider: "TypeSafe", providerEndpoint: "typesafe", endpoint: "https://example.invalid/v1/systemone",
        promptCeilingTokens: 4_000, completionCeilingTokens: 400, reasoningLimitTokens: 0, reasoningBilledSeparately: false,
        sendsMaxTokens: true)
    static let on = ConfirmEnrichmentSession.Preconditions(openRouterOn: true, enrichmentOn: true, keyState: .valid)
    static let locale = try! LedgerText("en_GB")

    struct Harness {
        let session: ConfirmEnrichmentSession
        let adapter: ConfirmEnrichmentTestAdapter
        let detailsAdapter: ConfirmEnrichmentTestAdapter
        let checker: ConfirmEnrichmentTestRouteChecker
        let cache: ConfirmEnrichmentTestCache
        let ledger: ConfirmEnrichmentTestLedger
        let egress: RecordingOpenRouterEgress
        let delaying: ConfirmEnrichmentTestDelaying
        let clock: ConfirmEnrichmentTestClock
    }

    func harness(_ results: [ConfirmEnrichmentAttemptResult], details: [ConfirmEnrichmentAttemptResult] = [],
                 checks: [ConfirmEnrichmentRouteCheckResult] = [.passed(ConfirmEnrichmentTestRouteChecker.cheap)],
                 egress: RecordingOpenRouterEgress = RecordingOpenRouterEgress(permits: true),
                 ledger: ConfirmEnrichmentTestLedger = ConfirmEnrichmentTestLedger(),
                 availability: ConfirmEnrichmentAvailability = ConfirmEnrichmentAvailability(details: true, nutrients: true),
                 adapterEgress: (any OpenRouterEgressPermitting)? = nil) -> Harness {
        let timing = ConfirmEnrichmentTestTiming()
        let adapter = ConfirmEnrichmentTestAdapter(results, use: .confirmEnrichmentNutrients, egress: adapterEgress ?? PermittingOpenRouterEgress(),
                                                   timing: timing)
        let detailsAdapter = ConfirmEnrichmentTestAdapter(details, use: .confirmEnrichmentDetails, timing: timing)
        let checker = ConfirmEnrichmentTestRouteChecker(checks)
        let cache = ConfirmEnrichmentTestCache()
        let delaying = ConfirmEnrichmentTestDelaying(timing: timing)
        let clock = ConfirmEnrichmentTestClock()
        let session = ConfirmEnrichmentSession(
            availability: availability, routes: .init(details: Self.detailsRoute, nutrients: Self.route), details: detailsAdapter,
            nutrients: adapter, checker: checker, cache: cache, ledger: ledger, egress: egress, delaying: delaying, timing: timing,
            jitter: ConfirmEnrichmentTestJitter(0.5), clock: clock, timeZone: TimeZone(identifier: "Europe/London")!,
            ids: ConfirmEnrichmentTestIDs(), digester: SHA256Digester())
        return Harness(session: session, adapter: adapter, detailsAdapter: detailsAdapter, checker: checker, cache: cache, ledger: ledger,
                       egress: egress, delaying: delaying, clock: clock)
    }

    func request(eligible: [NutrientKey] = [.fiber, .sodium]) throws -> ConfirmEnrichmentPolicy.NutrientRequest {
        let fixture = try ConfirmEnrichmentFixtures.inputs()
        let inputs = try ConfirmNutrientRequestInputs(description: fixture.description, identity: fixture.identity, basis: fixture.basis,
                                                      known: fixture.known, eligible: eligible)
        return try ConfirmEnrichmentPolicy.nutrientRequest(inputs, route: Self.route, encoder: FoundationCanonicalJSONEncoder(),
                                                           digester: SHA256Digester())
    }

    static func ok(_ values: [[String: Any]] = ConfirmEnrichmentFixtures.defaultValues(), withID: Bool = true) throws -> ConfirmEnrichmentAttemptResult {
        var bytes = try ConfirmEnrichmentFixtures.response(values: values)
        if !withID, var root = try JSONSerialization.jsonObject(with: bytes) as? [String: Any] {
            root["id"] = nil
            bytes = try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])
        }
        return .sent(status: 200, body: bytes, retryAfter: nil)
    }

    func answered(_ outcome: ConfirmEnrichmentSession.NutrientOutcome, file: StaticString = #filePath, line: UInt = #line) -> ConfirmNutrientSuggestion? {
        guard case let .answered(suggestion) = outcome else { XCTFail("not answered: \(outcome)", file: file, line: line); return nil }
        return suggestion
    }

    static func payload(_ evidence: CaptureEvidence) -> String {
        guard case let .text(text) = evidence.originalPayload else { return "" }
        return text.value
    }

    /// XCTest's assertions take autoclosures, which cannot await: these take plain arguments.
    func eq<T: Equatable>(_ a: T, _ b: T, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(a, b, message, file: file, line: line)
    }

    func notNil(_ value: Any?, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertNotNil(value, file: file, line: line)
    }

    // MARK: G1 Rebuild equals live

    func testACacheHitGivesTheSameCaptureAsTheLiveAnswerAndSendsNothing() async throws {
        for withID in [true, false] {
            let h = harness([try Self.ok(withID: withID)])
            let req = try request()
            guard let live = answered(await h.session.nutrients(req, mode: .automatic, preconditions: Self.on, locale: Self.locale)) else { return }
            XCTAssertFalse(live.fromCache)
            h.clock.advance(3_600)
            guard let hit = answered(await h.session.nutrients(req, mode: .automatic, preconditions: Self.on, locale: Self.locale)) else { return }
            XCTAssertTrue(hit.fromCache)
            XCTAssertEqual(h.adapter.bodies.count, 1, "a hit sends nothing")
            XCTAssertEqual(Self.payload(hit.capture), Self.payload(live.capture))
            XCTAssertEqual(hit.capture.byteHash, live.capture.byteHash)
            XCTAssertEqual(hit.capture.capturedAt, live.capture.capturedAt, "the cached received_at, never the time of the hit")
            XCTAssertEqual(try FoundationCanonicalJSONEncoder().encode(hit.capture.capturedAt),
                           try FoundationCanonicalJSONEncoder().encode(live.capture.capturedAt))
            let capture = try XCTUnwrap(ConfirmEnrichmentEvidence.nutrients(hit.capture))
            XCTAssertEqual(capture.generationID, withID ? "gen-synthetic-1" : nil)
            XCTAssertEqual(capture.requestBody, String(decoding: req.body, as: UTF8.self), "the wire body is the capture's request body")
        }
    }

    func testTheLiveTimeIsTruncatedToWholeMilliseconds() async throws {
        let h = harness([try Self.ok()])
        h.clock.set(Date(timeIntervalSince1970: 1_795_000_000.123_456))
        let live = answered(await h.session.nutrients(try request(), mode: .automatic, preconditions: Self.on, locale: Self.locale))
        XCTAssertEqual(live?.capture.capturedAt, ConfirmEnrichmentTime.truncated(Date(timeIntervalSince1970: 1_795_000_000.123)))
        XCTAssertEqual(ConfirmEnrichmentTime.text(live!.capture.capturedAt).suffix(5), ".123Z")
    }

    // MARK: G17 Preconditions

    func testNothingHappensWithoutBothSwitchesAndAValidKeyEvenForACachedSubject() async throws {
        let h = harness([try Self.ok()])
        let req = try request()
        _ = await h.session.nutrients(req, mode: .automatic, preconditions: Self.on, locale: Self.locale)
        for blocked in [ConfirmEnrichmentSession.Preconditions(openRouterOn: false, enrichmentOn: true, keyState: .valid),
                        .init(openRouterOn: true, enrichmentOn: false, keyState: .valid),
                        .init(openRouterOn: true, enrichmentOn: true, keyState: .notValidated),
                        .init(openRouterOn: true, enrichmentOn: true, keyState: .missing)] {
            let outcome = await h.session.nutrients(req, mode: .automatic, preconditions: blocked, locale: Self.locale)
            XCTAssertEqual(outcome, .failed(.silent))
        }
        XCTAssertEqual(h.adapter.bodies.count, 1)
    }

    func testAPartThatIsNotAvailableNeverStarts() async throws {
        let h = harness([try Self.ok()], availability: ConfirmEnrichmentAvailability(details: true, nutrients: false))
        eq(await h.session.nutrients(try request(), mode: .askAgain, preconditions: Self.on, locale: Self.locale), .failed(.silent))
        XCTAssertTrue(h.adapter.bodies.isEmpty)
        XCTAssertEqual(h.checker.checks, 0)
        XCTAssertEqual(ConfirmEnrichmentAvailability.inForce, ConfirmEnrichmentAvailability(details: false, nutrients: false),
                       "before the wiring PR the live session never starts")
    }

    func testAskAgainSkipsTheCacheSendsOnceAndReplacesTheEntry() async throws {
        let first = try Self.ok()
        let second = try Self.ok([["nutrient": "fiber", "value": 7, "unit": "g"]])
        let h = harness([first, second])
        let req = try request()
        _ = await h.session.nutrients(req, mode: .automatic, preconditions: Self.on, locale: Self.locale)
        let again = answered(await h.session.nutrients(req, mode: .askAgain, preconditions: Self.on, locale: Self.locale))
        XCTAssertEqual(h.adapter.bodies.count, 2)
        XCTAssertEqual(again?.kept, [.fiber: 7])
        let cached = answered(await h.session.nutrients(req, mode: .automatic, preconditions: Self.on, locale: Self.locale))
        XCTAssertEqual(cached?.kept, [.fiber: 7])
        XCTAssertEqual(h.cache.answers.count, 1)
    }

    func testCacheOnlyReadsTheCacheAndNeverSends() async throws {
        let h = harness([try Self.ok()])
        let req = try request()
        eq(await h.session.nutrients(req, mode: .cacheOnly, preconditions: Self.on, locale: Self.locale), .failed(.silent))
        XCTAssertTrue(h.adapter.bodies.isEmpty)
        _ = await h.session.nutrients(req, mode: .automatic, preconditions: Self.on, locale: Self.locale)
        eq(answered(await h.session.nutrients(req, mode: .cacheOnly, preconditions: Self.on, locale: Self.locale))?.fromCache, true)
        XCTAssertEqual(h.adapter.bodies.count, 1)
    }

    // MARK: G15 Cache writes

    func testAnAnswerThatKeepsNothingIsCachedAndAFailureIsNot() async throws {
        let h = harness([try Self.ok([["nutrient": "fiber", "value": -1, "unit": "g"]])])
        let req = try request()
        let kept = answered(await h.session.nutrients(req, mode: .automatic, preconditions: Self.on, locale: Self.locale))
        XCTAssertEqual(kept?.kept, [:])
        XCTAssertEqual(h.cache.answers.count, 1, "a validated answer that keeps no row is cached")
        let failing = harness([.sent(status: 200, body: Data("not json".utf8), retryAfter: nil)])
        eq(await failing.session.nutrients(req, mode: .automatic, preconditions: Self.on, locale: Self.locale), .failed(.notAvailable))
        XCTAssertTrue(failing.cache.answers.isEmpty)
    }

    func testACachedEntryWhoseBytesNoLongerPassIsAMissAndIsRemoved() async throws {
        let h = harness([try Self.ok(), try Self.ok()])
        let req = try request()
        _ = await h.session.nutrients(req, mode: .automatic, preconditions: Self.on, locale: Self.locale)
        let stored = try XCTUnwrap(h.cache.answers.first)
        h.cache.store(ConfirmEnrichmentCachedAnswer(subjectSHA256: stored.subjectSHA256, part: .nutrients, response: Data("{}".utf8),
                                                    responseSHA256: stored.responseSHA256, model: stored.model, provider: stored.provider,
                                                    costMicroUSD: nil, receivedAt: stored.receivedAt), now: h.clock.now())
        let outcome = answered(await h.session.nutrients(req, mode: .automatic, preconditions: Self.on, locale: Self.locale))
        XCTAssertEqual(outcome?.fromCache, false)
        XCTAssertEqual(h.adapter.bodies.count, 2)
    }

    func testACancelledRequestsAnswerIsDiscardedAndNeverCached() async throws {
        let h = harness([try Self.ok()])
        let req = try request()
        // Only Sendable values cross into the task: the actor and the request, never the harness.
        let session = h.session, on = Self.on, locale = Self.locale
        let task = Task { [session, req] in await session.nutrients(req, mode: .automatic, preconditions: on, locale: locale) }
        task.cancel()
        let outcome = await task.value
        XCTAssertNotEqual(outcome, .failed(.silent))
        if case .answered = outcome { XCTFail("a cancelled request showed an answer") }
        XCTAssertTrue(h.cache.answers.isEmpty)
    }

    func testTheAppLeavingTheForegroundStopsNewRequests() async throws {
        let h = harness([try Self.ok()])
        await h.session.appBecameInactive()
        eq(await h.session.nutrients(try request(), mode: .automatic, preconditions: Self.on, locale: Self.locale), .failed(.silent))
        XCTAssertTrue(h.adapter.bodies.isEmpty)
        await h.session.appBecameActive()
        notNil(answered(await h.session.nutrients(try request(), mode: .automatic, preconditions: Self.on, locale: Self.locale)))
    }

    // MARK: G13 Time

    func testTheDebounceWaitsOneAndAHalfSecondsAndAStoppedWaitSendsNothing() async throws {
        let h = harness([try Self.ok()])
        let passed = await h.session.debounce()
        XCTAssertTrue(passed)
        XCTAssertEqual(h.delaying.waits, [1.5])
        h.delaying.cancelWaits()
        let stopped = await h.session.debounce()
        XCTAssertFalse(stopped)
    }

    // MARK: G3 Spend, session cases

    func testAReservationIsMadeAtTheWholeCapAndReconciledToTheReportedCost() async throws {
        let h = harness([try Self.ok()])
        _ = await h.session.nutrients(try request(), mode: .automatic, preconditions: Self.on, locale: Self.locale)
        let day = try XCTUnwrap(h.ledger.day)
        XCTAssertEqual(day.requests, 1)
        XCTAssertEqual(day.settledMicroUSD, 1_200, "0.0012 reported")
        XCTAssertTrue(day.openRequests.isEmpty)
        XCTAssertEqual(day.paused, [])
    }

    func testTheHundredAndFirstRequestIsRefusedWithoutAGateCallOrASend() async throws {
        let ledger = ConfirmEnrichmentTestLedger(.day(.init(localDay: "2026-11-18", requests: 100)))
        let egress = RecordingOpenRouterEgress(permits: true)
        let h = harness([try Self.ok()], egress: egress, ledger: ledger)
        h.clock.set(Date(timeIntervalSince1970: 1_795_000_000))  // 2026-11-18 in London
        eq(await h.session.nutrients(try request(), mode: .automatic, preconditions: Self.on, locale: Self.locale),
                       .failed(.limitReached))
        XCTAssertTrue(egress.uses.isEmpty)
        XCTAssertTrue(h.adapter.bodies.isEmpty)
    }

    func testARequestThatWouldTakeTheDayPastFiftyCentsDoesNotStart() async throws {
        let ledger = ConfirmEnrichmentTestLedger(.day(.init(localDay: "2026-11-18", requests: 10, settledMicroUSD: 480_001)))
        let h = harness([try Self.ok()], ledger: ledger)
        h.clock.set(Date(timeIntervalSince1970: 1_795_000_000))
        eq(await h.session.nutrients(try request(), mode: .automatic, preconditions: Self.on, locale: Self.locale),
                       .failed(.limitReached))
        XCTAssertTrue(h.adapter.bodies.isEmpty)
    }

    func testAnUnreadableLedgerClosesTheDayAtOnceAndSendsNothing() async throws {
        let ledger = ConfirmEnrichmentTestLedger(.unreadable)
        let h = harness([try Self.ok()], ledger: ledger)
        eq(await h.session.nutrients(try request(), mode: .automatic, preconditions: Self.on, locale: Self.locale),
                       .failed(.limitReached))
        XCTAssertEqual(ledger.day?.requests, ConfirmEnrichmentSpendPolicy.dailyRequestLimit)
        XCTAssertTrue(h.adapter.bodies.isEmpty)
    }

    func testAFailedReservationWriteSendsNothing() async throws {
        let ledger = ConfirmEnrichmentTestLedger()
        ledger.failWrites(1)
        let h = harness([try Self.ok()], ledger: ledger)
        eq(await h.session.nutrients(try request(), mode: .automatic, preconditions: Self.on, locale: Self.locale),
                       .failed(.limitReached))
        XCTAssertTrue(h.adapter.bodies.isEmpty)
    }

    func testAGateRefusalBeforeTheFirstAttemptReleasesTheReservation() async throws {
        let h = harness([try Self.ok()], adapterEgress: RecordingOpenRouterEgress(permits: false))
        eq(await h.session.nutrients(try request(), mode: .automatic, preconditions: Self.on, locale: Self.locale),
                       .failed(.notPermitted))
        let day = try XCTUnwrap(h.ledger.day)
        XCTAssertEqual(day.requests, 0)
        XCTAssertTrue(day.openRequests.isEmpty)
        XCTAssertTrue(h.adapter.bodies.isEmpty)
    }

    func testAGateRefusalOfTheSecondAttemptEndsWithExactlyOneSend() async throws {
        let adapterGate = RecordingOpenRouterEgress(permits: true, then: [false])
        let h = harness([.sent(status: 503, body: Data(), retryAfter: nil), try Self.ok()], adapterEgress: adapterGate)
        eq(await h.session.nutrients(try request(), mode: .automatic, preconditions: Self.on, locale: Self.locale),
                       .failed(.notPermittedAfterSending))
        XCTAssertEqual(h.adapter.bodies.count, 1)
        let day = try XCTUnwrap(h.ledger.day)
        XCTAssertEqual(day.requests, 1)
        XCTAssertTrue(day.openRequests.isEmpty, "only the sent attempt is reconciled")
    }

    func testTheGateIsAskedForTheRequestUseAndTheCatalogueUse() async throws {
        let egress = RecordingOpenRouterEgress(permits: true)
        let h = harness([try Self.ok()], egress: egress)
        _ = await h.session.nutrients(try request(), mode: .automatic, preconditions: Self.on, locale: Self.locale)
        XCTAssertEqual(egress.uses, [.confirmEnrichmentNutrients, .confirmEnrichmentNutrientsCatalogueCheck])
    }

    func testAnAttemptReportedAboveWPausesThePartForTheDay() async throws {
        var root = try XCTUnwrap(JSONSerialization.jsonObject(with: ConfirmEnrichmentFixtures.response(values: ConfirmEnrichmentFixtures.defaultValues()))
                                 as? [String: Any])
        root["usage"] = ["cost": 0.019, "prompt_tokens": 410]
        let bytes = try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])
        let h = harness([.sent(status: 200, body: bytes, retryAfter: nil)])
        _ = await h.session.nutrients(try request(), mode: .automatic, preconditions: Self.on, locale: Self.locale)
        let day = try XCTUnwrap(h.ledger.day)
        XCTAssertEqual(day.paused, [.nutrients])
        XCTAssertEqual(day.settledMicroUSD, 19_000, "reconciled to the full reported amount")
        eq(await h.session.nutrients(try request(eligible: [.fiber]), mode: .automatic, preconditions: Self.on, locale: Self.locale),
                       .failed(.limitReached))
    }

    /// An adapter that makes the ledger refuse the next writes once it has sent: the attempt mark and
    /// both settlement writes fail.
    struct FailingSettleAdapter: NutrientEstimateSuggesting {
        let ledger: ConfirmEnrichmentTestLedger
        let reply: ConfirmEnrichmentAttemptResult
        func attempt(_ body: Data, timeout: TimeInterval) async -> ConfirmEnrichmentAttemptResult {
            ledger.failWrites(3)
            return reply
        }
    }

    func testAFailedReconcileIsRetriedOnceThenThePartClosesForTheAppSession() async throws {
        let ledger = ConfirmEnrichmentTestLedger()
        let timing = ConfirmEnrichmentTestTiming()
        let session = ConfirmEnrichmentSession(
            availability: .init(details: true, nutrients: true), routes: .init(details: Self.detailsRoute, nutrients: Self.route),
            details: ConfirmEnrichmentTestAdapter([], use: .confirmEnrichmentDetails),
            nutrients: FailingSettleAdapter(ledger: ledger, reply: try Self.ok()), checker: ConfirmEnrichmentTestRouteChecker(),
            cache: ConfirmEnrichmentTestCache(), ledger: ledger, egress: PermittingOpenRouterEgress(),
            delaying: ConfirmEnrichmentTestDelaying(timing: timing), timing: timing, jitter: ConfirmEnrichmentTestJitter(),
            clock: ConfirmEnrichmentTestClock(), timeZone: TimeZone(identifier: "Europe/London")!, ids: ConfirmEnrichmentTestIDs(),
            digester: SHA256Digester())
        _ = await session.nutrients(try request(), mode: .automatic, preconditions: Self.on, locale: Self.locale)
        XCTAssertEqual(ledger.day?.openRequests.count, 1, "the reservation stays, counted at its cap")
        eq(await session.nutrients(try request(eligible: [.fiber]), mode: .askAgain, preconditions: Self.on, locale: Self.locale),
                       .failed(.limitReached), "the part is closed for the app session")
    }

    func testAKillBetweenReservationAndReplyLeavesTheRequestCountedAtItsCap() throws {
        let day = try XCTUnwrap(ConfirmEnrichmentSpendPolicy.reserved(.nutrients, requestID: "r1", day: .init(localDay: "2026-11-21")))
        XCTAssertEqual(day.requests, 1)
        XCTAssertEqual(day.openMicroUSD, 20_000)
        XCTAssertEqual(ConfirmEnrichmentSpendPolicy.admission(.nutrients, day: day), .allowed)
    }

    func testAClockMovedBackResetsNothing() async throws {
        let ledger = ConfirmEnrichmentTestLedger(.day(.init(localDay: "2026-11-25", requests: 100)))
        let h = harness([try Self.ok()], ledger: ledger)
        h.clock.set(Date(timeIntervalSince1970: 1_795_000_000))  // 2026-11-18, earlier than the stored day
        eq(await h.session.nutrients(try request(), mode: .automatic, preconditions: Self.on, locale: Self.locale),
                       .failed(.limitReached))
        XCTAssertTrue(h.adapter.bodies.isEmpty)
    }

    // MARK: Retries

    func testATransientFailureIsRetriedWithBackoffWithinTheCaps() async throws {
        let h = harness([.sent(status: 503, body: Data(), retryAfter: nil), .transportFailed(.timedOut), try Self.ok()])
        notNil(answered(await h.session.nutrients(try request(), mode: .automatic, preconditions: Self.on, locale: Self.locale)))
        XCTAssertEqual(h.adapter.bodies.count, 3)
        XCTAssertEqual(h.delaying.waits, [1.5, 3.0], "1 s and 2 s doubled bases with jitter 0.5")
        XCTAssertEqual(Set(h.adapter.bodies).count, 1, "identical bytes on every attempt")
        let day = try XCTUnwrap(h.ledger.day)
        XCTAssertEqual(day.requests, 1, "a request counts once whatever its retries")
    }

    func testRetryAfterIsHonouredAndAContentFailureIsNeverRetried() async throws {
        let h = harness([.sent(status: 429, body: Data(), retryAfter: "4"), try Self.ok()])
        _ = await h.session.nutrients(try request(), mode: .automatic, preconditions: Self.on, locale: Self.locale)
        XCTAssertEqual(h.delaying.waits, [4])
        let content = harness([.sent(status: 400, body: Data(), retryAfter: nil), try Self.ok()])
        eq(await content.session.nutrients(try request(), mode: .automatic, preconditions: Self.on, locale: Self.locale),
                       .failed(.notAvailable))
        XCTAssertEqual(content.adapter.bodies.count, 1)
    }

    func testAtMostThreeAttemptsAndUnreportedAttemptsAreChargedW() async throws {
        let h = harness([.transportFailed(.connectionFailed)])
        eq(await h.session.nutrients(try request(), mode: .automatic, preconditions: Self.on, locale: Self.locale),
                       .failed(.notAvailable))
        XCTAssertEqual(h.adapter.bodies.count, 3)
        let w = ConfirmEnrichmentSpendPolicy.worstCase(Self.route, prices: ConfirmEnrichmentTestRouteChecker.cheap)
        XCTAssertEqual(h.ledger.day?.settledMicroUSD, 3 * w)
    }

    func testOverloadedEnvelopesAreRetried() async throws {
        let overloaded = try JSONSerialization.data(withJSONObject: ["error": ["code": 529, "message": "overloaded"]])
        let h = harness([.sent(status: 200, body: overloaded, retryAfter: nil), try Self.ok()])
        notNil(answered(await h.session.nutrients(try request(), mode: .automatic, preconditions: Self.on, locale: Self.locale)))
        XCTAssertEqual(h.adapter.bodies.count, 2)
    }

    // MARK: G14 Route check (session cases)

    func testTheRouteCheckRunsOncePerDayAndAgainAfterAConnectionFailure() async throws {
        let h = harness([try Self.ok()], checks: [.connectionFailed, .passed(ConfirmEnrichmentTestRouteChecker.cheap)])
        eq(await h.session.nutrients(try request(), mode: .automatic, preconditions: Self.on, locale: Self.locale),
                       .failed(.notAvailable))
        XCTAssertNil(h.ledger.day, "a failed check reserves nothing")
        _ = await h.session.nutrients(try request(), mode: .automatic, preconditions: Self.on, locale: Self.locale)
        _ = await h.session.nutrients(try request(eligible: [.fiber]), mode: .automatic, preconditions: Self.on, locale: Self.locale)
        XCTAssertEqual(h.checker.checks, 2)
        h.clock.advance(24 * 3_600)
        _ = await h.session.nutrients(try request(eligible: [.sodium]), mode: .automatic, preconditions: Self.on, locale: Self.locale)
        XCTAssertEqual(h.checker.checks, 3, "a new local day checks again")
    }

    func testAFailedCheckOrADayWhosePricesExceedTheCapMakesThePartUnavailable() async throws {
        let expensive = ConfirmEnrichmentPrices(promptPerTokenUSD: Decimal(string: "0.00001")!, completionPerTokenUSD: Decimal(string: "0.00001")!)
        for check in [ConfirmEnrichmentRouteCheckResult.unavailable, .passed(expensive)] {
            let h = harness([try Self.ok()], checks: [check, .passed(ConfirmEnrichmentTestRouteChecker.cheap)])
            eq(await h.session.nutrients(try request(), mode: .automatic, preconditions: Self.on, locale: Self.locale),
                           .failed(.notAvailable))
            eq(await h.session.nutrients(try request(), mode: .askAgain, preconditions: Self.on, locale: Self.locale),
                           .failed(.notAvailable))
            XCTAssertEqual(h.checker.checks, 1)
            XCTAssertTrue(h.adapter.bodies.isEmpty)
        }
    }

    func testACatalogueRefusalSendsNothingAndLeavesThePartAvailable() async throws {
        let egress = RecordingOpenRouterEgress(permits: true, then: [false, true, true])
        let h = harness([try Self.ok()], egress: egress)
        eq(await h.session.nutrients(try request(), mode: .automatic, preconditions: Self.on, locale: Self.locale),
                       .failed(.notPermitted))
        XCTAssertEqual(h.checker.checks, 0)
        XCTAssertNil(h.ledger.day)
        notNil(answered(await h.session.nutrients(try request(), mode: .automatic, preconditions: Self.on, locale: Self.locale)))
    }

    // MARK: A

    func testADetailsAnswerPreFillsOnlyConfidentKnownChoicesAndAgreesWithTheEntryState() async throws {
        let description = ConfirmEnrichmentFixtures.description()
        let inputs = try ConfirmDetailsRequestInputs(description: description, knownDetails: [:], asked: [.preparation, .bone, .fortification])
        let req = try ConfirmEnrichmentPolicy.detailsRequest(inputs, route: Self.detailsRoute, encoder: FoundationCanonicalJSONEncoder(),
                                                             digester: SHA256Digester())
        func reply(_ preparation: String) throws -> ConfirmEnrichmentAttemptResult {
            let answers: [String: Any] = [
                "preparation": ["type": "choice", "choice": preparation, "confidence": 0.9, "probabilities": [preparation: 0.9]],
                "bone": ["type": "choice", "choice": "not_applicable", "confidence": 0.5, "probabilities": ["not_applicable": 0.5]],
                "fortification": ["type": "choice", "choice": "unknown", "confidence": 0.99, "probabilities": ["unknown": 0.99]],
            ]
            return .sent(status: 200, body: try JSONSerialization.data(withJSONObject: [
                "id": "gen-a", "model": "typesafe/jev-1.13", "provider": "TypeSafe", "answers": answers]), retryAfter: nil)
        }
        let h = harness([], details: [try reply("as_sold")])
        guard case let .answered(suggestion) = await h.session.details(req, mode: .automatic, preconditions: Self.on, locale: Self.locale) else {
            return XCTFail("not answered")
        }
        XCTAssertEqual(suggestion.applied, [.preparation: "as_sold"])
        let capture = try XCTUnwrap(ConfirmEnrichmentEvidence.details(suggestion.capture))
        XCTAssertEqual(capture.applied, ["preparation"])
        XCTAssertEqual(capture.threshold, "0.85")
        let raw = harness([], details: [try reply("raw")])
        guard case let .answered(refused) = await raw.session.details(req, mode: .automatic, preconditions: Self.on, locale: Self.locale,
                                                                     entryState: .cooked) else { return XCTFail("not answered") }
        XCTAssertEqual(refused.applied, [:], "a raw preparation that disagrees with a cooked entry is not pre-filled")
    }

    // MARK: The Confirm tracker

    func testOneConfirmAsksASubjectOnceAndBForAtMostTwoSubjects() {
        var tracker = ConfirmEnrichmentConfirmTracker()
        XCTAssertFalse(tracker.offersAskAgain(.nutrients))
        XCTAssertTrue(tracker.mayAskAutomatically(.nutrients, subject: "a"))
        tracker.recordAsked(.nutrients, subject: "a")
        XCTAssertFalse(tracker.mayAskAutomatically(.nutrients, subject: "a"))
        XCTAssertTrue(tracker.mayAskAutomatically(.nutrients, subject: "b"))
        tracker.recordAsked(.nutrients, subject: "b")
        XCTAssertFalse(tracker.mayAskAutomatically(.nutrients, subject: "c"), "a third subject is not asked automatically")
        XCTAssertTrue(tracker.offersAskAgain(.nutrients))
        tracker.recordAsked(.details, subject: "x")
        XCTAssertFalse(tracker.mayAskAutomatically(.details, subject: "x"))
        XCTAssertTrue(tracker.mayAskAutomatically(.details, subject: "y"), "A: once per subject, so a new match is asked")
    }
}
