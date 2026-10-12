import FoodLedgerApplication
import FoodLedgerDomain
import FoodLedgerPresentation
import FoodLedgerTestSupport
import SwiftUI
import XCTest

@MainActor
final class FoodListImportPresentationTests: XCTestCase {
    /// #222: a pasted numeral that could mean two amounts in the reader's locale is never
    /// proposed as a number; the line has no amount, says why, and the needs-amount rule applies.
    func testPastedAmountsFollowTheReadersDecimalConvention() throws {
        let cases: [(String, String, String, Bool)] = [
            ("de_DE", "1.500 g rice", "", true),      // German grouping for 1500, or 1.5
            ("fr_FR", "1 500 g rice", "", false),     // space grouping: the parse has no amount
            ("fr_FR", "1\u{202F}500 g rice", "", false),
            ("en_GB", "1,5 g rice", "", true),        // a decimal comma is not English
            ("de_DE", "1,5 g rice", "1.5", false),
            ("en_GB", "1.500 g rice", "1.5", false),
            ("en_GB", "1,500 g rice", "", false),     // the parse leaves it as an ambiguous number
            ("de_DE", "1.500 kg rice", "", true),
            ("de_DE", "rice 1.500 g", "", true),
            ("de_DE", "10 g rice", "10.0", false),
            ("de_DE", "half pepper", "0.5", false),
            ("de_DE", "½ pepper", "0.5", false),
            ("de_DE", "1/2 orange pepper", "0.5", false),
            ("de_DE", ".5 l milk", "500.0", false),
            ("de_DE", "0.5 bell pepper", "0.5", false)
        ]
        for (identifier, text, quantityText, explained) in cases {
            let (model, _) = try listModel(locale: Locale(identifier: identifier))
            model.input = text
            model.prepare()
            let draft = try XCTUnwrap(model.rows.first?.draft, text)
            XCTAssertEqual(draft.quantityText, quantityText, "\(identifier) \(text)")
            XCTAssertEqual(FoodListAmountText.showsAmbiguousNumeral(draft, locale: model.amountLocale), explained, "\(identifier) \(text)")
            XCTAssertEqual(try FoodListParser.parse(text).first, draft.parsed, "the versioned parse is unchanged")
        }
        // Once the user types an amount, it is theirs; the explanation goes.
        let (model, _) = try listModel(locale: Locale(identifier: "de_DE"))
        model.input = "1.500 g rice"
        model.prepare()
        var draft = try XCTUnwrap(model.selectedRow?.draft)
        draft.quantityText = "1500"
        model.edit(draft)
        XCTAssertFalse(FoodListAmountText.showsAmbiguousNumeral(try XCTUnwrap(model.selectedRow?.draft), locale: model.amountLocale))
    }

    /// A queue saved before #222, or in another locale, gets the same check on restore for lines
    /// never edited; an edited amount is the user's. The explanation survives a relaunch, even
    /// in a locale where the numeral would not have been ambiguous.
    func testRestoredQueueWithholdsUntouchedAmbiguousAmountsAndKeepsTheNotice() throws {
        let checkpoint = MemoryCheckpoint()
        let make = { (identifier: String) in
            FoodListImportViewModel(service: FoodListImportService(searcher: ListSearch()), locale: try LedgerText(identifier),
                                    ids: ListIDs(), checkpointStore: checkpoint,
                                    amountLocale: Locale(identifier: identifier)) { _, _ in throw FoodLedgerValidationError.invalidProvenance }
        }
        let english = try make("en_GB")
        english.input = "1.500 g rice\n1.500 g oats\n10 g fixture"
        english.prepare()
        XCTAssertEqual(english.rows.map(\.draft.quantityText), ["1.5", "1.5", "10.0"], "unambiguous in English")
        var edited = english.rows[1].draft
        edited.quantityText = "2"
        english.edit(edited)

        let german = try make("de_DE")
        XCTAssertEqual(german.rows.map(\.draft.quantityText), ["", "2", "10.0"])
        XCTAssertTrue(FoodListAmountText.showsAmbiguousNumeral(german.rows[0].draft, locale: german.amountLocale))
        XCTAssertFalse(FoodListAmountText.showsAmbiguousNumeral(german.rows[1].draft, locale: german.amountLocale))
        german.retryCheckpoint() // persists the restored queue

        let relaunched = try make("en_GB")
        XCTAssertEqual(relaunched.rows.map(\.draft.quantityText), ["", "2", "10.0"])
        XCTAssertTrue(FoodListAmountText.showsAmbiguousNumeral(relaunched.rows[0].draft, locale: relaunched.amountLocale),
                      "the withheld line still says why after a relaunch")
    }

