import Foundation
@testable import FoodLedgerApplication
import FoodLedgerDomain
import FoodLedgerGRDB
import FoodLedgerTestSupport
import GRDB
import XCTest

/// Approved estimates from Your food database (estimates on catalogue v2): food contract 10, its
/// metadata-only migration, and the shape rule of daily export version 3. Synthetic data only.
final class ApprovedEstimateStorageContractTests: XCTestCase {
    static let fixtures = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("docs/fixtures")

    func testFoodContractTenAndSchemaTen() {
        XCTAssertEqual(CanonicalFoodProjection.foodContractVersion, 10)
        XCTAssertEqual(FoodLedgerGRDBStore.schemaVersion, 10)
        // An archive or store holding no estimate keeps the contract-6 floor and so its bytes.
        XCTAssertEqual(CanonicalFoodProjection.exportFloorContractVersion, 6)
        XCTAssertEqual(CanonicalFoodProjection.minimumContractVersion(for: LedgerMutation()), 1)
    }

    static func tableRows(_ queue: DatabaseQueue) throws -> [String: [String]] {
        try queue.read { db in
            var result: [String: [String]] = [:]
            for table in try String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%' AND name != 'grdb_migrations'") {
                result[table] = try Row.fetchAll(db, sql: "SELECT * FROM \"\(table)\"").map { row in
                    row.columnNames.map { "\($0)=\(row[$0] as DatabaseValue)" }.joined(separator: "|")
                }.sorted()
            }
            return result
        }
    }

    func testMigrationFromAPopulatedV9StoreChangesOnlyLedgerMetadataAndOlderBinariesDecline() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("approved-estimate-v10-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let database = directory.appendingPathComponent("food-ledger-v1.sqlite")
        do {
            let store = try FoodLedgerGRDBStore.temporary(directory: directory)
            _ = try LedgerFixtures.service(store).commit(LedgerFixtures.baseMutation(), type: .createProduct,
                                                         operationID: LedgerFixtures.operationID(10_511))
        }
        let queue = try DatabaseQueue(path: database.path)
        try queue.write { db in
            try db.execute(sql: "DELETE FROM grdb_migrations WHERE identifier = 'v10_approved_estimate'")
            try db.execute(sql: "UPDATE ledger_metadata SET value = 'food-ledger-v9' WHERE key = 'schema_identity'")
            try db.execute(sql: "PRAGMA user_version = 9")
        }
        let before = try Self.tableRows(queue)
        let schemaBefore = try queue.read { try String.fetchAll($0, sql: "SELECT sql FROM sqlite_master WHERE sql IS NOT NULL ORDER BY name") }
        try queue.close()
        let migrated = try FoodLedgerGRDBStore.temporary(directory: directory)
        try migrated.verifyIntegrity()
        let check = try DatabaseQueue(path: database.path)
        let after = try Self.tableRows(check)
        XCTAssertEqual(Set(before.keys.filter { before[$0] != after[$0] }), ["ledger_metadata"], "Only ledger_metadata may change")
        XCTAssertEqual(try check.read { try String.fetchAll($0, sql: "SELECT sql FROM sqlite_master WHERE sql IS NOT NULL ORDER BY name") },
                       schemaBefore, "No table, index or trigger definition changes")
        try check.read { db in
            XCTAssertEqual(try Int.fetchOne(db, sql: "PRAGMA user_version"), 10)
            XCTAssertEqual(try String.fetchOne(db, sql: "SELECT value FROM ledger_metadata WHERE key = 'schema_identity'"), "food-ledger-v10")
            XCTAssertEqual(try String.fetchAll(db, sql: "SELECT identifier FROM grdb_migrations ORDER BY rowid").last, "v10_approved_estimate")
        }
        // A contract 9 binary applies the pre-migration rule (user_version above its schema 9) and
        // declines this store: `unknownSchema(10)` there, shown here with the next number.
        XCTAssertGreaterThan(try check.read { try Int.fetchOne($0, sql: "PRAGMA user_version") ?? 0 }, 9)
        // The open check refuses v9 metadata on a v10 schema.
        try check.write { try $0.execute(sql: "UPDATE ledger_metadata SET value = 'food-ledger-v9' WHERE key = 'schema_identity'") }
        try check.close()
        XCTAssertThrowsError(try FoodLedgerGRDBStore.temporary(directory: directory)) {
            XCTAssertEqual($0 as? FoodLedgerStoreError, .integrityFailure("database open policy"))
        }
    }

    // MARK: Daily export version 3, the shape rule

    static func document(_ edit: (inout [String: Any]) throws -> Void) throws -> FoodDailyExportDocument {
        let data = try Data(contentsOf: fixtures.appendingPathComponent("food-daily-v2/food-daily-mixed-day.json"))
        var tree = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        try edit(&tree)
        return try FoodDailyExportSerializer.decode(try JSONSerialization.data(withJSONObject: tree))
    }

    /// Changes the first provenance object of the first value that has one. `asEstimate` also
    /// makes that value what the builder writes for an approved estimate (state and origin), so a
    /// test changes only the field it means to.
    static func editFirstProvenance(_ tree: inout [String: Any], asEstimate: Bool = false,
                                    _ edit: (inout [String: Any]) -> Void) throws {
        var entries = try XCTUnwrap(tree["entries"] as? [[String: Any]])
        for e in entries.indices {
            var nutrients = try XCTUnwrap(entries[e]["nutrients"] as? [[String: Any]])
            for n in nutrients.indices {
                guard var provenance = nutrients[n]["provenance"] as? [[String: Any]], !provenance.isEmpty else { continue }
                edit(&provenance[0])
                nutrients[n]["provenance"] = Array(provenance.prefix(asEstimate ? 1 : provenance.count))
                if asEstimate {
                    nutrients[n]["state"] = "estimated"
                    nutrients[n]["origin"] = "approved_estimate"
                }
                entries[e]["nutrients"] = nutrients
                tree["entries"] = entries
                return
            }
        }
        XCTFail("the fixture has no provenance")
    }

    static let tokens: [String: String] = ["source_kind": "approved_estimate", "estimate_source_type": "national_composition",
                                        "estimate_method": "carried_from_same_food", "estimate_state_basis": "source_states_it",
                                        "estimate_quality": "high"]

    func rejected(_ expected: FoodDailyExportShapeError, _ edit: (inout [String: Any]) throws -> Void,
                  file: StaticString = #filePath, line: UInt = #line) throws {
        let document = try Self.document(edit)
        XCTAssertThrowsError(try FoodDailyExportShape.validate(document), file: file, line: line) {
            XCTAssertEqual($0 as? FoodDailyExportShapeError, expected, file: file, line: line)
        }
    }

    func testSchemaThreeNeedsAnApprovedEstimateWithItsFourTokens() throws {
        let accepted = try Self.document { tree in
            tree["food_daily_schema_version"] = 3
            try Self.editFirstProvenance(&tree, asEstimate: true) { $0.merge(Self.tokens) { _, new in new } }
        }
        XCTAssertNoThrow(try FoodDailyExportShape.validate(accepted))
        XCTAssertEqual(FoodDailyExportDocument.estimatesSchemaVersion, 3)
        XCTAssertEqual(FoodDailyExportDocument.schemaVersion, 2, "a document without an estimate is still written as schema 2")
        // A schema 3 file with no approved estimate value is rejected.
        try rejected(.missingEstimate) { $0["food_daily_schema_version"] = 3 }
        // A missing or unknown tier, or any other missing token, is rejected.
        for key in ["estimate_quality", "estimate_source_type", "estimate_method", "estimate_state_basis"] {
            try rejected(.invalidEstimateFields) { tree in
                tree["food_daily_schema_version"] = 3
                try Self.editFirstProvenance(&tree, asEstimate: true) { $0.merge(Self.tokens) { _, new in new }; $0[key] = nil }
            }
            try rejected(.invalidEstimateFields) { tree in
                tree["food_daily_schema_version"] = 3
                try Self.editFirstProvenance(&tree, asEstimate: true) { $0.merge(Self.tokens) { _, new in new }; $0[key] = "excellent" }
            }
        }
    }

    func testOlderSchemasNeverCarryAnEstimateField() throws {
        // A schema 2 file carrying an approved estimate or any estimate field is rejected.
        try rejected(.unexpectedEstimate) { tree in
            try Self.editFirstProvenance(&tree, asEstimate: true) { $0.merge(Self.tokens) { _, new in new } }
        }
        try rejected(.unexpectedEstimate) { tree in
            try Self.editFirstProvenance(&tree) { $0["estimate_quality"] = "high" }
        }
        // A measured value relabelled with approved-estimate provenance alone is refused (Codex).
        try rejected(.invalidEstimateFields) { tree in
            tree["food_daily_schema_version"] = 3
            try Self.editFirstProvenance(&tree) { $0.merge(Self.tokens) { _, new in new } }
        }
        // A well-formed schema 3 estimate value is accepted.
        let stray = try Self.document { tree in
            tree["food_daily_schema_version"] = 3
            try Self.editFirstProvenance(&tree, asEstimate: true) { $0.merge(Self.tokens) { _, new in new } }
        }
        XCTAssertNoThrow(try FoodDailyExportShape.validate(stray))
    }

    /// Codex review of PR 514 at 8b0411a: the shape rule checks each value with its provenance.
    func testSchemaThreeChecksEachEstimateValueWithItsProvenance() throws {
        let golden = try Data(contentsOf: Self.fixtures.appendingPathComponent("food-daily-v3/food-daily-estimates-day.json"))
        let text = String(decoding: golden, as: UTF8.self)
        XCTAssertNoThrow(try FoodDailyExportShape.validate(try FoodDailyExportSerializer.decode(golden)))
        func rejected(_ edited: String, _ expected: FoodDailyExportShapeError, _ message: String, line: UInt = #line) {
            XCTAssertNotEqual(edited, text, message, line: line)
            XCTAssertThrowsError(try FoodDailyExportShape.validate(try FoodDailyExportSerializer.decode(Data(edited.utf8))), message, line: line) {
                XCTAssertEqual($0 as? FoodDailyExportShapeError, expected, message, line: line)
            }
        }
        // The bar's page fibre estimate, as the golden writes it.
        let page = "\"origin\":\"approved_estimate\""
        XCTAssertTrue(text.contains(page))
        rejected(text.replacingOccurrences(of: "\"state\":\"estimated\",\"unit\":\"g\"", with: "\"state\":\"measured\",\"unit\":\"g\""),
                 .invalidEstimateFields, "an approved estimate shown as measured")
        rejected(text.replacingOccurrences(of: "\"source_url\":\"https://www.example.com/products/synthetic\",", with: ""),
                 .invalidEstimateFields, "a page estimate without its page address")
        rejected(text.replacingOccurrences(of: "https://www.example.com/products/synthetic", with: "https://www.example.com/products/synthetic?x=1"),
                 .invalidEstimateFields, "a page address with a query string")
        rejected(text.replacingOccurrences(of: page, with: "\"origin\":\"product_database\""),
                 .invalidEstimateFields, "an approved estimate under another origin")
        // Schemas 1 and 2 never carry the origin, even without any estimate field.
        let v2 = try Data(contentsOf: Self.fixtures.appendingPathComponent("food-daily-v2/food-daily-mixed-day.json"))
        let v2Text = String(decoding: v2, as: UTF8.self)
        let firstOrigin = try XCTUnwrap(v2Text.range(of: #""origin":"[a-z_]+""#, options: .regularExpression))
        var relabelled = v2Text
        relabelled.replaceSubrange(firstOrigin, with: "\"origin\":\"approved_estimate\"")
        XCTAssertThrowsError(try FoodDailyExportShape.validate(try FoodDailyExportSerializer.decode(Data(relabelled.utf8)))) {
            XCTAssertEqual($0 as? FoodDailyExportShapeError, .unexpectedEstimate)
        }
    }

    func testTheOriginTableNamesTheNewKind() throws {
        XCTAssertEqual(try FoodDailyExportOrigin.origin(sourceKind: "approved_estimate"), "approved_estimate")
    }
}
