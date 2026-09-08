import SwiftUI

@main
struct WeeklyHealthReportApp: App {
    @StateObject private var dailyExport = DailyDriveSessionController()
    @StateObject private var navigation = WeeklyReportNavigationController()

    var body: some Scene {
        WindowGroup {
            WeeklyReportView(dailyExport: dailyExport, navigation: navigation)
                .onOpenURL { dailyExport.resumeOAuthRedirect($0) }
        }
    }
}
