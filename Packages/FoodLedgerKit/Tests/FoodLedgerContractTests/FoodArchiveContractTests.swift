import Foundation
import FoodLedgerApplication
import FoodLedgerArchive
import FoodLedgerDomain
import FoodLedgerGRDB
import FoodLedgerTestSupport
import XCTest

final class FoodArchiveContractTests: XCTestCase {
    func testGenerationIsByteDeterministicAndRoundTripPreservesCanonicalProjection() throws {
        let source = InMemoryFoodLedgerStore()
        _ = try LedgerFixtures.service(source).commit(
            LedgerFixtures.baseMutation(),
            type: .createProduct,
            operationID: LedgerFixtures.operationID(200)
        )
        let state = try source.archiveState()
        let summary = try canonicalSummary(input: [])
        let stateWithSummary = FoodArchiveState(
            records: state.records,
            operations: state.operations,
            summaries: [summary]
        )
        let generator = FoodArchiveGenerator()
        let first = try generator.generate(
            state: stateWithSummary,
            ledgerID: LedgerText("fixture-ledger"),
            createdAt: LedgerFixtures.date,
            creatingActorID: LedgerFixtures.id(900, ActorTag.self)
        )
        let second = try generator.generate(
            state: stateWithSummary,
            ledgerID: LedgerText("fixture-ledger"),
            createdAt: LedgerFixtures.date.addingTimeInterval(60),
            creatingActorID: LedgerFixtures.id(900, ActorTag.self)
        )

        XCTAssertEqual(first.snapshot, second.snapshot)
        XCTAssertEqual(first.operations, second.operations)
        let verifier = FoodArchiveVerifier()
        let firstVerified = try verifier.verify(first)
        let secondVerified = try verifier.verify(second)
        XCTAssertEqual(firstVerified.document.snapshotID, secondVerified.document.snapshotID)
        XCTAssertEqual(firstVerified.document.projection, secondVerified.document.projection)
        XCTAssertEqual(firstVerified.document.projection.records.resolutionVersions[0].nutrients.entries.count, 39)
        XCTAssertEqual(firstVerified.document.projection.summaries, [summary])
    }

    func testLocalFileExportReadsOnlyCompleteProtectedGeneration() throws {
        let bundle = try baseBundle(operationID: 201)
        let root = temporaryDirectory("archive-file")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let destination = root.appendingPathComponent("fixture.whrfoodbackup", isDirectory: true)
        let files = LocalFoodArchiveStore()
        try files.export(bundle, to: destination)
        XCTAssertEqual(try files.read(from: destination), bundle)

        let interrupted = root.appendingPathComponent("interrupted.whrfoodbackup", isDirectory: true)
        try FileManager.default.createDirectory(at: interrupted, withIntermediateDirectories: true)
        try bundle.snapshot.write(to: interrupted.appendingPathComponent("snapshot.json"))
        XCTAssertThrowsError(try files.read(from: interrupted)) { error in
            XCTAssertEqual(error as? FoodArchiveError, .interruptedGeneration)
        }
    }

    func testArchiveCarriesAttachmentDescriptorButNeverRawMediaBytes() throws {
        let rawMedia = Data("raw-camera-image-must-not-enter-archive".utf8)
        let descriptor = try AttachmentDescriptor(
            sha256: SHA256Digester().sha256(rawMedia),
            mediaKind: LedgerText("image/jpeg"),
            byteCount: rawMedia.count,
            relativePath: LedgerText("attachments/synthetic.jpg")
        )
        var mutation = try LedgerFixtures.baseMutation()
        mutation.evidence = [try CaptureEvidence(
            evidenceID: LedgerFixtures.id(1, EvidenceTag.self),
            kind: .packageImage,
            capturedAt: LedgerFixtures.date,
            locale: LedgerText("en_GB"),
            captureMethod: LedgerText("synthetic_fixture"),
            captureMethodVersion: LedgerText("v1"),
            originalPayload: .descriptor(LedgerText("package front")),
            byteHash: descriptor.sha256,
            attachment: descriptor
        )]
        let source = InMemoryFoodLedgerStore()
        let transaction = try LedgerFixtures.validTransaction(
            mutation: mutation,
            operationID: LedgerFixtures.operationID(208),
            actorID: LedgerFixtures.id(900, ActorTag.self),
            sequence: 1,
            previousHash: nil
        )
        _ = try source.commit(transaction)
        let bundle = try FoodArchiveGenerator().generate(
            state: source.archiveState(),
            ledgerID: LedgerText("privacy-fixture"),
            createdAt: LedgerFixtures.date,
            creatingActorID: LedgerFixtures.id(900, ActorTag.self)
        )

        XCTAssertTrue(bundle.snapshot.range(of: Data("synthetic.jpg".utf8)) != nil)
        XCTAssertNil(bundle.snapshot.range(of: rawMedia))
        XCTAssertNil(bundle.operations.range(of: rawMedia))
        XCTAssertTrue(try FoodArchiveVerifier().verify(bundle).manifest.rawAttachmentsOmitted)
    }

