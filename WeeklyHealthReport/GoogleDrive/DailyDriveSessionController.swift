import AppAuth
import DriveExportKit
import DriveExportOAuth
import Foundation
import UIKit

enum DailyExportAttention: Equatable {
    case configurationUnavailable
    case googleUnavailable
    case destinationRequired
    case destinationMissingOrInaccessible
    case destinationTrashed
    case destinationSetupFailed
    case nutritionSourceUnavailable
    case healthDataUnavailable
    case notesUnavailable
    case notesChanged
    case canonicalRecovery
    case unexpected
}

enum DailyExportPresentationAction: Hashable {
    case connect
    case authorizeNutrition
    case selectNutritionSource
    case refreshPreview
    case export
    case inspectExactJSON
    case manageAccount
    case createDestination
    case chooseDestination
    case forgetTrashedDestination
    case recoverCanonicalFile
    case retry
}

enum DailyExportPresentationState: Equatable {
    case preparing
    case needsGoogleConnection
    case needsNutritionSource
    case readyToExport
    case needsAttention(DailyExportAttention)

    var actions: Set<DailyExportPresentationAction> {
        switch self {
        case .preparing:
            []
        case .needsGoogleConnection:
            [.connect]
        case .needsNutritionSource:
            [.authorizeNutrition, .selectNutritionSource, .refreshPreview, .manageAccount]
        case .readyToExport:
            [
                .refreshPreview, .export, .inspectExactJSON, .manageAccount,
                .chooseDestination, .recoverCanonicalFile
            ]
        case .needsAttention(let attention):
            switch attention {
            case .configurationUnavailable:
                []
            case .googleUnavailable:
                [.connect, .manageAccount, .retry]
            case .destinationRequired:
                [.createDestination, .chooseDestination, .manageAccount]
            case .destinationMissingOrInaccessible, .destinationSetupFailed:
                [.manageAccount, .retry]
            case .destinationTrashed:
                [.forgetTrashedDestination, .manageAccount, .retry]
            case .nutritionSourceUnavailable:
                [.authorizeNutrition, .selectNutritionSource, .manageAccount]
            case .healthDataUnavailable, .notesUnavailable, .notesChanged, .unexpected:
                [.retry, .manageAccount]
            case .canonicalRecovery:
                [.recoverCanonicalFile, .refreshPreview, .manageAccount]
            }
        }
    }
}

enum DailyExportPreparationFailure: Error, Equatable {
    case freshGoogleConsentRequired
    case googleUnavailable
    case destinationRequired
    case destinationMissingOrInaccessible
    case destinationTrashed
    case destinationSetupFailed
    case nutritionSourceUnavailable
    case healthDataUnavailable
    case notesUnavailable
    case notesChanged
}

struct DailyExportGoogleContext: Equatable {
    let account: DailyDriveAccount
    let accessToken: String
}

@MainActor
protocol DailyExportPreparationDriving: AnyObject {
    var hasStoredGoogleSession: Bool { get }
    var storedNutritionSourceBundleIdentifier: String? { get }

    func restoreGoogleSession() async throws -> DailyExportGoogleContext
    func storedDestination(for accountID: String) throws -> DailyDestinationBinding?
    func validateStoredDestination(
        _ binding: DailyDestinationBinding,
        context: DailyExportGoogleContext
    ) async throws
    func createDefaultDestination(context: DailyExportGoogleContext) async throws
    func resolveNutritionSourceWithoutAuthorization(bundleIdentifier: String) async throws
    func refreshPreviewWithoutAuthorization(bundleIdentifier: String) async throws
}

@MainActor
final class DailyExportPreparationOrchestrator {
    private(set) var isRunning = false

    func prepare(using driver: any DailyExportPreparationDriving) async
        -> DailyExportPresentationState {
        guard !isRunning else { return .preparing }
        isRunning = true
        defer { isRunning = false }

        guard driver.hasStoredGoogleSession else {
            return .needsGoogleConnection
        }
        do {
            let context = try await driver.restoreGoogleSession()
            return try await finish(context: context, using: driver)
        } catch {
            return state(for: error)
        }
    }

    func prepareAfterGoogleConnection(
        context: DailyExportGoogleContext,
        using driver: any DailyExportPreparationDriving
    ) async -> DailyExportPresentationState {
        guard !isRunning else { return .preparing }
        isRunning = true
        defer { isRunning = false }
        do {
            return try await finish(context: context, using: driver)
        } catch {
            return state(for: error)
        }
    }

