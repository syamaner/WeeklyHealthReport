import Foundation
import FoodLedgerApplication
import FoodLedgerArchive
import FoodLedgerDomain
import FoodLedgerGRDB
import FoodLedgerTestSupport
import XCTest

/// Phase 4 (#197) Food Log orchestration against the memory and GRDB stores. No contract
/// changes: these pin that the new service only reads, removes and restores as before.
final class FoodLogReadingServiceContractTests: XCTestCase {
    // MARK: 1. Day content parity and the removed-only day

    func testDayContentIsIdenticalFromBothStoresAndARemovedOnlyDayHasNoTotals() throws {
        var results: [[String]] = []
        for harness in try LedgerFixtures.harnesses() {
            defer { harness.cleanup() }
            let (service, confirmations) = try services(harness)
            let first = try confirmations.save(try state(grams: 150, evidence: 40), operationID: LedgerFixtures.operationID(940))
            let second = try confirmations.save(try state(grams: 50, evidence: 41), operationID: LedgerFixtures.operationID(941))
            let day = first.logItemVersion.reportingDate.value
            let content = try service.day(reportingDate: day)
            XCTAssertEqual(content.entries.count, 2, harness.name)
            XCTAssertEqual(content.totals?.first { $0.key == .protein }?.knownAmount, 20, harness.name)
            results.append(content.entries.map { "\($0.name)|\($0.quantity.value)|\(String(describing: $0.energyKcal))|\($0.unknownKeys)" }
                + (content.totals ?? []).map { "\($0.key)|\(String(describing: $0.knownAmount))|\($0.incompleteContributions)" })

            for saved in [first, second] {
                XCTAssertEqual(service.remove(saved.logItem.logItemID, expected: saved.logItemVersion.logItemVersionID), .applied)
            }
            let removedOnly = try service.day(reportingDate: day)
            XCTAssertNil(removedOnly.totals, "\(harness.name): a removed-only day has no totals")
            XCTAssertTrue(removedOnly.entries.isEmpty)
            XCTAssertEqual(removedOnly.removed.count, 2)
            XCTAssertTrue(removedOnly.removed.allSatisfy { $0.removedAt == LedgerFixtures.date })
        }
        XCTAssertEqual(results.count, 2)
        XCTAssertEqual(results[0], results[1])
    }

    // MARK: 2. Fixed reason strings; 3. operation types; 4. changed elsewhere

    func testRemoveAndRestoreWriteFixedReasonsAndPinnedOperationTypes() throws {
        for harness in try LedgerFixtures.harnesses() {
            defer { harness.cleanup() }
            let (service, confirmations) = try services(harness)
            let archive = try XCTUnwrap(harness.committer as? any FoodArchiveLedgerAccess)
            var weighed = try state(grams: 2, evidence: 42)
            weighed.quantity = FoodQuantityDraft(value: 2, unit: .count, directWeight: DirectWeightDraft(totalGrams: 125, basis: .measured))
            for (index, entry) in [try state(grams: 150, evidence: 43), weighed].enumerated() {
                let saved = try confirmations.save(entry, operationID: LedgerFixtures.operationID(950 + index))
                let id = saved.logItem.logItemID
                let declared = saved.logItemVersion.weightDeclaration != nil
                XCTAssertEqual(declared, index == 1)
                var operations = try archive.archiveState().operations.map(\.operationID)
                XCTAssertEqual(service.remove(id, expected: saved.logItemVersion.logItemVersionID), .applied)
                let removed = try head(archive, id)
                XCTAssertEqual(removed.correctionReason?.value, "Removed by user from Food Log")
                XCTAssertEqual(try newTypes(archive, since: &operations), [declared ? .removeLogItemV2 : .removeLogItem], harness.name)
                XCTAssertEqual(service.restore(id, expected: removed.logItemVersionID), .applied)
                let restored = try head(archive, id)
                XCTAssertEqual(restored.correctionReason?.value, "Restored by user from Food Log")
                XCTAssertEqual(try newTypes(archive, since: &operations), [declared ? .restoreLogItemV2 : .restoreLogItem], harness.name)

                // The head moved since it was shown: nothing is written.
                let count = try archive.archiveState().records.logItemVersions.count
                XCTAssertEqual(service.remove(id, expected: saved.logItemVersion.logItemVersionID), .changedElsewhere)
                XCTAssertEqual(service.restore(id, expected: removed.logItemVersionID), .changedElsewhere)
                XCTAssertEqual(try archive.archiveState().records.logItemVersions.count, count)
            }
        }
    }

