import Foundation

enum SleepStage: Equatable {
    case inBed
    case awake
    case asleepUnspecified
    case asleepCore
    case asleepDeep
    case asleepREM
    case other

    var countsAsAsleep: Bool {
        switch self {
        case .asleepUnspecified, .asleepCore, .asleepDeep, .asleepREM:
            return true
        case .inBed, .awake, .other:
            return false
        }
    }
}

struct AsleepInterval: Equatable {
    let start: Date
    let end: Date

    var duration: TimeInterval { max(0, end.timeIntervalSince(start)) }
}

struct NightlySleepTotal: Equatable, Identifiable {
    /// The local calendar day on which the noon-to-noon night bucket ends.
    let wakeDay: Date
    let duration: TimeInterval
    let mergedIntervals: [AsleepInterval]

    var id: Date { wakeDay }
}

struct SleepSummary: Equatable {
    let nights: [NightlySleepTotal]
    let averageDuration: TimeInterval

    static func calculate(
        asleepIntervals: [AsleepInterval],
        period: ReportPeriod,
        calendar suppliedCalendar: Calendar = .autoupdatingCurrent
    ) -> SleepSummary? {
        var calendar = suppliedCalendar
        calendar.timeZone = suppliedCalendar.timeZone

        let nights = period.completedDays.compactMap { day -> NightlySleepTotal? in
            let wakeDay = day.start
            guard let bucketEnd = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: wakeDay),
                  let bucketStart = calendar.date(byAdding: .day, value: -1, to: bucketEnd)
            else { return nil }

            let clipped = asleepIntervals.compactMap { interval -> AsleepInterval? in
                let start = max(interval.start, bucketStart)
                let end = min(interval.end, bucketEnd)
                guard start < end else { return nil }
                return AsleepInterval(start: start, end: end)
            }
            let merged = mergeOverlaps(clipped)
            let duration = merged.reduce(0) { $0 + $1.duration }
            guard duration > 0 else { return nil }
            return NightlySleepTotal(
                wakeDay: wakeDay,
                duration: duration,
                mergedIntervals: merged
            )
        }

        guard !nights.isEmpty else { return nil }
        return SleepSummary(
            nights: nights,
            averageDuration: nights.reduce(0) { $0 + $1.duration } / Double(nights.count)
        )
    }

    static func queryInterval(
        for period: ReportPeriod,
        calendar suppliedCalendar: Calendar = .autoupdatingCurrent
    ) -> DateInterval? {
        guard let firstDay = period.completedDays.first else { return nil }
        var calendar = suppliedCalendar
        calendar.timeZone = suppliedCalendar.timeZone
        guard let firstNoon = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: firstDay.start),
              let start = calendar.date(byAdding: .day, value: -1, to: firstNoon),
              let lastDay = period.completedDays.last,
              let end = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: lastDay.start)
        else { return nil }
        return DateInterval(start: start, end: end)
    }

    static func mergeOverlaps(_ intervals: [AsleepInterval]) -> [AsleepInterval] {
        let sorted = intervals.filter { $0.start < $0.end }.sorted { lhs, rhs in
            lhs.start == rhs.start ? lhs.end < rhs.end : lhs.start < rhs.start
        }
        guard var current = sorted.first else { return [] }
        var result: [AsleepInterval] = []

        for interval in sorted.dropFirst() {
            if interval.start <= current.end {
                current = AsleepInterval(start: current.start, end: max(current.end, interval.end))
            } else {
                result.append(current)
                current = interval
            }
        }
        result.append(current)
        return result
    }
}
