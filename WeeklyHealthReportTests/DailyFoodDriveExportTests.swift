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

    /// #304, #307: v4 and v5 files already on Drive still validate (reconcile and recovery read
    /// them); the policy emits the current version (v6) only, derived from `FoodIntakeSummary`
    /// (gate G1), and an unpublished summary version is rejected.
    func testPolicyAcceptsEveryPublishedSummaryVersion() throws {
        let policy = DailyFoodExportIdentityPolicy()
        XCTAssertEqual(DailyFoodExportIdentityPolicy.summaryVersion, "food-intake-summary-v6")
        XCTAssertEqual(DailyFoodExportIdentityPolicy.summaryVersion, FoodIntakeSummary.version)
        // #312 (F8): the per-schema map in the shared shape rule replaces the policy's flat set.
        XCTAssertEqual(FoodDailyExportShape.acceptedSummaryVersions, [
            1: ["food-intake-summary-v4", "food-intake-summary-v5", "food-intake-summary-v6"],
            2: ["food-intake-summary-v6"],
            3: ["food-intake-summary-v6"],  // estimates on catalogue v2: schema 2's shape plus the estimate fields
            5: ["food-intake-summary-v6"],  // label photo estimates (#518): schema 3's shape plus the photo token
            7: ["food-intake-summary-v6"]   // Confirm enrichment (#549): schema 5's shape plus the OpenRouter estimate fields
        ])
        XCTAssertEqual(FoodDailyExportShape.acceptedSummaryVersions[FoodDailyExportDocument.schemaVersion]?
            .contains(DailyFoodExportIdentityPolicy.summaryVersion), true, "what this build writes is accepted")
        // Schema 1, as builds before #312 PR 3 wrote it: v4, v5 and v6 all validate.
        let text = String(decoding: try Self.schemaOne(fromEmptyDay: try foodBytes()), as: UTF8.self)
        XCTAssertTrue(text.contains(#""summary_version":"food-intake-summary-v6""#))
        XCTAssertNoThrow(try policy.validate(payload: Data(text.utf8), reportDate: reportDate), "schema 1 with v6")
        for earlier in ["food-intake-summary-v4", "food-intake-summary-v5"] {
            let payload = Data(text.replacingOccurrences(of: "food-intake-summary-v6", with: earlier).utf8)
            XCTAssertEqual(try FoodDailyExportSerializer.encode(FoodDailyExportSerializer.decode(payload)), payload, "a canonical \(earlier) payload")
            XCTAssertNoThrow(try policy.validate(payload: payload, reportDate: reportDate), earlier)
        }
        let unpublished = Data(text.replacingOccurrences(of: "food-intake-summary-v6", with: "food-intake-summary-v9").utf8)
        XCTAssertThrowsError(try policy.validate(payload: unpublished, reportDate: reportDate)) {
            XCTAssertEqual($0 as? DailyDriveExportFailure, .invalidPayload)
        }

        // The frozen v4 golden written before #304 and the v5 goldens written before #307.
        let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../docs/fixtures/food-daily-v1").standardizedFileURL
        let v4 = try Data(contentsOf: directory.appendingPathComponent("food-daily-plain-water-only-summary-v4.json"))
        XCTAssertEqual(try FoodDailyExportSerializer.decode(v4).summaryVersion, "food-intake-summary-v4")
        XCTAssertNoThrow(try policy.validate(payload: v4, reportDate: "2023-11-14"))
        let v5 = try Data(contentsOf: directory.appendingPathComponent("food-daily-plain-water-only-summary-v5.json"))
        XCTAssertEqual(try FoodDailyExportSerializer.decode(v5).summaryVersion, "food-intake-summary-v5")
        XCTAssertNoThrow(try policy.validate(payload: v5, reportDate: "2023-11-14"))
    }

    // MARK: Schema 2 readers (#312, PR 2; contract test 11)

    /// Contract 3.4, the constant sentence a schema-2 file carries.
    static let quantityEstimatesNote = "quantity.amount_method.is_estimate marks an amount that was estimated (a typical weight, the whole-milk volume rule or an estimate by eye). Every nutrient value in that entry is scaled from the estimated amount, including values whose state is measured. is_estimate false means no estimate rule was recorded for the amount, not that the amount was measured. The code recorded means the method is not described."

    /// The builder's empty-day schema-2 payload as the schema-1 file of the same instants, as
    /// builds before #312 PR 3 wrote it: the schema number, and no `quantity_estimates` sentence
    /// (an empty day has no entry to carry `amount_method`).
    static func schemaOne(fromEmptyDay payload: Data) throws -> Data {
        var text = String(decoding: payload, as: UTF8.self)
        for (old, new) in [(#""food_daily_schema_version":2,"#, #""food_daily_schema_version":1,"#),
                           (#","quantity_estimates":"\#(quantityEstimatesNote)""#, "")] {
            guard text.components(separatedBy: old).count == 2 else { throw DailyDriveExportFailure.invalidPayload }
            text = text.replacingOccurrences(of: old, with: new)
        }
        return Data(text.utf8)
    }

    private func fixture(_ path: String) throws -> Data {
        try Data(contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../docs/fixtures/\(path)").standardizedFileURL)
    }

    private func assertInvalid(_ payload: Data, reportDate: String? = nil, _ message: String,
                               file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try DailyFoodExportIdentityPolicy().validate(payload: payload, reportDate: reportDate ?? self.reportDate),
                             message, file: file, line: line) {
            XCTAssertEqual($0 as? DailyDriveExportFailure, .invalidPayload, message, file: file, line: line)
        }
    }

    /// The app writes schema 2 (#312 PR 3) and still reads schema 1, with the same file name,
    /// owner key and ordering token form for both.
    func testPolicyAcceptsSchemaTwoWithUnchangedIdentityAndOrdering() throws {
        let policy = DailyFoodExportIdentityPolicy()
        let v2 = try foodBytes()
        XCTAssertTrue(String(decoding: v2, as: UTF8.self).contains(#""food_daily_schema_version":2,"#), "the writer emits schema 2")
        XCTAssertTrue(String(decoding: v2, as: UTF8.self).contains(#""quantity_estimates":"\#(Self.quantityEstimatesNote)""#))
        let v1 = try Self.schemaOne(fromEmptyDay: v2)
        XCTAssertEqual(try FoodDailyExportSerializer.decode(v1).foodDailySchemaVersion, 1)
        XCTAssertEqual(try FoodDailyExportSerializer.encode(FoodDailyExportSerializer.decode(v1)), v1, "a canonical schema-1 payload")
        let first = try policy.validate(payload: v1, reportDate: reportDate)
        let second = try policy.validate(payload: v2, reportDate: reportDate)
        XCTAssertEqual(second.orderingToken, first.orderingToken, "the token names the ordering format, not the schema")
        XCTAssertEqual(second.orderingToken, "food-v1|2026-09-06T08:00:00.000+01:00|2026-09-06T08:00:00.500+01:00")
        XCTAssertNotEqual(second.payloadSHA256, first.payloadSHA256)
        XCTAssertEqual(second.payloadSHA256, DailyDriveExportCoordinator.sha256(v2))
        // Ordering across schemas is by cutoff and then preparation time, as within schema 1.
        let later = try policy.validate(payload: try foodBytes(exportedAfter: 60), reportDate: reportDate)
        XCTAssertEqual(try policy.compare(first.orderingToken, later.orderingToken), .orderedAscending)
        XCTAssertEqual(try policy.compare(later.orderingToken, first.orderingToken), .orderedDescending)
        XCTAssertThrowsError(try policy.validate(payload: v2, reportDate: "2026-09-05"), "another day's schema-2 file")
    }

    /// F8: schema 2 accepts summary v6 only; schema 1 keeps v4, v5 and v6.
    func testPolicyAppliesThePerSchemaSummaryMap() throws {
        let v2 = String(decoding: try foodBytes(), as: UTF8.self)
        for earlier in ["food-intake-summary-v4", "food-intake-summary-v5", "food-intake-summary-v9"] {
            let payload = Data(v2.replacingOccurrences(of: "food-intake-summary-v6", with: earlier).utf8)
            XCTAssertEqual(try FoodDailyExportSerializer.encode(FoodDailyExportSerializer.decode(payload)), payload, "canonical bytes")
            assertInvalid(payload, "schema 2 with \(earlier)")
        }
    }

    /// Fail closed: an unknown schema number, a mixed file, a broken closed-table row, a missing
    /// key and a null where the key must be absent are all invalid payloads.
    func testPolicyRejectsUnknownSchemasMixedFilesAndBrokenAmountMethods() throws {
        let v1 = String(decoding: try Self.schemaOne(fromEmptyDay: try foodBytes()), as: UTF8.self)
        let v2 = String(decoding: try foodBytes(), as: UTF8.self)
        for schema in [0, 3, 4] {
            for text in [v1, v2] {
                let payload = Data(text.replacing(#/"food_daily_schema_version":\d,/#,
                                                  with: "\"food_daily_schema_version\":\(schema),").utf8)
                XCTAssertEqual(try FoodDailyExportSerializer.decode(payload).foodDailySchemaVersion, schema)
                assertInvalid(payload, "schema \(schema)")
            }
        }
        assertInvalid(Data(v1.replacingOccurrences(of: #""food_daily_schema_version":1,"#, with: #""food_daily_schema_version":2,"#).utf8),
                      "schema 2 without quantity_estimates")
        assertInvalid(Data(v2.replacingOccurrences(of: #""food_daily_schema_version":2,"#, with: #""food_daily_schema_version":1,"#).utf8),
                      "schema 1 with quantity_estimates")

        let day = "2023-11-14"
        let typicalV1 = String(decoding: try fixture("food-daily-v1/food-daily-typical-weight-day.json"), as: UTF8.self)
        let typicalV2 = String(decoding: try fixture("food-daily-v2/food-daily-typical-weight-day.json"), as: UTF8.self)
        XCTAssertNoThrow(try DailyFoodExportIdentityPolicy().validate(payload: Data(typicalV2.utf8), reportDate: day))
        /// `canonical` true: the edited bytes still decode and re-encode exactly, so only the
        /// shape rule can be what rejects them. False: decode or the exact-byte check rejects.
        func edit(_ text: String, _ old: String, _ new: String, canonical: Bool = true, _ message: String, line: UInt = #line) {
            XCTAssertEqual(text.components(separatedBy: old).count, 2, "one occurrence of \(old)", line: line)
            let payload = Data(text.replacingOccurrences(of: old, with: new).utf8)
            let reencoded = (try? FoodDailyExportSerializer.decode(payload)).flatMap { try? FoodDailyExportSerializer.encode($0) }
            XCTAssertEqual(reencoded == payload, canonical, "canonical bytes: \(message)", line: line)
            assertInvalid(payload, reportDate: day, message, line: line)
        }
        let method = #""amount_method":{"code":"direct","entered":null,"is_estimate":false,"source":null},"#
        edit(typicalV1, #""quantity":{"amount":132,"#, #""quantity":{"amount":132,\#(method)"#, "schema 1 carrying amount_method")
        edit(typicalV1, #""quantity":{"amount":132,"#, #""quantity":{"amount":132,"amount_method":null,"#,
             canonical: false, "a null amount_method is not the absent key (exact bytes)")
        edit(typicalV2, #""food_daily_schema_version":2,"#, #""food_daily_schema_version":1,"#, "schema 1 carrying both v2 fields")
        edit(typicalV2, #""code":"typical_weight""#, #""code":"plate""#, "a code outside the closed set")
        edit(typicalV2, #""is_estimate":true"#, #""is_estimate":false"#, "is_estimate differing from the table")
        edit(typicalV2, #""size":"medium""#, #""size":null"#, "a typical weight without a size")
        edit(typicalV2, #""size":"medium""#, #""size":"jumbo""#, "a size outside the set")
        edit(typicalV2, #""entered":{"amount":3,"unit":"count"}"#, #""entered":{"amount":3,"unit":"piece"}"#, "an entered unit outside the set")
        edit(typicalV2, #""entered":{"amount":3,"unit":"count"},"#, "", canonical: false, "entered omitted rather than null")
        edit(typicalV2, #","size":"medium""#, "", canonical: false, "size omitted rather than null")
        edit(typicalV2, #""quantity_estimates":"#, #""quantity_estimate":"#, canonical: false, "a misspelt notes key")
        // Completed by the exact-byte check (gate finding 2): a null where the key must be absent,
        // an unknown key and a non-canonical number all decode, and none is accepted.
        edit(typicalV1, #"","unknown_values":""#, #"","quantity_estimates":null,"unknown_values":""#, canonical: false, "a null quantity_estimates in schema 1")
        edit(typicalV2, #""is_estimate":true,"#, #""is_estimate":true,"plate":true,"#, canonical: false, "an unknown key inside amount_method")
        edit(typicalV2, #""entered":{"amount":3,"unit":"count"}"#, #""entered":{"amount":3.0,"unit":"count"}"#, canonical: false, "a non-canonical entered amount")
        edit(typicalV2, #""size":"medium","#, #""size":"medium","sized_by":"you","#, canonical: false, "an unknown key inside source")
        let sourceStart = try XCTUnwrap(typicalV2.range(of: #","source":{"#)), sourceEnd = try XCTUnwrap(typicalV2.range(of: #"},"unit":"g""#))
        let withoutSource = typicalV2.replacingCharacters(in: sourceStart.lowerBound..<sourceEnd.lowerBound, with: #","source":null"#)
        XCTAssertEqual(try FoodDailyExportSerializer.encode(FoodDailyExportSerializer.decode(Data(withoutSource.utf8))),
                       Data(withoutSource.utf8), "canonical bytes")
        assertInvalid(Data(withoutSource.utf8), reportDate: day, "a typical weight without its source")
    }

    /// Contract test 8 at the policy: every frozen schema-1 golden and every hand-built schema-2
    /// fixture passes reconcile and recovery validation as the bytes on disk.
    func testPolicyAcceptsEveryFrozenV1GoldenAndEveryV2Fixture() throws {
        let policy = DailyFoodExportIdentityPolicy()
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../docs/fixtures").standardizedFileURL
        var counts: [String: Int] = [:]
        for (folder, schema) in [("food-daily-v1", 1), ("food-daily-v2", 2)] {
            let directory = root.appendingPathComponent(folder)
            for file in try FileManager.default.contentsOfDirectory(atPath: directory.path).filter({ $0.hasSuffix(".json") }) {
                let payload = try Data(contentsOf: directory.appendingPathComponent(file))
                XCTAssertEqual(try FoodDailyExportSerializer.decode(payload).foodDailySchemaVersion, schema, file)
                let identity = try policy.validate(payload: payload, reportDate: "2023-11-14")
                XCTAssertEqual(identity.orderingToken, "food-v1|2023-11-15T00:00:00.000Z|2023-11-15T09:00:00.125Z", file)
                counts[folder, default: 0] += 1
            }
        }
        XCTAssertEqual(counts, ["food-daily-v1": 8, "food-daily-v2": 6])
    }

    /// Daily export version 3 (estimates on catalogue v2): admitted through the same shape rule, under
    /// the same ordering format, so schema 2 and 3 files replace each other for a date in both
    /// directions. A schema 2 file carrying an estimate field, and a schema 3 file with no approved
    /// estimate, are refused.
    func testPolicyAcceptsSchemaThreeAndRefusesAMixedFile() throws {
        let policy = DailyFoodExportIdentityPolicy()
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../docs/fixtures").standardizedFileURL
        let v3 = try Data(contentsOf: root.appendingPathComponent("food-daily-v3/food-daily-estimates-day.json"))
        XCTAssertEqual(try FoodDailyExportSerializer.decode(v3).foodDailySchemaVersion, 3)
        let identity = try policy.validate(payload: v3, reportDate: "2023-11-14")
        XCTAssertTrue(identity.orderingToken.hasPrefix("food-v1|"), "the token names the ordering format, not the schema")
        let v2 = try Data(contentsOf: root.appendingPathComponent("food-daily-v2/food-daily-mixed-day.json"))
        let other = try policy.validate(payload: v2, reportDate: "2023-11-14")
        // Either may replace the other: the comparison reads only the two instants.
        XCTAssertNotEqual(try policy.compare(identity.orderingToken, other.orderingToken), .orderedSame)
        XCTAssertEqual(try policy.compare(identity.orderingToken, other.orderingToken) == .orderedAscending,
                       try policy.compare(other.orderingToken, identity.orderingToken) == .orderedDescending)
        func relabelled(_ payload: Data, from: Int, to: Int) -> Data {
            Data(String(decoding: payload, as: UTF8.self)
                .replacingOccurrences(of: "\"food_daily_schema_version\":\(from),", with: "\"food_daily_schema_version\":\(to),").utf8)
        }
        XCTAssertThrowsError(try policy.validate(payload: relabelled(v3, from: 3, to: 2), reportDate: "2023-11-14"),
                             "a schema 2 file carrying estimate fields")
        XCTAssertThrowsError(try policy.validate(payload: relabelled(v2, from: 2, to: 3), reportDate: "2023-11-14"),
                             "a schema 3 file with no approved estimate")
        // A value without its tier is refused.
        let noTier = Data(String(decoding: v3, as: UTF8.self).replacingOccurrences(of: "\"estimate_quality\":\"high\",", with: "").utf8)
        XCTAssertNotEqual(noTier, v3)
        XCTAssertThrowsError(try policy.validate(payload: noTier, reportDate: "2023-11-14"))
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
