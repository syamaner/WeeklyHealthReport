import Foundation
import FoodLedgerApplication
import FoodLedgerDomain
import XCTest

final class SharedStoreContractTests: XCTestCase {
    func testAtomicCommitAndStatePreservingReadback() throws {
        try forEachStore { harness, service in
            let outcome = try service.commit(
                LedgerFixtures.baseMutation(),
                type: .createProduct,
                operationID: LedgerFixtures.operationID(100)
            )
            guard case .committed = outcome else { return XCTFail(harness.name) }
            let counts = try harness.reader.counts()
            XCTAssertEqual(counts.evidence, 1, harness.name)
            XCTAssertEqual(counts.productVersions, 1, harness.name)
            XCTAssertEqual(counts.resolutionVersions, 1, harness.name)
            XCTAssertEqual(counts.operations, 1, harness.name)
            let resolution = try XCTUnwrap(
                harness.reader.resolutionVersion(id: LedgerFixtures.id(5, ResolutionVersionTag.self)),
                harness.name
            )
            XCTAssertEqual(resolution.nutrients.entries.count, 39, harness.name)
            guard case .bounded = resolution.nutrients.entries[8].value else {
                return XCTFail("bounded sugar was coerced: \(harness.name)")
            }
            guard case .unknown(.noCompatibleSource) = resolution.nutrients.entries[33].value else {
                return XCTFail("unknown iodine was coerced: \(harness.name)")
            }
        }
    }

    func testIdempotencyAndDivergentDuplicateBlock() throws {
        try forEachStore { harness, service in
            let operationID = try LedgerFixtures.operationID(101)
            let mutation = try LedgerFixtures.baseMutation()
            _ = try service.commit(mutation, type: .createProduct, operationID: operationID)
            let retry = try service.commit(mutation, type: .createProduct, operationID: operationID)
            guard case .idempotent = retry else { return XCTFail(harness.name) }
            XCTAssertEqual(try harness.reader.counts().operations, 1, harness.name)

            let otherEvidence = try CaptureEvidence(
                evidenceID: LedgerFixtures.id(91, EvidenceTag.self),
                kind: .synthetic,
                capturedAt: LedgerFixtures.date,
                locale: LedgerText("en_GB"),
                captureMethod: LedgerText("different"),
                captureMethodVersion: LedgerText("v1"),
                originalPayload: .text(LedgerText("different"))
            )
            XCTAssertThrowsError(try service.commit(
                LedgerMutation(evidence: [otherEvidence]),
                type: .recordEvidence,
                operationID: operationID
            )) { error in
                XCTAssertEqual(error as? FoodLedgerStoreError, .divergentDuplicateOperation, harness.name)
            }
        }
    }

    func testOperationIDCannotBeClaimedByAnotherActor() throws {
        try forEachStore { harness, service in
            let operationID = try LedgerFixtures.operationID(119)
            let mutation = try LedgerFixtures.baseMutation()
            _ = try service.commit(mutation, type: .createProduct, operationID: operationID)
            let otherActor = FoodLedgerService(
                actorID: try LedgerFixtures.id(901, ActorTag.self),
                committer: harness.committer,
                clock: LedgerFixtures.clock,
                encoder: LedgerFixtures.encoder,
                digester: LedgerFixtures.digester
            )
            XCTAssertThrowsError(try otherActor.commit(
                mutation,
                type: .createProduct,
                operationID: operationID
            )) { error in
                XCTAssertEqual(error as? FoodLedgerStoreError, .divergentDuplicateOperation)
            }
        }
    }

