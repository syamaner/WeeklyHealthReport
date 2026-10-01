import Foundation
import FoodGenericSearch
import FoodLedgerApplication
import FoodLedgerDomain
import FoodLedgerPresentation
import FoodLedgerTestSupport
import XCTest

@MainActor
final class SearchQuantityHandoffTests: XCTestCase {
    private func model() throws -> GenericFoodSearchViewModel {
        let ids = HandoffIDs()
        return try GenericFoodSearchViewModel(searcher: CompositeGenericFoodSearch(sources: [
            CoFIDGenericFoodSearch(ids: ids), USDAGenericFoodSearch(ids: ids)], ids: ids), locale: LedgerText("en_GB"))
    }
    func testRealSearchSelectionHandoffPrefillsEditableExactUnitsWithoutSaving() throws {
        for (query, amount, unit) in [("200g Greek yoghurt 10% fat", 200.0, QuantityUnit.grams),
            ("0.25kg rice", 250.0, .grams), ("200ml milk", 200.0, .millilitres), ("2 eggs", 2.0, .count)] {
            let search = try model(); search.query = query; search.search()
            guard case let .results(route) = search.phase else { return XCTFail(query) }
            // Exercise a non-first candidate as the native choose-and-review action does.
            let index = min(1,route.matches.count-1)
            let input = try XCTUnwrap(search.confirmation(at: index))
            XCTAssertEqual(input.candidates[0],route.matches[index].candidate)
            XCTAssertEqual(input.evidence.first?.originalPayload,.text(try LedgerText(query)))
            var saves = 0
            let confirmation = FoodConfirmationViewModel(
                state: FoodConfirmationState(input: input, queryQuantity: search.parsedQuery?.quantity)) { _ in
                saves += 1; throw CocoaError(.fileWriteUnknown)
            }
            XCTAssertEqual(confirmation.state.quantity.value, amount)
            XCTAssertEqual(confirmation.state.quantity.unit, unit)
            XCTAssertNil(confirmation.state.quantity.conversion)
            if unit == .millilitres && input.candidates[0].candidate.identity.servingBasis == .per100Grams {
                XCTAssertTrue(try XCTUnwrap(confirmation.quantityBasisWarning).contains("no density is inferred"))
            }
            XCTAssertEqual(confirmation.state.decision, .undecided)
            XCTAssertEqual(confirmation.state.phase, .editing)
            // View construction and candidate switches retain the owned confirmation model and edits.
            _ = FoodConfirmationView(model: confirmation, leave: {})
            confirmation.send(.setQuantity(amount+1, unit))
            confirmation.send(.selectCandidate(min(1,input.candidates.count-1)))
            _ = FoodConfirmationView(model: confirmation, leave: {})
            XCTAssertEqual(confirmation.state.quantity.value, amount+1)
            XCTAssertEqual(saves,0)
            if unit == .count {
                XCTAssertThrowsError(try FoodQuantityCalculator.direct(entered: PositiveQuantity(value: amount, unit: unit),conversion:nil))
            }
            XCTAssertNil(search.confirmation(at: -1)); XCTAssertNil(search.confirmation(at: route.matches.count))
        }
    }
    func testQueryAndPreparationEditsInvalidateSelectionAndHints() throws {
        let search = try model()
        search.query = "100g rice"; search.search()
        XCTAssertNotNil(search.confirmation(at: 0))
        let original = try XCTUnwrap(search.confirmation(at: 0))
        search.query = "200ml milk"
        XCTAssertEqual(search.phase, .idle)
        XCTAssertNil(search.parsedQuery)
        XCTAssertNil(search.confirmation(at: 0))
        // The previously opened confirmation remains an immutable rice snapshot.
        XCTAssertEqual(original.evidence.first?.originalPayload, .text(try LedgerText("100g rice")))
        search.search()
        XCTAssertEqual(search.parsedQuery?.quantity?.value, 200)
        XCTAssertNotNil(search.confirmation(at: 0))
        search.preparationFilter = .raw
        XCTAssertEqual(search.phase, .idle)
        XCTAssertNil(search.confirmation(at: 0))
        search.query = "dragonfruit"; search.search()
        guard case let .noResult(route) = search.phase else { return XCTFail("expected miss") }
        search.query = "milk"
        search.searchSuggestion(route.suggestedQueries.first ?? "rice", from: route)
        XCTAssertEqual(search.query, "milk")
        XCTAssertEqual(search.phase, .idle)
        search.query = "<100g rice"; search.search()
        XCTAssertNotNil(search.parsedQuery)
        search.query = "rice"
        XCTAssertNil(search.parsedQuery)
        XCTAssertEqual(search.phase, .idle)
    }

