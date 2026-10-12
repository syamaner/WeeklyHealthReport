import Foundation

/// The typed result of the most recent export attempt in this session. It is
/// set only when an export outcome is applied, so "verified" can never be
/// inferred from a status or label string.
struct DailyExportOutcomeRecord: Equatable {
    enum Kind: Equatable {
        case verified
        case unchangedVerified
        case cancelledBeforeSubmission
        case cancelledAfterSubmissionVerified
        case failed
    }

    let reportDate: String
    /// The cutoff of the data the outcome covers.
    let dataAsOf: String
    let kind: Kind

    var isVerified: Bool {
        switch kind {
        case .verified, .unchangedVerified, .cancelledAfterSubmissionVerified: true
        case .cancelledBeforeSubmission, .failed: false
        }
    }
}

/// What the Export screen says about the selected day, derived from plain
/// inputs only.
enum DailyExportPhase: Equatable {
    /// A plain summary of the export screen's preparation state.
    enum Setup: Equatable {
        case preparing
        case notSetUp
        case needsNutritionSource
        case ready
        case needsAttention
    }

    case notSetUp
    case preparing
    case prepared
    /// A submission is in flight.
    case attempting
    /// Both verified results and a cancellation that arrived after a verified submission.
    case verified
    case cancelledBeforeSending
    /// The attempt failed; whether Drive holds the file is not verified.
    case attemptedNotVerified
    case needsAttention

    static func resolve(
        setup: Setup,
        exporting: Bool,
        hasPreview: Bool,
        lastExportOutcome: DailyExportOutcomeRecord?
    ) -> DailyExportPhase {
        if setup == .preparing { return .preparing }
        if exporting { return .attempting }
        if lastExportOutcome?.kind == .failed { return .attemptedNotVerified }
        switch setup {
        case .notSetUp: return .notSetUp
        case .needsNutritionSource, .needsAttention: return .needsAttention
        case .preparing, .ready: break
        }
        if let lastExportOutcome {
            if lastExportOutcome.isVerified { return .verified }
            if lastExportOutcome.kind == .cancelledBeforeSubmission {
                return .cancelledBeforeSending
            }
        }
        return hasPreview ? .prepared : .preparing
    }
}

/// Labels for the Export day picker. The clock is never read: today's cutoff
/// comes only from a prepared snapshot of today.
enum DailyExportDayLabel {
    /// "Today, up to 08:00" when `previewDataAsOf` is a cutoff on
    /// `todayReportDate`; otherwise just "Today".
    static func today(todayReportDate: String, previewDataAsOf: String?) -> String {
        guard let previewDataAsOf,
              let time = localTime(in: previewDataAsOf, onReportDate: todayReportDate) else {
            return "Today"
        }
        return "Today, up to \(time)"
    }

    /// When a prepared snapshot's Health data runs to: "Today, 09:41" for a
    /// snapshot of today, otherwise the same weekday date and time as "Data
    /// up to", such as "Monday 12 October, 00:00" for yesterday's full day.
    /// Uses only the snapshot's dates; the clock is never read. Unreadable
    /// input is shown as is.
    static func dataAsOf(_ dataAsOf: String, reportDate: String, todayReportDate: String?, locale: Locale) -> String {
        let parts = dataAsOf.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        let timestamp = parts.count == 3 ? parts[1] : dataAsOf
        if let todayReportDate, reportDate == todayReportDate,
           let time = localTime(in: timestamp, onReportDate: todayReportDate) {
            return "Today, \(time)"
        }
        return cutoff(dataAsOf, locale: locale)
    }

    /// A weekday name for one of the previous seven days, such as
    /// "Saturday 5 September". Falls back to the report date itself.
    static func previousDay(reportDate: String, locale: Locale) -> String {
        var calendar = Calendar(identifier: .gregorian)
        guard let utc = TimeZone(identifier: "UTC") else { return reportDate }
        calendar.timeZone = utc
        let parts = reportDate.split(separator: "-")
        guard parts.count == 3,
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]),
              let date = calendar.date(from: DateComponents(year: year, month: month, day: day)) else {
            return reportDate
        }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = utc
        formatter.locale = locale
        formatter.setLocalizedDateFormatFromTemplate("EEEEdMMMM")
        return formatter.string(from: date)
    }

    /// A readable cutoff such as "Sunday 6 September, 08:00" from an ISO 8601
    /// timestamp or a three-part ordering token ("version|cutoff|encoded").
    /// Anything else is returned unchanged.
    static func cutoff(_ dataAsOf: String, locale: Locale) -> String {
        let parts = dataAsOf.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        let timestamp = parts.count == 3 ? parts[1] : dataAsOf
        let reportDate = String(timestamp.prefix(10))
        guard let time = localTime(in: timestamp, onReportDate: reportDate) else {
            return dataAsOf
        }
        return "\(previousDay(reportDate: reportDate, locale: locale)), \(time)"
    }

    /// The local wall-clock time of an ISO 8601 cutoff such as
    /// "2026-09-06T08:00:00+01:00", only when its date is `reportDate`.
    static func localTime(in dataAsOf: String, onReportDate reportDate: String) -> String? {
        let characters = Array(dataAsOf)
        guard characters.count >= 16,
              String(characters[0..<10]) == reportDate,
              characters[10] == "T",
              characters[13] == ":",
              characters[11].isASCIIDigit, characters[12].isASCIIDigit,
              characters[14].isASCIIDigit, characters[15].isASCIIDigit else {
            return nil
        }
        return String(characters[11..<16])
    }
}

private extension Character {
    var isASCIIDigit: Bool { isASCII && isNumber }
}