    private func head(_ archive: any FoodArchiveLedgerAccess, _ id: LogItemID) throws -> LogItemVersion {
        let versions = try archive.archiveState().records.logItemVersions.filter { $0.logItemID == id }
        let superseded = Set(versions.compactMap(\.supersedesLogItemVersionID))
        return try XCTUnwrap(versions.first { !superseded.contains($0.logItemVersionID) })
    }

    private func newTypes(_ archive: any FoodArchiveLedgerAccess, since known: inout [OperationID]) throws -> [LedgerOperationType] {
        let operations = try archive.archiveState().operations
        let fresh = operations.filter { !known.contains($0.operationID) }
        known = operations.map(\.operationID)
        return fresh.map(\.operationType)
    }

    /// Competing heads cannot be committed (the stores refuse them), so a reader that reports
    /// one stands in for a corrupted history.
    func testCompetingHeadsReportChangedElsewhere() throws {
        for harness in try LedgerFixtures.harnesses() {
            defer { harness.cleanup() }
            let (_, confirmations) = try services(harness)
            let saved = try confirmations.save(try state(grams: 150, evidence: 44), operationID: LedgerFixtures.operationID(955))
            let archive = try XCTUnwrap(harness.committer as? any FoodArchiveLedgerAccess)
            let old = saved.logItemVersion
            let competing = try LogItemVersion(logItemVersionID: LedgerFixtures.id(956, LogItemVersionTag.self), logItemID: old.logItemID,
                ordinal: VersionOrdinal(2), supersedesLogItemVersionID: old.logItemVersionID, occurredAt: old.occurredAt,
                reportingDate: old.reportingDate, composition: old.composition, edibleQuantity: PositiveQuantity(value: 151, unit: .grams),
                originalResolutionVersionID: old.originalResolutionVersionID, effectiveResolutionVersionID: old.effectiveResolutionVersionID,
                correctionReason: LedgerText("Competing"), createdAt: LedgerFixtures.date)
            let competingTwin = try LogItemVersion(logItemVersionID: LedgerFixtures.id(957, LogItemVersionTag.self), logItemID: old.logItemID,
                ordinal: VersionOrdinal(2), supersedesLogItemVersionID: old.logItemVersionID, occurredAt: old.occurredAt,
                reportingDate: old.reportingDate, composition: old.composition, edibleQuantity: PositiveQuantity(value: 152, unit: .grams),
                originalResolutionVersionID: old.originalResolutionVersionID, effectiveResolutionVersionID: old.effectiveResolutionVersionID,
                correctionReason: LedgerText("Competing"), createdAt: LedgerFixtures.date)
            let service = FoodLogReadingService(ledger: try LedgerFixtures.service(harness.committer), archive: archive,
                confirmationReader: harness.reader,
                history: CompetingHistory(base: ArchiveFoodLogHistoryReader(archive: archive), extra: [competing, competingTwin]),
                confirmations: confirmations, clock: LedgerFixtures.clock, ids: FoodLogContractIDs())
            let count = try archive.archiveState().records.logItemVersions.count
            XCTAssertEqual(service.remove(old.logItemID, expected: competing.logItemVersionID), .changedElsewhere, harness.name)
            XCTAssertEqual(try archive.archiveState().records.logItemVersions.count, count)
        }
    }

