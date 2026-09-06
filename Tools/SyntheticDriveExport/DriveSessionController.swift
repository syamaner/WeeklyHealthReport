import AppAuth
import Foundation
import UIKit

@MainActor
final class DriveSessionController: NSObject, ObservableObject {
    enum AuthorizationPurpose { case createFolder, chooseFolder, recoverFile }
    enum Failure: Error { case missingConfiguration, invalidConfiguration, noPresenter, noToken, noRefreshToken }

    enum FixtureSet: String, CaseIterable, Identifiable {
        case accepted = "Accepted 6 Sep"
        case adverse = "Adverse 7 Sep"

        var id: String { rawValue }
        var reportDate: String {
            switch self {
            case .accepted: return SyntheticPayload.acceptedReportDate
            case .adverse: return SyntheticPayload.adverseReportDate
            }
        }
    }

    @Published private(set) var busy = false
    @Published private(set) var exporting = false
    @Published private(set) var accountLabel = "Not connected"
    @Published private(set) var destinationLabel = "No destination"
    @Published private(set) var status = "No Google request has run."
    @Published var unrelatedSyntheticFileID = ""
    @Published var fixtureSet = FixtureSet.accepted

    private let keychain = KeychainStore()
    private let drive = DriveAPI()
    private lazy var probeDrive = AdverseProbeDriveTransport(base: drive)
    private lazy var identityStore = KeychainCanonicalExportIdentityStore(keychain: keychain)
    private lazy var exportCoordinator = CanonicalExportCoordinator(
        transport: probeDrive,
        store: identityStore
    )
    private var authState: OIDAuthState?
    private var authorizationFlow: OIDExternalUserAgentSession?
    private var account: DriveAccount?
    private var partitions = DestinationPartitions()
    private var launchProbeRan = false

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
        await performSyntheticExport(revision: revision)
    }

    func retryAdverseCreateWithReservedID() async {
        guard fixtureSet == .adverse else {
            status = "Select the Adverse 7 Sep fixture set before running an adverse probe."
            return
        }
        await performSyntheticExport(revision: 1, probeMode: .retryNextCreateAfterLostResponse)
    }

    func runLaunchProbeIfRequested() async {
#if DEBUG
        guard !launchProbeRan else { return }
        let supportedArguments = [
            "--whr-adverse-retry-create",
            "--whr-adverse-cancel-before-submission",
            "--whr-adverse-leave-unresolved",
            "--whr-adverse-retry-lost-response",
            "--whr-adverse-cancel-after-submission",
            "--whr-adverse-force-refresh",
            "--whr-adverse-reverify",
            "--whr-adverse-recover"
        ]
        let requestedArguments = ProcessInfo.processInfo.arguments.filter {
            supportedArguments.contains($0)
        }
        guard !requestedArguments.isEmpty else { return }
        launchProbeRan = true
        guard requestedArguments.count == 1 else {
            status = "Rejected ambiguous adverse launch request. No Google request ran."
            return
        }
        fixtureSet = .adverse
        switch requestedArguments[0] {
        case "--whr-adverse-retry-create":
            await retryAdverseCreateWithReservedID()
        case "--whr-adverse-cancel-before-submission":
            await cancelAdverseEveningBeforeSubmission()
        case "--whr-adverse-leave-unresolved":
            await leaveAdverseEveningUnresolved()
        case "--whr-adverse-retry-lost-response":
            await reconcileAdverseEveningAfterLostResponse()
        case "--whr-adverse-cancel-after-submission":
            await cancelAdverseBedtimeAfterSubmission()
        case "--whr-adverse-force-refresh":
            await forceRefreshAndReverifyBedtime()
        case "--whr-adverse-reverify":
            await exportSynthetic(revision: 3)
        case "--whr-adverse-recover":
            await recoverSyntheticFile()
        default:
            status = "Rejected unsupported adverse launch request. No Google request ran."
        }
#endif
    }

    func runLocalOnlyLaunchProbeIfRequested() async -> Bool {
#if DEBUG
        guard !launchProbeRan else { return false }
        let credentialRequests: [(String, SyntheticCredentialFailure)] = [
            ("--whr-adverse-credential-expired", .expired),
            ("--whr-adverse-credential-denied", .denied),
            ("--whr-adverse-credential-revoked", .revoked)
        ].filter { ProcessInfo.processInfo.arguments.contains($0.0) }
        let identityLossRequested = ProcessInfo.processInfo.arguments.contains(
            "--whr-adverse-lose-identity-and-prove-fail-closed"
        )
        let normalRequestArguments = [
            "--whr-adverse-retry-create",
            "--whr-adverse-cancel-before-submission",
            "--whr-adverse-leave-unresolved",
            "--whr-adverse-retry-lost-response",
            "--whr-adverse-cancel-after-submission",
            "--whr-adverse-force-refresh",
            "--whr-adverse-reverify",
            "--whr-adverse-recover"
        ].filter { ProcessInfo.processInfo.arguments.contains($0) }
        let localRequestCount = credentialRequests.count + (identityLossRequested ? 1 : 0)
        guard localRequestCount > 0 else { return false }
        launchProbeRan = true
        guard localRequestCount + normalRequestArguments.count == 1 else {
            status = "Rejected ambiguous local adverse probe. No Google request ran."
            return true
        }
        fixtureSet = .adverse
        if identityLossRequested {
            await performIdentityLossFailClosedProbe()
        } else if let request = credentialRequests.first {
            await performPersistedCredentialFailure(request.1)
        }
        return true
#else
        return false
#endif
    }

    func cancelAdverseEveningBeforeSubmission() async {
        guard fixtureSet == .adverse else {
            status = "Select the Adverse 7 Sep fixture set before running an adverse probe."
            return
        }
        await performSyntheticExport(revision: 2, probeMode: .cancelBeforeSubmission)
    }

    func leaveAdverseEveningUnresolved() async {
        guard fixtureSet == .adverse else {
            status = "Select the Adverse 7 Sep fixture set before running an adverse probe."
            return
        }
        await performSyntheticExport(revision: 2, probeMode: .loseNextTwoSubmissionsBeforeCommit)
    }

    func reconcileAdverseEveningAfterLostResponse() async {
        guard fixtureSet == .adverse else {
            status = "Select the Adverse 7 Sep fixture set before running an adverse probe."
            return
        }
        await performSyntheticExport(revision: 2, probeMode: .loseNextResponseAfterCommit)
    }

    func cancelAdverseBedtimeAfterSubmission() async {
        guard fixtureSet == .adverse else {
            status = "Select the Adverse 7 Sep fixture set before running an adverse probe."
            return
        }
        await performSyntheticExport(revision: 3, probeMode: .cancelAfterSubmission)
    }

    func forceRefreshAndReverifyBedtime() async {
        await performSyntheticExport(revision: 3, forceInitialTokenRefresh: true)
    }

    func simulateCredentialFailure(_ failure: SyntheticCredentialFailure) async {
        await performSyntheticExport(revision: 3, credentialFailure: failure)
    }

    private func performPersistedCredentialFailure(_ failure: SyntheticCredentialFailure) async {
        await run("Injecting local \(failure.rawValue) credential failure…") {
            guard let registry = try self.identityStore.load(),
                  let identity = registry.identities.first(where: {
                      $0.reportDate == SyntheticPayload.adverseReportDate
                  }) else {
                throw CanonicalExportFailure.identityRecoveryAmbiguous
            }
            _ = try await self.exportCoordinator.export(
                payload: SyntheticPayload.data(3, reportDate: SyntheticPayload.adverseReportDate),
                generation: 3,
                reportDate: SyntheticPayload.adverseReportDate,
                accountID: identity.accountID,
                folderID: identity.folderID,
                tokenProvider: { _ in throw failure }
            )
        }
    }

    private func performIdentityLossFailClosedProbe() async {
        await run("Removing canonical identity and proving fail-closed recovery…") {
            guard let registry = try self.identityStore.load(),
                  let identity = registry.identities.first(where: {
                      $0.reportDate == SyntheticPayload.adverseReportDate
                  }) else {
                throw CanonicalExportFailure.identityRecoveryAmbiguous
            }
            try self.identityStore.removeRegistryPreservingInstallationMarkerForProbe()
            do {
                _ = try await self.exportCoordinator.export(
                    payload: SyntheticPayload.data(3, reportDate: SyntheticPayload.adverseReportDate),
                    generation: 3,
                    reportDate: SyntheticPayload.adverseReportDate,
                    accountID: identity.accountID,
                    folderID: identity.folderID,
                    tokenProvider: { _ in throw Failure.noToken }
                )
                throw CanonicalExportFailure.staleCompletion
            } catch CanonicalExportFailure.identityRecoveryAmbiguous {
                self.status = "Export blocked: canonical identity recovery is ambiguous. Probe removed the registry, preserved the installation marker and failed closed before token acquisition."
            }
        }
    }

    func simulateMissingCanonicalIdentity() {
        guard !busy else { return }
        do {
            try identityStore.removeRegistryPreservingInstallationMarkerForProbe()
            status = "Simulated missing canonical identity while preserving the installation marker. Export must now fail closed until explicit recovery."
        } catch {
            status = "Could not simulate missing identity; secure state was left unchanged."
        }
    }

    private func performSyntheticExport(
        revision: Int,
        probeMode: AdverseProbeDriveTransport.Mode? = nil,
        forceInitialTokenRefresh: Bool = false,
        credentialFailure: SyntheticCredentialFailure? = nil
    ) async {
        guard let account,
              let destination = partitions.destination(for: account.id) else {
            status = "Connect and validate a destination before synthetic export."
            return
        }
        await run("Preparing invented revision \(revision)…") {
            self.exporting = true
            defer { self.exporting = false }
            if let probeMode {
                let coordinator = self.exportCoordinator
                try await self.probeDrive.arm(
                    probeMode,
                    cancellationHandler: {
                        await coordinator.requestCancellation()
                    }
                )
            }
            do {
                let reportDate = self.fixtureSet.reportDate
                let result = try await self.exportCoordinator.export(
                    payload: SyntheticPayload.data(revision, reportDate: reportDate),
                    generation: revision,
                    reportDate: reportDate,
                    accountID: account.id,
                    folderID: destination.folderID,
                    tokenProvider: { forceRefresh in
                        if let credentialFailure { throw credentialFailure }
                        return try await self.freshAccessToken(
                            forceRefresh: forceRefresh || forceInitialTokenRefresh
                        )
                    }
                )
                let observation = await self.probeDrive.takeObservation()
                await self.probeDrive.clear()
                self.status = [result.userFacingLabel, observation?.userFacingLabel]
                    .compactMap { $0 }
                    .joined(separator: " ")
            } catch {
                let observation = await self.probeDrive.takeObservation()
                await self.probeDrive.clear()
                if let failure = error as? CanonicalExportFailure {
                    self.status = [failure.userFacingLabel, observation?.userFacingLabel]
                        .compactMap { $0 }
                        .joined(separator: " ")
                    return
                }
                throw error
            }
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
                reportDate: self.fixtureSet.reportDate,
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
