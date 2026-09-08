import AppAuth
import Foundation
import UIKit

@MainActor
final class DailyDriveSessionController: NSObject, ObservableObject {
    enum AuthorizationPurpose { case connect, chooseFolder, recoverFile }
    enum FileReplacementReason { case trashed, missingOrInaccessible }
    enum Failure: Error {
        case missingConfiguration
        case invalidConfiguration
        case noPresenter
        case noToken
        case noRefreshToken
        case noAccount
        case noDestination
        case noPreview
    }

    @Published private(set) var busy = false
    @Published private(set) var exporting = false
    @Published private(set) var accountLabel = "Not connected"
    @Published private(set) var destinationLabel = "No destination"
    @Published private(set) var status = "No Health or Google request has run."
    @Published private(set) var preview: DailyHealthExportResult?
    @Published private(set) var lastVerifiedLabel = "No verified Drive upload in this session"
    @Published private(set) var canForgetTrashedDestination = false
    @Published private(set) var fileReplacementReason: FileReplacementReason?
    @Published private(set) var nutritionSources: [NutritionSource] = []
    @Published private(set) var selectedNutritionSourceBundleIdentifier: String?

    let notes: DailyNotesController

    var isConfigured: Bool { (try? oauthConfiguration()) != nil }
    var canExport: Bool {
        previewIsCurrent && account != nil && activeDestination != nil && !busy
    }
    var previewText: String? {
        preview.flatMap { String(data: $0.bytes, encoding: .utf8) }
    }
    var nutritionSourceLabel: String {
        guard let selectedNutritionSourceBundleIdentifier else {
            return "No source selected"
        }
        guard let source = nutritionSources.first(where: {
            $0.bundleIdentifier == selectedNutritionSourceBundleIdentifier
        }) else {
            return "Saved source unavailable — \(selectedNutritionSourceBundleIdentifier)"
        }
        return "\(source.name) — \(source.bundleIdentifier)"
    }
    var canRefreshPreview: Bool {
        !busy && notes.storageAvailable && nutritionSources.contains {
            $0.bundleIdentifier == selectedNutritionSourceBundleIdentifier
        }
    }

    private let keychain: DailyDriveKeychainStore
    private let drive: DailyDriveAPI
    private let exportService: DailyHealthExportService
    private let identityStore: KeychainDailyDriveExportIdentityStore
    private let exportCoordinator: DailyDriveExportCoordinator
    private let nutritionSourceSelection: any NutritionSourceSelectionPersisting
    private var authState: OIDAuthState?
    private var authorizationFlow: OIDExternalUserAgentSession?
    private var account: DailyDriveAccount?
    private var partitions = DailyDestinationPartitions()
    private var trashedDestinationCandidate: DailyDestinationBinding?
    private var fileReplacementCandidate: FileReplacementCandidate?

    private static let authKey = "google.oauth.daily-export.appauth-state.v1"
    private static let destinationsKey = "google.drive.daily-export-destinations.v1"

    private struct FileReplacementCandidate: Equatable {
        let accountID: String
        let folderID: String
        let reportDate: String
    }

    private var activeDestination: DailyDestinationBinding? {
        guard let account else { return nil }
        return partitions.destination(for: account.id)
    }

    override convenience init() {
        let keychain = DailyDriveKeychainStore()
        let notesStore = FileDailyNotesStore()
        let notes = DailyNotesController(store: notesStore)
        self.init(
            keychain: keychain,
            drive: DailyDriveAPI(),
            exportService: DailyHealthExportService(
                healthData: HealthKitClient(),
                notesStore: notesStore
            ),
            identityStore: KeychainDailyDriveExportIdentityStore(keychain: keychain),
            nutritionSourceSelection: UserDefaultsNutritionSourceSelectionStore(),
            notes: notes
        )
    }

