import Foundation

/// The query and aggregation windows for one daily HealthKit statistics
/// collection, derived from the calendar that built the report days
/// (docs/healthkit-day-bucketing-v1.md section 2). The adapter takes its
/// anchor, interval and days from here so they cannot drift apart.
struct DailyBucketPlan: Equatable {
    static let policyIdentifier = "healthkit_day_buckets_injected_calendar_v1"

    let queryInterval: DateInterval
    let anchorDate: Date
    let intervalComponents: DateComponents
    let days: [DateInterval]
    /// The next local midnight after each day's start. A correct day bucket
    /// ends there, including the last one when the query stops at a frozen
    /// cutoff: HealthKit's buckets end at interval boundaries, not at the
    /// predicate's end.
    let expectedBucketEnds: [Date]

    init?(period: ReportPeriod, calendar: Calendar) {
        self.init(interval: period.interval, days: period.completedDays, calendar: calendar)
    }

    /// Accepts the days only when they are consecutive local days in
    /// `calendar` that exactly cover `interval`. Every day but the last must be
    /// a whole calendar day; the last may end early at a frozen cutoff (the
    /// Daily JSON export's today so far). Returns nil otherwise, which tells
    /// the adapter not to trust a collection for these days.
    init?(interval: DateInterval, days: [DateInterval], calendar: Calendar) {
        guard let first = days.first, let last = days.last,
              first.start == interval.start,
              last.end == interval.end
        else { return nil }
        var ends: [Date] = []
        for (index, day) in days.enumerated() {
            guard calendar.startOfDay(for: day.start) == day.start,
                  let nextMidnight = calendar.date(byAdding: .day, value: 1, to: day.start),
                  day.duration > 0
            else { return nil }
            if index < days.count - 1 {
                guard day.end == nextMidnight, days[index + 1].start == day.end else { return nil }
            } else {
                guard day.end <= nextMidnight else { return nil }
            }
            ends.append(nextMidnight)
        }
        self.queryInterval = interval
        self.anchorDate = calendar.startOfDay(for: interval.start)
        self.intervalComponents = DateComponents(day: 1)
        self.days = days
        self.expectedBucketEnds = ends
    }
}

/// One returned collection bucket that carries a statistic. Buckets without
/// samples are not represented: they are neither values nor mismatches.
struct DailyBucket<Value> {
    let start: Date
    let end: Date
    let value: Value
}

enum DailyBucketAlignment {
    struct Match<Value> {
        /// One entry per report day, in day order; nil where no bucket matched.
        let values: [Value?]
        /// Starts of buckets that do not span exactly one report day, or that
        /// repeat a day already matched.
        let mismatchedBucketStarts: [Date]

        var requiresFallback: Bool { !mismatchedBucketStarts.isEmpty }
    }

    /// Attaches a bucket to a report day only when it starts at the day's
    /// start and ends at the day's next local midnight. Checking the end as
    /// well catches a fixed 24 hour bucket on a 23 hour day, which would carry
    /// the first hour of the next day even when the next bucket is empty. The
    /// last day also accepts a bucket clipped to its own end (a frozen cutoff).
    /// A bucket never lands on a neighbouring day and never replaces a value
    /// already attached.
    static func match<Value>(_ buckets: [DailyBucket<Value>], plan: DailyBucketPlan) -> Match<Value> {
        let days = plan.days
        var indexByStart: [Date: Int] = [:]
        for (index, day) in days.enumerated() where indexByStart[day.start] == nil {
            indexByStart[day.start] = index
        }
        var values = [Value?](repeating: nil, count: days.count)
        var filled = Set<Int>()
        var mismatched: [Date] = []
        for bucket in buckets {
            guard let index = indexByStart[bucket.start], !filled.contains(index),
                  bucket.end == plan.expectedBucketEnds[index]
                    || (index == days.count - 1 && bucket.end == days[index].end)
            else {
                mismatched.append(bucket.start)
                continue
            }
            values[index] = bucket.value
            filled.insert(index)
        }
        return Match(values: values, mismatchedBucketStarts: mismatched)
    }

