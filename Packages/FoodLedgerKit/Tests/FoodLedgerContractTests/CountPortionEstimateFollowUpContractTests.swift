import Foundation
import FoodGenericSearch
import FoodLedgerApplication
import FoodLedgerArchive
import FoodLedgerDomain
import FoodLedgerTestSupport
import XCTest

/// count-portion-estimate-v1 (#307), invariant review of 89ba348f: servings wording through one
/// predicate, the reuse path bound to the same record, the method as an estimate on its own, an
/// archive round trip, a whole-milk volume day under v6, the cross-surface fixture, and retry,
/// removal and restoration keeping the guide conversion. Synthetic ledgers only.
final class CountPortionEstimateFollowUpContractTests: XCTestCase {
    private static let boiledLarge = "count_portion_guide_v1:usda_sr_legacy_173424_92500"

    // MARK: Servings, one predicate (review item 1)

    func testPastedLabelServingsAreServingsOnTheSavedEntryFoodLogRowAndHistory() throws {
        let harness = try memoryHarness()
        let service = try PastedLabelFixtures.service(harness)
        let input = try PastedLabelFixtures.input(PastedLabelFixtures.perServingManifest(readableServingSize: false))
        var state = FoodConfirmationState(input: input, prefillSourceQuantity: false)
        FoodConfirmationReducer.reduce(state: &state, action: .setQuantity(2, .count))
        state.answerPendingDifferences()
        FoodConfirmationReducer.reduce(state: &state, action: .accept)
        let saved = try service.save(state, operationID: LedgerFixtures.operationID(800))
        XCTAssertNil(saved.quantityConversion, "servings with no weight have no conversion")
        var edit = try XCTUnwrap(service.reopen(logItemID: saved.logItem.logItemID))
        FoodConfirmationReducer.reduce(state: &edit, action: .setQuantity(3, .count))
        _ = try service.save(edit, operationID: LedgerFixtures.operationID(801))

        let reading = try readingService(harness, confirmations: service)
        let detail = try XCTUnwrap(reading.savedEntry(saved.logItem.logItemID))
        XCTAssertTrue(detail.amountIsServings)
        let day = try reading.day(reportingDate: saved.logItemVersion.reportingDate.value)
        XCTAssertEqual(day.entries.first?.amountIsServings, true, "the Food Log row reads servings")
        guard case let .changed(amount?, _) = detail.history.first?.kind else { return XCTFail("an amount change") }
        XCTAssertTrue(amount.isServings, "history reads servings")
        // One source for the servings rule: the Food Log row reads the decision candidate's
        // release, as the saved entry and Recent do.
        let stored = try XCTUnwrap(harness.reader.foodConfirmation(logItemID: saved.logItem.logItemID))
        let records = try (harness.committer as! any FoodArchiveLedgerAccess).archiveState().records
        XCTAssertEqual(FoodIntakeProjection.decisionCandidateReleaseID(stored.resolutionVersion, records: records),
                       stored.candidateDecision.candidate.sourceReleaseID)
    }

    func testSourceRecipeServingsAreServings() throws {
        let harness = try memoryHarness()
        let service = try confirmationService(harness, guides: nil)
        var state = FoodConfirmationState(input: try XCTUnwrap(RecipeAdmissionFixtures.route()).confirmation)
        FoodConfirmationReducer.reduce(state: &state, action: .setQuantity(0.5, .count))
        state.answerPendingDifferences()
        FoodConfirmationReducer.reduce(state: &state, action: .accept)
        let saved = try service.save(state, operationID: LedgerFixtures.operationID(810))
        let reading = try readingService(harness, confirmations: service)
        XCTAssertEqual(try reading.savedEntry(saved.logItem.logItemID)?.amountIsServings, true)
        XCTAssertEqual(try reading.day(reportingDate: saved.logItemVersion.reportingDate.value).entries.first?.amountIsServings, true)
        // A guide or user conversion of pieces is never servings.
        XCTAssertFalse(FoodAmountServings.isServings(enteredUnit: .count, conversion: nil, sourceID: "cofid", basis: .per100Grams))
        XCTAssertFalse(FoodAmountServings.isServings(enteredUnit: .grams, conversion: nil, sourceID: nil, basis: .perServing(
            try PositiveQuantity(value: 30, unit: .grams))))
    }

    // MARK: Reuse only for the same record (review item 5)

