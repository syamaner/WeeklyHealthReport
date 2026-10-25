import FoodLedgerApplication
import Foundation
import XCTest

/// Contract tests for the label photo pure policies (docs/label-photo-ai-prefill-v1.md 12.5 and
/// 17.8): attention v1 (test 4 and the L0 port), spend (tests 10, 21, 26), retry (test 9, 21) and
/// the crop value (17.2). Synthetic values only.
final class LabelPhotoAttentionTests: XCTestCase {
    typealias A = LabelPhotoAttention

    func cell(_ id: String, _ nutrient: String, _ basis: String = "per_100g", known: Bool = true, location: A.Location = .found) -> A.Cell {
        A.Cell(id: id, nutrient: nutrient, basis: basis, known: known, location: location)
    }

    var table: [A.Cell] {
        [cell("e100", "energy_kcal"), cell("p100", "protein"), cell("f100", "fat"), cell("s100", "saturates"),
         cell("c100", "carbohydrate"), cell("fi100", "fibre"), cell("n100", "sodium"),
         cell("es", "energy_kcal", "per_serving"), cell("ns", "sodium", "per_serving"), cell("nri", "sodium", "reference_intake")]
    }

    func testEverythingFoundAndPassingHasNoItems() {
        let found = A.items(cells: table, servingLines: [.init(id: "serving_size", location: .found)], gateFlaggedNutrients: [],
                            failedChecks: [])
        XCTAssertTrue(found.isEmpty)
        XCTAssertEqual(A.unresolved(found, resolutions: [:]), [])
    }

    func testNotFoundAmbiguousAndServingLinesAreItems() {
        var cells = table
        cells[6] = cell("n100", "sodium", location: .notFound)
        cells[1] = cell("p100", "protein", location: .ambiguous)
        let found = A.items(cells: cells, servingLines: [.init(id: "serving_size", location: .ambiguous),
                                                         .init(id: "servings_per_pack", location: .notFound)],
                            gateFlaggedNutrients: [], failedChecks: [])
        XCTAssertEqual(found.items.map(\.id), ["p100", "n100", "serving_size", "servings_per_pack"])
        XCTAssertEqual(found.items.map(\.reasons), [[.ambiguous], [.notFound], [.ambiguous], [.notFound]])
    }

    func testUnknownValuesAreNeverItems() {
        let cells = [cell("u", "sodium", known: false, location: .notFound)]
        XCTAssertTrue(A.items(cells: cells, servingLines: [], gateFlaggedNutrients: ["sodium"],
                              failedChecks: [.init(name: "serving_scaling", nutrient: "sodium")]).isEmpty)
    }

    func testGateFlaggedRowMarksItsKnownValues() {
        let found = A.items(cells: table, servingLines: [], gateFlaggedNutrients: ["sodium"], failedChecks: [])
        XCTAssertEqual(found.items.map(\.id), ["n100", "ns", "nri"])
        XCTAssertTrue(found.items.allSatisfy { $0.reasons == [.gateFlag] })
    }

    /// The L0 implication rules (`arithmetic_attention`), check by check.
    func testFailedChecksImplicateTheMeasuredCells() {
        XCTAssertEqual(A.implicated(by: .init(name: "energy", basis: "per_100g"), in: table), ["e100", "p100", "f100", "c100", "fi100"])
        XCTAssertEqual(A.implicated(by: .init(name: "kj_kcal_ratio", basis: "per_serving"), in: table), ["es"])
        XCTAssertEqual(A.implicated(by: .init(name: "serving_scaling", nutrient: "sodium"), in: table), ["n100", "ns"])
        XCTAssertEqual(A.implicated(by: .init(name: "subrow_not_above_parent", basis: "per_100g", child: "saturates"), in: table),
                       ["f100", "s100"])
        XCTAssertEqual(A.implicated(by: .init(name: "subrow_not_above_parent", basis: "per_100g", child: "fibre"), in: table),
                       ["c100", "fi100"])
        for other in ["bound_consistency", "net_weight", "basis_plausibility"] {
            XCTAssertEqual(A.implicated(by: .init(name: other, basis: "per_100g"), in: table), [], other)
        }
    }

