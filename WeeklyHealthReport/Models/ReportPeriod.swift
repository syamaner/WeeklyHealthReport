import Foundation

enum ReportPeriodSelection: String, CaseIterable, Identifiable {
    case currentWeek = "Current Week"
    case previousWeek = "Previous Week"
    case lastSevenCompletedDays = "Last 7 Completed Days"

    var id: Self { self }
}

struct VO2MaxReportingWindowStarts: Equatable {
    let fourWeek: Date
    let threeMonth: Date
    let sixMonth: Date
}

enum HealthReportingPolicy {
    static let bloodPressureLatestLookbackDays = 30
    static let bloodPressureMorningEndHour = 14
    static let bloodPressureEveningStartHour = 17
    static let oxygenSaturationLatestLookbackDays = 30

    static func bloodPressureLatestLookbackStart(
        asOf date: Date,
        calendar: Calendar
    ) -> Date? {
        calendar.date(
            byAdding: .day,
            value: -bloodPressureLatestLookbackDays,
            to: calendar.startOfDay(for: date)
        )
    }

    static func bloodPressureQueryStart(
        for period: ReportPeriod,
        asOf date: Date,
        calendar: Calendar
    ) -> Date? {
        bloodPressureLatestLookbackStart(asOf: date, calendar: calendar).map {
            min(period.interval.start, $0)
        }
    }

    static func oxygenSaturationLatestLookbackStart(
        asOf date: Date,
        calendar: Calendar
    ) -> Date? {
        calendar.date(
            byAdding: .day,
            value: -oxygenSaturationLatestLookbackDays,
            to: calendar.startOfDay(for: date)
        )
    }

    static func oxygenSaturationQueryStart(
        for period: ReportPeriod,
        asOf date: Date,
        calendar: Calendar
    ) -> Date? {
        oxygenSaturationLatestLookbackStart(asOf: date, calendar: calendar).map {
            min(period.interval.start, $0)
        }
    }

    static func vo2MaxWindowStarts(
        asOf date: Date,
        calendar: Calendar
    ) -> VO2MaxReportingWindowStarts? {
        let today = calendar.startOfDay(for: date)
        guard let fourWeek = calendar.date(byAdding: .day, value: -27, to: today),
              let threeMonth = calendar.date(byAdding: .month, value: -3, to: today),
              let sixMonth = calendar.date(byAdding: .month, value: -6, to: today)
        else { return nil }
        return VO2MaxReportingWindowStarts(
            fourWeek: fourWeek,
            threeMonth: threeMonth,
            sixMonth: sixMonth
        )
    }
}

struct ReportPeriod: Equatable {
    let selection: ReportPeriodSelection
    let interval: DateInterval
    let completedDays: [DateInterval]

    static func make(
        selection: ReportPeriodSelection,
        now: Date = Date(),
        calendar suppliedCalendar: Calendar = .autoupdatingCurrent
    ) -> ReportPeriod {
        var calendar = suppliedCalendar
        calendar.timeZone = suppliedCalendar.timeZone

        let today = calendar.startOfDay(for: now)
        let start: Date
        let end: Date

        switch selection {
        case .lastSevenCompletedDays:
            start = calendar.date(byAdding: .day, value: -7, to: today)!
            end = today

        case .currentWeek:
            start = calendar.dateInterval(of: .weekOfYear, for: today)!.start
            end = today

        case .previousWeek:
            let currentWeekStart = calendar.dateInterval(of: .weekOfYear, for: today)!.start
            start = calendar.date(byAdding: .weekOfYear, value: -1, to: currentWeekStart)!
            end = currentWeekStart
        }

        let interval = DateInterval(start: start, end: end)
        return ReportPeriod(
            selection: selection,
            interval: interval,
            completedDays: calendar.completeDayIntervals(from: start, to: end)
        )
    }

    func precedingEquivalent(
        calendar suppliedCalendar: Calendar = .autoupdatingCurrent
    ) -> ReportPeriod? {
        guard !completedDays.isEmpty else { return nil }
        var calendar = suppliedCalendar
        calendar.timeZone = suppliedCalendar.timeZone
        let end = interval.start
        guard let start = calendar.date(
            byAdding: .day,
            value: -completedDays.count,
            to: end
        ) else { return nil }
        return ReportPeriod(
            selection: selection,
            interval: DateInterval(start: start, end: end),
            completedDays: calendar.completeDayIntervals(from: start, to: end)
        )
    }
}

extension Calendar {
    fileprivate func completeDayIntervals(from start: Date, to end: Date) -> [DateInterval] {
        var days: [DateInterval] = []
        var cursor = start

        while cursor < end {
            guard let next = date(byAdding: .day, value: 1, to: cursor), next <= end else {
                break
            }
            days.append(DateInterval(start: cursor, end: next))
            cursor = next
        }

        return days
    }
}
