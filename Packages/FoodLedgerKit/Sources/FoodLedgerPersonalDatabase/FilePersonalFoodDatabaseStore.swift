import FoodLedgerApplication
import FoodLedgerDomain
import Foundation

/// The protected file store of Your food database (phase 1 plan sections 3 and 3.1).
///
/// ```text
/// <root>/Datasets/personal-food-database/active.json                       pointer (commit point)
/// <root>/Datasets/personal-food-database/pfc-sha256-<hex>/personal-food-catalogue-v1.json
/// <root>/Datasets/personal-food-database/pfc-sha256-<hex>/manifest.json
/// <root>/ImportStaging/personal-food-database-<uuid>/
/// ```
///
/// The data file name is a fixed storage name, not the file's schema: a `personal-food-catalogue-v2`
/// file is stored under it too, so an installed database keeps loading (import v2, owner decision 4).
///
/// `root` is the app's `FoodLedger/v1/` folder, inside the backup-excluded `WeeklyHealthReport/`
/// root. Nothing touches the disk until a method is called, so building the store while the phone
/// is locked is safe.
public struct FilePersonalFoodDatabaseStore: PersonalFoodDatabaseStoring {
    /// The steps an injected fault can interrupt, for the crash-safety contract tests.
    enum Step: Sendable { case staging, rename, pointer }

    public typealias ProtectionApplier = @Sendable (URL) throws -> Void

