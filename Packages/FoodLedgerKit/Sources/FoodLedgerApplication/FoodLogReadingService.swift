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
        try day(reportingDate: reportingDate, records: try archive.archiveState().records)
    }

    /// The content `day(reportingDate:)` gives for each date, in order, from one archive read
    /// (#399): a period costs one read, not one per day. No read for no dates.
    public func days(reportingDates: [String]) throws -> [FoodLogDayContent] {
        guard !reportingDates.isEmpty else { return [] }
        let records = try archive.archiveState().records
        return try reportingDates.map { try day(reportingDate: $0, records: records) }
    }

    /// Whether the entry's current saved version is the app's plain water reference: the same
    /// answer as `savedEntry(_:)?.isPlainWater == true`, without reading the entry's history
    /// (#399). False when the entry is missing or removed.
    public func isPlainWater(_ logItemID: LogItemID) throws -> Bool {
        guard let stored = try confirmationReader.foodConfirmation(logItemID: logItemID) else { return false }
        return PlainWaterReference.isPlainWater(stored.resolutionVersion)
    }

    private func day(reportingDate: String, records: LedgerMutation) throws -> FoodLogDayContent {
        let projection = try FoodIntakeProjection(records: records, reportingDate: reportingDate)
        let status = statuses(projection.rows.map(\.logItemID))
        return FoodLogDayContent(projection: projection, reportingDate: reportingDate,
                                 estimates: status.estimates, partlyEstimated: status.partlyEstimated,
                                 openFoodFactsValues: status.openFoodFactsValues,
                                 plainWater: try PlainWaterDayTotal.total(records: records, reportingDate: reportingDate))
    }

    /// Nil when the entry is missing or removed.
    public func savedEntry(_ logItemID: LogItemID) throws -> SavedFoodEntryDetail? {
        guard let stored = try confirmationReader.foodConfirmation(logItemID: logItemID) else { return nil }
        let release = stored.sourceReleases.first { $0.sourceReleaseID == stored.candidateDecision.candidate.sourceReleaseID }
        let entered = FoodConfirmationService.lastEnteredAmount(stored.logItemVersion, conversion: stored.quantityConversion)
        let servings = FoodAmountServings.isServings(enteredUnit: entered.unit, conversion: stored.quantityConversion,
                                                     sourceID: release?.sourceID.value, basis: stored.resolution.basis)
        return SavedFoodEntryDetail(stored: stored, isEstimate: (try? confirmations.isEstimate(stored)) == true,
                                    history: try historyEvents(logItemID, isServings: servings))
    }

    /// One archive read serves both the versions and the conversions they reference (#399): the
    /// versions are the archive's own, as `ArchiveFoodLogHistoryReader` reads them.
    public func historyEvents(_ logItemID: LogItemID, isServings: Bool = false) throws -> [FoodEntryHistoryEvent] {
        let records = try archive.archiveState().records
        let versions = records.logItemVersions.filter { $0.logItemID == logItemID }
        let referenced = Set(versions.compactMap(\.quantityConversionVersionID))
        let conversions = referenced.isEmpty ? [] : records.quantityConversions
            .filter { referenced.contains($0.quantityConversionVersionID) }
        return FoodEntryHistory.events(versions: versions, conversions: conversions, isServings: isServings)
    }

    public func remove(_ logItemID: LogItemID, expected: LogItemVersionID) -> FoodLogChangeOutcome {
        change(logItemID, expected: expected, restoring: false)
    }

    public func restore(_ logItemID: LogItemID, expected: LogItemVersionID) -> FoodLogChangeOutcome {
        change(logItemID, expected: expected, restoring: true)
    }

    /// Entries whose current saved version is a labelled estimate, and those that carry a label
    /// estimate layer ("partly estimated"), and those whose only estimated values are Open Food
    /// Facts values (docs/off-values-label-v1.md). An unreadable entry is none of them.
    private func statuses(_ ids: [LogItemID])
        -> (estimates: Set<LogItemID>, partlyEstimated: Set<LogItemID>, openFoodFactsValues: Set<LogItemID>) {
        var estimates: Set<LogItemID> = [], partly: Set<LogItemID> = [], openFoodFacts: Set<LogItemID> = []
        for id in ids {
            guard let stored = try? confirmationReader.foodConfirmation(logItemID: id) else { continue }
            if (try? confirmations.isEstimate(stored)) == true { estimates.insert(id) }
            if FoodEntryEstimateStatus.isPartlyEstimated(stored) { partly.insert(id) }
            if OpenFoodFactsValues.areTheOnlyEstimates(stored.resolutionVersion.nutrients) { openFoodFacts.insert(id) }
        }
        return (estimates, partly, openFoodFacts)
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
