import AppAuth
import Foundation
import UIKit

@MainActor
final class DriveSessionController: NSObject, ObservableObject {
    enum AuthorizationPurpose { case createFolder, chooseFolder, recoverFile }
    enum Failure: Error { case missingConfiguration, invalidConfiguration, noPresenter, noToken, noRefreshToken }

    @Published private(set) var busy = false
    @Published private(set) var exporting = false
    @Published private(set) var accountLabel = "Not connected"
    @Published private(set) var destinationLabel = "No destination"
    @Published private(set) var status = "No Google request has run."
    @Published var unrelatedSyntheticFileID = ""

    private let keychain = KeychainStore()
    private let drive = DriveAPI()
    private lazy var exportCoordinator = CanonicalExportCoordinator(
        transport: drive,
        store: KeychainCanonicalExportIdentityStore(keychain: keychain)
    )
    private var authState: OIDAuthState?
    private var authorizationFlow: OIDExternalUserAgentSession?
    private var account: DriveAccount?
    private var partitions = DestinationPartitions()

    private static let authKey = "google.oauth.appauth-state"
    private static let destinationsKey = "google.drive.destination-partitions"

    override init() {
        super.init()
        do {
            if let data = try keychain.load(account: Self.authKey) {
                authState = try NSKeyedUnarchiver.unarchivedObject(ofClass: OIDAuthState.self, from: data)
                attachDelegates()
            }
            if let data = try keychain.load(account: Self.destinationsKey) {
                partitions = try JSONDecoder().decode(DestinationPartitions.self, from: data)
            }
        } catch {
            status = "Secure local state could not be restored."
        }
    }

    func restore() async {
        guard authState != nil, !busy else { return }
        await run("Restoring secure Google session…") {
            let token = try await self.freshAccessToken()
            try self.validateCurrentGrant()
            let account = try await self.drive.account(accessToken: token)
            if let binding = self.partitions.destination(for: account.id) {
                let folder = try await self.drive.folder(
                    id: binding.folderID,
                    accessToken: token,
                    accountID: account.id
                )
                try DriveConsentPolicy.validate(folder: folder, expectedAccountID: account.id)
                try self.accept(folder: folder, origin: binding.origin, account: account)
                self.status = "Session, account and destination restored and revalidated. No Drive write ran."
            } else {
                self.accept(account: account)
                self.status = "Session and account restored. Choose or create a destination."
            }
        }
    }

    func createDestination() async {
        await run("Opening Google consent…") {
            let result = try await self.authorize(.createFolder)
            let folder: DriveFolderMetadata
            let reused: Bool
            if let existing = self.partitions.destination(for: result.account.id) {
                folder = try await self.drive.folder(
                    id: existing.folderID,
                    accessToken: result.token,
                    accountID: result.account.id
                )
                reused = true
            } else {
                folder = try await self.drive.createFolder(accessToken: result.token, accountID: result.account.id)
                reused = false
            }
            try DriveConsentPolicy.validate(folder: folder, expectedAccountID: result.account.id)
            try self.accept(folder: folder, origin: .created, account: result.account)
            self.status = reused
                ? "Revalidated the account’s existing destination; no duplicate folder or JSON was created."
                : "Created and validated the dedicated folder. No JSON file was created."
        }
    }

    func chooseDestination() async {
        await run("Opening Google consent and folder Picker…") {
            let result = try await self.authorize(.chooseFolder)
            guard let pickedID = result.pickedItemID else { throw DriveConsentPolicy.Failure.invalidPickerSelection }
            let folder = try await self.drive.folder(id: pickedID, accessToken: result.token, accountID: result.account.id)
            try DriveConsentPolicy.validate(folder: folder, expectedAccountID: result.account.id)
            try self.accept(folder: folder, origin: .picker, account: result.account)
            self.status = "Selected and validated the folder. Its unrelated contents were not enumerated."
        }
    }

    func signOut() {
        guard !busy else { return }
        do {
            try keychain.delete(account: Self.authKey)
            authState = nil
            account = nil
            accountLabel = "Not connected"
            destinationLabel = "No active destination"
            status = "Signed out locally. Google access was not revoked and exports were not deleted."
        } catch {
            status = "Local sign-out failed; secure credentials may still be present."
        }
    }