    private func finish(
        context: DailyExportGoogleContext,
        using driver: any DailyExportPreparationDriving
    ) async throws -> DailyExportPresentationState {
        guard let binding = try driver.storedDestination(for: context.account.id) else {
            throw DailyExportPreparationFailure.destinationRequired
        }
        try await driver.validateStoredDestination(binding, context: context)

        guard let bundleIdentifier = driver.storedNutritionSourceBundleIdentifier,
              !bundleIdentifier.isEmpty else {
            return .needsNutritionSource
        }
        try await driver.resolveNutritionSourceWithoutAuthorization(
            bundleIdentifier: bundleIdentifier
        )
        try await driver.refreshPreviewWithoutAuthorization(
            bundleIdentifier: bundleIdentifier
        )
        return .readyToExport
    }

    private func state(for error: Error) -> DailyExportPresentationState {
        guard let failure = error as? DailyExportPreparationFailure else {
            return .needsAttention(.unexpected)
        }
        switch failure {
        case .freshGoogleConsentRequired:
            return .needsGoogleConnection
        case .googleUnavailable:
            return .needsAttention(.googleUnavailable)
        case .destinationRequired:
            return .needsAttention(.destinationRequired)
        case .destinationMissingOrInaccessible:
            return .needsAttention(.destinationMissingOrInaccessible)
        case .destinationTrashed:
            return .needsAttention(.destinationTrashed)
        case .destinationSetupFailed:
            return .needsAttention(.destinationSetupFailed)
        case .nutritionSourceUnavailable:
            return .needsAttention(.nutritionSourceUnavailable)
        case .healthDataUnavailable:
            return .needsAttention(.healthDataUnavailable)
        case .notesUnavailable:
            return .needsAttention(.notesUnavailable)
        case .notesChanged:
            return .needsAttention(.notesChanged)
        }
    }
}

struct DailyExportPreviewSummary: Equatable {
    let reportDate: String
    let dataAsOf: String
    let nutritionSource: String
    let savedNoteCount: Int
    let currentWindow: String
    let previousWindow: String
    let encodedByteCount: Int
}

@MainActor
final class DailyDriveSessionController: NSObject, ObservableObject, DailyExportPreparationDriving {
    enum AuthorizationPurpose { case connect, chooseFolder, recoverFile }
    typealias FileReplacementReason = DailyDestinationCoordinator.FileReplacementReason
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
    @Published private(set) var presentationState: DailyExportPresentationState = .preparing

    let notes: DailyNotesController
    private(set) var exactJSONConstructionCount = 0

