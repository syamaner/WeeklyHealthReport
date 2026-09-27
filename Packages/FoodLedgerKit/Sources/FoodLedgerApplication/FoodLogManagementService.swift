import Foundation
import FoodLedgerDomain

public protocol FoodLogHistoryReading: Sendable {
    func versions(for logItemID: LogItemID) throws -> [LogItemVersion]
    func change(operationID: OperationID) throws -> LedgerOperation?
}

public struct ArchiveFoodLogHistoryReader: FoodLogHistoryReading {
    private let archive: any FoodArchiveLedgerAccess
    public init(archive: any FoodArchiveLedgerAccess) { self.archive = archive }
    public func versions(for logItemID: LogItemID) throws -> [LogItemVersion] {
        try archive.archiveState().records.logItemVersions.filter { $0.logItemID == logItemID }
    }
    public func change(operationID: OperationID) throws -> LedgerOperation? {
        try archive.operation(id: operationID)
    }
}

public enum FoodLogManagementError: Error { case staleVersion, invalidTransition, conflictingVersions }

public struct FoodLogManagementService: Sendable {
    private let ledger: FoodLedgerService
    private let reader: any FoodLogHistoryReading
    private let clock: any LedgerClock
    private let ids: any LedgerIDGenerating

    public init(ledger: FoodLedgerService, reader: any FoodLogHistoryReading,
                clock: any LedgerClock, ids: any LedgerIDGenerating) {
        self.ledger = ledger; self.reader = reader; self.clock = clock; self.ids = ids
    }

    @discardableResult
    public func remove(logItemID: LogItemID, expectedVersion: LogItemVersionID,
                       reason: LedgerText, operationID: OperationID) throws -> LogItemVersion {
        try change(logItemID: logItemID, expectedVersion: expectedVersion, reason: reason,
                   operationID: operationID, restoring: false)
    }

    @discardableResult
    public func restore(logItemID: LogItemID, expectedVersion: LogItemVersionID,
                        reason: LedgerText, operationID: OperationID) throws -> LogItemVersion {
        try change(logItemID: logItemID, expectedVersion: expectedVersion, reason: reason,
                   operationID: operationID, restoring: true)
    }

    private func change(logItemID: LogItemID, expectedVersion: LogItemVersionID,
                        reason: LedgerText, operationID: OperationID, restoring: Bool) throws -> LogItemVersion {
        let type: LedgerOperationType = restoring ? .restoreLogItem : .removeLogItem
        if let operation = try reader.change(operationID: operationID) {
            let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .millisecondsSince1970
            let mutation = try decoder.decode(LedgerMutation.self, from: operation.payload)
            guard operation.operationType == type, mutation.logItemVersions.count == 1,
                  let saved = mutation.logItemVersions.first, saved.logItemID == logItemID,
                  saved.supersedesLogItemVersionID == expectedVersion,
                  saved.correctionReason == reason else { throw FoodLogManagementError.invalidTransition }
            return saved
        }
        let versions = try reader.versions(for: logItemID)
        let superseded = Set(versions.compactMap(\.supersedesLogItemVersionID))
        let heads = versions.filter { !superseded.contains($0.logItemVersionID) }
        guard heads.count == 1 else { throw FoodLogManagementError.conflictingVersions }
        let head = heads[0]
        guard head.logItemVersionID == expectedVersion else { throw FoodLogManagementError.staleVersion }
        let original: LogItemVersion
        let composition: LogComposition
        if restoring {
            guard case let .removed(reference) = head.composition,
                  let retained = versions.first(where: { $0.logItemVersionID == reference }),
                  case .product = retained.composition else { throw FoodLogManagementError.invalidTransition }
            original = retained; composition = retained.composition
        } else {
            guard case .product = head.composition else { throw FoodLogManagementError.invalidTransition }
            original = head; composition = .removed(head.logItemVersionID)
        }
        let next = try LogItemVersion(logItemVersionID: ids.makeID(LogItemVersionTag.self),
            logItemID: logItemID, ordinal: VersionOrdinal(head.ordinal.value + 1),
            supersedesLogItemVersionID: head.logItemVersionID,
            occurredAt: original.occurredAt, reportingDate: original.reportingDate,
            composition: composition, edibleQuantity: original.edibleQuantity,
            quantityConversionVersionID: original.quantityConversionVersionID,
            plateWeightVersionID: original.plateWeightVersionID,
            originalResolutionVersionID: original.originalResolutionVersionID,
            effectiveResolutionVersionID: original.effectiveResolutionVersionID,
            correctionReason: reason, createdAt: clock.now())
        try next.validateRemovalTransition(predecessor: head, removedOriginal: restoring ? original : nil)
        _ = try ledger.commit(LedgerMutation(logItemVersions: [next]), type: type, operationID: operationID)
        return next
    }
}
