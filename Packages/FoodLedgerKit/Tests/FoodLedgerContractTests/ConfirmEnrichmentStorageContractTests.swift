import Foundation
@testable import FoodLedgerApplication
import FoodLedgerDomain
import FoodLedgerGRDB
import FoodLedgerTestSupport
import GRDB
import XCTest

/// Confirm enrichment v1, PR 1 (docs/confirm-enrichment-openrouter-v1-phase.md sections 2.7 and 2.8, G4 and
/// the export half of CE1 test 9): food contract 13 with 12 refused, store 13 and its metadata-only
/// migration, and daily export version 7. Synthetic data only.
final class ConfirmEnrichmentStorageContractTests: XCTestCase {
    typealias F = ConfirmEnrichmentFixtures

    func testVersionsAllocatedByThePhaseGate() {
        XCTAssertEqual(CanonicalFoodProjection.foodContractVersion, 13)
        XCTAssertEqual(FoodLedgerGRDBStore.schemaVersion, 13)
        XCTAssertEqual(FoodDailyExportDocument.openRouterEstimatesSchemaVersion, 7)
        XCTAssertFalse(CanonicalFoodProjection.isAcceptedFoodContract(12))
        XCTAssertEqual((1...14).filter(CanonicalFoodProjection.isAcceptedFoodContract), Array(1...11) + [13])
    }

    // MARK: Contract floor and archives (2.7)

    /// Each kind of CE1 content on its own raises the floor to 13.
    static func contents() throws -> [String: LedgerMutation] {
        let built = try F.built()
        var capture = LedgerMutation(); capture.evidence = [built.captureEvidence]
        var choices = LedgerMutation(); choices.evidence = [built.choicesEvidence]
        let details = try CaptureEvidence(
            evidenceID: F.id(9003), kind: .labelText, capturedAt: F.capturedAt, locale: LedgerText("en_GB"),
            captureMethod: LedgerText(ConfirmEnrichmentVersions.detailsCaptureMethod),
            captureMethodVersion: LedgerText(ConfirmEnrichmentVersions.detailsCaptureMethodVersion),
            originalPayload: .text(LedgerText("{}")), byteHash: try LedgerFixtures.digester.sha256(Data("{}".utf8)))
        var detailsCapture = LedgerMutation(); detailsCapture.evidence = [details]
        return ["B capture": capture, "choices item": choices, "A capture": detailsCapture]
    }

    func testEachKindOfContentNeedsContractThirteen() throws {
        for (name, records) in try Self.contents() {
            XCTAssertEqual(CanonicalFoodProjection.minimumContractVersion(for: records), 13, name)
            XCTAssertTrue(CanonicalFoodProjection.holdsConfirmEnrichment(records), name)
        }
        XCTAssertEqual(CanonicalFoodProjection.minimumContractVersion(for: LedgerMutation()), 1)
    }

