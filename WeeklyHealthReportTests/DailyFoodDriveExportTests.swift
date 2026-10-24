import FoodLedgerApplication
import FoodLedgerDomain
import Foundation
import XCTest
@testable import DriveExportKit
@testable import WeeklyHealthReport

// Food daily export contract v1 (#287): the food identity policy, its own registry and marker,
// cross-policy rejection and the Export presentation helpers. Every value here is invented.
final class DailyFoodDriveExportTests: XCTestCase {
    private let reportDate = "2026-09-06"
    private let zone = TimeZone(identifier: "Europe/London")!
    /// 2026-09-06T08:00:00+01:00.
    private let cutoff = Date(timeIntervalSince1970: 1_788_678_000)
    private let token: DailyDriveExportCoordinator.TokenProvider = { _ in "invented-token" }

    private func foodBytes(exportedAfter seconds: TimeInterval = 0.5, cutoff: Date? = nil) throws -> Data {
        let document = try FoodDailyExportBuilder.make(FoodDailyExportRequest(
            records: LedgerMutation(), reportDate: reportDate, timeZone: zone, dataAsOf: cutoff ?? self.cutoff,
            exportedAt: (cutoff ?? self.cutoff).addingTimeInterval(seconds),
            appContext: FoodDailyExportAppContext(appVersion: "0.0.0", appBuild: "0")))
        return try FoodDailyExportSerializer.encode(document)
    }

    // MARK: Identity policy

    func testPolicyNamesTheFileAndKeysAndOrdersByCutoffThenPreparationTime() throws {
        let policy = DailyFoodExportIdentityPolicy()
        XCTAssertEqual(policy.filename(for: reportDate), "food-daily-2026-09-06.json")
        XCTAssertEqual(policy.ownerPropertyKey, "whrDailyFood")
        XCTAssertNotEqual(policy.ownerPropertyKey, DailyHealthExportIdentityPolicy().ownerPropertyKey)
        XCTAssertEqual(policy.orderingPropertyKey, "whrDataAsOf")
        let identity = try policy.validate(payload: try foodBytes(), reportDate: reportDate)
        XCTAssertEqual(identity.orderingToken, "food-v1|2026-09-06T08:00:00.000+01:00|2026-09-06T08:00:00.500+01:00")
        XCTAssertEqual(identity.payloadSHA256, DailyDriveExportCoordinator.sha256(try foodBytes()))

        // A corrected past-day re-export: the cutoff is the same next midnight, so only the
        // preparation time orders it; it is accepted, and an older token is still stale.
        let midnight = Date(timeIntervalSince1970: 1_788_649_200) // 2026-09-06T00:00:00+01:00
        let first = try policy.validate(payload: try foodBytes(exportedAfter: 3_600, cutoff: midnight), reportDate: reportDate)
        let corrected = try policy.validate(payload: try foodBytes(exportedAfter: 7_200, cutoff: midnight), reportDate: reportDate)
        XCTAssertEqual(try policy.compare(first.orderingToken, corrected.orderingToken), .orderedAscending)
        XCTAssertEqual(try policy.compare(corrected.orderingToken, first.orderingToken), .orderedDescending)
        XCTAssertEqual(try policy.compare(identity.orderingToken, first.orderingToken), .orderedDescending, "a later cutoff wins")
        XCTAssertEqual(try policy.compare(first.orderingToken, first.orderingToken), .orderedSame)
        // The food parser reads its own millisecond form only.
        XCTAssertThrowsError(try policy.compare("2026-09-06T08:00:00+01:00", identity.orderingToken))
        XCTAssertThrowsError(try policy.compare("historical-v2|2026-09-06T08:00:00+01:00|2026-09-06T09:00:00+01:00", identity.orderingToken))
        XCTAssertThrowsError(try policy.compare("food-v1|2026-09-06T08:00:00.000+01:00|2026-09-06T07:00:00.000+01:00",
                                                identity.orderingToken), "exported before the cutoff")
    }

