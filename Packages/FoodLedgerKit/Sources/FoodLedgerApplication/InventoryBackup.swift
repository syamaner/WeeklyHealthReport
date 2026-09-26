import Foundation
import FoodLedgerDomain

/// Versioned backup integrity and compatible-history policy, independent of storage.
public struct InventoryBackupCodec: Sendable {
    public static let formatVersion = 2
    private let digester: any Digesting
    private let encoder: any CanonicalEncoding
    private struct Envelope: Codable {
        let formatVersion: Int
        let commands: [InventoryCommand]
        let sha256: String
    }

    public init(digester: any Digesting = SHA256Digester(), encoder: any CanonicalEncoding = FoundationCanonicalJSONEncoder()) {
        self.digester = digester; self.encoder = encoder
    }

    public func encode(_ commands: [InventoryCommand]) throws -> Data {
        try validate(commands)
        let hash = try digester.sha256(encoder.encode(commands)).value
        return try encoder.encode(Envelope(formatVersion: Self.formatVersion, commands: commands, sha256: hash))
    }

    public func decode(_ bytes: Data) throws -> [InventoryCommand] {
        guard bytes.count <= 100_000_000 else { throw InventoryStoreError.corruptStore }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        let backup = try decoder.decode(Envelope.self, from: bytes)
        guard backup.formatVersion == 1 || backup.formatVersion == Self.formatVersion else { throw InventoryStoreError.unsupportedSchema }
        guard try digester.sha256(encoder.encode(backup.commands)).value == backup.sha256 else { throw InventoryStoreError.corruptStore }
        try validate(backup.commands)
        return backup.commands
    }

    public func commandsToAppend(existing: [InventoryCommand], incoming: [InventoryCommand]) throws -> [InventoryCommand] {
        for index in 0..<min(existing.count, incoming.count) {
            guard existing[index] == incoming[index] else { throw InventoryStoreError.conflictingRetry }
        }
        return Array(incoming.dropFirst(existing.count))
    }

    private func validate(_ commands: [InventoryCommand]) throws {
        var state = InventorySnapshot()
        var operations = Set<OperationID>()
        for command in commands {
            guard operations.insert(command.operationID).inserted else { throw InventoryStoreError.conflictingRetry }
            state = try state.applying(command, digester: digester)
        }
    }
}
