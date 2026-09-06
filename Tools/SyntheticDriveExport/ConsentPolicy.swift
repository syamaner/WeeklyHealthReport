import Foundation

enum DriveConsentPolicy {
    static let scope = "https://www.googleapis.com/auth/drive.file"
    static let folderMIMEType = "application/vnd.google-apps.folder"

    enum Failure: Error, Equatable {
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

    static func validateGrantedScopes(_ rawScope: String?) throws {
        let scopes = Set((rawScope ?? "").split(whereSeparator: { $0.isWhitespace }).map(String.init))
        guard scopes.contains(scope) else { throw Failure.missingDriveFileScope }
        for value in scopes where value != scope {
            throw Failure.unexpectedScope(value)
        }
    }

    static func selectedFolderID(from rawValue: Any?) throws -> String {
        guard let value = rawValue as? String else { throw Failure.invalidPickerSelection }
        let ids = value.split(separator: ",", omittingEmptySubsequences: true).map(String.init)
        guard ids.count == 1, let id = ids.first, !id.isEmpty else {
            throw Failure.invalidPickerSelection
        }
        return id
    }

    static func validate(folder: DriveFolderMetadata, expectedAccountID: String) throws {
        guard folder.accountID == expectedAccountID else { throw Failure.accountMismatch }
        guard folder.isAppAuthorized else { throw Failure.notAppAuthorized }
        guard folder.mimeType == folderMIMEType else { throw Failure.notFolder }
        guard !folder.trashed else { throw Failure.trashed }
        guard folder.driveID == nil else { throw Failure.sharedDriveUnsupported }
        guard folder.canAddChildren else { throw Failure.notWritable }
    }
}

struct DriveFolderMetadata: Codable, Equatable {
    let id: String
    let accountID: String
    let name: String
    let mimeType: String
    let trashed: Bool
    let driveID: String?
    let isAppAuthorized: Bool
    let canAddChildren: Bool
}

struct DestinationBinding: Codable, Equatable {
    enum Origin: String, Codable { case created, picker }

    let accountID: String
    let folderID: String
    let folderName: String
    let origin: Origin
}

struct DestinationPartitions: Codable, Equatable {
    private(set) var values: [String: DestinationBinding] = [:]

    mutating func bind(_ destination: DestinationBinding) {
        values[destination.accountID] = destination
    }

    func destination(for accountID: String) -> DestinationBinding? {
        values[accountID]
    }
}

enum DisconnectTransition: Equatable {
    case keepCredentialsAndReportFailure
    case clearCredentialsPreserveDestinations

    static func afterRevocation(statusCode: Int) -> DisconnectTransition {
        statusCode == 200 ? .clearCredentialsPreserveDestinations : .keepCredentialsAndReportFailure
    }
}