    func testRejectedArchivesLeaveLiveLedgerUntouched() throws {
        let valid = try baseBundle(operationID: 202)
        let live = InMemoryFoodLedgerStore()
        let importer = FoodArchiveImportService(live: live, staging: InMemoryFoodArchiveStaging())

        var tamperedSnapshot = valid.snapshot
        tamperedSnapshot[tamperedSnapshot.startIndex] ^= 0x01
        let gap = try gapBundle()
        let unsupportedSchema = try replacingManifestValue(
            valid,
            key: "dailySchemaVersion",
            value: 99
        )
        let unsupportedContract = try replacingManifestValue(
            valid,
            key: "foodContractVersion",
            value: 99
        )
        let wrongRecordCount = try replacingManifestValue(
            valid,
            key: "recordCount",
            value: 99
        )
        let duplicateMember = try duplicatingManifestMember(valid)
        let corrupt = FoodArchiveBundle(
            manifest: Data("not-json".utf8),
            snapshot: valid.snapshot,
            operations: valid.operations
        )
        let rejected = [
            FoodArchiveBundle(
                manifest: valid.manifest,
                snapshot: tamperedSnapshot,
                operations: valid.operations
            ),
            gap,
            unsupportedSchema,
            unsupportedContract,
            wrongRecordCount,
            duplicateMember,
            corrupt
        ]
        for candidate in rejected {
            XCTAssertThrowsError(try importer.dryRun(candidate))
            XCTAssertEqual(try live.counts().operations, 0)
            XCTAssertEqual(try live.archiveState().records, LedgerMutation())
        }
    }

    func testDryRunThenTransactionalApplyWorksForMemoryAndGRDB() throws {
        let bundle = try baseBundle(operationID: 203)
        let directory = temporaryDirectory("archive-live")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let stores: [any FoodArchiveLedgerAccess] = [
            InMemoryFoodLedgerStore(),
            try FoodLedgerGRDBStore.temporary(directory: directory)
        ]
        for store in stores {
            let importer = FoodArchiveImportService(
                live: store,
                staging: InMemoryFoodArchiveStaging()
            )
            let dryRun = try importer.dryRun(bundle)
            XCTAssertEqual(dryRun.report.newOperationCount, 1)
            XCTAssertEqual(dryRun.report.idempotentOperationCount, 0)
            XCTAssertEqual(try store.counts().operations, 0)
            _ = try importer.apply(dryRun)
            XCTAssertEqual(try store.counts().operations, 1)
            let retry = try importer.dryRun(bundle)
            XCTAssertEqual(retry.report.newOperationCount, 0)
            XCTAssertEqual(retry.report.idempotentOperationCount, 1)
            _ = try importer.apply(retry)
            XCTAssertEqual(try store.counts().operations, 1)
        }
    }

