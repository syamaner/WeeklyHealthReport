import SwiftUI
import HealthKit

@main
struct WeeklyHealthReportApp: App {
    private let healthStore: HKHealthStore
    @StateObject private var viewModel: WeeklyReportViewModel
    @StateObject private var dailyExport = DailyDriveSessionController()
    @StateObject private var navigation = AppNavigationCoordinator()
    private let foodLedger: FoodLedgerCompositionRoot?
    private let settings: AppSettings

    init() {
        let store = HealthStoreProvider.shared
        healthStore = store
        let foodLedger = try? FoodLedgerCompositionRoot()
        self.foodLedger = foodLedger
        settings = Self.makeSettings(
            foodLedger: foodLedger,
            defaults: .standard,
            medicationAccessAvailable: Self.medicationAccessAvailable
        )
        _viewModel = StateObject(
            wrappedValue: WeeklyReportViewModel(
                healthData: HealthKitClient(store: store)
            )
        )
    }

    var body: some Scene {
        WindowGroup {
            AppShellView(
                viewModel: viewModel,
                dailyExport: dailyExport,
                navigation: navigation,
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
        medicationAccessAvailable: Bool
    ) -> AppSettings {
        var sections = foodLedger?.settingsSections() ?? []
        sections.append(ExportSettingsContribution.section())
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
