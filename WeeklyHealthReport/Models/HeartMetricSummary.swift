import Foundation

struct DailyHeartMetricValue: Equatable, Identifiable {
    let day: DateInterval
    let value: Double?
    let sourceNames: [String]

    var id: Date { day.start }
}

struct HeartMetricSummary: Equatable {
    let dailyValues: [DailyHeartMetricValue]
    let average: Double

    var validDayCount: Int {
        dailyValues.compactMap(\.value).count
    }

    static func aggregate(_ dailyValues: [DailyHeartMetricValue]) -> HeartMetricSummary? {
        // HealthKit first produces one discrete average per calendar day. The
        // weekly value is then the unweighted arithmetic mean of valid days, so
        // a day with more source samples cannot dominate the week.
        let validValues = dailyValues.compactMap(\.value)
        guard !validValues.isEmpty else { return nil }

        return HeartMetricSummary(
            dailyValues: dailyValues,
            average: validValues.reduce(0, +) / Double(validValues.count)
        )
    }
}

struct HeartMetricTrendSummary: Equatable {
    let current: HeartMetricSummary
    let previous: HeartMetricSummary?
    let trend: Double?

    static func calculate(
        currentValues: [DailyHeartMetricValue],
        previousValues: [DailyHeartMetricValue],
        minimumValidDays: Int = 3
    ) -> HeartMetricTrendSummary? {
        guard let current = HeartMetricSummary.aggregate(currentValues) else { return nil }
        let previous = HeartMetricSummary.aggregate(previousValues)
        let trend: Double?
        if current.validDayCount >= minimumValidDays,
           let previous,
           previous.validDayCount >= minimumValidDays {
            trend = current.average - previous.average
        } else {
            trend = nil
        }
        return HeartMetricTrendSummary(current: current, previous: previous, trend: trend)
    }
}