    func testReasonsCombineInOrderAndGroupsListTheirItems() {
        var cells = table
        cells[0] = cell("e100", "energy_kcal", location: .notFound)
        let check = A.FailedCheck(name: "energy", basis: "per_100g")
        let found = A.items(cells: cells, servingLines: [], gateFlaggedNutrients: ["energy_kcal"], failedChecks: [check])
        XCTAssertEqual(found.items.first, A.Item(id: "e100", reasons: [.notFound, .gateFlag, .checkFailed]))
        XCTAssertEqual(found.checks, [A.CheckGroup(check: check, itemIDs: ["e100", "p100", "f100", "c100", "fi100"])])
        // The gate flag marks every known value of the energy row, the per serving one too.
        XCTAssertEqual(found.items.map(\.id), ["e100", "p100", "f100", "c100", "fi100", "es"])
    }

    func testLogNeedsEveryItemResolvedAndCheckingAGroupKeepsCorrections() {
        let check = A.FailedCheck(name: "energy", basis: "per_100g")
        let found = A.items(cells: table, servingLines: [], gateFlaggedNutrients: [], failedChecks: [check])
        XCTAssertEqual(A.unresolved(found, resolutions: [:]).count, 5)
        let resolved = A.checkGroup(found.checks[0], resolutions: ["f100": .corrected])
        XCTAssertEqual(resolved["f100"], .corrected)
        XCTAssertEqual(resolved["e100"], .checked)
        XCTAssertEqual(A.unresolved(found, resolutions: resolved), [])
    }

    func testVersionIsPinned() {
        XCTAssertEqual(A.version, "label-photo-attention-v1")
        XCTAssertEqual(A.Reason.allCases.map(\.rawValue), ["not_found", "ambiguous", "gate_flag", "check_failed"])
        XCTAssertEqual(A.Resolution.allCases.map(\.rawValue), ["checked", "corrected", "entered", "left_unknown"])
    }
}

final class LabelPhotoSpendPolicyTests: XCTestCase {
    typealias S = LabelPhotoSpendPolicy

    /// Gemini 4 Argon's recorded catalogue prices: $2 and $10 per million tokens.
    let gemini = S.Prices(promptPerToken: Decimal(string: "0.000002")!, completionPerToken: Decimal(string: "0.00001")!,
                          reasoningBilledSeparately: false)

    func testWorstCaseIsPinnedForTheRequestGolden() {
        XCTAssertEqual(S.maxTokens, 1_200)
        XCTAssertEqual(S.reasoningLimit, 500)
        XCTAssertEqual(S.worstCase(gemini), Decimal(string: "0.024"))
        let separate = S.Prices(promptPerToken: gemini.promptPerToken, completionPerToken: gemini.completionPerToken,
                                reasoningBilledSeparately: true)
        XCTAssertEqual(S.worstCase(separate), Decimal(string: "0.029"))
    }

    func testPerTapBudgetCountsReportedUnreportedAndCancelledAttempts() {
        XCTAssertTrue(S.mayStartAttempt(after: [], prices: gemini))
        // An unreported failure is charged W ($0.024): one more W still fits in $0.05.
        XCTAssertTrue(S.mayStartAttempt(after: [.init(reportedCost: nil, promptTokens: nil)], prices: gemini))
        // Two unreported attempts ($0.048) leave no room for a third.
        XCTAssertFalse(S.mayStartAttempt(after: [.init(reportedCost: nil, promptTokens: nil), .init(reportedCost: nil, promptTokens: nil)],
                                         prices: gemini))
        // Rejected requests reported at zero leave the whole budget.
        XCTAssertTrue(S.mayStartAttempt(after: [.init(reportedCost: 0, promptTokens: nil), .init(reportedCost: 0, promptTokens: nil)],
                                        prices: gemini))
        // Billed separately, W is $0.029: after an unreported failure no retry fits.
        let separate = S.Prices(promptPerToken: gemini.promptPerToken, completionPerToken: gemini.completionPerToken,
                                reasoningBilledSeparately: true)
        XCTAssertFalse(S.mayStartAttempt(after: [.init(reportedCost: nil, promptTokens: nil)], prices: separate))
    }