    func disconnect() async {
        guard authState != nil else {
            status = "Nothing to revoke."
            return
        }
        await run("Revoking the Google grant…") {
            guard let token = self.authState?.refreshToken ?? self.authState?.lastTokenResponse?.accessToken else {
                throw Failure.noRefreshToken
            }
            let code = try await self.drive.revoke(token: token)
            switch DisconnectTransition.afterRevocation(statusCode: code) {
            case .clearCredentialsPreserveDestinations:
                try self.keychain.delete(account: Self.authKey)
                self.authState = nil
                self.account = nil
                self.accountLabel = "Not connected"
                self.destinationLabel = "No active destination"
                self.status = "Access revoked and local credentials cleared. Drive exports were not deleted."
            case .keepCredentialsAndReportFailure:
                throw DriveAPI.Failure.httpStatus(code, nil)
            }
        }
    }

    func checkUnrelatedFileDenied() async {
        let id = unrelatedSyntheticFileID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else {
            status = "Enter the ID of an unrelated synthetic file first."
            return
        }
        await run("Checking an unrelated synthetic file…") {
            let token = try await self.freshAccessToken()
            try await self.drive.confirmUnrelatedFileDenied(id: id, accessToken: token)
            self.unrelatedSyntheticFileID = ""
            self.status = "Unrelated synthetic file access was denied. The ID was not retained."
        }
    }

    func exportSynthetic(revision: Int) async {
        guard let account,
              let destination = partitions.destination(for: account.id) else {
            status = "Connect and validate a destination before synthetic export."
            return
        }
        await run("Preparing invented revision \(revision)…") {
            self.exporting = true
            defer { self.exporting = false }
            let result = try await self.exportCoordinator.export(
                payload: SyntheticPayload.data(revision),
                generation: revision,
                reportDate: "2026-09-06",
                accountID: account.id,
                folderID: destination.folderID,
                tokenProvider: { forceRefresh in
                    try await self.freshAccessToken(forceRefresh: forceRefresh)
                }
            )
            self.status = result.userFacingLabel
        }
    }

    func cancelSyntheticExport() {
        guard exporting else { return }
        status = "Cancellation requested. If submission already began, remote reconciliation must finish."
        Task { await exportCoordinator.requestCancellation() }
    }

    func recoverSyntheticFile() async {
        await run("Opening Google consent and explicit JSON Picker…") {
            let result = try await self.authorize(.recoverFile)
            guard let selectedFileID = result.pickedItemID,
                  let destination = self.partitions.destination(for: result.account.id) else {
                throw CanonicalExportFailure.identityRecoveryAmbiguous
            }
            let recovery = try await self.exportCoordinator.recover(
                selectedFileID: selectedFileID,
                reportDate: "2026-09-06",
                accountID: result.account.id,
                folderID: destination.folderID,
                tokenProvider: { forceRefresh in
                    try await self.freshAccessToken(forceRefresh: forceRefresh)
                }
            )
            self.status = recovery.userFacingLabel
        }
    }

    private struct AuthorizationResult {
        let token: String
        let account: DriveAccount
        let pickedItemID: String?
    }

    private func authorize(_ purpose: AuthorizationPurpose) async throws -> AuthorizationResult {
        let configuration = try oauthConfiguration()
        guard let presenter = UIApplication.shared.activeRootViewController else { throw Failure.noPresenter }
        let service = OIDServiceConfiguration(
            authorizationEndpoint: URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!,
            tokenEndpoint: URL(string: "https://oauth2.googleapis.com/token")!
        )
        var parameters = [
            "access_type": "offline",
            "prompt": "consent select_account",
            "include_granted_scopes": "false"
        ]
        if purpose == .chooseFolder || purpose == .recoverFile {
            parameters["trigger_onepick"] = "true"
            parameters["allow_multiple"] = "false"
            if purpose == .chooseFolder {
                parameters["allow_folder_selection"] = "true"
                parameters["mimetypes"] = DriveConsentPolicy.folderMIMEType
            } else {
                parameters["allow_folder_selection"] = "false"
                parameters["mimetypes"] = "application/json"
            }
        }
        let request = OIDAuthorizationRequest(
            configuration: service,
            clientId: configuration.clientID,
            clientSecret: nil,
            scopes: [DriveConsentPolicy.scope],
            redirectURL: configuration.redirectURL,
            responseType: OIDResponseTypeCode,
            additionalParameters: parameters
        )
        let newState: OIDAuthState = try await withCheckedThrowingContinuation { continuation in
            authorizationFlow = OIDAuthState.authState(byPresenting: request, presenting: presenter) { state, error in
                self.authorizationFlow = nil
                if let state { continuation.resume(returning: state) }
                else { continuation.resume(throwing: error ?? Failure.noToken) }
            }
        }
        try DriveConsentPolicy.validateGrantedScopes(newState.scope)
        let pickedID: String?
        if purpose == .chooseFolder || purpose == .recoverFile {
            pickedID = try DriveConsentPolicy.selectedFolderID(
                from: newState.lastAuthorizationResponse.additionalParameters?["picked_file_ids"]
            )
        } else {
            pickedID = nil
        }
        guard let token = newState.lastTokenResponse?.accessToken else { throw Failure.noToken }
        let account = try await drive.account(accessToken: token)
        authState = newState
        attachDelegates()
        try saveAuthState()
        return AuthorizationResult(token: token, account: account, pickedItemID: pickedID)
    }

