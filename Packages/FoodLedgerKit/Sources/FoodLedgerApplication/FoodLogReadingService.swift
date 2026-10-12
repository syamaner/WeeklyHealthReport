import Foundation
import FoodLedgerDomain

/// The result of a remove or restore from the Food Log or a saved entry.
public enum FoodLogChangeOutcome: Equatable, Sendable {
    case applied
    /// The entry changed elsewhere since it was shown (stale or competing versions); nothing was written.
    case changedElsewhere
    /// The change could not be saved; nothing was written.
    case notSaved
}

/// Food Log orchestration (#197): day content, saved-entry detail, remove and restore. No text
/// for presentation and no view state; the reason strings are persisted data and fixed here.
public struct FoodLogReadingService: Sendable {
    public static let removalReason = "Removed by user from Food Log"
    public static let restorationReason = "Restored by user from Food Log"

    private let ledger: FoodLedgerService
    private let archive: any FoodArchiveLedgerAccess
    private let confirmationReader: any FoodConfirmationReading
    private let history: any FoodLogHistoryReading
    private let confirmations: FoodConfirmationService
    private let clock: any LedgerClock
    private let ids: any LedgerIDGenerating

    public init(ledger: FoodLedgerService, archive: any FoodArchiveLedgerAccess,
                confirmationReader: any FoodConfirmationReading, history: any FoodLogHistoryReading,
                confirmations: FoodConfirmationService, clock: any LedgerClock, ids: any LedgerIDGenerating) {
        self.ledger = ledger; self.archive = archive; self.confirmationReader = confirmationReader
        self.history = history; self.confirmations = confirmations; self.clock = clock; self.ids = ids
    }

    /// Throws `FoodIntakeProjectionError` for competing versions, mixtures or missing references.
    public func day(reportingDate: String) throws -> FoodLogDayContent {
        let records = try archive.archiveState().records
        let projection = try FoodIntakeProjection(records: records, reportingDate: reportingDate)
        return FoodLogDayContent(projection: projection, reportingDate: reportingDate,
                                 estimates: estimates(projection.rows.map(\.logItemID)),
                                 plainWater: try PlainWaterDayTotal.total(records: records, reportingDate: reportingDate))
    }

    /// Nil when the entry is missing or removed.
    public func savedEntry(_ logItemID: LogItemID) throws -> SavedFoodEntryDetail? {
        guard let stored = try confirmationReader.foodConfirmation(logItemID: logItemID) else { return nil }
        return SavedFoodEntryDetail(stored: stored, isEstimate: (try? confirmations.isEstimate(stored)) == true,
                                    history: try historyEvents(logItemID))
    }

    public func historyEvents(_ logItemID: LogItemID) throws -> [FoodEntryHistoryEvent] {
        let versions = try history.versions(for: logItemID)
        let referenced = Set(versions.compactMap(\.quantityConversionVersionID))
        let conversions = referenced.isEmpty ? [] : try archive.archiveState().records.quantityConversions
            .filter { referenced.contains($0.quantityConversionVersionID) }
        return FoodEntryHistory.events(versions: versions, conversions: conversions)
    }

    public func remove(_ logItemID: LogItemID, expected: LogItemVersionID) -> FoodLogChangeOutcome {
        change(logItemID, expected: expected, restoring: false)
    }

    public func restore(_ logItemID: LogItemID, expected: LogItemVersionID) -> FoodLogChangeOutcome {
        change(logItemID, expected: expected, restoring: true)
    }

    /// Entries whose current saved version is a labelled estimate. An unreadable entry is not labelled.
    private func estimates(_ ids: [LogItemID]) -> Set<LogItemID> {
        Set(ids.filter { id in
            guard let stored = try? confirmationReader.foodConfirmation(logItemID: id) else { return false }
            return (try? confirmations.isEstimate(stored)) == true
        })
    }

    private func change(_ logItemID: LogItemID, expected: LogItemVersionID, restoring: Bool) -> FoodLogChangeOutcome {
        let management = FoodLogManagementService(ledger: ledger, reader: history, clock: clock, ids: ids)
        do {
            let operationID = try ids.makeID(OperationTag.self)
            let reason = try LedgerText(restoring ? Self.restorationReason : Self.removalReason)
            if restoring {
                try management.restore(logItemID: logItemID, expectedVersion: expected, reason: reason, operationID: operationID)
            } else {
                try management.remove(logItemID: logItemID, expectedVersion: expected, reason: reason, operationID: operationID)
            }
            return .applied
        } catch FoodLogManagementError.staleVersion, FoodLogManagementError.conflictingVersions {
            return .changedElsewhere
        } catch {
            return .notSaved
        }
    }
}
