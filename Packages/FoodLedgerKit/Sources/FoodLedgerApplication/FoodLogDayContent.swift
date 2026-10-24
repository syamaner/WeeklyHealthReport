import Foundation
import FoodLedgerDomain

/// One Food Log day as structured facts (#197). Totals come from `FoodIntakeSummary` unchanged;
/// presentation formats them. No text is produced here.
public struct FoodLogDayContent: Sendable {
    /// Nutrients in the totals strip (F1, amended by F10 on 23 October 2026, #288: fibre after fat).
    /// Water is not a strip nutrient: the strip shows plain water logged separately (#198, Q8).
    public static let stripKeys: [NutrientKey] = [.energyConsumed, .protein, .carbohydrates, .fatTotal, .fiber]

    /// The only nutrients flagged per entry and the saved entry's main nutrition rows (F3). Fibre is
    /// a strip total but not a per-entry flag; in the saved entry it stays under "All nutrients".
    public static let entryFlagKeys: [NutrientKey] = [.energyConsumed, .protein, .carbohydrates, .fatTotal]

    public struct Entry: Sendable, Equatable {
        public let logItemID: LogItemID
        public let logItemVersionID: LogItemVersionID
        public let occurredAt: Date
        public let name: String
        public let quantity: PositiveQuantity
        /// Energy for the amount; nil when it is unknown, bounded or cannot be scaled.
        public let energyKcal: Double?
        /// A labelled estimate: the saved decisions say so (`FoodEntryEstimateStatus`) or the
        /// entry's own contribution includes estimated values (augmented nutrients or an estimated
        /// weight). Shown once.
        public let isEstimate: Bool
        /// Flagged nutrients (`entryFlagKeys`) this entry cannot contribute, in strip order.
        public let unknownKeys: [NutrientKey]
        /// Energy stated only as an upper bound, shown as a bound when `energyKcal` is nil.
        public var energyUpperBound: FoodEnergyUpperBound? = nil
        /// The amount as entered ("3 pieces"), when it differs from `quantity`.
        public var enteredAmount: PositiveQuantity? = nil
        /// How the amount was obtained (count-portion-estimate-v1, C7).
        public var quantityMethod: FoodQuantityMethod = .direct
        /// A count of servings, not pieces.
        public var amountIsServings: Bool = false
    }

    public struct RemovedEntry: Sendable, Equatable {
        public let logItemID: LogItemID
        public let logItemVersionID: LogItemVersionID
        public let occurredAt: Date
        public let name: String
        public let quantity: PositiveQuantity
        public let removedAt: Date?

        public init(logItemID: LogItemID, logItemVersionID: LogItemVersionID, occurredAt: Date, name: String,
                    quantity: PositiveQuantity, removedAt: Date?) {
            self.logItemID = logItemID; self.logItemVersionID = logItemVersionID; self.occurredAt = occurredAt
            self.name = name; self.quantity = quantity; self.removedAt = removedAt
        }
    }

    public let reportingDate: String
    /// Strip totals in strip order; nil when the day has no current entries (empty is not zero).
    public let totals: [FoodIntakeTotal]?
    public let entries: [Entry]
    public let removed: [RemovedEntry]
    /// Plain water logged on this day in mL (#198, Q8), the same figure as Home. Nil when none is
    /// logged (No data, never 0 mL); a known minimum when an entry cannot be scaled.
    public let plainWater: FoodIntakeTotal?
    /// Current entries that are not plain water (`food-intake-summary-v6`, #304). With entries but
    /// none of them food, the strip shows the no-food copy instead of its nutrient totals.
    public let foodEntryCount: Int
    /// Whether the strip shows nutrient totals: some current entry is food.
    public var showsFoodTotals: Bool { totals != nil && foodEntryCount > 0 }

    /// `estimates` is the set of entries whose current version is a labelled estimate; the caller
    /// computes it from stored evidence (`FoodEntryEstimateStatus`).
    public init(projection: FoodIntakeProjection, reportingDate: String, estimates: Set<LogItemID>,
                plainWater: FoodIntakeTotal? = nil) {
        self.reportingDate = reportingDate
        self.plainWater = plainWater
        foodEntryCount = projection.summary.foodItemCount
        totals = projection.rows.isEmpty ? nil : Self.stripKeys.compactMap { key in
            projection.summary.totals.first { $0.key == key }
        }
        entries = projection.rows.map { row in
            let known = Dictionary(row.totals.map { ($0.key, $0.knownAmount) }, uniquingKeysWith: { first, _ in first })
            return Entry(logItemID: row.logItemID, logItemVersionID: row.logItemVersionID, occurredAt: row.occurredAt,
                         name: row.name, quantity: row.quantity,
                         energyKcal: known[.energyConsumed] ?? nil,
                         isEstimate: estimates.contains(row.logItemID) || row.totals.contains { $0.includesEstimates }
                            || row.quantityMethod.isEstimate
                            || row.energyUpperBound?.isCalculated == true,
                         unknownKeys: Self.entryFlagKeys.filter { (known[$0] ?? nil) == nil },
                         energyUpperBound: row.energyUpperBound,
                         enteredAmount: row.enteredAmount, quantityMethod: row.quantityMethod,
                         amountIsServings: row.amountIsServings)
        }
        removed = projection.removedRows.map { row in
            RemovedEntry(logItemID: row.logItemID, logItemVersionID: row.logItemVersionID, occurredAt: row.occurredAt,
                         name: row.name, quantity: row.quantity, removedAt: row.removedAt)
        }
    }
}
