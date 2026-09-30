import Foundation
import SwiftUI
import XCTest
import FoodLedgerDomain
import FoodLedgerApplication
import FoodGenericSearch
import FoodLedgerPresentation

@MainActor
final class RecipeServingPresentationTests: XCTestCase {
    private func model() throws -> FoodConfirmationViewModel {
        let url = URL(string: "https://auntieemily.com/taiwan-night-market-steak/")!
        let raw = Data(Self.html.utf8)
        let profile = try WPRecipeSourceParser.profile(raw, sourceURL: url)
        let page = AcquiredFoodSourcePage(requestedURL: url, finalURL: url, hops: [.init(url: url, status: 200)],
            html: raw, sha256: profile.htmlSHA256, retrievedAt: Date(timeIntervalSince1970: 1000))
        let source = FoodReviewedSource(citation: .init(title: "Untrusted", url: url), page: page, panels: [], recipes: [profile])
        let evidence = try CaptureEvidence(evidenceID: EvidenceID(UUID().uuidString.lowercased()), kind: .genericSearch, capturedAt: page.retrievedAt,
            locale: LedgerText("en_GB"), captureMethod: LedgerText("test"), captureMethodVersion: LedgerText("v1"),
            originalPayload: .text(LedgerText("Taiwanese steak with noodles and fried egg")))
        let route = try XCTUnwrap(AuntieEmilyRecipeCandidateAdmission().admit(source,
            query: FoodSearchRemoteQuery(foodTerms: "Taiwanese steak with noodles and fried egg"), evidence: evidence))
        return FoodConfirmationViewModel(state: FoodConfirmationState(input: route.confirmation)) { _ in throw CocoaError(.fileWriteUnknown) }
    }
    func testRecipeServingStartsEmptyRequiresSelectionAndPreviewsFractionAsEstimate() throws {
        let model = try model()
        XCTAssertNil(model.state.quantity.value)
        XCTAssertFalse(model.saveRequirements.isEmpty)
        model.send(.setQuantity(0.5, .count))
        XCTAssertEqual(model.consumedNutrition.first { $0.key == .energyConsumed }?.knownAmount, 200)
        XCTAssertTrue(model.consumedNutrition.first { $0.key == .energyConsumed }?.includesEstimates == true)
        model.send(.accept)
        XCTAssertTrue(model.saveRequirements.contains { $0.contains("closest match") })
        model.send(.acceptClosestMatch(try LedgerText("Representative recipe estimate")))
        XCTAssertTrue(model.saveRequirements.isEmpty)
        XCTAssertTrue(model.nutritionReferenceTitle.contains("recipe serving"))
        let view = FoodConfirmationView(model: model, leave: {}).environment(\.dynamicTypeSize, .accessibility5)
        XCTAssertFalse(String(describing: view).isEmpty)
    }
    func testWeighedRecipeCannotPretendCookedServingWeightIsKnown() throws {
        let model = try model()
        model.send(.setQuantity(250, .grams))
        XCTAssertTrue(model.quantityBasisWarning?.contains("unknown") == true)
        XCTAssertTrue(model.consumedNutrition.isEmpty)
        XCTAssertTrue(model.saveRequirements.contains { $0.contains("cooked serving weight is unknown") })
    }
    private static let html = #"""
<html><script type="application/ld+json">{"@type": "Recipe", "@id": "https://auntieemily.com/taiwan-night-market-steak/#recipe", "name": "Taiwan night market steak", "recipeYield": ["2", "2 Servings"], "recipeIngredient": ["2 eggs", "100 g dry pasta"], "nutrition": {"@type": "NutritionInformation", "servingSize": "1 serving", "calories": "400 kcal", "fatContent": "10 g", "carbohydrateContent": "50 g", "proteinContent": "20 g"}}</script><div class="wprm-recipe-container"><h2 class="wprm-recipe-name">Taiwan night market steak</h2><span class="wprm-recipe-servings">2</span><div class="wprm-nutrition-label-container"><span class="wprm-nutrition-label-text-nutrition-container-calories"><span class="wprm-nutrition-label-text-nutrition-label">Calories:</span><span class="wprm-nutrition-label-text-nutrition-value">400</span><span class="wprm-nutrition-label-text-nutrition-unit">kcal</span></span><span class="wprm-nutrition-label-text-nutrition-container-fat"><span class="wprm-nutrition-label-text-nutrition-label">Fat:</span><span class="wprm-nutrition-label-text-nutrition-value">10</span><span class="wprm-nutrition-label-text-nutrition-unit">g</span></span><span class="wprm-nutrition-label-text-nutrition-container-carbohydrates"><span class="wprm-nutrition-label-text-nutrition-label">Carbohydrates:</span><span class="wprm-nutrition-label-text-nutrition-value">50</span><span class="wprm-nutrition-label-text-nutrition-unit">g</span></span><span class="wprm-nutrition-label-text-nutrition-container-protein"><span class="wprm-nutrition-label-text-nutrition-label">Protein:</span><span class="wprm-nutrition-label-text-nutrition-value">20</span><span class="wprm-nutrition-label-text-nutrition-unit">g</span></span></div></div></html>
"""#
}