    static func match(bucketIntervals: [DateInterval], plan: DailyBucketPlan) -> Match<Void> {
        match(
            bucketIntervals.map { DailyBucket(start: $0.start, end: $0.end, value: ()) },
            plan: plan
        )
    }
}

enum DailyBucketFallbackReason: Equatable, Sendable {
    /// At least one returned bucket did not span exactly one report day.
    case bucketMismatch
    /// The report days were not consecutive days of the supplied calendar.
    case planRejected
}

enum DailyBucketReadOutcome: Equatable, Sendable {
    case aligned
    case perDayFallback(reason: DailyBucketFallbackReason, mismatchedBucketCount: Int)
}

/// Developer tools record of one daily read (decision 5: shown nowhere else).
struct DailyBucketReadRecord: Equatable, Sendable {
    let metric: String
    let interval: DateInterval
    let timeZoneIdentifier: String
    let dayCount: Int
    let outcome: DailyBucketReadOutcome
}

/// Orchestrates one daily read: trust the collection only when every bucket
/// lands exactly on a report day; otherwise discard it and read each day over
/// its exact interval. Owns no HealthKit types; the adapter supplies both reads.
enum DailyBucketReader {
    struct Result<Value> {
        let values: [Value?]
        let outcome: DailyBucketReadOutcome
    }

    static func read<Value>(
        days: [DateInterval],
        plan: DailyBucketPlan?,
        collection: (DailyBucketPlan) async throws -> [DailyBucket<Value>],
        perDay: (DateInterval) async throws -> Value?
    ) async throws -> Result<Value> {
        guard let plan else {
            return Result(
                values: try await readEachDay(days, perDay: perDay),
                outcome: .perDayFallback(reason: .planRejected, mismatchedBucketCount: 0)
            )
        }
        let match = DailyBucketAlignment.match(try await collection(plan), plan: plan)
        guard match.requiresFallback else {
            return Result(values: match.values, outcome: .aligned)
        }
        return Result(
            values: try await readEachDay(plan.days, perDay: perDay),
            outcome: .perDayFallback(
                reason: .bucketMismatch,
                mismatchedBucketCount: match.mismatchedBucketStarts.count
            )
        )
    }

    private static func readEachDay<Value>(
        _ days: [DateInterval],
        perDay: (DateInterval) async throws -> Value?
    ) async throws -> [Value?] {
        var values: [Value?] = []
        values.reserveCapacity(days.count)
        for day in days {
            try Task.checkCancellation()
            values.append(try await perDay(day))
        }
        return values
    }
}

extension NutritionNutrientTotals {
    /// The days one nutrition collection covers: the previous seven completed
    /// days, the context's seven, then today so far when it is not empty.
    static func collectionDays(
        window: DailyExportWindow,
        previous: ReportPeriod
    ) -> [DateInterval] {
        previous.completedDays + window.context.completedDays
            + (window.day.duration > 0 ? [window.day] : [])
    }

    /// Assembles one nutrient's totals from values read for `collectionDays`.
    /// A day without a value stays absent, never zero.
    init(
        key: String,
        window: DailyExportWindow,
        previous: ReportPeriod,
        days: [DateInterval],
        values: [Double?]
    ) {
        var valueByStart: [Date: Double] = [:]
        for (day, value) in zip(days, values) {
            if let value { valueByStart[day.start] = value }
        }
        self.init(
            key: key,
            today: window.day.duration > 0 ? valueByStart[window.day.start] : nil,
            currentDays: window.context.completedDays.map {
                NutritionDailyTotal(day: $0.start, value: valueByStart[$0.start])
            },
            previousDays: previous.completedDays.map {
                NutritionDailyTotal(day: $0.start, value: valueByStart[$0.start])
            }
        )
    }
}
