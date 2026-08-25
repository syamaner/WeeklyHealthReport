import Foundation

enum ReportPeriodSelection: String, CaseIterable, Identifiable {
    case currentWeek = "Current Week"
    case previousWeek = "Previous Week"
    case lastSevenCompletedDays = "Last 7 Completed Days"

    var id: Self { self }
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
