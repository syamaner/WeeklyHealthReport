import FoodLedgerApplication
import FoodLedgerArchive
import FoodLedgerDomain
import FoodLedgerGRDB
import FoodLedgerTestSupport
import Foundation
import GRDB
import XCTest

final class DirectWeightContractTests: XCTestCase {
    func testFrozenHistoricalArchivesRestoreWithOriginalBytesHashesAndUnspecifiedWeight() throws {
        for version in [1, 2] {
            let directory = try XCTUnwrap(Bundle.module.resourceURL).appendingPathComponent(
                "Fixtures/legacy-v\(version)")
            let bundle = try LocalFoodArchiveStore().read(from: directory)
            let verified = try FoodArchiveVerifier().verify(bundle)
            XCTAssertEqual(verified.manifest.foodContractVersion, version)
            XCTAssertEqual(verified.document.projection.foodContractVersion, version)
            XCTAssertEqual(try LedgerFixtures.encoder.encode(verified.document), bundle.snapshot)
            XCTAssertEqual(
                try LedgerFixtures.digester.sha256(bundle.operations).value,
                "530ba82d7106eb9e351e90e45345f10f6bb36d700df1c83456b4785043d9e8e6")
            for harness in try LedgerFixtures.harnesses() {
                defer { harness.cleanup() }

                let archive = try XCTUnwrap(harness.committer as? any FoodArchiveLedgerAccess)
                let importer = FoodArchiveImportService(
                    live: archive, staging: InMemoryFoodArchiveStaging())
                _ = try importer.apply(importer.dryRun(bundle))
                let restored = try archive.archiveState()
                XCTAssertEqual(
                    try CanonicalFoodProjection(
                        records: restored.records, foodContractVersion: version),
                    verified.document.projection)
                XCTAssertEqual(
                    restored.operations.sorted { $0.actorSequence < $1.actorSequence },
                    verified.transactions.map(\.operation).sorted {
                        $0.actorSequence < $1.actorSequence
                    })
                XCTAssertTrue(
                    restored.records.logItemVersions.allSatisfy { $0.weightDeclaration == nil })
                XCTAssertEqual(
                    restored.records.logItemVersions.map { $0.edibleQuantity.value }.sorted(),
                    [1, 150])
                XCTAssertEqual(
                    restored.records.quantityConversions.first?.convertedQuantity.value, 42)
                XCTAssertEqual(
                    restored.records.productVersions,
                    verified.document.projection.records.productVersions)
                XCTAssertEqual(
                    restored.records.resolutionVersions,
                    verified.document.projection.records.resolutionVersions)
            }
        }
    }

