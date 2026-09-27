import Foundation
import FoodLedgerApplication
import FoodLedgerArchive
import FoodLedgerDomain
import FoodLedgerGRDB
import XCTest

final class FoodLogManagementContractTests: XCTestCase {
    func testBothStoresRetainHistoryThroughRemoveRestoreAndArchiveReplay() throws {
        for harness in try LedgerFixtures.harnesses() {
            defer { harness.cleanup() }
            let archive = try XCTUnwrap(harness.committer as? any FoodArchiveLedgerAccess)
            let ledger = try LedgerFixtures.service(harness.committer)
            var mutation = try LedgerFixtures.baseMutation()
            let original = try LogItemVersion(logItemVersionID: LedgerFixtures.id(801, LogItemVersionTag.self),
                logItemID: LedgerFixtures.id(800, LogItemTag.self), ordinal: VersionOrdinal(1),
                occurredAt: LedgerFixtures.date, reportingDate: LedgerText("2023-11-14"),
                composition: .product(LedgerFixtures.id(3, ProductVersionTag.self)),
                edibleQuantity: PositiveQuantity(value: 150, unit: .grams),
                originalResolutionVersionID: LedgerFixtures.id(5, ResolutionVersionTag.self),
                effectiveResolutionVersionID: LedgerFixtures.id(5, ResolutionVersionTag.self), createdAt: LedgerFixtures.date)
            mutation.logItems = [LogItem(logItemID: original.logItemID, createdAt: LedgerFixtures.date)]
            mutation.logItemVersions = [original]
            _ = try ledger.commit(mutation, type: .recordLogItem, operationID: LedgerFixtures.operationID(800))
            let originalState = try archive.archiveState()
            let management = FoodLogManagementService(ledger: ledger,
                reader: ArchiveFoodLogHistoryReader(archive: archive), clock: LedgerFixtures.clock,
                ids: RandomLedgerIDGenerator())
            let alteredRemoval = try LogItemVersion(logItemVersionID: LedgerFixtures.id(899, LogItemVersionTag.self),
                logItemID: original.logItemID, ordinal: VersionOrdinal(2),
                supersedesLogItemVersionID: original.logItemVersionID,
                occurredAt: original.occurredAt, reportingDate: original.reportingDate,
                composition: .removed(original.logItemVersionID),
                edibleQuantity: PositiveQuantity(value: 151, unit: .grams),
                originalResolutionVersionID: original.originalResolutionVersionID,
                effectiveResolutionVersionID: original.effectiveResolutionVersionID,
                correctionReason: LedgerText("Must not alter retained quantity"), createdAt: LedgerFixtures.date)
            XCTAssertThrowsError(try ledger.commit(LedgerMutation(logItemVersions: [alteredRemoval]),
                type: .removeLogItem, operationID: LedgerFixtures.operationID(899)))
            XCTAssertEqual(try archive.counts().logItemVersions, 1)
            let removed = try management.remove(logItemID: original.logItemID,
                expectedVersion: original.logItemVersionID, reason: LedgerText("Accidental log"),
                operationID: LedgerFixtures.operationID(801))
            let removedState = try archive.archiveState()
            XCTAssertThrowsError(try CanonicalFoodProjection(records: removedState.records, foodContractVersion: 1))
            let removedDay = try FoodIntakeProjection(records: removedState.records, reportingDate: "2023-11-14")
            XCTAssertEqual(removedDay.summary.itemCount, 0, harness.name)
            XCTAssertEqual(removedDay.removedRows.first?.logItemVersionID, removed.logItemVersionID)
            XCTAssertNil(try harness.reader.foodConfirmation(logItemID: original.logItemID))
            XCTAssertThrowsError(try management.remove(logItemID: original.logItemID,
                expectedVersion: original.logItemVersionID, reason: LedgerText("Stale action"),
                operationID: LedgerFixtures.operationID(802)))
            let bundle = try FoodArchiveGenerator().generate(state: removedState,
                ledgerID: LedgerText("removal-contract"), createdAt: LedgerFixtures.date,
                creatingActorID: LedgerFixtures.id(900, ActorTag.self))
            let verified = try FoodArchiveVerifier().verify(bundle)
            XCTAssertEqual(verified.document.projection.foodContractVersion, 2)
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: directory) }
            let staged = try ProtectedGRDBFoodArchiveStaging(root: directory).validate(verified.transactions)
            XCTAssertEqual(try CanonicalFoodProjection(records: staged.records),
                           try CanonicalFoodProjection(records: removedState.records))
            let restored = try management.restore(logItemID: original.logItemID,
                expectedVersion: removed.logItemVersionID, reason: LedgerText("Restore retained entry"),
                operationID: LedgerFixtures.operationID(803))
            let restoredState = try archive.archiveState()
            XCTAssertEqual(restoredState.records.logItemVersions.count, 3)
            XCTAssertEqual(restoredState.records.evidence, originalState.records.evidence)
            XCTAssertEqual(restoredState.records.resolutionVersions, originalState.records.resolutionVersions)
            XCTAssertEqual(restored.occurredAt, original.occurredAt)
            XCTAssertEqual(restored.reportingDate, original.reportingDate)
            XCTAssertEqual(restored.edibleQuantity, original.edibleQuantity)
            let before = try FoodIntakeProjection(records: originalState.records, reportingDate: "2023-11-14")
            let after = try FoodIntakeProjection(records: restoredState.records, reportingDate: "2023-11-14")
            XCTAssertEqual(after.summary, before.summary)
            XCTAssertTrue(after.removedRows.isEmpty)
            XCTAssertEqual(after.rows.first?.totals.first(where: { $0.key == .protein })?.knownAmount, 15)
        }
    }
}