    // MARK: 5. Edit parity

    func testEditComparisonAgreesWithWhatTheSavePathRecords() throws {
        for harness in try LedgerFixtures.harnesses() {
            defer { harness.cleanup() }
            let (_, confirmations) = try services(harness)
            var converted = try state(grams: 1, evidence: 45)
            converted.quantity = FoodQuantityDraft(value: 1, unit: .count, conversion: QuantityConversionDraft(
                convertedQuantity: try PositiveQuantity(value: 120, unit: .grams), methodVersion: try LedgerText("fixture-conversion-v1"),
                sourceReleaseID: nil, evidenceID: nil))
            let edits: [(String, (inout FoodConfirmationState) throws -> Void, Bool)] = [
                ("untouched gram", { _ in }, false),
                ("amount", { FoodConfirmationReducer.reduce(state: &$0, action: .setQuantity(175, .grams)) }, true),
                ("time", { FoodConfirmationReducer.reduce(state: &$0, action: .setOccurredAt(LedgerFixtures.date.addingTimeInterval(-3600))) }, true),
                ("new plate", { $0.quantity.plateChoice = .new(emptyWeight: try PositiveQuantity(value: 20, unit: .grams), superseding: nil)
                                $0.quantity.value = 170 }, true)
            ]
            for (index, (name, edit, expected)) in edits.enumerated() {
                let saved = try confirmations.save(try state(grams: 150, evidence: 46 + index), operationID: LedgerFixtures.operationID(960 + index))
                try assertParity(name, harness, confirmations, saved, edit: edit, expected: expected, operation: 970 + index)
            }
            let savedConverted = try confirmations.save(converted, operationID: LedgerFixtures.operationID(965))
            try assertParity("untouched conversion", harness, confirmations, savedConverted, edit: { _ in }, expected: false, operation: 975)
            let reloaded = try XCTUnwrap(harness.reader.foodConfirmation(logItemID: savedConverted.logItem.logItemID))
            try assertParity("conversion amount", harness, confirmations, reloaded, edit: {
                FoodConfirmationReducer.reduce(state: &$0, action: .setQuantity(2, .count))
                $0.quantity.conversion = QuantityConversionDraft(convertedQuantity: try PositiveQuantity(value: 240, unit: .grams),
                    methodVersion: try LedgerText("fixture-conversion-v1"), sourceReleaseID: nil, evidenceID: nil)
            }, expected: true, operation: 976)
        }
    }

    /// Review fix 7: untouched plate and direct-weight entries are unchanged; a declaration change
    /// and a correction are changes, for the button and the save path alike.
    func testEditComparisonCoversPlateDirectWeightDeclarationAndCorrection() throws {
        for harness in try LedgerFixtures.harnesses() {
            defer { harness.cleanup() }
            let (_, confirmations) = try services(harness)
            var plated = try state(grams: 170, evidence: 60)
            plated.quantity.plateChoice = .new(emptyWeight: try PositiveQuantity(value: 20, unit: .grams), superseding: nil)
            func weighed(_ evidence: Int) throws -> FoodConfirmationState {
                var weighed = try state(grams: 2, evidence: evidence)
                weighed.quantity = FoodQuantityDraft(value: 2, unit: .count, directWeight: DirectWeightDraft(totalGrams: 125, basis: .measured))
                return weighed
            }
            let cases: [(String, FoodConfirmationState, (inout FoodConfirmationState) throws -> Void, Bool)] = [
                ("untouched saved plate", plated, { _ in }, false),
                ("untouched direct weight", try weighed(61), { _ in }, false),
                ("declaration basis", try weighed(67), { $0.quantity.directWeight?.basis = .estimated }, true),
                ("correction", try state(grams: 150, evidence: 62), { state in
                    FoodConfirmationReducer.reduce(state: &state, action: .applyCorrection(FoodCorrection(
                        name: try LedgerText("Corrected fixture food"), brand: nil, variant: nil,
                        identity: try LedgerFixtures.identity(), nutrients: state.selectedCandidate.candidate.nutrients,
                        reason: try LedgerText("Fixture correction"))))
                }, true)
            ]
            for (index, (name, initial, edit, expected)) in cases.enumerated() {
                let saved = try confirmations.save(initial, operationID: LedgerFixtures.operationID(1_000 + index))
                if name == "untouched saved plate" { XCTAssertNotNil(saved.logItemVersion.plateWeightVersionID) }
                if name == "untouched direct weight" { XCTAssertNotNil(saved.logItemVersion.weightDeclaration) }
                try assertParity(name, harness, confirmations, saved, edit: edit, expected: expected, operation: 1_010 + index)
            }
        }
    }

