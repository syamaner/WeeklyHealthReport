import Foundation

public struct DriveOAuthClientConfiguration: Equatable, Sendable {
    public enum Failure: Error, Equatable {
        case missingConfiguration
        case invalidConfiguration
    }

    public let clientID: String
    public let redirectURL: URL

    public init(infoDictionary: [String: Any]) throws {
        guard let clientID = infoDictionary["GoogleOAuthClientID"] as? String,
              let scheme = infoDictionary["GoogleOAuthRedirectScheme"] as? String,
              clientID != "MISSING", scheme != "MISSING" else {
            throw Failure.missingConfiguration
        }
        let suffix = ".apps.googleusercontent.com"
        guard clientID.hasSuffix(suffix) else { throw Failure.invalidConfiguration }
        let stem = String(clientID.dropLast(suffix.count))
        guard scheme == "com.googleusercontent.apps.\(stem)",
              let redirectURL = URL(string: "\(scheme):/oauth2redirect") else {
            throw Failure.invalidConfiguration
        }
        self.clientID = clientID
        self.redirectURL = redirectURL
    }

    public static func fromMainBundle() throws -> DriveOAuthClientConfiguration {
        try DriveOAuthClientConfiguration(infoDictionary: Bundle.main.infoDictionary ?? [:])
    }
}