    func testBatchFailureRollsBackEveryAcceptedOperation() throws {
        let actor: ActorID = try LedgerFixtures.id(905, ActorTag.self)
        let first = try LedgerFixtures.validTransaction(
            mutation: LedgerFixtures.baseMutation(),
            operationID: LedgerFixtures.operationID(204),
            actorID: actor,
            sequence: 1,
            previousHash: nil
        )
        let missingProductVersion = try ProductVersion(
            productVersionID: LedgerFixtures.id(299, ProductVersionTag.self),
            productID: LedgerFixtures.id(998, ProductTag.self),
            ordinal: VersionOrdinal(1),
            name: LedgerText("Missing product"),
            itemClass: .food,
            packFacts: PackFacts(),
            identity: LedgerFixtures.identity(),
            evidenceIDs: [LedgerFixtures.id(1, EvidenceTag.self)],
            assertionIDs: [],
            createdAt: LedgerFixtures.date
        )
        let second = try LedgerFixtures.validTransaction(
            mutation: LedgerMutation(productVersions: [missingProductVersion]),
            operationID: LedgerFixtures.operationID(205),
            actorID: actor,
            sequence: 2,
            previousHash: first.operation.operationHash
        )
        let directory = temporaryDirectory("archive-rollback")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let stores: [any FoodArchiveLedgerAccess] = [
            InMemoryFoodLedgerStore(),
            try FoodLedgerGRDBStore.temporary(directory: directory)
        ]
        for store in stores {
            XCTAssertThrowsError(try store.commitAtomically([first, second]))
            XCTAssertEqual(try store.counts().operations, 0)
            XCTAssertEqual(try store.counts().productVersions, 0)
        }
    }

    func testMergeFixturePreservesConflictsReformulationResolutionDatasetPlateAndQuantityVersions() throws {
        let source = InMemoryFoodLedgerStore()
        let service = try LedgerFixtures.service(source)
        _ = try service.commit(
            LedgerFixtures.baseMutation(),
            type: .createProduct,
            operationID: LedgerFixtures.operationID(206)
        )
        let first = try productSuccessor(number: 220, name: "Reformulation A")
        let second = try productSuccessor(number: 221, name: "Reformulation B")
        let conflict = try LedgerConflict(
            conflictID: LedgerFixtures.id(222, ConflictTag.self),
            kind: .competingProductSuccessors,
            ancestorVersionID: VersionReference(try LedgerFixtures.id(3, ProductVersionTag.self).rawValue),
            competingVersionIDs: [
                VersionReference(first.productVersionID.rawValue),
                VersionReference(second.productVersionID.rawValue)
            ],
            createdAt: LedgerFixtures.date
        )
        let dataset = try datasetRelease()
        let resolution = try NutritionResolutionVersion(
            resolutionVersionID: LedgerFixtures.id(223, ResolutionVersionTag.self),
            resolutionID: LedgerFixtures.id(4, ResolutionTag.self),
            ordinal: VersionOrdinal(2),
            supersedesResolutionVersionID: LedgerFixtures.id(5, ResolutionVersionTag.self),
            methodVersion: LedgerText("dataset_re_resolution_v1"),
            sourceReleaseIDs: [try ExternalIdentifier("package:fixture-v1"), dataset.sourceReleaseID],
            nutrients: LedgerFixtures.nutrientSet(),
            createdAt: LedgerFixtures.date
        )
        let conversion1 = try conversion(number: 224, ordinal: 1, supersedes: nil, grams: 42)
        let conversion2 = try conversion(
            number: 225,
            ordinal: 2,
            supersedes: conversion1.quantityConversionVersionID,
            grams: 45
        )
        let plate = Plate(plateID: try LedgerFixtures.id(226, PlateTag.self), createdAt: LedgerFixtures.date)
        let plate1 = try plateVersion(number: 227, plate: plate, ordinal: 1, supersedes: nil, grams: 300)
        let plate2 = try plateVersion(
            number: 228,
            plate: plate,
            ordinal: 2,
            supersedes: plate1.plateWeightVersionID,
            grams: 305
        )
        let log = LogItem(logItemID: try LedgerFixtures.id(229, LogItemTag.self), createdAt: LedgerFixtures.date)
        let log1 = try logVersion(
            number: 230,
            log: log,
            ordinal: 1,
            supersedes: nil,
            product: first.productVersionID,
            resolution: resolution.resolutionVersionID,
            conversion: conversion1.quantityConversionVersionID,
            plate: plate1.plateWeightVersionID
        )
        let log2 = try logVersion(
            number: 231,
            log: log,
            ordinal: 2,
            supersedes: log1.logItemVersionID,
            product: first.productVersionID,
            resolution: resolution.resolutionVersionID,
            conversion: conversion2.quantityConversionVersionID,
            plate: plate2.plateWeightVersionID
        )
        _ = try service.commit(
            LedgerMutation(
                productVersions: [first, second],
                resolutionVersions: [resolution],
                logItems: [log],
                logItemVersions: [log1, log2],
                quantityConversions: [conversion1, conversion2],
                plates: [plate],
                plateWeightVersions: [plate1, plate2],
                conflicts: [conflict],
                sourceReleases: [dataset]
            ),
            type: .composite,
            operationID: LedgerFixtures.operationID(207)
        )
        let raw = try source.archiveState()
        let state = FoodArchiveState(
            records: raw.records,
            operations: raw.operations,
            summaries: [try canonicalSummary(input: [log2.logItemVersionID])]
        )
        let bundle = try FoodArchiveGenerator().generate(
            state: state,
            ledgerID: LedgerText("merge-fixture"),
            createdAt: LedgerFixtures.date,
            creatingActorID: LedgerFixtures.id(900, ActorTag.self)
        )
        let live = InMemoryFoodLedgerStore()
        let importer = FoodArchiveImportService(live: live, staging: InMemoryFoodArchiveStaging())
        let staged = try importer.dryRun(bundle)
        XCTAssertTrue(staged.report.requiresConflictResolution)
        XCTAssertEqual(staged.report.explicitConflictIDs, [conflict.conflictID])
        _ = try importer.apply(staged)
        let restored = try live.archiveState().records
        XCTAssertEqual(restored.productVersions.count, 3)
        XCTAssertEqual(restored.resolutionVersions.count, 2)
        XCTAssertEqual(restored.sourceReleases.count, 2)
        XCTAssertEqual(restored.quantityConversions.count, 2)
        XCTAssertEqual(restored.plateWeightVersions.count, 2)
        XCTAssertEqual(restored.logItemVersions.count, 2)
        XCTAssertEqual(restored.conflicts, [conflict])
    }