    func testMeasuredEstimatedAndLegacySaveReopenAndNewArchiveRoundTripAcrossAdapters() throws {
        for (index, basis) in [UserWeightBasis?.none, .some(.measured), .some(.estimated)]
            .enumerated()
        {
            for harness in try LedgerFixtures.harnesses() {
                defer { harness.cleanup() }
                let ledger = try LedgerFixtures.service(harness.committer)
                let service = FoodConfirmationService(
                    ledger: ledger, reader: harness.reader,
                    clock: LedgerFixtures.clock, ids: RandomLedgerIDGenerator(), digester: SHA256Digester())
                let input = try fixtureInput()
                var state = FoodConfirmationState(input: input)
                state.decision = .accepted
                if let basis {
                    state.quantity = FoodQuantityDraft(
                        value: 2, unit: .count,
                        directWeight: DirectWeightDraft(totalGrams: 125, basis: basis))
                } else {
                    state.quantity = FoodQuantityDraft(value: 125, unit: .grams)
                }
                let operationID = try LedgerFixtures.operationID(700 + index)
                let saved = try service.save(
                    state, operationID: operationID,
                    idempotencyKey: LedgerText("direct-test-\(index)"))
                XCTAssertEqual(
                    saved.logItemVersion.edibleQuantity,
                    try state.quantity.calculatedEdibleQuantity(), harness.name)
                XCTAssertEqual(saved.logItemVersion.weightDeclaration?.basis, basis)
                XCTAssertEqual(
                    saved.resolutionVersion.nutrients, input.candidates[0].candidate.nutrients)
                XCTAssertEqual(
                    saved.productVersion.identity, input.candidates[0].candidate.identity)
                XCTAssertEqual(
                    try harness.committer.operation(id: operationID)?.operationType,
                    basis == nil ? .confirmFood : .confirmFoodV2)
                // Retrying a new versioned confirmation still recovers the committed record.
                XCTAssertEqual(
                    try service.save(
                        state, operationID: operationID,
                        idempotencyKey: LedgerText("direct-test-\(index)")), saved)
                let reopened = try XCTUnwrap(service.reopen(logItemID: saved.logItem.logItemID))
                XCTAssertEqual(reopened.quantity.directWeight?.basis, basis)
                XCTAssertEqual(
                    try reopened.quantity.calculatedEdibleQuantity(),
                    saved.logItemVersion.edibleQuantity)
                if basis != nil {
                    XCTAssertEqual(reopened.quantity.value, 2)
                    XCTAssertEqual(reopened.quantity.directWeight?.totalGrams, 125)
                }
                let archive = try XCTUnwrap(harness.committer as? any FoodArchiveLedgerAccess)
                let bundle = try FoodArchiveGenerator().generate(
                    state: archive.archiveState(), ledgerID: LedgerText("direct-v3"),
                    createdAt: LedgerFixtures.date,
                    creatingActorID: LedgerFixtures.id(900, ActorTag.self))
                let verified = try FoodArchiveVerifier().verify(bundle)
                XCTAssertEqual(verified.manifest.foodContractVersion, 3)
                for destination in try LedgerFixtures.harnesses() {
                    defer { destination.cleanup() }
                    let live = try XCTUnwrap(destination.committer as? any FoodArchiveLedgerAccess)
                    let importer = FoodArchiveImportService(
                        live: live, staging: InMemoryFoodArchiveStaging())
                    _ = try importer.apply(importer.dryRun(bundle))
                    XCTAssertEqual(
                        try CanonicalFoodProjection(records: live.archiveState().records),
                        try CanonicalFoodProjection(records: archive.archiveState().records))
                    XCTAssertEqual(
                        try live.archiveState().operations, try archive.archiveState().operations)
                }
                if basis != nil {
                    XCTAssertThrowsError(
                        try CanonicalFoodProjection(
                            records: archive.archiveState().records, foodContractVersion: 2))
                }
                XCTAssertThrowsError(
                    try LedgerOperationRegistry.builtInV2.requireSupported(.confirmFoodV2))
                XCTAssertThrowsError(
                    try LedgerOperationRegistry.builtInV3.requireSupported(
                        LedgerOperationType(rawValue: "confirm_food_v99")!))
            }
        }
    }

    func testOldOperationContractsRejectDeclarationsAndRemovalRestorationRetainThem() throws {
        for harness in try LedgerFixtures.harnesses() {
            defer { harness.cleanup() }
            let ledger = try LedgerFixtures.service(harness.committer)
            let confirmations = FoodConfirmationService(
                ledger: ledger, reader: harness.reader,
                clock: LedgerFixtures.clock, ids: RandomLedgerIDGenerator(), digester: SHA256Digester())
            var state = FoodConfirmationState(input: try fixtureInput())
            state.decision = .accepted
            state.quantity.directWeight = DirectWeightDraft(totalGrams: 125, basis: .measured)
            let saved = try confirmations.save(state, operationID: LedgerFixtures.operationID(710))
            let old = saved.logItemVersion
            let correction = try LogItemVersion(
                logItemVersionID: LedgerFixtures.id(711, LogItemVersionTag.self),
                logItemID: old.logItemID, ordinal: VersionOrdinal(2),
                supersedesLogItemVersionID: old.logItemVersionID,
                occurredAt: old.occurredAt, reportingDate: old.reportingDate,
                composition: old.composition,
                edibleQuantity: old.edibleQuantity,
                weightDeclaration: old.weightDeclaration,
                originalResolutionVersionID: old.originalResolutionVersionID,
                effectiveResolutionVersionID: old.effectiveResolutionVersionID,
                correctionReason: LedgerText("Synthetic invalid quantity"), createdAt: old.createdAt
            )
            let mutation = LedgerMutation(logItemVersions: [correction])
            for type in [
                LedgerOperationType.confirmFood, .recordLogItem, .correctLogItem, .composite,
                .correctResolution,
            ] {
                XCTAssertThrowsError(
                    try ledger.commit(
                        mutation, type: type, operationID: LedgerFixtures.operationID(711)))
            }
            XCTAssertEqual(try harness.reader.foodConfirmation(logItemID: old.logItemID), saved)
            let management = FoodLogManagementService(
                ledger: ledger,
                reader: ArchiveFoodLogHistoryReader(
                    archive: try XCTUnwrap(harness.committer as? any FoodArchiveLedgerAccess)),
                clock: LedgerFixtures.clock, ids: RandomLedgerIDGenerator())
            let removed = try management.remove(
                logItemID: old.logItemID, expectedVersion: old.logItemVersionID,
                reason: LedgerText("Synthetic removal"),
                operationID: LedgerFixtures.operationID(712))
            let restored = try management.restore(
                logItemID: old.logItemID, expectedVersion: removed.logItemVersionID,
                reason: LedgerText("Synthetic restoration"),
                operationID: LedgerFixtures.operationID(713))
            XCTAssertEqual(restored.weightDeclaration, old.weightDeclaration)
        }
    }

