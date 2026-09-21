import SwiftUI
import HealthKit

@main
struct WeeklyHealthReportApp: App {
    private let healthStore: HKHealthStore
    @StateObject private var viewModel: WeeklyReportViewModel
    @StateObject private var dailyExport = DailyDriveSessionController()
    @StateObject private var navigation = WeeklyReportNavigationController()
    private let foodLedger: FoodLedgerCompositionRoot?

    init() {
        let store = HealthStoreProvider.shared
        healthStore = store
        foodLedger = try? FoodLedgerCompositionRoot()
        _viewModel = StateObject(
            wrappedValue: WeeklyReportViewModel(
                healthData: HealthKitClient(store: store)
            )
        )
    }

    var body: some Scene {
        WindowGroup {
            WeeklyReportView(
                viewModel: viewModel,
                dailyExport: dailyExport,
                navigation: navigation,
                medicationAccess: MedicationAccessRequest(store: healthStore),
                foodLedger: foodLedger
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
}
