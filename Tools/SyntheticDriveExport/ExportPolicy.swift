import Foundation

struct ExportPolicy {
    private(set) var highestSubmitted: Int
    private(set) var active = false

    mutating func begin(_ revision: Int) -> Bool {
        guard !active, revision >= highestSubmitted else { return false }
        highestSubmitted = revision
        active = true
        return true
    }

    mutating func finish() { active = false }
}

enum SyntheticPayload {
    static let filename = "health-daily-2026-09-06.json"
    static func data(_ revision: Int) throws -> Data {
        let labels = [1: "morning", 2: "evening", 3: "bedtime"]
        let hours = [1: "08", 2: "18", 3: "23"]
        guard let label = labels[revision], let hour = hours[revision] else {
            throw CocoaError(.coderInvalidValue)
        }
        // Fixed bytes for repeat-save tests. This is not the production health schema.
        return try JSONSerialization.data(withJSONObject: [
            "synthetic_only": true,
            "fixture_version": 1,
            "report_date": "2026-09-06",
            "time_zone": "Europe/London",
            "data_as_of": "2026-09-06T\(hour):00:00+01:00",
            "revision": revision,
            "marker": label,
            "invented_steps": revision * 1234
        ], options: [.prettyPrinted, .sortedKeys])
    }

    static func revision(in candidate: Data) throws -> Int {
        for revision in 1...3 where candidate == (try data(revision)) {
            return revision
        }
        throw CocoaError(.coderInvalidValue)
    }
}

// Disposable directory-route probe, not a production storage abstraction.
enum DirectoryProbe {
    static let folderName = "WHR-Directory-2026-09-06"

    enum Failure: Int, Error, CustomNSError {
        case wrongFolder = 1, unexpectedContents, unknownPayload, staleRevision
        case injectedFailure, verificationFailed, noAccessor
        static var errorDomain: String { "SyntheticDirectoryProbe" }
        var errorCode: Int { rawValue }
    }

    static func write(_ revision: Int, in folder: URL, injectFailure: Bool = false) throws -> String {
        guard folder.lastPathComponent == folderName else { throw Failure.wrongFolder }
        let bytes = try SyntheticPayload.data(revision)
        var coordinationError: NSError?
        var outcome: Result<String, Error> = .failure(Failure.noAccessor)
        // Coordinate the containing directory while enumerating and replacing its child.
        // Run off the main thread; a provider may need to fetch data before access.
        NSFileCoordinator().coordinate(writingItemAt: folder, options: [], error: &coordinationError) { directory in
            outcome = Result { try transact(bytes, revision: revision, directory: directory, injectFailure: injectFailure) }
        }
        if let coordinationError { throw coordinationError }
        return try outcome.get()
    }

    private static func transact(_ bytes: Data, revision: Int, directory: URL, injectFailure: Bool) throws -> String {
        let manager = FileManager.default
        let children = try manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard children.count <= 1,
              children.allSatisfy({ $0.lastPathComponent == SyntheticPayload.filename }) else {
            throw Failure.unexpectedContents
        }
        let destination = directory.appendingPathComponent(SyntheticPayload.filename)
        var previous: Data?
        if let existing = children.first {
            let values = try existing.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true else { throw Failure.unexpectedContents }
            previous = try Data(contentsOf: existing)
            var previousRevision: Int?
            for candidate in 1...3 where previous == (try SyntheticPayload.data(candidate)) {
                previousRevision = candidate
            }
            guard let previousRevision else { throw Failure.unknownPayload }
            guard previousRevision <= revision else { throw Failure.staleRevision }
        }
        if injectFailure { throw Failure.injectedFailure }
        if previous == bytes { return "Identical existing payload; no write. Remote upload UNVERIFIED" }
        // Never delete first. Whether a provider preserves identity/atomicity is the experiment.
        try bytes.write(to: destination, options: .atomic)
        let after = try manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        guard after.count == 1, after.first?.lastPathComponent == SyntheticPayload.filename,
              try Data(contentsOf: destination) == bytes else { throw Failure.verificationFailed }
        return "Local write/readback: one file, revision \(revision). Remote upload UNVERIFIED"
    }
}

// Opens an existing document, never creates a destination or enumerates its parent.
enum ExistingFileProbe {
    static func write(_ revision: Int, at file: URL, injectFailure: Bool = false) throws -> String {
        guard file.lastPathComponent == SyntheticPayload.filename else { throw DirectoryProbe.Failure.wrongFolder }
        let bytes = try SyntheticPayload.data(revision)
        var coordinationError: NSError?
        var result: Result<String, Error> = .failure(DirectoryProbe.Failure.noAccessor)
        NSFileCoordinator().coordinate(writingItemAt: file, options: .forReplacing, error: &coordinationError) { target in
            result = Result {
                let values = try target.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                guard values.isRegularFile == true, values.isSymbolicLink != true else {
                    throw DirectoryProbe.Failure.unexpectedContents
                }
                let before = try Data(contentsOf: target)
                var current: Int?
                for candidate in 1...3 where before == (try SyntheticPayload.data(candidate)) { current = candidate }
                guard let current else { throw DirectoryProbe.Failure.unknownPayload }
                guard current <= revision else { throw DirectoryProbe.Failure.staleRevision }
                if injectFailure { throw DirectoryProbe.Failure.injectedFailure }
                if before == bytes { return "Identical selected payload; no write. Remote upload UNVERIFIED" }
                // No truncate/delete-first fallback if provider rejects atomic replacement.
                try bytes.write(to: target, options: .atomic)
                guard try Data(contentsOf: target) == bytes else { throw DirectoryProbe.Failure.verificationFailed }
                return "Selected file readback matches revision \(revision). Remote identity/count/upload UNVERIFIED"
            }
        }
        if let coordinationError { throw coordinationError }
        return try result.get()
    }
}