    func testTheReusePathRequiresTheSameRecord() throws {
        let guides = try USDACountPortionGuides()
        let harness = try memoryHarness()
        let service = try confirmationService(harness, guides: guides)
        let saved = try service.save(try boiledEggs(guides: guides, code: Self.boiledLarge), operationID: LedgerFixtures.operationID(820))
        // The same code on another allow-listed record (USDA hard-boiled) with the same count.
        let usda = try usdaHardBoiled()
        let input = try PopulatedFoodConfirmation(evidence: saved.evidence + usda.evidence,
            sourceReleases: saved.sourceReleases + usda.releases.filter { release in
                !saved.sourceReleases.contains { $0.sourceReleaseID == release.sourceReleaseID } },
            candidates: [try XCTUnwrap(service.reopen(logItemID: saved.logItem.logItemID)).input.candidates[0], usda.candidate],
            expectedIdentity: usda.candidate.candidate.identity, expectedEdibleQuantity: usda.candidate.candidate.edibleQuantity)
        var state = FoodConfirmationState(input: input, reopened: saved)
        FoodConfirmationReducer.reduce(state: &state, action: .selectCandidate(1))
        FoodConfirmationReducer.reduce(state: &state, action: .setQuantity(3, .count))
        FoodConfirmationReducer.reduce(state: &state, action: .setPortionGuide(try LedgerText(Self.boiledLarge)))
        XCTAssertNotNil(try guides.guide(for: usda.candidate), "the USDA hard-boiled record has the boiled sizes")
        XCTAssertEqual(state.quantity.portionGuideCode?.value, Self.boiledLarge)
        XCTAssertTrue(CountPortionGuidePolicy.applies(state))
        XCTAssertEqual(state.selectedCandidate.candidate.recordID, usda.candidate.candidate.recordID)
        FoodConfirmationReducer.reduce(state: &state, action: .accept)
        let resaved = try service.save(state, operationID: LedgerFixtures.operationID(821))
        XCTAssertNotEqual(resaved.quantityConversion?.quantityConversionVersionID, saved.quantityConversion?.quantityConversionVersionID,
                          "another record resolves through the port and writes its own conversion")
        XCTAssertEqual(resaved.quantityConversion?.methodVersion.value, Self.boiledLarge)
    }

    // MARK: The method is an estimate on its own (review item 6)

    func testATypicalWeightEntryWithUnknownNutrientsIsStillAnEstimateOnItsRow() throws {
        let guides = try USDACountPortionGuides()
        let harness = try memoryHarness()
        let service = try confirmationService(harness, guides: guides)
        let saved = try service.save(try boiledEggs(guides: guides, code: Self.boiledLarge), operationID: LedgerFixtures.operationID(830))
        let unknown = try NutrientSet(entries: NutrientKey.allCases.map { try NutrientEntry(key: $0, value: .unknown(.notDeclared)) })
        var records = try (harness.committer as! any FoodArchiveLedgerAccess).archiveState().records
        records.resolutionVersions = try records.resolutionVersions.map {
            try NutritionResolutionVersion(resolutionVersionID: $0.resolutionVersionID, resolutionID: $0.resolutionID,
                ordinal: $0.ordinal, methodVersion: $0.methodVersion, sourceReleaseIDs: $0.sourceReleaseIDs, nutrients: unknown,
                decisionIDs: $0.decisionIDs, assertionIDs: $0.assertionIDs, createdAt: $0.createdAt)
        }
        let projection = try FoodIntakeProjection(records: records, reportingDate: saved.logItemVersion.reportingDate.value)
        let day = FoodLogDayContent(projection: projection, reportingDate: saved.logItemVersion.reportingDate.value, estimates: [])
        XCTAssertEqual(day.entries.first?.isEstimate, true, "the typical weight alone makes the row an estimate")
    }

    // MARK: 6. Archive export and import