    init(
        keychain: DailyDriveKeychainStore,
        drive: DailyDriveAPI,
        exportService: DailyHealthExportService,
        identityStore: KeychainDailyDriveExportIdentityStore,
        nutritionSourceSelection: any NutritionSourceSelectionPersisting,
        notes: DailyNotesController
    ) {
        self.keychain = keychain
        self.drive = drive
        self.exportService = exportService
        self.identityStore = identityStore
        self.nutritionSourceSelection = nutritionSourceSelection
        self.notes = notes
        exportCoordinator = DailyDriveExportCoordinator(
            transport: drive,
            store: identityStore
        )
        super.init()
        notes.onSavedNotesMutation = { [weak self] snapshot in
            self?.invalidatePreview(after: snapshot)
        }
        selectedNutritionSourceBundleIdentifier = nutritionSourceSelection.loadBundleIdentifier()
        restoreLocalStateWithoutNetwork()
        if !isConfigured {
            status = "Drive export is disabled until this app has its own local OAuth client configuration."
        }
    }

    func connect() async {
        await run("Opening Google consent…") {
            let result = try await self.authorize(.connect)
            self.accept(account: result.account)
            self.status = "Connected with drive.file only. Choose or create a destination; no export ran."
        }
    }

    func restore() async {
        guard authState != nil else {
            status = "No secure Google session is stored on this installation."
            return
        }
        await run("Revalidating the stored Google session…") {
            let token = try await self.freshAccessToken()
            try self.validateCurrentGrant()
            let account = try await self.drive.account(accessToken: token)
            if let binding = self.partitions.destination(for: account.id) {
                let folder = try await self.drive.folder(
                    id: binding.folderID,
                    accessToken: token,
                    accountID: account.id
                )
                try self.validateStoredDestination(
                    folder,
                    binding: binding,
                    accountID: account.id
                )
                try self.accept(folder: folder, origin: binding.origin, account: account)
                self.status = "Session, account and destination revalidated. No export ran."
            } else {
                self.accept(account: account)
                self.status = "Session and account revalidated. Choose or create a destination."
            }
        }
    }

    func createDestination() async {
        await run("Creating the dedicated Drive destination…") {
            let context = try await self.currentContext()
            if let existing = self.partitions.destination(for: context.account.id) {
                let folder = try await self.drive.folder(
                    id: existing.folderID,
                    accessToken: context.token,
                    accountID: context.account.id
                )
                try self.validateStoredDestination(
                    folder,
                    binding: existing,
                    accountID: context.account.id
                )
                try self.accept(folder: folder, origin: existing.origin, account: context.account)
                self.status = "Revalidated the existing destination. No duplicate folder or export was created."
                return
            }
            let folder = try await self.drive.createFolder(
                accessToken: context.token,
                accountID: context.account.id
            )
            try DailyDriveConsentPolicy.validate(folder: folder, expectedAccountID: context.account.id)
            try self.accept(folder: folder, origin: .created, account: context.account)
            self.status = "Created and validated the destination. No health JSON was exported."
        }
    }

    func forgetTrashedDestination() async {
        await run("Forgetting the confirmed trashed destination…") {
            let context = try await self.currentContext()
            guard let candidate = self.trashedDestinationCandidate,
                  candidate.accountID == context.account.id,
                  self.activeDestination == candidate else {
                throw Failure.noDestination
            }

            try await self.exportCoordinator.abandonDestination(
                accountID: candidate.accountID,
                folderID: candidate.folderID
            )
            var updatedPartitions = self.partitions
            guard updatedPartitions.unbind(
                accountID: candidate.accountID,
                folderID: candidate.folderID
            ) else {
                throw Failure.noDestination
            }
            try self.keychain.save(
                try JSONEncoder().encode(updatedPartitions),
                account: Self.destinationsKey
            )
            self.partitions = updatedPartitions
            self.clearTrashedDestinationCandidate()
            self.clearFileReplacementCandidate()
            self.accept(account: context.account)
            self.status = "Forgot the trashed destination and its local file identities. You can now create or choose a fresh folder; no Drive item was changed."
        }
    }