    func testNewPlateDeclarationFirstSaveReopenAndInconsistentPlatePayloadAcrossAdapters() throws {
        for harness in try LedgerFixtures.harnesses() {
            defer { harness.cleanup() }
            let ledger = try LedgerFixtures.service(harness.committer)
            let service = FoodConfirmationService(
                ledger: ledger, reader: harness.reader,
                clock: LedgerFixtures.clock, ids: RandomLedgerIDGenerator(), digester: SHA256Digester())
            var state = FoodConfirmationState(input: try fixtureInput())
            state.decision = .accepted
            state.quantity = FoodQuantityDraft(
                value: 2, unit: .count,
                plateChoice: .new(
                    emptyWeight: try PositiveQuantity(value: 50, unit: .grams), superseding: nil),
                directWeight: DirectWeightDraft(totalGrams: 250, basis: .estimated))
            let saved = try service.save(state, operationID: LedgerFixtures.operationID(720))
            XCTAssertEqual(saved.logItemVersion.edibleQuantity.value, 200)
            let reopened = try XCTUnwrap(service.reopen(logItemID: saved.logItem.logItemID))
            XCTAssertEqual(reopened.quantity.directWeight?.totalGrams, 250)
            XCTAssertEqual(try reopened.quantity.calculatedEdibleQuantity().value, 200)
            let old = saved.logItemVersion
            let invalid = try LogItemVersion(
                logItemVersionID: LedgerFixtures.id(721, LogItemVersionTag.self),
                logItemID: old.logItemID, ordinal: VersionOrdinal(2),
                supersedesLogItemVersionID: old.logItemVersionID,
                occurredAt: old.occurredAt, reportingDate: old.reportingDate,
                composition: old.composition,
                edibleQuantity: PositiveQuantity(value: 250, unit: .grams),
                weightDeclaration: old.weightDeclaration,
                plateWeightVersionID: old.plateWeightVersionID,
                originalResolutionVersionID: old.originalResolutionVersionID,
                effectiveResolutionVersionID: old.effectiveResolutionVersionID,
                correctionReason: LedgerText("Inconsistent plate total"), createdAt: old.createdAt)
            XCTAssertThrowsError(
                try ledger.commit(
                    LedgerMutation(logItemVersions: [invalid]),
                    type: .correctLogItemV2, operationID: LedgerFixtures.operationID(721)))
            let archive = try XCTUnwrap(harness.committer as? any FoodArchiveLedgerAccess)
            let projection = try FoodIntakeProjection(
                records: archive.archiveState().records,
                reportingDate: old.reportingDate.value)
            XCTAssertTrue(
                projection.summary.totals.first { $0.key == .protein }?.includesEstimates == true)
        }
    }

