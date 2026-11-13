import FoodLedgerApplication
import FoodLedgerDomain
import FoodLedgerTestSupport
import Foundation
import XCTest

/// The importer's contract (phase 1 plan sections 3 and 3.1): synthetic fixtures only.
final class PersonalFoodDatabaseImporterTests: XCTestCase {
    static let fixtures = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("docs/fixtures/personal-food-database-v1")

    static func fixture(_ name: String) throws -> Data { try Data(contentsOf: fixtures.appendingPathComponent(name)) }

    /// The golden file with one Open Food Facts attribution changed: still valid, so its release ID
    /// is the golden file's with different fields.
    static func conflictingGolden() throws -> Data {
        let golden = try String(decoding: fixture("golden.json"), as: UTF8.self)
        return Data(golden.replacingOccurrences(of: "product/00000017", with: "product/00000018").utf8)
    }

    struct FixedClock: LedgerClock {
        let date: Date
        func now() -> Date { date }
    }

    final class Releases: FoodConfirmationReading, @unchecked Sendable {
        var stored: [SourceRelease] = []
        var fails = false
        func sourceRelease(id: ExternalIdentifier) throws -> SourceRelease? {
            if fails { throw FoodLedgerValidationError.invalidDigest }
            return stored.first { $0.sourceReleaseID == id }
        }
        func foodConfirmation(logItemID: LogItemID) throws -> StoredFoodConfirmation? { nil }
        func foodConfirmation(logItemVersionID: LogItemVersionID) throws -> StoredFoodConfirmation? { nil }
        func evidence(id: EvidenceID) throws -> CaptureEvidence? { nil }
    }

    let now = Date(timeIntervalSince1970: 1_794_000_000.75)
    var store: InMemoryPersonalFoodDatabaseStore!
    var releases: Releases!
    var importer: PersonalFoodDatabaseImporter!

    override func setUp() {
        store = InMemoryPersonalFoodDatabaseStore()
        releases = Releases()
        importer = PersonalFoodDatabaseImporter(store: store, digester: SHA256Digester(), clock: FixedClock(date: now), releases: releases)
    }

    func summary(_ outcome: PersonalFoodDatabaseImportOutcome) -> PersonalFoodDatabaseSummary? {
        switch outcome {
        case let .installed(summary), let .added(summary): return summary
        default: return nil
        }
    }

    func testGoldenInstallsWithItsReleaseIdentity() async throws {
        let bytes = try Self.fixture("golden.json")
        let digest = try SHA256Digester().sha256(bytes)
        let file = try PersonalFoodDatabaseCodec.decode(bytes).get()
        let i1 = await importer.importFile(bytes)
        let installed = try XCTUnwrap(summary(i1))
        XCTAssertEqual(installed.releaseID, "pfc:sha256:\(digest.value)")
        XCTAssertEqual(installed.entryCount, file.entries.count)
        XCTAssertEqual(installed.generated, file.generated)
        XCTAssertEqual(installed.importedAt, Date(timeIntervalSince1970: 1_794_000_000), "whole seconds")
        XCTAssertEqual(try store.activeRelease()?.bytes, bytes)
        let status = await importer.status()
        XCTAssertEqual(status, .installed(installed))
    }

    func testRejectedFileInstallsNothingAndKeepsTheActiveRelease() async throws {
        let golden = try Self.fixture("golden.json")
        _ = await importer.importFile(golden)
        let outcome = await importer.importFile(try Self.fixture("reject-unknown-schema.json"))
        guard case let .rejected(codes) = outcome else { return XCTFail("\(outcome)") }
        XCTAssertTrue(codes.contains(.schema))
        XCTAssertEqual(try store.activeRelease()?.bytes, golden)
    }

    func testSameBytesTwiceIsUnchanged() async throws {
        let bytes = try Self.fixture("golden.json")
        let i2 = await importer.importFile(bytes)
        let first = try XCTUnwrap(summary(i2))
        let again = await importer.importFile(bytes)
        XCTAssertEqual(again, .unchanged(first))
    }

