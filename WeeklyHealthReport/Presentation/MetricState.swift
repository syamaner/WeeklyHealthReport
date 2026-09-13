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
    case loaded(StepSummary)
    case noCompletedDays
    case noDataOrAccess
    case healthUnavailable
    case failed(String)
}
