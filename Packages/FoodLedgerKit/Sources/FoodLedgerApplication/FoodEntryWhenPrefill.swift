import Foundation

/// When for a new entry started from a Food Log day (owner decision D, 13 Oct 2026). Add food
/// opened from a past day prefills When with that day at the current clock time; today, no day,
/// or a day the backdating window no longer reaches leaves When at Now. Navigation input only:
/// nothing here is persisted, and `FoodLogPolicy` still decides whether the chosen time saves.
public enum FoodEntryWhenPrefill: Equatable, Sendable {
    /// When stays "Now".
    case now
    /// The past day at the current clock time, resolved by the calendar.
    case day(Date)
    /// The day is older than `FoodLogPolicy.backdatingDays`, so When falls back to Now.
    case beyondBackdatingWindow

    /// The instant to put in `FoodConfirmationState.occurredAt` (nil means Now).
    public var occurredAt: Date? {
        if case let .day(date) = self { return date }
        return nil
    }

    /// `dayKey` is a reporting-day key ("yyyy-MM-dd") in the calendar's time zone. The day's
    /// wall time is today's clock time; a non-existent time (a spring-forward gap) is resolved by
    /// the Gregorian calendar in that time zone, as v5 section 4 requires, and the result is
    /// checked against the same window the policy uses.
    public static func resolve(dayKey: String?, now: Date, calendar: Calendar) -> FoodEntryWhenPrefill {
        guard let dayKey else { return .now }
        let navigation = FoodLogDayNavigation(now: now, calendar: calendar)
        guard dayKey < navigation.todayKey else { return .now }
        let parts = dayKey.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return .now }
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = calendar.timeZone
        let clock = gregorian.dateComponents([.hour, .minute, .second, .nanosecond], from: now)
        guard let resolved = gregorian.date(from: DateComponents(
            year: parts[0], month: parts[1], day: parts[2],
            hour: clock.hour, minute: clock.minute, second: clock.second, nanosecond: clock.nanosecond
        )), resolved <= now else { return .now }
        guard resolved >= FoodLogPolicy.windowStart(now: now, calendar: calendar) else { return .beyondBackdatingWindow }
        return .day(resolved)
    }
}
