import SwiftUI
import HealthKit

@main
struct WeeklyHealthReportApp: App {
    private let healthStore: HKHealthStore
    @StateObject private var viewModel: WeeklyReportViewModel
    @StateObject private var dailyExport = DailyDriveSessionController()
    @StateObject private var navigation = WeeklyReportNavigationController()

    init() {
        let store = HealthStoreProvider.shared
        healthStore = store
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
                medicationAccess: MedicationAccessRequest(store: healthStore)
            )
                .onOpenURL { dailyExport.resumeOAuthRedirect($0) }
        }
    }
}
