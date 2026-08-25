import Foundation

struct WeightMeasurement: Equatable {
    let date: Date
    let kilograms: Double

    static func latest(in measurements: [WeightMeasurement]) -> WeightMeasurement? {
        measurements.max { lhs, rhs in lhs.date < rhs.date }
    }
}

struct DailyWeightValue: Equatable, Identifiable {
    let day: Date
    let kilograms: Double
    let sampleCount: Int

    var id: Date { day }
}

struct WeightTrendSummary: Equatable {
    let latest: WeightMeasurement
    let currentSevenDayAverage: Double?
    let previousSevenDayAverage: Double?
    let trendKilograms: Double?
    let dailyValues: [DailyWeightValue]

    static func calculate(
        measurements: [WeightMeasurement],
        asOf: Date,
        calendar suppliedCalendar: Calendar = .autoupdatingCurrent,
        minimumSampledDays: Int = 3
    ) -> WeightTrendSummary? {
        guard let latest = WeightMeasurement.latest(in: measurements) else { return nil }
        var calendar = suppliedCalendar
        calendar.timeZone = suppliedCalendar.timeZone
        let today = calendar.startOfDay(for: asOf)
        guard let currentStart = calendar.date(byAdding: .day, value: -7, to: today),
              let previousStart = calendar.date(byAdding: .day, value: -7, to: currentStart)
        else { return nil }

        // Multiple weigh-ins on a day become one daily value before either
        // seven-day mean is calculated, so each sampled day has equal weight.
        let grouped = Dictionary(grouping: measurements.filter {
            $0.date >= previousStart && $0.date < today
        }) { calendar.startOfDay(for: $0.date) }
        let dailyValues = grouped.map { day, samples in
            DailyWeightValue(
                day: day,
                kilograms: samples.map(\.kilograms).reduce(0, +) / Double(samples.count),
                sampleCount: samples.count
            )
        }.sorted { $0.day < $1.day }

        func average(from start: Date, to end: Date) -> Double? {
            let values = dailyValues.filter { $0.day >= start && $0.day < end }.map(\.kilograms)
            guard values.count >= minimumSampledDays else { return nil }
            return values.reduce(0, +) / Double(values.count)
        }

        let current = average(from: currentStart, to: today)
        let previous = average(from: previousStart, to: currentStart)
        return WeightTrendSummary(
            latest: latest,
            currentSevenDayAverage: current,
            previousSevenDayAverage: previous,
            trendKilograms: current.flatMap { current in previous.map { current - $0 } },
            dailyValues: dailyValues
        )
    }
}
