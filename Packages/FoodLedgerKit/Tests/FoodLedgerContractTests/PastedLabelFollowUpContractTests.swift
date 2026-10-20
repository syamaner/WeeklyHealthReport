import Foundation
import FoodLedgerApplication
import FoodLedgerDomain
import FoodLedgerTestSupport
import XCTest

/// PR #271 follow-ups at contract level (#93): Recent items for a pasted label with a calculated
/// value (L5) and a pasted label's servings amount (Q-D1), and the saved entry's serving size
/// origin, on both stores. Synthetic fixtures only.
final class PastedLabelFollowUpContractTests: XCTestCase {
    private typealias F = PastedLabelFixtures

    private func state(_ input: PopulatedFoodConfirmation, _ amount: Double, _ unit: QuantityUnit) -> FoodConfirmationState {
        var state = FoodConfirmationState(input: input, prefillSourceQuantity: false)
        FoodConfirmationReducer.reduce(state: &state, action: .setQuantity(amount, unit))
        state.answerPendingDifferences()
        FoodConfirmationReducer.reduce(state: &state, action: .accept)
        return state
    }

    func testRecentItemsMarkACalculatedPastedLabelAsAnEstimateAndKnowItsServings() throws {
        let printed30g = PastedLabelManifest.Candidate.ServingSize(printedText: "每一份量30公克", decimalText: "30", unit: "公克", canonicalUnit: "g")
        for harness in try LedgerFixtures.harnesses() {
            defer { harness.cleanup() }
            let service = try F.service(harness)
            // kcal is calculated from printed kJ (pasted-label-conversions-v1), logged in grams.
            let grams = try service.save(state(try F.input(F.manifest()), 150, .grams), operationID: LedgerFixtures.operationID(9_500))
            // The same kind of label with a serving size, logged as 2 servings (v2), a separate record.
            let servingsInput = try F.input(F.per100Manifest(servingSize: printed30g), evidence: 9_101)
            let servings = try service.save(state(servingsInput, 2, .count), operationID: LedgerFixtures.operationID(9_501))
            let records = try XCTUnwrap(harness.committer as? any FoodArchiveLedgerAccess).archiveState().records
            let items = FoodRecentItemsService(reader: harness.reader, confirmations: service)
                .items(records: records, now: LedgerFixtures.date.addingTimeInterval(60), calendar: QuickAddFixtures.london)
            let byLog = Dictionary(uniqueKeysWithValues: items.map { ($0.item.logItemID, $0) })
            let gramsItem = try XCTUnwrap(byLog[grams.logItem.logItemID], harness.name)
            XCTAssertTrue(gramsItem.isEstimate, "A calculated value makes a recent item an estimate (\(harness.name))")
            XCTAssertFalse(gramsItem.item.lastAmountIsServings)
            let servingsItem = try XCTUnwrap(byLog[servings.logItem.logItemID], harness.name)
            XCTAssertTrue(servingsItem.isEstimate, harness.name)
            XCTAssertTrue(servingsItem.item.lastAmountIsServings, "2 servings, not 2 pieces (\(harness.name))")
            XCTAssertEqual(servingsItem.item.lastAmount, try PositiveQuantity(value: 2, unit: .count))

            let detail = SavedFoodEntryDetail(stored: servings, isEstimate: false, history: [])
            XCTAssertTrue(detail.amountIsServings)
            XCTAssertEqual(detail.servingSize?.quantity, try PositiveQuantity(value: 30, unit: .grams))
            XCTAssertEqual(detail.servingSize?.origin, .printed)
            let gramsDetail = SavedFoodEntryDetail(stored: grams, isEstimate: false, history: [])
            XCTAssertFalse(gramsDetail.amountIsServings)
            XCTAssertNil(gramsDetail.servingSize)
        }
    }

    func testServingsAmountsAreOnlyPastedLabelServings() throws {
        XCTAssertTrue(PastedLabelServingPolicy.isServingsAmount(enteredUnit: .count, conversion: nil, sourceID: PastedLabelSource.sourceID),
                      "v1 case 3: counted servings with no conversion")
        XCTAssertFalse(PastedLabelServingPolicy.isServingsAmount(enteredUnit: .count, conversion: nil, sourceID: "cofid"))
        XCTAssertFalse(PastedLabelServingPolicy.isServingsAmount(enteredUnit: .grams, conversion: nil, sourceID: PastedLabelSource.sourceID))
        let measured = try QuantityConversionVersion(quantityConversionVersionID: LedgerFixtures.id(9_510, QuantityConversionVersionTag.self),
            ordinal: VersionOrdinal(1), supersedesQuantityConversionVersionID: nil,
            sourceQuantity: PositiveQuantity(value: 2, unit: .count), convertedQuantity: PositiveQuantity(value: 50, unit: .grams),
            methodVersion: LedgerText("Kitchen scale"), sourceReleaseID: nil, evidenceID: nil, createdAt: LedgerFixtures.date)
        XCTAssertFalse(PastedLabelServingPolicy.isServingsAmount(enteredUnit: .count, conversion: measured, sourceID: PastedLabelSource.sourceID),
                       "A measured count on a label with no serving size is pieces")
    }
}
