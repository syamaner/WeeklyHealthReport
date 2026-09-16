import Foundation
import UIKit

enum DailyNotesStorageError: Error {
    case protectedDataUnavailable
}

protocol DailyNotesPersisting {
    var protectedDataAvailable: Bool { get }
    func load() throws -> DailyNotesDocument?
    func save(_ document: DailyNotesDocument) throws
}

struct EmptyDailyNotesStore: DailyNotesPersisting {
    func load() throws -> DailyNotesDocument? { nil }
    func save(_ document: DailyNotesDocument) throws {}
}

extension DailyNotesPersisting {
    var protectedDataAvailable: Bool { true }

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
    private let isProtectedDataAvailable: () -> Bool

    var protectedDataAvailable: Bool { isProtectedDataAvailable() }

    init(
        fileURL: URL = URL.applicationSupportDirectory
            .appending(path: "WeeklyHealthReport", directoryHint: .isDirectory)
            .appending(path: "daily-notes-v1.json", directoryHint: .notDirectory),
        fileManager: FileManager = .default,
        isProtectedDataAvailable: @escaping () -> Bool = {
            UIApplication.shared.isProtectedDataAvailable
        }
    ) {
        self.fileURL = fileURL
        self.fileManager = fileManager
        self.isProtectedDataAvailable = isProtectedDataAvailable
    }

    func load() throws -> DailyNotesDocument? {
        guard protectedDataAvailable else { throw DailyNotesStorageError.protectedDataUnavailable }
        do {
            guard fileManager.fileExists(atPath: fileURL.path) else { return nil }
            let data = try Data(contentsOf: fileURL)
            let document = try JSONDecoder().decode(DailyNotesDocument.self, from: data)
            guard document.version == DailyNotesDocument.formatVersion else {
                throw DailyNotesError.corruptStorage
            }
            return document
        } catch {
            if !protectedDataAvailable { throw DailyNotesStorageError.protectedDataUnavailable }
            throw error
        }
    }

    func save(_ document: DailyNotesDocument) throws {
        guard protectedDataAvailable else { throw DailyNotesStorageError.protectedDataUnavailable }
        guard document.version == DailyNotesDocument.formatVersion else {
            throw DailyNotesError.corruptStorage
        }
        do {
            try write(document)
        } catch {
            if !protectedDataAvailable { throw DailyNotesStorageError.protectedDataUnavailable }
            throw error
        }
    }

    private func write(_ document: DailyNotesDocument) throws {
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
