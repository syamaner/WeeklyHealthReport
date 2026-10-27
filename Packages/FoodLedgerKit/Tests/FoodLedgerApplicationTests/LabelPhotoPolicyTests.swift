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

    func record(_ attempts: [S.Attempt], _ today: String, _ stored: S.Day?) -> S.Day {
        S.record(attempts, prices: gemini, today: today, stored: stored)
    }

    func testDailyReadsAndCostAndUnknownCost() {
        let today = "2026-10-25"
        var day = S.Day.empty(today)
        for _ in 0..<29 { day = record([.init(reportedCost: Decimal(string: "0.01"), promptTokens: 2_000)], today, day) }
        XCTAssertEqual(S.admission(today: today, stored: .day(day)), .allowed)
        day = record([.init(reportedCost: Decimal(string: "0.01"), promptTokens: 2_000)], today, day)
        XCTAssertEqual(day.reads, 30)
        XCTAssertEqual(S.admission(today: today, stored: .day(day)), .limitReached)
        // E10 and test 10: a read with no reported cost counts $0.05; with reported costs as well it
        // counts the larger of $0.05 and those costs plus W ($0.024) per unreported attempt.
        XCTAssertEqual(record([.init(reportedCost: nil, promptTokens: nil)], today, nil).cost, Decimal(string: "0.05"))
        let mixed = record([.init(reportedCost: Decimal(string: "0.01"), promptTokens: 2_000), .init(reportedCost: nil, promptTokens: nil)],
                           today, nil)
        XCTAssertEqual(mixed.cost, Decimal(string: "0.05"), "max(0.05, 0.034)")
        let costly = record([.init(reportedCost: Decimal(string: "0.03"), promptTokens: 2_000), .init(reportedCost: nil, promptTokens: nil)],
                            today, nil)
        XCTAssertEqual(costly.cost, Decimal(string: "0.054"), "max(0.05, 0.054)")
        XCTAssertEqual(record([.init(reportedCost: Decimal(string: "0.01"), promptTokens: 2_000)], today, nil).cost, Decimal(string: "0.01"))
        // Ten reads with no reported cost reach $0.50.
        var tenUnknown = S.Day.empty(today)
        for _ in 0..<10 { tenUnknown = record([.init(reportedCost: nil, promptTokens: nil)], today, tenUnknown) }
        XCTAssertEqual(tenUnknown.cost, Decimal(string: "0.50"))
        XCTAssertEqual(S.admission(today: today, stored: .day(tenUnknown)), .limitReached)
        // E10: a tap is admitted only while the day plus a whole tap's $0.05 stays within $0.50,
        // so the day can never exceed it.
        XCTAssertEqual(S.admission(today: today, stored: .day(S.Day(day: today, reads: 5, cost: Decimal(string: "0.45")!, paused: false))),
                       .allowed)
        XCTAssertEqual(S.admission(today: today, stored: .day(S.Day(day: today, reads: 5, cost: Decimal(string: "0.4501")!, paused: false))),
                       .limitReached)
        var unknown = S.Day.empty(today)
        while S.admission(today: today, stored: .day(unknown)) == .allowed {
            unknown = record([.init(reportedCost: nil, promptTokens: nil), .init(reportedCost: nil, promptTokens: nil)], today, unknown)
        }
        XCTAssertLessThanOrEqual(unknown.cost, S.dailyCostLimit)
        XCTAssertEqual(unknown.reads, 10, "ten taps of two unreported attempts ($0.05 each) fit; the eleventh would not")
    }

    func testOverCapCostAndInputCeilingPauseTheDay() {
        let today = "2026-10-25"
        let over = record([.init(reportedCost: Decimal(string: "0.051"), promptTokens: 2_000)], today, nil)
        XCTAssertEqual(S.admission(today: today, stored: .day(over)), .paused)
        // Test 26: 6,001 prompt tokens pause the day; 6,000 do not.
        let input = record([.init(reportedCost: Decimal(string: "0.01"), promptTokens: 6_001)], today, nil)
        XCTAssertEqual(S.admission(today: today, stored: .day(input)), .paused)
        let edge = record([.init(reportedCost: Decimal(string: "0.01"), promptTokens: 6_000)], today, nil)
        XCTAssertEqual(S.admission(today: today, stored: .day(edge)), .allowed)
        // The pause survives a reload of the stored day, and ends at the next local day.
        let reloaded = try! JSONDecoder().decode(S.Day.self, from: JSONEncoder().encode(input))
        XCTAssertEqual(S.admission(today: today, stored: .day(reloaded)), .paused)
        XCTAssertEqual(S.admission(today: "2026-10-26", stored: .day(reloaded)), .allowed)
    }

    func testUnreadableLedgerFailsClosedAbsentIsAFreshDayAndNoAttemptRecordsNothing() {
        XCTAssertEqual(S.admission(today: "2026-10-25", stored: .unreadable), .limitReached)
        XCTAssertEqual(S.admission(today: "2026-10-25", stored: .absent), .allowed)
        XCTAssertEqual(record([], "2026-10-25", nil), S.Day.empty("2026-10-25"))
    }

    func testAClockMovedBackNeverResetsTheAllowance() {
        // The stored day is later than today: it still counts, and a new tap adds to it.
        let full = S.Day(day: "2026-10-26", reads: 30, cost: Decimal(string: "0.20")!, paused: false)
        XCTAssertEqual(S.admission(today: "2026-10-25", stored: .day(full)), .limitReached)
        let paused = S.Day(day: "2026-10-26", reads: 1, cost: Decimal(string: "0.01")!, paused: true)
        XCTAssertEqual(S.admission(today: "2026-10-25", stored: .day(paused)), .paused)
        let later = S.Day(day: "2026-10-26", reads: 3, cost: Decimal(string: "0.03")!, paused: false)
        let after = record([.init(reportedCost: Decimal(string: "0.01"), promptTokens: 100)], "2026-10-25", later)
        XCTAssertEqual(after, S.Day(day: "2026-10-26", reads: 4, cost: Decimal(string: "0.04")!, paused: false))
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
        XCTAssertEqual(R.next(afterAttempt: 1, outcome: .transportError, elapsed: 2, now: now, jitter: 0), .retry(after: 0.5, timeout: 45))
        // Q1: the next attempt's timeout is what is left of the 90 s deadline when that is less than 45 s.
        XCTAssertEqual(R.next(afterAttempt: 2, outcome: .timedOut, elapsed: 47, now: now, jitter: 1), .retry(after: 2, timeout: 41))
        XCTAssertEqual(R.next(afterAttempt: 1, outcome: .httpStatus(429, retryAfter: "10"), elapsed: 2, now: now, jitter: 0),
                       .retry(after: 10, timeout: 45))
        XCTAssertEqual(R.next(afterAttempt: 1, outcome: .providerError(code: 529, hasChoices: false, retryAfter: "3"), elapsed: 2,
                              now: now, jitter: 0), .retry(after: 3, timeout: 45))
        XCTAssertEqual(R.attemptTimeout(elapsed: 0), 45)
        XCTAssertEqual(R.attemptTimeout(elapsed: 60), 30)
        XCTAssertEqual(R.attemptTimeout(elapsed: 95), 0)
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

    func testShortEdgeMinimumIsTheDecided160Pixels() throws {
        // 480 px, then 240 px after L0 (17.9), then 160 px after E13 (17.21).
        XCTAssertEqual(LabelCropRect.minimumShortEdge, 160)
        let crop = try XCTUnwrap(LabelCropRect(x: 0, y: 0, width: 0.5, height: 0.25))
        XCTAssertEqual(crop.shortEdge(pixelWidth: 2_000, pixelHeight: 640), 160)
    }
}