    func chooseDestination() async {
        await run("Opening explicit folder selection…") {
            let result = try await self.authorize(.chooseFolder)
            guard let pickedID = result.pickedItemID else {
                throw DailyDriveConsentPolicy.Failure.invalidPickerSelection
            }
            let folder = try await self.drive.folder(
                id: pickedID,
                accessToken: result.token,
                accountID: result.account.id
            )
            try DailyDriveConsentPolicy.validate(folder: folder, expectedAccountID: result.account.id)
            try self.accept(folder: folder, origin: .picker, account: result.account)
            self.status = "Selected and validated the folder. Its contents were not enumerated."
        }
    }

    func refreshPreview() async {
        await run("Reading a fresh on-device daily snapshot…") {
            let result = try await self.exportService.refresh(
                nutritionSourceBundleIdentifier: self.selectedNutritionSourceBundleIdentifier
            )
            if self.fileReplacementCandidate?.reportDate != result.envelope.reportDate {
                self.clearFileReplacementCandidate()
            }
            self.preview = result
            self.status = "Fresh preview created in memory. Review it before choosing Export."
        }
    }

    func refreshNutritionSources() async {
        await run("Requesting nutrition read access and discovering visible sources…") {
            let sources = try await self.exportService.discoverNutritionSources()
            self.nutritionSources = sources
            guard let selected = self.selectedNutritionSourceBundleIdentifier else {
                self.status = sources.isEmpty
                    ? "No visible nutrition source was found. No preview or Drive request was created."
                    : "Choose a visible nutrition source. No preview or Drive request was created."
                return
            }
            guard sources.contains(where: { $0.bundleIdentifier == selected }) else {
                self.preview = nil
                self.status = "The saved nutrition source is not visible. Choose an available source; no unfiltered nutrition was used."
                return
            }
            self.status = "Nutrition source resolved by bundle identifier. Refresh the preview when ready."
        }
    }

    func selectNutritionSource(bundleIdentifier: String) {
        guard !busy,
              let source = nutritionSources.first(where: {
                $0.bundleIdentifier == bundleIdentifier
              }) else { return }
        selectedNutritionSourceBundleIdentifier = source.bundleIdentifier
        nutritionSourceSelection.saveBundleIdentifier(source.bundleIdentifier)
        preview = nil
        status = "Selected \(source.name) by bundle identifier. Refresh to create a new reviewed preview."
    }

    func exportPreview() async {
        guard let preview, previewIsCurrent,
              let account, let destination = activeDestination else {
            status = "Refresh a preview and validate an account and destination before export."
            return
        }
        await run("Submitting the reviewed preview and verifying Drive…") {
            self.exporting = true
            defer { self.exporting = false }
            let result: DailyDriveExportResult
            do {
                result = try await self.exportCoordinator.export(
                    payload: preview.bytes,
                    reportDate: preview.envelope.reportDate,
                    accountID: account.id,
                    folderID: destination.folderID,
                    tokenProvider: { forceRefresh in
                        try await self.freshAccessToken(forceRefresh: forceRefresh)
                    }
                )
            } catch DailyDriveExportFailure.remoteTrashed {
                self.markFileForReplacement(
                    accountID: account.id,
                    folderID: destination.folderID,
                    reportDate: preview.envelope.reportDate,
                    reason: .trashed
                )
                throw DailyDriveExportFailure.remoteTrashed
            } catch DailyDriveExportFailure.remoteMissing {
                self.markFileForReplacement(
                    accountID: account.id,
                    folderID: destination.folderID,
                    reportDate: preview.envelope.reportDate,
                    reason: .missingOrInaccessible
                )
                throw DailyDriveExportFailure.remoteMissing
            }
            self.clearFileReplacementCandidate(
                accountID: account.id,
                folderID: destination.folderID,
                reportDate: preview.envelope.reportDate
            )
            self.lastVerifiedLabel = result.verifiedLabel
            self.status = result.userFacingLabel
            if result.authorizesNoteCleanup,
               !self.notes.markVerified(
                   snapshot: preview.notesSnapshot,
                   payload: preview.bytes
               ) {
                self.status += " Current notes were retained because their verified cleanup marker was not saved."
            }
        }
    }

