#if canImport(DriveExportKit)
import DriveExportKit
#endif

typealias DriveAccount = DailyDriveAccount
typealias DriveFolderMetadata = DailyDriveFolder
typealias DriveFileMetadata = DailyDriveFileMetadata
typealias DriveUploadDescriptor = DailyDriveUploadDescriptor
typealias DriveTransporting = DailyDriveTransporting
typealias DriveAPI = DailyDriveAPI
typealias KeychainStore = DailyDriveKeychainStore
typealias DriveConsentPolicy = DailyDriveConsentPolicy
typealias DestinationBinding = DailyDestinationBinding
typealias DestinationPartitions = DailyDestinationPartitions
typealias DisconnectTransition = DailyDisconnectTransition

enum UnrelatedFileAccessFailure: Error, Equatable {
    case unexpectedAccess
}

extension DailyDriveAPI {
    func confirmUnrelatedFileDenied(id: String, accessToken: String) async throws {
        do {
            _ = try await fileMetadata(id: id, accessToken: accessToken)
            throw UnrelatedFileAccessFailure.unexpectedAccess
        } catch Failure.httpStatus(403, _), Failure.httpStatus(404, _) {
            return
        }
    }
}
