import Foundation

public enum DailyDriveConsentPolicy {
    public static let scope = "https://www.googleapis.com/auth/drive.file"
    public static let folderMIMEType = "application/vnd.google-apps.folder"
    public static let defaultExportFolderName = "WeeklyHealthReport Exports"

    public enum Failure: Error, Equatable {
        case missingDriveFileScope
        case unexpectedScope(String)
        case invalidPickerSelection
        case accountMismatch
        case notAppAuthorized
        case notFolder
        case trashed
        case sharedDriveUnsupported
        case notWritable
    }

    public static func validateGrantedScopes(_ rawScope: String?) throws {
        let scopes = Set((rawScope ?? "").split(whereSeparator: { $0.isWhitespace }).map(String.init))
        guard scopes.contains(scope) else { throw Failure.missingDriveFileScope }
        for value in scopes where value != scope {
            throw Failure.unexpectedScope(value)
        }
    }

    public static func selectedItemID(from rawValue: Any?) throws -> String {
        guard let value = rawValue as? String else { throw Failure.invalidPickerSelection }
        let ids = value.split(separator: ",", omittingEmptySubsequences: true).map(String.init)
        guard ids.count == 1, let id = ids.first, !id.isEmpty else {
            throw Failure.invalidPickerSelection
        }
        return id
    }

    public static func validate(folder: DailyDriveFolder, expectedAccountID: String) throws {
        guard folder.accountID == expectedAccountID else { throw Failure.accountMismatch }
        guard folder.isAppAuthorized else { throw Failure.notAppAuthorized }
        guard folder.mimeType == folderMIMEType else { throw Failure.notFolder }
        guard !folder.trashed else { throw Failure.trashed }
        guard folder.driveID == nil else { throw Failure.sharedDriveUnsupported }
        guard folder.canAddChildren else { throw Failure.notWritable }
    }
}
