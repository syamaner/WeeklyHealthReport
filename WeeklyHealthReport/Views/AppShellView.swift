import SwiftUI
import UIKit
import FoodLedgerPresentation

/// Root of the app: one navigation stack from Home, with every destination
/// resolved from `AppRoute`. Lifecycle notifications are observed here and
/// forwarded to the coordinator.
struct AppShellView: View {
    @ObservedObject var viewModel: WeeklyReportViewModel
    @ObservedObject var dailyExport: DailyDriveSessionController
    @ObservedObject var navigation: AppNavigationCoordinator
    @ObservedObject var todaySoFar: TodaySoFarHealthModel
    let foodHome: FoodHomeModel
    let medicationAccess: MedicationAccessRequest
    let foodLedger: FoodLedgerCompositionRoot?
    let settings: AppSettings
    @StateObject private var presentationState = WeeklyReportPresentationState()
    @StateObject private var screenshotController = WeeklyReportScreenshotController()
    @State private var medicationAuthorizationRequest = 0
    @AppStorage("hasRequestedMedicationAccess") private var hasRequestedMedicationAccess = false

    @ViewBuilder
    var body: some View {
        if #available(iOS 26.0, *) {
            shellContent
                .medicationAccessRequest(
                    medicationAccess,
                    trigger: medicationAuthorizationRequest
                ) { result in
                    Task { @MainActor in
                        presentationState.finishMedicationAuthorizationRequest()
                        switch result {
                        case .success:
                            hasRequestedMedicationAccess = true
                            await viewModel.refreshMedications()
                        case .failure(let error):
                            viewModel.setMedicationAuthorizationFailure(
                                error.localizedDescription
                            )
                        }
                    }
                }
                .sheet(isPresented: $presentationState.showsMedicationAccessHelp) {
                    NavigationStack {
                        MedicationAccessHelpView {
                            presentationState.showsMedicationAccessHelp = false
                        }
                    }
                }
        } else {
            shellContent
        }
    }

    private var shellContent: some View {
        NavigationStack(path: Binding(
            get: { navigation.path },
            set: { navigation.acceptPathChange($0) }
        )) {
            HomeView(
                features: homeFeatures,
                now: { foodLedger?.confirmationNow ?? Date() },
                calendar: foodLedger?.confirmationDayCalendar ?? .autoupdatingCurrent,
                dayRefreshed: { [screenshotController] day in screenshotController.todayRefreshedDay = day }
            )
            .navigationTitle("Today")
            .foodLoggedBannerScreen(foodLedger?.loggedBanner)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { navigation.openSettings() } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")
                    .accessibilityIdentifier("settingsButton")
                }
            }
            .navigationDestination(for: AppRoute.self) { route in
                destination(for: route)
            }
            .task {
                // Hosted unit tests launch the app process. Avoid presenting the
                // Health authorization sheet before XCTest can load its bundle.
                guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else {
                    return
                }
                await viewModel.refresh()
                if #available(iOS 26.0, *), !hasRequestedMedicationAccess {
                    presentationState.beginMedicationAuthorizationRequest()
                    medicationAuthorizationRequest += 1
                }
            }
            .onAppear {
                screenshotController.isTodayOnScreen = true
                configureScreenshotProvider()
                FullPageSceneRegistry.shared.attach(screenshotController)
                navigation.restoreIfNeeded(
                    hasDraft: dailyExport.notes.currentDraft != nil,
                    availableRoutes: settings.availableRoutes
                )
                syncNotesPin()
            }
            .onDisappear {
                screenshotController.isTodayOnScreen = false
                // Home leaving the window (a push) must not affect registration.
                FullPageSceneRegistry.shared.refresh()
            }
            .onChange(of: navigation.path) { _, path in
                foodLedger?.loggedBanner.navigated(to: path)
                navigation.recordDestination()
                syncNotesPin()
                // Cheap and idempotent: the screen that may be captured next is registered.
                FullPageSceneRegistry.shared.refresh()
            }
            .onReceive(
                NotificationCenter.default.publisher(
                    for: UIApplication.willResignActiveNotification
                )
            ) { _ in
                navigation.willResignActive()
            }
            .onReceive(
                NotificationCenter.default.publisher(
                    for: UIApplication.didBecomeActiveNotification
                )
            ) { _ in
                FullPageSceneRegistry.shared.refresh()
                navigation.didBecomeActive(
                    hasDraft: dailyExport.notes.currentDraft != nil,
                    availableRoutes: settings.availableRoutes
                )
            }
        }
        .overlay(alignment: .bottom) {
            if let foodLedger { FoodLoggedBannerHost(banner: foodLedger.loggedBanner, navigation: navigation, foodHome: foodHome) }
        }
    }

    /// Home's features in one place; `HomeView` only sorts and renders their cards.
    private var homeFeatures: [HomeFeature] {
        Self.homeFeatures(foodHome: foodHome, todaySoFar: todaySoFar, notes: dailyExport.notes)
    }

    /// Home's features from their models; also used by Today's Full Page so the
    /// PDF reads the same current card content as the screen.
    private static func homeFeatures(
        foodHome: FoodHomeModel,
        todaySoFar: TodaySoFarHealthModel,
        notes: DailyNotesController
    ) -> [HomeFeature] {
        [
            FoodHomeCards.feature(model: foodHome),
            TodaySoFarHealthCardView.feature(model: todaySoFar, readsHealthData: !isHostedUnitTest),
            NotesHomeCard.feature(controller: notes)
        ]
    }

    /// Hosted unit tests launch the app process; never present the Health sheet
    /// or read HealthKit there.
    private static var isHostedUnitTest: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    /// Pins the shared notes controller to today while Home's today notes are open,
    /// and restores the export's selected day when they close (#199, D11).
    private func syncNotesPin() {
        let pinned = AppRoute.pinsNotesToToday(navigation.path)
        guard pinned != dailyExport.notes.isPinnedToToday else { return }
        if pinned { dailyExport.notes.pinToday() } else { dailyExport.notes.unpinToday() }
    }

    @ViewBuilder
    private func destination(for route: AppRoute) -> some View {
        switch route {
        case .foodLog:
            if let foodLedger { FoodLogView(root: foodLedger, navigation: navigation) }
            else { ContentUnavailableView("Food log unavailable", systemImage: "exclamationmark.triangle", description: Text("The local food ledger could not be opened.")) }
        case .healthReport:
            HealthReportView(viewModel: viewModel, presentationState: presentationState)
                .navigationTitle("Health report")
        case .dailyExport:
            DailyExportView(session: dailyExport) { navigation.openDriveSetupFromExport() }
        case .genericFoodSearch:
            if let foodLedger,
               let flow = GenericFoodSearchFlowView(root: foodLedger) {
                flow
            } else {
                ContentUnavailableView(
                    "Food search unavailable",
                    systemImage: "exclamationmark.triangle",
                    description: Text("The local food ledger could not be opened.")
                )
            }
        case .foodListImport:
            if let foodLedger, let flow = FoodListImportFlowView(root: foodLedger) {
                flow
            } else {
                ContentUnavailableView("Food list unavailable", systemImage: "exclamationmark.triangle")
            }
        case .barcodeFoodCapture:
            if let foodLedger { BarcodeFoodFlowView(root: foodLedger) }
            else { ContentUnavailableView("Food scanner unavailable", systemImage: "exclamationmark.triangle") }
        case .inventoryReview:
            if let foodLedger, let flow = LocalInventoryFlowView(root: foodLedger) { flow }
            else { ContentUnavailableView("Receipt review unavailable", systemImage: "exclamationmark.triangle", description: Text("The local inventory store could not be opened. Food search remains separate.")) }
        case .commonFoods:
            if let foodLedger, let flow = CommonFoodsFlowView(root: foodLedger) { flow }
            else { ContentUnavailableView("Usual foods unavailable", systemImage: "exclamationmark.triangle", description: Text("Your usual foods could not be opened. Try again after unlocking your device.")) }
        case .foodReresolution:
            if let foodLedger, let flow = FoodReresolutionFlowView(root: foodLedger) { flow }
            else { ContentUnavailableView("Nutrition review unavailable", systemImage: "exclamationmark.triangle") }
        case .notes:
            DailyNotesView(
                controller: dailyExport.notes,
                openEditor: { navigation.append(.noteEditor) }
            )
        case .todayNotes:
            DailyNotesView(
                controller: dailyExport.notes,
                openEditor: { navigation.append(.todayNoteEditor) }
            )
        case .todayNoteEditor:
            DailyNoteEditorView(
                controller: dailyExport.notes,
                willOpenApplicationSettings: {
                    navigation.protectCurrentPath()
                }
            )
        case .noteEditor:
            DailyNoteEditorView(
                controller: dailyExport.notes,
                willOpenApplicationSettings: {
                    navigation.protectCurrentPath()
                }
            )
        case .privacy:
            PrivacyPolicyView()
        case .diagnostics:
            DeveloperDiagnosticsView(viewModel: viewModel, todaySoFar: todaySoFar)
        case .settings:
            SettingsView(settings: settings)
        case .webLookupKey:
            if let foodLedger { OpenRouterFoodKeyView(model: foodLedger.webDiscovery, showsDone: false) }
            else { ContentUnavailableView("Web lookup unavailable", systemImage: "exclamationmark.triangle", description: Text("The local food ledger could not be opened.")) }
        case .foodMarket:
            if let foodLedger { FoodMarketSelectionView(preference: foodLedger.foodMarket) }
            else { ContentUnavailableView("Food market unavailable", systemImage: "exclamationmark.triangle", description: Text("The local food ledger could not be opened.")) }
        case .dataBackup:
            if let foodLedger, let view = InventoryBackupView(root: foodLedger) { view }
            else { ContentUnavailableView("Backup unavailable", systemImage: "exclamationmark.triangle", description: Text("The local inventory store could not be opened.")) }
        case .medicationAccess:
            MedicationAccessHelpView()
        case .developerTools:
            DeveloperToolsSettingsView(toggle: settings.developerTools, diagnostics: foodLedger?.searchDiagnostics,
                                       driveExportConfigured: dailyExport.isConfigured)
        case .addFood:
            if let foodLedger {
                AddFoodFlowView(root: foodLedger, finish: FoodEntryFinish(entryDay: navigation.addFoodEntryDay) { day in
                    navigation.finishFoodEntry(reportingDay: day)
                })
            }
            else { ContentUnavailableView("Add food unavailable", systemImage: "exclamationmark.triangle", description: Text("The local food ledger could not be opened.")) }
        case .exportDestination:
            DriveDestinationSettingsView(session: dailyExport,
                                         returnToExport: navigation.exportSetupReturnsToExport ? { navigation.returnToExport() } : nil)
        case .favourites:
            if let foodLedger { FavouritesFlowView(root: foodLedger) }
            else { ContentUnavailableView("Favourites unavailable", systemImage: "exclamationmark.triangle", description: Text("The local food ledger could not be opened.")) }
        }
    }

    private func configureScreenshotProvider() {
        let foodHome = foodHome
        let todaySoFar = todaySoFar
        let notes = dailyExport.notes
        let foodLedger = foodLedger
        screenshotController.setRequestProvider {
            [weak viewModel, weak navigation, weak presentationState, weak screenshotController] in
            guard let viewModel,
                  let navigation,
                  let presentationState,
                  let screenshotController,
                  let screen = WeeklyReportScreenshotEligibility.screen(
                    navigationPath: navigation.path,
                    isTransientUIPresented: presentationState.isTransientUIPresented,
                    isTodayOnScreen: screenshotController.isTodayOnScreen
                        && !screenshotController.isPresentingModally
                  ) else {
                return nil
            }

            switch screen {
            case .healthReport:
                // Full Page is always the expanded document, independent of
                // what is expanded on screen.
                return HealthReportView.fullPageDocument(viewModel: viewModel).map { .healthReport($0) }
            case .today:
                // Built now from the same models as Home's cards, never a stale copy.
                let features = Self.homeFeatures(foodHome: foodHome, todaySoFar: todaySoFar, notes: notes)
                return .today(HomeView.fullPageDocument(
                    features,
                    // The day of Home's last refresh, as in its header and cards.
                    today: screenshotController.todayRefreshedDay ?? foodLedger?.confirmationNow ?? Date(),
                    calendar: foodLedger?.confirmationDayCalendar ?? .autoupdatingCurrent
                ))
            }
        }
    }
}