    /// Sets `FileProtectionType.complete` on iOS. The attribute does not exist on macOS, where the
    /// package tests run, so tests inject a recording applier instead.
    public static let completeFileProtection: ProtectionApplier = { url in
        #if os(iOS)
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: url.path)
        #endif
    }

    static let fileName = "personal-food-catalogue-v1.json"
    static let manifestName = "manifest.json"
    static let pointerName = "active.json"
    static let folderPrefix = "pfc-sha256-"
    static let stagingPrefix = "personal-food-database-"

    /// Serialises every install and remove in the process, across store instances: they share one
    /// pending pointer and each sweep keeps only its own release, so two at once could delete or
    /// replace the other's work after both reported success. Reads need no lock, because the
    /// pointer changes only by an atomic rename.
    static let writeLock = NSLock()

    let base: URL
    let staging: URL
    private let digester: any Digesting
    private let isProtectedDataAvailable: @Sendable () -> Bool
    private let protect: ProtectionApplier
    private let fault: (@Sendable (Step) throws -> Void)?

    public init(root: URL, digester: any Digesting, isProtectedDataAvailable: @escaping @Sendable () -> Bool,
                protect: @escaping ProtectionApplier = Self.completeFileProtection) {
        self.init(root: root, digester: digester, isProtectedDataAvailable: isProtectedDataAvailable, protect: protect, fault: nil)
    }

    init(root: URL, digester: any Digesting, isProtectedDataAvailable: @escaping @Sendable () -> Bool,
         protect: @escaping ProtectionApplier, fault: (@Sendable (Step) throws -> Void)?) {
        base = root.appendingPathComponent("Datasets", isDirectory: true)
            .appendingPathComponent("personal-food-database", isDirectory: true)
        staging = root.appendingPathComponent("ImportStaging", isDirectory: true)
        self.digester = digester
        self.isProtectedDataAvailable = isProtectedDataAvailable
        self.protect = protect
        self.fault = fault
    }

    private var pointerURL: URL { base.appendingPathComponent(Self.pointerName) }

    static func folderName(_ digest: SHA256Digest) -> String { folderPrefix + digest.value }

    // MARK: Load

    public func activeRelease() throws -> PersonalFoodDatabaseInstalledRelease? {
        guard isProtectedDataAvailable() else { throw PersonalFoodDatabaseStoreError.locked }
        // Only a pointer that does not exist means no release; one that exists but cannot be
        // reached is damaged (or locked), never absent.
        do { _ = try FileManager.default.attributesOfItem(atPath: pointerURL.path) } catch let error as CocoaError
            where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile {
            return nil
        } catch {
            throw isProtectedDataAvailable() ? PersonalFoodDatabaseStoreError.damaged : .locked
        }
        let pointer = try read(pointerURL, as: PersonalFoodDatabaseStoredPointer.self)
        guard pointer.version == PersonalFoodDatabaseStoredPointer.currentVersion,
              Self.isFolderName(pointer.folder) else { throw PersonalFoodDatabaseStoreError.damaged }
        let folder = base.appendingPathComponent(pointer.folder, isDirectory: true)
        let stored = try read(folder.appendingPathComponent(Self.manifestName), as: PersonalFoodDatabaseStoredManifest.self)
        guard let manifest = stored.manifest else { throw PersonalFoodDatabaseStoreError.damaged }
        let bytes = try readData(folder.appendingPathComponent(Self.fileName))
        guard let digest = try? digester.sha256(bytes), digest == manifest.fileSHA256,
              manifest.releaseID == PersonalFoodDatabaseRelease.releaseID(fileSHA256: digest),
              pointer.folder == Self.folderName(digest) else { throw PersonalFoodDatabaseStoreError.damaged }
        return PersonalFoodDatabaseInstalledRelease(bytes: bytes, manifest: manifest)
    }

    // MARK: Install and remove

    public func install(bytes: Data, manifest: PersonalFoodDatabaseManifest) throws {
        Self.writeLock.lock()
        defer { Self.writeLock.unlock() }
        guard isProtectedDataAvailable() else { throw PersonalFoodDatabaseStoreError.locked }
        guard manifest.releaseID == PersonalFoodDatabaseRelease.releaseID(fileSHA256: manifest.fileSHA256),
              (try? digester.sha256(bytes)) == manifest.fileSHA256,
              // Only a manifest this store's own reader accepts back unchanged is written, so a
              // successful install never reads as damaged.
              PersonalFoodDatabaseStoredManifest(manifest).manifest == manifest else {
            throw PersonalFoodDatabaseStoreError.writeFailed
        }
        let folderName = Self.folderName(manifest.fileSHA256)
        let stage = staging.appendingPathComponent(Self.stagingPrefix + UUID().uuidString, isDirectory: true)
        let pending = base.appendingPathComponent(Self.pointerName + ".pending")
        // A failed install removes its own staging copy at once; anything older is swept later.
        defer {
            try? FileManager.default.removeItem(at: stage)
            try? FileManager.default.removeItem(at: pending)
        }
        try guarded {
            let fileManager = FileManager.default
            try makeDirectory(base)
            // `ImportStaging` is shared with other features: only this call's subfolder is protected.
            try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
            try makeDirectory(stage)
            try write(bytes, to: stage.appendingPathComponent(Self.fileName))
            try write(PersonalFoodDatabaseStoredManifest(manifest).encoded(), to: stage.appendingPathComponent(Self.manifestName))
            try fault?(.staging)

            // A folder of the same release already in place is never changed while the current
            // pointer names it and it verifies: it is reused as it is. Otherwise it is an orphan of a
            // crashed install (no pointer names it) or a damaged copy (nothing valid to lose), and the
            // new copy replaces it. So no failure before the commit point changes a valid release.
            let target = base.appendingPathComponent(folderName, isDirectory: true)
            var reuse = false
            if fileManager.fileExists(atPath: target.path) {
                let named = (try? Self.decodePointer(fileManager.contents(atPath: pointerURL.path)))?.folder == folderName
                if named, verifies(target, digest: manifest.fileSHA256, schema: manifest.schema) {
                    reuse = true
                } else {
                    try fileManager.removeItem(at: target)
                }
            }
            if !reuse {
                try fault?(.rename)
                try fileManager.moveItem(at: stage, to: target)
                // Protection travels with a move; applying it again at the final paths keeps the rule
                // checkable path by path.
                for url in [target, target.appendingPathComponent(Self.fileName), target.appendingPathComponent(Self.manifestName)] {
                    try protect(url)
                }
            }

            // The pointer is written and protected beside its final name, then renamed over it: the
            // rename is the commit point and nothing that can fail runs after it.
            try write(PersonalFoodDatabaseStoredPointer(folder: folderName).encoded(), to: pending)
            try fault?(.pointer)
            if fileManager.fileExists(atPath: pointerURL.path) {
                _ = try fileManager.replaceItemAt(pointerURL, withItemAt: pending, options: .usingNewMetadataOnly)
            } else {
                try fileManager.moveItem(at: pending, to: pointerURL)
            }
        }
        sweep(keeping: folderName)
    }

    @discardableResult
    public func remove() throws -> Bool {
        Self.writeLock.lock()
        defer { Self.writeLock.unlock() }
        guard isProtectedDataAvailable() else { throw PersonalFoodDatabaseStoreError.locked }
        let fileManager = FileManager.default
        let present = fileManager.fileExists(atPath: pointerURL.path)
        if present { try guarded { try fileManager.removeItem(at: pointerURL) } }
        sweep(keeping: nil)
        return present
    }

    /// Runs only after this call's commit point succeeded. Deletes release folders other than the
    /// one kept and only this feature's staging folders (other features share `ImportStaging`).
    private func sweep(keeping folder: String?) {
        guard isProtectedDataAvailable() else { return }
        let fileManager = FileManager.default
        for name in (try? fileManager.contentsOfDirectory(atPath: base.path)) ?? []
        where Self.isFolderName(name) && name != folder {
            try? fileManager.removeItem(at: base.appendingPathComponent(name, isDirectory: true))
        }
        for name in (try? fileManager.contentsOfDirectory(atPath: staging.path)) ?? [] where name.hasPrefix(Self.stagingPrefix) {
            try? fileManager.removeItem(at: staging.appendingPathComponent(name, isDirectory: true))
        }
    }

    // MARK: File helpers

    static func isFolderName(_ name: String) -> Bool {
        guard name.hasPrefix(folderPrefix) else { return false }
        let hex = name.utf8.dropFirst(folderPrefix.utf8.count)
        return hex.count == 64 && hex.allSatisfy { (0x30...0x39).contains($0) || (0x61...0x66).contains($0) }
    }

    private func makeDirectory(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try protect(url)
    }

    private func write(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: .atomic)
        try protect(url)
    }

    /// A read failure while protected data is unavailable is `locked`; otherwise the release is `damaged`.
    /// Local file reads only, by path (no URL loading API is reachable from this store).
    private func readData(_ url: URL) throws -> Data {
        guard let data = FileManager.default.contents(atPath: url.path) else {
            throw isProtectedDataAvailable() ? PersonalFoodDatabaseStoreError.damaged : .locked
        }
        return data
    }

    /// A folder is reused only when its manifest names the same file and schema, so a reinstall
    /// repairs a manifest whose schema was wrong (import v2).
    private func verifies(_ folder: URL, digest: SHA256Digest, schema: String) -> Bool {
        guard let bytes = FileManager.default.contents(atPath: folder.appendingPathComponent(Self.fileName).path),
              let stored = try? JSONDecoder().decode(PersonalFoodDatabaseStoredManifest.self,
                  from: FileManager.default.contents(atPath: folder.appendingPathComponent(Self.manifestName).path) ?? Data()),
              let storedManifest = stored.manifest, storedManifest.fileSHA256 == digest, storedManifest.schema == schema,
              storedManifest.releaseID == PersonalFoodDatabaseRelease.releaseID(fileSHA256: digest) else { return false }
        return (try? digester.sha256(bytes)) == digest
    }

    static func decodePointer(_ data: Data?) throws -> PersonalFoodDatabaseStoredPointer? {
        guard let data else { return nil }
        return try JSONDecoder().decode(PersonalFoodDatabaseStoredPointer.self, from: data)
    }

    private func read<T: Decodable>(_ url: URL, as type: T.Type) throws -> T {
        let data = try readData(url)
        guard let value = try? JSONDecoder().decode(T.self, from: data) else { throw PersonalFoodDatabaseStoreError.damaged }
        return value
    }

    /// Maps every file-system error to the port's closed set.
    private func guarded(_ body: () throws -> Void) throws {
        do { try body() } catch let error as PersonalFoodDatabaseStoreError { throw error } catch {
            throw isProtectedDataAvailable() ? PersonalFoodDatabaseStoreError.writeFailed : .locked
        }
    }
}

