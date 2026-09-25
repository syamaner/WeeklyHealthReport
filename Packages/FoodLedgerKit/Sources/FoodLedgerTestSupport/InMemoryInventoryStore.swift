import Foundation
import FoodLedgerApplication

public final class InMemoryInventoryStore: InventoryStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var state = InventorySnapshot()
    private var operations: [String: Data] = [:]
    private let digester: any Digesting
    private let encoder: any CanonicalEncoding

    public init(digester: any Digesting = SHA256Digester(), encoder: any CanonicalEncoding = FoundationCanonicalJSONEncoder()) {
        self.digester = digester
        self.encoder = encoder
    }

    public func snapshot() throws -> InventorySnapshot { lock.withLock { state } }

    @discardableResult
    public func commit(_ command: InventoryCommand) throws -> InventorySnapshot {
        try lock.withLock {
            let bytes = try encoder.encode(command)
            if let prior = operations[command.operationID.rawValue] {
                guard prior == bytes else { throw InventoryStoreError.conflictingRetry }
                return state
            }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .millisecondsSince1970
            let canonical = try decoder.decode(InventoryCommand.self, from: bytes)
            let next = try state.applying(canonical, digester: digester)
            operations[command.operationID.rawValue] = bytes
            state = next
            return next
        }
    }
}
