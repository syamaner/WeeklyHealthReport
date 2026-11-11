import FoodLedgerDomain
import Foundation

// Your food database: install, replace and remove (import v1 sections 3, 4 and 7; phase 1 plan
// section 3). Nothing here searches the file or writes the ledger.

/// What the store keeps beside the file. The import time lives only here (import v1 section 4),
/// never in a `SourceRelease`. A plain value: the file store owns its on-disk JSON shape.
public struct PersonalFoodDatabaseManifest: Equatable, Sendable {
    public static let version = 1
    public let schema: String
    public let releaseID: String
    public let fileSHA256: SHA256Digest
    public let generated: PersonalFoodDatabaseDate
    /// Whole seconds, so the stored form round-trips exactly.
    public let importedAt: Date
    public let entryCount: Int

    public init(schema: String, releaseID: String, fileSHA256: SHA256Digest, generated: PersonalFoodDatabaseDate,
                importedAt: Date, entryCount: Int) {
        self.schema = schema
        self.releaseID = releaseID
        self.fileSHA256 = fileSHA256
        self.generated = generated
        self.importedAt = importedAt
        self.entryCount = entryCount
    }
}

public struct PersonalFoodDatabaseInstalledRelease: Equatable, Sendable {
    public let bytes: Data
    public let manifest: PersonalFoodDatabaseManifest

    public init(bytes: Data, manifest: PersonalFoodDatabaseManifest) {
        self.bytes = bytes
        self.manifest = manifest
    }
}

public enum PersonalFoodDatabaseStoreError: Error, Equatable, Sendable {
    /// Protected data is unavailable (the iPhone is locked). Never reported as empty.
    case locked
    /// The pointer, manifest or file does not verify; the release is disabled until replaced.
    case damaged
    case writeFailed
}

/// The protected store of the one active release. Implementations throw only
/// `PersonalFoodDatabaseStoreError`; no file-system type crosses this port.
public protocol PersonalFoodDatabaseStoring: Sendable {
    /// The verified active release, nil when none is installed.
    func activeRelease() throws -> PersonalFoodDatabaseInstalledRelease?
    /// Replaces the active release atomically: on any failure the previous one stays active.
    func install(bytes: Data, manifest: PersonalFoodDatabaseManifest) throws
    /// Removes the active release; true when one (possibly damaged) was present.
    @discardableResult func remove() throws -> Bool
}

/// What Settings shows. It never carries entry content.
public struct PersonalFoodDatabaseSummary: Equatable, Sendable {
    public let releaseID: String
    public let generated: PersonalFoodDatabaseDate
    public let importedAt: Date
    public let entryCount: Int

    public init(_ manifest: PersonalFoodDatabaseManifest) {
        releaseID = manifest.releaseID
        generated = manifest.generated
        importedAt = manifest.importedAt
        entryCount = manifest.entryCount
    }
}

public enum PersonalFoodDatabaseStatus: Equatable, Sendable {
    case none
    case installed(PersonalFoodDatabaseSummary)
    case locked
    case damaged
}

/// The closed set of import outcomes (phase 1 plan section 3.1, change 8). None carries an entry
/// ID, title, value or source field.
public enum PersonalFoodDatabaseImportOutcome: Equatable, Sendable {
    case installed(PersonalFoodDatabaseSummary)
    /// The same bytes are already the verified active release.
    case unchanged(PersonalFoodDatabaseSummary)
    case rejected([PersonalFoodDatabaseRuleCode])
    /// A declared or database release ID is already known with different fields.
    case releaseConflict
    case locked
    case writeFailed
    case tooLarge
    /// The saved release records could not be read, so immutability could not be checked.
    case ledgerUnavailable
}

public enum PersonalFoodDatabaseRemoveOutcome: Equatable, Sendable {
    case removed
    case nothingToRemove
    case locked
    case writeFailed
}

/// The Settings view model's seam.
public protocol PersonalFoodDatabaseImporting: Sendable {
    func status() async -> PersonalFoodDatabaseStatus
    func importFile(_ bytes: Data) async -> PersonalFoodDatabaseImportOutcome
    func remove() async -> PersonalFoodDatabaseRemoveOutcome
}

