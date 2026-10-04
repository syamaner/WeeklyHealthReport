import Foundation

/// Infrastructure policy for the app-owned health-data directory. Excluding the
/// directory also covers existing/future SQLite sidecars, attachments and drafts.
/// This does not delete data already included in an older system backup.
enum LocalHealthStorageDirectory {
    enum PreparationError: Error { case backupExclusionNotApplied }

    static func prepare(_ directory: URL, fileManager: FileManager = .default) throws {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        var directory = directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try directory.setResourceValues(values)
        guard try directory.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true else {
            throw PreparationError.backupExclusionNotApplied
        }
    }
}
