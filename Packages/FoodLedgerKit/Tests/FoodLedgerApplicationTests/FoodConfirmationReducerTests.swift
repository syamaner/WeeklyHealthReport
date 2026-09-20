import FoodLedgerApplication
import FoodLedgerDomain
import FoodLedgerTestSupport
import XCTest

final class FoodConfirmationReducerTests: XCTestCase {
    func testReducerModelsCandidateChoiceClosestMatchDeclineCorrectionAndFailure() throws {
        var state = FoodConfirmationState(input: try fixtureInput(candidateCount: 2))
        FoodConfirmationReducer.reduce(state: &state, action: .selectCandidate(1))
        XCTAssertEqual(state.selectedCandidateIndex, 1)

        let explanation = try LedgerText("The preparation difference is understood")
        FoodConfirmationReducer.reduce(state: &state, action: .acceptClosestMatch(explanation))
        XCTAssertEqual(state.decision, .acceptedClosestMatch(explanation: explanation))

        let correction = FoodCorrection(
            name: try LedgerText("Corrected food"),
            brand: nil,
            variant: nil,
            identity: state.selectedCandidate.candidate.identity,
            nutrients: state.selectedCandidate.candidate.nutrients,
            reason: try LedgerText("Package wording corrected")
        )
        FoodConfirmationReducer.reduce(state: &state, action: .applyCorrection(correction))
        XCTAssertEqual(state.decision, .accepted)
        FoodConfirmationReducer.reduce(state: &state, action: .saveFailed("offline"))
        XCTAssertEqual(state.correction, correction)
        XCTAssertEqual(state.selectedCandidateIndex, 1)
        XCTAssertEqual(state.quantity.value, 100)
        XCTAssertEqual(state.phase, .saveFailed(message: "offline"))

        FoodConfirmationReducer.reduce(state: &state, action: .decline)
        XCTAssertEqual(state.decision, .declined)
    }

    func testAtomicSaveOfflineReopenAndImmutableCorrectionVersions() throws {
        let store = InMemoryFoodLedgerStore()
        let ids = SequenceIDs()
        let service = makeService(store: store, ids: ids)
        var state = FoodConfirmationState(input: try fixtureInput())
        FoodConfirmationReducer.reduce(state: &state, action: .accept)

        let first = try service.save(state, operationID: id(800, OperationTag.self))
        XCTAssertEqual(try store.counts().productVersions, 1)
        XCTAssertEqual(try store.counts().resolutionVersions, 1)
        XCTAssertEqual(try store.counts().logItemVersions, 1)

        var reopened = try XCTUnwrap(service.reopen(logItemID: first.logItem.logItemID))
        let correction = FoodCorrection(
            name: try LedgerText("Corrected fixture food"),
            brand: nil,
            variant: nil,
            identity: reopened.selectedCandidate.candidate.identity,
            nutrients: reopened.selectedCandidate.candidate.nutrients,
            reason: try LedgerText("Verified package correction")
        )
        FoodConfirmationReducer.reduce(state: &reopened, action: .applyCorrection(correction))
        FoodConfirmationReducer.reduce(state: &reopened, action: .accept)
        let second = try service.save(reopened, operationID: id(801, OperationTag.self))
        XCTAssertEqual(try store.counts().productVersions, 2)
        XCTAssertEqual(try store.counts().resolutionVersions, 2)
        XCTAssertEqual(try store.counts().logItemVersions, 2)
        XCTAssertEqual(second.productVersion.supersedesProductVersionID, first.productVersion.productVersionID)
        XCTAssertEqual(first.productVersion.name.value, "Fixture food")

        var quantityEdit = try XCTUnwrap(service.reopen(logItemID: first.logItem.logItemID))
        FoodConfirmationReducer.reduce(state: &quantityEdit, action: .setQuantity(150, .grams))
        FoodConfirmationReducer.reduce(state: &quantityEdit, action: .accept)
        let third = try service.save(quantityEdit, operationID: id(802, OperationTag.self))
        XCTAssertEqual(try store.counts().productVersions, 2)
        XCTAssertEqual(try store.counts().resolutionVersions, 2)
        XCTAssertEqual(try store.counts().logItemVersions, 3)
        XCTAssertEqual(third.logItemVersion.edibleQuantity.value, 150)
        XCTAssertEqual(first.logItemVersion.edibleQuantity.value, 100)

        var plateEdit = try XCTUnwrap(service.reopen(logItemID: first.logItem.logItemID))
        FoodConfirmationReducer.reduce(state: &plateEdit, action: .setQuantity(250, .grams))
        FoodConfirmationReducer.reduce(state: &plateEdit, action: .setPlateChoice(.new(
            emptyWeight: try PositiveQuantity(value: 50, unit: .grams),
            superseding: plateEdit.reopened?.plateWeightVersion
        )))
        FoodConfirmationReducer.reduce(state: &plateEdit, action: .accept)
        let fourth = try service.save(plateEdit, operationID: id(803, OperationTag.self))
        XCTAssertEqual(fourth.logItemVersion.edibleQuantity.value, 200)
        XCTAssertNotNil(fourth.logItemVersion.plateWeightVersionID)
        XCTAssertEqual(try store.counts().logItemVersions, 4)
    }

