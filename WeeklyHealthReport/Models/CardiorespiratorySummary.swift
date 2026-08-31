import Foundation

struct VO2MaxMeasurement: Equatable {
    let date: Date
    let millilitresPerKilogramMinute: Double
    let sourceName: String
}

struct DailyVO2MaxValue: Equatable, Identifiable {
    let day: Date
    let average: Double
    let sampleCount: Int

    var id: Date { day }
}

struct VO2MaxWindowSummary: Equatable {
    let average: Double?
    let sampledDayCount: Int
}

struct VO2MaxSummary: Equatable {
    let latest: VO2MaxMeasurement
    let fourWeek: VO2MaxWindowSummary
    let threeMonth: VO2MaxWindowSummary
    let sixMonth: VO2MaxWindowSummary
    let dailyValues: [DailyVO2MaxValue]
    let measurements: [VO2MaxMeasurement]

    static func calculate(
        measurements: [VO2MaxMeasurement],
        asOf: Date,
        calendar suppliedCalendar: Calendar = .autoupdatingCurrent,
        minimumSampledDays: Int = 3
    ) -> VO2MaxSummary? {
        var calendar = suppliedCalendar
        calendar.timeZone = suppliedCalendar.timeZone
        let today = calendar.startOfDay(for: asOf)
        guard let fourWeekStart = calendar.date(byAdding: .day, value: -27, to: today),
              let threeMonthStart = calendar.date(byAdding: .month, value: -3, to: today),
              let sixMonthStart = calendar.date(byAdding: .month, value: -6, to: today)
        else { return nil }

        let visibleMeasurements = measurements.filter {
            $0.date >= sixMonthStart
                && $0.date <= asOf
                && $0.millilitresPerKilogramMinute.isFinite
                && $0.millilitresPerKilogramMinute > 0
        }
        guard let latest = visibleMeasurements.max(by: { $0.date < $1.date }) else {
            return nil
        }

        // VO2 max is a discrete estimate. Multiple estimates on one calendar
        // day become one daily mean before any rolling average, preventing one
        // heavily sampled day from dominating a longer window.
        let grouped = Dictionary(grouping: visibleMeasurements) {
            calendar.startOfDay(for: $0.date)
        }
        let dailyValues = grouped.map { day, samples in
            DailyVO2MaxValue(
                day: day,
                average: samples.map(\.millilitresPerKilogramMinute).reduce(0, +)
                    / Double(samples.count),
                sampleCount: samples.count
            )
        }.sorted { $0.day < $1.day }

        func window(start: Date) -> VO2MaxWindowSummary {
            let values = dailyValues.filter { $0.day >= start }.map(\.average)
            let average = values.count >= minimumSampledDays
                ? values.reduce(0, +) / Double(values.count)
                : nil
            return VO2MaxWindowSummary(
                average: average,
                sampledDayCount: values.count
            )
        }

        return VO2MaxSummary(
            latest: latest,
            fourWeek: window(start: fourWeekStart),
            threeMonth: window(start: threeMonthStart),
            sixMonth: window(start: sixMonthStart),
            dailyValues: dailyValues,
            measurements: visibleMeasurements.sorted { $0.date < $1.date }
        )
    }
}

struct OxygenSaturationMeasurement: Equatable {
    let date: Date
    let percentage: Double
    let sourceName: String

    static func percentagePoints(fromHealthKitFraction fraction: Double) -> Double {
        fraction * 100
    }
}

struct DailyOxygenSaturationValue: Equatable, Identifiable {
    let day: DateInterval
    let medianPercentage: Double?
    let sampleCount: Int
    let sourceNames: [String]

    var id: Date { day.start }
}

struct BloodOxygenSummary: Equatable {
    let latest: OxygenSaturationMeasurement
    let dailyValues: [DailyOxygenSaturationValue]
    let typicalPercentage: Double?
    let minimumDailyMedian: Double?
    let maximumDailyMedian: Double?
    let measurements: [OxygenSaturationMeasurement]

    var validDayCount: Int { dailyValues.compactMap(\.medianPercentage).count }
    var reportingDayCount: Int { dailyValues.count }

    static func calculate(
        measurements: [OxygenSaturationMeasurement],
        period: ReportPeriod,
        asOf: Date,
        calendar suppliedCalendar: Calendar = .autoupdatingCurrent
    ) -> BloodOxygenSummary? {
        var calendar = suppliedCalendar
        calendar.timeZone = suppliedCalendar.timeZone
        guard let latestLookbackStart = calendar.date(
            byAdding: .day,
            value: -30,
            to: calendar.startOfDay(for: asOf)
        ) else { return nil }
        let validMeasurements = measurements.filter {
            $0.date >= latestLookbackStart
                && $0.date <= asOf
                && $0.percentage.isFinite
                && (0...100).contains($0.percentage)
        }
        guard let latest = validMeasurements.max(by: { $0.date < $1.date }) else {
            return nil
        }

        // HealthKit exposes oxygen saturation as discrete samples and does not
        // publish a source-precedence rule. Use the median of all visible values
        // within each completed day, then give every valid day equal weight by
        // taking the median of daily medians. This is robust to occasional
        // outliers and unequal background-sampling frequency between days.
        let dailyValues = period.completedDays.map { day in
            // Keep the report's half-open interval contract explicit so a
            // midnight sample belongs only to the day that starts then.
            let samples = validMeasurements.filter {
                $0.date >= day.start && $0.date < day.end
            }
            return DailyOxygenSaturationValue(
                day: day,
                medianPercentage: median(samples.map(\.percentage)),
                sampleCount: samples.count,
                sourceNames: Array(Set(samples.map(\.sourceName))).sorted()
            )
        }
        let dailyMedians = dailyValues.compactMap(\.medianPercentage)

        return BloodOxygenSummary(
            latest: latest,
            dailyValues: dailyValues,
            typicalPercentage: median(dailyMedians),
            minimumDailyMedian: dailyMedians.min(),
            maximumDailyMedian: dailyMedians.max(),
            measurements: validMeasurements.sorted { $0.date < $1.date }
        )
    }

    private static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let midpoint = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[midpoint - 1] + sorted[midpoint]) / 2
        }
        return sorted[midpoint]
    }
}