    private func oauthConfiguration() throws -> (clientID: String, redirectURL: URL) {
        guard let clientID = Bundle.main.object(forInfoDictionaryKey: "GoogleOAuthClientID") as? String,
              let scheme = Bundle.main.object(forInfoDictionaryKey: "GoogleOAuthRedirectScheme") as? String,
              clientID != "MISSING", scheme != "MISSING" else { throw Failure.missingConfiguration }
        let suffix = ".apps.googleusercontent.com"
        guard clientID.hasSuffix(suffix) else { throw Failure.invalidConfiguration }
        let stem = String(clientID.dropLast(suffix.count))
        guard scheme == "com.googleusercontent.apps.\(stem)",
              let redirectURL = URL(string: "\(scheme):/oauth2redirect") else {
            throw Failure.invalidConfiguration
        }
        return (clientID, redirectURL)
    }

    private func freshAccessToken(forceRefresh: Bool = false) async throws -> String {
        guard let authState else { throw Failure.noToken }
        if forceRefresh { authState.setNeedsTokenRefresh() }
        return try await withCheckedThrowingContinuation { continuation in
            authState.performAction { accessToken, _, error in
                if let accessToken { continuation.resume(returning: accessToken) }
                else { continuation.resume(throwing: error ?? Failure.noToken) }
            }
        }
    }

    private func validateCurrentGrant() throws {
        guard let authState else { throw Failure.noToken }
        try DriveConsentPolicy.validateGrantedScopes(authState.scope)
    }

    private func accept(folder: DriveFolderMetadata, origin: DestinationBinding.Origin, account: DriveAccount) throws {
        let binding = DestinationBinding(
            accountID: account.id,
            folderID: folder.id,
            folderName: folder.name,
            origin: origin
        )
        partitions.bind(binding)
        let data = try JSONEncoder().encode(partitions)
        try keychain.save(data, account: Self.destinationsKey)
        accept(account: account)
    }

    private func accept(account: DriveAccount) {
        self.account = account
        accountLabel = "\(account.displayName) — \(account.emailAddress)"
        destinationLabel = partitions.destination(for: account.id)?.folderName ?? "Choose or create a destination"
    }

    private func attachDelegates() {
        authState?.stateChangeDelegate = self
        authState?.errorDelegate = self
    }

    private func saveAuthState() throws {
        guard let authState else { return }
        let data = try NSKeyedArchiver.archivedData(withRootObject: authState, requiringSecureCoding: true)
        try keychain.save(data, account: Self.authKey)
    }

    private func run(_ startingStatus: String, operation: () async throws -> Void) async {
        guard !busy else { return }
        busy = true
        status = startingStatus
        defer { busy = false }
        do {
            try await operation()
        } catch let failure as DriveConsentPolicy.Failure {
            status = "Rejected by consent/destination policy: \(failure.userFacingLabel)."
        } catch let failure as CanonicalExportFailure {
            status = failure.userFacingLabel
        } catch let error as NSError where error.domain == OIDGeneralErrorDomain && error.code == -3 {
            // OIDErrorCodeUserCanceledAuthorizationFlow. Do not replace the prior Keychain state.
            status = "Consent or Picker was cancelled. Existing credentials and destination were preserved."
        } catch {
            status = "Operation cancelled or failed. No export file was written."
        }
    }
}