    func testThreeSyntheticRoutesUseOneModelAndMutationShape() throws {
        let kinds: [CaptureKind] = [.barcode, .labelText, .synthetic]
        var shapes: [[Int]] = []
        for (index, kind) in kinds.enumerated() {
            let store = RecordingStore()
            let service = makeService(store: store, ids: SequenceIDs(seed: index * 100))
            var state = FoodConfirmationState(input: try fixtureInput(kind: kind))
            FoodConfirmationReducer.reduce(state: &state, action: .accept)
            _ = try service.save(state, operationID: id(850 + index, OperationTag.self))
            let mutation = try XCTUnwrap(store.transaction?.mutation)
            shapes.append([
                mutation.evidence.count, mutation.products.count,
                mutation.productVersions.count, mutation.resolutions.count,
                mutation.resolutionVersions.count, mutation.logItems.count,
                mutation.logItemVersions.count, mutation.candidateDecisions.count
            ])
        }
        XCTAssertEqual(Set(shapes.map(String.init(describing:))).count, 1)
    }

    func testFailedSaveLeavesNoPartialMutation() throws {
        let store = RecordingStore(failure: .integrityFailure("synthetic failure"))
        let service = makeService(store: store, ids: SequenceIDs())
        var state = FoodConfirmationState(input: try fixtureInput())
        FoodConfirmationReducer.reduce(state: &state, action: .accept)
        XCTAssertThrowsError(try service.save(state, operationID: id(900, OperationTag.self)))
        XCTAssertNil(store.transaction)
        XCTAssertEqual(try store.counts(), LedgerCounts(
            evidence: 0, productVersions: 0, resolutionVersions: 0,
            logItemVersions: 0, conflicts: 0, operations: 0
        ))
    }

    func testDirectAcceptanceCannotBypassMaterialDifference() throws {
        let base = try fixtureInput()
        let candidateIdentity = base.candidates[0].candidate.identity
        let expected = try DecisiveIdentity(
            preparation: PreparationState(kind: .raw),
            bone: candidateIdentity.bone,
            skin: candidateIdentity.skin,
            drained: candidateIdentity.drained,
            packingMedium: candidateIdentity.packingMedium,
            fortification: candidateIdentity.fortification,
            declaredFortificants: candidateIdentity.declaredFortificants,
            servingBasis: candidateIdentity.servingBasis
        )
        let input = try PopulatedFoodConfirmation(
            evidence: base.evidence,
            sourceReleases: base.sourceReleases,
            candidates: base.candidates,
            expectedIdentity: expected,
            expectedEdibleQuantity: base.expectedEdibleQuantity
        )
        var state = FoodConfirmationState(input: input)
        FoodConfirmationReducer.reduce(state: &state, action: .accept)
        let store = InMemoryFoodLedgerStore()

        XCTAssertThrowsError(try makeService(store: store, ids: SequenceIDs()).save(
            state,
            operationID: id(901, OperationTag.self)
        )) {
            XCTAssertEqual(
                $0 as? FoodConfirmationSaveError,
                .unexplainedMaterialDifferences([.preparation])
            )
        }
        XCTAssertEqual(try store.counts().operations, 0)
    }

