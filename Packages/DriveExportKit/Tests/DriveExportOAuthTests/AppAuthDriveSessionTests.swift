import AppAuth
import DriveExportKit
@testable import DriveExportOAuth
import XCTest

@MainActor
final class AppAuthDriveSessionTests: XCTestCase {
    func testRestoreGarbageThrowsAndLeavesNoSession() throws {
        let store = MemorySecureStore(values: ["auth": Data("not an archive".utf8)])
        let session = AppAuthDriveSession(secureStore: store, authKey: "auth")

        XCTAssertThrowsError(try session.restoreWithoutNetwork())
        XCTAssertFalse(session.hasStoredSession)
    }

    func testClearDeletesExactlyConfiguredAuthKey() throws {
        let store = MemorySecureStore(values: [
            "auth": Data([1]),
            "destination": Data([2])
        ])
        let session = AppAuthDriveSession(secureStore: store, authKey: "auth")

        try session.clear()

        XCTAssertEqual(store.deletedAccounts, ["auth"])
        XCTAssertEqual(try store.load(account: "destination"), Data([2]))
    }

    func testStateChangeDelegateSavesSecureArchiveOnce() async throws {
        let state = makeAuthState()
        let archived = try NSKeyedArchiver.archivedData(
            withRootObject: state,
            requiringSecureCoding: true
        )
        let store = MemorySecureStore(values: ["auth": archived])
        let session = AppAuthDriveSession(secureStore: store, authKey: "auth")
        try session.restoreWithoutNetwork()
        store.saved.removeAll()

        session.didChange(state)
        await Task.yield()

        XCTAssertEqual(store.saved.map(\.account), ["auth"])
        XCTAssertNoThrow(try NSKeyedUnarchiver.unarchivedObject(
            ofClass: OIDAuthState.self,
            from: try XCTUnwrap(store.saved.first?.data)
        ))
    }

    func testCredentialClassificationUsesOnlySupportedAppAuthEvidence() throws {
        XCTAssertEqual(AppAuthDriveSession.classify(nil), .missing)
        XCTAssertEqual(
            AppAuthDriveSession.classify(NSError(domain: OIDGeneralErrorDomain, code: -11)),
            .expired
        )
        XCTAssertEqual(
            AppAuthDriveSession.classify(
                NSError(domain: OIDOAuthAuthorizationErrorDomain, code: -4)
            ),
            .denied
        )
        XCTAssertEqual(
            AppAuthDriveSession.classify(
                NSError(domain: OIDOAuthTokenErrorDomain, code: -10)
            ),
            .indeterminate
        )
        XCTAssertEqual(
            AppAuthDriveSession.classify(
                NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut)
            ),
            .indeterminate
        )
        XCTAssertEqual(AppAuthDriveSession.classify(DailyDriveCredentialFailure.revoked), .revoked)

        XCTAssertEqual(
            try AppAuthDriveSession.resolveAccessToken("token", error: nil),
            "token"
        )
        XCTAssertThrowsError(
            try AppAuthDriveSession.resolveAccessToken(
                "token",
                error: NSError(domain: OIDOAuthTokenErrorDomain, code: -10)
            )
        ) { error in
            XCTAssertEqual(error as? DailyDriveCredentialFailure, .indeterminate)
        }
    }

    private func makeAuthState() -> OIDAuthState {
        let configuration = OIDServiceConfiguration(
            authorizationEndpoint: URL(string: "https://example.invalid/auth")!,
            tokenEndpoint: URL(string: "https://example.invalid/token")!
        )
        let request = OIDAuthorizationRequest(
            configuration: configuration,
            clientId: "client",
            clientSecret: nil,
            scopes: [DailyDriveConsentPolicy.scope],
            redirectURL: URL(string: "example:/oauth2redirect")!,
            responseType: "code",
            additionalParameters: nil
        )
        let parameters: [String: any NSCopying & NSObjectProtocol] = [
            "code": "invented-code" as NSString,
            "scope": DailyDriveConsentPolicy.scope as NSString
        ]
        let response = OIDAuthorizationResponse(
            request: request,
            parameters: parameters
        )
        return OIDAuthState(authorizationResponse: response)
    }
}

private final class MemorySecureStore: DailyDriveSecurePersisting, @unchecked Sendable {
    struct Save {
        let data: Data
        let account: String
    }

    private var values: [String: Data]
    var saved: [Save] = []
    var deletedAccounts: [String] = []

    init(values: [String: Data] = [:]) {
        self.values = values
    }

    func save(_ data: Data, account: String) throws {
        saved.append(Save(data: data, account: account))
        values[account] = data
    }

    func load(account: String) throws -> Data? {
        values[account]
    }

    func delete(account: String) throws {
        deletedAccounts.append(account)
        values[account] = nil
    }
}