    /// Review fix 7: saved-entry detail for an estimate, a plate-weighed entry and a converted entry.
    func testSavedEntryDetailEstimatePlateAndConversion() throws {
        for harness in try LedgerFixtures.harnesses() {
            defer { harness.cleanup() }
            let (service, confirmations) = try services(harness)
            var estimated = try state(grams: 2, evidence: 63)
            estimated.quantity = FoodQuantityDraft(value: 2, unit: .count, directWeight: DirectWeightDraft(totalGrams: 125, basis: .estimated))
            let estimate = try confirmations.save(estimated, operationID: LedgerFixtures.operationID(1_020))
            let estimateDetail = try XCTUnwrap(service.savedEntry(estimate.logItem.logItemID))
            XCTAssertEqual(estimateDetail.enteredAmount, try PositiveQuantity(value: 2, unit: .count))
            XCTAssertEqual(estimateDetail.edibleQuantity, try PositiveQuantity(value: 125, unit: .grams))
            guard case let .calculated(totals) = estimateDetail.nutrition else { return XCTFail("calculated") }
            XCTAssertTrue(totals.first { $0.key == .protein }?.includesEstimates == true, "an estimated weight is labelled")
            XCTAssertTrue(estimateDetail.weightIsEstimated, "stated once in the header")
            XCTAssertTrue(estimateDetail.augmentedKeys.isEmpty, "no per-value marker for measured values")
            let row = try XCTUnwrap(service.day(reportingDate: estimateDetail.reportingDate).entries.first { $0.logItemID == estimate.logItem.logItemID })
            XCTAssertTrue(row.isEstimate, "\(harness.name): the row says Estimate for an estimated weight")

            var plated = try state(grams: 170, evidence: 64)
            plated.quantity.plateChoice = .new(emptyWeight: try PositiveQuantity(value: 20, unit: .grams), superseding: nil)
            let plate = try confirmations.save(plated, operationID: LedgerFixtures.operationID(1_021))
            let plateDetail = try XCTUnwrap(service.savedEntry(plate.logItem.logItemID))
            XCTAssertEqual(plateDetail.edibleQuantity, try PositiveQuantity(value: 150, unit: .grams), "edible weight, plate excluded")

            var converted = try state(grams: 1, evidence: 65)
            converted.quantity = FoodQuantityDraft(value: 1, unit: .count, conversion: QuantityConversionDraft(
                convertedQuantity: try PositiveQuantity(value: 120, unit: .grams), methodVersion: try LedgerText("fixture-conversion-v1"),
                sourceReleaseID: nil, evidenceID: nil))
            let conversion = try confirmations.save(converted, operationID: LedgerFixtures.operationID(1_022))
            let conversionDetail = try XCTUnwrap(service.savedEntry(conversion.logItem.logItemID))
            XCTAssertEqual(conversionDetail.enteredAmount, try PositiveQuantity(value: 1, unit: .count))
            XCTAssertEqual(conversionDetail.edibleQuantity, try PositiveQuantity(value: 120, unit: .grams))
            XCTAssertEqual(conversionDetail.sourceFamily, .yourFoods)
            XCTAssertTrue(conversionDetail.decisions.isEmpty)
        }
    }