extension DriveSessionController: OIDAuthStateChangeDelegate, OIDAuthStateErrorDelegate {
    nonisolated func didChange(_ state: OIDAuthState) {
        Task { @MainActor in try? self.saveAuthState() }
    }

    nonisolated func authState(_ state: OIDAuthState, didEncounterAuthorizationError error: Error) {
        Task { @MainActor in
            try? self.saveAuthState()
            self.status = "The Google grant is expired, denied or revoked. Reconnect before continuing."
        }
    }
}

private extension DriveConsentPolicy.Failure {
    var userFacingLabel: String {
        switch self {
        case .missingDriveFileScope: return "drive.file was not granted"
        case .unexpectedScope: return "an unexpected broader or identity scope was returned"
        case .invalidPickerSelection: return "Picker did not return exactly one folder"
        case .accountMismatch: return "account mismatch"
        case .notAppAuthorized: return "folder was not explicitly authorised for this app"
        case .notFolder: return "selection is not a folder"
        case .trashed: return "folder is trashed"
        case .sharedDriveUnsupported: return "Shared Drives are outside this slice"
        case .notWritable: return "folder cannot accept children"
        }
    }
}

private extension CanonicalExportResult {
    var userFacingLabel: String {
        switch self {
        case .verified(let generation, _):
            return "Upload verified remotely byte-for-byte for invented revision \(generation)."
        case .unchangedVerified(let generation):
            return "Unchanged invented revision \(generation) was reverified remotely; no write ran."
        case .cancelledBeforeSubmission:
            return "Cancelled before file submission. Remote file state was preserved."
        case .cancelledAfterSubmissionVerified(let generation, _):
            return "Cancellation arrived after submission; reconciliation verified invented revision \(generation)."
        }
    }
}

private extension CanonicalRecoveryResult {
    var userFacingLabel: String {
        switch self {
        case .recovered(let generation):
            return "Explicit file recovery verified and restored invented revision \(generation)."
        case .alreadyTracked(let generation):
            return "The selected file was already tracked and revision \(generation) was reverified."
        }
    }
}

private extension CanonicalExportFailure {
    var userFacingLabel: String {
        switch self {
        case .busy: return "Another export or reconciliation is still active."
        case .invalidSyntheticPayload: return "Rejected: only the fixed morning, evening and bedtime fixtures are allowed."
        case .staleGeneration: return "Rejected stale synthetic completion; the last verified file is unchanged."
        case .destinationChangeRequiresMigration: return "Export blocked: account or destination changed and no migration policy is authorised."
        case .accountMismatch: return "Export blocked by Google account mismatch."
        case .identityRecoveryAmbiguous: return "Export blocked: canonical destination identity recovery is ambiguous."
        case .staleCompletion: return "A stale completion was rejected; the last verified identity was preserved."
        case .credentials(let reason): return "Google credentials are \(reason.rawValue). Reconnect before exporting."
        case .credentialsRejected: return "Google credentials were expired, denied or revoked. Reconnect before exporting."
        case .permissionDenied: return "Google denied the file operation. No broader scope will be requested."
        case .quotaExceeded: return "Google Drive quota is exhausted. No retry was queued."
        case .rateLimited: return "Google Drive rate-limited the request. No background retry was queued."
        case .remoteMissing: return "The stored Drive file ID is missing or inaccessible; no replacement was created."
        case .remoteMoved: return "The stored Drive file moved outside the validated destination; export is blocked."
        case .remoteTrashed: return "The stored Drive file is trashed; export is blocked."
        case .remoteMetadataMismatch: return "Remote file metadata did not match the canonical identity. Upload is unverified."
        case .remoteContentMismatch: return "Remote bytes did not match the submitted fixture. Upload is unverified."
        case .unresolvedRequest: return "The submitted request remains unresolved. Newer writes are blocked; no retry is queued."
        case .persistenceFailure: return "Secure export identity state could not be persisted. No new file will be created."
        case .transportFailure: return "The Drive request failed. Upload is unverified and no background retry was queued."
        }
    }
}

private extension UIApplication {
    var activeRootViewController: UIViewController? {
        connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }?
            .windows.first { $0.isKeyWindow }?
            .rootViewController
    }
}
