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
            averageDailySteps: total / Double(visibleValues.count),
            reportingDayCount: dailyTotals.count,
            daysWithVisibleData: visibleValues.count
        )
    }
}

/// Policy `steps_trend_previous_equivalent_v1` (docs/health-steps-trend-v1.md).
/// The one home of the trend's coverage rule.
enum StepTrendPolicy {
    static let identifier = "steps_trend_previous_equivalent_v1"
    /// No trend is possible below this many completed days.
    static let minimumCompletedDays = 3

    /// Sampled days needed on each side: `max(3, ceil(5 × N / 7))`, or nil
    /// when N is below `minimumCompletedDays` and no trend is possible.
    static func requiredSampledDays(completedDayCount: Int) -> Int? {
        guard completedDayCount >= minimumCompletedDays else { return nil }
        let fiveSevenths = (5 * completedDayCount + 6) / 7
        return max(minimumCompletedDays, fiveSevenths)
    }
}

/// The selected period's average daily steps compared with the equivalent
/// previous period (`ReportPeriod.precedingEquivalent`). Each side uses the
/// `StepSummary.aggregate` rule, so a missing day is never zero. `change` is
/// the unrounded percentage, or nil when coverage is short or the previous
/// average is 0.
struct StepTrendSummary: Equatable {
    let current: StepSummary
    let previous: StepSummary?
    /// Every previous-period day as read, including days with no statistic.
    let previousDailyTotals: [DailyStepTotal]
    let completedDayCount: Int
    let requiredSampledDays: Int?
    let change: Double?

    static func calculate(
        current currentTotals: [DailyStepTotal],
        previous previousTotals: [DailyStepTotal],
        completedDayCount: Int
    ) -> StepTrendSummary? {
        guard let current = StepSummary.aggregate(currentTotals) else { return nil }
        let previous = StepSummary.aggregate(previousTotals)
        let required = StepTrendPolicy.requiredSampledDays(completedDayCount: completedDayCount)

        var change: Double?
        if let required,
           let previous,
           current.daysWithVisibleData >= required,
           previous.daysWithVisibleData >= required,
           previous.averageDailySteps > 0 {
            change = (current.averageDailySteps - previous.averageDailySteps)
                / previous.averageDailySteps * 100
        }
        return StepTrendSummary(
            current: current,
            previous: previous,
            previousDailyTotals: previousTotals,
            completedDayCount: completedDayCount,
            requiredSampledDays: required,
            change: change
        )
    }
}
