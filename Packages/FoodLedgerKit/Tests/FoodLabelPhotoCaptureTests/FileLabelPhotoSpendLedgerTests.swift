@testable import FoodLabelPhotoCapture
import FoodLedgerApplication
import Foundation
import XCTest

/// The file spend ledger's contract (docs/label-photo-ai-prefill-v1.md 17.18 and 17.19, tests 24 and
/// 25): absent is a fresh day, anything undecodable is unreadable, and `update` is one atomic
/// read-modify-write that throws only when nothing was stored, so the session's settle retry is safe.
final class FileLabelPhotoSpendLedgerTests: XCTestCase {
    var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("spend-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: directory.path)
        try? FileManager.default.removeItem(at: directory)
    }

    var url: URL { directory.appendingPathComponent("label-photo-spend-v1.json") }
    let day = LabelPhotoSpendPolicy.Day(day: "2026-10-25", reads: 3, cost: Decimal(string: "0.15")!, paused: false, openTaps: ["t1"])

    func testAbsentIsAFreshDayAndGarbageIsUnreadable() throws {
        let ledger = FileLabelPhotoSpendLedger(url: url)
        XCTAssertEqual(ledger.load(), .absent)
        try Data("not json".utf8).write(to: url)
        XCTAssertEqual(ledger.load(), .unreadable)
    }

    /// The shared day record (docs/pasted-label-ai-text-v1.md D14, test 20): a photo-only file
    /// written before the text route reads as photo-only, a text write keeps the photo counts, and a
    /// record of an unknown version is unreadable, so both routes fail closed.
    func testTheSharedRecordThroughTheFile() throws {
        let ledger = FileLabelPhotoSpendLedger(url: url)
        try Data(#"{"cost":0.15,"day":"2026-10-25","openTaps":["t1"],"paused":false,"reads":3}"#.utf8).write(to: url)
        XCTAssertEqual(ledger.load(), .day(day))
        let shared = try ledger.update { stored in
            guard case let .day(previous) = stored else { throw CocoaError(.fileReadCorruptFile) }
            return PastedLabelAITextSpendPolicy.reservation(today: "2026-10-25", stored: previous, tap: "x1")
        }
        XCTAssertEqual(shared.reads, 4)
        XCTAssertEqual(shared.openTaps, ["t1"])
        XCTAssertEqual(shared.text.openTaps, ["x1"])
        XCTAssertEqual(FileLabelPhotoSpendLedger(url: url).load(), .day(shared))
        try Data(#"{"cost":0.15,"day":"2026-10-25","paused":false,"reads":3,"version":"label-ai-spend-day-v2","text":{}}"#.utf8).write(to: url)
        XCTAssertEqual(ledger.load(), .unreadable)
        XCTAssertEqual(PastedLabelAITextSpendPolicy.admission(today: "2026-10-25", stored: ledger.load()), .limitReached)
    }

    func testUpdateStoresAndReturnsTheDayItWrote() throws {
        let ledger = FileLabelPhotoSpendLedger(url: url)
        let stored = try ledger.update { previous in
            XCTAssertEqual(previous, .absent)
            return self.day
        }
        XCTAssertEqual(stored, day)
        XCTAssertEqual(ledger.load(), .day(day))
        XCTAssertEqual(FileLabelPhotoSpendLedger(url: url).load(), .day(day), "a new instance reads the same file")
    }

    func testUpdateThrowsOnlyWhenNothingWasStored() throws {
        let ledger = FileLabelPhotoSpendLedger(url: url)
        try ledger.update { _ in self.day }
        let before = try Data(contentsOf: url)
        // The transform refuses: nothing is written.
        struct Refused: Error {}
        XCTAssertThrowsError(try ledger.update { _ in throw Refused() })
        XCTAssertEqual(try Data(contentsOf: url), before)
        // The write itself fails (the directory is read-only): it throws, and the file is unchanged.
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: directory.path)
        let next = LabelPhotoSpendPolicy.Day(day: "2026-10-25", reads: 4, cost: Decimal(string: "0.20")!, paused: false)
        XCTAssertThrowsError(try ledger.update { _ in next })
        XCTAssertEqual(try Data(contentsOf: url), before)
        XCTAssertEqual(ledger.load(), .day(day))
    }
}
