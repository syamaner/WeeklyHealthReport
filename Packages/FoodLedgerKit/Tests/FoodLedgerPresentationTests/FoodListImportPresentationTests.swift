import FoodLedgerApplication
import FoodLedgerDomain
import FoodLedgerPresentation
import FoodLedgerTestSupport
import SwiftUI
import XCTest

@MainActor
final class FoodListImportPresentationTests: XCTestCase {
    func testDuplicateLinesSaveIndependentlyAndRetryDoesNotDuplicate() throws {
        let (model, store, search) = try fixture()
        model.input = "25 g fixture\n\n25 g fixture\nunknown product"
        model.prepare()
        XCTAssertEqual(model.rows.count, 3)
        XCTAssertEqual(model.rows.map { $0.draft.parsed.lineNumber }, [1, 3, 4])
        XCTAssertNotEqual(model.rows[0].id, model.rows[1].id)
        let firstID = model.rows[0].id
        model.search()
        model.review(candidate: 0)
        let review = try XCTUnwrap(model.confirmation)
        XCTAssertEqual(review.state.decision, .undecided)
        review.save()
        XCTAssertEqual(model.savedCount, 0)
        guard case .failed = model.rows[0].status else { return XCTFail("Missing failed row") }
        review.send(.accept)
        review.save()
        review.save()
        XCTAssertEqual(model.savedCount, 1)
        XCTAssertEqual(try store.counts().logItemVersions, 1)
        model.finishReview()
        XCTAssertEqual(model.selectedID, model.rows[1].id)
        model.search()
        model.review(candidate: 0)
        model.confirmation?.send(.accept)
        model.confirmation?.save()
        model.finishReview()
        XCTAssertEqual(model.savedCount, 2)
        XCTAssertEqual(try store.counts().logItemVersions, 2)
        XCTAssertEqual(model.progress, "2 of 3 saved · 1 not saved")
        model.deferLine()
        XCTAssertFalse(model.progress.contains("All"))
        model.select(firstID)
        let callCount = search.calls
        model.search()
        model.review(candidate: 0)
        XCTAssertNil(model.confirmation)
        XCTAssertEqual(search.calls, callCount)
        XCTAssertEqual(try store.counts().logItemVersions, 2)
    }

    func testEditsInvalidateCandidatesAndNoResultAndDeclineRemainVisible() throws {
        let (model, store, search) = try fixture()
        model.input = "fixture\n40 g fixture"
        model.prepare()
        model.search()
        model.review(candidate: 0)
        XCTAssertNil(model.confirmation?.state.quantity.value)
        model.finishReview()
        var draft = try XCTUnwrap(model.selectedRow?.draft)
        draft.query = "corrected food"
        model.edit(draft)
        XCTAssertNil(model.selectedRow?.route)
        model.review(candidate: 0)
        XCTAssertNil(model.confirmation)
        search.returnsNoResult = true
        model.search()
        guard case .unresolved = model.selectedRow?.status else { return XCTFail("Missing unresolved row") }
        model.declineLine()
        XCTAssertEqual(model.rows[0].status, .declined)
        XCTAssertEqual(model.selectedID, model.rows[1].id)
        XCTAssertEqual(try store.counts().operations, 0)
        let originalRows = model.rows.map(\.id)
        model.input = "new list"
        model.prepare()
        XCTAssertEqual(model.rows.map(\.id), originalRows)
        model.startNewList()
        XCTAssertTrue(model.rows.isEmpty)
    }

    func testEmptyAndOversizedInputAreRecoverableAndViewSupportsLargeText() throws {
        let (model, _, _) = try fixture()
        model.prepare()
        XCTAssertNotNil(model.errorMessage)
        model.input = String(repeating: "x", count: 30_001)
        model.prepare()
        XCTAssertTrue(model.rows.isEmpty)
        XCTAssertEqual(model.input.count, 30_001)
        let view = FoodListImportView(model: model).environment(\.dynamicTypeSize, .accessibility5)
        XCTAssertFalse(String(describing: view).isEmpty)
    }