    func testSameBytesOverADamagedReleaseReinstall() async throws {
        let bytes = try Self.fixture("golden.json")
        _ = await importer.importFile(bytes)
        store.damaged = true
        let damaged = await importer.status()
        XCTAssertEqual(damaged, .damaged)
        let i3 = await importer.importFile(bytes)
        XCTAssertNotNil(summary(i3))
        XCTAssertEqual(try store.activeRelease()?.bytes, bytes)
    }

    func testLedgerReleaseWithDifferentFieldsIsAConflict() async throws {
        let golden = try Self.fixture("golden.json")
        _ = await importer.importFile(try Self.fixture("accept-empty-brand.json"))
        let before = try store.activeRelease()
        let variant = try PersonalFoodDatabaseCodec.decode(try Self.conflictingGolden()).get()
        releases.stored = try variant.sources.map { try $0.sourceRelease() }
        let outcome = await importer.importFile(golden)
        XCTAssertEqual(outcome, .releaseConflict)
        XCTAssertEqual(try store.activeRelease(), before)
    }

    func testActiveFileReleaseWithDifferentFieldsIsAConflict() async throws {
        let variant = try Self.conflictingGolden()
        let i4 = await importer.importFile(variant)
        XCTAssertNotNil(summary(i4))
        let outcome = await importer.importFile(try Self.fixture("golden.json"))
        XCTAssertEqual(outcome, .releaseConflict)
        XCTAssertEqual(try store.activeRelease()?.bytes, variant)
    }

    func testDamagedActiveFileSkipsOnlyTheActiveComparison() async throws {
        _ = await importer.importFile(try Self.conflictingGolden())
        store.damaged = true
        let i5 = await importer.importFile(try Self.fixture("golden.json"))
        XCTAssertNotNil(summary(i5))
        // The ledger comparison still applies over a damaged release.
        store.damaged = true
        let variant = try PersonalFoodDatabaseCodec.decode(try Self.fixture("golden.json")).get()
        releases.stored = try variant.sources.map { try $0.sourceRelease() }
        let outcome = await importer.importFile(try Self.conflictingGolden())
        XCTAssertEqual(outcome, .releaseConflict)
    }

    func testEqualStoredReleasesPass() async throws {
        let bytes = try Self.fixture("golden.json")
        let file = try PersonalFoodDatabaseCodec.decode(bytes).get()
        releases.stored = try file.sources.map { try $0.sourceRelease() }
            + [PersonalFoodDatabaseRelease.sourceRelease(fileSHA256: SHA256Digester().sha256(bytes), generated: file.generated, schema: .v1)]
        let i6 = await importer.importFile(bytes)
        XCTAssertNotNil(summary(i6))
    }

    /// Import v2: the manifest records the file's own schema, the v1 golden's stays v1, and the stored
    /// v1 database release still compares equal (no conflict on re-import after this change).
    func testV2FileRecordsItsSchemaAndV1KeepsV1() async throws {
        let v1 = try Self.fixture("golden.json")
        let v1File = try PersonalFoodDatabaseCodec.decode(v1).get()
        releases.stored = try v1File.sources.map { try $0.sourceRelease() }
            + [PersonalFoodDatabaseRelease.sourceRelease(fileSHA256: SHA256Digester().sha256(v1), generated: v1File.generated,
                                                         schema: .v1)]
        let first = await importer.importFile(v1)
        XCTAssertNotNil(summary(first))
        XCTAssertEqual(try store.activeRelease()?.manifest.schema, "personal-food-catalogue-v1")
        let v2 = try Data(contentsOf: Self.fixtures.deletingLastPathComponent()
            .appendingPathComponent("personal-food-database-v2/golden.json"))
        let second = await importer.importFile(v2)
        XCTAssertNotNil(summary(second))
        XCTAssertEqual(try store.activeRelease()?.manifest.schema, "personal-food-catalogue-v2")
        let release = try PersonalFoodDatabaseRelease.sourceRelease(fileSHA256: SHA256Digester().sha256(v2),
            generated: PersonalFoodDatabaseCodec.decode(v2).get().generated, schema: .v2)
        XCTAssertEqual(release.schemaVersion.value, "personal-food-catalogue-v2")
    }

