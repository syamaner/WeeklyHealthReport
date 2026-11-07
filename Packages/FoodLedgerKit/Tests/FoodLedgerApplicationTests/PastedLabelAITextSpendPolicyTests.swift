import FoodLedgerApplication
import Foundation
import XCTest

/// The shared day record and the text route's spend policy (docs/pasted-label-ai-text-v1.md 4.2,
/// D14, D17; contract tests 11 and 20).
final class PastedLabelAITextSpendPolicyTests: XCTestCase {
    typealias Text = PastedLabelAITextSpendPolicy
    typealias Photo = LabelPhotoSpendPolicy
    let today = "2026-11-07"
    let prices = LabelPhotoSpendPolicy.Prices(promptPerToken: Decimal(string: "0.000001")!, completionPerToken: Decimal(string: "0.000004")!,
                                              reasoningBilledSeparately: false, maxOutputTokens: 2_400)
    var w: Decimal { Text.worstCase(prices, reasoningLimit: 500) }

    func testWorstCasePricesTheTextCeiling() {
        // 32,000 prompt tokens at 0.000001 plus 2,400 completion tokens at 0.000004.
        XCTAssertEqual(w, Decimal(string: "0.0416"))
        let separate = LabelPhotoSpendPolicy.Prices(promptPerToken: prices.promptPerToken, completionPerToken: prices.completionPerToken,
                                                    reasoningBilledSeparately: true, maxOutputTokens: 2_400)
        XCTAssertEqual(Text.worstCase(separate, reasoningLimit: 500), Decimal(string: "0.0436"))
    }

    /// A2 gate finding 2: W prices the request's own prompt bound, and a bound past the ceiling is refused.
    func testWPricesTheRequestsPromptBound() {
        // A full 8,000-scalar Traditional Chinese text (24,000 UTF-8 bytes) with a 3,000-byte
        // instruction and a 2,500-byte schema: 29,756 tokens at most, under the ceiling.
        let bound = Text.promptTokenBound(instructionBytes: 3_000, schemaBytes: 2_500, textBytes: String(repeating: "鈉", count: 8_000).utf8.count)
        XCTAssertEqual(bound, 29_756)
        XCTAssertEqual(Text.worstCase(prices, reasoningLimit: 500, promptTokenBound: bound), Decimal(string: "0.039356"))
        XCTAssertNil(Text.worstCase(prices, reasoningLimit: 500, promptTokenBound: Text.promptTokenCeiling + 1), "refused, never priced")
        XCTAssertNotNil(Text.worstCase(prices, reasoningLimit: 500, promptTokenBound: Text.promptTokenCeiling))
    }

    /// A2 invariant finding 4: a tap with no attempts is released, never reconciled.
    func testReconcilingNoAttemptsIsARelease() throws {
        let reserved = Text.reservation(today: today, stored: nil, tap: "t1")
        XCTAssertEqual(Text.reconciled(reserved, reservedOn: today, tap: "t1", attempts: [], worstCase: w),
                       Text.released(reserved, reservedOn: today, tap: "t1"))
        XCTAssertEqual(try XCTUnwrap(Text.reconciled(reserved, reservedOn: today, tap: "t1", attempts: [], worstCase: w)).reads, 0)
    }