    func testContextIsVisibleExcludedFromFoodCountAndCanBeCorrected() throws {
        let (model, _, _) = try fixture()
        model.input = "Lunch:\n13:45\n40 g fixture\n£8.70"
        model.prepare()
        XCTAssertEqual(model.rows.count, 4)
        XCTAssertEqual(model.selectedID, model.rows[2].id)
        XCTAssertEqual(model.progress, "0 of 1 saved · 1 not saved · 3 context lines")
        model.select(model.rows[0].id)
        model.reviewContextAsFood()
        XCTAssertEqual(model.rows[0].status, .pending)
        XCTAssertEqual(model.progress, "0 of 2 saved · 2 not saved · 2 context lines")
    }

    private func fixture() throws -> (FoodListImportViewModel, InMemoryFoodLedgerStore, ListSearch) {
        let ids = ListIDs()
        let store = InMemoryFoodLedgerStore()
        let ledger = FoodLedgerService(
            actorID: try ids.makeID(ActorTag.self), committer: store, clock: ListClock(),
            encoder: FoundationCanonicalJSONEncoder(), digester: SHA256Digester()
        )
        let confirmations = FoodConfirmationService(ledger: ledger, reader: store, clock: ListClock(), ids: ids)
        let search = ListSearch()
        return (FoodListImportViewModel(
            service: FoodListImportService(searcher: search), locale: try LedgerText("en_GB"), ids: ids,
            now: { ListClock().now() }
        ) { state, operationID in
            try confirmations.save(state, operationID: operationID, idempotencyKey: LedgerText(operationID.rawValue))
        }, store, search)
    }
}

private struct ListClock: LedgerClock {
    func now() -> Date { Date(timeIntervalSince1970: 1_700_000_000) }
}

private final class ListIDs: LedgerIDGenerating, @unchecked Sendable {
    private var counter = 0
    func makeID<Tag>(_ tag: Tag.Type) throws -> LedgerID<Tag> {
        counter += 1
        return try LedgerID(String(format: "00000000-0000-0000-0000-%012x", counter))
    }
}

private final class ListSearch: GenericFoodSearching, @unchecked Sendable {
    var calls = 0
    var returnsNoResult = false
    func search(_ request: GenericFoodSearchRequest) throws -> GenericFoodSearchOutcome {
        calls += 1
        let evidence = try XCTUnwrap(request.captureEvidence)
        if returnsNoResult { return .noResult(GenericFoodNoResultRoute(evidence: evidence)) }
        let release = SourceRelease(
            sourceReleaseID: try ExternalIdentifier("fixture"), sourceID: try ExternalIdentifier("fixture"),
            releasedAt: ListClock().now(), artifactHash: try SHA256Digest(String(repeating: "a", count: 64)),
            schemaVersion: try LedgerText("1"), pipelineVersion: try LedgerText("1"),
            licence: try LedgerText("synthetic"), attribution: try LedgerText("synthetic"),
            manifestHash: try SHA256Digest(String(repeating: "b", count: 64))
        )
        let identity = try DecisiveIdentity(
            preparation: PreparationState(kind: .asSold), bone: .notApplicable, skin: .notApplicable,
            drained: .notApplicable, packingMedium: .named(LedgerText("none")),
            fortification: .unfortified, servingBasis: .per100Grams
        )
        let candidate = try PopulatedFoodCandidate(
            candidate: ProviderNeutralCandidate(
                sourceReleaseID: release.sourceReleaseID, recordID: ExternalIdentifier("fixture"),
                identity: identity, edibleQuantity: .known(PositiveQuantity(value: 100, unit: .grams), conversionVersionID: nil),
                nutrients: NutrientSet(entries: NutrientKey.allCases.map { try NutrientEntry(key: $0, value: .unknown(.notDeclared)) }),
                evidenceIDs: [evidence.evidenceID]
            ), name: LedgerText("fixture"), itemClass: .food
        )
        return .confirmation(GenericFoodConfirmationRoute(
            confirmation: try PopulatedFoodConfirmation(
                evidence: [evidence], sourceReleases: [release], candidates: [candidate],
                expectedIdentity: identity, expectedEdibleQuantity: candidate.candidate.edibleQuantity
            ), matches: [GenericFoodMatch(candidate: candidate, isExactName: true)]
        ))
    }
}
