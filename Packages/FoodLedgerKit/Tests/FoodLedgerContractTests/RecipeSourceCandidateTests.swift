import CryptoKit
import Foundation
import XCTest
import FoodGenericSearch
import FoodLedgerApplication
import FoodLedgerDomain

final class RecipeSourceCandidateTests: XCTestCase {
    func testRecipeDeclarationAndUnknownIdentityRequireExplicitChoiceAndAmount() throws {
        let source = try RecipeAdmissionFixtures.source()
        XCTAssertEqual(source.recipes, [try WPRecipeSourceParser.profile(source.page.html, sourceURL: source.page.finalURL)])
        let route = try XCTUnwrap(RecipeAdmissionFixtures.route())
        let candidate = route.matches[0].candidate
        let state = FoodConfirmationState(input: route.confirmation)
        XCTAssertTrue(state.isSourceRecipe)
        XCTAssertTrue(state.isGenericEstimate)
        XCTAssertNil(state.quantity.value)
        XCTAssertEqual(state.quantity.unit, .count)
        XCTAssertEqual(state.decision, .undecided)
        XCTAssertFalse(state.materialDifferences.isEmpty)
        XCTAssertEqual(candidate.candidate.identity.preparation.kind, .unknown)
        XCTAssertEqual(candidate.candidate.identity.bone, .unknown)
        XCTAssertEqual(candidate.candidate.identity.servingBasis, FoodSourceRecipeProfile.basis)
        XCTAssertEqual(candidate.candidate.nutrients.entries.filter { if case .unknown = $0.value { true } else { false } }.count, 35)
        XCTAssertThrowsError(try state.calculatedEdibleQuantity())
    }
    func testQueryFoodCountDoesNotPrefillSourceRecipeServingCount() throws {
        let input = try XCTUnwrap(RecipeAdmissionFixtures.route()).confirmation
        for text in ["2 steak", "250g steak"] {
            let state = FoodConfirmationState(input: input, queryQuantity: FoodQueryParser.parse(text).quantity)
            XCTAssertNil(state.quantity.value, text)
            XCTAssertEqual(state.quantity.unit, .count, text)
        }
    }

    func testFractionalRecipeServingScalesWithoutInferringGrams() throws {
        var state = FoodConfirmationState(input: try XCTUnwrap(RecipeAdmissionFixtures.route()).confirmation)
        FoodConfirmationReducer.reduce(state: &state, action: .setQuantity(0.5, .count))
        let quantity = try state.calculatedEdibleQuantity()
        XCTAssertEqual(quantity, try PositiveQuantity(value: 0.5, unit: .count))
        let totals = FoodIntakeSummary(contributions: [.init(quantity: quantity, basis: FoodSourceRecipeProfile.basis,
            nutrients: state.selectedCandidate.candidate.nutrients)])
        XCTAssertEqual(totals.totals.first { $0.key == .energyConsumed }?.knownAmount, 200)
        XCTAssertTrue(totals.totals.first { $0.key == .energyConsumed }?.includesEstimates == true)
        XCTAssertNil(try RecipeAdmissionFixtures.source().recipes[0].cookedWeightGrams)
    }
    func testWeightVolumeConversionsAndPlatesCannotMasqueradeAsRecipeServings() throws {
        let input = try XCTUnwrap(RecipeAdmissionFixtures.route()).confirmation
        for unit in [QuantityUnit.grams, .millilitres] {
            var state = FoodConfirmationState(input: input)
            state.quantity.value = 250; state.quantity.unit = unit
            XCTAssertThrowsError(try state.calculatedEdibleQuantity())
        }
        var state = FoodConfirmationState(input: input)
        state.quantity.value = 1
        state.quantity.conversion = try .init(convertedQuantity: PositiveQuantity(value: 250, unit: .grams), methodVersion: LedgerText("synthetic"))
        XCTAssertThrowsError(try state.calculatedEdibleQuantity())
        state.quantity.conversion = nil; state.quantity.plateChoice = .missing
        XCTAssertThrowsError(try state.calculatedEdibleQuantity())
        state.quantity.plateChoice = .foodOnly; state.quantity.directWeight = .init(totalGrams: 250, basis: .measured)
        XCTAssertThrowsError(try state.calculatedEdibleQuantity())
        let ordinary = FoodQuantityDraft(value: 1, unit: .count)
        XCTAssertThrowsError(try ordinary.calculatedEdibleQuantity())
    }
    func testOtherFoodsBrandsAndSourceHostsDoNotBecomeThisRecipe() throws {
        for terms in ["Taiwanese oyster omelette", "Fat Daddy fried chicken Taiwan", "steak with cheese", "beef noodles", "250g cooked sirloin", "steak 10% fat"] {
            XCTAssertNil(try RecipeAdmissionFixtures.route(terms: terms), terms)
        }
        let source = try RecipeAdmissionFixtures.source()
        for url in ["https://auntieemily.com/other-recipe/", "https://evil.example/taiwan-night-market-steak/", "https://auntieemily.com/taiwan-night-market-steak/?product=other"] {
            let p = source.page
            let page = AcquiredFoodSourcePage(requestedURL: p.requestedURL, finalURL: URL(string: url)!, hops: p.hops,
                html: p.html, sha256: p.sha256, retrievedAt: p.retrievedAt)
            XCTAssertNil(try AuntieEmilyRecipeCandidateAdmission().admit(.init(citation: source.citation, page: page,
                panels: [], recipes: source.recipes), query: RecipeAdmissionFixtures.query(), evidence: SourceAdmissionFixtures.evidence()))
        }
    }
    func testMergedRecipeKeepsExplicitAcknowledgementAndSelectionClearsOtherFoodQuantity() throws {
        let recipe = try XCTUnwrap(RecipeAdmissionFixtures.route())
        guard case let .confirmation(onlyRecipe) = try FoodSearchResultMerger.merge(nil, .confirmation(recipe)) else { return XCTFail() }
        let onlyState = FoodConfirmationState(input: onlyRecipe.confirmation)
        XCTAssertNil(onlyState.quantity.value)
        XCTAssertFalse(onlyState.materialDifferences.isEmpty)
        let local = try CoFIDGenericFoodSearch(ids: RandomLedgerIDGenerator()).search(
            GenericFoodSearchRequest(text: LedgerText("rice"), capturedAt: LedgerFixtures.date, locale: LedgerText("en_GB")))
        guard case let .confirmation(merged) = try FoodSearchResultMerger.merge(local, .confirmation(recipe)),
              let index = merged.confirmation.candidates.firstIndex(where: { $0.candidate.recordID == recipe.matches[0].candidate.candidate.recordID }) else { return XCTFail() }
        var state = FoodConfirmationState(input: merged.confirmation)
        state.quantity = FoodQuantityDraft(value: 250, unit: .grams)
        FoodConfirmationReducer.reduce(state: &state, action: .selectCandidate(index))
        XCTAssertTrue(state.isSourceRecipe); XCTAssertNil(state.quantity.value); XCTAssertEqual(state.quantity.unit, .count)
        FoodConfirmationReducer.reduce(state: &state, action: .setQuantity(0.5, .count))
        FoodConfirmationReducer.reduce(state: &state, action: .selectCandidate(0))
        XCTAssertFalse(state.isSourceRecipe); XCTAssertNil(state.quantity.value); XCTAssertEqual(state.quantity.unit, .grams)
    }

