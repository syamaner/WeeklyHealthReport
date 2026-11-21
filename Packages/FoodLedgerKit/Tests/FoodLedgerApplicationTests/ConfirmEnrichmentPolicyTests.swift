import Foundation
import XCTest
@testable import FoodLedgerApplication
import FoodLedgerDomain
import FoodLedgerTestSupport

/// The pure spend, retry and cache policies and the request builder rules of Confirm enrichment
/// (docs/confirm-enrichment-openrouter-v1-phase.md sections 2.5, 2.6, 3.2 and 7: G2's policy cases, G3,
/// G13 and G14's builder cases).
final class ConfirmEnrichmentPolicyTests: XCTestCase {
    let route = ConfirmEnrichmentSessionTests.route

    // MARK: G3 Spend policy

    func testMoneyIsWholeMicroDollarsRoundedUp() {
        XCTAssertEqual(ConfirmEnrichmentSpendPolicy.microUSD(Decimal(string: "0.0012")!), 1_200)
        XCTAssertEqual(ConfirmEnrichmentSpendPolicy.microUSD(Decimal(string: "0.00000001")!), 1)
        XCTAssertEqual(ConfirmEnrichmentSpendPolicy.microUSD(0), 0)
    }

    func testWIsSizedFromTheDaysPricesAndTheRouteCeilings() {
        let prices = ConfirmEnrichmentPrices(promptPerTokenUSD: Decimal(string: "0.000001")!, completionPerTokenUSD: Decimal(string: "0.000002")!)
        // 6,000 * 1e-6 + (1,200 + 500) * 2e-6 = 0.0094
        XCTAssertEqual(ConfirmEnrichmentSpendPolicy.worstCase(route, prices: prices), 9_400)
        let doubled = ConfirmEnrichmentPrices(promptPerTokenUSD: Decimal(string: "0.000002")!, completionPerTokenUSD: Decimal(string: "0.000004")!)
        XCTAssertEqual(ConfirmEnrichmentSpendPolicy.worstCase(route, prices: doubled), 18_800, "W changes with the day's prices alone")
        XCTAssertTrue(ConfirmEnrichmentSpendPolicy.routeFits(route, prices: doubled))
    }

    func testRetriesAreGatedByAttemptsChargedNeverTheReservation() {
        XCTAssertTrue(ConfirmEnrichmentSpendPolicy.mayStartAttempt([], w: 9_000, part: .nutrients))
        XCTAssertTrue(ConfirmEnrichmentSpendPolicy.mayStartAttempt([.init(reportedMicroUSD: 1_000, promptTokens: nil)], w: 9_000, part: .nutrients))
        XCTAssertFalse(ConfirmEnrichmentSpendPolicy.mayStartAttempt([.init(reportedMicroUSD: nil, promptTokens: nil)], w: 11_000, part: .nutrients),
                       "an unreported attempt is charged W")
        XCTAssertFalse(ConfirmEnrichmentSpendPolicy.mayStartAttempt([], w: 10_001, part: .details))
    }

    func testReservationReconcileAndReleaseAreIdempotentPerRequest() throws {
        let start = ConfirmEnrichmentSpendPolicy.Day(localDay: "2026-11-21")
        let reserved = try XCTUnwrap(ConfirmEnrichmentSpendPolicy.reserved(.details, requestID: "r1", day: start))
        XCTAssertEqual(reserved.openRequests.first?.chargedMicroUSD, 10_000)
        XCTAssertNil(ConfirmEnrichmentSpendPolicy.reserved(.details, requestID: "r1", day: reserved))
        let sent = ConfirmEnrichmentSpendPolicy.attemptSent("r1", day: reserved)
        let attempts = [ConfirmEnrichmentSpendPolicy.Attempt(reportedMicroUSD: 300, promptTokens: 200)]
        let settled = try XCTUnwrap(ConfirmEnrichmentSpendPolicy.reconciled("r1", attempts: attempts, w: 3_000, route: route, day: sent))
        XCTAssertEqual(settled.settledMicroUSD, 300)
        XCTAssertEqual(settled.requests, 1)
        XCTAssertNil(ConfirmEnrichmentSpendPolicy.reconciled("r1", attempts: attempts, w: 3_000, route: route, day: settled))
        XCTAssertNil(ConfirmEnrichmentSpendPolicy.released("r1", day: settled))
        let other = try XCTUnwrap(ConfirmEnrichmentSpendPolicy.reserved(.nutrients, requestID: "r2", day: settled))
        let released = try XCTUnwrap(ConfirmEnrichmentSpendPolicy.released("r2", day: other))
        XCTAssertEqual(released.requests, 1)
        XCTAssertTrue(released.openRequests.isEmpty)
    }

