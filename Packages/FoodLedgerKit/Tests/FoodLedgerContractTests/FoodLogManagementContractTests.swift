import Foundation
import FoodLedgerApplication
import FoodLedgerArchive
import FoodLedgerDomain
import FoodLedgerGRDB
import XCTest

final class FoodLogManagementContractTests: XCTestCase {
    func testLegacyLogPayloadReencodesExactlyWithoutInventingPlateReference() throws {
        let legacy = Data(#"{"composition":{"product":{"_0":"00000000-0000-0000-0000-000000000003"}},"createdAt":1700000000000,"edibleQuantity":{"unit":"g","value":150},"effectiveResolutionVersionID":"00000000-0000-0000-0000-000000000005","logItemID":"00000000-0000-0000-0000-000000000800","logItemVersionID":"00000000-0000-0000-0000-000000000801","occurredAt":1700000000000,"ordinal":1,"originalResolutionVersionID":"00000000-0000-0000-0000-000000000005","reportingDate":"2023-11-14"}"#.utf8)
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .millisecondsSince1970
        let decoded = try decoder.decode(LogItemVersion.self, from: legacy)
        XCTAssertNil(decoded.plateWeightVersionID)
        XCTAssertEqual(try LedgerFixtures.encoder.encode(decoded), legacy)
    }

    func testBothStoresRetainHistoryThroughRemoveRestoreAndArchiveReplay() throws {
        for harness in try LedgerFixtures.harnesses() {
            defer { harness.cleanup() }
            let archive = try XCTUnwrap(harness.committer as? any FoodArchiveLedgerAccess)
            let ledger = try LedgerFixtures.service(harness.committer)
            var mutation = try LedgerFixtures.baseMutation()
            let plate = Plate(plateID: try LedgerFixtures.id(804, PlateTag.self), createdAt: LedgerFixtures.date)
            let weight = try PlateWeightVersion(plateWeightVersionID: LedgerFixtures.id(805, PlateWeightVersionTag.self),
                plateID: plate.plateID, ordinal: VersionOrdinal(1),
                emptyWeight: PositiveQuantity(value: 300, unit: .grams), createdAt: LedgerFixtures.date)
            mutation.plates = [plate]; mutation.plateWeightVersions = [weight]
            let original = try LogItemVersion(logItemVersionID: LedgerFixtures.id(801, LogItemVersionTag.self),
                logItemID: LedgerFixtures.id(800, LogItemTag.self), ordinal: VersionOrdinal(1),
                occurredAt: LedgerFixtures.date, reportingDate: LedgerText("2023-11-14"),
                composition: .product(LedgerFixtures.id(3, ProductVersionTag.self)),
                edibleQuantity: PositiveQuantity(value: 150, unit: .grams),
                plateWeightVersionID: weight.plateWeightVersionID,
                originalResolutionVersionID: LedgerFixtures.id(5, ResolutionVersionTag.self),
                effectiveResolutionVersionID: LedgerFixtures.id(5, ResolutionVersionTag.self), createdAt: LedgerFixtures.date)
            mutation.logItems = [LogItem(logItemID: original.logItemID, createdAt: LedgerFixtures.date)]
            mutation.logItemVersions = [original]
            _ = try ledger.commit(mutation, type: .recordLogItem, operationID: LedgerFixtures.operationID(800))
            let originalState = try archive.archiveState()
            XCTAssertEqual(originalState.records.logItemVersions.first?.plateWeightVersionID, weight.plateWeightVersionID)
            XCTAssertThrowsError(try CanonicalFoodProjection(records: originalState.records, foodContractVersion: 1))
            let management = FoodLogManagementService(ledger: ledger,
                reader: ArchiveFoodLogHistoryReader(archive: archive), clock: LedgerFixtures.clock,
                ids: RandomLedgerIDGenerator())
            let alteredRemoval = try LogItemVersion(logItemVersionID: LedgerFixtures.id(899, LogItemVersionTag.self),
                logItemID: original.logItemID, ordinal: VersionOrdinal(2),
                supersedesLogItemVersionID: original.logItemVersionID,
                occurredAt: original.occurredAt, reportingDate: original.reportingDate,
                composition: .removed(original.logItemVersionID),
                edibleQuantity: PositiveQuantity(value: 151, unit: .grams),
                plateWeightVersionID: weight.plateWeightVersionID,
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
            var competingRecords = removedState.records
            competingRecords.logItemVersions.append(try LogItemVersion(
                logItemVersionID: LedgerFixtures.id(898, LogItemVersionTag.self),
                logItemID: original.logItemID, ordinal: VersionOrdinal(2),
                supersedesLogItemVersionID: original.logItemVersionID,
                occurredAt: original.occurredAt, reportingDate: original.reportingDate,
                composition: original.composition, edibleQuantity: original.edibleQuantity,
                plateWeightVersionID: weight.plateWeightVersionID,
                originalResolutionVersionID: original.originalResolutionVersionID,
                effectiveResolutionVersionID: original.effectiveResolutionVersionID,
                correctionReason: LedgerText("Competing correction"), createdAt: LedgerFixtures.date))
            XCTAssertThrowsError(try FoodIntakeProjection(records: competingRecords, reportingDate: "2023-11-14"))

            XCTAssertThrowsError(try management.remove(logItemID: original.logItemID,
                expectedVersion: original.logItemVersionID, reason: LedgerText("Stale action"),
                operationID: LedgerFixtures.operationID(802)))
            let bundle = try FoodArchiveGenerator().generate(state: removedState,
                ledgerID: LedgerText("removal-contract"), createdAt: LedgerFixtures.date,
                creatingActorID: LedgerFixtures.id(900, ActorTag.self))
            let verified = try FoodArchiveVerifier().verify(bundle)
            XCTAssertEqual(verified.document.projection.foodContractVersion, CanonicalFoodProjection.foodContractVersion)
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
            XCTAssertEqual(restored.plateWeightVersionID, weight.plateWeightVersionID)
            XCTAssertTrue(restoredState.records.logItemVersions.allSatisfy { $0.plateWeightVersionID == weight.plateWeightVersionID })
            let before = try FoodIntakeProjection(records: originalState.records, reportingDate: "2023-11-14")
            let after = try FoodIntakeProjection(records: restoredState.records, reportingDate: "2023-11-14")
            XCTAssertEqual(after.summary, before.summary)
            XCTAssertTrue(after.removedRows.isEmpty)
            XCTAssertEqual(after.rows.first?.totals.first(where: { $0.key == .protein })?.knownAmount, 15)
        }
    }
}
