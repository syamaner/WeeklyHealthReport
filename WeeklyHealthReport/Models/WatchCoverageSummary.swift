import Foundation

struct WatchCoverageSummary: Equatable {
    let reportingDayCount: Int
    let coveredDays: [DateInterval]

    var daysWithWatchData: Int { coveredDays.count }

    static func calculate(
        appleWatchSampleDates: [Date],
        period: ReportPeriod
    ) -> WatchCoverageSummary? {
        let coveredDays = period.completedDays.filter { day in
            appleWatchSampleDates.contains { date in
                date >= day.start && date < day.end
            }
        }
        guard !coveredDays.isEmpty else { return nil }
        return WatchCoverageSummary(
            reportingDayCount: period.completedDays.count,
            coveredDays: coveredDays
        )
    }
}