/// Validates, derives the release from the bytes, checks release immutability against the ledger
/// and the active file, then installs. An actor, so install and remove run one at a time.
public actor PersonalFoodDatabaseImporter: PersonalFoodDatabaseImporting {
    private let store: any PersonalFoodDatabaseStoring
    private let digester: any Digesting
    private let clock: any LedgerClock
    private let releases: any FoodConfirmationReading

    public init(store: any PersonalFoodDatabaseStoring, digester: any Digesting, clock: any LedgerClock,
                releases: any FoodConfirmationReading) {
        self.store = store
        self.digester = digester
        self.clock = clock
        self.releases = releases
    }

    public func status() async -> PersonalFoodDatabaseStatus {
        switch Self.loadActive(store) {
        case let .present(active): .installed(PersonalFoodDatabaseSummary(active.manifest))
        case .absent: .none
        case .locked: .locked
        case .damaged, .unreadable: .damaged
        }
    }

    public func importFile(_ bytes: Data) async -> PersonalFoodDatabaseImportOutcome {
        guard bytes.count <= PersonalFoodDatabaseCodec.limitBytes else { return .tooLarge }
        let file: PersonalFoodDatabaseFile
        switch PersonalFoodDatabaseCodec.decode(bytes) {
        case let .success(decoded): file = decoded
        case let .failure(rejection): return .rejected(rejection.codes)
        }
        guard let digest = try? digester.sha256(bytes) else { return .writeFailed }
        let candidates: [SourceRelease]
        do {
            candidates = try [PersonalFoodDatabaseRelease.sourceRelease(fileSHA256: digest, generated: file.generated)]
                + file.sources.map { try $0.sourceRelease() }
        } catch {
            return .rejected([.malformed])
        }

        var activeSources: [SourceRelease] = []
        switch Self.loadActive(store) {
        case .locked: return .locked
        case .unreadable: return .writeFailed
        case .absent, .damaged: break // over a damaged release the active comparison is skipped (3.1, change 3)
        case let .present(active):
            if active.manifest.fileSHA256 == digest { return .unchanged(PersonalFoodDatabaseSummary(active.manifest)) }
            if case let .success(activeFile) = PersonalFoodDatabaseCodec.decode(active.bytes) {
                activeSources = (try? activeFile.sources.map { try $0.sourceRelease() }) ?? []
            }
        }

        for release in candidates {
            if let other = activeSources.first(where: { $0.sourceReleaseID == release.sourceReleaseID }), other != release {
                return .releaseConflict
            }
            let stored: SourceRelease?
            do { stored = try releases.sourceRelease(id: release.sourceReleaseID) } catch { return .ledgerUnavailable }
            if let stored, stored != release { return .releaseConflict }
        }

        let manifest = PersonalFoodDatabaseManifest(
            schema: PersonalFoodDatabaseFile.schema,
            releaseID: PersonalFoodDatabaseRelease.releaseID(fileSHA256: digest),
            fileSHA256: digest,
            generated: file.generated,
            importedAt: Date(timeIntervalSince1970: clock.now().timeIntervalSince1970.rounded(.down)),
            entryCount: file.entries.count
        )
        do {
            try store.install(bytes: bytes, manifest: manifest)
        } catch PersonalFoodDatabaseStoreError.locked {
            return .locked
        } catch {
            return .writeFailed
        }
        return .installed(PersonalFoodDatabaseSummary(manifest))
    }

    public func remove() async -> PersonalFoodDatabaseRemoveOutcome {
        do {
            return try store.remove() ? .removed : .nothingToRemove
        } catch PersonalFoodDatabaseStoreError.locked {
            return .locked
        } catch {
            return .writeFailed
        }
    }

    private enum ActiveLoad {
        case present(PersonalFoodDatabaseInstalledRelease)
        case absent, locked, damaged, unreadable
    }

    private static func loadActive(_ store: any PersonalFoodDatabaseStoring) -> ActiveLoad {
        do {
            return try store.activeRelease().map(ActiveLoad.present) ?? .absent
        } catch PersonalFoodDatabaseStoreError.locked {
            return .locked
        } catch PersonalFoodDatabaseStoreError.damaged {
            return .damaged
        } catch {
            return .unreadable
        }
    }
}
