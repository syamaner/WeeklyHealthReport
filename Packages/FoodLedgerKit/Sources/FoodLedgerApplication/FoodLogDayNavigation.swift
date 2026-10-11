import Foundation

/// Food Log day navigation over reporting-day keys (#197). Keys come only from
/// `FoodReportingDay.key`; stepping uses a Gregorian calendar in the injected calendar's time
/// zone, so a non-Gregorian display calendar yields the same days. No day after today is offered.
public struct FoodLogDayNavigation: Sendable {
    public let now: Date
    private let calendar: Calendar
    private let gregorian: Calendar

    public init(now: Date, calendar: Calendar) {
        self.now = now
        self.calendar = calendar
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = calendar.timeZone
        self.gregorian = gregorian
    }

    public var todayKey: String { key(for: now) }

    public func key(for date: Date) -> String { FoodReportingDay.key(for: date, calendar: calendar) }

    /// Noon of the day a key names, in the calendar's time zone (stable across DST changes).
    public func date(forKey key: String) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return gregorian.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12))
    }

    public func isToday(_ key: String) -> Bool { key == todayKey }

    public func canMoveForward(from key: String) -> Bool { key < todayKey }

    /// The previous day's key.
    public func previous(_ key: String) -> String? { step(key, by: -1) }

    /// The next day's key, or nil when it would be after today.
    public func next(_ key: String) -> String? {
        guard let next = step(key, by: 1), next <= todayKey else { return nil }
        return next
    }

    /// A chosen date's key, never later than today.
    public func clampedKey(for date: Date) -> String { min(key(for: date), todayKey) }

    private func step(_ key: String, by days: Int) -> String? {
        guard let date = date(forKey: key), let moved = gregorian.date(byAdding: .day, value: days, to: date) else { return nil }
        return self.key(for: moved)
    }
}