    /// D7: with a mixed source (protein augmented, energy measured) only the augmented value is marked.
    func testOnlyAugmentedValuesAreMarkedOnTheSavedEntry() throws {
        for harness in try LedgerFixtures.harnesses() {
            defer { harness.cleanup() }
            let (service, confirmations) = try services(harness)
            let saved = try confirmations.save(try state(grams: 150, evidence: 68, augmented: [.protein]),
                                               operationID: LedgerFixtures.operationID(1_040))
            let detail = try XCTUnwrap(service.savedEntry(saved.logItem.logItemID))
            XCTAssertEqual(detail.augmentedKeys, [.protein], harness.name)
            XCTAssertFalse(detail.weightIsEstimated)
            guard case let .calculated(totals) = detail.nutrition else { return XCTFail("calculated") }
            let marked = totals.filter { $0.knownAmount != nil && detail.augmentedKeys.contains($0.key) }.map(\.key)
            XCTAssertEqual(marked, [.protein], "Estimated only beside protein, never beside energy")
        }
    }

    /// Review fix 4: a plate-only change is a weight-details event, never "saved again without changes".
    func testPlateOnlyEditIsAWeightDetailsEvent() throws {
        for harness in try LedgerFixtures.harnesses() {
            defer { harness.cleanup() }
            let (service, confirmations) = try services(harness)
            let saved = try confirmations.save(try state(grams: 150, evidence: 66), operationID: LedgerFixtures.operationID(1_030))
            var reopened = try XCTUnwrap(confirmations.reopen(logItemID: saved.logItem.logItemID))
            reopened.quantity.plateChoice = .new(emptyWeight: try PositiveQuantity(value: 20, unit: .grams), superseding: nil)
            reopened.quantity.value = 170
            XCTAssertTrue(FoodLogPolicy.editChanges(reopened))
            FoodConfirmationReducer.reduce(state: &reopened, action: .accept)
            _ = try confirmations.save(reopened, operationID: LedgerFixtures.operationID(1_031))
            XCTAssertEqual(try service.historyEvents(saved.logItem.logItemID).first?.kind, .weightDetailsChanged, harness.name)
        }
    }

    private func assertParity(_ name: String, _ harness: TestHarness, _ confirmations: FoodConfirmationService,
                              _ saved: StoredFoodConfirmation, edit: (inout FoodConfirmationState) throws -> Void,
                              expected: Bool, operation: Int) throws {
        var reopened = try XCTUnwrap(confirmations.reopen(logItemID: saved.logItem.logItemID), name)
        try edit(&reopened)
        XCTAssertEqual(FoodLogPolicy.editChanges(reopened), expected, "\(harness.name) \(name): button")
        FoodConfirmationReducer.reduce(state: &reopened, action: .accept)
        let next = try confirmations.save(reopened, operationID: LedgerFixtures.operationID(operation))
        let before = saved.logItemVersion, after = next.logItemVersion
        let recordedChange = before.occurredAt != after.occurredAt || before.edibleQuantity != after.edibleQuantity
            || before.weightDeclaration != after.weightDeclaration
            || before.quantityConversionVersionID != after.quantityConversionVersionID
            || before.plateWeightVersionID != after.plateWeightVersionID
            || before.composition != after.composition
        XCTAssertEqual(recordedChange, expected, "\(harness.name) \(name): save path")
    }

    // MARK: 6. Time edit moves the entry between days