    func testTamperedReviewProfileOrSourceHashCannotAdmit() throws {
        let source = try RecipeAdmissionFixtures.source()
        XCTAssertNil(try AuntieEmilyRecipeCandidateAdmission().admit(.init(citation: source.citation, page: source.page, panels: []),
            query: RecipeAdmissionFixtures.query(), evidence: SourceAdmissionFixtures.evidence()))
        let p=source.page
        let page=AcquiredFoodSourcePage(requestedURL:p.requestedURL,finalURL:p.finalURL,hops:p.hops,html:p.html,
            sha256:String(repeating:"0",count:64),retrievedAt:p.retrievedAt)
        XCTAssertNil(try AuntieEmilyRecipeCandidateAdmission().admit(.init(citation:source.citation,page:page,panels:[],recipes:source.recipes),
            query:RecipeAdmissionFixtures.query(),evidence:SourceAdmissionFixtures.evidence()))
    }
    func testRecipeBindingRejectsDuplicateHiddenAndAmbiguousSourceFields() throws {
        let html = try RecipeAdmissionFixtures.html()
        let variants = [
            html.replacingOccurrences(of: "\"proteinContent\": \"20 g\"", with: "\"proteinContent\": \"999 g\", \"proteinContent\": \"20 g\""),
            html.replacingOccurrences(of: ">20</span>", with: "><span hidden>20</span></span>"),
            html + "<script type='application/ld+json'>{\"@type\":[\"Thing\",\"Recipe\"],\"name\":\"Other\"}</script>",
            html.replacingOccurrences(of: "\"servingSize\": \"1 serving\"", with: "\"servingSize\": \"100 g\""),
            html.replacingOccurrences(of: "\"recipeYield\": [\"2\", \"2 Servings\"]", with: "\"recipeYield\": [\"2\", \"3 Servings\"]")]
        for variant in variants { XCTAssertThrowsError(try WPRecipeSourceParser.profile(Data(variant.utf8), sourceURL: RecipeAdmissionFixtures.url)) }
    }
}

enum RecipeAdmissionFixtures {
    static let url = URL(string: "https://auntieemily.com/taiwan-night-market-steak/")!
    static func query(_ text: String = "Taiwanese steak with noodles and fried egg") throws -> FoodSearchRemoteQuery { try .init(foodTerms: text) }
    static func html() throws -> String {
        let path = Bundle.module.url(forResource: "recipe-source-synthetic", withExtension: "html", subdirectory: "Fixtures")!
        return try String(contentsOf: path, encoding: .utf8)
    }
    static func source() throws -> FoodReviewedSource {
        let raw = Data(try html().utf8)
        let profile = try WPRecipeSourceParser.profile(raw, sourceURL: url)
        let page = AcquiredFoodSourcePage(requestedURL: url, finalURL: url, hops: [.init(url: url, status: 200)],
            html: raw, sha256: profile.htmlSHA256, retrievedAt: LedgerFixtures.date)
        return .init(citation: .init(title: "Untrusted model estimates 999 kcal", url: url), page: page, panels: [], recipes: [profile])
    }
    static func route(terms: String = "Taiwanese steak with noodles and fried egg") throws -> GenericFoodConfirmationRoute? {
        try AuntieEmilyRecipeCandidateAdmission().admit(source(), query: query(terms), evidence: SourceAdmissionFixtures.evidence(terms))
    }
}
