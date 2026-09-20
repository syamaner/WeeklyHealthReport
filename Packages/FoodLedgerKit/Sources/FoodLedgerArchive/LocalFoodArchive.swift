import Foundation
import FoodLedgerApplication
import FoodLedgerGRDB

public struct LocalFoodArchiveStore: Sendable {
    private let verifier: FoodArchiveVerifier

    public init(
        verifier: FoodArchiveVerifier = FoodArchiveVerifier()
    ) {
        self.verifier = verifier
    }

    public func export(_ bundle: FoodArchiveBundle, to destination: URL) throws {
        _ = try verifier.verify(bundle)
        guard !FileManager.default.fileExists(atPath: destination.path) else {
            throw CocoaError(.fileWriteFileExists)
        }
        let staging = destination.deletingLastPathComponent()
            .appendingPathComponent(".\(destination.lastPathComponent).incomplete-\(UUID().uuidString)")
        do {
            try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: false)
            try protect(staging)
            try bundle.snapshot.write(
                to: staging.appendingPathComponent("snapshot.json"),
                options: [.atomic, .completeFileProtection]
            )
            try bundle.operations.write(
                to: staging.appendingPathComponent("operations.ndjson"),
                options: [.atomic, .completeFileProtection]
            )
            // A generation is incomplete until the manifest is durably written last.
            try bundle.manifest.write(
                to: staging.appendingPathComponent("manifest.json"),
                options: [.atomic, .completeFileProtection]
            )
            _ = try read(from: staging)
            try FileManager.default.moveItem(at: staging, to: destination)
            try protect(destination)
        } catch {
            try? FileManager.default.removeItem(at: staging)
            throw error
        }
    }

    public func read(from archive: URL) throws -> FoodArchiveBundle {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: archive.path, isDirectory: &isDirectory),
              isDirectory.boolValue,
              FileManager.default.fileExists(atPath: archive.appendingPathComponent("manifest.json").path)
        else { throw FoodArchiveError.interruptedGeneration }
        let expected = Set(["manifest.json", "snapshot.json", "operations.ndjson"])
        let actual = try Set(FileManager.default.contentsOfDirectory(atPath: archive.path))
        guard actual == expected else { throw FoodArchiveError.malformedArchive("members") }
        let bundle = FoodArchiveBundle(
            manifest: try Data(contentsOf: archive.appendingPathComponent("manifest.json")),
            snapshot: try Data(contentsOf: archive.appendingPathComponent("snapshot.json")),
            operations: try Data(contentsOf: archive.appendingPathComponent("operations.ndjson"))
        )
        _ = try verifier.verify(bundle)
        return bundle
    }

    private func protect(_ url: URL) throws {
        try FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.complete],
            ofItemAtPath: url.path
        )
    }
}

public struct ProtectedGRDBFoodArchiveStaging: FoodArchiveStaging {
    private let root: URL

    public init(root: URL) {
        self.root = root
    }

    public func validate(_ transactions: [LedgerTransaction]) throws -> FoodArchiveState {
        let directory = root.appendingPathComponent("food-import-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.complete],
            ofItemAtPath: directory.path
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try FoodLedgerGRDBStore.temporary(directory: directory)
        _ = try store.commitAtomically(transactions)
        try store.verifyIntegrity()
        return try store.archiveState()
    }
}
