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
