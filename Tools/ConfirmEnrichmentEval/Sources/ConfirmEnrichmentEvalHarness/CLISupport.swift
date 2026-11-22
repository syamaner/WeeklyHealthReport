import FoodConfirmEnrichment
import FoodLedgerApplication
import Foundation

/// Small CLI helpers kept in the harness so main.swift names no transport type.
public protocol ConfirmEnrichmentHTTPTransportingBox {
    var value: any ConfirmEnrichmentHTTPTransporting { get }
}

public struct Box: ConfirmEnrichmentHTTPTransportingBox {
    public let value: any ConfirmEnrichmentHTTPTransporting
    public init(_ value: any ConfirmEnrichmentHTTPTransporting) { self.value = value }
}

/// A placeholder key for `send --fake`: well formed, never a real key, never sent anywhere.
public struct FixedEvalKey: FoodWebKeyStoring {
    public init() {}
    public func load() throws -> String? { "sk-or-v1-synthetic-fake-transport-only" }
    public func save(_ key: String) throws {}
    public func delete() throws {}
}

/// The lines a run returns, handed from the run's task to the main thread.
public final class OutputLines: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [String] = []
    public init() {}
    public func set(_ lines: [String]) { lock.withLock { stored = lines } }
    public var lines: [String] { lock.withLock { stored } }
}

/// Both live parts and both sets use one spend ledger. Hold its process lock across a send.
public enum EvalLiveRunLock {
    public static func acquire(in folder: URL) -> FileHandle? {
        let path = folder.appendingPathComponent("confirm-enrichment-eval.lock").path
        let descriptor = open(path, O_WRONLY | O_CREAT | O_NOFOLLOW | O_CLOEXEC, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { return nil }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            close(descriptor)
            return nil
        }
        return FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
    }
}
