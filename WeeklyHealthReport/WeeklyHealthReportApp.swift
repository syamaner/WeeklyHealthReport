import SwiftUI

@main
struct WeeklyHealthReportApp: App {
    @StateObject private var dailyExport = DailyDriveSessionController()

    var body: some Scene {
        WindowGroup {
            WeeklyReportView(dailyExport: dailyExport)
                .onOpenURL { dailyExport.resumeOAuthRedirect($0) }
        }
    }
}
