import Foundation

/// Counts of what the prepared Daily JSON export holds for the selected day
/// (daily-export-included-summary-v1, #217). Derived only from the in-memory
/// prepared envelope; JSON is never parsed and nothing is read from HealthKit.
/// The counts are of records, never of health.
struct DailyExportIncludedSummary: Equatable {
    /// Per-day Health entries whose availability is `available`.
    let metricsWithData: Int
    /// The per-day Health entries minus any that are `unsupported`.
    let metricsApplicable: Int
    /// Entries in `today.workouts.data` when workouts are `available`;
    /// `nil` when they are not (no data or access, or unsupported).
    let workouts: Int?

    /// The 15 per-day Health entries, in contract order: weight, bodyFat,
    /// waist, bloodPressure, glucose, restingHeartRate, hrv, bloodOxygen,
    /// vo2Max, sleep, activity.steps, activity.activeEnergy,
    /// activity.exercise, watchCoverage, medications. Workouts, nutrition,
    /// notes, app context and the food fields are not metrics.
    static func metricAvailabilities(_ today: DailyHealthMetrics) -> [ExportAvailability] {
        [
            today.weight.availability,
            today.bodyFat.availability,
            today.waist.availability,
            today.bloodPressure.availability,
            today.glucose.availability,
            today.restingHeartRate.availability,
            today.hrv.availability,
            today.bloodOxygen.availability,
            today.vo2Max.availability,
            today.sleep.availability,
            today.activity.steps.availability,
            today.activity.activeEnergy.availability,
            today.activity.exercise.availability,
            today.watchCoverage.availability,
            today.medications.availability
        ]
    }

    static func make(today: DailyHealthMetrics) -> DailyExportIncludedSummary {
        let availabilities = metricAvailabilities(today)
        let workouts: Int? = today.workouts.availability == .available
            ? (today.workouts.data?.count ?? 0)
            : nil
        return DailyExportIncludedSummary(
            metricsWithData: availabilities.filter { $0 == .available }.count,
            metricsApplicable: availabilities.filter { $0 != .unsupported }.count,
            workouts: workouts
        )
    }

    static let noMetricsText = "No Health data visible for this day, or no access"
    static let noWorkoutsText = "no workouts visible"

    /// "9 of 14 metrics have data", or the no-data line. A missing entry is
    /// never shown as a zero value.
    var metricsText: String {
        guard metricsWithData > 0, metricsApplicable > 0 else { return Self.noMetricsText }
        return "\(metricsWithData) of \(metricsApplicable) metrics have data"
    }

    /// "1 workout", "2 workouts", or "no workouts visible"; never "0 workouts".
    var workoutsText: String {
        guard let workouts, workouts > 0 else { return Self.noWorkoutsText }
        return workouts == 1 ? "1 workout" : "\(workouts) workouts"
    }

    /// "Health · 9 of 14 metrics have data · 2 workouts".
    var line: String {
        "Health · \(metricsText) · \(workoutsText)"
    }
}

/// The last verified export of the selected day recorded on this iPhone,
/// as a plain value (#217). Only a verified snapshot is ever `.verified`;
/// pending, failed and cancelled operations are not exports.
enum DailyExportLastExport: Equatable {
    case none
    /// The local record could not be read or is ambiguous.
    case unknown
    /// `dataAsOf` is the stored ordering token: an ISO 8601 cutoff, or
    /// "version|cutoff|encoded" for an earlier day.
    case verified(verifiedAt: Date, dataAsOf: String)
}

/// The selected day's local export record, with the raw fields Developer
/// tools shows. No file or account identifier is held here.
struct DailyExportLastExportLookup: Equatable {
    let reportDate: String
    let state: DailyExportLastExport
    /// Whether an unverified operation is recorded for this day. Never shown
    /// as an export.
    let hasPendingOperation: Bool
}

enum DailyExportLastExportFormatter {
    static let noneLine = "Last export of this day from this iPhone: none"
    static let unknownLine = "Last export of this day from this iPhone: unknown"
    /// The historical ordering token's version prefix. Must equal
    /// `DailyHealthExportIdentityPolicy.historicalOrderingVersion` (a test pins it);
    /// Presentation does not depend on the Drive policy type.
    static let historicalOrderingVersion = "historical-v2"

    /// "Last export of this day from this iPhone: 11/10/26 - 13:05, data up
    /// to 13:02". The cutoff is shown as a time alone when it falls after
    /// midnight on the verification day, and in full otherwise (an earlier
    /// day's cutoff is its next midnight). An unreadable cutoff is omitted.
    static func line(
        _ value: DailyExportLastExport,
        calendar: Calendar = .autoupdatingCurrent
    ) -> String {
        switch value {
        case .none:
            return noneLine
        case .unknown:
            return unknownLine
        case .verified(let verifiedAt, let dataAsOf):
            let verified = HealthReportFormatter.dateAndTime(verifiedAt, calendar: calendar)
            guard let cutoff = cutoffText(dataAsOf, verifiedAt: verifiedAt, calendar: calendar) else {
                return "Last export of this day from this iPhone: \(verified)"
            }
            return "Last export of this day from this iPhone: \(verified), data up to \(cutoff)"
        }
    }

    static func cutoffText(_ dataAsOf: String, verifiedAt: Date, calendar: Calendar) -> String? {
        guard let cutoff = cutoffDate(dataAsOf) else { return nil }
        // A whole earlier day ends at the next midnight; "00:00" alone would
        // read as no data, so that cutoff is always shown in full.
        if calendar.isDate(cutoff, inSameDayAs: verifiedAt), cutoff > calendar.startOfDay(for: cutoff) {
            let formatter = DateFormatter()
            formatter.calendar = calendar
            formatter.timeZone = calendar.timeZone
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "HH:mm"
            return formatter.string(from: cutoff)
        }
        return HealthReportFormatter.dateAndTime(cutoff, calendar: calendar)
    }

    struct DeveloperField: Equatable {
        let label: String
        let value: String
    }

    /// The raw record fields for Developer tools: report date, the stored
    /// `dataAsOf` token, `verifiedAt` (ISO 8601) and whether an operation is pending.
    static func developerFields(_ lookup: DailyExportLastExportLookup) -> [DeveloperField] {
        let dataAsOf: String
        let verifiedAt: String
        switch lookup.state {
        case .none:
            dataAsOf = "None"
            verifiedAt = "None"
        case .unknown:
            dataAsOf = "Unreadable"
            verifiedAt = "Unreadable"
        case .verified(let date, let token):
            dataAsOf = token
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime]
            verifiedAt = formatter.string(from: date)
        }
        return [
            DeveloperField(label: "Selected day", value: lookup.reportDate),
            DeveloperField(label: "Data as of token", value: dataAsOf),
            DeveloperField(label: "Verified at", value: verifiedAt),
            DeveloperField(label: "Pending operation", value: lookup.hasPendingOperation ? "Yes" : "No")
        ]
    }

    /// The cutoff of an ISO 8601 token or of a "historical-v2|cutoff|encoded"
    /// token; `nil` for anything else, including another version prefix.
    static func cutoffDate(_ dataAsOf: String) -> Date? {
        let parts = dataAsOf.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        let timestamp: String
        switch parts.count {
        case 1: timestamp = dataAsOf
        case 3 where parts[0] == historicalOrderingVersion: timestamp = parts[1]
        default: return nil
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: timestamp)
    }
}
