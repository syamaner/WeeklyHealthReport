import Foundation
@testable import FoodLedgerApplication
import FoodLedgerDomain
import FoodLedgerGRDB
import FoodLedgerTestSupport
import GRDB
import XCTest

/// Label photo estimates (docs/personal-food-catalogue-off-estimates-v1-phase.md section 6, tests 9,
/// 11 and 12): food contract 11 and its metadata-only migration, the contract floor for a manifest
/// citing `product_dataset_photo`, and the shape rule of daily export version 5. Synthetic data only.
final class PhotoEstimateStorageContractTests: XCTestCase {
    static let photoURL = "https://images.openfoodfacts.org/images/products/500/000/000/0017/nutrition_en.3.full.jpg"
    static let digest = String(repeating: "e", count: 64)

    func testVersionsAllocatedByThePhaseGate() {
        XCTAssertEqual(CanonicalFoodProjection.foodContractVersion, 13)
        XCTAssertEqual(FoodLedgerGRDBStore.schemaVersion, 13)
        XCTAssertEqual(FoodDailyExportDocument.photoEstimatesSchemaVersion, 5)
        XCTAssertEqual(FoodDailyExportDocument.estimatesSchemaVersion, 3)
        XCTAssertEqual(FoodDailyExportDocument.schemaVersion, 2)
    }

    // MARK: Contract floor and archive decoding

    static func manifestEvidence(sourceType: String, contract: Int = 11) throws -> LedgerMutation {
        let ids = RandomLedgerIDGenerator()
        let payload = #"{"estimates":[{"evidence":{"source_type":"\#(sourceType)"}}]}"#
        let evidence = try CaptureEvidence(
            evidenceID: ids.makeID(EvidenceTag.self), kind: .labelText, capturedAt: LedgerFixtures.date,
            locale: LedgerText("en_GB"), captureMethod: LedgerText("synthetic"),
            captureMethodVersion: LedgerText(ApprovedEstimateProvenance.captureMethodVersion),
            originalPayload: .text(LedgerText(payload)), byteHash: try LedgerFixtures.digester.sha256(Data(payload.utf8)))
        var records = LedgerMutation()
        records.evidence = [evidence]
        return records
    }

    func testAPhotoManifestNeedsContractElevenAndANationalOneStaysAtTen() throws {
        XCTAssertEqual(CanonicalFoodProjection.minimumContractVersion(for: try Self.manifestEvidence(sourceType: "product_dataset_photo")), 11)
        XCTAssertEqual(CanonicalFoodProjection.minimumContractVersion(for: try Self.manifestEvidence(sourceType: "national_composition")), 10)
        // Free text never decides it: only the evidence source type does.
        var records = LedgerMutation()
        XCTAssertEqual(CanonicalFoodProjection.minimumContractVersion(for: records), 1)
        records = try Self.manifestEvidence(sourceType: "aggregator")
        XCTAssertEqual(CanonicalFoodProjection.minimumContractVersion(for: records), 10)
    }

    func testAnArchiveBelowElevenHoldingAPhotoManifestIsRejectedAndElevenRoundTrips() throws {
        let photo = try Self.manifestEvidence(sourceType: "product_dataset_photo")
        let projection = try CanonicalFoodProjection(records: photo)
        XCTAssertEqual(projection.foodContractVersion, 11)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let encoded = try encoder.encode(projection)
        let decoded = try JSONDecoder().decode(CanonicalFoodProjection.self, from: encoded)
        XCTAssertEqual(decoded, projection)
        XCTAssertEqual(try encoder.encode(decoded), encoded)
        // The same records labelled contract 10 are not an archive.
        var tree = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        tree["foodContractVersion"] = 10
        XCTAssertThrowsError(try JSONDecoder().decode(CanonicalFoodProjection.self,
                                                      from: JSONSerialization.data(withJSONObject: tree)))
        // Encoding refuses a contract below the floor too.
        XCTAssertThrowsError(try CanonicalFoodProjection(records: photo, foodContractVersion: 10))
        // A national manifest at contract 10 still decodes.
        let national = try CanonicalFoodProjection(records: try Self.manifestEvidence(sourceType: "national_composition"))
        XCTAssertEqual(national.foodContractVersion, 10)
        XCTAssertNoThrow(try JSONDecoder().decode(CanonicalFoodProjection.self, from: JSONEncoder().encode(national)))
    }

    func testMigrationFromAPopulatedV10StoreChangesOnlyLedgerMetadata() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("photo-estimate-v11-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let database = directory.appendingPathComponent("food-ledger-v1.sqlite")
        do {
            let store = try FoodLedgerGRDBStore.temporary(directory: directory)
            _ = try LedgerFixtures.service(store).commit(LedgerFixtures.baseMutation(), type: .createProduct,
                                                         operationID: LedgerFixtures.operationID(10_518))
        }
        let queue = try DatabaseQueue(path: database.path)
        try queue.write { db in
            try db.execute(sql: "DELETE FROM grdb_migrations WHERE identifier = 'v11_label_photo_estimate'")
            try db.execute(sql: "DELETE FROM grdb_migrations WHERE identifier = 'v13_confirm_enrichment'")
            try db.execute(sql: "UPDATE ledger_metadata SET value = 'food-ledger-v10' WHERE key = 'schema_identity'")
            try db.execute(sql: "PRAGMA user_version = 10")
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
            XCTAssertEqual(try String.fetchAll(db, sql: "SELECT identifier FROM grdb_migrations ORDER BY rowid").last,
                           "v13_confirm_enrichment")
        }
    }

    // MARK: Daily export version 5

