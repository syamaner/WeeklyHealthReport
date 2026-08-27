import Foundation

struct DailyGlucoseValue: Equatable, Identifiable {
    let day: DateInterval
    let averageMillimolesPerLiter: Double?
    let minimumMillimolesPerLiter: Double?
    let maximumMillimolesPerLiter: Double?
    let sourceNames: [String]

    var id: Date { day.start }
}

struct GlucoseSummary: Equatable {
    let dailyValues: [DailyGlucoseValue]
    let averageMillimolesPerLiter: Double
    let minimumMillimolesPerLiter: Double
    let maximumMillimolesPerLiter: Double

    var validDayCount: Int {
        dailyValues.compactMap(\.averageMillimolesPerLiter).count
    }

    var reportingDayCount: Int { dailyValues.count }

    static func aggregate(_ dailyValues: [DailyGlucoseValue]) -> GlucoseSummary? {
        // Average within each calendar day first, then give every valid day
        // equal weight. A day with more CGM samples cannot dominate the week.
        let dailyAverages = dailyValues.compactMap(\.averageMillimolesPerLiter)
        let dailyMinimums = dailyValues.compactMap(\.minimumMillimolesPerLiter)
        let dailyMaximums = dailyValues.compactMap(\.maximumMillimolesPerLiter)
        guard !dailyAverages.isEmpty,
              let minimum = dailyMinimums.min(),
              let maximum = dailyMaximums.max()
        else { return nil }

        return GlucoseSummary(
            dailyValues: dailyValues,
            averageMillimolesPerLiter: dailyAverages.reduce(0, +) / Double(dailyAverages.count),
            minimumMillimolesPerLiter: minimum,
            maximumMillimolesPerLiter: maximum
        )
    }
}