    func testAffectedIdentifiersMustMatchTheMutation() throws {
        try forEachStore { harness, _ in
            let actor: ActorID = try LedgerFixtures.id(900, ActorTag.self)
            let mutation = try LedgerFixtures.baseMutation()
            let valid = try LedgerFixtures.validTransaction(
                mutation: mutation,
                operationID: LedgerFixtures.operationID(120),
                actorID: actor,
                sequence: 1,
                previousHash: nil
            )
            let alteredIDs = [try LedgerFixtures.id(999, EvidenceTag.self).rawValue]
            let unsigned = UnsignedLedgerOperation(
                schemaVersion: LedgerOperation.schemaVersion,
                operationID: valid.operation.operationID,
                actorID: actor,
                actorSequence: 1,
                operationType: valid.operation.operationType,
                createdAt: valid.operation.createdAt,
                affectedIDs: alteredIDs,
                payloadHash: valid.operation.payloadHash,
                previousOperationHash: nil,
                idempotencyKey: nil
            )
            let altered = LedgerOperation(
                operationID: valid.operation.operationID,
                actorID: actor,
                actorSequence: 1,
                operationType: valid.operation.operationType,
                createdAt: valid.operation.createdAt,
                affectedIDs: alteredIDs,
                payload: valid.operation.payload,
                payloadHash: valid.operation.payloadHash,
                previousOperationHash: nil,
                operationHash: try LedgerFixtures.digester.sha256(
                    LedgerFixtures.encoder.encode(unsigned)
                ),
                idempotencyKey: nil
            )
            XCTAssertThrowsError(try harness.committer.commit(
                LedgerTransaction(mutation: mutation, operation: altered)
            )) { error in
                XCTAssertEqual(
                    error as? FoodLedgerStoreError,
                    .integrityFailure("operation payload"),
                    harness.name
                )
            }
        }
    }

    func testLibraryLookupIsExactAndReturnsTheStoredVersion() throws {
        try forEachStore { harness, service in
            _ = try service.commit(
                LedgerFixtures.baseMutation(),
                type: .createProduct,
                operationID: LedgerFixtures.operationID(117)
            )
            let entry = LibraryEntry(
                libraryEntryID: try LedgerFixtures.id(60, LibraryEntryTag.self),
                createdAt: LedgerFixtures.date
            )
            let version = try LibraryEntryVersion(
                libraryEntryVersionID: LedgerFixtures.id(61, LibraryEntryVersionTag.self),
                libraryEntryID: entry.libraryEntryID,
                ordinal: VersionOrdinal(1),
                productVersionID: LedgerFixtures.id(3, ProductVersionTag.self),
                aliases: [LedgerText("fixture alias")],
                createdAt: LedgerFixtures.date
            )
            _ = try service.commit(
                LedgerMutation(libraryEntries: [entry], libraryEntryVersions: [version]),
                type: .saveLibraryEntry,
                operationID: LedgerFixtures.operationID(118)
            )

            XCTAssertEqual(
                try harness.reader.exactLibraryEntries(alias: LedgerText("fixture alias")),
                [version],
                harness.name
            )
            XCTAssertEqual(
                try harness.reader.exactLibraryEntries(alias: LedgerText("Fixture alias")),
                [],
                harness.name
            )
        }
    }

    func testMissingReferenceRollsBackEveryRowAndOperation() throws {
        try forEachStore { harness, service in
            let mutation = try LedgerFixtures.baseMutation()
            let invalid = LedgerMutation(
                evidence: mutation.evidence,
                productVersions: mutation.productVersions
            )
            XCTAssertThrowsError(try service.commit(
                invalid,
                type: .createProduct,
                operationID: LedgerFixtures.operationID(102)
            ))
            XCTAssertEqual(
                try harness.reader.counts(),
                LedgerCounts(evidence: 0, productVersions: 0, resolutionVersions: 0,
                             logItemVersions: 0, conflicts: 0, operations: 0),
                harness.name
            )
        }
    }

