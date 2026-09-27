import Foundation

/// Existing ledger date keys remain Gregorian yyyy-MM-dd in the local time zone.
/// Display calendars may differ; they must not change stored key identity.
public enum FoodReportingDay {
    public static func key(for date: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
