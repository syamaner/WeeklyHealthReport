import Foundation
import FoodLedgerApplication
import FoodLedgerDomain
import GRDB

/// Independent local inventory event store; not part of the food archive v1 schema.
public final class LocalInventoryGRDBStore: InventoryStoring, @unchecked Sendable {
    public static let schemaVersion = 1
    private static let applicationID = 0x5748_5249 // WHRI
    private let queue: DatabaseQueue
    private let digester: any Digesting
    private let encoder: any CanonicalEncoding
    private let protectedData: ProtectedDataAvailability

    public init(
        databaseURL: URL,
        protectedData: ProtectedDataAvailability = .available,
        digester: any Digesting = SHA256Digester(),
        encoder: any CanonicalEncoding = FoundationCanonicalJSONEncoder()
    ) throws {
        self.protectedData = protectedData
        self.digester = digester
        self.encoder = encoder
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
                try db.execute(sql: "CREATE TABLE inventory_event (sequence INTEGER PRIMARY KEY, operation_id TEXT NOT NULL UNIQUE, payload BLOB NOT NULL)")
                try db.execute(sql: "PRAGMA application_id = \(Self.applicationID)")
                try db.execute(sql: "PRAGMA user_version = \(Self.schemaVersion)")
            } else {
                guard appID == Self.applicationID else { throw InventoryStoreError.corruptStore }
                guard version == Self.schemaVersion else { throw InventoryStoreError.unsupportedSchema }
            }
        }
        #if os(iOS)
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: databaseURL.path)
        #endif
        _ = try snapshot()
    }

    public func snapshot() throws -> InventorySnapshot {
        try protectedData.requireAvailable()
        return try queue.read { try replay($0) }
    }

    @discardableResult
    public func commit(_ command: InventoryCommand) throws -> InventorySnapshot {
        try protectedData.requireAvailable()
        let bytes = try encoder.encode(command)
        return try queue.write { db in
            if let previous = try Data.fetchOne(db, sql: "SELECT payload FROM inventory_event WHERE operation_id = ?", arguments: [command.operationID.rawValue]) {
                guard previous == bytes else { throw InventoryStoreError.conflictingRetry }
                return try replay(db)
            }
            let current = try replay(db)
            let next = try current.applying(Self.decode(bytes), digester: digester)
            try db.execute(sql: "INSERT INTO inventory_event (sequence, operation_id, payload) VALUES (?, ?, ?)", arguments: [next.revision, command.operationID.rawValue, bytes])
            return next
        }
    }

    private func replay(_ db: Database) throws -> InventorySnapshot {
        var state = InventorySnapshot()
        for row in try Row.fetchAll(db, sql: "SELECT sequence, operation_id, payload FROM inventory_event ORDER BY sequence") {
            let command = try Self.decode(row["payload"])
            let sequence: Int = row["sequence"]
            let operationID: String = row["operation_id"]
            guard sequence == state.revision + 1, operationID == command.operationID.rawValue else {
                throw InventoryStoreError.corruptStore
            }
            state = try state.applying(command, digester: digester)
        }
        return state
    }

    private static func decode(_ bytes: Data) throws -> InventoryCommand {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return try decoder.decode(InventoryCommand.self, from: bytes)
    }
}