    func testEditMovingTheTimeToThePreviousDayMovesTheEntry() throws {
        for harness in try LedgerFixtures.harnesses() {
            defer { harness.cleanup() }
            let (service, confirmations) = try services(harness)
            let saved = try confirmations.save(try state(grams: 150, evidence: 50), operationID: LedgerFixtures.operationID(980))
            var reopened = try XCTUnwrap(confirmations.reopen(logItemID: saved.logItem.logItemID))
            FoodConfirmationReducer.reduce(state: &reopened, action: .setOccurredAt(LedgerFixtures.date.addingTimeInterval(-86_400)))
            FoodConfirmationReducer.reduce(state: &reopened, action: .accept)
            let moved = try confirmations.save(reopened, operationID: LedgerFixtures.operationID(981))
            let originalDay = saved.logItemVersion.reportingDate.value, newDay = moved.logItemVersion.reportingDate.value
            XCTAssertNotEqual(originalDay, newDay)
            XCTAssertTrue(try service.day(reportingDate: originalDay).entries.isEmpty, harness.name)
            XCTAssertEqual(try service.day(reportingDate: newDay).entries.map(\.logItemID), [saved.logItem.logItemID])
            let history = try service.historyEvents(saved.logItem.logItemID)
            XCTAssertEqual(history.count, 2)
            XCTAssertEqual(history.first?.kind, .changed(amount: nil, time: .init(from: LedgerFixtures.date,
                                                                                  to: LedgerFixtures.date.addingTimeInterval(-86_400))))
        }
    }

    // MARK: 7. History parity and saved-entry detail

    func testHistoryAndDetailAreIdenticalFromBothStores() throws {
        var histories: [[FoodEntryHistoryEvent]] = []
        for harness in try LedgerFixtures.harnesses() {
            defer { harness.cleanup() }
            let (service, confirmations) = try services(harness)
            let saved = try confirmations.save(try state(grams: 120, evidence: 51), operationID: LedgerFixtures.operationID(985))
            var reopened = try XCTUnwrap(confirmations.reopen(logItemID: saved.logItem.logItemID))
            FoodConfirmationReducer.reduce(state: &reopened, action: .setQuantity(150, .grams))
            FoodConfirmationReducer.reduce(state: &reopened, action: .accept)
            _ = try confirmations.save(reopened, operationID: LedgerFixtures.operationID(986))
            let detail = try XCTUnwrap(service.savedEntry(saved.logItem.logItemID))
            XCTAssertEqual(detail.enteredAmount, try PositiveQuantity(value: 150, unit: .grams))
            XCTAssertFalse(detail.isEstimate)
            guard case let .calculated(totals) = detail.nutrition else { return XCTFail("calculated") }
            let row = try XCTUnwrap(service.day(reportingDate: detail.reportingDate).entries.first)
            XCTAssertEqual(totals.first { $0.key == .energyConsumed }?.knownAmount, row.energyKcal)
            XCTAssertEqual(totals.first { $0.key == .protein }?.knownAmount, 15)
            histories.append(detail.history)

            XCTAssertEqual(service.remove(saved.logItem.logItemID, expected: detail.logItemVersionID), .applied)
            XCTAssertNil(try service.savedEntry(saved.logItem.logItemID), "a removed entry is not opened")
        }
        XCTAssertEqual(histories.count, 2)
        XCTAssertEqual(histories[0].map(\.kind), histories[1].map(\.kind))
        XCTAssertEqual(histories[0].map(\.kind).last, .logged)
    }

    func testVolumeAgainstPerHundredGramsIsNotCalculableAndNeverZero() throws {
        for harness in try LedgerFixtures.harnesses() {
            defer { harness.cleanup() }
            let (service, confirmations) = try services(harness)
            var volume = try state(grams: 200, evidence: 52)
            volume.quantity = FoodQuantityDraft(value: 200, unit: .millilitres)
            let saved = try confirmations.save(volume, operationID: LedgerFixtures.operationID(990))
            let detail = try XCTUnwrap(service.savedEntry(saved.logItem.logItemID))
            XCTAssertEqual(detail.nutrition, .notCalculable(.unitMismatch(basis: .per100Grams, unit: .millilitres)), harness.name)
        }
        let quantity = try PositiveQuantity(value: 200, unit: .grams)
        XCTAssertEqual(SavedFoodEntryDetail.nutrition(quantity: quantity, basis: .unknown, nutrients: try nutrients(LedgerFixtures.id(1, EvidenceTag.self)),
                                                      quantityIsEstimate: false), .notCalculable(.unknownBasis))
    }

