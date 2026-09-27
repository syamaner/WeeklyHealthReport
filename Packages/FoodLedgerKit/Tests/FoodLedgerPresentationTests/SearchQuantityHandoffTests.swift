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
    func testAmbiguityNeverReachesCandidateSelectionOrExactQuantity() throws {
        let search = try model()
        for query in ["A bowl of rice", "<100g rice", "one mug coffee 15g grounds"] {
            search.query = query; search.search()
            XCTAssertNil(search.parsedQuery?.quantity)
            XCTAssertNil(search.confirmation(at: 0))
            guard case .failed = search.phase else { return XCTFail(query) }
        }
    }
}

private final class HandoffIDs: LedgerIDGenerating, @unchecked Sendable {
    private var value = 1
    func makeID<Tag>(_ tag: Tag.Type) throws -> LedgerID<Tag> {
        defer { value += 1 }
        return try LedgerID(String(format: "00000000-0000-0000-0000-%012x",value))
    }
}