    func testMissingEvidenceReferenceIsRejectedByBothAdapters() throws {
        try forEachStore { harness, service in
            let product = Product(
                productID: try LedgerFixtures.id(70, ProductTag.self),
                createdAt: LedgerFixtures.date
            )
            let version = try ProductVersion(
                productVersionID: LedgerFixtures.id(71, ProductVersionTag.self),
                productID: product.productID,
                ordinal: VersionOrdinal(1),
                name: LedgerText("Missing evidence"),
                itemClass: .food,
                packFacts: PackFacts(),
                identity: LedgerFixtures.identity(),
                evidenceIDs: [LedgerFixtures.id(799, EvidenceTag.self)],
                assertionIDs: [],
                createdAt: LedgerFixtures.date
            )
            XCTAssertThrowsError(try service.commit(
                LedgerMutation(products: [product], productVersions: [version]),
                type: .createProduct,
                operationID: LedgerFixtures.operationID(121)
            ), harness.name)
            XCTAssertEqual(try harness.reader.counts().productVersions, 0, harness.name)
            XCTAssertEqual(try harness.reader.counts().operations, 0, harness.name)
        }
    }

    func testSupersessionCannotCrossStableEntities() throws {
        try forEachStore { harness, service in
            _ = try service.commit(
                LedgerFixtures.baseMutation(),
                type: .createProduct,
                operationID: LedgerFixtures.operationID(122)
            )
            let other = Product(
                productID: try LedgerFixtures.id(72, ProductTag.self),
                createdAt: LedgerFixtures.date
            )
            let invalid = try ProductVersion(
                productVersionID: LedgerFixtures.id(73, ProductVersionTag.self),
                productID: other.productID,
                ordinal: VersionOrdinal(2),
                supersedesProductVersionID: LedgerFixtures.id(3, ProductVersionTag.self),
                name: LedgerText("Crossed lineage"),
                itemClass: .food,
                packFacts: PackFacts(),
                identity: LedgerFixtures.identity(),
                evidenceIDs: [LedgerFixtures.id(1, EvidenceTag.self)],
                assertionIDs: [],
                createdAt: LedgerFixtures.date
            )
            XCTAssertThrowsError(try service.commit(
                LedgerMutation(products: [other], productVersions: [invalid]),
                type: .reformulateProduct,
                operationID: LedgerFixtures.operationID(123)
            ), harness.name)
            XCTAssertEqual(try harness.reader.counts().productVersions, 1, harness.name)
            XCTAssertEqual(try harness.reader.counts().operations, 1, harness.name)
        }
    }

    func testMissingMixtureComponentRollsBack() throws {
        try forEachStore { harness, service in
            _ = try service.commit(
                LedgerFixtures.baseMutation(),
                type: .createProduct,
                operationID: LedgerFixtures.operationID(124)
            )
            let log = LogItem(
                logItemID: try LedgerFixtures.id(74, LogItemTag.self),
                createdAt: LedgerFixtures.date
            )
            let version = try LogItemVersion(
                logItemVersionID: LedgerFixtures.id(75, LogItemVersionTag.self),
                logItemID: log.logItemID,
                ordinal: VersionOrdinal(1),
                occurredAt: LedgerFixtures.date,
                reportingDate: LedgerText("2026-09-20"),
                composition: .mixture([LedgerFixtures.id(798, LogItemVersionTag.self)]),
                edibleQuantity: PositiveQuantity(value: 100, unit: .grams),
                originalResolutionVersionID: LedgerFixtures.id(5, ResolutionVersionTag.self),
                effectiveResolutionVersionID: LedgerFixtures.id(5, ResolutionVersionTag.self),
                createdAt: LedgerFixtures.date
            )
            XCTAssertThrowsError(try service.commit(
                LedgerMutation(logItems: [log], logItemVersions: [version]),
                type: .recordLogItem,
                operationID: LedgerFixtures.operationID(125)
            ), harness.name)
            XCTAssertEqual(try harness.reader.counts().logItemVersions, 0, harness.name)
            XCTAssertEqual(try harness.reader.counts().operations, 1, harness.name)
        }
    }

    func testImmutableRowsRejectSecondOperationWithoutPartialMutation() throws {
        try forEachStore { harness, service in
            let mutation = try LedgerFixtures.baseMutation()
            _ = try service.commit(
                mutation,
                type: .createProduct,
                operationID: LedgerFixtures.operationID(103)
            )
            XCTAssertThrowsError(try service.commit(
                LedgerMutation(products: mutation.products),
                type: .createProduct,
                operationID: LedgerFixtures.operationID(104)
            )) { error in
                guard case .immutableRecord = error as? FoodLedgerStoreError else {
                    return XCTFail("\(harness.name): \(error)")
                }
            }
            XCTAssertEqual(try harness.reader.counts().operations, 1, harness.name)
        }
    }

