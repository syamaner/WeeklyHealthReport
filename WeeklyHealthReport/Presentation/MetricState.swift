import Foundation

enum MetricState<Value: Equatable>: Equatable {
    case idle
    case loading
    case available(Value)
    case noDataOrAccess
    case healthUnavailable
    case failed(String)

    var value: Value? {
        if case .available(let value) = self { return value }
        return nil
    }
}

enum StepsState: Equatable {
    case idle
    case loading
    /// The current period's summary and, separately, the comparison with the
    /// previous period. A failed previous read never changes the current rows.
    case loaded(StepSummary, trend: StepTrendRead = .notRead)
    case noCompletedDays
    case noDataOrAccess
    case healthUnavailable
    case failed(String)
}

/// The previous-period side of the steps trend (docs/health-steps-trend-v1.md).
enum StepTrendRead: Equatable {
    /// Not read, for example when there is no previous period.
    case notRead
    case calculated(StepTrendSummary)
    /// Only the previous-period read failed; Developer tools shows the message.
    case previousFailed(String)

    var change: Double? {
        if case .calculated(let summary) = self { return summary.change }
        return nil
    }
}