    func testAnArchiveRoundTripKeepsTheCodeReleaseAndSize() throws {
        let guides = try USDACountPortionGuides()
        let harness = try memoryHarness()
        let service = try confirmationService(harness, guides: guides)
        let medium = "count_portion_guide_v1:usda_sr_legacy_boiled_from_171287_88378"
        let saved = try service.save(try boiledEggs(guides: guides, code: medium), operationID: LedgerFixtures.operationID(840))
        let bundle = try FoodArchiveGenerator().generate(state: (harness.committer as! any FoodArchiveLedgerAccess).archiveState(), ledgerID: LedgerText("guide-archive"),
            createdAt: LedgerFixtures.date, creatingActorID: LedgerFixtures.id(900, ActorTag.self))
        _ = try FoodArchiveVerifier().verify(bundle)
        for destination in try LedgerFixtures.harnesses() {
            defer { destination.cleanup() }
            let live = try XCTUnwrap(destination.committer as? any FoodArchiveLedgerAccess)
            let importer = FoodArchiveImportService(live: live, staging: InMemoryFoodArchiveStaging())
            _ = try importer.apply(importer.dryRun(bundle))
            let records = try live.archiveState().records
            let conversion = try XCTUnwrap(records.quantityConversions.first)
            XCTAssertEqual(conversion, saved.quantityConversion, destination.name)
            XCTAssertNotNil(records.sourceReleases.first { $0.sourceReleaseID == guides.sourceRelease.sourceReleaseID }, destination.name)
            XCTAssertEqual(FoodQuantityMethod.of(conversion), .typicalWeight(size: .medium, gramsEach: 44))
            let restoredService = FoodConfirmationService(ledger: try LedgerFixtures.service(destination.committer), reader: destination.reader,
                clock: LedgerFixtures.clock, ids: FollowUpIDs(seed: 20_000), digester: SHA256Digester(), portionGuides: guides)
            let reopened = try XCTUnwrap(restoredService.reopen(logItemID: saved.logItem.logItemID))
            XCTAssertEqual(reopened.quantity.portionGuideCode?.value, medium, destination.name)
        }
    }

    // MARK: 9. A whole-milk volume day under v6

    func testAWholeMilkVolumeDaySetsIncludesEstimatesUnderV6() throws {
        let harness = try memoryHarness()
        let service = try confirmationService(harness, guides: nil)
        let milk = try CoFIDWholeMilkVolumeConversion()
        let search = try CoFIDGenericFoodSearch(ids: FollowUpIDs(seed: 30_000))
        let request = GenericFoodSearchRequest(text: try LedgerText("whole milk"), identity: GenericFoodIdentityQuery(),
                                               capturedAt: LedgerFixtures.date, locale: try LedgerText("en_GB"))
        guard case let .confirmation(route) = try search.search(request),
              let candidate = route.matches.map(\.candidate).first(where: milk.applies(to:)) else {
            return XCTFail("Expected the CoFID whole milk record")
        }
        let input = try PopulatedFoodConfirmation(evidence: route.confirmation.evidence,
            sourceReleases: route.confirmation.sourceReleases + [milk.sourceRelease], candidates: [candidate],
            expectedIdentity: candidate.candidate.identity, expectedEdibleQuantity: candidate.candidate.edibleQuantity)
        var state = FoodConfirmationState(input: input, prefillSourceQuantity: false)
        FoodConfirmationReducer.reduce(state: &state, action: .setQuantity(200, .millilitres))
        let volume = try PositiveQuantity(value: 200, unit: .millilitres)
        FoodConfirmationReducer.reduce(state: &state, action: .setConversion(try milk.offer(for: candidate, original: volume)))
        state.answerPendingDifferences()
        FoodConfirmationReducer.reduce(state: &state, action: .accept)
        let saved = try service.save(state, operationID: LedgerFixtures.operationID(850))
        let records = try (harness.committer as! any FoodArchiveLedgerAccess).archiveState().records
        let projection = try FoodIntakeProjection(records: records, reportingDate: saved.logItemVersion.reportingDate.value)
        XCTAssertEqual(projection.summary.totals.first { $0.key == .energyConsumed }?.includesEstimates, true)
        XCTAssertEqual(projection.rows.first?.quantityMethod, .wholeMilkVolume)
        let document = try FoodDailyExportBuilder.make(FoodDailyExportRequest(records: records,
            reportDate: saved.logItemVersion.reportingDate.value, timeZone: TimeZone(identifier: "Europe/London")!,
            dataAsOf: LedgerFixtures.date.addingTimeInterval(86_400), exportedAt: LedgerFixtures.date.addingTimeInterval(86_400),
            appContext: FoodDailyExportAppContext(appVersion: "1.0", appBuild: "1")))
        XCTAssertEqual(document.summaryVersion, "food-intake-summary-v6")
        XCTAssertEqual(document.summary.first { $0.key == "energy_consumed" }?.includesEstimates, true)
    }

    // MARK: 10. Cross-surface fixture