    func testGenericEstimatesSaveReopenAndRetainUnknownsAndStrictSourceRejection() throws {
        for query in ["100g rice", "200ml milk", "200g Greek yoghurt 10% fat", "2 eggs"] {
            let search = try model(); search.query = query; search.search()
            let input = try XCTUnwrap(search.confirmation(at: 0))
            let store = InMemoryFoodLedgerStore()
            let ids = HandoffIDs(seed: 10000)
            let ledger = FoodLedgerService(actorID: try ids.makeID(ActorTag.self), committer: store,
                clock: HandoffClock(), encoder: FoundationCanonicalJSONEncoder(), digester: SHA256Digester())
            let service = FoodConfirmationService(ledger: ledger, reader: store, clock: HandoffClock(), ids: ids)
            var state = FoodConfirmationState(input: input, queryQuantity: search.parsedQuery?.quantity)
            XCTAssertTrue(state.isGenericEstimate, query)
            XCTAssertTrue(state.materialDifferences.isEmpty, query)
            XCTAssertTrue(state.unresolvedIdentity.isEmpty, query)
            XCTAssertThrowsError(try service.save(state, operationID: ids.makeID(OperationTag.self)))
            FoodConfirmationReducer.reduce(state: &state, action: .accept)
            if state.quantity.unit == .count {
                XCTAssertThrowsError(try service.save(state, operationID: ids.makeID(OperationTag.self)))
                FoodConfirmationReducer.reduce(state: &state, action: .setConversion(QuantityConversionDraft(
                    convertedQuantity: try PositiveQuantity(value: 90, unit: .grams),
                    methodVersion: try LedgerText("User measured edible weight excluding shell"))))
            }
            let saved = try service.save(state, operationID: ids.makeID(OperationTag.self))
            XCTAssertEqual(saved.productVersion.identity, input.candidates[0].candidate.identity)
            XCTAssertEqual(saved.resolutionVersion.nutrients, input.candidates[0].candidate.nutrients)
            XCTAssertEqual(saved.evidence, input.evidence)
            XCTAssertEqual(saved.resolutionVersion.methodVersion.value, FoodConfirmationPolicy.version)
            XCTAssertTrue(saved.assertions.contains { $0.claim.value.contains(FoodConfirmationPolicy.version) })
            XCTAssertEqual(saved.candidateDecision.outcome, .rejected)
            XCTAssertFalse(saved.candidateDecision.contradictionReasons.isEmpty)
            let reopened = try XCTUnwrap(service.reopen(logItemID: saved.logItem.logItemID))
            XCTAssertTrue(reopened.unresolvedIdentity.isEmpty)
            let again = try service.save(reopened, operationID: ids.makeID(OperationTag.self))
            XCTAssertEqual(again.productVersion, saved.productVersion)
            XCTAssertEqual(again.resolutionVersion, saved.resolutionVersion)
            if query.contains("ml") {
                let projection = try FoodIntakeProjection(records: store.archiveState().records,
                    reportingDate: saved.logItemVersion.reportingDate.value)
                XCTAssertNil(projection.rows.first?.totals.first { $0.key == .protein }?.knownAmount)
            }
        }
    }

    func testAmbiguityNeverPrefillsExactQuantityAndGroundsStillBlockDiscovery() throws {
        let search = try model()
        for query in ["A bowl of rice", "<100g rice", "one mug coffee 15g grounds"] {
            search.query = query; search.search()
            XCTAssertNil(search.parsedQuery?.quantity)
            if query.contains("grounds") {
                XCTAssertNil(search.confirmation(at: 0))
                guard case .failed = search.phase else { return XCTFail(query) }
            } else {
                XCTAssertNotNil(search.confirmation(at: 0), query)
            }
        }
    }
}

private final class HandoffIDs: LedgerIDGenerating, @unchecked Sendable {
    private var value: Int
    init(seed: Int = 1) { value = seed }
    func makeID<Tag>(_ tag: Tag.Type) throws -> LedgerID<Tag> {
        defer { value += 1 }
        return try LedgerID(String(format: "00000000-0000-0000-0000-%012x",value))
    }
}

private struct HandoffClock: LedgerClock {
    func now() -> Date { Date(timeIntervalSince1970: 1700000000) }
}