    func testAnArchiveBelowThirteenHoldingCE1ContentIsRejectedAndThirteenRoundTrips() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        for (name, records) in try Self.contents() {
            let projection = try CanonicalFoodProjection(records: records)
            XCTAssertEqual(projection.foodContractVersion, 13, name)
            let encoded = try encoder.encode(projection)
            let decoded = try JSONDecoder().decode(CanonicalFoodProjection.self, from: encoded)
            XCTAssertEqual(decoded, projection, name)
            XCTAssertEqual(try encoder.encode(decoded), encoded, name)
            var tree = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
            for label in [11, 12] {
                tree["foodContractVersion"] = label
                XCTAssertThrowsError(try JSONDecoder().decode(CanonicalFoodProjection.self,
                                                              from: JSONSerialization.data(withJSONObject: tree)), "\(name) at \(label)")
            }
            XCTAssertThrowsError(try CanonicalFoodProjection(records: records, foodContractVersion: 11), name)
        }
        // Contract 12 is refused at projection construction even with no CE1 content.
        XCTAssertThrowsError(try CanonicalFoodProjection(records: LedgerMutation(), foodContractVersion: 12)) {
            XCTAssertEqual($0 as? FoodArchiveError, .unsupportedFoodContract(12))
        }
        // An archive without CE1 content keeps its contract.
        XCTAssertEqual(try CanonicalFoodProjection(records: LedgerMutation()).foodContractVersion, CanonicalFoodProjection.exportFloorContractVersion)
    }

    func testTheManifestRefusesTwelveAndListsNoV12Migration() throws {
        func manifest(_ contract: Int) throws -> FoodArchiveManifest {
            try FoodArchiveManifest(ledgerID: LedgerText("ledger"), snapshotID: SHA256Digest(String(repeating: "0", count: 64)),
                                    createdAt: F.capturedAt, creatingActorID: try F.id(7), sourceReleaseIDs: [],
                                    watermarks: [], recordCount: 0, operationCount: 0, members: [], foodContractVersion: contract)
        }
        XCTAssertThrowsError(try manifest(12)) { XCTAssertEqual($0 as? FoodArchiveError, .unsupportedFoodContract(12)) }
        XCTAssertEqual(try manifest(13).migrationIdentifiers.map(\.value),
                       (1...11).map { "food-ledger-v\($0)" } + ["food-ledger-v13"])
        XCTAssertEqual(try manifest(11).migrationIdentifiers.map(\.value), (1...11).map { "food-ledger-v\($0)" })
    }

    // MARK: Store 13

    func testMigrationFromAPopulatedV11StoreChangesOnlyLedgerMetadata() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("confirm-enrichment-v13-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let database = directory.appendingPathComponent("food-ledger-v1.sqlite")
        do {
            let store = try FoodLedgerGRDBStore.temporary(directory: directory)
            _ = try LedgerFixtures.service(store).commit(LedgerFixtures.baseMutation(), type: .createProduct,
                                                         operationID: LedgerFixtures.operationID(10_549))
        }
        let queue = try DatabaseQueue(path: database.path)
        try queue.write { db in
            try db.execute(sql: "DELETE FROM grdb_migrations WHERE identifier = 'v13_confirm_enrichment'")
            try db.execute(sql: "UPDATE ledger_metadata SET value = 'food-ledger-v11' WHERE key = 'schema_identity'")
            try db.execute(sql: "PRAGMA user_version = 11")
        }
        let before = try ApprovedEstimateStorageContractTests.tableRows(queue)
        try queue.close()
        let migrated = try FoodLedgerGRDBStore.temporary(directory: directory)
        try migrated.verifyIntegrity()
        let check = try DatabaseQueue(path: database.path)
        let after = try ApprovedEstimateStorageContractTests.tableRows(check)
        XCTAssertEqual(Set(before.keys.filter { before[$0] != after[$0] }), ["ledger_metadata"], "Only ledger_metadata may change")
        try check.read { db in
            XCTAssertEqual(try Int.fetchOne(db, sql: "PRAGMA user_version"), 13)
            XCTAssertEqual(try String.fetchOne(db, sql: "SELECT value FROM ledger_metadata WHERE key = 'schema_identity'"), "food-ledger-v13")
            let identifiers = try String.fetchAll(db, sql: "SELECT identifier FROM grdb_migrations ORDER BY rowid")
            XCTAssertEqual(identifiers.last, "v13_confirm_enrichment")
            XCTAssertFalse(identifiers.contains { $0.hasPrefix("v12_") })
        }
    }

    // MARK: Daily export version 7 (2.8)

    static let responseHash = String(repeating: "c", count: 64)
    static var openRouterFields: [String: Any] { [
        "source_kind": "openrouter_estimate", "source_release_id": "confirm-enrichment-openrouter", "transforms": [Any](),
        "estimate_quality": "low", "estimate_model": F.model, "estimate_contract": "confirm-enrichment-openrouter-v1",
        "estimate_response_sha256": responseHash] }

    /// The mixed-day fixture with its first provenance made an OpenRouter estimate.
    func document(schema: Int, notes: Bool = true, _ change: (inout [String: Any]) -> Void = { _ in }) throws -> FoodDailyExportDocument {
        try ApprovedEstimateStorageContractTests.document { tree in
            tree["food_daily_schema_version"] = schema
            if notes {
                var n = try XCTUnwrap(tree["notes"] as? [String: Any])
                n["openrouter_estimates"] = FoodDailyExportNotes.openRouterEstimatesSentence
                tree["notes"] = n
            }
            var entries = try XCTUnwrap(tree["entries"] as? [[String: Any]])
            outer: for e in entries.indices {
                var nutrients = try XCTUnwrap(entries[e]["nutrients"] as? [[String: Any]])
                for i in nutrients.indices {
                    guard var provenance = nutrients[i]["provenance"] as? [[String: Any]], !provenance.isEmpty,
                          nutrients[i]["state"] as? String == "measured" || nutrients[i]["state"] as? String == "estimated" else { continue }
                    var first = provenance[0]
                    first = first.filter { ["source_url", "content_hash"].contains($0.key) == false }
                    first.merge(Self.openRouterFields) { _, new in new }
                    change(&first)
                    provenance = [first]
                    nutrients[i]["provenance"] = provenance
                    nutrients[i]["state"] = "estimated"
                    nutrients[i]["origin"] = "openrouter_estimate"
                    nutrients[i]["calculated"] = false
                    entries[e]["nutrients"] = nutrients
                    break outer
                }
            }
            tree["entries"] = entries
        }
    }

    func testSchemaSevenExactlyWithAnOpenRouterEstimate() throws {
        XCTAssertNoThrow(try FoodDailyExportShape.validate(try document(schema: 7)))
        // Earlier schemas reject the origin and its fields; version 7 needs its notes sentence.
        for schema in [2, 3, 5] {
            XCTAssertThrowsError(try FoodDailyExportShape.validate(try document(schema: schema)), "schema \(schema)")
        }
        XCTAssertThrowsError(try FoodDailyExportShape.validate(try document(schema: 7, notes: false)))
        // A version 7 file with no OpenRouter estimate is rejected.
        let plain = try ApprovedEstimateStorageContractTests.document { tree in
            tree["food_daily_schema_version"] = 7
            var n = try XCTUnwrap(tree["notes"] as? [String: Any])
            n["openrouter_estimates"] = FoodDailyExportNotes.openRouterEstimatesSentence
            tree["notes"] = n
        }
        XCTAssertThrowsError(try FoodDailyExportShape.validate(plain)) {
            XCTAssertEqual($0 as? FoodDailyExportShapeError, .missingEstimate)
        }
    }

    func testEachOpenRouterFieldIsRequiredInItsExactForm() throws {
        let mutations: [(String, (inout [String: Any]) -> Void)] = [
            ("quality", { $0["estimate_quality"] = "medium" }),
            ("model", { $0["estimate_model"] = nil }),
            ("contract", { $0["estimate_contract"] = "other" }),
            ("hash", { $0["estimate_response_sha256"] = "abc" }),
            ("release", { $0["source_release_id"] = "openrouter-estimate:sha256:" + Self.responseHash }),
            ("v2 token", { $0["estimate_source_type"] = "national_composition" }),
            ("address", { $0["source_url"] = "https://example.com/" })
        ]
        for (name, change) in mutations {
            XCTAssertThrowsError(try FoodDailyExportShape.validate(try document(schema: 7, change)), name)
        }
    }

    func testTheExportRefusesAFieldOnAnotherProvenance() throws {
        let document = try ApprovedEstimateStorageContractTests.document { tree in
            try ApprovedEstimateStorageContractTests.editFirstProvenance(&tree) { $0["estimate_model"] = F.model }
        }
        XCTAssertThrowsError(try FoodDailyExportShape.validate(document))
    }
}