    func testThePauseTrigger() throws {
        func pauses(_ attempts: [ConfirmEnrichmentSpendPolicy.Attempt], w: Int, part: ConfirmEnrichmentPart = .details) throws -> Bool {
            let day = try XCTUnwrap(ConfirmEnrichmentSpendPolicy.reserved(part, requestID: "r", day: .init(localDay: "2026-11-21")))
            return try XCTUnwrap(ConfirmEnrichmentSpendPolicy.reconciled("r", attempts: attempts, w: w, route: route, day: day)).paused == [part]
        }
        XCTAssertTrue(try pauses([.init(reportedMicroUSD: 4_000, promptTokens: nil)], w: 3_000), "W 3,000, reported 4,000, cap 10,000")
        XCTAssertFalse(try pauses([.init(reportedMicroUSD: 2_000, promptTokens: nil)], w: 3_000))
        XCTAssertTrue(try pauses([.init(reportedMicroUSD: 6_000, promptTokens: nil), .init(reportedMicroUSD: 6_000, promptTokens: nil)], w: 9_000),
                      "the request's total above its cap")
        XCTAssertTrue(try pauses([.init(reportedMicroUSD: 100, promptTokens: 6_001)], w: 3_000), "prompt tokens above the ceiling")
        let day = try XCTUnwrap(ConfirmEnrichmentSpendPolicy.reserved(.details, requestID: "r", day: .init(localDay: "2026-11-21")))
        let paused = try XCTUnwrap(ConfirmEnrichmentSpendPolicy.reconciled("r", attempts: [.init(reportedMicroUSD: 4_000, promptTokens: nil)],
                                                                          w: 3_000, route: route, day: day))
        XCTAssertEqual(ConfirmEnrichmentSpendPolicy.admission(.details, day: paused), .paused)
        XCTAssertEqual(ConfirmEnrichmentSpendPolicy.admission(.nutrients, day: paused), .allowed, "that part only")
        XCTAssertEqual(paused.settledMicroUSD, 4_000, "reconciled above the reservation, never clamped")
    }

    func testTheDayRules() {
        let stored = ConfirmEnrichmentSpendPolicy.Day(localDay: "2026-11-20", requests: 40, settledMicroUSD: 10)
        XCTAssertEqual(ConfirmEnrichmentSpendPolicy.current(today: "2026-11-21", stored: .day(stored)).requests, 0, "a later day starts fresh")
        XCTAssertEqual(ConfirmEnrichmentSpendPolicy.current(today: "2026-11-19", stored: .day(stored)), stored, "a clock moved back keeps it")
        XCTAssertEqual(ConfirmEnrichmentSpendPolicy.current(today: "2026-11-21", stored: .absent), .init(localDay: "2026-11-21"))
        XCTAssertEqual(ConfirmEnrichmentSpendPolicy.current(today: "2026-11-21", stored: .unreadable).requests, 100, "fails closed")
        XCTAssertEqual(ConfirmEnrichmentSpendPolicy.admission(.details, day: .init(localDay: "d", requests: 99)), .allowed)
        XCTAssertEqual(ConfirmEnrichmentSpendPolicy.admission(.details, day: .init(localDay: "d", requests: 100)), .limitReached)
        XCTAssertEqual(ConfirmEnrichmentSpendPolicy.admission(.nutrients, day: .init(localDay: "d", settledMicroUSD: 480_001)), .limitReached)
        XCTAssertEqual(ConfirmEnrichmentSpendPolicy.admission(.nutrients, day: .init(localDay: "d", settledMicroUSD: 480_000)), .allowed)
        XCTAssertEqual(ConfirmEnrichmentSpendPolicy.dayKey(Date(timeIntervalSince1970: 1_795_000_000), timeZone: TimeZone(identifier: "Asia/Taipei")!),
                       "2026-11-18")
    }

