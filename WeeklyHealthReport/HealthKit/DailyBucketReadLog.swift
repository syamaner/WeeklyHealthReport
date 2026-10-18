import Foundation

extension Notification.Name {
    /// Posted after a Daily JSON export's HealthKit reads finish, successfully
    /// or not, so Developer tools can refresh its export section.
    static let dailyBucketExportReadsDidChange = Notification.Name(
        "WeeklyHealthReport.dailyBucketExportReadsDidChange"
    )
}

/// Keeps the latest daily-bucket read outcome per caller, metric and interval
/// for Developer tools (docs/healthkit-day-bucketing-v1.md decision 5).
/// Process local and never persisted or exported. The lock guards the list.
final class DailyBucketReadLog: @unchecked Sendable {
    static let shared = DailyBucketReadLog()

    /// The caller recorded for reads in the current task; the Daily JSON
    /// export sets `.dailyExport` around its reads.
    @TaskLocal static var currentReader: DailyBucketReadCaller = .healthReport

    private let lock = NSLock()
    private let capacity: Int
    private var entries: [DailyBucketReadRecord] = []

    init(capacity: Int = 64) {
        self.capacity = max(1, capacity)
    }

    func record(_ record: DailyBucketReadRecord) {
        lock.withLock {
            entries.removeAll {
                $0.reader == record.reader && $0.metric == record.metric
                    && $0.interval == record.interval
            }
            entries.append(record)
            if entries.count > capacity {
                entries.removeFirst(entries.count - capacity)
            }
        }
    }

    func removeRecords(for intervals: [DateInterval], reader: DailyBucketReadCaller) {
        lock.withLock {
            entries.removeAll { $0.reader == reader && intervals.contains($0.interval) }
        }
    }

    /// Newest first.
    func records() -> [DailyBucketReadRecord] {
        lock.withLock { entries.reversed() }
    }
}