    func testDailyReadsAndCostAndUnknownCost() {
        let today = "2026-10-25"
        var day = S.Day.empty(today)
        for _ in 0..<29 { day = S.record([.init(reportedCost: Decimal(string: "0.01"), promptTokens: 2_000)], today: today, stored: day) }
        XCTAssertEqual(S.admission(today: today, stored: day, ledgerReadable: true), .allowed)
        day = S.record([.init(reportedCost: Decimal(string: "0.01"), promptTokens: 2_000)], today: today, stored: day)
        XCTAssertEqual(day.reads, 30)
        XCTAssertEqual(S.admission(today: today, stored: day, ledgerReadable: true), .limitReached)
        // A read with no reported cost counts $0.05; ten of them reach $0.50.
        var unknown = S.Day.empty(today)
        for _ in 0..<10 { unknown = S.record([.init(reportedCost: nil, promptTokens: nil)], today: today, stored: unknown) }
        XCTAssertEqual(unknown.cost, Decimal(string: "0.50"))
        XCTAssertEqual(S.admission(today: today, stored: unknown, ledgerReadable: true), .limitReached)
    }

    func testOverCapCostAndInputCeilingPauseTheDay() {
        let today = "2026-10-25"
        let over = S.record([.init(reportedCost: Decimal(string: "0.051"), promptTokens: 2_000)], today: today, stored: nil)
        XCTAssertEqual(S.admission(today: today, stored: over, ledgerReadable: true), .paused)
        // Test 26: 6,001 prompt tokens pause the day; 6,000 do not.
        let input = S.record([.init(reportedCost: Decimal(string: "0.01"), promptTokens: 6_001)], today: today, stored: nil)
        XCTAssertEqual(S.admission(today: today, stored: input, ledgerReadable: true), .paused)
        let edge = S.record([.init(reportedCost: Decimal(string: "0.01"), promptTokens: 6_000)], today: today, stored: nil)
        XCTAssertEqual(S.admission(today: today, stored: edge, ledgerReadable: true), .allowed)
        // The pause survives a reload of the stored day, and ends at the next local day.
        let reloaded = try! JSONDecoder().decode(S.Day.self, from: JSONEncoder().encode(input))
        XCTAssertEqual(S.admission(today: today, stored: reloaded, ledgerReadable: true), .paused)
        XCTAssertEqual(S.admission(today: "2026-10-26", stored: reloaded, ledgerReadable: true), .allowed)
    }

    func testUnreadableLedgerFailsClosedAndNoAttemptRecordsNothing() {
        XCTAssertEqual(S.admission(today: "2026-10-25", stored: nil, ledgerReadable: false), .limitReached)
        XCTAssertEqual(S.record([], today: "2026-10-25", stored: nil), S.Day.empty("2026-10-25"))
    }

    func testDayFollowsTheInjectedCalendar() {
        var taipei = Calendar(identifier: .gregorian)
        taipei.timeZone = TimeZone(identifier: "Asia/Taipei")!
        var london = Calendar(identifier: .gregorian)
        london.timeZone = TimeZone(identifier: "Europe/London")!
        let instant = Date(timeIntervalSince1970: 1_792_944_000) // 2026-10-25T16:00:00Z
        XCTAssertEqual(S.dayKey(instant, calendar: taipei), "2026-10-26")
        XCTAssertEqual(S.dayKey(instant, calendar: london), "2026-10-25")
    }
}

final class LabelPhotoRetryPolicyTests: XCTestCase {
    typealias R = LabelPhotoRetryPolicy
    let now = Date(timeIntervalSince1970: 1_761_400_000)

    func testRetryableAndContentOutcomes() {
        for status in [408, 429, 500, 502, 503, 504] { XCTAssertTrue(R.isRetryable(.httpStatus(status, retryAfter: nil)), "\(status)") }
        for status in [400, 401, 402, 403, 404, 422] { XCTAssertFalse(R.isRetryable(.httpStatus(status, retryAfter: nil)), "\(status)") }
        XCTAssertTrue(R.isRetryable(.transportError))
        XCTAssertTrue(R.isRetryable(.timedOut))
        XCTAssertFalse(R.isRetryable(.contentFailure))
        XCTAssertEqual(R.next(afterAttempt: 1, outcome: .contentFailure, elapsed: 1, now: now, jitter: 0), .stop(.notRetryable))
    }

    func testOverloadedIsExactlyTheDefinedCodesWithoutChoices() {
        for code in [502, 503, 529] { XCTAssertTrue(R.isOverloaded(code: code, hasChoices: false)) }
        XCTAssertFalse(R.isOverloaded(code: 503, hasChoices: true))
        XCTAssertFalse(R.isOverloaded(code: 500, hasChoices: false))
        XCTAssertFalse(R.isOverloaded(code: nil, hasChoices: false))
    }