extension View {
    /// Registers a screen the banner after Log can appear on. Leaving it dismisses a banner shown
    /// there, whatever covered it: a path push, `navigationDestination(item:)` or
    /// `(isPresented:)`, so new pushes need no wiring. A sheet stays modal over the banner.
    func foodLoggedBannerScreen(_ banner: FoodLoggedBannerModel?) -> some View {
        modifier(FoodLoggedBannerScreen(banner: banner))
    }
}

/// Reports the screen entering and leaving the window (review fix, PR #240). The navigation
/// stack removes a covered screen's view from the window after any kind of push and puts it back
/// on the pop, so this needs no help from the screen's own appear callbacks.
private struct FoodLoggedBannerScreen: ViewModifier {
    let banner: FoodLoggedBannerModel?
    @State private var id = UUID()

    func body(content: Content) -> some View {
        content.background {
            if let banner {
                WindowPresence { [id] inWindow in
                    if inWindow { banner.screenAppeared(id) } else { banner.screenDisappeared(id) }
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
        }
    }
}

private struct WindowPresence: UIViewRepresentable {
    let changed: @MainActor (Bool) -> Void

    func makeUIView(context: Context) -> PresenceView {
        let view = PresenceView()
        view.changed = changed
        return view
    }

    func updateUIView(_ view: PresenceView, context: Context) { view.changed = changed }

    final class PresenceView: UIView {
        var changed: (@MainActor (Bool) -> Void)?
        override func didMoveToWindow() {
            super.didMoveToWindow()
            changed?(window != nil)
        }
    }
}

/// The banner after Log closes Confirm (owner decision, 15 October 2026), over whichever screen
/// the journey returned to. It anchors to the navigation path at the moment it appears, and an
/// applied Undo reloads Home's food card (the Food Log reloads itself).
private struct FoodLoggedBannerHost: View {
    let banner: FoodLoggedBannerModel
    let navigation: AppNavigationCoordinator
    let foodHome: FoodHomeModel

    var body: some View {
        FoodLoggedBanner(model: banner)
            .onAppear { banner.location = { [weak navigation] in navigation.map { AnyHashable($0.path) } } }
            .onReceive(banner.$removals.dropFirst()) { _ in foodHome.reload() }
    }
}