    /// A withheld amount reaches Confirm as no amount, never as 1.5.
    func testWithheldAmbiguousAmountReachesConfirmWithoutAValue() throws {
        let (model, search) = try listModel(locale: Locale(identifier: "de_DE"))
        model.input = "1.500 g fixture"
        model.prepare()
        model.search()
        XCTAssertEqual(search.calls, 1)
        model.review(candidate: 0)
        let confirmation = try XCTUnwrap(model.confirmation)
        XCTAssertNil(confirmation.state.quantity.value)
        XCTAssertEqual(confirmation.state.quantity.unit, .grams)
    }

    func testCommonFoodAddsToExistingReviewWithoutSavingOrSearching() throws {
        let (model, store, search) = try fixture()
        model.input = "10 g fixture"
        model.prepare()
        let original = model.rows[0].id
        model.deferLine()
        try model.addCommonFood(name: "fixture", portion: InventoryAmount(value: 25, unit: .grams))
        XCTAssertEqual(model.rows.count, 2)
        XCTAssertEqual(model.rows[0].id, original)
        XCTAssertEqual(model.rows[0].status, .deferred)
        XCTAssertEqual(model.selectedRow?.draft.quantityText, "25.0")
        XCTAssertEqual(model.selectedRow?.draft.unit, .grams)
        XCTAssertEqual(search.calls, 0)
        XCTAssertEqual(try store.counts().operations, 0)
        XCTAssertThrowsError(try model.addCommonFood(name: "oats\nmilk", portion: nil))
    }

    func testResumeRestoresQueueAndReconcilesCommittedSave() throws {
        let checkpointStore = MemoryCheckpoint()
        let (fixture, _, search) = try fixture()
        let ids = ListIDs()
        let model = FoodListImportViewModel(service: FoodListImportService(searcher: search), locale: try LedgerText("en_GB"), ids: ids,
            checkpointStore: checkpointStore) { _, _ in throw FoodLedgerValidationError.invalidProvenance }
        model.input = "10 g fixture\n20 g fixture"
        model.prepare()
        let first = model.rows[0].id
        let second = model.rows[1].id
        model.deferLine()
        var draft = try XCTUnwrap(model.selectedRow?.draft)
        draft.quantityText = "30"
        model.edit(draft)
        let logID = try LogItemID("00000000-0000-0000-0000-000000000999")
        let resumed = FoodListImportViewModel(service: FoodListImportService(searcher: search), locale: try LedgerText("en_GB"), ids: ids,
            checkpointStore: checkpointStore, recoveredLogItemID: { $0 == second ? logID : nil }) { _, _ in throw FoodLedgerValidationError.invalidProvenance }
        XCTAssertEqual(resumed.rows[0].id, first)
        XCTAssertEqual(resumed.rows[0].status, .deferred)
        XCTAssertEqual(resumed.rows[1].status, .saved(logID))
        XCTAssertEqual(resumed.rows[1].draft.quantityText, "30")
        XCTAssertEqual(resumed.selectedID, second)
        resumed.search()
        XCTAssertEqual(search.calls, 0)
        _ = fixture
    }

    func testCheckpointFailureKeepsQuickAddVisibleAndRetriesSameRow() throws {
        let checkpointStore = MemoryCheckpoint()
        let (_, _, search) = try fixture()
        let model = FoodListImportViewModel(service: FoodListImportService(searcher: search), locale: try LedgerText("en_GB"), ids: ListIDs(),
            checkpointStore: checkpointStore) { _, _ in throw FoodLedgerValidationError.invalidProvenance }
        checkpointStore.failWrites = true
        try model.addCommonFood(name: "fixture", portion: InventoryAmount(value: 25, unit: .grams))
        let rowID = try XCTUnwrap(model.selectedID)
        XCTAssertEqual(model.rows.count, 1)
        XCTAssertNotNil(model.checkpointErrorMessage)
        XCTAssertNil(try checkpointStore.load())
        checkpointStore.failWrites = false
        model.retryCheckpoint()
        XCTAssertNil(model.checkpointErrorMessage)
        XCTAssertEqual(try checkpointStore.load()?.drafts.map(\.id), [rowID])
    }