    func testOneGuideEntryReadsTheSameOnEverySurface() throws {
        let guides = try USDACountPortionGuides()
        let harness = try memoryHarness()
        let service = try confirmationService(harness, guides: guides)
        let saved = try service.save(try boiledEggs(guides: guides, code: Self.boiledLarge), operationID: LedgerFixtures.operationID(860))
        let reading = try readingService(harness, confirmations: service)
        let detail = try XCTUnwrap(reading.savedEntry(saved.logItem.logItemID))
        let entry = try XCTUnwrap(reading.day(reportingDate: saved.logItemVersion.reportingDate.value).entries.first)
        let recent = try XCTUnwrap(FoodRecentItemsService(reader: harness.reader, confirmations: service)
            .items(records: (harness.committer as! any FoodArchiveLedgerAccess).archiveState().records, now: LedgerFixtures.date, calendar: QuickAddFixtures.london).first)
        let typical = FoodQuantityMethod.typicalWeight(size: .large, gramsEach: 50)
        XCTAssertEqual(detail.quantityMethod, typical)
        XCTAssertEqual(entry.quantityMethod, typical)
        XCTAssertTrue(detail.weightIsEstimated)
        XCTAssertTrue(entry.isEstimate)
        XCTAssertTrue(recent.isEstimate)
        XCTAssertEqual(detail.enteredAmount, entry.enteredAmount)
        XCTAssertEqual(detail.edibleQuantity, entry.quantity)
        XCTAssertEqual(recent.item.lastAmount, try PositiveQuantity(value: 3, unit: .count))
        XCTAssertFalse(recent.item.lastAmountIsServings)
        let document = try FoodDailyExportBuilder.make(FoodDailyExportRequest(records: (harness.committer as! any FoodArchiveLedgerAccess).archiveState().records,
            reportDate: saved.logItemVersion.reportingDate.value, timeZone: TimeZone(identifier: "Europe/London")!,
            dataAsOf: LedgerFixtures.date.addingTimeInterval(86_400), exportedAt: LedgerFixtures.date.addingTimeInterval(86_400),
            appContext: FoodDailyExportAppContext(appVersion: "1.0", appBuild: "1")))
        XCTAssertEqual(document.summary.first { $0.key == "energy_consumed" }?.includesEstimates, true, "the v6 summary flag")
    }

    // MARK: 15. Retry recovery, removal and restoration

    func testRetryRemovalAndRestorationKeepTheGuideConversion() throws {
        let guides = try USDACountPortionGuides()
        let harness = try memoryHarness()
        let service = try confirmationService(harness, guides: guides)
        let state = try boiledEggs(guides: guides, code: Self.boiledLarge)
        let operation = try LedgerFixtures.operationID(870)
        let key = try LedgerText("guide-retry")
        let saved = try service.save(state, operationID: operation, idempotencyKey: key)
        let retried = try service.save(state, operationID: operation, idempotencyKey: key)
        XCTAssertEqual(retried.quantityConversion, saved.quantityConversion, "retry recovery returns the stored conversion")
        let management = FoodLogManagementService(ledger: try LedgerFixtures.service(harness.committer),
            reader: ArchiveFoodLogHistoryReader(archive: (harness.committer as! any FoodArchiveLedgerAccess)), clock: LedgerFixtures.clock, ids: FollowUpIDs(seed: 40_000))
        let removed = try management.remove(logItemID: saved.logItem.logItemID, expectedVersion: saved.logItemVersion.logItemVersionID,
                                            reason: LedgerText("Logged twice"), operationID: LedgerFixtures.operationID(871))
        XCTAssertEqual(removed.quantityConversionVersionID, saved.quantityConversion?.quantityConversionVersionID)
        let restored = try management.restore(logItemID: saved.logItem.logItemID, expectedVersion: removed.logItemVersionID,
                                              reason: LedgerText("Logged after all"), operationID: LedgerFixtures.operationID(872))
        XCTAssertEqual(restored.quantityConversionVersionID, saved.quantityConversion?.quantityConversionVersionID)
        let reopened = try XCTUnwrap(service.reopen(logItemID: saved.logItem.logItemID))
        XCTAssertEqual(reopened.quantity.portionGuideCode?.value, Self.boiledLarge)
    }

    // MARK: - Fixtures

    private func memoryHarness() throws -> TestHarness {
        let memory = InMemoryFoodLedgerStore(encoder: LedgerFixtures.encoder, digester: LedgerFixtures.digester)
        return TestHarness(name: "memory", committer: memory, reader: memory, cleanup: {})
    }

