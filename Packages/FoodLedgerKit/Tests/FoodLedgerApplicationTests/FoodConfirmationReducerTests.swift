import FoodLedgerApplication
import FoodLedgerDomain
import FoodLedgerTestSupport
import XCTest

final class FoodConfirmationReducerTests: XCTestCase {
    func testFractionalCountCannotSaveOrCalculateMassWithoutConversion() throws {
        let store = InMemoryFoodLedgerStore()
        let service = makeService(store: store, ids: SequenceIDs())
        var state = FoodConfirmationState(input: try fixtureInput(), queryQuantity: FoodQueryParser.parse("half a green pepper").quantity)
        XCTAssertEqual(state.quantity.value, 0.5)
        XCTAssertEqual(state.quantity.unit, .count)
        XCTAssertNil(state.quantity.conversion)
        FoodConfirmationReducer.reduce(state: &state, action: .accept)
        XCTAssertThrowsError(try state.quantity.calculatedEdibleQuantity()) { error in
            XCTAssertEqual(error as? FoodQuantityValidationError, .missingConversion)
        }
        XCTAssertThrowsError(try service.save(state, operationID: id(960, OperationTag.self))) { error in
            XCTAssertEqual(error as? FoodQuantityValidationError, .missingConversion)
        }
        XCTAssertEqual(try store.counts().logItemVersions, 0)
    }