    func testTheDayRecordIsAClosedFormat() throws {
        let day = ConfirmEnrichmentSpendPolicy.Day(localDay: "2026-11-21", requests: 2, settledMicroUSD: 5, paused: [.nutrients],
                                                   openRequests: [.init(requestID: "r", part: .details, chargedMicroUSD: 10_000, attemptsSent: 1)])
        let bytes = try FoundationCanonicalJSONEncoder().encode(day)
        XCTAssertEqual(String(decoding: bytes, as: UTF8.self),
                       #"{"local_day":"2026-11-21","open_requests":[{"attempts_sent":1,"charged_microusd":10000,"part":"details","request_id":"r"}],"paused":["nutrients"],"requests":2,"schema":"confirm-enrichment-day-v1","settled_microusd":5}"#)
        XCTAssertEqual(try JSONDecoder().decode(ConfirmEnrichmentSpendPolicy.Day.self, from: bytes), day)
        for altered in [#"{"local_day":"2026-11-21","open_requests":[],"paused":[],"requests":2,"schema":"confirm-enrichment-day-v2","settled_microusd":5}"#,
                        #"{"local_day":"2026-11-21","open_requests":[],"paused":[],"requests":2,"schema":"confirm-enrichment-day-v1","settled_microusd":5,"extra":1}"#,
                        #"{"local_day":"2026-11-21","open_requests":[],"paused":[],"requests":-1,"schema":"confirm-enrichment-day-v1","settled_microusd":5}"#] {
            XCTAssertThrowsError(try JSONDecoder().decode(ConfirmEnrichmentSpendPolicy.Day.self, from: Data(altered.utf8)))
        }
    }

    // MARK: G13 Retry policy

    func testRetryClassesAndRetryAfterInBothForms() {
        let now = Date(timeIntervalSince1970: 1_795_000_000)
        XCTAssertEqual(ConfirmEnrichmentRetryPolicy.next(afterAttempt: 1, outcome: .httpStatus(503, retryAfter: "7"), elapsed: 2, now: now, jitter: 0),
                       .retry(after: 7))
        let date = "Wed, 18 Nov 2026 11:06:50 GMT"
        if case let .retry(after) = ConfirmEnrichmentRetryPolicy.next(afterAttempt: 1, outcome: .httpStatus(429, retryAfter: date), elapsed: 2,
                                                                      now: now, jitter: 0) {
            XCTAssertEqual(after, 10, accuracy: 1)
        } else { XCTFail("an HTTP-date Retry-After was not honoured") }
        XCTAssertEqual(ConfirmEnrichmentRetryPolicy.next(afterAttempt: 1, outcome: .httpStatus(400, retryAfter: nil), elapsed: 2, now: now, jitter: 0), .stop)
        XCTAssertEqual(ConfirmEnrichmentRetryPolicy.next(afterAttempt: 1, outcome: .contentFailure, elapsed: 2, now: now, jitter: 0), .stop)
        XCTAssertEqual(ConfirmEnrichmentRetryPolicy.next(afterAttempt: 3, outcome: .timedOut, elapsed: 2, now: now, jitter: 0), .stop)
        XCTAssertEqual(ConfirmEnrichmentRetryPolicy.next(afterAttempt: 1, outcome: .httpStatus(503, retryAfter: "70"), elapsed: 2, now: now, jitter: 0),
                       .stop, "a wait past the 60 s deadline stops")
        XCTAssertEqual(ConfirmEnrichmentRetryPolicy.attemptTimeout(elapsed: 45), 15)
        XCTAssertEqual(ConfirmEnrichmentRetryPolicy.attemptTimeout(elapsed: 0), 30)
        for status in [408, 429, 500, 502, 503, 504] { XCTAssertTrue(ConfirmEnrichmentRetryPolicy.isRetryable(.httpStatus(status, retryAfter: nil))) }
    }

    // MARK: Cache policy (G2's policy cases)

    func testTheCacheFileIsExactlyTheApprovedValue() throws {
        let answer = ConfirmEnrichmentCachedAnswer(subjectSHA256: String(repeating: "a", count: 64), part: .details, response: Data("{}".utf8),
                                                   responseSHA256: String(repeating: "b", count: 64), model: "m", provider: "p",
                                                   costMicroUSD: nil, receivedAt: ConfirmEnrichmentTime.truncated(Date(timeIntervalSince1970: 1_795_000_000.5)))
        let bytes = try ConfirmEnrichmentCachePolicy.encode([answer], encoder: FoundationCanonicalJSONEncoder())
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        XCTAssertEqual(Set(root.keys), ["schema", "entries"])
        let entry = try XCTUnwrap((root["entries"] as? [[String: Any]])?.first)
        XCTAssertEqual(Set(entry.keys), ["subject_sha256", "part", "response", "response_sha256", "model", "provider", "cost_microusd", "received_at"])
        XCTAssertEqual(entry["received_at"] as? String, "2026-11-18T11:06:40.500Z")
        XCTAssertEqual(ConfirmEnrichmentCachePolicy.decode(bytes), [answer])
        var extra = root
        extra["note"] = "x"
        XCTAssertNil(ConfirmEnrichmentCachePolicy.decode(try JSONSerialization.data(withJSONObject: extra)))
        var unknown = root
        unknown["schema"] = "confirm-enrichment-cache-v2"
        XCTAssertNil(ConfirmEnrichmentCachePolicy.decode(try JSONSerialization.data(withJSONObject: unknown)))
        XCTAssertNil(ConfirmEnrichmentCachePolicy.decode(Data("{".utf8)))
        let many = (0..<501).map { _ in answer }
        XCTAssertNil(ConfirmEnrichmentCachePolicy.decode(try ConfirmEnrichmentCachePolicy.encode(many, encoder: FoundationCanonicalJSONEncoder())))
    }

    func testTheDoublesPassTheSharedPortSuites() async {
        XCTAssertEqual(ConfirmEnrichmentPortContracts.cacheViolations { ConfirmEnrichmentTestCache() }, [])
        XCTAssertEqual(ConfirmEnrichmentPortContracts.ledgerViolations { ConfirmEnrichmentTestLedger($0) }, [])
        let delaying = await ConfirmEnrichmentPortContracts.delayingViolations(ConfirmEnrichmentTestDelaying())
        XCTAssertTrue(delaying.isEmpty || delaying == ["cancel: did not throw"], "\(delaying)")
        XCTAssertEqual(ConfirmEnrichmentPortContracts.timingViolations(ConfirmEnrichmentTestTiming(), jitter: ConfirmEnrichmentTestJitter(0.3)), [])
        let attempt = await ConfirmEnrichmentPortContracts.attemptViolations(use: .confirmEnrichmentNutrients, { egress in
            NutrientAttempting(ConfirmEnrichmentTestAdapter([.sent(status: 200, body: Data(), retryAfter: nil)], use: .confirmEnrichmentNutrients,
                                                            egress: egress))
        }, body: Data("{}".utf8))
        XCTAssertEqual(attempt, [])
    }

    // MARK: Builder rules

    func testTheDenyGateRefusesPersonalAndPaymentText() {
        func description(_ name: String) -> ConfirmEnrichmentDescription {
            ConfirmEnrichmentDescription(name: name, brand: nil, variant: nil, category: nil, productType: nil, state: nil, source: .yourFoodDatabase)
        }
        XCTAssertTrue(ConfirmEnrichmentPolicy.passesDenyGate(description("Oat bar 4 x 30g")))
        for name in ["Oat bar for someone@example.com", "Oat bar 07700 900123", "Oat bar SW1A 1AA", "Order 12345678 oats",
                     "Oat bar £2.50", "Oat bar 3.20 GBP", "Oat bar payment", "Account oat bar"] {
            XCTAssertFalse(ConfirmEnrichmentPolicy.passesDenyGate(description(name)), name)
        }
    }

    func testABodyOverItsPromptCeilingIsRefusedBeforeSending() throws {
        let long = ConfirmEnrichmentDescription(name: String(repeating: "oat ", count: 2_000), brand: nil, variant: nil, category: nil,
                                                productType: nil, state: nil, source: .compositionTable)
        let inputs = try ConfirmNutrientRequestInputs(description: long, identity: [:], basis: .per100Grams, known: [], eligible: [.fiber])
        XCTAssertThrowsError(try ConfirmEnrichmentPolicy.nutrientRequest(inputs, route: route, encoder: FoundationCanonicalJSONEncoder(),
                                                                         digester: SHA256Digester())) {
            XCTAssertEqual($0 as? ConfirmEnrichmentPolicy.BuildFailure, .overPromptCeiling)
        }
    }

    func testTheSubjectChangesWithEveryPartItHashesAndTheBodyDecodesBack() throws {
        let inputs = try ConfirmEnrichmentFixtures.inputs()
        let encoder = FoundationCanonicalJSONEncoder(), digester = SHA256Digester()
        let base = try ConfirmEnrichmentPolicy.nutrientRequest(inputs, route: route, encoder: encoder, digester: digester)
        XCTAssertEqual(ConfirmNutrientRequestInputs.decode(requestBody: String(decoding: base.body, as: UTF8.self)), inputs)
        XCTAssertEqual(try ConfirmEnrichmentPolicy.nutrientRequest(inputs, route: route, encoder: encoder, digester: digester), base, "pure")
        let identity = try ConfirmNutrientRequestInputs(description: inputs.description, identity: ["preparation": "raw"], basis: inputs.basis,
                                                        known: inputs.known, eligible: [.fiber, .sodium])
        let known = try ConfirmNutrientRequestInputs(description: inputs.description, identity: inputs.identity, basis: inputs.basis,
                                                     known: Array(inputs.known.dropLast()), eligible: [.fiber, .sodium])
        let eligible = try ConfirmNutrientRequestInputs(description: inputs.description, identity: inputs.identity, basis: inputs.basis,
                                                        known: inputs.known, eligible: [.fiber])
        for other in [identity, known, eligible] {
            XCTAssertNotEqual(try ConfirmEnrichmentPolicy.nutrientRequest(other, route: route, encoder: encoder, digester: digester).subjectSHA256,
                              base.subjectSHA256)
        }
        let body = String(decoding: base.body, as: UTF8.self)
        XCTAssertFalse(body.contains("openrouter.ai"))
        for never in ["amount", "occurred", "barcode", "evidence", "record_id"] { XCTAssertFalse(body.contains(never), never) }
    }

    func testFortifiedIsNeverAChoiceAndAFillNeverReplacesAKnownFact() throws {
        XCTAssertFalse(ConfirmDetailsFact.fortification.choices.contains("fortified"))
        let identity = try DecisiveIdentity(preparation: PreparationState(kind: .raw), bone: .unknown, skin: .unknown, drained: .unknown,
                                            packingMedium: .unknown, fortification: .unknown, servingBasis: .per100Grams)
        let filled = try ConfirmEnrichmentPolicy.applying([.preparation: "cooked", .bone: "boneless", .fortification: "fortified"], to: identity)
        XCTAssertEqual(filled.preparation.kind, .raw, "a known fact is never replaced")
        XCTAssertEqual(filled.bone, .boneless)
        XCTAssertEqual(filled.fortification, .unknown, "fortified cannot be applied")
    }

    /// Defect review of PR 2: the label layer's values enter the energy check on Confirm as at save.
    func testTheLabelLayerTakesPartInTheEnergyCheck() throws {
        let base = try ConfirmEnrichmentFixtures.nutrients([
            .energyConsumed: try ConfirmEnrichmentFixtures.value(500, key: .energyConsumed,
                provenance: NutrientProvenance(sourceKind: .exactProductDataset, sourceID: ExternalIdentifier("open-food-facts"),
                                               sourceReleaseID: ExternalIdentifier("off-release"), recordID: ExternalIdentifier("1")))
        ])
        let kept: [NutrientKey: Double] = [.protein: 5, .carbohydrates: 10]
        let withoutLayer = ConfirmEnrichmentMerge.merge(kept: kept, leftOut: [], base: base, layer: [:])
        XCTAssertEqual(Set(withoutLayer.saved.keys), [.protein, .carbohydrates], "fat unknown: the check does not run")
        let withLayer = ConfirmEnrichmentMerge.merge(kept: kept, leftOut: [], base: base, layer: [.fatTotal: 2])
        XCTAssertEqual(withLayer.mergeEnergyDropped, [.protein, .carbohydrates], "500 kcal against 5, 10 and 2 g fails every form")
        XCTAssertTrue(withLayer.saved.isEmpty)
    }

    func testTheThreeUnmeasuredKeysAreNeverRequested() {
        XCTAssertEqual(ConfirmNutrientRequestInputs.unmeasuredKeys, [.cholesterol, .water, .caffeine])
        XCTAssertThrowsError(try ConfirmNutrientRequestInputs(description: ConfirmEnrichmentFixtures.description(), identity: [:],
                                                              basis: .per100Grams, known: [], eligible: [.caffeine]))
    }
}