    func testRetryAfterInSecondsAndHTTPDateForms() {
        XCTAssertEqual(R.retryAfter("7", now: now), 7)
        XCTAssertEqual(R.retryAfter(" 0 ", now: now), 0)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"
        XCTAssertEqual(R.retryAfter(formatter.string(from: now.addingTimeInterval(12)), now: now), 12)
        XCTAssertEqual(R.retryAfter(formatter.string(from: now.addingTimeInterval(-30)), now: now), 0)
        XCTAssertNil(R.retryAfter("soon", now: now))
        XCTAssertNil(R.retryAfter("-3", now: now))
        XCTAssertNil(R.retryAfter(nil, now: now))
    }

    func testBackoffHonoursRetryAfterAttemptsAndDeadline() {
        XCTAssertEqual(R.next(afterAttempt: 1, outcome: .transportError, elapsed: 2, now: now, jitter: 0), .retry(after: 0.5))
        XCTAssertEqual(R.next(afterAttempt: 2, outcome: .timedOut, elapsed: 47, now: now, jitter: 1), .retry(after: 2))
        XCTAssertEqual(R.next(afterAttempt: 1, outcome: .httpStatus(429, retryAfter: "10"), elapsed: 2, now: now, jitter: 0),
                       .retry(after: 10))
        XCTAssertEqual(R.next(afterAttempt: 1, outcome: .providerError(code: 529, hasChoices: false, retryAfter: "3"), elapsed: 2,
                              now: now, jitter: 0), .retry(after: 3))
        XCTAssertEqual(R.next(afterAttempt: 3, outcome: .transportError, elapsed: 20, now: now, jitter: 0), .stop(.attemptsExhausted))
        // A Retry-After past the deadline stops.
        XCTAssertEqual(R.next(afterAttempt: 1, outcome: .httpStatus(503, retryAfter: "120"), elapsed: 5, now: now, jitter: 0),
                       .stop(.deadline))
        XCTAssertEqual(R.next(afterAttempt: 2, outcome: .timedOut, elapsed: 89.5, now: now, jitter: 0), .stop(.deadline))
    }

    func testLimitsArePinned() {
        XCTAssertEqual(R.maxAttempts, 3)
        XCTAssertEqual(R.attemptTimeout, 45)
        XCTAssertEqual(R.deadline, 90)
    }
}

final class LabelCropRectTests: XCTestCase {
    func testValidAndInvalidCrops() throws {
        XCTAssertNotNil(LabelCropRect(x: 0.1, y: 0.2, width: 0.5, height: 0.6, quarterTurns: 1))
        XCTAssertNil(LabelCropRect(x: 0.6, y: 0, width: 0.5, height: 1))
        XCTAssertNil(LabelCropRect(x: 0, y: 0, width: 0, height: 1))
        XCTAssertNil(LabelCropRect(x: -0.1, y: 0, width: 0.5, height: 1))
        XCTAssertNil(LabelCropRect(x: 0, y: 0, width: .nan, height: 1))
        XCTAssertNil(LabelCropRect(x: 0, y: 0, width: 1, height: 1, quarterTurns: 4))
        XCTAssertEqual(LabelCropRect.whole, LabelCropRect(x: 0, y: 0, width: 1, height: 1))
    }

    func testDecodingRefusesACropOutsideThePhotoAndRoundTrips() throws {
        let crop = try XCTUnwrap(LabelCropRect(x: 0.25, y: 0.5, width: 0.5, height: 0.25, quarterTurns: 2))
        XCTAssertEqual(try JSONDecoder().decode(LabelCropRect.self, from: JSONEncoder().encode(crop)), crop)
        let bad = Data(#"{"x":0.9,"y":0,"width":0.5,"height":1,"quarterTurns":0}"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(LabelCropRect.self, from: bad))
    }

    func testShortEdgeMinimumIsTheDecided240Pixels() throws {
        XCTAssertEqual(LabelCropRect.minimumShortEdge, 240)
        let crop = try XCTUnwrap(LabelCropRect(x: 0, y: 0, width: 0.5, height: 0.25))
        XCTAssertEqual(crop.shortEdge(pixelWidth: 2_000, pixelHeight: 960), 240)
    }
}
