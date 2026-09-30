import Foundation
import FoodGenericSearch
import FoodLedgerApplication
import FoodLedgerDomain
import FoodLedgerPresentation
import XCTest

final class FoodSearchStatusPresentationTests: XCTestCase {
    func testCitationOnlySourceNeverClaimsNutritionOrAnAddedMatch() {
        let status = FoodSearchStatusPresentation(reports: [.init(stage: .local),
            .init(stage: .gemini, hasSourceLinks: true)], pending: nil, stopped: false)
        XCTAssertEqual(status.summary, "0 matches · Web nutrition not verified")
        XCTAssertEqual(status.details[1], "Open Food Facts: Not searched")
        XCTAssertEqual(status.details[2], "Gemini: Source links found; no verified nutrition added")
        XCTAssertFalse(status.isSearching)
    }
    func testFailureKindsRemainActionableInDetailsWithoutScoresOrRawErrors() {
        for (error, text) in [(FoodSearchEnrichmentError.credentialRejected,"Key needs validation"),
                              (.quotaExceeded,"Usage limit reached"),(.permissionDenied,"Access unavailable")] {
            let status = FoodSearchStatusPresentation(reports: [.init(stage: .gemini, failure: error)], pending: nil, stopped: false)
            XCTAssertEqual(status.details[2], "Gemini: \(text)")
            XCTAssertEqual(status.summary,"Gemini unavailable · 0 matches kept")
        }
    }
    func testCompactCautionKeepsLiteralPercentageDistinctFromFatPercent() throws {
        let source = try CoFIDGenericFoodSearch(ids: RandomLedgerIDGenerator())
        guard case let .confirmation(route) = try source.search(.init(text: LedgerText("whole milk"),
            capturedAt: Date(timeIntervalSince1970: 1_700_000_000), locale: LedgerText("en_GB"))) else { return XCTFail() }
        let candidate = try XCTUnwrap(route.matches.first).candidate
        let literal = FoodSearchResultText.caution(query: FoodQueryParser.parse("milk 10%"), candidate: candidate,
            requestedPreparation: nil, isRecipe: false)
        XCTAssertEqual(literal,"10% meaning needs review")
        let fat = FoodSearchResultText.caution(query: FoodQueryParser.parse("milk 10% fat"), candidate: candidate,
            requestedPreparation: nil, isRecipe: false)
        XCTAssertTrue(fat?.contains("requested 10% fat") == true || fat?.contains("Requested 10% fat not verified") == true)
        XCTAssertFalse(fat?.contains("meaning needs review") == true)
    }
    func testGreekStyleRemainsALabelledAlternativeInCompactRows() throws {
        guard case let .confirmation(route) = try CoFIDGenericFoodSearch(ids: RandomLedgerIDGenerator()).search(
            .init(text: LedgerText("Greek style yoghurt"), capturedAt: Date(timeIntervalSince1970: 1_700_000_000), locale: LedgerText("en_GB"))) else { return XCTFail() }
        let candidate = try XCTUnwrap(route.matches.first(where: { $0.candidate.name.value.lowercased().contains("style") })).candidate
        let note = FoodSearchResultText.caution(query: FoodQueryParser.parse("Greek yoghurt 10% fat"), candidate: candidate,
            requestedPreparation: nil, isRecipe: false)
        XCTAssertTrue(note?.contains("Greek-style alternative") == true)
        XCTAssertFalse(note?.contains("Exact") == true)
    }
    func testRequestedCookedStateIsNotHiddenWhenSourcePreparationIsUnknown() throws {
        guard case let .confirmation(route) = try CoFIDGenericFoodSearch(ids: RandomLedgerIDGenerator()).search(
            .init(text: LedgerText("porridge made with water"), capturedAt: Date(timeIntervalSince1970: 1_700_000_000), locale: LedgerText("en_GB"))) else { return XCTFail() }
        let candidate = try XCTUnwrap(route.matches.first(where: { $0.candidate.candidate.identity.preparation.kind == .unknown })).candidate
        let note = FoodSearchResultText.caution(query: FoodQueryParser.parse("cooked porridge made with water"),
            candidate: candidate, requestedPreparation: .cooked, isRecipe: false)
        XCTAssertTrue(note?.contains("Cooked preparation not verified") == true)
    }
    func testRecipeCautionAndUnknownBasisNeverInventMeasuredWeight() throws {
        guard case let .confirmation(route) = try CoFIDGenericFoodSearch(ids: RandomLedgerIDGenerator()).search(
            .init(text: LedgerText("rice"), capturedAt: Date(timeIntervalSince1970: 1_700_000_000), locale: LedgerText("en_GB"))) else { return XCTFail() }
        XCTAssertEqual(FoodSearchResultText.caution(query:nil,candidate:route.matches[0].candidate,requestedPreparation:nil,isRecipe:true),
            "Representative recipe · cooked serving weight unknown")
        XCTAssertEqual(FoodSearchResultText.basisLabel(.unknown),"basis not specified")
    }
}