    func confirmFileReplacementOverride() async {
        await run("Forgetting the unavailable file identity…") {
            let context = try await self.currentContext()
            guard let candidate = self.fileReplacementCandidate,
                  let reason = self.fileReplacementReason,
                  candidate.accountID == context.account.id,
                  self.activeDestination?.folderID == candidate.folderID else {
                throw Failure.noDestination
            }

            try await self.exportCoordinator.abandonFileIdentity(
                accountID: candidate.accountID,
                folderID: candidate.folderID,
                reportDate: candidate.reportDate
            )
            self.clearFileReplacementCandidate()
            self.restoreLastVerifiedLabel(for: context.account.id)
            switch reason {
            case .trashed:
                self.status = "Forgot the trashed daily file identity. Export the matching date again to create a fresh canonical file; no Drive item was changed."
            case .missingOrInaccessible:
                self.status = "Explicit override accepted for the missing or inaccessible daily file. Export the matching date again to create a new canonical file ID; no Drive item was changed."
            }
        }
    }

    func cancelExport() {
        guard exporting else { return }
        status = "Cancellation requested. If submission began, verification must finish before the result is known."
        Task { await exportCoordinator.requestCancellation() }
    }

    func recoverSelectedFile() async {
        guard let preview, let destination = activeDestination else {
            status = "Refresh the matching report date and validate a destination before recovery."
            return
        }
        await run("Opening explicit canonical-file recovery…") {
            let result = try await self.authorize(.recoverFile)
            guard result.account.id == destination.accountID,
                  let selectedFileID = result.pickedItemID else {
                throw DailyDriveExportFailure.identityRecoveryAmbiguous
            }
            let recovery = try await self.exportCoordinator.recover(
                selectedFileID: selectedFileID,
                reportDate: preview.envelope.reportDate,
                accountID: result.account.id,
                folderID: destination.folderID,
                tokenProvider: { forceRefresh in
                    try await self.freshAccessToken(forceRefresh: forceRefresh)
                }
            )
            self.clearFileReplacementCandidate(
                accountID: result.account.id,
                folderID: destination.folderID,
                reportDate: preview.envelope.reportDate
            )
            self.lastVerifiedLabel = recovery.verifiedLabel
            self.status = recovery.userFacingLabel
        }
    }

    func signOut() {
        guard !busy else { return }
        do {
            try keychain.delete(account: Self.authKey)
            authState = nil
            account = nil
            clearTrashedDestinationCandidate()
            clearFileReplacementCandidate()
            accountLabel = "Not connected"
            destinationLabel = "No active destination"
            status = "Signed out locally. Drive access was not revoked and exports were not deleted."
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
            guard let token = self.authState?.refreshToken
                ?? self.authState?.lastTokenResponse?.accessToken else {
                throw Failure.noRefreshToken
            }
            let code = try await self.drive.revoke(token: token)
            switch DailyDisconnectTransition.afterRevocation(statusCode: code) {
            case .clearCredentialsPreserveDestinations:
                try self.keychain.delete(account: Self.authKey)
                self.authState = nil
                self.account = nil
                self.clearTrashedDestinationCandidate()
                self.clearFileReplacementCandidate()
                self.accountLabel = "Not connected"
                self.destinationLabel = "No active destination"
                self.status = "Access revoked and local credentials cleared. Drive files were not deleted."
            case .keepCredentialsAndReportFailure:
                throw DailyDriveAPI.Failure.httpStatus(code, nil)
            }
        }
    }

    func resumeOAuthRedirect(_ url: URL) {
        _ = authorizationFlow?.resumeExternalUserAgentFlow(with: url)
    }

    private struct AuthorizationResult {
        let token: String
        let account: DailyDriveAccount
        let pickedItemID: String?
    }