    func testActorSequenceAndPreviousHashFailuresAreClosed() throws {
        try forEachStore { harness, service in
            _ = try service.commit(
                LedgerFixtures.baseMutation(),
                type: .createProduct,
                operationID: LedgerFixtures.operationID(105)
            )
            let actor: ActorID = try LedgerFixtures.id(900, ActorTag.self)
            let newEvidence = try CaptureEvidence(
                evidenceID: LedgerFixtures.id(92, EvidenceTag.self),
                kind: .synthetic,
                capturedAt: LedgerFixtures.date,
                locale: LedgerText("en_GB"),
                captureMethod: LedgerText("fixture"),
                captureMethodVersion: LedgerText("v1"),
                originalPayload: .text(LedgerText("gap"))
            )
            let gap = try LedgerFixtures.validTransaction(
                mutation: LedgerMutation(evidence: [newEvidence]),
                operationID: LedgerFixtures.operationID(106),
                actorID: actor,
                sequence: 3,
                previousHash: try harness.committer.actorHead(for: actor).operationHash
            )
            XCTAssertThrowsError(try harness.committer.commit(gap)) { error in
                XCTAssertEqual(error as? FoodLedgerStoreError, .actorSequenceMismatch, harness.name)
            }
            let wrongHash = try LedgerFixtures.validTransaction(
                mutation: LedgerMutation(evidence: [newEvidence]),
                operationID: LedgerFixtures.operationID(107),
                actorID: actor,
                sequence: 2,
                previousHash: try? SHA256Digest(String(repeating: "a", count: 64))
            )
            XCTAssertThrowsError(try harness.committer.commit(wrongHash)) { error in
                XCTAssertEqual(error as? FoodLedgerStoreError, .actorHashMismatch, harness.name)
            }
            XCTAssertEqual(try harness.reader.counts().operations, 1, harness.name)
        }
    }

    func testConcurrentSuccessorsAndExplicitConflictArePreserved() throws {
        try forEachStore { harness, service in
            _ = try service.commit(
                LedgerFixtures.baseMutation(),
                type: .createProduct,
                operationID: LedgerFixtures.operationID(108)
            )
            let first = try successor(number: 20, name: "Reformulation A")
            let second = try successor(number: 21, name: "Reformulation B")
            let conflict = try LedgerConflict(
                conflictID: LedgerFixtures.id(22, ConflictTag.self),
                kind: .competingProductSuccessors,
                ancestorVersionID: VersionReference(first.supersedesProductVersionID!.rawValue),
                competingVersionIDs: [
                    VersionReference(first.productVersionID.rawValue),
                    VersionReference(second.productVersionID.rawValue)
                ],
                createdAt: LedgerFixtures.date
            )
            _ = try service.commit(
                LedgerMutation(productVersions: [first, second], conflicts: [conflict]),
                type: .preserveConflict,
                operationID: LedgerFixtures.operationID(109)
            )
            XCTAssertEqual(
                try harness.reader.productVersions(productID: LedgerFixtures.id(2, ProductTag.self)).count,
                3,
                harness.name
            )
            XCTAssertEqual(try harness.reader.conflicts(), [conflict], harness.name)
        }
    }