    var isConfigured: Bool { (try? oauthConfiguration()) != nil }
    var canExport: Bool {
        previewIsCurrent && account != nil && activeDestination != nil && !busy
            && presentationState == .readyToExport
    }
    var previewSummary: DailyExportPreviewSummary? {
        guard let preview,
              let nutrition = preview.envelope.today.nutrition,
              let context = preview.envelope.appContext.nutrition else { return nil }
        return DailyExportPreviewSummary(
            reportDate: preview.envelope.reportDate,
            dataAsOf: preview.envelope.dataAsOf,
            nutritionSource: "\(nutrition.source.name) — \(nutrition.source.bundleIdentifier)",
            savedNoteCount: preview.envelope.today.notes?.count ?? 0,
            currentWindow: "\(context.currentWindow.start) to \(context.currentWindow.end)",
            previousWindow: "\(context.previousWindow.start) to \(context.previousWindow.end)",
            encodedByteCount: preview.bytes.count
        )
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

    private let oauthSession: any DriveOAuthSessionProviding
    private let drive: any DailyDriveSessionTransporting
    private let destinationCoordinator: DailyDestinationCoordinator
    private let exportService: DailyHealthExportService
    private let identityStore: KeychainDailyDriveExportIdentityStore
    private let exportCoordinator: DailyDriveExportCoordinator
    private let nutritionSourceSelection: any NutritionSourceSelectionPersisting
    private let preparationOrchestrator = DailyExportPreparationOrchestrator()
    private var account: DailyDriveAccount?
    private var identityRecoveryRequired = false

    private static let authKey = "google.oauth.daily-export.appauth-state.v1"
    private static let destinationsKey = "google.drive.daily-export-destinations.v1"

    private var activeDestination: DailyDestinationBinding? {
        destinationCoordinator.activeDestination(for: account?.id)
    }

    var hasStoredGoogleSession: Bool { oauthSession.hasStoredSession }
    var storedNutritionSourceBundleIdentifier: String? {
        selectedNutritionSourceBundleIdentifier
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
        keychain: any DailyDriveSecurePersisting,
        drive: any DailyDriveSessionTransporting,
        exportService: DailyHealthExportService,
        identityStore: KeychainDailyDriveExportIdentityStore,
        nutritionSourceSelection: any NutritionSourceSelectionPersisting,
        notes: DailyNotesController,
        oauthSession: (any DriveOAuthSessionProviding)? = nil
    ) {
        self.oauthSession = oauthSession ?? AppAuthDriveSession(
            secureStore: keychain,
            authKey: Self.authKey
        )
        self.drive = drive
        destinationCoordinator = DailyDestinationCoordinator(
            drive: drive,
            secureStore: keychain,
            destinationsKey: Self.destinationsKey
        )
        self.exportService = exportService
        self.identityStore = identityStore
        self.nutritionSourceSelection = nutritionSourceSelection
        self.notes = notes
        exportCoordinator = DailyDriveExportCoordinator(
            transport: drive,
            store: identityStore
        )
        super.init()
        self.oauthSession.onAuthorizationError = { [weak self] failure in
            guard let self else { return }
            self.preview = nil
            self.presentationState = .needsGoogleConnection
            self.status = DailyDriveExportFailure.credentials(failure).userFacingLabel
        }
        notes.onSavedNotesMutation = { [weak self] snapshot in
            self?.invalidatePreview(after: snapshot)
        }
        selectedNutritionSourceBundleIdentifier = nutritionSourceSelection.loadBundleIdentifier()
        restoreLocalStateWithoutNetwork()
        if !isConfigured {
            status = "Drive export is disabled until this app has its own local OAuth client configuration."
            presentationState = .needsAttention(.configurationUnavailable)
        } else if !self.oauthSession.hasStoredSession {
            presentationState = .needsGoogleConnection
        }
    }

    func connect() async {
        await run("Opening Google consent…") {
            let result = try await self.authorize(.connect)
            self.accept(account: result.account)
            let state = await self.preparationOrchestrator.prepareAfterGoogleConnection(
                context: DailyExportGoogleContext(
                    account: result.account,
                    accessToken: result.token
                ),
                using: self
            )
            self.applyPresentationState(state)
        }
    }

    func restore() async {
        await prepareForPresentation()
    }

    func prepareForPresentation() async {
        guard !busy, isConfigured else {
            if !isConfigured {
                presentationState = .needsAttention(.configurationUnavailable)
            }
            return
        }
        busy = true
        preview = nil
        presentationState = .preparing
        status = "Restoring the saved account, destination and nutrition source…"
        let state = await preparationOrchestrator.prepare(using: self)
        applyPresentationState(state)
        busy = false
    }

    func createDestination() async {
        await run("Creating the dedicated Drive destination…") {
            let context = try await self.currentContext()
            try await self.createDefaultDestination(
                context: DailyExportGoogleContext(
                    account: context.account,
                    accessToken: context.token
                )
            )
            let state = await self.preparationOrchestrator.prepareAfterGoogleConnection(
                context: DailyExportGoogleContext(
                    account: context.account,
                    accessToken: context.token
                ),
                using: self
            )
            self.applyPresentationState(state)
        }
    }

    func forgetTrashedDestination() async {
        await run("Forgetting the confirmed trashed destination…") {
            let context = try await self.currentContext()
            guard let candidate = self.destinationCoordinator.trashedDestination(
                for: context.account.id
            ) else {
                throw Failure.noDestination
            }

            try await self.exportCoordinator.abandonDestination(
                accountID: candidate.accountID,
                folderID: candidate.folderID
            )
            try self.destinationCoordinator.forgetTrashedDestination(candidate)
            self.accept(account: context.account)
            self.presentationState = .needsAttention(.destinationRequired)
            self.status = "Forgot the trashed destination and its local file identities. You can now create or choose a fresh folder; no Drive item was changed."
        }
    }

    func chooseDestination() async {
        await run("Opening explicit folder selection…") {
            guard let expectedAccountID = self.account?.id else {
                throw Failure.noAccount
            }
            let result = try await self.authorize(
                .chooseFolder,
                expectedAccountID: expectedAccountID
            )
            guard let pickedID = result.pickedItemID else {
                throw DailyDriveConsentPolicy.Failure.invalidPickerSelection
            }
            let folder = try await self.drive.folder(
                id: pickedID,
                accessToken: result.token,
                accountID: result.account.id
            )
            try self.destinationCoordinator.acceptPickedFolder(
                folder,
                accountID: result.account.id
            )
            self.accept(account: result.account)
            let state = await self.preparationOrchestrator.prepareAfterGoogleConnection(
                context: DailyExportGoogleContext(
                    account: result.account,
                    accessToken: result.token
                ),
                using: self
            )
            self.applyPresentationState(state)
        }
    }

    func refreshPreview() async {
        await run("Reading a fresh on-device daily snapshot…") {
            guard let bundleIdentifier = self.selectedNutritionSourceBundleIdentifier else {
                throw DailyHealthExportError.nutritionSourceRequired
            }
            try await self.resolveNutritionSourceWithoutAuthorization(
                bundleIdentifier: bundleIdentifier
            )
            try await self.refreshPreviewWithoutAuthorization(
                bundleIdentifier: bundleIdentifier
            )
            self.applyReadyStateAfterPreview()
        }
    }

    func refreshNutritionSources() async {
        await run("Requesting nutrition read access and discovering visible sources…") {
            let sources = try await self.exportService.discoverNutritionSources()
            self.nutritionSources = sources
            guard let selected = self.selectedNutritionSourceBundleIdentifier else {
                self.presentationState = .needsNutritionSource
                self.status = sources.isEmpty
                    ? "No visible nutrition source was found. No preview or Drive request was created."
                    : "Choose a visible nutrition source. No preview or Drive request was created."
                return
            }
            guard sources.contains(where: { $0.bundleIdentifier == selected }) else {
                self.preview = nil
                self.presentationState = .needsAttention(.nutritionSourceUnavailable)
                self.status = "The saved nutrition source is not visible. Choose an available source; no unfiltered nutrition was used."
                return
            }
            self.presentationState = .needsNutritionSource
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
        presentationState = .needsNutritionSource
        status = "Selected \(source.name) by bundle identifier. Refresh to create a new reviewed preview."
    }

    func makeExactPreviewText() -> String? {
        guard let preview else { return nil }
        exactJSONConstructionCount += 1
        return String(data: preview.bytes, encoding: .utf8)
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
                self.destinationCoordinator.markFileForReplacement(
                    accountID: account.id,
                    folderID: destination.folderID,
                    reportDate: preview.envelope.reportDate,
                    reason: .trashed
                )
                self.mirrorDestinationState()
                throw DailyDriveExportFailure.remoteTrashed
            } catch DailyDriveExportFailure.remoteMissing {
                self.destinationCoordinator.markFileForReplacement(
                    accountID: account.id,
                    folderID: destination.folderID,
                    reportDate: preview.envelope.reportDate,
                    reason: .missingOrInaccessible
                )
                self.mirrorDestinationState()
                throw DailyDriveExportFailure.remoteMissing
            } catch let failure as DailyDriveExportFailure {
                try self.applyExportOutcome(.failure(failure), exportedPreview: preview)
                return
            }
            self.destinationCoordinator.clearFileReplacementCandidate(
                accountID: account.id,
                folderID: destination.folderID,
                reportDate: preview.envelope.reportDate
            )
            self.mirrorDestinationState()
            try self.applyExportOutcome(.success(result), exportedPreview: preview)
        }
    }

