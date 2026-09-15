import AppAuth
import DriveExportKit
import Foundation

public struct DriveAuthorizationOutcome: Equatable, Sendable {
    public let accessToken: String
    public let pickedItemID: String?

    public init(accessToken: String, pickedItemID: String?) {
        self.accessToken = accessToken
        self.pickedItemID = pickedItemID
    }
}

@MainActor
public protocol DriveOAuthSessionProviding: AnyObject {
    var hasStoredSession: Bool { get }
    var revocationToken: String? { get }
    var onAuthorizationError: (@MainActor (DailyDriveCredentialFailure) -> Void)? { get set }

    func restoreWithoutNetwork() throws
    func authorize(
        _ request: DriveAuthorizationRequest,
        configuration: DriveOAuthClientConfiguration,
        userAgent: any OIDExternalUserAgent
    ) async throws -> DriveAuthorizationOutcome
    func acceptPendingAuthorization() throws
    func discardPendingAuthorization()
    func accessToken(forceRefresh: Bool) async throws -> String
    func validateCurrentGrant() throws
    func clear() throws
    func resumeRedirect(_ url: URL) -> Bool
}
