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
        DailyExportStatusCatalogue.resolve(error).presentationState
            ?? .needsAttention(.unexpected)
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
    /// Metric and workout counts of the reviewed envelope (#217); display only.
    let included: DailyExportIncludedSummary
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
    @Published private(set) var preview: DailyHealthExportResult? {
        // The food file shares the health file's refresh (#287): discarding the health snapshot
        // discards the food one, except when the health file was just verified.
        didSet { if preview == nil, !retainingFoodAfterHealthVerification { refreshedFood = .notPrepared } }
    }
    @Published private(set) var selectedReportDay: DailyNoteDayID?
    /// Food log (#287): on by default when Drive is connected; the person can switch it off.
    @Published private(set) var foodLogEnabled: Bool
    /// The food file prepared by the latest refresh, whether or not Food log is on.
    @Published private var refreshedFood: DailyFoodExportPreparation = .notPrepared
    /// The latest food export attempt, independent of the health result.
    @Published private(set) var lastFoodExportOutcome: DailyExportOutcomeRecord?
    /// The selected day's verified food export recorded on this iPhone (food registry only).
    @Published private(set) var lastFoodExportOfSelectedDay: DailyExportLastExportLookup?
    @Published private(set) var foodFileReplacementReason: FileReplacementReason?
    private var retainingFoodAfterHealthVerification = false
    /// Set by Cancel export for the whole Export action, so a food file that has not started
    /// yet is never sent after the person cancelled (the food coordinator is idle until then).
    private var exportCancellationRequested = false

    /// What Export sends as the food file: off, unavailable in this build, blocked or prepared.
    var foodPreparation: DailyFoodExportPreparation {
        guard foodExport.isAvailable else { return .unavailable }
        guard foodLogEnabled else { return .off }
        return refreshedFood
    }

    var foodLogAvailable: Bool { foodExport.isAvailable }

    func setFoodLogEnabled(_ enabled: Bool) {
        guard !busy, foodExport.isAvailable, enabled != foodLogEnabled else { return }
        foodLogEnabled = enabled
        foodLogPreference.saveFoodLogEnabled(enabled)
    }
    var availableReportDays: [DailyNoteDayID] { exportService.availableReportDays() }

    /// Re-applies the export's selected day to the shared notes controller when
    /// Export appears, after Home's today notes may have shown another day (#199).
    func reassertReportDay() {
        notes.selectReportDay(selectedReportDay)
    }

    func selectReportDay(_ day: DailyNoteDayID?) {
        guard !busy else { return }
        if let day, !availableReportDays.contains(day) { return }
        selectedReportDay = day
        notes.selectReportDay(day)
        preview = nil
        lastExportOutcome = nil
        destinationCoordinator.clearFileReplacementCandidate(unlessReportDate: day?.reportDate ?? "")
        mirrorDestinationState()
        refreshLastExportOfSelectedDay()
        switch presentationState {
        case .needsAttention(.configurationUnavailable):
            // Drive cannot be set up in this build; the day change does not alter that.
            status = DailyExportStatusCatalogue.status(
                for: presentationState,
                hasStoredSession: oauthSession.hasStoredSession
            )
        case .needsGoogleConnection:
            // Still not set up: keep that state rather than offering a retry.
            status = "Report date changed. Connect Google in Settings, Export, to prepare and export this day."
        default:
            presentationState = .needsAttention(.notesChanged)
            status = "Report date changed. Choose Retry preparation to prepare a new snapshot before exporting."
        }
    }
    /// Session-wide label kept for Developer tools; Export shows
    /// `lastExportOfSelectedDay` instead (#217).
    @Published private(set) var lastVerifiedLabel = "No verified Drive upload in this session"
    /// The selected day's verified export recorded on this iPhone, read from
    /// the local registry only (#217). `nil` with no account or no active folder.
    @Published private(set) var lastExportOfSelectedDay: DailyExportLastExportLookup?
    /// The typed outcome of the latest export attempt. Set only in
    /// `applyExportOutcome`; cleared on day change, saved-note invalidation,
    /// sign-out, revocation, an authorisation error, `prepareForPresentation()`
    /// and whenever a new preview is installed.
    @Published private(set) var lastExportOutcome: DailyExportOutcomeRecord? {
        // A cleared health result clears the food result too: both belonged to the old snapshot.
        didSet { if lastExportOutcome == nil { lastFoodExportOutcome = nil } }
    }
    @Published private(set) var canForgetTrashedDestination = false
    @Published private(set) var fileReplacementReason: FileReplacementReason?
    @Published private(set) var nutritionSources: [NutritionSource] = []
    @Published private(set) var selectedNutritionSourceBundleIdentifier: String?
    @Published private(set) var presentationState: DailyExportPresentationState = .preparing

    let notes: DailyNotesController
    private(set) var exactJSONConstructionCount = 0

    var isConfigured: Bool { (try? oauthConfiguration()) != nil }
    /// The same check against the main bundle, for building Settings before any session exists.
    /// Reads Info.plist only; no request.
    static var bundleHasOAuthConfiguration: Bool { (try? DriveOAuthClientConfiguration.fromMainBundle()) != nil }
    /// Export is available while either file of the prepared snapshot is still unsent, so a
    /// failure in one retries only that file.
    var canExport: Bool {
        (previewIsCurrent || foodPreparation.preview != nil)
            && account != nil && activeDestination != nil && !busy
            && presentationState == .readyToExport
    }
    var previewSummary: DailyExportPreviewSummary? {
        guard let preview,
              let nutrition = preview.envelope.today.nutrition,
              let context = preview.envelope.appContext.nutrition else { return nil }
        return DailyExportPreviewSummary(
            reportDate: preview.envelope.reportDate,
            dataAsOf: preview.envelope.dataAsOf,
            nutritionSource: "\(nutrition.source.name) · \(nutrition.source.bundleIdentifier)",
            savedNoteCount: preview.envelope.today.notes?.count ?? 0,
            currentWindow: "\(context.currentWindow.start) to \(context.currentWindow.end)",
            previousWindow: "\(context.previousWindow.start) to \(context.previousWindow.end)",
            encodedByteCount: preview.bytes.count,
            included: DailyExportIncludedSummary.make(today: preview.envelope.today)
        )
    }
    var nutritionSourceLabel: String {
        guard let selectedNutritionSourceBundleIdentifier else {
            return "No source selected"
        }
        guard let source = nutritionSources.first(where: {
            $0.bundleIdentifier == selectedNutritionSourceBundleIdentifier
        }) else {
            return "Saved source unavailable · \(selectedNutritionSourceBundleIdentifier)"
        }
        return "\(source.name) · \(source.bundleIdentifier)"
    }
    var canRefreshPreview: Bool {
        !busy && notes.storageAvailable && nutritionSources.contains {
            $0.bundleIdentifier == selectedNutritionSourceBundleIdentifier
        }
    }

    private let oauthSession: any DriveOAuthSessionProviding
    private let loadOAuthConfiguration: () throws -> DriveOAuthClientConfiguration
    private let drive: any DailyDriveSessionTransporting
    private let destinationCoordinator: DailyDestinationCoordinator
    private let exportService: DailyHealthExportService
    private let identityStore: any DailyDriveExportIdentityPersisting
    private let exportCoordinator: DailyDriveExportCoordinator
    private let foodIdentityStore: any DailyDriveExportIdentityPersisting
    private let foodExportCoordinator: DailyDriveExportCoordinator
    private let foodExport: DailyFoodExportService
    private let foodLogPreference: any DailyFoodLogPreferencePersisting
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

    convenience init(foodLedger: (any DailyFoodLedgerSnapshotReading)? = nil) {
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
            notes: notes,
            foodIdentityStore: KeychainDailyDriveExportIdentityStore.food(keychain: keychain),
            foodExport: DailyFoodExportService(reader: foodLedger),
            foodLogPreference: UserDefaultsDailyFoodLogPreference()
        )
    }

    init(
        keychain: any DailyDriveSecurePersisting,
        drive: any DailyDriveSessionTransporting,
        exportService: DailyHealthExportService,
        identityStore: any DailyDriveExportIdentityPersisting,
        nutritionSourceSelection: any NutritionSourceSelectionPersisting,
        notes: DailyNotesController,
        oauthSession: (any DriveOAuthSessionProviding)? = nil,
        oauthConfiguration: @escaping () throws -> DriveOAuthClientConfiguration = {
            try DriveOAuthClientConfiguration.fromMainBundle()
        },
        foodIdentityStore: (any DailyDriveExportIdentityPersisting)? = nil,
        foodExport: DailyFoodExportService = .unavailable,
        foodLogPreference: any DailyFoodLogPreferencePersisting = MemoryDailyFoodLogPreference()
    ) {
        self.oauthSession = oauthSession ?? AppAuthDriveSession(
            secureStore: keychain,
            authKey: Self.authKey
        )
        loadOAuthConfiguration = oauthConfiguration
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
        let foodStore = foodIdentityStore ?? KeychainDailyDriveExportIdentityStore.food(keychain: keychain)
        self.foodIdentityStore = foodStore
        foodExportCoordinator = DailyDriveExportCoordinator(
            transport: drive,
            store: foodStore,
            policy: DailyFoodExportIdentityPolicy()
        )
        self.foodExport = foodExport
        self.foodLogPreference = foodLogPreference
        foodLogEnabled = foodExport.isAvailable && foodLogPreference.loadFoodLogEnabled()
        super.init()
        self.oauthSession.onAuthorizationError = { [weak self] failure in
            guard let self else { return }
            self.preview = nil
            self.lastExportOutcome = nil
            self.presentationState = .needsGoogleConnection
            self.status = DailyDriveExportFailure.credentials(failure).userFacingLabel
        }
        notes.onSavedNotesMutation = { [weak self] snapshot in
            self?.invalidatePreview(after: snapshot)
        }
        selectedNutritionSourceBundleIdentifier = nutritionSourceSelection.loadBundleIdentifier()
        restoreLocalStateWithoutNetwork()
        if !isConfigured {
            applyPresentationState(.needsAttention(.configurationUnavailable))
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
        await surviveCallerCancellation { await self.performPrepareForPresentation() }
    }

    /// Runs a HealthKit-reading operation in its own unstructured task. A
    /// caller's cancellation (a view task ending) would otherwise reach the
    /// export service's cancellation checks and be shown as a failed or
    /// unavailable state. `busy` still serialises these operations.
    private func surviveCallerCancellation(_ work: @escaping @MainActor () async -> Void) async {
        let task = Task { await work() }
        await task.value
    }

    private func performPrepareForPresentation() async {
        if !busy { lastExportOutcome = nil }
        guard !busy, isConfigured else {
            if !isConfigured {
                applyPresentationState(.needsAttention(.configurationUnavailable))
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

            // The food registry follows the health registry on every lifecycle path (#287). Food
            // goes first: if it fails, nothing is abandoned and the action can be retried as is.
            try await self.foodExportCoordinator.abandonDestination(
                accountID: candidate.accountID,
                folderID: candidate.folderID
            )
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
        await surviveCallerCancellation { await self.performRefreshPreview() }
    }

    private func performRefreshPreview() async {
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
        await surviveCallerCancellation { await self.performRefreshNutritionSources() }
    }

    private func performRefreshNutritionSources() async {
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

    /// Whether this run has validated a Google account (no request is made).
    var hasValidatedAccount: Bool { account != nil }

    /// The food file's exact bytes as text, built only when viewed.
    func makeExactFoodPreviewText() -> String? {
        guard let food = foodPreparation.preview else { return nil }
        return String(data: food.bytes, encoding: .utf8)
    }

    /// Per-file results appear once a food export ran or Food log is on beside a health result.
    var showsPerFileResults: Bool {
        lastFoodExportOutcome != nil || (lastExportOutcome != nil && foodLogEnabled && foodExport.isAvailable)
    }

    func makeExactPreviewText() -> String? {
        guard let preview else { return nil }
        exactJSONConstructionCount += 1
        return String(data: preview.bytes, encoding: .utf8)
    }

    /// Sends the health file first, then the food file (D3). Each is verified on its own and keeps
    /// its own result; a failure in one never marks the other as failed. A file already verified
    /// from this snapshot is not sent again.
    func exportPreview() async {
        let health = previewIsCurrent ? preview : nil
        let food = foodPreparation.preview
        guard health != nil || food != nil,
              let account, let destination = activeDestination else {
            status = "Refresh a preview and validate an account and destination before export."
            return
        }
        await run("Submitting the reviewed preview and verifying Drive…") {
            self.exporting = true
            self.exportCancellationRequested = false
            defer {
                self.exporting = false
                self.exportCancellationRequested = false
            }
            var healthError: Error?
            if let health {
                do {
                    try await self.exportHealth(health, account: account, destination: destination)
                } catch {
                    healthError = error
                }
            }
            if let food {
                if self.exportCancellationRequested {
                    self.applyFoodExportOutcome(.success(.cancelledBeforeSubmission), exportedFood: food,
                                                accountID: account.id, folderID: destination.folderID)
                } else {
                    await self.exportFood(food, account: account, destination: destination)
                }
            }
            if let healthError { throw healthError }
        }
    }

    private func exportHealth(
        _ preview: DailyHealthExportResult,
        account: DailyDriveAccount,
        destination: DailyDestinationBinding
    ) async throws {
        let result: DailyDriveExportResult
        do {
            result = try await exportCoordinator.export(
                payload: preview.bytes,
                reportDate: preview.envelope.reportDate,
                accountID: account.id,
                folderID: destination.folderID,
                tokenProvider: { forceRefresh in
                    try await self.freshAccessToken(forceRefresh: forceRefresh)
                }
            )
        } catch DailyDriveExportFailure.remoteTrashed {
            destinationCoordinator.markFileForReplacement(
                accountID: account.id,
                folderID: destination.folderID,
                reportDate: preview.envelope.reportDate,
                reason: .trashed
            )
            mirrorDestinationState()
            try applyExportOutcome(.failure(.remoteTrashed), exportedPreview: preview)
            return
        } catch DailyDriveExportFailure.remoteMissing {
            destinationCoordinator.markFileForReplacement(
                accountID: account.id,
                folderID: destination.folderID,
                reportDate: preview.envelope.reportDate,
                reason: .missingOrInaccessible
            )
            mirrorDestinationState()
            try applyExportOutcome(.failure(.remoteMissing), exportedPreview: preview)
            return
        } catch let failure as DailyDriveExportFailure {
            try applyExportOutcome(.failure(failure), exportedPreview: preview)
            return
        }
        destinationCoordinator.clearFileReplacementCandidate(
            accountID: account.id,
            folderID: destination.folderID,
            reportDate: preview.envelope.reportDate,
            documentType: .health
        )
        mirrorDestinationState()
        try applyExportOutcome(.success(result), exportedPreview: preview)
    }

    private func exportFood(
        _ food: DailyFoodExportPreview,
        account: DailyDriveAccount,
        destination: DailyDestinationBinding
    ) async {
        let outcome: Result<DailyDriveExportResult, Error>
        do {
            outcome = .success(try await foodExportCoordinator.export(
                payload: food.bytes,
                reportDate: food.reportDate,
                accountID: account.id,
                folderID: destination.folderID,
                tokenProvider: { forceRefresh in
                    try await self.freshAccessToken(forceRefresh: forceRefresh)
                }
            ))
        } catch {
            outcome = .failure(error)
        }
        applyFoodExportOutcome(outcome, exportedFood: food, accountID: account.id, folderID: destination.folderID)
    }

    /// Records the food file's own result. Note cleanup stays bound to the health file alone.
    /// A food failure changes the screen's state only when the person must act (reconnect or
    /// recover a file); otherwise Export stays available to retry the food file.
    func applyFoodExportOutcome(
        _ outcome: Result<DailyDriveExportResult, Error>,
        exportedFood: DailyFoodExportPreview,
        accountID: String,
        folderID: String
    ) {
        switch outcome {
        case .success(let result):
            lastFoodExportOutcome = DailyExportOutcomeRecord(
                outcome: .success(result),
                reportDate: exportedFood.reportDate,
                attemptedDataAsOf: exportedFood.orderingToken
            )
            destinationCoordinator.clearFileReplacementCandidate(
                accountID: accountID,
                folderID: folderID,
                reportDate: exportedFood.reportDate,
                documentType: .food
            )
            if result.authorizesNoteCleanup, refreshedFood.preview == exportedFood {
                refreshedFood = .notPrepared
            }
            status += " Food file: \(result.foodUserFacingLabel)"
        case .failure(let error):
            let failure = error as? DailyDriveExportFailure
            lastFoodExportOutcome = DailyExportOutcomeRecord(
                outcome: .failure(failure ?? .transportFailure),
                reportDate: exportedFood.reportDate,
                attemptedDataAsOf: exportedFood.orderingToken
            )
            if failure == .remoteTrashed || failure == .remoteMissing {
                destinationCoordinator.markFileForReplacement(
                    accountID: accountID,
                    folderID: folderID,
                    reportDate: exportedFood.reportDate,
                    reason: failure == .remoteTrashed ? .trashed : .missingOrInaccessible,
                    documentType: .food
                )
            }
            let resolution = DailyExportStatusCatalogue.resolve(error)
            switch resolution.presentationState {
            case .needsGoogleConnection?, .needsAttention(.canonicalRecovery)?:
                presentationState = resolution.presentationState ?? presentationState
            default:
                break
            }
            status += " Food file: \(resolution.statusOverride ?? "Export failed. No background retry was queued.")"
        }
        mirrorDestinationState()
        refreshLastExportOfSelectedDay()
    }

    func applyExportOutcome(
        _ outcome: Result<DailyDriveExportResult, DailyDriveExportFailure>,
        exportedPreview: DailyHealthExportResult
    ) throws {
        lastExportOutcome = DailyExportOutcomeRecord(
            outcome: outcome,
            exportedPreview: exportedPreview
        )
        refreshLastExportOfSelectedDay()
        let result = try outcome.get()
        lastVerifiedLabel = result.verifiedLabel
        status = result.userFacingLabel
        guard result.authorizesNoteCleanup else { return }
        status += " Report date: \(exportedPreview.envelope.reportDate)."

        if !notes.markVerified(
            snapshot: exportedPreview.notesSnapshot,
            payload: exportedPreview.bytes
        ) {
            status += " Current notes were retained because their verified cleanup marker was not saved."
        }
        if preview == exportedPreview {
            retainingFoodAfterHealthVerification = true
            preview = nil
            retainingFoodAfterHealthVerification = false
        }
    }

    /// Forgets only the identity of `documentType`'s file for that date (#287): a missing food
    /// file never abandons the health identity, and the reverse.
    func confirmFileReplacementOverride(documentType: DailyExportDocumentType = .health) async {
        await run("Forgetting the unavailable file identity…") {
            let context = try await self.currentContext()
            guard let candidate = self.destinationCoordinator.fileReplacementCandidate(
                    accountID: context.account.id,
                    folderID: self.activeDestination?.folderID,
                    documentType: documentType
                  ),
                  let reason = self.destinationCoordinator.fileReplacementReason(for: documentType),
                  candidate.accountID == context.account.id,
                  self.activeDestination?.folderID == candidate.folderID else {
                throw Failure.noDestination
            }

            try await self.coordinator(for: documentType).abandonFileIdentity(
                accountID: candidate.accountID,
                folderID: candidate.folderID,
                reportDate: candidate.reportDate
            )
            self.destinationCoordinator.clearFileReplacementCandidate(documentType: documentType)
            self.mirrorDestinationState()
            self.restoreLastVerifiedLabel(for: context.account.id)
            let file = documentType == .food ? "food file" : "daily file"
            switch reason {
            case .trashed:
                self.status = "Forgot the trashed \(file) identity. Export the matching date again to create a fresh canonical file; no Drive item was changed."
            case .missingOrInaccessible:
                self.status = "Explicit override accepted for the missing or inaccessible \(file). Export the matching date again to create a new canonical file ID; no Drive item was changed."
            }
        }
    }

    private func coordinator(for documentType: DailyExportDocumentType) -> DailyDriveExportCoordinator {
        switch documentType {
        case .health: exportCoordinator
        case .food: foodExportCoordinator
        }
    }

    func cancelExport() {
        guard exporting else { return }
        exportCancellationRequested = true
        status = "Cancellation requested. If submission began, verification must finish before the result is known."
        Task {
            await exportCoordinator.requestCancellation()
            await foodExportCoordinator.requestCancellation()
        }
    }

    func recoverSelectedFile(documentType: DailyExportDocumentType = .health) async {
        if documentType == .food {
            await recoverSelectedFoodFile()
            return
        }
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
                reportDate: preview.envelope.reportDate,
                documentType: .health
            )
            self.mirrorDestinationState()
            self.lastVerifiedLabel = recovery.verifiedLabel
            self.identityRecoveryRequired = false
            self.refreshLastExportOfSelectedDay()
            self.presentationState = .readyToExport
            self.status = recovery.userFacingLabel
        }
    }

    /// The food registry recovers on its own through the same Picker path (#287).
    private func recoverSelectedFoodFile() async {
        guard let food = refreshedFood.preview, let destination = activeDestination else {
            status = "Refresh the matching report date with Food log on and validate a destination before recovery."
            return
        }
        await run("Opening explicit food-file recovery…") {
            let result = try await self.authorize(
                .recoverFile,
                expectedAccountID: destination.accountID
            )
            guard let selectedFileID = result.pickedItemID else {
                throw DailyDriveExportFailure.identityRecoveryAmbiguous
            }
            let recovery = try await self.foodExportCoordinator.recover(
                selectedFileID: selectedFileID,
                reportDate: food.reportDate,
                accountID: result.account.id,
                folderID: destination.folderID,
                tokenProvider: { forceRefresh in
                    try await self.freshAccessToken(forceRefresh: forceRefresh)
                }
            )
            self.destinationCoordinator.clearFileReplacementCandidate(
                accountID: result.account.id,
                folderID: destination.folderID,
                reportDate: food.reportDate,
                documentType: .food
            )
            self.mirrorDestinationState()
            self.refreshLastExportOfSelectedDay()
            if !self.identityRecoveryRequired { self.presentationState = .readyToExport }
            self.status = "Food file: \(recovery.foodUserFacingLabel)"
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
            lastExportOfSelectedDay = nil
            lastFoodExportOfSelectedDay = nil
            preview = nil
            lastExportOutcome = nil
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
                self.lastExportOfSelectedDay = nil
                self.lastFoodExportOfSelectedDay = nil
                self.preview = nil
                self.lastExportOutcome = nil
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
                nutritionSourceBundleIdentifier: bundleIdentifier,
                selectedDay: selectedReportDay
            )
            destinationCoordinator.clearFileReplacementCandidate(
                unlessReportDate: result.envelope.reportDate
            )
            mirrorDestinationState()
            preview = result
            // The food file is built from the same refresh: the same report date, zone and
            // instants, and the ledger as it is now (#287). Building it sends nothing.
            refreshedFood = foodExport.prepare(matching: result.envelope)
            // A fresh exportable preview supersedes the previous attempt's result.
            lastExportOutcome = nil
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
            return try loadOAuthConfiguration()
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
        accountLabel = "\(account.displayName) · \(account.emailAddress)"
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
        foodFileReplacementReason = destinationCoordinator.fileReplacementReason(for: .food)
        if let account {
            destinationLabel = destinationCoordinator.destinationLabel(for: account.id)
        }
    }

    private func restoreLastVerifiedLabel(for accountID: String) {
        do {
            let folderID = destinationCoordinator.activeDestination(for: accountID)?.folderID
            let registry = try identityStore.load()
            lastExportOfSelectedDay = lastVerifiedExport(
                for: selectedReportDate,
                accountID: accountID,
                folderID: folderID,
                registry: { registry }
            )
            lastFoodExportOfSelectedDay = lastVerifiedExport(
                for: selectedReportDate,
                accountID: accountID,
                folderID: folderID,
                registry: { try self.foodIdentityStore.load() }
            )
            let latest = registry?.identities
                .filter { $0.accountID == accountID && $0.folderID == folderID }
                .compactMap(\.lastVerified)
                .max { $0.verifiedAt < $1.verifiedAt }
            if let latest {
                lastVerifiedLabel = "Persisted verification through \(DailyHealthExportIdentityPolicy.displayOrderingToken(latest.dataAsOf))"
            } else {
                lastVerifiedLabel = "No verified Drive upload for this destination"
            }
            identityRecoveryRequired = false
        } catch {
            lastVerifiedLabel = "Stored identity is ambiguous; explicit recovery required"
            identityRecoveryRequired = true
            lastExportOfSelectedDay = lastVerifiedExport(
                for: selectedReportDate,
                accountID: accountID,
                folderID: destinationCoordinator.activeDestination(for: accountID)?.folderID,
                registry: { throw error }
            )
            lastFoodExportOfSelectedDay = lastVerifiedExport(
                for: selectedReportDate,
                accountID: accountID,
                folderID: destinationCoordinator.activeDestination(for: accountID)?.folderID,
                registry: { try self.foodIdentityStore.load() }
            )
        }
    }

    /// The selected export day's report date: the chosen previous day, or today.
    private var selectedReportDate: String? {
        selectedReportDay?.reportDate ?? availableReportDays.first?.reportDate
    }

    /// The verified export of `reportDate` recorded on this iPhone for the
    /// connected account and active folder (#217). A local Keychain read only:
    /// no Drive, network or token request. `nil` with no account restored or no
    /// active folder. Read, never written.
    func lastVerifiedExport(for reportDate: String) -> DailyExportLastExportLookup? {
        lastVerifiedExport(
            for: reportDate,
            accountID: account?.id,
            folderID: activeDestination?.folderID,
            registry: { try self.identityStore.load() }
        )
    }

    private func refreshLastExportOfSelectedDay() {
        guard let reportDate = selectedReportDate else {
            lastExportOfSelectedDay = nil
            lastFoodExportOfSelectedDay = nil
            return
        }
        lastExportOfSelectedDay = lastVerifiedExport(for: reportDate)
        lastFoodExportOfSelectedDay = lastVerifiedFoodExport(for: reportDate)
    }

    /// The food registry's record of `reportDate` (#287): a local Keychain read only.
    func lastVerifiedFoodExport(for reportDate: String) -> DailyExportLastExportLookup? {
        lastVerifiedExport(
            for: reportDate,
            accountID: account?.id,
            folderID: activeDestination?.folderID,
            registry: { try self.foodIdentityStore.load() }
        )
    }

    /// The food file's Drive record for `reportDate` in the active folder, for Developer tools.
    /// A local Keychain read; nil when none is tracked or the registry cannot be read.
    func foodDriveRecord(for reportDate: String) -> DailyFoodDriveRecord? {
        guard let accountID = account?.id, let folderID = activeDestination?.folderID else { return nil }
        let matches = ((try? foodIdentityStore.load())??.identities ?? []).filter {
            $0.accountID == accountID && $0.folderID == folderID && $0.reportDate == reportDate
        }
        guard matches.count == 1 else { return nil }
        return DailyFoodDriveRecord(fileID: matches[0].fileID, lastVerifiedToken: matches[0].lastVerified?.dataAsOf)
    }

    private func lastVerifiedExport(
        for reportDate: String?,
        accountID: String?,
        folderID: String?,
        registry load: () throws -> DailyDriveExportRegistry?
    ) -> DailyExportLastExportLookup? {
        guard let reportDate, let accountID, let folderID else { return nil }
        let matches: [DailyDriveExportIdentity]
        do {
            matches = (try load()?.identities ?? []).filter {
                $0.accountID == accountID && $0.folderID == folderID && $0.reportDate == reportDate
            }
        } catch {
            return DailyExportLastExportLookup(reportDate: reportDate, state: .unknown, hasPendingOperation: false)
        }
        guard matches.count <= 1 else {
            return DailyExportLastExportLookup(reportDate: reportDate, state: .unknown, hasPendingOperation: false)
        }
        let identity = matches.first
        let state: DailyExportLastExport = identity?.lastVerified.map {
            .verified(verifiedAt: $0.verifiedAt, dataAsOf: $0.dataAsOf)
        } ?? .none
        return DailyExportLastExportLookup(
            reportDate: reportDate,
            state: state,
            hasPendingOperation: identity?.pending != nil
        )
    }

    private func run(_ startingStatus: String, operation: () async throws -> Void) async {
        guard !busy else { return }
        busy = true
        status = startingStatus
        defer { busy = false }
        do {
            try await operation()
        } catch {
            let resolution = DailyExportStatusCatalogue.resolve(error)
            if resolution.invalidatesPreview {
                preview = nil
            }
            if let state = resolution.presentationState {
                presentationState = state
                status = resolution.statusOverride ?? DailyExportStatusCatalogue.status(
                    for: state,
                    hasStoredSession: oauthSession.hasStoredSession
                )
            } else if let statusOverride = resolution.statusOverride {
                status = statusOverride
            }
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
        case .readyToExport:
            applyReadyStateAfterPreview()
        case .preparing, .needsGoogleConnection, .needsNutritionSource, .needsAttention:
            status = DailyExportStatusCatalogue.status(
                for: state,
                hasStoredSession: oauthSession.hasStoredSession
            )
        }
    }

    private var previewIsCurrent: Bool {
        guard notes.storageAvailable, let preview else { return false }
        guard preview.notesSnapshot.dayID == (selectedReportDay ?? availableReportDays.first) else { return false }
        return notes.document.snapshot(for: preview.notesSnapshot.dayID) == preview.notesSnapshot
    }

    private func invalidatePreview(after snapshot: DailyNotesSnapshot) {
        guard let preview, preview.notesSnapshot.dayID == snapshot.dayID,
              preview.notesSnapshot != snapshot else { return }
        self.preview = nil
        lastExportOutcome = nil
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

extension DailyExportOutcomeRecord {
    /// Maps every export result and failure. Verified kinds record the cutoff
    /// Drive verified; the others record the cutoff of the attempted snapshot.
    init(
        outcome: Result<DailyDriveExportResult, DailyDriveExportFailure>,
        exportedPreview: DailyHealthExportResult
    ) {
        self.init(
            outcome: outcome,
            reportDate: exportedPreview.envelope.reportDate,
            attemptedDataAsOf: exportedPreview.envelope.dataAsOf
        )
    }

    init(
        outcome: Result<DailyDriveExportResult, DailyDriveExportFailure>,
        reportDate: String,
        attemptedDataAsOf: String
    ) {
        switch outcome {
        case .success(.verified(let dataAsOf, _)):
            self.init(reportDate: reportDate, dataAsOf: dataAsOf, kind: .verified)
        case .success(.unchangedVerified(let dataAsOf)):
            self.init(reportDate: reportDate, dataAsOf: dataAsOf, kind: .unchangedVerified)
        case .success(.cancelledBeforeSubmission):
            self.init(
                reportDate: reportDate,
                dataAsOf: attemptedDataAsOf,
                kind: .cancelledBeforeSubmission
            )
        case .success(.cancelledAfterSubmissionVerified(let dataAsOf, _)):
            self.init(
                reportDate: reportDate,
                dataAsOf: dataAsOf,
                kind: .cancelledAfterSubmissionVerified
            )
        case .failure:
            self.init(reportDate: reportDate, dataAsOf: attemptedDataAsOf, kind: .failed)
        }
    }
}

extension DailyExportPresentationState {
    /// The plain summary `DailyExportPhase` takes.
    var phaseSetup: DailyExportPhase.Setup {
        switch self {
        case .preparing: .preparing
        case .needsGoogleConnection, .needsAttention(.configurationUnavailable): .notSetUp
        case .needsNutritionSource: .needsNutritionSource
        case .readyToExport: .ready
        case .needsAttention: .needsAttention
        }
    }
}

/// The Settings > Export actions, behind a small consumer-owned protocol so a
/// test can prove each button reaches the matching controller method.
@MainActor
protocol DriveDestinationControlling: AnyObject {
    func connect() async
    func signOut()
    func disconnect() async
    func chooseDestination() async
    func createDestination() async
}

extension DailyDriveSessionController: DriveDestinationControlling {}

enum DriveDestinationAction: CaseIterable {
    case connect
    case signOut
    case revoke
    case chooseFolder
    case createFolder

    @MainActor
    func perform(on controller: any DriveDestinationControlling) async {
        switch self {
        case .connect: await controller.connect()
        case .signOut: controller.signOut()
        case .revoke: await controller.disconnect()
        case .chooseFolder: await controller.chooseDestination()
        case .createFolder: await controller.createDestination()
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

private extension UIApplication {
    var activeRootViewController: UIViewController? {
        connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }?
            .windows.first { $0.isKeyWindow }?
            .rootViewController
    }
}