    func testMissingPlateDraftFailsWithoutPartialMutation() throws {
        let store = InMemoryFoodLedgerStore()
        var state = FoodConfirmationState(input: try fixtureInput())
        FoodConfirmationReducer.reduce(state: &state, action: .accept)
        FoodConfirmationReducer.reduce(state: &state, action: .setQuantity(200, .grams))
        FoodConfirmationReducer.reduce(state: &state, action: .setPlateChoice(.missing))

        XCTAssertThrowsError(try makeService(store: store, ids: SequenceIDs()).save(
            state,
            operationID: id(902, OperationTag.self)
        )) {
            XCTAssertEqual($0 as? FoodQuantityValidationError, .missingPlateWeight)
        }
        XCTAssertEqual(try store.counts().operations, 0)
    }

    func testCountConversionSurvivesCountEditAndClearsWhenUnitChanges() throws {
        var state = FoodConfirmationState(input: try fixtureInput())
        let conversion = QuantityConversionDraft(
            convertedQuantity: try PositiveQuantity(value: 42, unit: .grams),
            methodVersion: try LedgerText("count-mass-v1")
        )
        FoodConfirmationReducer.reduce(state: &state, action: .setQuantity(1, .count))
        FoodConfirmationReducer.reduce(state: &state, action: .setConversion(conversion))
        FoodConfirmationReducer.reduce(state: &state, action: .setQuantity(2, .count))
        XCTAssertEqual(state.quantity.conversion, conversion)

        FoodConfirmationReducer.reduce(state: &state, action: .setQuantity(42, .grams))
        XCTAssertNil(state.quantity.conversion)
    }

    private func makeService(
        store: some LedgerCommandCommitting & LedgerReading & FoodConfirmationReading,
        ids: SequenceIDs
    ) -> FoodConfirmationService {
        let clock = FixedClock()
        let ledger = FoodLedgerService(
            actorID: try! id(999, ActorTag.self),
            committer: store,
            clock: clock,
            encoder: FoundationCanonicalJSONEncoder(),
            digester: SHA256Digester()
        )
        return FoodConfirmationService(ledger: ledger, reader: store, clock: clock, ids: ids)
    }

