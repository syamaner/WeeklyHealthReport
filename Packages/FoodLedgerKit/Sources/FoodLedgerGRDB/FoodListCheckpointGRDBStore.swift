import Foundation
import FoodLedgerApplication
import GRDB

public final class FoodListCheckpointGRDBStore: FoodListCheckpointStoring, @unchecked Sendable {
    private let queue: DatabaseQueue
    private let protectedData: ProtectedDataAvailability

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
                guard count == 0 else { throw FoodLedgerStoreError.integrityFailure("foreign draft database") }
                try db.execute(sql: "CREATE TABLE food_list_checkpoint (id INTEGER PRIMARY KEY CHECK (id = 1), payload BLOB NOT NULL)")
                try db.execute(sql: "PRAGMA application_id = 1464357444") // WHRD
                try db.execute(sql: "PRAGMA user_version = 1")
            } else {
                guard appID == 1464357444, version == 1 else { throw FoodLedgerStoreError.integrityFailure("unsupported draft database") }
            }
        }
        #if os(iOS)
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: databaseURL.path)
        #endif
    }

    public func load() throws -> FoodListCheckpoint? {
        try protectedData.requireAvailable()
        return try queue.read { db in
            guard let bytes = try Data.fetchOne(db, sql: "SELECT payload FROM food_list_checkpoint WHERE id = 1") else { return nil }
            let result = try JSONDecoder().decode(FoodListCheckpoint.self, from: bytes)
            try result.validate()
            return result
        }
    }

    public func save(_ checkpoint: FoodListCheckpoint) throws {
        try protectedData.requireAvailable()
        try checkpoint.validate()
        let bytes = try JSONEncoder().encode(checkpoint)
        try queue.write { db in
            try db.execute(sql: "INSERT INTO food_list_checkpoint (id, payload) VALUES (1, ?) ON CONFLICT(id) DO UPDATE SET payload = excluded.payload", arguments: [bytes])
        }
    }
}