    func applyExportOutcome(
        _ outcome: Result<DailyDriveExportResult, DailyDriveExportFailure>,
        exportedPreview: DailyHealthExportResult
    ) throws {
        let result = try outcome.get()
        lastVerifiedLabel = result.verifiedLabel
        status = result.userFacingLabel
        guard result.authorizesNoteCleanup else { return }

        if !notes.markVerified(
            snapshot: exportedPreview.notesSnapshot,
            payload: exportedPreview.bytes
        ) {
            status += " Current notes were retained because their verified cleanup marker was not saved."
        }
        if preview == exportedPreview {
            preview = nil
        }
    }

    func confirmFileReplacementOverride() async {
        await run("Forgetting the unavailable file identity…") {
            let context = try await self.currentContext()
            guard let candidate = self.destinationCoordinator.fileReplacementCandidate(
                    accountID: context.account.id,
                    folderID: self.activeDestination?.folderID
                  ),
                  let reason = self.destinationCoordinator.fileReplacementReason,
                  candidate.accountID == context.account.id,
                  self.activeDestination?.folderID == candidate.folderID else {
                throw Failure.noDestination
            }

            try await self.exportCoordinator.abandonFileIdentity(
                accountID: candidate.accountID,
                folderID: candidate.folderID,
                reportDate: candidate.reportDate
            )
            self.destinationCoordinator.clearFileReplacementCandidate()
            self.mirrorDestinationState()
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
            let result = try await self.authorize(
                .recoverFile,
                expectedAccountID: destination.accountID
            )
            guard let selectedFileID = result.pickedItemID else {
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
            self.destinationCoordinator.clearFileReplacementCandidate(
                accountID: result.account.id,
                folderID: destination.folderID,
                reportDate: preview.envelope.reportDate
            )
            self.mirrorDestinationState()
            self.lastVerifiedLabel = recovery.verifiedLabel
            self.identityRecoveryRequired = false
            self.presentationState = .readyToExport
            self.status = recovery.userFacingLabel
        }
    }

    func signOut() {
        guard !busy else { return }
        do {
            try oauthSession.clear()
            account = nil
            destinationCoordinator.clearCandidates()
            mirrorDestinationState()
            accountLabel = "Not connected"
            destinationLabel = "No active destination"
            preview = nil
            presentationState = .needsGoogleConnection
            status = "Signed out locally. Drive access was not revoked and exports were not deleted."
        } catch {
            status = "Local sign-out failed; secure credentials may still be present."
        }
    }

    func disconnect() async {
        guard oauthSession.hasStoredSession else {
            status = "Nothing to revoke."
            return
        }
        await run("Revoking the Google grant…") {
            guard let token = self.oauthSession.revocationToken else {
                throw Failure.noRefreshToken
            }
            let code = try await self.drive.revoke(token: token)
            switch DailyDisconnectTransition.afterRevocation(statusCode: code) {
            case .clearCredentialsPreserveDestinations:
                try self.oauthSession.clear()
                self.account = nil
                self.destinationCoordinator.clearCandidates()
                self.mirrorDestinationState()
                self.accountLabel = "Not connected"
                self.destinationLabel = "No active destination"
                self.preview = nil
                self.presentationState = .needsGoogleConnection
                self.status = "Access revoked and local credentials cleared. Drive files were not deleted."
            case .keepCredentialsAndReportFailure:
                throw DailyDriveAPI.Failure.httpStatus(code, nil)
            }
        }
    }

    func resumeOAuthRedirect(_ url: URL) {
        _ = oauthSession.resumeRedirect(url)
    }

    private struct AuthorizationResult {
        let token: String
        let account: DailyDriveAccount
        let pickedItemID: String?
    }

    private func authorize(
        _ purpose: AuthorizationPurpose,
        expectedAccountID: String? = nil
    ) async throws -> AuthorizationResult {
        let configuration = try oauthConfiguration()
        let authorization = DriveAuthorizationRequest(
            purpose: purpose.driveAuthorizationPurpose,
            loginHint: account?.emailAddress
        )
        guard let presenter = UIApplication.shared.activeRootViewController else {
            throw Failure.noPresenter
        }
        guard let userAgent = OIDExternalUserAgentIOS(presenting: presenter) else {
            throw Failure.noPresenter
        }
        do {
            let outcome = try await oauthSession.authorize(
                authorization,
                configuration: configuration,
                userAgent: userAgent
            )
            let account = try await drive.account(accessToken: outcome.accessToken)
            if let expectedAccountID, account.id != expectedAccountID {
                throw DailyDriveExportFailure.accountMismatch
            }
            try oauthSession.acceptPendingAuthorization()
            return AuthorizationResult(
                token: outcome.accessToken,
                account: account,
                pickedItemID: outcome.pickedItemID
            )
        } catch {
            oauthSession.discardPendingAuthorization()
            throw error
        }
    }

    func restoreGoogleSession() async throws -> DailyExportGoogleContext {
        guard oauthSession.hasStoredSession else {
            throw DailyExportPreparationFailure.freshGoogleConsentRequired
        }
        let token: String
        do {
            token = try await freshAccessToken()
            try validateCurrentGrant()
        } catch {
            throw DailyExportPreparationFailure.freshGoogleConsentRequired
        }
        let restoredAccount: DailyDriveAccount
        do {
            restoredAccount = try await drive.account(accessToken: token)
        } catch DailyDriveAPI.Failure.httpStatus(401, _) {
            throw DailyExportPreparationFailure.freshGoogleConsentRequired
        } catch {
            throw DailyExportPreparationFailure.googleUnavailable
        }
        accept(account: restoredAccount)
        return DailyExportGoogleContext(account: restoredAccount, accessToken: token)
    }

    func storedDestination(for accountID: String) throws -> DailyDestinationBinding? {
        try destinationCoordinator.storedDestination(for: accountID)
    }

    func validateStoredDestination(
        _ binding: DailyDestinationBinding,
        context: DailyExportGoogleContext
    ) async throws {
        defer { mirrorDestinationState() }
        try await destinationCoordinator.validateStoredDestination(binding, context: context)
        accept(account: context.account)
    }

    func createDefaultDestination(context: DailyExportGoogleContext) async throws {
        defer { mirrorDestinationState() }
        try await destinationCoordinator.createDefaultDestination(context: context)
        accept(account: context.account)
    }

    func resolveNutritionSourceWithoutAuthorization(bundleIdentifier: String) async throws {
        let sources: [NutritionSource]
        do {
            sources = try await exportService.resolveNutritionSourcesWithoutAuthorization()
        } catch HealthDataError.unavailable {
            throw DailyExportPreparationFailure.healthDataUnavailable
        } catch {
            throw DailyExportPreparationFailure.nutritionSourceUnavailable
        }
        nutritionSources = sources
        guard sources.contains(where: { $0.bundleIdentifier == bundleIdentifier }) else {
            preview = nil
            throw DailyExportPreparationFailure.nutritionSourceUnavailable
        }
    }

    func refreshPreviewWithoutAuthorization(bundleIdentifier: String) async throws {
        do {
            let result = try await exportService.refresh(
                nutritionSourceBundleIdentifier: bundleIdentifier
            )
            destinationCoordinator.clearFileReplacementCandidate(
                unlessReportDate: result.envelope.reportDate
            )
            mirrorDestinationState()
            preview = result
        } catch HealthDataError.unavailable {
            throw DailyExportPreparationFailure.healthDataUnavailable
        } catch DailyHealthExportError.nutritionSourceUnavailable {
            preview = nil
            throw DailyExportPreparationFailure.nutritionSourceUnavailable
        } catch DailyHealthExportError.notesChanged {
            preview = nil
            throw DailyExportPreparationFailure.notesChanged
        } catch DailyHealthExportError.notesUnavailable {
            preview = nil
            throw DailyExportPreparationFailure.notesUnavailable
        }
    }

    private func currentContext() async throws -> (token: String, account: DailyDriveAccount) {
        guard let expected = account else { throw Failure.noAccount }
        let token = try await freshAccessToken()
        try validateCurrentGrant()
        let current = try await drive.account(accessToken: token)
        guard current.id == expected.id else { throw DailyDriveExportFailure.accountMismatch }
        return (token, current)
    }

    private func oauthConfiguration() throws -> DriveOAuthClientConfiguration {
        do {
            return try DriveOAuthClientConfiguration.fromMainBundle()
        } catch DriveOAuthClientConfiguration.Failure.missingConfiguration {
            throw Failure.missingConfiguration
        } catch DriveOAuthClientConfiguration.Failure.invalidConfiguration {
            throw Failure.invalidConfiguration
        }
    }

    private func freshAccessToken(forceRefresh: Bool = false) async throws -> String {
        try await oauthSession.accessToken(forceRefresh: forceRefresh)
    }

    private func validateCurrentGrant() throws {
        try oauthSession.validateCurrentGrant()
    }

    private func accept(account: DailyDriveAccount) {
        destinationCoordinator.acceptAccount(account.id)
        self.account = account
        accountLabel = "\(account.displayName) — \(account.emailAddress)"
        mirrorDestinationState()
        restoreLastVerifiedLabel(for: account.id)
    }

    private func restoreLocalStateWithoutNetwork() {
        do {
            try oauthSession.restoreWithoutNetwork()
        } catch {
            status = "Secure Google session state could not be restored; fresh consent is required."
        }
        do {
            try destinationCoordinator.restoreWithoutNetwork()
        } catch {
            status = "Secure destination state could not be restored; automatic folder creation is blocked."
        }
    }

    private func mirrorDestinationState() {
        canForgetTrashedDestination = destinationCoordinator.canForgetTrashedDestination
        fileReplacementReason = destinationCoordinator.fileReplacementReason
        if let account {
            destinationLabel = destinationCoordinator.destinationLabel(for: account.id)
        }
    }

    private func restoreLastVerifiedLabel(for accountID: String) {
        do {
            let folderID = destinationCoordinator.activeDestination(for: accountID)?.folderID
            let latest = try identityStore.load()?.identities
                .filter { $0.accountID == accountID && $0.folderID == folderID }
                .compactMap(\.lastVerified)
                .max { $0.verifiedAt < $1.verifiedAt }
            if let latest {
                lastVerifiedLabel = "Persisted verification through \(latest.dataAsOf)"
            } else {
                lastVerifiedLabel = "No verified Drive upload for this destination"
            }
            identityRecoveryRequired = false
        } catch {
            lastVerifiedLabel = "Stored identity is ambiguous; explicit recovery required"
            identityRecoveryRequired = true
        }
    }

    private func run(_ startingStatus: String, operation: () async throws -> Void) async {
        guard !busy else { return }
        busy = true
        status = startingStatus
        defer { busy = false }
        do {
            try await operation()
        } catch let failure as DailyDriveConsentPolicy.Failure {
            presentationState = failure == .trashed
                ? .needsAttention(.destinationTrashed)
                : .needsAttention(.destinationMissingOrInaccessible)
            status = "Rejected by consent/destination policy: \(failure.userFacingLabel)."
        } catch let failure as DailyDriveExportFailure {
            switch failure {
            case .credentials, .credentialsRejected:
                presentationState = .needsGoogleConnection
            case .remoteMissing, .remoteTrashed, .remoteMoved,
                 .destinationChangeRequiresMigration, .identityRecoveryAmbiguous:
                presentationState = .needsAttention(.canonicalRecovery)
            default:
                presentationState = .needsAttention(.unexpected)
            }
            status = failure.userFacingLabel
        } catch HealthDataError.unavailable {
            presentationState = .needsAttention(.healthDataUnavailable)
            status = "Health data is unavailable on this device. No JSON or Drive request was created."
        } catch DailyHealthExportError.nutritionSourceRequired {
            presentationState = .needsNutritionSource
            status = "Choose a visible nutrition source before refreshing the preview."
        } catch DailyHealthExportError.nutritionSourceUnavailable {
            preview = nil
            presentationState = .needsAttention(.nutritionSourceUnavailable)
            status = "The selected nutrition source is unavailable. Refresh sources and choose again; no unfiltered nutrition was used."
        } catch DailyHealthExportError.notesChanged {
            preview = nil
            presentationState = .needsAttention(.notesChanged)
            status = "Saved notes changed during refresh. Refresh and review a new preview."
        } catch DailyHealthExportError.notesUnavailable {
            preview = nil
            presentationState = .needsAttention(.notesUnavailable)
            status = "Saved notes are unavailable. No preview or Drive request was created."
        } catch let error as NSError
            where error.domain == AppAuthDriveSession.errorDomain
                && error.code == AppAuthDriveSession.userCancelledAuthorizationFlowCode {
            status = "Consent or selection was cancelled. Existing state was preserved."
        } catch Failure.missingConfiguration {
            presentationState = .needsAttention(.configurationUnavailable)
            status = "Drive export is disabled until this app has its own local OAuth client configuration."
        } catch {
            presentationState = .needsAttention(.unexpected)
            status = "Operation failed. No background retry was queued."
        }
    }

    private func applyReadyStateAfterPreview() {
        if identityRecoveryRequired {
            presentationState = .needsAttention(.canonicalRecovery)
            status = "Fresh preview created. Stored canonical identity is ambiguous; use contextual recovery before exporting."
        } else if account != nil, activeDestination != nil {
            presentationState = .readyToExport
            status = "Fresh preview created in memory. Review the snapshot, then choose Export."
        } else {
            presentationState = .needsAttention(.destinationSetupFailed)
            status = "Fresh preview created, but a validated account and destination are still required."
        }
    }

    private func applyPresentationState(_ state: DailyExportPresentationState) {
        presentationState = state
        switch state {
        case .preparing:
            status = "Restoring the saved account, destination and nutrition source…"
        case .needsGoogleConnection:
            status = !oauthSession.hasStoredSession
                ? "Connect Google to continue. No Health or Drive request ran."
                : "The stored Google session needs fresh consent before export can continue."
        case .needsNutritionSource:
            status = "Choose a nutrition source explicitly. Opening this screen did not request Health access."
        case .readyToExport:
            applyReadyStateAfterPreview()
        case .needsAttention(let attention):
            switch attention {
            case .configurationUnavailable:
                status = "Drive export is disabled until this app has its own local OAuth client configuration."
            case .googleUnavailable:
                status = "The stored Google account could not be revalidated. No export ran."
            case .destinationRequired:
                status = "Choose an existing Drive folder or explicitly create a new export folder. No folder was created automatically."
            case .destinationMissingOrInaccessible:
                status = "The stored destination is missing or inaccessible. It was not replaced."
            case .destinationTrashed:
                status = "The stored destination is trashed. It was not replaced."
            case .destinationSetupFailed:
                status = "The destination could not be prepared. No duplicate folder or export was created."
            case .nutritionSourceUnavailable:
                status = "The exact saved nutrition source is no longer visible. No all-source fallback was used."
            case .healthDataUnavailable:
                status = "Health data is unavailable on this device. No JSON or Drive request was created."
            case .notesUnavailable:
                status = "Saved notes are unavailable. No preview or Drive request was created."
            case .notesChanged:
                status = "Saved notes changed during refresh. Refresh and review a new preview."
            case .canonicalRecovery:
                status = "Canonical file identity needs contextual recovery before export."
            case .unexpected:
                status = "Preparation failed. No export or background retry ran."
            }
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
        presentationState = .needsAttention(.notesChanged)
        status = "Saved notes changed. Refresh and review a new preview before exporting."
    }
}

private extension DailyDriveSessionController.AuthorizationPurpose {
    var driveAuthorizationPurpose: DriveAuthorizationRequest.Purpose {
        switch self {
        case .connect: .connect
        case .chooseFolder: .chooseFolder
        case .recoverFile: .recoverFile
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
        case .recovered(let dataAsOf), .alreadyTracked(let dataAsOf),
             .migrated(let dataAsOf):
            "Recovered and verified through \(dataAsOf)"
        }
    }

    var userFacingLabel: String {
        switch self {
        case .recovered(let dataAsOf):
            "Explicit recovery verified the selected canonical file through \(dataAsOf)."
        case .alreadyTracked(let dataAsOf):
            "The selected canonical file was already tracked and reverified through \(dataAsOf)."
        case .migrated(let dataAsOf):
            "The selected canonical file was safely migrated to this destination and verified through \(dataAsOf)."
        }
    }
}

private extension DailyDriveExportFailure {
    var userFacingLabel: String {
        switch self {
        case .busy: "Another export or reconciliation is active."
        case .invalidPayload: "The preview is not canonical daily-export JSON."
        case .staleSnapshot: "A stale or conflicting snapshot was rejected; the last verified file is unchanged."
        case .destinationChangeRequiresMigration: "The selected destination differs from this date's canonical file identity. Explicitly recover that JSON file to migrate it safely."
        case .accountMismatch: "Export is blocked by a Google account mismatch."
        case .identityRecoveryAmbiguous: "Export is blocked because canonical identity recovery is ambiguous."
        case .staleCompletion: "A stale completion was rejected; the last verified file was preserved."
        case .credentials(let reason): "Google credentials are \(reason.rawValue). Reconnect before exporting."
        case .credentialsRejected: "Google credentials were expired, denied or revoked. Reconnect before exporting."
        case .permissionDenied: "Google denied the operation. No broader permission will be requested."
        case .quotaExceeded: "Drive quota is exhausted. No retry was queued."
        case .rateLimited: "Drive rate-limited the request. No background retry was queued."
        case .remoteMissing: "The stored Drive file is missing or inaccessible. Confirm an explicit override before creating a replacement."
        case .remoteMoved: "The canonical file moved outside the validated destination. Choose its current folder, then explicitly recover that JSON file."
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
