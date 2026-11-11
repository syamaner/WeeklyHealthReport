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

// MARK: - Individual readings for the Daily JSON export (#469)

/// One visible HealthKit glucose sample as plain values, exactly as read.
/// Nothing is filtered at the query boundary: `GlucoseReadingsProjection`
/// decides what counts as a single point reading.
struct GlucoseReadingSample: Equatable {
    /// Internal tie-break only. Never exported.
    let id: UUID
    let start: Date
    let end: Date
    /// HealthKit's `count`: 1 for an ordinary sample, more for a series.
    let quantityCount: Int
    let millimolesPerLiter: Double
    let sourceName: String
    let sourceBundleIdentifier: String
}

enum GlucoseReadingsPolicy {
    static let readingsVersion = 1
    /// Safety bound for one export day. A 5-minute source produces 288.
    static let maximumReadingsPerDay = 2_000
    static let unit = "mmol/L"
}

/// Pure rules for the export's `glucose_readings` block
/// (docs/glucose-readings-export-contract-v1.md). Readings are grouped by
/// source and never merged, resampled, interpolated or deduplicated.
enum GlucoseReadingsProjection {
    struct Series: Equatable {
        let sourceName: String
        let sourceBundleIdentifier: String
        let readings: [GlucoseReadingSample]
    }

    enum Outcome: Equatable {
        case available([Series])
        /// The read succeeded and nothing was visible in the window. Not
        /// zero, and not proof that access was denied.
        case noDataOrAccess
        case limitExceeded
        case invalidEvidence
    }

    /// `samples` is everything the query returned for the window, up to the
    /// bound plus one. A reading belongs to the window when its start instant
    /// is inside it, start included and end excluded.
    static func project(
        _ samples: [GlucoseReadingSample],
        in window: DateInterval
    ) -> Outcome {
        // More than the bound means the list may be incomplete, so no
        // partial list is exported.
        guard samples.count <= GlucoseReadingsPolicy.maximumReadingsPerDay else {
            return .limitExceeded
        }
        let visible = samples.filter { $0.start >= window.start && $0.start < window.end }
        guard !visible.isEmpty else { return .noDataOrAccess }
        guard visible.allSatisfy(isPointReading) else { return .invalidEvidence }

        struct SourceKey: Hashable {
            let bundleIdentifier: String
            let name: String
        }
        let grouped = Dictionary(grouping: visible) {
            SourceKey(bundleIdentifier: $0.sourceBundleIdentifier, name: $0.sourceName)
        }
        let series = grouped.keys.sorted {
            ($0.bundleIdentifier, $0.name) < ($1.bundleIdentifier, $1.name)
        }.map { key in
            Series(
                sourceName: key.name,
                sourceBundleIdentifier: key.bundleIdentifier,
                readings: (grouped[key] ?? []).sorted {
                    ($0.start, $0.millimolesPerLiter, $0.id.uuidString)
                        < ($1.start, $1.millimolesPerLiter, $1.id.uuidString)
                }
            )
        }
        return .available(series)
    }

    /// A single reading at one instant with a usable value and source. A
    /// series sample's quantity is not one reading, and a sample with a
    /// duration is not a point; v1 exports neither (decision D6).
    private static func isPointReading(_ sample: GlucoseReadingSample) -> Bool {
        sample.quantityCount == 1
            && sample.start == sample.end
            && sample.millimolesPerLiter.isFinite
            && sample.millimolesPerLiter > 0
            && !sample.sourceName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !sample.sourceBundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
