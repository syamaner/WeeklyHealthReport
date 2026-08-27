import Foundation

struct WaistMeasurement: Equatable {
    let date: Date
    let centimetres: Double
}

struct WaistSummary: Equatable {
    let latest: WaistMeasurement
    let comparison: WaistMeasurement?
    let fourWeekChangeCentimetres: Double?
    let measurements: [WaistMeasurement]

    static func calculate(
        measurements: [WaistMeasurement],
        asOf date: Date,
        calendar: Calendar
    ) -> WaistSummary? {
        guard let lookbackStart = calendar.date(byAdding: .day, value: -56, to: date) else {
            return nil
        }

        // Waist entries are sparse manual observations. Keep the latest visible
        // value from an eight-week window instead of tying it to the weekly report.
        let visible = measurements
            .filter { $0.date >= lookbackStart && $0.date <= date }
            .sorted { $0.date < $1.date }
        guard let latest = visible.last else { return nil }

        // A four-week trend needs a genuinely older observation. Select the
        // sample closest to 28 days before the latest reading, accepting only
        // measurements 21...35 days earlier so a misleading comparison is not
        // manufactured from either a very recent or stale value.
        guard let target = calendar.date(byAdding: .day, value: -28, to: latest.date),
              let earliestComparison = calendar.date(
                byAdding: .day,
                value: -35,
                to: latest.date
              ),
              let latestComparison = calendar.date(
                byAdding: .day,
                value: -21,
                to: latest.date
              )
        else {
            return WaistSummary(
                latest: latest,
                comparison: nil,
                fourWeekChangeCentimetres: nil,
                measurements: visible
            )
        }

        let comparison = visible
            .filter { $0.date >= earliestComparison && $0.date <= latestComparison }
            .min {
                let leftDistance = abs($0.date.timeIntervalSince(target))
                let rightDistance = abs($1.date.timeIntervalSince(target))
                if leftDistance == rightDistance { return $0.date > $1.date }
                return leftDistance < rightDistance
            }

        return WaistSummary(
            latest: latest,
            comparison: comparison,
            fourWeekChangeCentimetres: comparison.map {
                latest.centimetres - $0.centimetres
            },
            measurements: visible
        )
    }
}
