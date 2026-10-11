import Foundation
import FoodLedgerDomain

/// One Food Log day as structured facts (#197). Totals come from `FoodIntakeSummary` unchanged;
/// presentation formats them. No text is produced here.
public struct FoodLogDayContent: Sendable {
    /// Nutrients in the totals strip and the only ones flagged per entry (F1, F3). Water stays
    /// out until #198 settles what the label means.
    public static let stripKeys: [NutrientKey] = [.energyConsumed, .protein, .carbohydrates, .fatTotal]

    public struct Entry: Sendable, Equatable {
        public let logItemID: LogItemID
        public let logItemVersionID: LogItemVersionID
        public let occurredAt: Date
        public let name: String
        public let quantity: PositiveQuantity
        /// Energy for the amount; nil when it is unknown, bounded or cannot be scaled.
        public let energyKcal: Double?
        public let isEstimate: Bool
        /// Strip nutrients this entry cannot contribute, in strip order.
        public let unknownKeys: [NutrientKey]
    }

    public struct RemovedEntry: Sendable, Equatable {
        public let logItemID: LogItemID
        public let logItemVersionID: LogItemVersionID
        public let occurredAt: Date
        public let name: String
        public let quantity: PositiveQuantity
        public let removedAt: Date?
    }

    public let reportingDate: String
    /// Strip totals in strip order; nil when the day has no current entries (empty is not zero).
    public let totals: [FoodIntakeTotal]?
    public let entries: [Entry]
    public let removed: [RemovedEntry]

    /// `estimates` is the set of entries whose current version is a labelled estimate; the caller
    /// computes it from stored evidence (`FoodEntryEstimateStatus`).
    public init(projection: FoodIntakeProjection, reportingDate: String, estimates: Set<LogItemID>) {
        self.reportingDate = reportingDate
        totals = projection.rows.isEmpty ? nil : Self.stripKeys.compactMap { key in
            projection.summary.totals.first { $0.key == key }
        }
        entries = projection.rows.map { row in
            let known = Dictionary(row.totals.map { ($0.key, $0.knownAmount) }, uniquingKeysWith: { first, _ in first })
            return Entry(logItemID: row.logItemID, logItemVersionID: row.logItemVersionID, occurredAt: row.occurredAt,
                         name: row.name, quantity: row.quantity,
                         energyKcal: known[.energyConsumed] ?? nil,
                         isEstimate: estimates.contains(row.logItemID),
                         unknownKeys: Self.stripKeys.filter { (known[$0] ?? nil) == nil })
        }
        removed = projection.removedRows.map { row in
            RemovedEntry(logItemID: row.logItemID, logItemVersionID: row.logItemVersionID, occurredAt: row.occurredAt,
                         name: row.name, quantity: row.quantity, removedAt: row.removedAt)
        }
    }
}