    func testCompetingSuccessorWithoutConflictFailsAtomically() throws {
        try forEachStore { harness, service in
            _ = try service.commit(
                LedgerFixtures.baseMutation(),
                type: .createProduct,
                operationID: LedgerFixtures.operationID(114)
            )
            _ = try service.commit(
                LedgerMutation(productVersions: [successor(number: 50, name: "First successor")]),
                type: .reformulateProduct,
                operationID: LedgerFixtures.operationID(115)
            )
            XCTAssertThrowsError(try service.commit(
                LedgerMutation(productVersions: [successor(number: 51, name: "Competing successor")]),
                type: .reformulateProduct,
                operationID: LedgerFixtures.operationID(116)
            )) { error in
                XCTAssertEqual(
                    error as? FoodLedgerStoreError,
                    .integrityFailure("unrecorded competing successor"),
                    harness.name
                )
            }
            XCTAssertEqual(
                try harness.reader.productVersions(productID: LedgerFixtures.id(2, ProductTag.self)).count,
                2,
                harness.name
            )
            XCTAssertEqual(try harness.reader.counts().operations, 2, harness.name)
        }
    }

    func testConflictCannotNameUnrelatedOrMissingVersions() throws {
        try forEachStore { harness, service in
            _ = try service.commit(
                LedgerFixtures.baseMutation(),
                type: .createProduct,
                operationID: LedgerFixtures.operationID(126)
            )
            let invalid = try LedgerConflict(
                conflictID: LedgerFixtures.id(76, ConflictTag.self),
                kind: .competingProductSuccessors,
                ancestorVersionID: VersionReference(
                    LedgerFixtures.id(3, ProductVersionTag.self).rawValue
                ),
                competingVersionIDs: [
                    VersionReference(LedgerFixtures.id(77, ProductVersionTag.self).rawValue),
                    VersionReference(LedgerFixtures.id(78, ProductVersionTag.self).rawValue)
                ],
                createdAt: LedgerFixtures.date
            )
            XCTAssertThrowsError(try service.commit(
                LedgerMutation(conflicts: [invalid]),
                type: .preserveConflict,
                operationID: LedgerFixtures.operationID(127)
            ), harness.name)
            XCTAssertEqual(try harness.reader.counts().conflicts, 0, harness.name)
            XCTAssertEqual(try harness.reader.counts().operations, 1, harness.name)
        }
    }

