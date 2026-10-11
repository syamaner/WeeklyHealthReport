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
            FoodIntakeHomeView(root: foodLedger)
            .navigationTitle("Today")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { navigation.openSettings() } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")
                    .accessibilityIdentifier("settingsButton")
                }
            }
            .background {
                WeeklyReportScreenshotSceneRegistration(controller: screenshotController)
                    .frame(width: 0, height: 0)
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
                configureScreenshotProvider()
                navigation.restoreIfNeeded(
                    hasDraft: dailyExport.notes.currentDraft != nil,
                    availableRoutes: settings.availableRoutes
                )
            }
            .onChange(of: navigation.path) {
                navigation.recordDestination()
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
                navigation.didBecomeActive(
                    hasDraft: dailyExport.notes.currentDraft != nil,
                    availableRoutes: settings.availableRoutes
                )
            }
        }
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
            DailyExportView(session: dailyExport)
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
            else { ContentUnavailableView("Common foods unavailable", systemImage: "exclamationmark.triangle", description: Text("Your saved foods could not be opened. Try again after unlocking your device.")) }
        case .foodReresolution:
            if let foodLedger, let flow = FoodReresolutionFlowView(root: foodLedger) { flow }
            else { ContentUnavailableView("Nutrition review unavailable", systemImage: "exclamationmark.triangle") }
        case .notes:
            DailyNotesView(
                controller: dailyExport.notes,
                openEditor: { navigation.append(.noteEditor) }
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
            DeveloperDiagnosticsView(viewModel: viewModel)
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
            DeveloperToolsSettingsView(toggle: settings.developerTools, diagnostics: foodLedger?.searchDiagnostics)
        case .addFood:
            if let foodLedger {
                AddFoodFlowView(root: foodLedger)
                    .environment(\.finishFoodEntry, FoodEntryFinish { day in navigation.finishFoodEntry(reportingDay: day) })
            }
            else { ContentUnavailableView("Add food unavailable", systemImage: "exclamationmark.triangle", description: Text("The local food ledger could not be opened.")) }
        }
    }

    private func configureScreenshotProvider() {
        screenshotController.setRequestProvider {
            [weak viewModel, weak navigation, weak presentationState] in
            guard let viewModel,
                  let navigation,
                  let presentationState,
                  WeeklyReportScreenshotEligibility.isEligible(
                    navigationPath: navigation.path,
                    isTransientUIPresented: presentationState.isTransientUIPresented
                  ) else {
                return nil
            }

            guard let snapshot = viewModel.screenshotSnapshot(
                includesMedicationSection: HealthReportView.includesMedicationSection,
                showsMorningBloodPressureDetails:
                    presentationState.showsMorningBloodPressureDetails,
                showsEveningBloodPressureDetails:
                    presentationState.showsEveningBloodPressureDetails
            ) else {
                return nil
            }
            return HealthReportView.reportDocument(snapshot: snapshot)
        }
    }
}