    func testDeclarationVersionAndArchiveContractMismatchRejectBeforeImport() throws {
        let declaration = try EdibleWeightDeclaration(
            basis: .measured,
            total: PositiveQuantity(value: 150, unit: .grams), originalInput: nil)
        let bytes = try LedgerFixtures.encoder.encode(declaration)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        json["version"] = 99
        XCTAssertThrowsError(
            try JSONDecoder().decode(
                EdibleWeightDeclaration.self, from: JSONSerialization.data(withJSONObject: json)))
        let harnesses = try LedgerFixtures.harnesses()
        defer { harnesses.forEach { $0.cleanup() } }
        let harness = try XCTUnwrap(harnesses.first)
        let service = FoodConfirmationService(
            ledger: try LedgerFixtures.service(harness.committer), reader: harness.reader,
            clock: LedgerFixtures.clock, ids: RandomLedgerIDGenerator(), digester: SHA256Digester())
        var state = FoodConfirmationState(input: try fixtureInput())
        state.decision = .accepted
        state.quantity.directWeight = DirectWeightDraft(totalGrams: 150, basis: .measured)
        _ = try service.save(state, operationID: LedgerFixtures.operationID(730))
        let archive = try XCTUnwrap(harness.committer as? any FoodArchiveLedgerAccess)
        let valid = try FoodArchiveGenerator().generate(
            state: archive.archiveState(), ledgerID: LedgerText("mismatch"),
            createdAt: LedgerFixtures.date, creatingActorID: LedgerFixtures.id(900, ActorTag.self))
        let verified = try FoodArchiveVerifier().verify(valid)
        var snapshotObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: valid.snapshot) as? [String: Any])
        var projection = try XCTUnwrap(snapshotObject["projection"] as? [String: Any])
        projection["foodContractVersion"] = 2
        snapshotObject["projection"] = projection
        let snapshot = try JSONSerialization.data(
            withJSONObject: snapshotObject, options: [.sortedKeys])
        let manifest = try FoodArchiveManifest(
            ledgerID: verified.manifest.ledgerID, snapshotID: verified.manifest.snapshotID,
            createdAt: verified.manifest.createdAt,
            creatingActorID: verified.manifest.creatingActorID,
            sourceReleaseIDs: verified.manifest.sourceReleaseIDs,
            watermarks: verified.manifest.watermarks,
            recordCount: verified.manifest.recordCount,
            operationCount: verified.manifest.operationCount,
            members: [
                FoodArchiveMember(
                    filename: LedgerText("snapshot.json"), bytes: snapshot,
                    digester: LedgerFixtures.digester),
                FoodArchiveMember(
                    filename: LedgerText("operations.ndjson"), bytes: valid.operations,
                    digester: LedgerFixtures.digester),
            ],
            foodContractVersion: 2)
        XCTAssertThrowsError(
            try FoodArchiveVerifier().verify(
                FoodArchiveBundle(
                    manifest: LedgerFixtures.encoder.encode(manifest), snapshot: snapshot,
                    operations: valid.operations))
        ) {
            XCTAssertEqual($0 as? FoodArchiveError, .unsupportedFoodContract(2))
        }
    }

    func testMalformedNoPlateDeclarationsAndConflictingConversionsRejectOnDecode() throws {
        let store = InMemoryFoodLedgerStore()
        let service = FoodConfirmationService(
            ledger: try LedgerFixtures.service(store), reader: store,
            clock: LedgerFixtures.clock, ids: RandomLedgerIDGenerator(), digester: SHA256Digester())
        var state = FoodConfirmationState(input: try fixtureInput())
        state.decision = .accepted
        state.quantity.directWeight = DirectWeightDraft(totalGrams: 150, basis: .measured)
        let saved = try service.save(state, operationID: LedgerFixtures.operationID(740))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        let original = try XCTUnwrap(
            JSONSerialization.jsonObject(with: LedgerFixtures.encoder.encode(saved.logItemVersion))
                as? [String: Any])
        var wrongTotal = original
        var declaration = try XCTUnwrap(wrongTotal["weightDeclaration"] as? [String: Any])
        var total = try XCTUnwrap(declaration["total"] as? [String: Any])
        total["value"] = 999
        declaration["total"] = total
        wrongTotal["weightDeclaration"] = declaration
        XCTAssertThrowsError(
            try decoder.decode(
                LogItemVersion.self, from: JSONSerialization.data(withJSONObject: wrongTotal)))
        var conflicting = original
        conflicting["quantityConversionVersionID"] = try LedgerFixtures.id(
            741, QuantityConversionVersionTag.self
        ).rawValue
        XCTAssertThrowsError(
            try decoder.decode(
                LogItemVersion.self, from: JSONSerialization.data(withJSONObject: conflicting)))
    }

    func testStoredPlateMismatchRejectsReadServiceReopenAndDatabaseOpen() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try FoodLedgerGRDBStore.temporary(directory: directory)
        let service = FoodConfirmationService(
            ledger: try LedgerFixtures.service(store), reader: store,
            clock: LedgerFixtures.clock, ids: RandomLedgerIDGenerator(), digester: SHA256Digester())
        var state = FoodConfirmationState(input: try fixtureInput())
        state.decision = .accepted
        state.quantity = FoodQuantityDraft(
            value: 2, unit: .count,
            plateChoice: .new(
                emptyWeight: try PositiveQuantity(value: 50, unit: .grams), superseding: nil),
            directWeight: DirectWeightDraft(totalGrams: 250, basis: .measured))
        let saved = try service.save(state, operationID: LedgerFixtures.operationID(750))
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: LedgerFixtures.encoder.encode(saved.logItemVersion))
                as? [String: Any])
        var declaration = try XCTUnwrap(object["weightDeclaration"] as? [String: Any])
        var total = try XCTUnwrap(declaration["total"] as? [String: Any])
        total["value"] = 999
        declaration["total"] = total
        object["weightDeclaration"] = declaration
        let badBytes = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        let queue = try DatabaseQueue(
            path: directory.appendingPathComponent("food-ledger-v1.sqlite").path)
        try queue.write { db in
            try db.execute(sql: "DROP TRIGGER log_item_version_immutable_update")
            try db.execute(
                sql: "UPDATE log_item_version SET payload = ? WHERE version_id = ?",
                arguments: [badBytes, saved.logItemVersion.logItemVersionID.rawValue])
        }
        XCTAssertThrowsError(try store.archiveState())
        XCTAssertThrowsError(try store.verifyIntegrity())
        XCTAssertThrowsError(try store.foodConfirmation(logItemID: saved.logItem.logItemID))
        XCTAssertThrowsError(try service.reopen(logItemID: saved.logItem.logItemID))
        XCTAssertThrowsError(try FoodLedgerGRDBStore.temporary(directory: directory))
        // A different port can return a typed record whose plate-dependent values
        // need application-level validation as well as adapter validation.
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        let badLog = try decoder.decode(LogItemVersion.self, from: badBytes)
        let alternate = StoredFoodConfirmation(
            evidence: saved.evidence, sourceReleases: saved.sourceReleases,
            product: saved.product, productVersion: saved.productVersion,
            resolution: saved.resolution,
            resolutionVersion: saved.resolutionVersion, logItem: saved.logItem,
            logItemVersion: badLog,
            quantityConversion: saved.quantityConversion, plate: saved.plate,
            plateWeightVersion: saved.plateWeightVersion,
            candidateDecision: saved.candidateDecision, assertions: saved.assertions)
        let alternateService = FoodConfirmationService(
            ledger: try LedgerFixtures.service(InMemoryFoodLedgerStore()),
            reader: FixedConfirmationReader(record: alternate), clock: LedgerFixtures.clock,
            ids: RandomLedgerIDGenerator(), digester: SHA256Digester())
        XCTAssertThrowsError(try alternateService.reopen(logItemID: badLog.logItemID))
    }

    private func fixtureInput() throws -> PopulatedFoodConfirmation {
        let base = try LedgerFixtures.baseMutation()
        let candidate = try ProviderNeutralCandidate(
            sourceReleaseID: base.sourceReleases[0].sourceReleaseID,
            recordID: ExternalIdentifier("sample"), identity: LedgerFixtures.identity(),
            edibleQuantity: .known(
                PositiveQuantity(value: 100, unit: .grams), conversionVersionID: nil),
            nutrients: LedgerFixtures.nutrientSet(), evidenceIDs: base.evidence.map(\.evidenceID))
        return try PopulatedFoodConfirmation(
            evidence: base.evidence, sourceReleases: base.sourceReleases,
            candidates: [
                PopulatedFoodCandidate(
                    candidate: candidate, name: LedgerText("Sample food"), itemClass: .food)
            ],
            expectedIdentity: candidate.identity, expectedEdibleQuantity: candidate.edibleQuantity)
    }
}

private struct FixedConfirmationReader: FoodConfirmationReading {
    let record: StoredFoodConfirmation
    func sourceRelease(id: ExternalIdentifier) throws -> SourceRelease? {
        record.sourceReleases.first { $0.sourceReleaseID == id }
    }
    func foodConfirmation(logItemID: LogItemID) throws -> StoredFoodConfirmation? { record }
}
