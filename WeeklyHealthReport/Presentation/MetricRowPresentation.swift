import Foundation

private enum MetricRowVocabulary {
    static let loading = "Loading…"
    static let noData = "No data"
    static let unavailable = "Unavailable"
    static let queryFailed = "Query failed"
    static let insufficientHistory = "Insufficient history"
    static let noPeriodData = "No period data"
}

extension ReportDocument.Row {
    enum MissingValue {
        case insufficientHistory
        case noData
        case noPeriodData

        fileprivate var text: String {
            switch self {
            case .insufficientHistory: MetricRowVocabulary.insufficientHistory
            case .noData: MetricRowVocabulary.noData
            case .noPeriodData: MetricRowVocabulary.noPeriodData
            }
        }
    }

    static func metric<Value: Equatable>(
        id: String,
        label: String,
        state: MetricState<Value>,
        format: (Value) -> String?
    ) -> Self {
        switch state {
        case .idle, .loading:
            return Self(id, label: label, value: MetricRowVocabulary.loading, style: .loading)
        case .available(let value):
            guard let formattedValue = format(value) else {
                return Self(
                    id,
                    label: label,
                    value: MissingValue.insufficientHistory.text,
                    style: .secondary
                )
            }
            return Self(id, label: label, value: formattedValue)
        case .noDataOrAccess:
            return Self(id, label: label, value: MetricRowVocabulary.noData, style: .secondary)
        case .healthUnavailable:
            return Self(
                id,
                label: label,
                value: MetricRowVocabulary.unavailable,
                style: .secondary
            )
        case .failed:
            return Self(id, label: label, value: MetricRowVocabulary.queryFailed, style: .failure)
        }
    }

    static func optional<Value>(
        id: String,
        label: String,
        value: Value?,
        missing: MissingValue,
        format: (Value) -> String
    ) -> Self {
        guard let value else {
            return Self(id, label: label, value: missing.text, style: .secondary)
        }
        return Self(id, label: label, value: format(value))
    }
}