    /// Qodo (local review): a manifest naming another schema than its file reads as damaged, as the
    /// search index reads it, and importing the same bytes repairs it instead of answering unchanged.
    func testAManifestSchemaMismatchIsDamagedAndReimportRepairsIt() async throws {
        let v2 = try Data(contentsOf: Self.fixtures.deletingLastPathComponent()
            .appendingPathComponent("personal-food-database-v2/golden.json"))
        let digest = try SHA256Digester().sha256(v2)
        let file = try PersonalFoodDatabaseCodec.decode(v2).get()
        try store.install(bytes: v2, manifest: PersonalFoodDatabaseManifest(schema: PersonalFoodDatabaseSchema.v1.rawValue,
            releaseID: PersonalFoodDatabaseRelease.releaseID(fileSHA256: digest), fileSHA256: digest, generated: file.generated,
            importedAt: Date(timeIntervalSince1970: 1_794_000_000), entryCount: file.entries.count))
        let before = await importer.status()
        XCTAssertEqual(before, .damaged)
        let outcome = await importer.importFile(v2)
        XCTAssertNotNil(summary(outcome), "repaired, not unchanged: \(outcome)")
        XCTAssertEqual(try store.activeRelease()?.manifest.schema, "personal-food-catalogue-v2")
        let after = await importer.status()
        guard case .installed = after else { return XCTFail("expected installed, got \(after)") }
        XCTAssertEqual(PersonalFoodDatabaseCodec.declaredSchema(v2), .v2)
        XCTAssertNil(PersonalFoodDatabaseCodec.declaredSchema(Data(#"{"schema":"personal-food-catalogue-v3"}"#.utf8)))
        XCTAssertNil(PersonalFoodDatabaseCodec.declaredSchema(Data("not json".utf8)))
    }

    func testFailureOutcomes() async throws {
        let bytes = try Self.fixture("golden.json")
        let tooLarge = await importer.importFile(Data(count: PersonalFoodDatabaseCodec.limitBytes + 1))
        XCTAssertEqual(tooLarge, .tooLarge)
        releases.fails = true
        let ledger = await importer.importFile(bytes)
        XCTAssertEqual(ledger, .ledgerUnavailable)
        releases.fails = false
        store.failWrites = true
        let write = await importer.importFile(bytes)
        XCTAssertEqual(write, .writeFailed)
        store.failWrites = false
        store.locked = true
        let locked = await importer.importFile(bytes)
        XCTAssertEqual(locked, .locked)
        let lockedStatus = await importer.status()
        XCTAssertEqual(lockedStatus, .locked)
        let lockedRemove = await importer.remove()
        XCTAssertEqual(lockedRemove, .locked)
        store.locked = false
        let none = await importer.status()
        XCTAssertEqual(none, .none)
    }

    func testRemove() async throws {
        let bytes = try Self.fixture("golden.json")
        let file = try PersonalFoodDatabaseCodec.decode(bytes).get()
        releases.stored = try file.sources.map { try $0.sourceRelease() }
        _ = await importer.importFile(bytes)
        let removed = await importer.remove()
        XCTAssertEqual(removed, .removed)
        let again = await importer.remove()
        XCTAssertEqual(again, .nothingToRemove)
        let status = await importer.status()
        XCTAssertEqual(status, .none)
        XCTAssertEqual(releases.stored.count, file.sources.count, "remove never touches release records")
    }

    /// Phase 1 plan section 5: a first import is "added"; replacing an active release is "installed".
    func testFirstImportIsAddedAndAReplacementIsInstalled() async throws {
        let golden = try Self.fixture("golden.json")
        guard case .added = await importer.importFile(golden) else { return XCTFail("first import") }
        let other = Data(String(decoding: golden, as: UTF8.self).replacingOccurrences(of: "Synthetic Example Oats", with: "Synthetic Example Oat Flakes").utf8)
        guard case .installed = await importer.importFile(other) else { return XCTFail("replacement") }
    }
}