    func testUnavailableCheckpointCanResumeAfterRetryWithoutOverwriting() throws {
        let checkpoint = MemoryCheckpoint()
        let (_, _, search) = try fixture()
        let ids = ListIDs()
        let make = {
            FoodListImportViewModel(service: FoodListImportService(searcher: search), locale: try LedgerText("en_GB"), ids: ids,
                checkpointStore: checkpoint) { _, _ in throw FoodLedgerValidationError.invalidProvenance }
        }
        let original = try make()
        original.input = "25 g fixture"; original.prepare()
        let rowID = original.rows.first?.id
        checkpoint.failReads = true
        let resumed = try make()
        XCTAssertNotNil(resumed.checkpointErrorMessage)
        resumed.input = "Must not overwrite saved queue"
        checkpoint.failReads = false
        resumed.retryCheckpoint()
        XCTAssertNil(resumed.checkpointErrorMessage)
        XCTAssertEqual(resumed.input, "25 g fixture")
        XCTAssertEqual(resumed.rows.first?.id, rowID)
    }

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

    func testReviewedSpeechAppendsWithoutParsingSearchingOrSaving() throws {
        let (model, store, search) = try fixture()
        model.input = "25 g fixture"
        XCTAssertTrue(model.appendReviewedSpeech("125 ml milk"))
        XCTAssertEqual(model.input, "25 g fixture\n125 ml milk")
        XCTAssertEqual(model.inputMethod, .reviewedSpeechText)
        XCTAssertTrue(model.rows.isEmpty)
        XCTAssertEqual(search.calls, 0)
        XCTAssertEqual(try store.counts().operations, 0)
        XCTAssertFalse(model.appendReviewedSpeech(String(repeating: "x", count: 30_001)))
        model.prepare()
        XCTAssertEqual(model.rows.map(\.draft.inputMethod), [.reviewedSpeechText, .reviewedSpeechText])
        model.search()
        XCTAssertEqual(search.lastEvidence?.captureMethod.value, "reviewed_food_text_with_on_device_speech")
        XCTAssertEqual(search.lastEvidence?.kind, .manual)
        XCTAssertEqual(try store.counts().operations, 0)
        XCTAssertFalse(model.appendReviewedSpeech("late text"))
        model.startNewList()
        XCTAssertEqual(model.inputMethod, .pastedOrTyped)
    }

    private func listModel(locale: Locale) throws -> (FoodListImportViewModel, ListSearch) {
        let search = ListSearch()
        let model = FoodListImportViewModel(
            service: FoodListImportService(searcher: search), locale: try LedgerText(locale.identifier), ids: ListIDs(),
            amountLocale: locale
        ) { _, _ in throw FoodLedgerValidationError.invalidProvenance }
        return (model, search)
    }

    private func fixture() throws -> (FoodListImportViewModel, InMemoryFoodLedgerStore, ListSearch) {
        let ids = ListIDs()
        let store = InMemoryFoodLedgerStore()
        let ledger = FoodLedgerService(
            actorID: try ids.makeID(ActorTag.self), committer: store, clock: ListClock(),
            encoder: FoundationCanonicalJSONEncoder(), digester: SHA256Digester()
        )
        let confirmations = FoodConfirmationService(ledger: ledger, reader: store, clock: ListClock(), ids: ids, digester: SHA256Digester())
        let search = ListSearch()
        return (FoodListImportViewModel(
            service: FoodListImportService(searcher: search), locale: try LedgerText("en_GB"), ids: ids,
            now: { ListClock().now() }
        ) { state, operationID in
            try confirmations.save(state, operationID: operationID, idempotencyKey: LedgerText(operationID.rawValue))
        }, store, search)
    }
}

private final class MemoryCheckpoint: FoodListCheckpointStoring, @unchecked Sendable {
    private var value: FoodListCheckpoint?
    var failWrites = false
    var failReads = false
    func load() throws -> FoodListCheckpoint? {
        if failReads { throw FoodLedgerValidationError.invalidProvenance }
        return value
    }
    func save(_ checkpoint: FoodListCheckpoint) throws {
        if failWrites { throw FoodLedgerValidationError.invalidProvenance }
        try checkpoint.validate(); value = checkpoint
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
    var lastEvidence: CaptureEvidence?
    var returnsNoResult = false
    func search(_ request: GenericFoodSearchRequest) throws -> GenericFoodSearchOutcome {
        calls += 1
        let evidence = try XCTUnwrap(request.captureEvidence)
        lastEvidence = evidence
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