    private func baseBundle(operationID: Int) throws -> FoodArchiveBundle {
        let source = InMemoryFoodLedgerStore()
        _ = try LedgerFixtures.service(source).commit(
            LedgerFixtures.baseMutation(),
            type: .createProduct,
            operationID: LedgerFixtures.operationID(operationID)
        )
        return try FoodArchiveGenerator().generate(
            state: source.archiveState(),
            ledgerID: LedgerText("fixture-ledger"),
            createdAt: LedgerFixtures.date,
            creatingActorID: LedgerFixtures.id(900, ActorTag.self)
        )
    }

    private func gapBundle() throws -> FoodArchiveBundle {
        let transaction = try LedgerFixtures.validTransaction(
            mutation: LedgerFixtures.baseMutation(),
            operationID: LedgerFixtures.operationID(240),
            actorID: LedgerFixtures.id(940, ActorTag.self),
            sequence: 2,
            previousHash: nil
        )
        return try FoodArchiveGenerator().generate(
            state: FoodArchiveState(
                records: LedgerFixtures.baseMutation(),
                operations: [transaction.operation]
            ),
            ledgerID: LedgerText("gap-ledger"),
            createdAt: LedgerFixtures.date,
            creatingActorID: transaction.operation.actorID
        )
    }

    private func replacingManifestValue(
        _ bundle: FoodArchiveBundle,
        key: String,
        value: Int
    ) throws -> FoodArchiveBundle {
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: bundle.manifest) as? [String: Any]
        )
        object[key] = value
        let manifest = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return FoodArchiveBundle(
            manifest: manifest,
            snapshot: bundle.snapshot,
            operations: bundle.operations
        )
    }

    private func duplicatingManifestMember(
        _ bundle: FoodArchiveBundle
    ) throws -> FoodArchiveBundle {
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: bundle.manifest) as? [String: Any]
        )
        var members = try XCTUnwrap(object["members"] as? [[String: Any]])
        members.append(try XCTUnwrap(members.first))
        object["members"] = members
        return FoodArchiveBundle(
            manifest: try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
            snapshot: bundle.snapshot,
            operations: bundle.operations
        )
    }

    private func canonicalSummary(
        input: [LogItemVersionID]
    ) throws -> CanonicalFoodNutritionSummary {
        CanonicalFoodNutritionSummary(
            summaryVersionID: try LedgerText("summary-v1"),
            reportingDate: try LedgerText("2026-09-20"),
            nutrients: try LedgerFixtures.nutrientSet(),
            inputLogItemVersionIDs: input,
            hasUnknownContribution: true
        )
    }

    private func productSuccessor(number: Int, name: String) throws -> ProductVersion {
        try ProductVersion(
            productVersionID: LedgerFixtures.id(number, ProductVersionTag.self),
            productID: LedgerFixtures.id(2, ProductTag.self),
            ordinal: VersionOrdinal(2),
            supersedesProductVersionID: LedgerFixtures.id(3, ProductVersionTag.self),
            name: LedgerText(name),
            itemClass: .food,
            packFacts: PackFacts(),
            identity: LedgerFixtures.identity(),
            evidenceIDs: [LedgerFixtures.id(1, EvidenceTag.self)],
            assertionIDs: [],
            createdAt: LedgerFixtures.date
        )
    }

    private func datasetRelease() throws -> SourceRelease {
        SourceRelease(
            sourceReleaseID: try ExternalIdentifier("cofid:2026"),
            sourceID: try ExternalIdentifier("cofid"),
            releasedAt: LedgerFixtures.date,
            artifactHash: try SHA256Digest(String(repeating: "e", count: 64)),
            schemaVersion: try LedgerText("v1"),
            pipelineVersion: try LedgerText("v1"),
            licence: try LedgerText("Open Government Licence v3.0"),
            attribution: try LedgerText("synthetic fixture"),
            manifestHash: try SHA256Digest(String(repeating: "f", count: 64))
        )
    }

    private func conversion(
        number: Int,
        ordinal: Int,
        supersedes: QuantityConversionVersionID?,
        grams: Double
    ) throws -> QuantityConversionVersion {
        try QuantityConversionVersion(
            quantityConversionVersionID: LedgerFixtures.id(number, QuantityConversionVersionTag.self),
            ordinal: VersionOrdinal(ordinal),
            supersedesQuantityConversionVersionID: supersedes,
            sourceQuantity: PositiveQuantity(value: 1, unit: .count),
            convertedQuantity: PositiveQuantity(value: grams, unit: .grams),
            methodVersion: LedgerText("label_unit_v1"),
            evidenceID: LedgerFixtures.id(1, EvidenceTag.self),
            createdAt: LedgerFixtures.date
        )
    }

    private func plateVersion(
        number: Int,
        plate: Plate,
        ordinal: Int,
        supersedes: PlateWeightVersionID?,
        grams: Double
    ) throws -> PlateWeightVersion {
        try PlateWeightVersion(
            plateWeightVersionID: LedgerFixtures.id(number, PlateWeightVersionTag.self),
            plateID: plate.plateID,
            ordinal: VersionOrdinal(ordinal),
            supersedesPlateWeightVersionID: supersedes,
            emptyWeight: PositiveQuantity(value: grams, unit: .grams),
            createdAt: LedgerFixtures.date
        )
    }

    private func logVersion(
        number: Int,
        log: LogItem,
        ordinal: Int,
        supersedes: LogItemVersionID?,
        product: ProductVersionID,
        resolution: ResolutionVersionID,
        conversion: QuantityConversionVersionID,
        plate: PlateWeightVersionID
    ) throws -> LogItemVersion {
        try LogItemVersion(
            logItemVersionID: LedgerFixtures.id(number, LogItemVersionTag.self),
            logItemID: log.logItemID,
            ordinal: VersionOrdinal(ordinal),
            supersedesLogItemVersionID: supersedes,
            occurredAt: LedgerFixtures.date,
            reportingDate: LedgerText("2026-09-20"),
            composition: .product(product),
            edibleQuantity: PositiveQuantity(value: 1, unit: .count),
            quantityConversionVersionID: conversion,
            plateWeightVersionID: plate,
            originalResolutionVersionID: resolution,
            effectiveResolutionVersionID: resolution,
            correctionReason: supersedes == nil ? nil : LedgerText("corrected quantity"),
            createdAt: LedgerFixtures.date
        )
    }

    private func temporaryDirectory(_ name: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("\(name)-\(UUID().uuidString)", isDirectory: true)
    }
}
