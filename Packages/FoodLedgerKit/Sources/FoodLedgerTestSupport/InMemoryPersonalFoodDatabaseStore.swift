import FoodLedgerApplication
import Foundation

/// The in-memory `PersonalFoodDatabaseStoring` for tests. It passes the same store contract suite
/// as the file store; `locked` and `damaged` simulate the protected and disabled states.
public final class InMemoryPersonalFoodDatabaseStore: PersonalFoodDatabaseStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var active: PersonalFoodDatabaseInstalledRelease?
    private var isLocked = false
    private var isDamaged = false
    private var failsWrites = false

    public init(active: PersonalFoodDatabaseInstalledRelease? = nil) { self.active = active }

    public var locked: Bool {
        get { lock.withLock { isLocked } }
        set { lock.withLock { isLocked = newValue } }
    }

    public var damaged: Bool {
        get { lock.withLock { isDamaged } }
        set { lock.withLock { isDamaged = newValue } }
    }

    public var failWrites: Bool {
        get { lock.withLock { failsWrites } }
        set { lock.withLock { failsWrites = newValue } }
    }

    public func activeRelease() throws -> PersonalFoodDatabaseInstalledRelease? {
        try lock.withLock {
            if isLocked { throw PersonalFoodDatabaseStoreError.locked }
            if isDamaged, active != nil { throw PersonalFoodDatabaseStoreError.damaged }
            return active
        }
    }

    public func install(bytes: Data, manifest: PersonalFoodDatabaseManifest) throws {
        try lock.withLock {
            if isLocked { throw PersonalFoodDatabaseStoreError.locked }
            if failsWrites { throw PersonalFoodDatabaseStoreError.writeFailed }
            active = PersonalFoodDatabaseInstalledRelease(bytes: bytes, manifest: manifest)
            isDamaged = false
        }
    }

    @discardableResult
    public func remove() throws -> Bool {
        try lock.withLock {
            if isLocked { throw PersonalFoodDatabaseStoreError.locked }
            if failsWrites { throw PersonalFoodDatabaseStoreError.writeFailed }
            defer { active = nil; isDamaged = false }
            return active != nil
        }
    }
}