    /// A2 gate finding 12: an unversioned photo record re-encodes with every value kept, the
    /// version and an empty text share added, and decodes back to the same day.
    func testAnUnversionedPhotoRecordRoundTripsWithNothingLost() throws {
        let old = #"{"cost":0.15,"day":"2026-11-07","openTaps":["p1","p2"],"paused":true,"reads":3}"#
        let day = try JSONDecoder().decode(Photo.Day.self, from: Data(old.utf8))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let encoded = try encoder.encode(day)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        let original = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(old.utf8)) as? [String: Any])
        for (key, value) in original { XCTAssertEqual("\(object[key] ?? "missing")", "\(value)", key) }
        XCTAssertEqual(object["version"] as? String, "label-ai-spend-day-v1")
        XCTAssertEqual(Set(object.keys), Set(original.keys).union(["version", "text"]))
        let again = try JSONDecoder().decode(Photo.Day.self, from: encoded)
        XCTAssertEqual(again, day)
        XCTAssertEqual([again.reads, again.openTaps.count], [3, 2])
        XCTAssertEqual(again.cost, Decimal(string: "0.15"))
        XCTAssertTrue(again.paused)
        XCTAssertEqual(again.text, .none)
    }

    // MARK: Test 20: existing records, corrupt records, pauses

    func testExistingPhotoRecordsDecodeAsPhotoOnly() throws {
        let old = Data(#"{"cost":0.1,"day":"2026-11-07","paused":false,"reads":2,"openTaps":["p1"]}"#.utf8)
        let day = try JSONDecoder().decode(Photo.Day.self, from: old)
        XCTAssertEqual(day.text, .none)
        XCTAssertEqual(day.reads, 2)
        XCTAssertEqual(day.openTaps, ["p1"])
        // The photo reads count against the shared cap for the text route.
        XCTAssertEqual(Text.admission(today: today, stored: .day(day)), .allowed)
        let full = try JSONDecoder().decode(Photo.Day.self, from: Data(#"{"cost":0.1,"day":"2026-11-07","paused":false,"reads":30}"#.utf8))
        XCTAssertEqual(Text.admission(today: today, stored: .day(full)), .limitReached)
    }

    func testTheSharedRecordRoundTripsAndNamesItsVersion() throws {
        let day = Text.reservation(today: today, stored: Photo.reservation(today: today, stored: nil, tap: "p1"), tap: "t1")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(day)
        XCTAssertEqual(String(decoding: data, as: UTF8.self),
                       #"{"cost":0.1,"day":"2026-11-07","openTaps":["p1"],"paused":false,"reads":2,"#
                           + #""text":{"cost":0.05,"openTaps":["t1"],"paused":false,"reads":1},"version":"label-ai-spend-day-v1"}"#)
        XCTAssertEqual(try JSONDecoder().decode(Photo.Day.self, from: data), day)
    }

    func testCorruptRecordsThrowSoTheLedgerFailsClosed() {
        let corrupt = [
            #"{"cost":0.1,"day":"2026-11-07","paused":false,"reads":2,"version":"label-ai-spend-day-v9","text":{"cost":0,"openTaps":[],"paused":false,"reads":0}}"#,
            #"{"cost":0.1,"day":"2026-11-07","paused":false,"reads":2,"text":{"cost":0,"openTaps":[],"paused":false,"reads":0}}"#,
            #"{"cost":0.1,"day":"2026-11-07","paused":false,"reads":2,"version":"label-ai-spend-day-v1"}"#,
            #"{"cost":0.1,"day":"2026-11-07","paused":false,"reads":2,"version":"label-ai-spend-day-v1","text":{"cost":0,"paused":false,"reads":0}}"#,
            #"{"cost":0.1,"day":"2026-11-07","paused":false,"reads":2,"version":"label-ai-spend-day-v1","text":{"cost":0,"openTaps":[],"paused":false,"reads":3}}"#,
            #"{"cost":0.1,"day":"2026-11-07","paused":false,"reads":2,"version":"label-ai-spend-day-v1","text":{"cost":0.2,"openTaps":[],"paused":false,"reads":1}}"#,
            #"{"cost":-0.1,"day":"2026-11-07","paused":false,"reads":2}"#,
        ]
        for json in corrupt {
            XCTAssertThrowsError(try JSONDecoder().decode(Photo.Day.self, from: Data(json.utf8)), json)
        }
        XCTAssertEqual(Text.admission(today: today, stored: .unreadable), .limitReached)
        XCTAssertEqual(Photo.admission(today: today, stored: .unreadable), .limitReached)
    }

    func testAnOverCeilingTextReadPausesOnlyTheTextRoute() throws {
        let reserved = Text.reservation(today: today, stored: nil, tap: "t1")
        let settled = try XCTUnwrap(Text.reconciled(reserved, reservedOn: today, tap: "t1",
                                                    attempts: [.init(reportedCost: Decimal(string: "0.01"), promptTokens: 32_001)], worstCase: w))
        XCTAssertTrue(settled.text.paused)
        XCTAssertFalse(settled.paused, "the photo route is not paused")
        XCTAssertEqual(Text.admission(today: today, stored: .day(settled)), .paused)
        XCTAssertEqual(Photo.admission(today: today, stored: .day(settled)), .allowed)
        // Over the text cap pauses the text route too.
        let over = try XCTUnwrap(Text.reconciled(Text.reservation(today: today, stored: nil, tap: "t2"), reservedOn: today, tap: "t2",
                                                 attempts: [.init(reportedCost: Decimal(string: "0.06"), promptTokens: 100)], worstCase: w))
        XCTAssertTrue(over.text.paused)
        XCTAssertFalse(over.paused)
    }

    func testAPhotoPauseNeverStopsATextRead() {
        let paused = Photo.Day(day: today, reads: 1, cost: Decimal(string: "0.05")!, paused: true)
        XCTAssertEqual(Photo.admission(today: today, stored: .day(paused)), .paused)
        XCTAssertEqual(Text.admission(today: today, stored: .day(paused)), .allowed)
    }

    // MARK: Test 11: shared spend across routes

    func testBothRoutesCountAgainstOneSharedCap() throws {
        var day = Photo.Day(day: today, reads: 28, cost: Decimal(string: "0.20")!, paused: false)
        day = Text.reservation(today: today, stored: day, tap: "t1")
        day = try XCTUnwrap(Text.reconciled(day, reservedOn: today, tap: "t1", attempts: [.init(reportedCost: Decimal(string: "0.01"), promptTokens: 900)],
                                            worstCase: w))
        XCTAssertEqual(day.reads, 29)
        XCTAssertEqual(day.cost, Decimal(string: "0.21"))
        XCTAssertEqual(day.text, LabelAISpendRouteShare(reads: 1, cost: Decimal(string: "0.01")!, paused: false, openTaps: []))
        // A photo tap on the same day keeps the text share and counts against the same totals.
        day = Photo.reservation(today: today, stored: day, tap: "p1")
        day = try XCTUnwrap(Photo.reconciled(day, reservedOn: today, tap: "p1", attempts: [.init(reportedCost: Decimal(string: "0.02"), promptTokens: 2_000)],
                                             prices: prices))
        XCTAssertEqual(day.reads, 30)
        XCTAssertEqual(day.cost, Decimal(string: "0.23"))
        XCTAssertEqual(day.text.reads, 1, "a photo write never erases a text read")
        XCTAssertEqual(Text.admission(today: today, stored: .day(day)), .limitReached)
        XCTAssertEqual(Photo.admission(today: today, stored: .day(day)), .limitReached)
        // The photo route's other writes carry the text share too.
        XCTAssertEqual(Photo.record([.init(reportedCost: 0, promptTokens: 1)], prices: prices, today: today, stored: day).text, day.text)
        XCTAssertEqual(Photo.released(Photo.reservation(today: today, stored: day, tap: "p2"), reservedOn: today, tap: "p2")?.text, day.text)
    }

    func testTheCostCapCountsTheTextCapBeforeAdmitting() {
        let nearly = Photo.Day(day: today, reads: 3, cost: Decimal(string: "0.45")!, paused: false)
        XCTAssertEqual(Text.admission(today: today, stored: .day(nearly)), .allowed)
        let over = Photo.Day(day: today, reads: 3, cost: Decimal(string: "0.4501")!, paused: false)
        XCTAssertEqual(Text.admission(today: today, stored: .day(over)), .limitReached)
    }

    func testUnknownCostIsChargedAtTheCapAndW() throws {
        XCTAssertEqual(Text.tapCost([.init(reportedCost: nil, promptTokens: nil)], worstCase: w), Text.perTapLimit)
        let bigW = Decimal(string: "0.04")!
        XCTAssertEqual(Text.tapCost([.init(reportedCost: Decimal(string: "0.02"), promptTokens: 1), .init(reportedCost: nil, promptTokens: nil)],
                                    worstCase: bigW), Decimal(string: "0.06"))
        let settled = try XCTUnwrap(Text.reconciled(Text.reservation(today: today, stored: nil, tap: "t1"), reservedOn: today, tap: "t1",
                                                    attempts: [.init(reportedCost: nil, promptTokens: nil)], worstCase: w))
        XCTAssertEqual(settled.cost, Text.perTapLimit, "unknown is never zero")
        XCTAssertEqual(settled.text.cost, Text.perTapLimit)
        XCTAssertFalse(Text.mayStartAttempt(after: [.init(reportedCost: nil, promptTokens: nil)], worstCase: Decimal(string: "0.03")!))
        XCTAssertTrue(Text.mayStartAttempt(after: [], worstCase: Decimal(string: "0.03")!))
    }

    func testASettleAppliesOnceAndAReleaseReturnsTheReservation() throws {
        let reserved = Text.reservation(today: today, stored: nil, tap: "t1")
        let settled = try XCTUnwrap(Text.reconciled(reserved, reservedOn: today, tap: "t1", attempts: [.init(reportedCost: Decimal(string: "0.01"), promptTokens: 10)],
                                                    worstCase: w))
        XCTAssertNil(Text.reconciled(settled, reservedOn: today, tap: "t1", attempts: [], worstCase: w), "a retried settle never applies twice")
        XCTAssertNil(Text.reconciled(reserved, reservedOn: "2026-11-08", tap: "t1", attempts: [], worstCase: w))
        let released = try XCTUnwrap(Text.released(reserved, reservedOn: today, tap: "t1"))
        XCTAssertEqual(released, Photo.Day(day: today, reads: 0, cost: 0, paused: false))
        XCTAssertNil(Text.released(released, reservedOn: today, tap: "t1"))
        // A photo tap ID never settles a text tap.
        XCTAssertNil(Text.reconciled(Photo.reservation(today: today, stored: nil, tap: "p1"), reservedOn: today, tap: "p1", attempts: [], worstCase: w))
    }

    func testAClockMovedBackNeverResetsTheAllowance() {
        let later = Photo.Day(day: "2026-11-08", reads: 30, cost: Decimal(string: "0.30")!, paused: false)
        XCTAssertEqual(Text.admission(today: today, stored: .day(later)), .limitReached)
        XCTAssertEqual(Text.admission(today: "2026-11-09", stored: .day(later)), .allowed)
    }
}
