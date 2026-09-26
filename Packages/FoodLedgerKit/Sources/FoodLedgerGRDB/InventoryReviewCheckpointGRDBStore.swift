import Foundation
import FoodLedgerApplication
import GRDB

public final class InventoryReviewCheckpointGRDBStore: InventoryReviewCheckpointStoring, @unchecked Sendable {
    private let queue: DatabaseQueue
    private let protectedData: ProtectedDataAvailability
    private static let applicationID = 0x5748_5245 // WHRE

    public init(databaseURL: URL, protectedData: ProtectedDataAvailability = .available) throws {
        self.protectedData = protectedData
        try protectedData.requireAvailable()
        let directory = databaseURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        #if os(iOS)
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: directory.path)
        #endif
        var configuration = Configuration()
        configuration.prepareDatabase { db in
            try db.execute(sql: "PRAGMA journal_mode = DELETE")
            try db.execute(sql: "PRAGMA synchronous = FULL")
        }
        queue = try DatabaseQueue(path: databaseURL.path, configuration: configuration)
        try queue.write { db in
            let appID = try Int.fetchOne(db, sql: "PRAGMA application_id") ?? 0
            let version = try Int.fetchOne(db, sql: "PRAGMA user_version") ?? 0
            if appID == 0 && version == 0 {
                let count = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%'") ?? 0
                guard count == 0 else { throw InventoryStoreError.corruptStore }
                try db.execute(sql: "CREATE TABLE inventory_review_checkpoint (id INTEGER PRIMARY KEY CHECK (id = 1), payload BLOB NOT NULL)")
                try db.execute(sql: "PRAGMA application_id = \(Self.applicationID)")
                try db.execute(sql: "PRAGMA user_version = 1")
            } else {
                guard appID == Self.applicationID, version == 1 else { throw InventoryStoreError.unsupportedSchema }
            }
        }
        #if os(iOS)
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: databaseURL.path)
        #endif
    }

    public func load() throws -> InventoryReviewCheckpoint? {
        try protectedData.requireAvailable()
        return try queue.read { db in
            guard let bytes = try Data.fetchOne(db, sql: "SELECT payload FROM inventory_review_checkpoint WHERE id = 1") else { return nil }
            let checkpoint = try JSONDecoder().decode(InventoryReviewCheckpoint.self, from: bytes)
            try checkpoint.validate()
            return checkpoint
        }
    }

    public func save(_ checkpoint: InventoryReviewCheckpoint) throws {
        try protectedData.requireAvailable()
        try checkpoint.validate()
        let bytes = try JSONEncoder().encode(checkpoint)
        try queue.write { db in
            try db.execute(sql: "INSERT INTO inventory_review_checkpoint (id, payload) VALUES (1, ?) ON CONFLICT(id) DO UPDATE SET payload = excluded.payload", arguments: [bytes])
        }
    }
}