    func testPolicyRejectsNonCanonicalOtherDayAndEarlyExportedPayloads() throws {
        let policy = DailyFoodExportIdentityPolicy()
        let bytes = try foodBytes()
        let text = String(decoding: bytes, as: UTF8.self)
        let spaced = Data(text.replacingOccurrences(of: #"{"app_context""#, with: #"{ "app_context""#).utf8)
        XCTAssertThrowsError(try policy.validate(payload: spaced, reportDate: reportDate)) {
            XCTAssertEqual($0 as? DailyDriveExportFailure, .invalidPayload, "non-canonical bytes")
        }
        XCTAssertThrowsError(try policy.validate(payload: bytes, reportDate: "2026-09-05"))
        let early = Data(text.replacingOccurrences(of: #""exported_at":"2026-09-06T08:00:00.500+01:00""#,
                                                   with: #""exported_at":"2026-09-06T07:59:59.999+01:00""#).utf8)
        XCTAssertNotEqual(early, bytes)
        XCTAssertThrowsError(try policy.validate(payload: early, reportDate: reportDate)) {
            XCTAssertEqual($0 as? DailyDriveExportFailure, .invalidPayload, "exported_at earlier than data_as_of")
        }
    }

    /// #304: v4 files already on Drive still validate (reconcile and recovery read them); the
    /// policy emits v5 only, and an unpublished summary version is rejected.
    func testPolicyAcceptsEveryPublishedSummaryVersion() throws {
        let policy = DailyFoodExportIdentityPolicy()
        XCTAssertEqual(DailyFoodExportIdentityPolicy.summaryVersion, "food-intake-summary-v5")
        XCTAssertEqual(DailyFoodExportIdentityPolicy.acceptedSummaryVersions, ["food-intake-summary-v4", "food-intake-summary-v5"])
        let text = String(decoding: try foodBytes(), as: UTF8.self)
        XCTAssertTrue(text.contains(#""summary_version":"food-intake-summary-v5""#))
        let v4 = Data(text.replacingOccurrences(of: "food-intake-summary-v5", with: "food-intake-summary-v4").utf8)
        XCTAssertEqual(try FoodDailyExportSerializer.encode(FoodDailyExportSerializer.decode(v4)), v4, "a canonical v4 payload")
        XCTAssertNoThrow(try policy.validate(payload: v4, reportDate: reportDate))
        let unpublished = Data(text.replacingOccurrences(of: "food-intake-summary-v5", with: "food-intake-summary-v9").utf8)
        XCTAssertThrowsError(try policy.validate(payload: unpublished, reportDate: reportDate)) {
            XCTAssertEqual($0 as? DailyDriveExportFailure, .invalidPayload)
        }

        // The frozen v4 golden written before #304 (docs/fixtures/food-daily-v1).
        let golden = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../docs/fixtures/food-daily-v1/food-daily-plain-water-only-summary-v4.json").standardizedFileURL
        let bytes = try Data(contentsOf: golden)
        XCTAssertEqual(try FoodDailyExportSerializer.decode(bytes).summaryVersion, "food-intake-summary-v4")
        XCTAssertNoThrow(try policy.validate(payload: bytes, reportDate: "2023-11-14"))
    }

    func testEachPolicyRejectsTheOtherFilesPayload() throws {
        let food = try foodBytes()
        XCTAssertThrowsError(try DailyHealthExportIdentityPolicy().validate(payload: food, reportDate: reportDate)) {
            XCTAssertEqual($0 as? DailyDriveExportFailure, .invalidPayload)
        }
        let health = Data(#"{"schema_version":8,"report_date":"2026-09-06"}"#.utf8)
        XCTAssertThrowsError(try DailyFoodExportIdentityPolicy().validate(payload: health, reportDate: reportDate)) {
            XCTAssertEqual($0 as? DailyDriveExportFailure, .invalidPayload)
        }
    }

    // MARK: Registries and markers

    func testTheFoodRegistryAndMarkerUseTheirOwnKeys() throws {
        let keychain = MemorySecureStore()
        let health = KeychainDailyDriveExportIdentityStore(keychain: keychain)
        let food = KeychainDailyDriveExportIdentityStore.food(keychain: keychain)
        try health.save(DailyDriveExportRegistry(installationID: "health-installation"))
        XCTAssertNil(try food.load())
        XCTAssertNil(try food.installationMarker(), "a health export creates no food marker")
        try food.save(DailyDriveExportRegistry(installationID: "food-installation"))
        XCTAssertEqual(try health.installationMarker(), "health-installation")
        XCTAssertEqual(try food.installationMarker(), "food-installation")
        XCTAssertEqual(keychain.accounts.sorted(), [
            "google.drive.daily-export-identities.v1", "google.drive.daily-export-installation.v1",
            "google.drive.daily-food-export-identities.v1", "google.drive.daily-food-export-installation.v1"
        ])
    }

    // MARK: Presentation

    func testPresentationHelpersAndTheSharedTokenPrefix() throws {
        XCTAssertEqual(DailyExportLastExportFormatter.foodOrderingVersion, DailyFoodExportIdentityPolicy.orderingVersion)
        XCTAssertEqual(DailyFoodExportIdentityPolicy.summaryVersion, FoodIntakeSummary.version)
        let token = "food-v1|2026-09-06T08:00:00.000+01:00|2026-09-06T08:00:00.500+01:00"
        XCTAssertEqual(DailyExportLastExportFormatter.cutoffDate(token), cutoff)
        XCTAssertEqual(DailyExportFileResult.line(nil), "Not sent")
        XCTAssertEqual(DailyExportFileResult.line(DailyExportOutcomeRecord(reportDate: reportDate, dataAsOf: token, kind: .failed)),
                       "Not verified")
        let document = try FoodDailyExportSerializer.decode(try foodBytes())
        let preview = DailyFoodExportPreview(document: document, bytes: try foodBytes())
        XCTAssertEqual(DailyExportFoodSummary.line(preview), "no entries · \(preview.bytes.count.formatted()) bytes")
        let fields = FoodDailyExportDeveloperFields.fields(.prepared(preview),
                                                           record: DailyFoodDriveRecord(fileID: "file-1", lastVerifiedToken: token))
        XCTAssertEqual(fields.map(\.label), ["Schema version", "Report date", "Byte count", "SHA-256", "Entry count",
                                             "Ordering token", "Drive file ID", "Last verified token"])
        XCTAssertEqual(fields[3].value, DailyDriveExportCoordinator.sha256(preview.bytes))
        XCTAssertEqual(fields.last?.value, token)
        XCTAssertEqual(FoodDailyExportDeveloperFields.fields(.off, record: nil).first?.value, "Food log is off")
        XCTAssertEqual(DailyFoodExportIdentityPolicy.displayOrderingToken(token),
                       "2026-09-06T08:00:00.000+01:00 (prepared 2026-09-06T08:00:00.500+01:00)")
    }

    private func londonCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        calendar.locale = Locale(identifier: "en_GB")
        return calendar
    }
}

private final class MemorySecureStore: DailyDriveSecurePersisting, @unchecked Sendable {
    private var values: [String: Data] = [:]
    var accounts: [String] { Array(values.keys) }
    func save(_ data: Data, account: String) throws { values[account] = data }
    func load(account: String) throws -> Data? { values[account] }
    func delete(account: String) throws { values.removeValue(forKey: account) }
}