    // MARK: 8. Archive round trip after edit, remove and restore

    func testArchiveRoundTripAfterEditRemoveAndRestoreIsUnchanged() throws {
        for harness in try LedgerFixtures.harnesses() {
            defer { harness.cleanup() }
            let (service, confirmations) = try services(harness)
            let archive = try XCTUnwrap(harness.committer as? any FoodArchiveLedgerAccess)
            let saved = try confirmations.save(try state(grams: 150, evidence: 53), operationID: LedgerFixtures.operationID(995))
            var reopened = try XCTUnwrap(confirmations.reopen(logItemID: saved.logItem.logItemID))
            FoodConfirmationReducer.reduce(state: &reopened, action: .setQuantity(160, .grams))
            FoodConfirmationReducer.reduce(state: &reopened, action: .accept)
            let edited = try confirmations.save(reopened, operationID: LedgerFixtures.operationID(996))
            XCTAssertEqual(service.remove(saved.logItem.logItemID, expected: edited.logItemVersion.logItemVersionID), .applied)
            let removedHead = try head(archive, saved.logItem.logItemID).logItemVersionID
            XCTAssertEqual(service.restore(saved.logItem.logItemID, expected: removedHead), .applied)
            let state = try archive.archiveState()
            let bundle = try FoodArchiveGenerator().generate(state: state, ledgerID: LedgerText("food-log-phase-4"),
                createdAt: LedgerFixtures.date, creatingActorID: LedgerFixtures.id(900, ActorTag.self))
            let verified = try FoodArchiveVerifier().verify(bundle)
            for destination in try LedgerFixtures.harnesses() {
                defer { destination.cleanup() }
                let live = try XCTUnwrap(destination.committer as? any FoodArchiveLedgerAccess)
                let importer = FoodArchiveImportService(live: live, staging: InMemoryFoodArchiveStaging())
                _ = try importer.apply(importer.dryRun(bundle))
                let imported = try live.archiveState()
                XCTAssertEqual(try CanonicalFoodProjection(records: imported.records), try CanonicalFoodProjection(records: state.records),
                               "\(harness.name)->\(destination.name)")
                XCTAssertEqual(Set(imported.records.logItemVersions.map(\.logItemVersionID)),
                               Set(state.records.logItemVersions.map(\.logItemVersionID)))
                let reissued = try FoodArchiveGenerator().generate(state: imported, ledgerID: LedgerText("food-log-phase-4"),
                    createdAt: LedgerFixtures.date, creatingActorID: LedgerFixtures.id(900, ActorTag.self))
                XCTAssertEqual(try FoodArchiveVerifier().verify(reissued).document, verified.document)
            }
        }
    }

    // MARK: - Helpers

    private func services(_ harness: TestHarness) throws -> (FoodLogReadingService, FoodConfirmationService) {
        let ledger = try LedgerFixtures.service(harness.committer)
        let ids = FoodLogContractIDs()
        let archive = try XCTUnwrap(harness.committer as? any FoodArchiveLedgerAccess)
        let confirmations = FoodConfirmationService(ledger: ledger, reader: harness.reader, clock: LedgerFixtures.clock,
                                                    ids: ids, digester: SHA256Digester())
        let service = FoodLogReadingService(ledger: ledger, archive: archive, confirmationReader: harness.reader,
            history: ArchiveFoodLogHistoryReader(archive: archive), confirmations: confirmations,
            clock: LedgerFixtures.clock, ids: ids)
        return (service, confirmations)
    }

