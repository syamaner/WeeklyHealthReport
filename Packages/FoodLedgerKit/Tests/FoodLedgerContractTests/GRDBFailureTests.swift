import Foundation
import FoodLedgerApplication
import FoodLedgerDomain
import FoodLedgerGRDB
import GRDB
import XCTest

final class GRDBFailureTests: XCTestCase {
    func testProtectedDataUnavailabilityFailsClosed() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        XCTAssertThrowsError(try FoodLedgerGRDBStore.temporary(
            directory: directory,
            protectedData: ProtectedDataAvailability { false }
        )) { error in
            XCTAssertEqual(error as? FoodLedgerStoreError, .protectedDataUnavailable)
        }
    }

    func testProtectedDataBecomingUnavailableClosesEveryOperation() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let flag = AvailabilityFlag(true)
        let store = try FoodLedgerGRDBStore.temporary(
            directory: directory,
            protectedData: ProtectedDataAvailability { flag.value }
        )
        flag.value = false
        XCTAssertThrowsError(try store.counts()) { error in
            XCTAssertEqual(error as? FoodLedgerStoreError, .protectedDataUnavailable)
        }
        XCTAssertThrowsError(try store.persist(Data([1]), mediaKind: LedgerText("image/jpeg"))) {
            error in
            XCTAssertEqual(error as? FoodLedgerStoreError, .protectedDataUnavailable)
        }
    }

    func testCorruptDatabaseFailsClosedWithoutRecreation() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let database = directory.appendingPathComponent("food-ledger-v1.sqlite")
        let corruptBytes = Data("not sqlite".utf8)
        try corruptBytes.write(to: database)
        XCTAssertThrowsError(try FoodLedgerGRDBStore.temporary(directory: directory))
        XCTAssertEqual(try Data(contentsOf: database), corruptBytes)
    }

    func testSemanticallyCorruptPayloadFailsClosedOnReopen() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let database = directory.appendingPathComponent("food-ledger-v1.sqlite")
        do {
            let store = try FoodLedgerGRDBStore.temporary(directory: directory)
            let service = try LedgerFixtures.service(store)
            _ = try service.commit(
                LedgerFixtures.baseMutation(),
                type: .createProduct,
                operationID: LedgerFixtures.operationID(307)
            )
        }
        let queue = try DatabaseQueue(path: database.path)
        try queue.write { db in
            try db.execute(sql: "DROP TRIGGER product_immutable_update")
            try db.execute(sql: "UPDATE product SET payload = X'7B7D'")
        }
        XCTAssertThrowsError(try FoodLedgerGRDBStore.temporary(directory: directory)) { error in
            XCTAssertEqual(
                error as? FoodLedgerStoreError,
                .integrityFailure("product payload decoding")
            )
        }
    }

    func testUnknownNewerSchemaFailsClosed() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let database = directory.appendingPathComponent("food-ledger-v1.sqlite")
        let queue = try DatabaseQueue(path: database.path)
        try queue.write { db in
            try db.execute(sql: "PRAGMA application_id = \(FoodLedgerGRDBStore.applicationID)")
            try db.execute(sql: "PRAGMA user_version = 99")
        }
        XCTAssertThrowsError(try FoodLedgerGRDBStore.temporary(directory: directory)) { error in
            XCTAssertEqual(error as? FoodLedgerStoreError, .unknownSchema(99))
        }
    }

    func testFailedMigrationDoesNotReplaceOrEraseStore() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let database = directory.appendingPathComponent("food-ledger-v1.sqlite")
        let queue = try DatabaseQueue(path: database.path)
        try queue.write { db in
            try db.execute(sql: "CREATE TABLE ledger_metadata(wrong TEXT)")
        }
        XCTAssertThrowsError(try FoodLedgerGRDBStore.temporary(directory: directory)) { error in
            guard case .migrationFailed = error as? FoodLedgerStoreError else {
                return XCTFail("\(error)")
            }
        }
        let columns = try queue.read { db in
            try Row.fetchAll(db, sql: "PRAGMA table_info(ledger_metadata)")
                .map { $0["name"] as String }
        }
        XCTAssertEqual(columns, ["wrong"])
    }

    func testSQLitePolicyAndIdentityAreAsserted() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let database = directory.appendingPathComponent("food-ledger-v1.sqlite")
        let store = try FoodLedgerGRDBStore.temporary(directory: directory)
        try store.verifyIntegrity()
        let queue = try DatabaseQueue(path: database.path)
        try queue.read { db in
            XCTAssertEqual(try Int.fetchOne(db, sql: "PRAGMA foreign_keys"), 1)
            XCTAssertEqual(try String.fetchOne(db, sql: "PRAGMA journal_mode")?.lowercased(), "delete")
            XCTAssertEqual(try Int.fetchOne(db, sql: "PRAGMA synchronous"), 2)
            XCTAssertEqual(
                try Int.fetchOne(db, sql: "PRAGMA application_id"),
                FoodLedgerGRDBStore.applicationID
            )
            XCTAssertEqual(
                try Int.fetchOne(db, sql: "PRAGMA user_version"),
                FoodLedgerGRDBStore.schemaVersion
            )
        }
    }

    func testUnknownOperationTypeFailsClosedOnReopen() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let database = directory.appendingPathComponent("food-ledger-v1.sqlite")
        do {
            _ = try FoodLedgerGRDBStore.temporary(directory: directory)
        }
        let queue = try DatabaseQueue(path: database.path)
        try queue.write { db in
            try db.execute(
                sql: "INSERT INTO ledger_operation(operation_id, actor_id, actor_sequence, operation_type, created_at, affected_ids, payload, payload_hash, operation_hash) VALUES (?, ?, 1, 'future_v99', 0, ?, ?, ?, ?)",
                arguments: [
                    try LedgerFixtures.operationID(301).rawValue,
                    try LedgerFixtures.id(302, ActorTag.self).rawValue,
                    try JSONEncoder().encode([String]()),
                    Data(),
                    String(repeating: "a", count: 64),
                    String(repeating: "b", count: 64)
                ]
            )
        }
        XCTAssertThrowsError(try FoodLedgerGRDBStore.temporary(directory: directory)) { error in
            XCTAssertEqual(error as? FoodLedgerStoreError, .unsupportedOperation)
        }
    }

    func testRegisteredOperationReopensWithoutCurrentMutationDecoding() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let custom = try XCTUnwrap(LedgerOperationType(rawValue: "synthetic_import_v2"))
        let registry = LedgerOperationRegistry(
            supported: LedgerOperationType.builtInV1.union([custom])
        )
        do {
            _ = try FoodLedgerGRDBStore.temporary(
                directory: directory,
                operationRegistry: registry
            )
        }
        let operationID = try LedgerFixtures.operationID(306)
        let actorID: ActorID = try LedgerFixtures.id(902, ActorTag.self)
        let payload = Data("future payload that is not LedgerMutation JSON".utf8)
        let payloadHash = try LedgerFixtures.digester.sha256(payload)
        let unsigned = UnsignedLedgerOperation(
            schemaVersion: LedgerOperation.schemaVersion,
            operationID: operationID,
            actorID: actorID,
            actorSequence: 1,
            operationType: custom,
            createdAt: LedgerFixtures.date,
            affectedIDs: [],
            payloadHash: payloadHash,
            previousOperationHash: nil,
            idempotencyKey: nil
        )
        let operationHash = try LedgerFixtures.digester.sha256(
            LedgerFixtures.encoder.encode(unsigned)
        )
        let queue = try DatabaseQueue(
            path: directory.appendingPathComponent("food-ledger-v1.sqlite").path
        )
        try queue.write { db in
            try db.execute(
                sql: "INSERT INTO ledger_operation(operation_id, actor_id, actor_sequence, operation_type, created_at, affected_ids, payload, payload_hash, operation_hash) VALUES (?, ?, 1, ?, ?, ?, ?, ?, ?)",
                arguments: [
                    operationID.rawValue,
                    actorID.rawValue,
                    custom.rawValue,
                    LedgerFixtures.date.timeIntervalSince1970,
                    try JSONEncoder().encode([String]()),
                    payload,
                    payloadHash.value,
                    operationHash.value
                ]
            )
            try db.execute(
                sql: "INSERT INTO ledger_actor(actor_id, sequence, operation_hash) VALUES (?, 1, ?)",
                arguments: [actorID.rawValue, operationHash.value]
            )
        }
        let reopened = try FoodLedgerGRDBStore.temporary(
            directory: directory,
            operationRegistry: registry
        )
        XCTAssertEqual(try reopened.counts().operations, 1)
    }

    func testImmutableUpdateTriggerRejectsMutation() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let database = directory.appendingPathComponent("food-ledger-v1.sqlite")
        let store = try FoodLedgerGRDBStore.temporary(directory: directory)
        let service = try LedgerFixtures.service(store)
        _ = try service.commit(
            LedgerFixtures.baseMutation(),
            type: .createProduct,
            operationID: LedgerFixtures.operationID(303)
        )
        let queue = try DatabaseQueue(path: database.path)
        XCTAssertThrowsError(try queue.write { db in
            try db.execute(
                sql: "UPDATE product SET payload = ? WHERE product_id = ?",
                arguments: [Data("changed".utf8), try LedgerFixtures.id(2, ProductTag.self).rawValue]
            )
        }) { error in
            XCTAssertTrue(String(describing: error).contains("immutable product"))
        }
    }

    func testContentAddressedAttachmentIsRemovedAfterDatabaseRollback() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try FoodLedgerGRDBStore.temporary(directory: directory)
        let service = try LedgerFixtures.service(store)
        _ = try service.commit(
            LedgerFixtures.baseMutation(),
            type: .createProduct,
            operationID: LedgerFixtures.operationID(304)
        )
        let bytes = Data("synthetic retained media".utf8)
        let hash = try LedgerFixtures.digester.sha256(bytes)
        let expectedURL = directory
            .appendingPathComponent("Attachments/v1")
            .appendingPathComponent(String(hash.value.prefix(2)))
            .appendingPathComponent(hash.value)
        XCTAssertThrowsError(try service.recordEvidenceWithAttachment(
            bytes: bytes,
            mediaKind: LedgerText("image/jpeg"),
            attachmentStore: store,
            evidenceID: LedgerFixtures.id(1, EvidenceTag.self),
            kind: .synthetic,
            locale: LedgerText("en_GB"),
            captureMethod: LedgerText("synthetic"),
            captureMethodVersion: LedgerText("v1"),
            payload: .descriptor(LedgerText("duplicate evidence")),
            operationID: LedgerFixtures.operationID(305)
        ))
        XCTAssertFalse(FileManager.default.fileExists(atPath: expectedURL.path))
        XCTAssertEqual(try store.counts().operations, 1)
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("food-ledger-failure-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}

private final class AvailabilityFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValue: Bool

    init(_ value: Bool) {
        storedValue = value
    }

    var value: Bool {
        get {
            lock.lock()
            defer { lock.unlock() }
            return storedValue
        }
        set {
            lock.lock()
            storedValue = newValue
            lock.unlock()
        }
    }
}
