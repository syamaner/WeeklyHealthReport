import Foundation

protocol DailyNotesPersisting {
    func load() throws -> DailyNotesDocument?
    func save(_ document: DailyNotesDocument) throws
}

struct EmptyDailyNotesStore: DailyNotesPersisting {
    func load() throws -> DailyNotesDocument? { nil }
    func save(_ document: DailyNotesDocument) throws {}
}

extension DailyNotesPersisting {
    func snapshot(for dayID: DailyNoteDayID) throws -> DailyNotesSnapshot {
        let document = try load() ?? DailyNotesDocument()
        guard document.version == DailyNotesDocument.formatVersion else {
            throw DailyNotesError.corruptStorage
        }
        return document.snapshot(for: dayID)
    }

    func containsCurrent(_ snapshot: DailyNotesSnapshot) throws -> Bool {
        try self.snapshot(for: snapshot.dayID) == snapshot
    }
}

struct FileDailyNotesStore: DailyNotesPersisting {
    private let fileURL: URL
    private let fileManager: FileManager

    init(
        fileURL: URL = URL.applicationSupportDirectory
            .appending(path: "WeeklyHealthReport", directoryHint: .isDirectory)
            .appending(path: "daily-notes-v1.json", directoryHint: .notDirectory),
        fileManager: FileManager = .default
    ) {
        self.fileURL = fileURL
        self.fileManager = fileManager
    }

    func load() throws -> DailyNotesDocument? {
        guard fileManager.fileExists(atPath: fileURL.path) else { return nil }
        let data = try Data(contentsOf: fileURL)
        let document = try JSONDecoder().decode(DailyNotesDocument.self, from: data)
        guard document.version == DailyNotesDocument.formatVersion else {
            throw DailyNotesError.corruptStorage
        }
        return document
    }

    func save(_ document: DailyNotesDocument) throws {
        guard document.version == DailyNotesDocument.formatVersion else {
            throw DailyNotesError.corruptStorage
        }
        let directory = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.complete]
        )
        try fileManager.setAttributes(
            [.protectionKey: FileProtectionType.complete],
            ofItemAtPath: directory.path
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(document)
        let temporaryURL = directory.appending(
            path: ".daily-notes-\(UUID().uuidString).tmp",
            directoryHint: .notDirectory
        )
        defer { try? fileManager.removeItem(at: temporaryURL) }

        try data.write(to: temporaryURL, options: .withoutOverwriting)
        try fileManager.setAttributes(
            [.protectionKey: FileProtectionType.complete],
            ofItemAtPath: temporaryURL.path
        )
        if fileManager.fileExists(atPath: fileURL.path) {
            _ = try fileManager.replaceItemAt(fileURL, withItemAt: temporaryURL)
        } else {
            try fileManager.moveItem(at: temporaryURL, to: fileURL)
        }
    }
}
