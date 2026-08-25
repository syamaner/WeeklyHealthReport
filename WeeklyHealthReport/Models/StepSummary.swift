import Foundation

struct DailyStepTotal: Equatable, Identifiable {
    let day: DateInterval
    let steps: Double?
    let sourceNames: [String]

    var id: Date { day.start }
}

struct StepSummary: Equatable {
    let dailyTotals: [DailyStepTotal]
    let totalSteps: Double
    let averageDailySteps: Double
    let reportingDayCount: Int
    let daysWithVisibleData: Int

    static func aggregate(_ dailyTotals: [DailyStepTotal]) -> StepSummary? {
        guard !dailyTotals.isEmpty else { return nil }

        let visibleValues = dailyTotals.compactMap(\.steps)
        guard !visibleValues.isEmpty else { return nil }

        let total = visibleValues.reduce(0, +)
        return StepSummary(
            dailyTotals: dailyTotals,
            totalSteps: total,
            averageDailySteps: total / Double(dailyTotals.count),
            reportingDayCount: dailyTotals.count,
            daysWithVisibleData: visibleValues.count
        )
    }
}
