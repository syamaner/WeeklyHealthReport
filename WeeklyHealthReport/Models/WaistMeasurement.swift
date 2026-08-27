import Foundation

struct WaistMeasurement: Equatable {
    let date: Date
    let centimetres: Double
}

struct WaistSummary: Equatable {
    let latest: WaistMeasurement
    let measurements: [WaistMeasurement]

    static func calculate(
        measurements: [WaistMeasurement],
        period: ReportPeriod
    ) -> WaistSummary? {
        // Waist entries are sparse manual observations. Select the latest value
        // in the report interval rather than averaging one or two measurements.
        let visible = measurements
            .filter { period.interval.contains($0.date) && $0.date < period.interval.end }
            .sorted { $0.date < $1.date }
        guard let latest = visible.last else { return nil }
        return WaistSummary(latest: latest, measurements: visible)
    }
}