/// `active.json`, version 1: `{"folder":"pfc-sha256-<hex>","version":1}` with sorted keys.
struct PersonalFoodDatabaseStoredPointer: Codable, Equatable {
    static let currentVersion = 1
    let folder: String
    let version: Int

    init(folder: String, version: Int = currentVersion) {
        self.folder = folder
        self.version = version
    }

    func encoded() throws -> Data { try PersonalFoodDatabaseStoredJSON.encoder.encode(self) }
}

/// `manifest.json`, version 1, with sorted keys. `generated` is `YYYY-MM-DD`; `imported_at` is
/// RFC 3339 UTC to the second with a `Z`.
struct PersonalFoodDatabaseStoredManifest: Codable, Equatable {
    static let currentVersion = 1
    let entryCount: Int
    let fileSHA256: String
    let generated: String
    let importedAt: String
    let releaseID: String
    let schema: String
    let version: Int

    enum CodingKeys: String, CodingKey {
        case entryCount = "entry_count", fileSHA256 = "file_sha256", generated
        case importedAt = "imported_at", releaseID = "release_id", schema, version
    }

    init(_ manifest: PersonalFoodDatabaseManifest) {
        entryCount = manifest.entryCount
        fileSHA256 = manifest.fileSHA256.value
        generated = manifest.generated.text
        importedAt = manifest.importedAt.formatted(Date.ISO8601FormatStyle())
        releaseID = manifest.releaseID
        schema = manifest.schema
        version = Self.currentVersion
    }

    /// Nil for any version, schema, date, digest or count this store did not write.
    var manifest: PersonalFoodDatabaseManifest? {
        // Either accepted file schema (import v2); the data file name stays a fixed storage name.
        guard version == Self.currentVersion, PersonalFoodDatabaseSchema(rawValue: schema) != nil, entryCount >= 0,
              let digest = try? SHA256Digest(fileSHA256),
              let date = PersonalFoodDatabaseDate(ascii: Array(generated.utf8)),
              let imported = try? Date(importedAt, strategy: Date.ISO8601FormatStyle()),
              imported.formatted(Date.ISO8601FormatStyle()) == importedAt else { return nil }
        return PersonalFoodDatabaseManifest(schema: schema, releaseID: releaseID, fileSHA256: digest, generated: date,
                                            importedAt: imported, entryCount: entryCount)
    }

    func encoded() throws -> Data { try PersonalFoodDatabaseStoredJSON.encoder.encode(self) }
}

enum PersonalFoodDatabaseStoredJSON {
    static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }
}
