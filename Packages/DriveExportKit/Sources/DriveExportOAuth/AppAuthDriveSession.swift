import AppAuth
import DriveExportKit
import Foundation

@MainActor
public final class AppAuthDriveSession: NSObject, DriveOAuthSessionProviding {
    nonisolated public static let errorDomain = OIDGeneralErrorDomain
    nonisolated public static let userCancelledAuthorizationFlowCode = -3

    public var hasStoredSession: Bool { authState != nil }
    public var revocationToken: String? {
        authState?.refreshToken ?? authState?.lastTokenResponse?.accessToken
    }
    public var onAuthorizationError: (@MainActor (DailyDriveCredentialFailure) -> Void)?

    nonisolated private static let tokenRefreshErrorCode = -11
    nonisolated private static let accessDeniedErrorCode = -4

    private let secureStore: any DailyDriveSecurePersisting
    private let authKey: String
    private var authState: OIDAuthState?
    private var pendingAuthState: OIDAuthState?
    private var authorizationFlow: OIDExternalUserAgentSession?

    public init(secureStore: any DailyDriveSecurePersisting, authKey: String) {
        self.secureStore = secureStore
        self.authKey = authKey
        super.init()
    }

    public func restoreWithoutNetwork() throws {
        authState = nil
        guard let data = try secureStore.load(account: authKey) else { return }
        do {
            authState = try NSKeyedUnarchiver.unarchivedObject(
                ofClass: OIDAuthState.self,
                from: data
            )
            attachDelegates()
        } catch {
            authState = nil
            throw error
        }
    }

    public func authorize(
        _ authorization: DriveAuthorizationRequest,
        configuration: DriveOAuthClientConfiguration,
        userAgent: any OIDExternalUserAgent
    ) async throws -> DriveAuthorizationOutcome {
        let service = OIDServiceConfiguration(
            authorizationEndpoint: URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!,
            tokenEndpoint: URL(string: "https://oauth2.googleapis.com/token")!
        )
        let request = OIDAuthorizationRequest(
            configuration: service,
            clientId: configuration.clientID,
            clientSecret: authorization.clientSecret,
            scopes: authorization.scopes,
            redirectURL: configuration.redirectURL,
            responseType: authorization.responseType,
            additionalParameters: authorization.additionalParameters
        )
        let newState: OIDAuthState = try await withCheckedThrowingContinuation { continuation in
            authorizationFlow = OIDAuthState.authState(
                byPresenting: request,
                externalUserAgent: userAgent
            ) { state, error in
                self.authorizationFlow = nil
                if let state {
                    continuation.resume(returning: state)
                } else {
                    continuation.resume(throwing: error ?? DailyDriveCredentialFailure.missing)
                }
            }
        }
        try DailyDriveConsentPolicy.validateGrantedScopes(newState.scope)
        let pickedItemID: String?
        if authorization.purpose == .chooseFolder || authorization.purpose == .recoverFile {
            pickedItemID = try DailyDriveConsentPolicy.selectedItemID(
                from: newState.lastAuthorizationResponse.additionalParameters?["picked_file_ids"]
            )
        } else {
            pickedItemID = nil
        }
        guard let accessToken = newState.lastTokenResponse?.accessToken else {
            throw DailyDriveCredentialFailure.missing
        }
        pendingAuthState = newState
        return DriveAuthorizationOutcome(
            accessToken: accessToken,
            pickedItemID: pickedItemID
        )
    }

    public func acceptPendingAuthorization() throws {
        guard let pendingAuthState else { throw DailyDriveCredentialFailure.missing }
        authState = pendingAuthState
        self.pendingAuthState = nil
        attachDelegates()
        try saveAuthState()
    }

    public func discardPendingAuthorization() {
        pendingAuthState = nil
    }

    public func accessToken(forceRefresh: Bool = false) async throws -> String {
        guard let authState else { throw DailyDriveCredentialFailure.missing }
        if forceRefresh { authState.setNeedsTokenRefresh() }
        return try await withCheckedThrowingContinuation { continuation in
            authState.performAction { accessToken, _, error in
                continuation.resume(with: Result {
                    try Self.resolveAccessToken(accessToken, error: error)
                })
            }
        }
    }

    public func validateCurrentGrant() throws {
        guard let authState else { throw DailyDriveCredentialFailure.missing }
        try DailyDriveConsentPolicy.validateGrantedScopes(authState.scope)
    }

    public func clear() throws {
        try secureStore.delete(account: authKey)
        authState = nil
        pendingAuthState = nil
    }

    public func resumeRedirect(_ url: URL) -> Bool {
        authorizationFlow?.resumeExternalUserAgentFlow(with: url) ?? false
    }

    nonisolated public static func classify(_ error: Error?) -> DailyDriveCredentialFailure {
        if let failure = error as? DailyDriveCredentialFailure { return failure }
        guard let error else { return .missing }
        let appAuthError = error as NSError
        if appAuthError.domain == OIDGeneralErrorDomain,
           appAuthError.code == tokenRefreshErrorCode {
            return .expired
        }
        if appAuthError.domain == OIDOAuthAuthorizationErrorDomain,
           appAuthError.code == accessDeniedErrorCode {
            return .denied
        }
        return .indeterminate
    }

    nonisolated public static func resolveAccessToken(
        _ accessToken: String?,
        error: Error?
    ) throws -> String {
        if let error { throw classify(error) }
        guard let accessToken else { throw DailyDriveCredentialFailure.missing }
        return accessToken
    }

    private func attachDelegates() {
        authState?.stateChangeDelegate = self
        authState?.errorDelegate = self
    }

    private func saveAuthState() throws {
        guard let authState else { return }
        let data = try NSKeyedArchiver.archivedData(
            withRootObject: authState,
            requiringSecureCoding: true
        )
        try secureStore.save(data, account: authKey)
    }
}

extension AppAuthDriveSession: OIDAuthStateChangeDelegate, OIDAuthStateErrorDelegate {
    nonisolated public func didChange(_ state: OIDAuthState) {
        Task { @MainActor in try? self.saveAuthState() }
    }

    nonisolated public func authState(
        _ state: OIDAuthState,
        didEncounterAuthorizationError error: Error
    ) {
        Task { @MainActor in
            try? self.saveAuthState()
            self.onAuthorizationError?(Self.classify(error))
        }
    }
}