    private func fixtureInput(candidateCount: Int = 1, kind: CaptureKind = .synthetic) throws -> PopulatedFoodConfirmation {
        let evidenceID: EvidenceID = try id(1, EvidenceTag.self)
        let release = SourceRelease(
            sourceReleaseID: try ExternalIdentifier("synthetic:food-v1"),
            sourceID: try ExternalIdentifier("synthetic"),
            releasedAt: FixedClock.date,
            artifactHash: try SHA256Digest(String(repeating: "a", count: 64)),
            schemaVersion: try LedgerText("food-v1"),
            pipelineVersion: try LedgerText("fixture-v1"),
            licence: try LedgerText("fixture"),
            attribution: try LedgerText("fixture"),
            manifestHash: try SHA256Digest(String(repeating: "b", count: 64))
        )
        let evidence = try CaptureEvidence(
            evidenceID: evidenceID,
            kind: kind,
            capturedAt: FixedClock.date,
            locale: LedgerText("en_GB"),
            captureMethod: LedgerText("synthetic_route"),
            captureMethodVersion: LedgerText("v1"),
            originalPayload: .text(LedgerText("populated evidence"))
        )
        let identity = try DecisiveIdentity(
            preparation: PreparationState(kind: .asSold),
            bone: .notApplicable,
            skin: .notApplicable,
            drained: .notApplicable,
            packingMedium: .named(LedgerText("none")),
            fortification: .unfortified,
            servingBasis: .per100Grams
        )
        let quantity = try PositiveQuantity(value: 100, unit: .grams)
        let provenance = NutrientProvenance(
            sourceKind: .exactProductDataset,
            sourceID: release.sourceID,
            sourceReleaseID: release.sourceReleaseID,
            recordID: try ExternalIdentifier("record:1"),
            evidenceID: evidenceID,
            capturedAt: FixedClock.date
        )
        let nutrients = try NutrientSet(entries: NutrientKey.allCases.map { key in
            if key == .protein {
                return try NutrientEntry(key: key, value: .measured(ExactNutrientValue(
                    amount: 10,
                    unit: key.canonicalUnit,
                    sourceValue: .exact(SourceExactNutrientValue(
                        amount: 10,
                        unit: LedgerText(key.canonicalUnit.rawValue),
                        basis: .per100Grams
                    )),
                    provenance: [provenance]
                )))
            }
            return try NutrientEntry(key: key, value: .unknown(.notDeclared))
        })
        let candidates = try (0..<candidateCount).map { index in
            try PopulatedFoodCandidate(
                candidate: ProviderNeutralCandidate(
                    sourceReleaseID: release.sourceReleaseID,
                    recordID: ExternalIdentifier("record:\(index + 1)"),
                    identity: identity,
                    edibleQuantity: .known(quantity, conversionVersionID: nil),
                    nutrients: nutrients,
                    evidenceIDs: [evidenceID]
                ),
                name: LedgerText(index == 0 ? "Fixture food" : "Alternate fixture food"),
                itemClass: .food
            )
        }
        return try PopulatedFoodConfirmation(
            evidence: [evidence],
            sourceReleases: [release],
            candidates: candidates,
            expectedIdentity: identity,
            expectedEdibleQuantity: .known(quantity, conversionVersionID: nil)
        )
    }

    private func id<Tag>(_ value: Int, _ tag: Tag.Type) throws -> LedgerID<Tag> {
        try LedgerID(String(format: "00000000-0000-0000-0000-%012x", value))
    }
}

private struct FixedClock: LedgerClock {
    static let date = Date(timeIntervalSince1970: 1_700_000_000)
    func now() -> Date { Self.date }
}

private final class SequenceIDs: LedgerIDGenerating, @unchecked Sendable {
    private var value: Int
    private let lock = NSLock()
    init(seed: Int = 100) { value = seed }
    func makeID<Tag>(_ tag: Tag.Type) throws -> LedgerID<Tag> {
        lock.lock(); defer { lock.unlock() }
        value += 1
        return try LedgerID(String(format: "00000000-0000-0000-0000-%012x", value))
    }
}

private final class RecordingStore: LedgerCommandCommitting, LedgerReading,
    FoodConfirmationReading, @unchecked Sendable
{
    var transaction: LedgerTransaction?
    let failure: FoodLedgerStoreError?
    init(failure: FoodLedgerStoreError? = nil) { self.failure = failure }
    func actorHead(for actorID: ActorID) throws -> ActorHead { ActorHead(sequence: 0, operationHash: nil) }
    func operation(id: OperationID) throws -> LedgerOperation? { nil }
    func commit(_ transaction: LedgerTransaction) throws -> CommitOutcome {
        if let failure { throw failure }
        self.transaction = transaction
        return .committed(transaction.operation)
    }
    func counts() throws -> LedgerCounts { LedgerCounts(evidence: 0, productVersions: 0, resolutionVersions: 0, logItemVersions: 0, conflicts: 0, operations: 0) }
    func productVersions(productID: ProductID) throws -> [ProductVersion] { [] }
    func resolutionVersion(id: ResolutionVersionID) throws -> NutritionResolutionVersion? { nil }
    func exactLibraryEntries(alias: LedgerText) throws -> [LibraryEntryVersion] { [] }
    func barcodeLibraryRecords(alias: LedgerText) throws -> [BarcodeLibraryRecord] { [] }
    func conflicts() throws -> [LedgerConflict] { [] }
    func sourceRelease(id: ExternalIdentifier) throws -> SourceRelease? { nil }
    func foodConfirmation(logItemID: LogItemID) throws -> StoredFoodConfirmation? { nil }
}