    static var photoTokens: [String: Any] { [
        "source_kind": "approved_estimate", "estimate_source_type": "product_dataset_photo",
        "estimate_method": "carried_from_similar_food", "estimate_state_basis": "source_states_it",
        "estimate_quality": "medium", "source_url": photoURL, "content_hash": digest] }

    func photoDocument(schema: Int, _ change: (inout [String: Any]) -> Void = { _ in }) throws -> FoodDailyExportDocument {
        try ApprovedEstimateStorageContractTests.document { tree in
            tree["food_daily_schema_version"] = schema
            try ApprovedEstimateStorageContractTests.editFirstProvenance(&tree, asEstimate: true) {
                $0.merge(Self.photoTokens) { _, new in new }
                change(&$0)
            }
        }
    }

    func testSchemaFiveExactlyWithAPhotoEstimate() throws {
        XCTAssertNoThrow(try FoodDailyExportShape.validate(try photoDocument(schema: 5)))
        // Schema 3 never carries the token, and schema 5 never lacks it.
        XCTAssertThrowsError(try FoodDailyExportShape.validate(try photoDocument(schema: 3)))
        let national = try ApprovedEstimateStorageContractTests.document { tree in
            tree["food_daily_schema_version"] = 5
            try ApprovedEstimateStorageContractTests.editFirstProvenance(&tree, asEstimate: true) {
                $0.merge(ApprovedEstimateStorageContractTests.tokens) { _, new in new }
            }
        }
        XCTAssertThrowsError(try FoodDailyExportShape.validate(national))
        // Schema 2 never carries an estimate at all.
        XCTAssertThrowsError(try FoodDailyExportShape.validate(try photoDocument(schema: 2)))
    }

    func testAPhotoValueNeedsThePhotoAddressAndADigest() throws {
        for change: (inout [String: Any]) -> Void in [
            { $0["source_url"] = "https://example.com/label.jpg" },
            { $0["source_url"] = Self.photoURL + "?x=1" },
            { $0["source_url"] = nil },
            { $0["content_hash"] = nil },
            { $0["content_hash"] = "abc" },
            { $0["estimate_quality"] = "excellent" }
        ] {
            XCTAssertThrowsError(try FoodDailyExportShape.validate(try photoDocument(schema: 5, change)))
        }
    }

    func testThePresentationNamesTheSource() {
        XCTAssertEqual(PersonalFoodDatabaseEstimateSourceType.allCases.count, 4)
        XCTAssertEqual(PersonalFoodDatabaseEstimateSourceType.estimatesV2List, [.nationalComposition, .manufacturerPage, .aggregator])
    }
}

/// Gate test 11 through the writer: logs saved with label photo estimates, exported by
/// `FoodDailyExportBuilder` from the shared v3 golden (label photo on the serving bar's sugar, same
/// barcode; the bar also carries a page fibre estimate). Synthetic data only.
final class PhotoEstimateExportContractTests: XCTestCase {
    typealias Export = ApprovedEstimateExportContractTests
    static let v3 = "personal-food-database-estimates-v3"

    func testAKeptPhotoEstimateWritesSchemaFiveWithItsAddressAndDigest() throws {
        let (document, _) = try Export.export([(ApprovedEstimateConfirmContractTests.bar, [])], fixture: Self.v3)
        XCTAssertEqual(document.foodDailySchemaVersion, 5)
        XCTAssertNoThrow(try FoodDailyExportShape.validate(document))
        let sugar = try Export.value(document, entry: 0, .sugar)
        XCTAssertEqual(sugar.state, "estimated")
        let photo = try XCTUnwrap(sugar.provenance?.first)
        XCTAssertEqual(photo.estimateSourceType, "product_dataset_photo")
        XCTAssertEqual(photo.estimateMethod, "direct")
        XCTAssertEqual(photo.estimateQuality, "medium")
        XCTAssertEqual(photo.sourceURL, "https://images.openfoodfacts.org/images/products/000/000/000/0024/nutrition_en.1.400.jpg")
        XCTAssertEqual(photo.contentHash, String(repeating: "e", count: 64), "the manifest's source_digest, never its own hash")
        // The page estimate beside it keeps its own type in the same schema 5 document.
        XCTAssertEqual(try Export.value(document, entry: 0, .fiber).provenance?.first?.estimateSourceType, "manufacturer_page")
    }

    func testALeftOutPhotoEstimateLeavesTheDayAtSchemaThree() throws {
        let (document, _) = try Export.export([(ApprovedEstimateConfirmContractTests.bar, [.sugar])], fixture: Self.v3)
        XCTAssertEqual(document.foodDailySchemaVersion, 3, "the page estimate remains, the photo was left out")
        XCTAssertEqual(try Export.value(document, entry: 0, .sugar).state, "unknown")
        XCTAssertNoThrow(try FoodDailyExportShape.validate(document))
        let none = try Export.export([(ApprovedEstimateConfirmContractTests.bar, [.sugar, .fiber])], fixture: Self.v3)
        XCTAssertEqual(none.document.foodDailySchemaVersion, 2, "no estimate kept: schema 2")
    }

    func testAPhotoBesideACompositionEstimateIsSchemaFive() throws {
        let (document, _) = try Export.export([(ApprovedEstimateConfirmContractTests.bar, []),
                                               (ApprovedEstimateConfirmContractTests.fish, [])], fixture: Self.v3)
        XCTAssertEqual(document.foodDailySchemaVersion, 5)
        XCTAssertNoThrow(try FoodDailyExportShape.validate(document))
    }

    func testTheSameDayFromTheV2CatalogueStaysAtSchemaThree() throws {
        let (document, _) = try Export.export([(ApprovedEstimateConfirmContractTests.bar, [])])
        XCTAssertEqual(document.foodDailySchemaVersion, 3)
    }
}
