import Foundation

public struct DriveAuthorizationRequest: Equatable, Sendable {
    public enum Purpose: Equatable, Sendable {
        case connect
        case createFolder
        case chooseFolder
        case recoverFile
    }

    public let purpose: Purpose
    public let loginHint: String?
    public let selectsAccount: Bool

    public init(purpose: Purpose, loginHint: String? = nil, selectsAccount: Bool = false) {
        self.purpose = purpose
        self.loginHint = loginHint
        self.selectsAccount = selectsAccount
    }

    public var scopes: [String] { [DailyDriveConsentPolicy.scope] }
    public var clientSecret: String? { nil }
    public var responseType: String { "code" }

    public var additionalParameters: [String: String] {
        var parameters = [
            "access_type": "offline",
            "include_granted_scopes": "false"
        ]
        parameters["prompt"] = selectsAccount || purpose == .connect || purpose == .createFolder
            ? "consent select_account"
            : "consent"
        if purpose == .chooseFolder || purpose == .recoverFile {
            if let loginHint, !loginHint.isEmpty {
                parameters["login_hint"] = loginHint
            }
            parameters["trigger_onepick"] = "true"
            parameters["allow_multiple"] = "false"
            parameters["allow_folder_selection"] = purpose == .chooseFolder ? "true" : "false"
            parameters["mimetypes"] = purpose == .chooseFolder
                ? DailyDriveConsentPolicy.folderMIMEType
                : "application/json"
        }
        return parameters
    }
}