    private func nutrients(_ evidenceID: EvidenceID, augmented: Set<NutrientKey> = []) throws -> NutrientSet {
        let provenance = NutrientProvenance(sourceKind: .manualDeclaration, sourceID: try ExternalIdentifier("physical_package"),
            sourceReleaseID: try ExternalIdentifier("package:fixture-v1"), evidenceID: evidenceID, capturedAt: LedgerFixtures.date)
        // Augmented values need dataset provenance with a record (domain rule).
        let datasetProvenance = NutrientProvenance(sourceKind: .exactProductDataset, sourceID: try ExternalIdentifier("physical_package"),
            sourceReleaseID: try ExternalIdentifier("package:fixture-v1"), recordID: try ExternalIdentifier("fixture:augmented"))
        let known: [NutrientKey: Double] = [.energyConsumed: 200, .protein: 10]
        return try NutrientSet(entries: NutrientKey.allCases.map { key in
            guard let amount = known[key] else { return try NutrientEntry(key: key, value: .unknown(.notDeclared)) }
            let value = try ExactNutrientValue(amount: amount, unit: key.canonicalUnit,
                sourceValue: .exact(SourceExactNutrientValue(amount: amount, unit: LedgerText(key.canonicalUnit.rawValue), basis: .per100Grams)),
                provenance: [augmented.contains(key) ? datasetProvenance : provenance])
            return try NutrientEntry(key: key, value: augmented.contains(key) ? .augmented(value) : .measured(value))
        })
    }

    private func state(grams: Double, evidence number: Int, augmented: Set<NutrientKey> = []) throws -> FoodConfirmationState {
        let evidenceID: EvidenceID = try LedgerFixtures.id(number, EvidenceTag.self)
        let evidence = try CaptureEvidence(evidenceID: evidenceID, kind: .synthetic, capturedAt: LedgerFixtures.date,
            locale: LedgerText("en_GB"), captureMethod: LedgerText("synthetic_fixture"), captureMethodVersion: LedgerText("v1"),
            originalPayload: .text(LedgerText("food log fixture \(number)")))
        let quantity = try PositiveQuantity(value: 100, unit: .grams)
        let candidate = try PopulatedFoodCandidate(
            candidate: ProviderNeutralCandidate(sourceReleaseID: try ExternalIdentifier("package:fixture-v1"),
                recordID: try ExternalIdentifier("fixture:food-log-\(number)"), identity: try LedgerFixtures.identity(),
                edibleQuantity: .known(quantity, conversionVersionID: nil), nutrients: try nutrients(evidenceID, augmented: augmented),
                evidenceIDs: [evidenceID]),
            name: try LedgerText("Fixture food \(number)"), itemClass: .food)
        let input = try PopulatedFoodConfirmation(evidence: [evidence], sourceReleases: [try LedgerFixtures.packageSourceRelease()],
            candidates: [candidate], expectedIdentity: try LedgerFixtures.identity(),
            expectedEdibleQuantity: .known(quantity, conversionVersionID: nil))
        var state = FoodConfirmationState(input: input)
        state.decision = .accepted
        state.quantity = FoodQuantityDraft(value: grams, unit: .grams)
        return state
    }
}

private struct CompetingHistory: FoodLogHistoryReading {
    let base: ArchiveFoodLogHistoryReader
    let extra: [LogItemVersion]
    func versions(for logItemID: LogItemID) throws -> [LogItemVersion] {
        try base.versions(for: logItemID) + extra.filter { $0.logItemID == logItemID }
    }
    func change(operationID: OperationID) throws -> LedgerOperation? { try base.change(operationID: operationID) }
}

private final class FoodLogContractIDs: LedgerIDGenerating, @unchecked Sendable {
    private let lock = NSLock()
    private var value = 7_000
    func makeID<Tag>(_ tag: Tag.Type) throws -> LedgerID<Tag> {
        lock.lock(); defer { lock.unlock() }
        value += 1
        return try LedgerID(String(format: "00000000-0000-0000-0000-%012x", value))
    }
}
