import Foundation

public protocol DailyDriveTransporting: Sendable {
    func account(accessToken: String) async throws -> DailyDriveAccount
    func generateFileID(accessToken: String) async throws -> String
    func createFile(
        _ descriptor: DailyDriveUploadDescriptor,
        content: Data,
        accessToken: String
    ) async throws
    func updateFile(
        _ descriptor: DailyDriveUploadDescriptor,
        content: Data,
        accessToken: String
    ) async throws
    func fileMetadata(id: String, accessToken: String) async throws -> DailyDriveFileMetadata
    func fileContent(id: String, accessToken: String) async throws -> Data
}

public protocol DailyDriveSessionTransporting: DailyDriveTransporting {
    func createFolder(
        id: String,
        accessToken: String,
        accountID: String
    ) async throws -> DailyDriveFolder
    func folder(
        id: String,
        accessToken: String,
        accountID: String
    ) async throws -> DailyDriveFolder
    func revoke(token: String) async throws -> Int
}