    private func confirmationService(_ harness: TestHarness, guides: (any FoodEdibleWeightGuideProviding)?) throws -> FoodConfirmationService {
        FoodConfirmationService(ledger: try LedgerFixtures.service(harness.committer), reader: harness.reader, clock: LedgerFixtures.clock,
                                ids: FollowUpIDs(), digester: SHA256Digester(), calendar: QuickAddFixtures.london,
                                pastedLabelConversions: GoldenPastedLabelConversions(), portionGuides: guides)
    }

    private func readingService(_ harness: TestHarness, confirmations: FoodConfirmationService) throws -> FoodLogReadingService {
        FoodLogReadingService(ledger: try LedgerFixtures.service(harness.committer), archive: (harness.committer as! any FoodArchiveLedgerAccess),
            confirmationReader: harness.reader, history: ArchiveFoodLogHistoryReader(archive: (harness.committer as! any FoodArchiveLedgerAccess)),
            confirmations: confirmations, clock: LedgerFixtures.clock, ids: FollowUpIDs(seed: 50_000))
    }

    private func eggRoute(name: String) throws -> (candidate: PopulatedFoodCandidate, evidence: [CaptureEvidence], releases: [SourceRelease]) {
        let search = try CoFIDGenericFoodSearch(ids: FollowUpIDs(seed: 60_000))
        let request = GenericFoodSearchRequest(text: try LedgerText(name.replacingOccurrences(of: ",", with: "")),
                                               identity: GenericFoodIdentityQuery(),
                                               capturedAt: LedgerFixtures.date, locale: try LedgerText("en_GB"))
        guard case let .confirmation(route) = try search.search(request),
              let egg = route.matches.first(where: { $0.candidate.name.value == name })?.candidate else {
            throw FoodLedgerValidationError.invalidProvenance
        }
        return (egg, route.confirmation.evidence, route.confirmation.sourceReleases)
    }

    private func usdaHardBoiled() throws -> (candidate: PopulatedFoodCandidate, evidence: [CaptureEvidence], releases: [SourceRelease]) {
        let search = try USDAGenericFoodSearch(ids: FollowUpIDs(seed: 70_000))
        for text in ["egg whole cooked hard-boiled", "hard boiled egg", "egg hard-boiled"] {
            let request = GenericFoodSearchRequest(text: try LedgerText(text), identity: GenericFoodIdentityQuery(),
                                                   capturedAt: LedgerFixtures.date, locale: try LedgerText("en_GB"))
            if case let .confirmation(route) = try search.search(request),
               let egg = route.matches.first(where: { $0.candidate.candidate.recordID.value.hasSuffix(":fdc:173424") })?.candidate {
                return (egg, route.confirmation.evidence, route.confirmation.sourceReleases)
            }
        }
        // Never a skip: the USDA allow-list fix must be exercised.
        XCTFail("Expected the USDA hard-boiled egg record")
        throw FoodLedgerValidationError.invalidProvenance
    }

    private func boiledEggs(guides: USDACountPortionGuides, code: String) throws -> FoodConfirmationState {
        let route = try eggRoute(name: "Eggs, chicken, whole, boiled")
        let input = try PopulatedFoodConfirmation(evidence: route.evidence, sourceReleases: route.releases + [guides.sourceRelease],
            candidates: [route.candidate], expectedIdentity: route.candidate.candidate.identity,
            expectedEdibleQuantity: route.candidate.candidate.edibleQuantity)
        var state = FoodConfirmationState(input: input, prefillSourceQuantity: false)
        FoodConfirmationReducer.reduce(state: &state, action: .setQuantity(3, .count))
        FoodConfirmationReducer.reduce(state: &state, action: .setPortionGuide(try LedgerText(code)))
        FoodConfirmationReducer.reduce(state: &state, action: .accept)
        return state
    }
}

private final class FollowUpIDs: LedgerIDGenerating, @unchecked Sendable {
    private let lock = NSLock()
    private var value: Int
    init(seed: Int = 10_000) { value = seed }
    func makeID<Tag>(_ tag: Tag.Type) throws -> LedgerID<Tag> {
        lock.lock()
        defer { lock.unlock() }
        value += 1
        return try LedgerID(String(format: "00000000-0000-0000-0000-%012x", value))
    }
}
