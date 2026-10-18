import Foundation

/// Keeps the latest daily-bucket read outcome per metric and interval for
/// Developer tools (docs/healthkit-day-bucketing-v1.md decision 5). Process
/// local and never persisted or exported. The lock guards the whole list.
final class DailyBucketReadLog: @unchecked Sendable {
    static let shared = DailyBucketReadLog()

    private let lock = NSLock()
    private let capacity: Int
    private var entries: [DailyBucketReadRecord] = []

    init(capacity: Int = 64) {
        self.capacity = max(1, capacity)
    }

    func record(_ record: DailyBucketReadRecord) {
        lock.withLock {
            entries.removeAll {
                $0.metric == record.metric && $0.interval == record.interval
            }
            entries.append(record)
            if entries.count > capacity {
                entries.removeFirst(entries.count - capacity)
            }
        }
    }

    /// Newest first.
    func records() -> [DailyBucketReadRecord] {
        lock.withLock { entries.reversed() }
    }
}