    func testReformulationCorrectionsQuantityAndPlateVersionsRemainImmutable() throws {
        try forEachStore { harness, service in
            _ = try service.commit(
                LedgerFixtures.baseMutation(),
                type: .createProduct,
                operationID: LedgerFixtures.operationID(110)
            )
            let productV2 = try successor(number: 30, name: "Reformulated food")
            let resolutionV2 = try NutritionResolutionVersion(
                resolutionVersionID: try LedgerFixtures.id(31, ResolutionVersionTag.self),
                resolutionID: try LedgerFixtures.id(4, ResolutionTag.self),
                ordinal: try VersionOrdinal(2),
                supersedesResolutionVersionID: try LedgerFixtures.id(5, ResolutionVersionTag.self),
                methodVersion: try LedgerText("correction_v1"),
                sourceReleaseIDs: [try ExternalIdentifier("package:fixture-v1")],
                nutrients: try LedgerFixtures.nutrientSet(),
                createdAt: LedgerFixtures.date
            )
            let conversionV1 = try QuantityConversionVersion(
                quantityConversionVersionID: LedgerFixtures.id(32, QuantityConversionVersionTag.self),
                ordinal: VersionOrdinal(1),
                sourceQuantity: PositiveQuantity(value: 1, unit: .count),
                convertedQuantity: PositiveQuantity(value: 42, unit: .grams),
                methodVersion: LedgerText("label_unit_v1"),
                evidenceID: LedgerFixtures.id(1, EvidenceTag.self),
                createdAt: LedgerFixtures.date
            )
            let conversionV2 = try QuantityConversionVersion(
                quantityConversionVersionID: LedgerFixtures.id(33, QuantityConversionVersionTag.self),
                ordinal: VersionOrdinal(2),
                supersedesQuantityConversionVersionID: conversionV1.quantityConversionVersionID,
                sourceQuantity: PositiveQuantity(value: 1, unit: .count),
                convertedQuantity: PositiveQuantity(value: 45, unit: .grams),
                methodVersion: LedgerText("corrected_unit_v1"),
                evidenceID: LedgerFixtures.id(1, EvidenceTag.self),
                createdAt: LedgerFixtures.date
            )
            let plate = Plate(plateID: try LedgerFixtures.id(34, PlateTag.self), createdAt: LedgerFixtures.date)
            let plateV1 = try PlateWeightVersion(
                plateWeightVersionID: LedgerFixtures.id(35, PlateWeightVersionTag.self),
                plateID: plate.plateID,
                ordinal: VersionOrdinal(1),
                emptyWeight: PositiveQuantity(value: 300, unit: .grams),
                createdAt: LedgerFixtures.date
            )
            let plateV2 = try PlateWeightVersion(
                plateWeightVersionID: LedgerFixtures.id(36, PlateWeightVersionTag.self),
                plateID: plate.plateID,
                ordinal: VersionOrdinal(2),
                supersedesPlateWeightVersionID: plateV1.plateWeightVersionID,
                emptyWeight: PositiveQuantity(value: 305, unit: .grams),
                createdAt: LedgerFixtures.date
            )
            let log = LogItem(logItemID: try LedgerFixtures.id(37, LogItemTag.self), createdAt: LedgerFixtures.date)
            let logV1 = try makeLogVersion(
                number: 38, log: log, ordinal: 1, supersedes: nil,
                productVersion: productV2.productVersionID,
                resolutionVersion: resolutionV2.resolutionVersionID,
                conversion: conversionV1.quantityConversionVersionID,
                reason: nil
            )
            let logV2 = try makeLogVersion(
                number: 39, log: log, ordinal: 2, supersedes: logV1.logItemVersionID,
                productVersion: productV2.productVersionID,
                resolutionVersion: resolutionV2.resolutionVersionID,
                conversion: conversionV2.quantityConversionVersionID,
                reason: LedgerText("corrected quantity")
            )
            _ = try service.commit(
                LedgerMutation(
                    productVersions: [productV2],
                    resolutionVersions: [resolutionV2],
                    logItems: [log],
                    logItemVersions: [logV1, logV2],
                    quantityConversions: [conversionV1, conversionV2],
                    plates: [plate],
                    plateWeightVersions: [plateV1, plateV2]
                ),
                type: .composite,
                operationID: LedgerFixtures.operationID(111)
            )
            XCTAssertEqual(try harness.reader.counts().productVersions, 2, harness.name)
            XCTAssertEqual(try harness.reader.counts().resolutionVersions, 2, harness.name)
            XCTAssertEqual(try harness.reader.counts().logItemVersions, 2, harness.name)
        }
    }

    func testSourceReleasesInstallSideBySide() throws {
        try forEachStore { harness, service in
            let first = try sourceRelease(name: "cofid:2021", hashCharacter: "a")
            let second = try sourceRelease(name: "cofid:2026", hashCharacter: "b")
            _ = try service.installSourceRelease(
                first,
                operationID: LedgerFixtures.operationID(112),
                idempotencyKey: LedgerText("install-cofid-2021")
            )
            _ = try service.installSourceRelease(
                second,
                operationID: LedgerFixtures.operationID(113),
                idempotencyKey: LedgerText("install-cofid-2026")
            )
            XCTAssertEqual(try harness.reader.sourceRelease(id: first.sourceReleaseID), first, harness.name)
            XCTAssertEqual(try harness.reader.sourceRelease(id: second.sourceReleaseID), second, harness.name)
        }
    }

