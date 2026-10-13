import SwiftUI
import HealthKit

@main
struct WeeklyHealthReportApp: App {
    private let healthStore: HKHealthStore
    @StateObject private var viewModel: WeeklyReportViewModel
    @StateObject private var dailyExport = DailyDriveSessionController()
    @StateObject private var navigation = AppNavigationCoordinator()
    /// Home's today-so-far health card (#199); one per app session.
    @StateObject private var todaySoFar: TodaySoFarHealthModel
    private let foodLedger: FoodLedgerCompositionRoot?
    @StateObject private var foodHome: FoodHomeModel
    private let settings: AppSettings

    init() {
        let store = HealthStoreProvider.shared
        healthStore = store
        let foodLedger = try? FoodLedgerCompositionRoot()
        self.foodLedger = foodLedger
        _foodHome = StateObject(wrappedValue: FoodHomeModel(root: foodLedger))
        settings = Self.makeSettings(
            foodLedger: foodLedger,
            defaults: .standard,
            medicationAccessAvailable: Self.medicationAccessAvailable,
            driveExportAvailable: DailyDriveSessionController.bundleHasOAuthConfiguration
        )
        let healthClient = HealthKitClient(store: store)
        // One shared request: the report and Home both ask on launch (#199).
        let readAuthorization = SingleFlightReadAuthorization(base: healthClient)
        _viewModel = StateObject(
            wrappedValue: WeeklyReportViewModel(
                healthData: healthClient,
                readAuthorization: readAuthorization
            )
        )
        // Home uses the food ledger's injected clock and calendar, so the food
        // card and the health window agree on "today".
        _todaySoFar = StateObject(
            wrappedValue: TodaySoFarHealthModel(
                reader: healthClient,
                authorizer: readAuthorization,
                now: { foodLedger?.confirmationNow ?? Date() },
                calendar: { foodLedger?.confirmationDayCalendar ?? .autoupdatingCurrent }
            )
        )
    }

    var body: some Scene {
        WindowGroup {
            AppShellView(
                viewModel: viewModel,
                dailyExport: dailyExport,
                navigation: navigation,
                todaySoFar: todaySoFar,
                foodHome: foodHome,
                medicationAccess: MedicationAccessRequest(store: healthStore),
                foodLedger: foodLedger,
                settings: settings
            )
                .onOpenURL { dailyExport.resumeOAuthRedirect($0) }
                .onReceive(NotificationCenter.default.publisher(
                    for: UIApplication.protectedDataWillBecomeUnavailableNotification
                )) { _ in
                    dailyExport.notes.protectedDataWillBecomeUnavailable()
                }
                .onReceive(NotificationCenter.default.publisher(
                    for: UIApplication.protectedDataDidBecomeAvailableNotification
                )) { _ in
                    dailyExport.notes.retryStorageAccess()
                }
        }
    }

    /// Settings sections are contributed by each composed feature.
    @MainActor
    static func makeSettings(
        foodLedger: FoodLedgerCompositionRoot?,
        defaults: UserDefaults,
        medicationAccessAvailable: Bool,
        driveExportAvailable: Bool = true
    ) -> AppSettings {
        var sections = foodLedger?.settingsSections() ?? []
        sections.append(ExportSettingsContribution.section(driveExportAvailable: driveExportAvailable))
        if let appleHealth = AppleHealthSettingsContribution.section(
            medicationAccessAvailable: medicationAccessAvailable
        ) {
            sections.append(appleHealth)
        }
        sections.append(AboutSettingsContribution.section())
        return AppSettings(
            sections: sections,
            // The search screen reads this key from the food ledger's store.
            developerTools: AboutSettingsContribution.developerToolsToggle(
                defaults: foodLedger?.userDefaults ?? defaults
            )
        )
    }

    private static var medicationAccessAvailable: Bool {
        if #available(iOS 26.0, *) { true } else { false }
    }
}