    func testSaveAndProjectionShareCanonicalLocalDateWithNonGregorianDisplayCalendar() throws {
        var calendar = Calendar(identifier: .buddhist)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Pacific/Auckland"))
        let store = InMemoryFoodLedgerStore()
        let service = makeService(store: store, ids: SequenceIDs(), calendar: calendar)
        var state = FoodConfirmationState(input: try fixtureInput())
        FoodConfirmationReducer.reduce(state: &state, action: .accept)
        let saved = try service.save(state, operationID: id(920, OperationTag.self))
        let dateKey = FoodReportingDay.key(for: FixedClock.date, calendar: calendar)
        XCTAssertEqual(dateKey, "2023-11-15")
        XCTAssertEqual(saved.logItemVersion.reportingDate.value, dateKey)
        let records = try store.archiveState().records
        XCTAssertEqual(try FoodIntakeProjection(records: records, reportingDate: dateKey).summary.itemCount, 1)
        let tomorrow = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: FixedClock.date))
        let pastDays = FoodIntakeDayPreview.pastWeek(records: records, now: tomorrow, calendar: calendar)
        XCTAssertEqual(pastDays.first?.summary?.itemCount, 1)
        XCTAssertEqual(FoodReportingDay.key(for: try XCTUnwrap(pastDays.first?.date), calendar: calendar), dateKey)
    }

    func testRemoveRestoreRetainsHistoryRejectsStaleHeadsAndRecoversRetries() throws {
        let store = InMemoryFoodLedgerStore()
        let ids = SequenceIDs()
        let confirmations = makeService(store: store, ids: ids)
        var state = FoodConfirmationState(input: try fixtureInput())
        FoodConfirmationReducer.reduce(state: &state, action: .accept)
        let saved = try confirmations.save(state, operationID: id(910, OperationTag.self))
        let original = saved.logItemVersion
        let before = try store.archiveState().records
        let ledger = FoodLedgerService(actorID: try id(999, ActorTag.self), committer: store,
            clock: FixedClock(), encoder: FoundationCanonicalJSONEncoder(), digester: SHA256Digester())
        let management = FoodLogManagementService(ledger: ledger,
            reader: ArchiveFoodLogHistoryReader(archive: store), clock: FixedClock(), ids: ids)
        let reason = try LedgerText("Mistaken entry")
        let operationID: OperationID = try id(911, OperationTag.self)
        let removed = try management.remove(logItemID: original.logItemID,
            expectedVersion: original.logItemVersionID, reason: reason, operationID: operationID)
        XCTAssertEqual(removed.composition, .removed(original.logItemVersionID))
        XCTAssertNil(try confirmations.reopen(logItemID: original.logItemID))
        let empty = try FoodIntakeProjection(records: store.archiveState().records, reportingDate: original.reportingDate.value)
        XCTAssertEqual(empty.summary.itemCount, 0)
        XCTAssertEqual(empty.removedRows.count, 1)
        XCTAssertEqual(empty.removedRows.first?.logItemVersionID, removed.logItemVersionID)
        XCTAssertEqual(try management.remove(logItemID: original.logItemID,
            expectedVersion: original.logItemVersionID, reason: reason, operationID: operationID), removed)
        XCTAssertThrowsError(try management.remove(logItemID: original.logItemID,
            expectedVersion: original.logItemVersionID, reason: reason, operationID: id(912, OperationTag.self)))
        let restored = try management.restore(logItemID: original.logItemID,
            expectedVersion: removed.logItemVersionID, reason: LedgerText("Restore mistake"),
            operationID: id(913, OperationTag.self))
        XCTAssertEqual(restored.composition, original.composition)
        XCTAssertEqual(restored.occurredAt, original.occurredAt)
        XCTAssertEqual(restored.reportingDate, original.reportingDate)
        XCTAssertEqual(restored.edibleQuantity, original.edibleQuantity)
        let after = try store.archiveState().records
        XCTAssertEqual(after.evidence, before.evidence)
        XCTAssertEqual(after.productVersions, before.productVersions)
        XCTAssertEqual(after.resolutionVersions, before.resolutionVersions)
        XCTAssertEqual(after.logItemVersions.count, 3)
        let restoredDay = try FoodIntakeProjection(records: after, reportingDate: original.reportingDate.value)
        XCTAssertEqual(restoredDay.summary.itemCount, 1)
        XCTAssertEqual(restoredDay.removedRows.count, 0)
        XCTAssertEqual(restoredDay.summary, try FoodIntakeProjection(records: before, reportingDate: original.reportingDate.value).summary)
    }

    func testIntakeProjectionUsesConfirmedHeadsAndRejectsCompetingVersions() throws {
        let store = InMemoryFoodLedgerStore()
        let service = makeService(store: store, ids: SequenceIDs())
        var state = FoodConfirmationState(input: try fixtureInput())
        FoodConfirmationReducer.reduce(state: &state, action: .accept)
        _ = try service.save(state, operationID: id(900, OperationTag.self))
        var records = try store.archiveState().records
        let first = try XCTUnwrap(records.logItemVersions.first)
        let projection = try FoodIntakeProjection(records: records, reportingDate: first.reportingDate.value)
        XCTAssertEqual(projection.rows.count, 1)
        XCTAssertEqual(projection.summary.itemCount, 1)
        XCTAssertEqual(try FoodIntakeProjection(records: records, reportingDate: "1900-01-01").rows.count, 0)
        let competing = try LogItemVersion(logItemVersionID: id(901, LogItemVersionTag.self),
            logItemID: first.logItemID, ordinal: VersionOrdinal(2), occurredAt: first.occurredAt,
            reportingDate: first.reportingDate, composition: first.composition, edibleQuantity: first.edibleQuantity,
            originalResolutionVersionID: first.originalResolutionVersionID,
            effectiveResolutionVersionID: first.effectiveResolutionVersionID, createdAt: first.createdAt)
        records.logItemVersions.append(competing)
        XCTAssertThrowsError(try FoodIntakeProjection(records: records, reportingDate: first.reportingDate.value))
        let corrected = try LogItemVersion(logItemVersionID: id(902, LogItemVersionTag.self),
            logItemID: first.logItemID, ordinal: VersionOrdinal(2), supersedesLogItemVersionID: first.logItemVersionID,
            occurredAt: first.occurredAt, reportingDate: LedgerText("1900-01-01"), composition: first.composition,
            edibleQuantity: PositiveQuantity(value: 150, unit: .grams),
            originalResolutionVersionID: first.originalResolutionVersionID,
            effectiveResolutionVersionID: first.effectiveResolutionVersionID,
            correctionReason: LedgerText("Date and amount corrected"), createdAt: first.createdAt)
        records.logItemVersions = [first, corrected]
        XCTAssertEqual(try FoodIntakeProjection(records: records, reportingDate: first.reportingDate.value).rows.count, 0)
        let revised = try FoodIntakeProjection(records: records, reportingDate: "1900-01-01")
        XCTAssertEqual(revised.rows.count, 1)
        XCTAssertEqual(revised.rows.first?.quantity.value, 150)
        XCTAssertEqual(revised.rows.first?.sourceIDs, ["synthetic"])
        XCTAssertEqual(revised.rows.first?.totals.first { $0.key == .protein }?.knownAmount, 15)

    }

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

    func testConsumedQuantityDoesNotRewriteCandidateIdentityQuantity() throws {
        let store = InMemoryFoodLedgerStore()
        var state = FoodConfirmationState(input: try fixtureInput())
        FoodConfirmationReducer.reduce(state: &state, action: .setQuantity(175, .grams))
        FoodConfirmationReducer.reduce(state: &state, action: .accept)

        let saved = try makeService(store: store, ids: SequenceIDs()).save(
            state,
            operationID: id(903, OperationTag.self)
        )

        XCTAssertEqual(saved.logItemVersion.edibleQuantity.value, 175)
        XCTAssertEqual(saved.candidateDecision.outcome, .selected)
        XCTAssertEqual(saved.candidateDecision.expectedEdibleQuantity, state.input.expectedEdibleQuantity)
    }

    func testExactProductUnknownsStillBlockEvenWithGenericCaptureAndExplanation() throws {
        let unknown = try DecisiveIdentity(preparation: PreparationState(kind: .unknown),
            bone: .unknown, skin: .unknown, drained: .unknown, packingMedium: .unknown,
            fortification: .unknown, servingBasis: .per100Grams)
        var state = FoodConfirmationState(input: try fixtureInput(kind: .genericSearch, identityOverride: unknown))
        XCTAssertFalse(state.isGenericEstimate)
        FoodConfirmationReducer.reduce(state: &state, action: .acceptClosestMatch(try LedgerText("I choose this")))
        let store = InMemoryFoodLedgerStore()
        XCTAssertThrowsError(try makeService(store: store, ids: SequenceIDs()).save(state, operationID: id(904, OperationTag.self))) { error in
            XCTAssertEqual(error as? FoodConfirmationSaveError, .unresolvedMandatoryIdentity([
                .preparation, .bone, .skin, .drained, .packingMedium, .fortification]))
        }
        XCTAssertEqual(try store.counts().logItemVersions, 0)
        XCTAssertEqual(FoodConfirmationPolicy.unresolvedIdentity(unknown, allowingEstimate: true), [])
    }

    func testGuidePreviewKeepsCountEvidenceEstimateAndMeasuredOverrideSeparate() throws {
        let candidate = try fixtureInput().candidates[0]
        let guide = try FoodEdibleWeightGuide(foodRecordID: candidate.candidate.recordID,
            foodSourceReleaseID: candidate.candidate.sourceReleaseID, guideID: ExternalIdentifier("synthetic:guide"),
            guideVersion: LedgerText("test-v1"), size: LedgerText("Synthetic size"), edibleGramsPerPiece: 40,
            sourceReleaseID: ExternalIdentifier("synthetic:portion-source"), evidenceID: id(1, EvidenceTag.self))
        let preview = try guide.estimate(for: candidate, count: 2,
            measuredOverride: PositiveQuantity(value: 85, unit: .grams))
        XCTAssertEqual(preview.count.value, 2)
        XCTAssertEqual(preview.guide, guide)
        XCTAssertEqual(preview.estimatedEdibleWeight.value, 80)
        XCTAssertEqual(preview.finalEdibleWeight.value, 85)
        XCTAssertThrowsError(try guide.estimate(for: candidate, count: 0))
        XCTAssertThrowsError(try guide.estimate(for: candidate, count: .infinity))
        XCTAssertThrowsError(try guide.estimate(for: candidate, count: 2,
            measuredOverride: PositiveQuantity(value: 85, unit: .millilitres)))
        let other = try fixtureInput(candidateCount: 2).candidates[1]
        XCTAssertThrowsError(try guide.estimate(for: other, count: 2))
    }

    func testDirectWeightRequiresSeparateGramsAndExplicitBasisAndPreservesOriginalInput() throws {
        for (original, unit) in [(2.0, QuantityUnit.count), (200, .millilitres), (150, .grams)] {
            let store = InMemoryFoodLedgerStore()
            let service = makeService(store: store, ids: SequenceIDs())
            var state = FoodConfirmationState(input: try fixtureInput())
            FoodConfirmationReducer.reduce(state: &state, action: .setQuantity(original, unit))
            FoodConfirmationReducer.reduce(state: &state, action: .accept)
            FoodConfirmationReducer.reduce(state: &state, action: .beginDirectWeight)
            XCTAssertNil(state.quantity.directWeight?.totalGrams)
            XCTAssertNil(state.quantity.directWeight?.basis)
            XCTAssertThrowsError(try service.save(state, operationID: id(940, OperationTag.self)))
            FoodConfirmationReducer.reduce(state: &state, action: .setDirectWeight(125))
            XCTAssertThrowsError(try service.save(state, operationID: id(940, OperationTag.self)))
            FoodConfirmationReducer.reduce(state: &state, action: .setWeightBasis(.measured))
            let preview = try state.quantity.calculatedEdibleQuantity()
            let selected = state.selectedCandidate
            let saved = try service.save(state, operationID: id(940, OperationTag.self))
            XCTAssertEqual(saved.logItemVersion.edibleQuantity, preview)
            XCTAssertEqual(saved.logItemVersion.weightDeclaration?.basis, .measured)
            XCTAssertEqual(saved.logItemVersion.weightDeclaration?.originalInput, try PositiveQuantity(value: original, unit: unit))
            XCTAssertEqual(saved.productVersion.identity, selected.candidate.identity)
            XCTAssertEqual(saved.resolutionVersion.nutrients, selected.candidate.nutrients)
            let reopened = try XCTUnwrap(service.reopen(logItemID: saved.logItem.logItemID))
            XCTAssertEqual(reopened.quantity.directWeight?.totalGrams, 125)
            XCTAssertEqual(reopened.quantity.directWeight?.basis, .measured)
            XCTAssertEqual(reopened.quantity.value, original)
            XCTAssertEqual(reopened.quantity.unit, unit)
            XCTAssertEqual(try reopened.quantity.calculatedEdibleQuantity(), preview)
        }
    }

    func testDirectWeightCountEditsAndCandidateChangesRequireCoherentReconfirmation() throws {
        var state = FoodConfirmationState(input: try fixtureInput(candidateCount: 2))
        FoodConfirmationReducer.reduce(state: &state, action: .setQuantity(2, .count))
        FoodConfirmationReducer.reduce(state: &state, action: .beginDirectWeight)
        FoodConfirmationReducer.reduce(state: &state, action: .setDirectWeight(120))
        FoodConfirmationReducer.reduce(state: &state, action: .setWeightBasis(.estimated))
        FoodConfirmationReducer.reduce(state: &state, action: .accept)
        FoodConfirmationReducer.reduce(state: &state, action: .setQuantity(3, .count))
        XCTAssertEqual(state.quantity.directWeight?.totalGrams, 120)
        XCTAssertEqual(try state.quantity.calculatedEdibleQuantity().value, 120)
        FoodConfirmationReducer.reduce(state: &state, action: .selectCandidate(1))
        XCTAssertEqual(state.decision, .undecided)
        XCTAssertEqual(state.quantity.directWeight?.totalGrams, 120)
        XCTAssertTrue(state.quantity.directWeight?.needsReconfirmation == true)
        XCTAssertThrowsError(try state.quantity.declaration())
        FoodConfirmationReducer.reduce(state: &state, action: .accept)
        XCTAssertEqual(try state.quantity.declaration()?.originalInput?.value, 3)
        var changed = state.selectedCandidate.candidate.identity
        changed = try DecisiveIdentity(preparation: PreparationState(kind: .cooked), bone: changed.bone,
            skin: changed.skin, drained: changed.drained, packingMedium: changed.packingMedium,
            fortification: changed.fortification, servingBasis: changed.servingBasis)
        FoodConfirmationReducer.reduce(state: &state, action: .applyCorrection(FoodCorrection(
            name: state.selectedCandidate.name, brand: nil, variant: nil, identity: changed,
            nutrients: state.selectedCandidate.candidate.nutrients, reason: try LedgerText("Prepared as cooked"))))
        XCTAssertEqual(state.decision, .undecided)
        XCTAssertThrowsError(try state.quantity.declaration())
        FoodConfirmationReducer.reduce(state: &state, action: .accept)
        XCTAssertEqual(try state.quantity.declaration()?.total.value, 120)
    }

    func testInvalidDirectTotalsAndPlatePreviewSaveAgreement() throws {
        let store = InMemoryFoodLedgerStore()
        let service = makeService(store: store, ids: SequenceIDs())
        var state = FoodConfirmationState(input: try fixtureInput())
        FoodConfirmationReducer.reduce(state: &state, action: .accept)
        FoodConfirmationReducer.reduce(state: &state, action: .beginDirectWeight)
        FoodConfirmationReducer.reduce(state: &state, action: .setWeightBasis(.estimated))
        for invalid in [0.0, -1, Double.nan, Double.infinity] {
            FoodConfirmationReducer.reduce(state: &state, action: .setDirectWeight(invalid))
            XCTAssertThrowsError(try service.save(state, operationID: id(941, OperationTag.self)))
            XCTAssertThrowsError(try state.quantity.calculatedEdibleQuantity())
        }
        FoodConfirmationReducer.reduce(state: &state, action: .setQuantity(2, .count))
        FoodConfirmationReducer.reduce(state: &state, action: .setDirectWeight(250))
        FoodConfirmationReducer.reduce(state: &state, action: .setPlateChoice(.new(
            emptyWeight: try PositiveQuantity(value: 50, unit: .grams), superseding: nil)))
        XCTAssertEqual(try state.quantity.calculatedEdibleQuantity().value, 200)
        let saved = try service.save(state, operationID: id(941, OperationTag.self))
        XCTAssertEqual(saved.logItemVersion.edibleQuantity.value, 200)
        XCTAssertEqual(saved.logItemVersion.weightDeclaration?.total.value, 250)
        let reopened = try XCTUnwrap(service.reopen(logItemID: saved.logItem.logItemID))
        XCTAssertEqual(try reopened.quantity.calculatedEdibleQuantity(), saved.logItemVersion.edibleQuantity)
        XCTAssertEqual(reopened.quantity.directWeight?.basis, .estimated)
    }

    private func makeService(
        store: some LedgerCommandCommitting & LedgerReading & FoodConfirmationReading,
        ids: SequenceIDs,
        calendar: Calendar = .autoupdatingCurrent
    ) -> FoodConfirmationService {
        let clock = FixedClock()
        let ledger = FoodLedgerService(
            actorID: try! id(999, ActorTag.self),
            committer: store,
            clock: clock,
            encoder: FoundationCanonicalJSONEncoder(),
            digester: SHA256Digester()
        )
        return FoodConfirmationService(ledger: ledger, reader: store, clock: clock, ids: ids, digester: SHA256Digester(), calendar: calendar)
    }

    private func fixtureInput(candidateCount: Int = 1, kind: CaptureKind = .synthetic, identityOverride: DecisiveIdentity? = nil) throws -> PopulatedFoodConfirmation {
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
        let identity = try identityOverride ?? DecisiveIdentity(
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
