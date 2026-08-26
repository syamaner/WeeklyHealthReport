import Foundation

struct BodyFatMeasurement: Equatable {
    let date: Date
    let percentage: Double

    static func percentagePoints(fromHealthKitFraction fraction: Double) -> Double {
        // HKUnit.percent values are defined by HealthKit on a 0.0...1.0 scale.
        // The app's domain model uses percentage points so 0.30 becomes 30.0%.
        fraction * 100
    }
}

struct DailyBodyFatValue: Equatable, Identifiable {
    let day: Date
    let percentage: Double
    let sampleCount: Int

    var id: Date { day }
}

struct BodyFatTrendSummary: Equatable {
    let latest: BodyFatMeasurement
    let sevenDayAverage: Double?
    let current28DayAverage: Double?
    let previous28DayAverage: Double?
    let trendPercentagePoints: Double?
    let dailyValues: [DailyBodyFatValue]
    let measurements: [BodyFatMeasurement]

    static func calculate(
        measurements: [BodyFatMeasurement],
        asOf: Date,
        calendar suppliedCalendar: Calendar = .autoupdatingCurrent,
        minimumSampledDays: Int = 2
    ) -> BodyFatTrendSummary? {
        guard let latest = measurements.max(by: { $0.date < $1.date }) else {
            return nil
        }

        var calendar = suppliedCalendar
        calendar.timeZone = suppliedCalendar.timeZone
        let today = calendar.startOfDay(for: asOf)
        guard let sevenDayStart = calendar.date(byAdding: .day, value: -6, to: today),
              let current28DayStart = calendar.date(byAdding: .day, value: -27, to: today),
              let previous28DayStart = calendar.date(byAdding: .day, value: -28, to: current28DayStart)
        else {
            return nil
        }

        let visibleMeasurements = measurements.filter { $0.date >= previous28DayStart && $0.date <= asOf }
        let grouped = Dictionary(grouping: visibleMeasurements) { calendar.startOfDay(for: $0.date) }
        let dailyValues = grouped.map { day, samples in
            DailyBodyFatValue(
                day: day,
                percentage: samples.map(\.percentage).reduce(0, +) / Double(samples.count),
                sampleCount: samples.count
            )
        }.sorted { $0.day < $1.day }

        func average(from start: Date, to end: Date) -> Double? {
            let values = dailyValues
                .filter { $0.day >= start && $0.day < end }
                .map(\.percentage)
            guard values.count >= minimumSampledDays else { return nil }
            return values.reduce(0, +) / Double(values.count)
        }

        let sevenDayAverage = average(from: sevenDayStart, to: asOf)
        let current28DayAverage = average(from: current28DayStart, to: asOf)
        let previous28DayAverage = average(from: previous28DayStart, to: current28DayStart)
        let trend = current28DayAverage.flatMap { current in
            previous28DayAverage.map { current - $0 }
        }

        return BodyFatTrendSummary(
            latest: latest,
            sevenDayAverage: sevenDayAverage,
            current28DayAverage: current28DayAverage,
            previous28DayAverage: previous28DayAverage,
            trendPercentagePoints: trend,
            dailyValues: dailyValues,
            measurements: visibleMeasurements.sorted { $0.date < $1.date }
        )
    }
}