    func testConfirmationSaveAndOfflineReopenUseBothStoreAdapters() throws {
        try forEachStore { harness, ledger in
            let base = try LedgerFixtures.baseMutation()
            let candidate = try PopulatedFoodCandidate(
                candidate: ProviderNeutralCandidate(
                    sourceReleaseID: try ExternalIdentifier("package:fixture-v1"),
                    recordID: try ExternalIdentifier("fixture:row-1"),
                    identity: try LedgerFixtures.identity(),
                    edibleQuantity: .known(
                        try PositiveQuantity(value: 100, unit: .grams),
                        conversionVersionID: nil
                    ),
                    nutrients: try LedgerFixtures.nutrientSet(),
                    evidenceIDs: [try LedgerFixtures.id(1, EvidenceTag.self)]
                ),
                name: try LedgerText("Fixture food"),
                itemClass: .food
            )
            let input = try PopulatedFoodConfirmation(
                evidence: base.evidence,
                sourceReleases: base.sourceReleases,
                candidates: [candidate],
                expectedIdentity: try LedgerFixtures.identity(),
                expectedEdibleQuantity: .known(
                    try PositiveQuantity(value: 100, unit: .grams),
                    conversionVersionID: nil
                )
            )
            var state = FoodConfirmationState(input: input)
            FoodConfirmationReducer.reduce(state: &state, action: .accept)
            let confirmation = FoodConfirmationService(
                ledger: ledger,
                reader: harness.reader,
                clock: LedgerFixtures.clock,
                ids: ContractSequenceIDs()
            )
            let saved = try confirmation.save(
                state,
                operationID: LedgerFixtures.operationID(150)
            )
            let reopened = try XCTUnwrap(
                confirmation.reopen(logItemID: saved.logItem.logItemID),
                harness.name
            )
            XCTAssertEqual(reopened.selectedCandidate.name.value, "Fixture food", harness.name)
            XCTAssertEqual(reopened.quantity.value, 100, harness.name)
            XCTAssertEqual(try harness.reader.counts().operations, 1, harness.name)
        }
    }

    private func forEachStore(
        _ body: (TestHarness, FoodLedgerService) throws -> Void
    ) throws {
        let harnesses = try LedgerFixtures.harnesses()
        defer { harnesses.forEach { $0.cleanup() } }
        for harness in harnesses {
            try body(harness, LedgerFixtures.service(harness.committer))
        }
    }

    private func successor(number: Int, name: String) throws -> ProductVersion {
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

    private func makeLogVersion(
        number: Int,
        log: LogItem,
        ordinal: Int,
        supersedes: LogItemVersionID?,
        productVersion: ProductVersionID,
        resolutionVersion: ResolutionVersionID,
        conversion: QuantityConversionVersionID,
        reason: LedgerText?
    ) throws -> LogItemVersion {
        try LogItemVersion(
            logItemVersionID: LedgerFixtures.id(number, LogItemVersionTag.self),
            logItemID: log.logItemID,
            ordinal: VersionOrdinal(ordinal),
            supersedesLogItemVersionID: supersedes,
            occurredAt: LedgerFixtures.date,
            reportingDate: LedgerText("2026-09-20"),
            composition: .product(productVersion),
            edibleQuantity: PositiveQuantity(value: 1, unit: .count),
            quantityConversionVersionID: conversion,
            originalResolutionVersionID: resolutionVersion,
            effectiveResolutionVersionID: resolutionVersion,
            correctionReason: reason,
            createdAt: LedgerFixtures.date
        )
    }

    private func sourceRelease(name: String, hashCharacter: Character) throws -> SourceRelease {
        SourceRelease(
            sourceReleaseID: try ExternalIdentifier(name),
            sourceID: try ExternalIdentifier("cofid"),
            releasedAt: LedgerFixtures.date,
            artifactHash: try SHA256Digest(String(repeating: hashCharacter, count: 64)),
            schemaVersion: try LedgerText("v1"),
            pipelineVersion: try LedgerText("v1"),
            licence: try LedgerText("Open Government Licence v3.0"),
            attribution: try LedgerText("invented fixture"),
            manifestHash: try SHA256Digest(String(repeating: hashCharacter, count: 64))
        )
    }
}

private final class ContractSequenceIDs: LedgerIDGenerating, @unchecked Sendable {
    private let lock = NSLock()
    private var value = 1_000

    func makeID<Tag>(_ tag: Tag.Type) throws -> LedgerID<Tag> {
        lock.lock()
        defer { lock.unlock() }
        value += 1
        return try LedgerID(String(format: "00000000-0000-0000-0000-%012x", value))
    }
}