    private func authorize(_ purpose: AuthorizationPurpose) async throws -> AuthorizationResult {
        let configuration = try oauthConfiguration()
        guard let presenter = UIApplication.shared.activeRootViewController else {
            throw Failure.noPresenter
        }
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
            parameters["allow_folder_selection"] = purpose == .chooseFolder ? "true" : "false"
            parameters["mimetypes"] = purpose == .chooseFolder
                ? DailyDriveConsentPolicy.folderMIMEType
                : "application/json"
        }
        let request = OIDAuthorizationRequest(
            configuration: service,
            clientId: configuration.clientID,
            clientSecret: nil,
            scopes: [DailyDriveConsentPolicy.scope],
            redirectURL: configuration.redirectURL,
            responseType: OIDResponseTypeCode,
            additionalParameters: parameters
        )
        let newState: OIDAuthState = try await withCheckedThrowingContinuation { continuation in
            authorizationFlow = OIDAuthState.authState(
                byPresenting: request,
                presenting: presenter
            ) { state, error in
                self.authorizationFlow = nil
                if let state { continuation.resume(returning: state) }
                else { continuation.resume(throwing: error ?? Failure.noToken) }
            }
        }
        try DailyDriveConsentPolicy.validateGrantedScopes(newState.scope)
        let pickedID: String?
        if purpose == .chooseFolder || purpose == .recoverFile {
            pickedID = try DailyDriveConsentPolicy.selectedItemID(
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

    private func currentContext() async throws -> (token: String, account: DailyDriveAccount) {
        guard let expected = account else { throw Failure.noAccount }
        let token = try await freshAccessToken()
        try validateCurrentGrant()
        let current = try await drive.account(accessToken: token)
        guard current.id == expected.id else { throw DailyDriveExportFailure.accountMismatch }
        return (token, current)
    }

    private func oauthConfiguration() throws -> (clientID: String, redirectURL: URL) {
        guard let clientID = Bundle.main.object(forInfoDictionaryKey: "GoogleOAuthClientID") as? String,
              let scheme = Bundle.main.object(forInfoDictionaryKey: "GoogleOAuthRedirectScheme") as? String,
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
        try DailyDriveConsentPolicy.validateGrantedScopes(authState.scope)
    }

    private func accept(
        folder: DailyDriveFolder,
        origin: DailyDestinationBinding.Origin,
        account: DailyDriveAccount
    ) throws {
        clearTrashedDestinationCandidate()
        if fileReplacementCandidate?.accountID != account.id
            || fileReplacementCandidate?.folderID != folder.id {
            clearFileReplacementCandidate()
        }
        partitions.bind(DailyDestinationBinding(
            accountID: account.id,
            folderID: folder.id,
            folderName: folder.name,
            origin: origin
        ))
        try keychain.save(try JSONEncoder().encode(partitions), account: Self.destinationsKey)
        accept(account: account)
    }

    private func accept(account: DailyDriveAccount) {
        if trashedDestinationCandidate?.accountID != account.id {
            clearTrashedDestinationCandidate()
        }
        if fileReplacementCandidate?.accountID != account.id {
            clearFileReplacementCandidate()
        }
        self.account = account
        accountLabel = "\(account.displayName) — \(account.emailAddress)"
        destinationLabel = partitions.destination(for: account.id)?.folderName
            ?? "Choose or create a destination"
        restoreLastVerifiedLabel(for: account.id)
    }

    private func validateStoredDestination(
        _ folder: DailyDriveFolder,
        binding: DailyDestinationBinding,
        accountID: String
    ) throws {
        do {
            try DailyDriveConsentPolicy.validate(
                folder: folder,
                expectedAccountID: accountID
            )
            clearTrashedDestinationCandidate()
        } catch DailyDriveConsentPolicy.Failure.trashed {
            trashedDestinationCandidate = binding
            canForgetTrashedDestination = true
            throw DailyDriveConsentPolicy.Failure.trashed
        }
    }

    private func clearTrashedDestinationCandidate() {
        trashedDestinationCandidate = nil
        canForgetTrashedDestination = false
    }

    private func markFileForReplacement(
        accountID: String,
        folderID: String,
        reportDate: String,
        reason: FileReplacementReason
    ) {
        fileReplacementCandidate = FileReplacementCandidate(
            accountID: accountID,
            folderID: folderID,
            reportDate: reportDate
        )
        fileReplacementReason = reason
    }

    private func clearFileReplacementCandidate(
        accountID: String? = nil,
        folderID: String? = nil,
        reportDate: String? = nil
    ) {
        if let candidate = fileReplacementCandidate,
           let accountID, let folderID, let reportDate,
           candidate != FileReplacementCandidate(
               accountID: accountID,
               folderID: folderID,
               reportDate: reportDate
           ) {
            return
        }
        fileReplacementCandidate = nil
        fileReplacementReason = nil
    }

    private func restoreLocalStateWithoutNetwork() {
        do {
            if let data = try keychain.load(account: Self.authKey) {
                authState = try NSKeyedUnarchiver.unarchivedObject(
                    ofClass: OIDAuthState.self,
                    from: data
                )
                attachDelegates()
            }
            if let data = try keychain.load(account: Self.destinationsKey) {
                partitions = try JSONDecoder().decode(DailyDestinationPartitions.self, from: data)
            }
        } catch {
            status = "Secure local state could not be restored; export is blocked."
        }
    }

    private func restoreLastVerifiedLabel(for accountID: String) {
        do {
            let folderID = partitions.destination(for: accountID)?.folderID
            let latest = try identityStore.load()?.identities
                .filter { $0.accountID == accountID && $0.folderID == folderID }
                .compactMap(\.lastVerified)
                .max { $0.verifiedAt < $1.verifiedAt }
            if let latest {
                lastVerifiedLabel = "Persisted verification through \(latest.dataAsOf)"
            } else {
                lastVerifiedLabel = "No verified Drive upload for this destination"
            }
        } catch {
            lastVerifiedLabel = "Stored identity is ambiguous; explicit recovery required"
        }
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
        try keychain.save(data, account: Self.authKey)
    }

    private func run(_ startingStatus: String, operation: () async throws -> Void) async {
        guard !busy else { return }
        busy = true
        status = startingStatus
        defer { busy = false }
        do {
            try await operation()
        } catch let failure as DailyDriveConsentPolicy.Failure {
            status = "Rejected by consent/destination policy: \(failure.userFacingLabel)."
        } catch let failure as DailyDriveExportFailure {
            status = failure.userFacingLabel
        } catch HealthDataError.unavailable {
            status = "Health data is unavailable on this device. No JSON or Drive request was created."
        } catch DailyHealthExportError.nutritionSourceRequired {
            status = "Choose a visible nutrition source before refreshing the preview."
        } catch DailyHealthExportError.nutritionSourceUnavailable {
            preview = nil
            status = "The selected nutrition source is unavailable. Refresh sources and choose again; no unfiltered nutrition was used."
        } catch DailyHealthExportError.notesChanged {
            preview = nil
            status = "Saved notes changed during refresh. Refresh and review a new preview."
        } catch DailyHealthExportError.notesUnavailable {
            preview = nil
            status = "Saved notes are unavailable. No preview or Drive request was created."
        } catch let error as NSError
            where error.domain == OIDGeneralErrorDomain && error.code == -3 {
            status = "Consent or selection was cancelled. Existing state was preserved."
        } catch Failure.missingConfiguration {
            status = "Drive export is disabled until this app has its own local OAuth client configuration."
        } catch {
            status = "Operation failed. No background retry was queued."
        }
    }

    private var previewIsCurrent: Bool {
        guard let preview else { return false }
        return notes.document.snapshot(for: preview.notesSnapshot.dayID) == preview.notesSnapshot
    }

    private func invalidatePreview(after snapshot: DailyNotesSnapshot) {
        guard let preview, preview.notesSnapshot.dayID == snapshot.dayID,
              preview.notesSnapshot != snapshot else { return }
        self.preview = nil
        status = "Saved notes changed. Refresh and review a new preview before exporting."
    }
}

extension DailyDriveSessionController: OIDAuthStateChangeDelegate, OIDAuthStateErrorDelegate {
    nonisolated func didChange(_ state: OIDAuthState) {
        Task { @MainActor in try? self.saveAuthState() }
    }

    nonisolated func authState(_ state: OIDAuthState, didEncounterAuthorizationError error: Error) {
        Task { @MainActor in
            try? self.saveAuthState()
            self.status = "The Google grant is expired, denied or revoked. Reconnect before exporting."
        }
    }
}

private extension DailyDriveConsentPolicy.Failure {
    var userFacingLabel: String {
        switch self {
        case .missingDriveFileScope: "drive.file was not granted"
        case .unexpectedScope: "an unexpected broader or identity scope was returned"
        case .invalidPickerSelection: "selection did not return exactly one item"
        case .accountMismatch: "account mismatch"
        case .notAppAuthorized: "the folder was not explicitly authorised for this app"
        case .notFolder: "the selection is not a folder"
        case .trashed: "the folder is trashed"
        case .sharedDriveUnsupported: "Shared Drives are unsupported"
        case .notWritable: "the folder cannot accept children"
        }
    }
}

extension DailyDriveExportResult {

    var authorizesNoteCleanup: Bool {
        switch self {
        case .verified, .unchangedVerified: true
        case .cancelledBeforeSubmission, .cancelledAfterSubmissionVerified: false
        }
    }
}

private extension DailyDriveExportResult {

    var verifiedLabel: String {
        switch self {
        case .verified(let dataAsOf, _), .unchangedVerified(let dataAsOf),
             .cancelledAfterSubmissionVerified(let dataAsOf, _):
            "Verified through \(dataAsOf)"
        case .cancelledBeforeSubmission:
            "No new verified upload"
        }
    }

    var userFacingLabel: String {
        switch self {
        case .verified(let dataAsOf, _):
            "Upload metadata and bytes verified remotely for \(dataAsOf)."
        case .unchangedVerified(let dataAsOf):
            "The unchanged \(dataAsOf) snapshot was reverified; no write ran."
        case .cancelledBeforeSubmission:
            "Cancelled before submission. The last verified Drive file was preserved."
        case .cancelledAfterSubmissionVerified(let dataAsOf, _):
            "Cancellation followed submission; reconciliation verified \(dataAsOf)."
        }
    }
}

private extension DailyDriveRecoveryResult {
    var verifiedLabel: String {
        switch self {
        case .recovered(let dataAsOf), .alreadyTracked(let dataAsOf):
            "Recovered and verified through \(dataAsOf)"
        }
    }

    var userFacingLabel: String {
        switch self {
        case .recovered(let dataAsOf):
            "Explicit recovery verified the selected canonical file through \(dataAsOf)."
        case .alreadyTracked(let dataAsOf):
            "The selected canonical file was already tracked and reverified through \(dataAsOf)."
        }
    }
}

private extension DailyDriveExportFailure {
    var userFacingLabel: String {
        switch self {
        case .busy: "Another export or reconciliation is active."
        case .invalidPayload: "The preview is not canonical daily-export JSON."
        case .staleSnapshot: "A stale or conflicting snapshot was rejected; the last verified file is unchanged."
        case .destinationChangeRequiresMigration: "Export is blocked because account or destination identity changed."
        case .accountMismatch: "Export is blocked by a Google account mismatch."
        case .identityRecoveryAmbiguous: "Export is blocked because canonical identity recovery is ambiguous."
        case .staleCompletion: "A stale completion was rejected; the last verified file was preserved."
        case .credentials(let reason): "Google credentials are \(reason.rawValue). Reconnect before exporting."
        case .credentialsRejected: "Google credentials were expired, denied or revoked. Reconnect before exporting."
        case .permissionDenied: "Google denied the operation. No broader permission will be requested."
        case .quotaExceeded: "Drive quota is exhausted. No retry was queued."
        case .rateLimited: "Drive rate-limited the request. No background retry was queued."
        case .remoteMissing: "The stored Drive file is missing or inaccessible. Confirm an explicit override before creating a replacement."
        case .remoteMoved: "The stored file moved outside the validated destination; export is blocked."
        case .remoteTrashed: "The stored file is trashed. Confirm replacement before creating a new file ID."
        case .remoteMetadataMismatch: "Remote metadata did not match the canonical identity."
        case .remoteContentMismatch: "Remote bytes did not match the reviewed preview."
        case .unresolvedRequest: "The submitted request is unresolved. New writes are blocked; no retry is queued."
        case .persistenceFailure: "Secure export identity state could not be persisted."
        case .transportFailure: "The Drive request failed. Upload is unverified and no retry was queued."
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
