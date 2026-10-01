import Foundation
import FoodGenericSearch
import FoodLedgerApplication
import FoodLedgerDomain
import XCTest

final class OpenFoodFactsSearchTests: XCTestCase {
    private let clock = SearchFixedClock()
    private func product(_ change: (inout [String: Any]) -> Void = { _ in }) -> [String: Any] {
        var value: [String: Any] = ["code": "3274080005003", "product_name": "Greek yoghurt", "brands": "Synthetic",
            "quantity": "500 g", "nutrition_data_per": "100g", "nutriments": ["energy-kcal_100g": 120, "energy-kcal_unit": "kcal",
                "proteins_100g": 8, "proteins_unit": "g", "fat_100g": 0, "fat_unit": "g"]]
        change(&value)
        return value
    }
    private func search(_ products: [[String: Any]], terms: String = "Greek yogurt", status: Int = 200) async throws -> GenericFoodSearchOutcome {
        let transport = SearchFixture(response: OFFProductResponse(status: status,
            body: try JSONSerialization.data(withJSONObject: ["products": products])))
        return try await OpenFoodFactsSearch(transport: transport, locale: LedgerText("en_GB"), clock: clock)
            .enrich(FoodSearchRemoteQuery(foodTerms: terms))
    }

    func testTravelDishAdmissionRequiresAllIngredientsAndKeepsSourceUnknowns() async throws {
        let terms = "200g scallion pancake with egg and cheese"
        for name in ["Scallion pancake", "Scallion pancake with egg", "Cheese", "Pancake syrup", "Scallion pancake with egg and cheese dry mix"] {
            guard case .noResult = try await search([product { $0["product_name"] = name }], terms: terms) else { return XCTFail("Incomplete/different food admitted: \(name)") }
        }
        guard case let .confirmation(route) = try await search([product { $0["product_name"] = "Scallion pancake with egg and cheese" }], terms: terms) else { return XCTFail() }
        XCTAssertNil(FoodQueryParser.parse(terms).quantity)
        XCTAssertEqual(route.matches[0].candidate.candidate.identity.preparation.kind, .unknown)
        XCTAssertEqual(FoodConfirmationState(input: route.confirmation).decision, .undecided)
        XCTAssertEqual(route.confirmation.evidence[0].originalPayload, .text(try LedgerText(terms)))
        for query in ["pancake", "pancakes", "蛋餅 pancake"] {
            guard case .noResult = try await search([product { $0["product_name"] = "Pancake syrup" }], terms: query) else { return XCTFail(query) }
        }
        guard case .confirmation = try await search([product { $0["product_name"] = "Pancake syrup" }], terms: "pancake syrup") else { return XCTFail("Explicit syrup remains eligible") }
        guard case .noResult = try await search([product { $0["product_name"] = "Cheese" }], terms: "蛋餅 cheese") else { return XCTFail("Do not drop Chinese identity") }
    }

    func testNamedDishUsesWholeProductWithoutRecipeOrAmountInference() async throws {
        let original = "180g Baxters lentil and tomato soup"
        let transport = SearchFixture(response: .init(status: 200, body: try JSONSerialization.data(withJSONObject: ["products": [product { $0["product_name"] = "Baxters lentil and tomato soup" }]])))
        let outcome = try await OpenFoodFactsSearch(transport: transport, locale: LedgerText("en_GB"), clock: clock)
            .enrich(FoodSearchRemoteQuery(foodTerms: original))
        let terms = await transport.terms
        XCTAssertEqual(terms, ["baxters lentil and tomato soup"])
        guard case let .confirmation(route) = outcome else { return XCTFail() }
        XCTAssertNil(FoodQueryParser.parse(original).quantity)
        XCTAssertEqual(route.matches[0].candidate.candidate.identity.preparation.kind, .unknown)
        XCTAssertEqual(FoodConfirmationState(input: route.confirmation).decision, .undecided)
        XCTAssertEqual(route.confirmation.evidence[0].originalPayload, .text(try LedgerText(original)))
        guard case .noResult = try await search([product { $0["product_name"] = "Baxters lentil soup" }], terms: original) else { return XCTFail("Tomato must not be dropped") }
    }

    func testRequestedCookingMethodMustRemainInProductSearchAndCompatibility() async throws {
        for name in ["Raw broccoli", "Roasted broccoli", "Broccoli"] {
            let outcome = try await search([product { $0["product_name"] = name }], terms: "90g boiled broccoli")
            guard case .noResult = outcome else { return XCTFail(name) }
        }
        let outcome = try await search([product { $0["product_name"] = "Boiled broccoli" }], terms: "90g boiled broccoli")
        guard case let .confirmation(route) = outcome else { return XCTFail() }
        XCTAssertEqual(route.matches.first?.candidate.candidate.identity.preparation.kind, .unknown)
        XCTAssertEqual(FoodConfirmationState(input: route.confirmation).decision, .undecided)
    }

    func testTextResultPreservesProductUnknownsLicencesAndExplicitSelection() async throws {
        guard case let .confirmation(route) = try await search([product()]) else { return XCTFail() }
        XCTAssertNil(route.reuse)
        let candidate = try XCTUnwrap(route.matches.first?.candidate)
        XCTAssertEqual(candidate.barcode?.value, "03274080005003")
        XCTAssertEqual(candidate.brand?.value, "Synthetic")
        XCTAssertEqual(candidate.candidate.identity.preparation.kind, .unknown)
        XCTAssertEqual(candidate.candidate.nutrients.entries.first { $0.key == .sodium }?.value, .unknown(.notDeclared))
        guard case let .augmented(energy) = candidate.candidate.nutrients.entries.first(where: { $0.key == .energyConsumed })?.value else { return XCTFail() }
        XCTAssertEqual(energy.amount, 120)
        XCTAssertEqual(energy.provenance.first?.sourceKind, .exactProductDataset)
        XCTAssertFalse(FoodConfirmationPolicy.isGenericEstimate(route.confirmation, candidate: candidate))
        let state = FoodConfirmationState(input: route.confirmation)
        XCTAssertFalse(state.unresolvedIdentity.isEmpty)
        XCTAssertEqual(state.decision, .undecided)
        XCTAssertEqual(candidate.candidate.matchMetadata?.libraryAliases, [])
        XCTAssertEqual(route.confirmation.evidence[0].originalPayload, .text(try LedgerText("Greek yogurt")))
        XCTAssertEqual(route.confirmation.evidence[0].kind, .genericSearch) // Never a fabricated barcode scan.
        XCTAssertTrue(route.confirmation.sourceReleases[0].licence.value.contains("dbcl"))
        XCTAssertEqual(route.confirmation.sourceReleases[0].schemaVersion.value, "off-search-explicit-basis-candidates-v5")
    }

    func testBarcodeAndSearchShareNutrientIdentityAndQuantityAdmission() async throws {
        let modern = product { $0["nutrition"] = ["input_sets": [["source": "packaging", "per": "100g", "preparation": "as_sold",
            "nutrients": ["sodium": ["value": 0.052, "unit": "g"]]]]] }
        guard case let .confirmation(route) = try await search([modern]) else { return XCTFail() }
        let evidence = route.confirmation.evidence[0]
        let response = OFFProductResponse(status: 200, body: try JSONSerialization.data(withJSONObject: ["status": "success", "product": modern]))
        let barcode = OpenFoodFactsLookup(transport: SearchProductFixture(response: response), clock: clock)
        let request = try PackagedFoodLookupRequest(identity: BarcodeClassifier.classify(code: LedgerText("3274080005003"), symbology: .ean13), evidence: evidence)
        guard case let .candidate(input) = try await barcode.lookup(request) else { return XCTFail() }
        let a = route.matches[0].candidate.candidate, b = input.candidates[0].candidate
        XCTAssertTrue(route.confirmation.sourceReleases[0].sourceReleaseID.value.contains("schema:off-search-explicit-basis-candidates-v5:"))
        XCTAssertNotEqual(route.confirmation.sourceReleases[0].sourceReleaseID, input.sourceReleases[0].sourceReleaseID)
        guard case let .augmented(sodium) = a.nutrients.entries.first(where: { $0.key == .sodium })?.value else { return XCTFail() }
        XCTAssertEqual(sodium.amount, 52, accuracy: 1e-10)
        XCTAssertEqual(a.identity, b.identity)
        XCTAssertEqual(a.edibleQuantity, b.edibleQuantity)
        for (x, y) in zip(a.nutrients.entries, b.nutrients.entries) {
            XCTAssertEqual(x.key, y.key)
            switch (x.value, y.value) {
            case let (.augmented(x), .augmented(y)):
                XCTAssertEqual(x.amount, y.amount); XCTAssertEqual(x.unit, y.unit); XCTAssertEqual(x.sourceValue, y.sourceValue)
            default: XCTAssertEqual(x.value, y.value)
            }
        }
    }

    private func brandedCategoryProduct(_ change: (inout [String: Any]) -> Void = { _ in }) -> [String: Any] {
        product { p in
            p["product_name"] = "Acme Total 2%"; p["brands"] = "Acme"
            p["categories_tags"] = ["en:dairies", "en:greek-style-yogurts"]
            change(&p)
        }
    }

    func testLiteralPercentageUsesNamedVariantAndVisibleCategoryWithoutQuantityInference() async throws {
        let original = "150g Acme Total 2% Greek yoghurt"
        let transport = SearchFixture(response: .init(status: 200, body: try JSONSerialization.data(withJSONObject: ["products": [brandedCategoryProduct()]])))
        let outcome = try await OpenFoodFactsSearch(transport: transport, locale: LedgerText("en_GB"), clock: clock)
            .enrich(FoodSearchRemoteQuery(foodTerms: original))
        guard case let .confirmation(route) = outcome else { return XCTFail() }
        let sent = await transport.terms
        XCTAssertEqual(sent, ["acme total greek yoghurt 2%"])
        let candidate = route.matches[0].candidate
        XCTAssertEqual(candidate.name.value, "Acme Total 2%")
        XCTAssertTrue(candidate.variant?.value.contains("source category: greek style yogurts") == true)
        XCTAssertFalse(route.matches[0].isExactName)
        XCTAssertEqual(route.confirmation.evidence[0].originalPayload, .text(try LedgerText(original)))
        XCTAssertNil(FoodQueryParser.parse(original).quantity)
        XCTAssertTrue(FoodQueryCandidateAssessment.note(query: FoodQueryParser.parse(original), candidate: candidate)?.contains("meaning is not verified") == true)
        XCTAssertFalse(FoodConfirmationState(input: route.confirmation).unresolvedIdentity.isEmpty)
    }

    func testCategoryDiscoveryRequiresBrandAndOneExplicitCategoryCoveringEveryMissingTerm() async throws {
        let changes: [(inout [String: Any]) -> Void] = [
            { $0["brands"] = "Other" }, { $0["brands"] = "" }, { $0.removeValue(forKey: "brands") },
            { $0["categories_tags"] = ["en:yogurts"] },
            { $0["categories_tags"] = ["en:greek", "en:yogurts"] },
            { $0["categories_tags"] = ["fr:greek-style-yogurts"] },
            { $0["categories_tags"] = ["en:greek-style-yogurts": true] },
            { $0["categories_tags"] = ["en:desserts"] }
        ]
        for change in changes {
            guard case .noResult = try await search([brandedCategoryProduct(change)], terms: "Acme Total Greek yoghurt") else { return XCTFail("Unsupported category match") }
        }
        for text in ["Acme Total strawberry Greek yoghurt", "Other Total Greek yoghurt", "Greek yoghurt"] {
            guard case .noResult = try await search([brandedCategoryProduct()], terms: text) else { return XCTFail(text) }
        }
        guard case .confirmation = try await search([brandedCategoryProduct()], terms: "Acme Total Greek yoghurt") else { return XCTFail() }
    }

    func testLiteralPercentageCannotUseDifferentMissingRelativeOrNutrientOnlyPercentage() async throws {
        for name in ["Acme Total 5%", "Acme Total", "Acme Total 2% less", "Acme Total 2% or 5%"] {
            guard case .noResult = try await search([brandedCategoryProduct { $0["product_name"] = name }], terms: "150g Acme Total 2% Greek yoghurt") else { return XCTFail(name) }
        }
        guard case .confirmation = try await search([brandedCategoryProduct { $0["product_name"] = "Acme Total 2% fat" }], terms: "150g Acme Total 2% Greek yoghurt") else { return XCTFail() }
    }

    func testVolumeSearchCoverageDoesNotInventDensityForMassQuantity() async throws {
        let milk = product { p in
            p["product_name"] = "Whole milk"; p["quantity"] = "1 l"
            p["nutrition"] = ["input_sets": [["source": "packaging", "per": "100ml", "preparation": "as_sold",
                "nutrients": ["energy-kcal": ["value": 64, "unit": "kcal"], "proteins": ["value": 3.3, "unit": "g"],
                    "carbohydrates": ["value": 4.7, "unit": "g"], "fat": ["value": 3.6, "unit": "g"], "sodium": ["value": 40, "unit": "mg"]]]]]
        }
        for (query, expected) in [("200ml whole milk", FoodSearchCandidateCoverage.Basis.compatible), ("200g whole milk", .incompatible)] {
            let outcome = try await search([milk], terms: query)
            guard case let .confirmation(route) = outcome else { return XCTFail() }
            XCTAssertEqual(route.matches[0].candidate.candidate.identity.servingBasis, .per100Millilitres)
            let request = try GenericFoodSearchRequest(text: LedgerText(query), capturedAt: clock.now(), locale: LedgerText("en_GB"))
            let coverage = ConservativeFoodSearchCoverageAssessment().assess(outcome, for: request)
            XCTAssertEqual(coverage[0].basis, expected); XCTAssertEqual(coverage[0].nutrition, .complete)
            XCTAssertFalse(coverage[0].isSufficientForSearch)
        }
    }

    private func soyaDrink(_ change: (inout [String: Any]) -> Void = { _ in }) -> [String: Any] {
        product { p in
            p["product_name"] = "Soya Original"; p["brands"] = "Alpro"; p["quantity"] = "250 ml"
            p["categories_tags"] = ["en:soy-based-drinks"]
            p["nutrition"] = ["input_sets": [["source": "packaging", "per": "100ml", "preparation": "as_sold",
                "nutrients": ["proteins": ["value": 3, "unit": "g"]]]]]
            change(&p)
        }
    }
    func testCategoryDrinkPluralMatchesSymmetricallyWithoutRewritingSourceLabel() async throws {
        for query in ["205ml Alpro soya original drink", "205ml Alpro soya original drinks"] {
            for category in ["en:soy-based-drink", "en:soy-based-drinks"] {
                guard case let .confirmation(route) = try await search([soyaDrink { $0["categories_tags"] = [category] }], terms: query) else { return XCTFail(query) }
                XCTAssertEqual(route.matches.count, 1)
                XCTAssertTrue(route.matches[0].candidate.variant?.value.contains(category.dropFirst(3).replacingOccurrences(of: "-", with: " ")) == true)
                XCTAssertEqual(route.matches[0].candidate.candidate.identity.servingBasis, .per100Millilitres)
                XCTAssertFalse(route.matches[0].isExactName)
            }
        }
    }
    func testCategoryPluralDoesNotDiscardRequestedBrandFlavourOrOtherTerms() async throws {
        let changes: [(inout [String: Any]) -> Void] = [
            { $0["product_name"] = "Soya Vanilla" }, { $0["brands"] = "Other" },
            { $0["categories_tags"] = ["en:soy-based-desserts"] }, { $0["categories_tags"] = ["fr:soy-based-drinks"] }
        ]
        for change in changes {
            guard case .noResult = try await search([soyaDrink(change)], terms: "205ml Alpro soya original drink") else { return XCTFail() }
        }
        guard case .noResult = try await search([soyaDrink()], terms: "205ml Alpro oat original drink") else { return XCTFail() }
    }

    func testIrrelevantInvalidCodeLiquidAndAmbiguousProductsAreNotCandidates() async throws {
        let changes: [(inout [String: Any]) -> Void] = [
            { $0["product_name"] = "Greek bread" }, { $0["code"] = "3274080005004" },
            { $0["code"] = "abc" }, { $0["quantity"] = "500 ml" },
            { $0.removeValue(forKey: "nutrition_data_per") }, { $0["nutrition"] = [:] },
            { $0["nutriments"] = [:] }, { $0["categories_tags"] = ["en:dietary-supplements"] }
        ]
        for change in changes {
            guard case .noResult = try await search([product(change)]) else { return XCTFail("Unsafe or unrelated candidate admitted") }
        }
    }

    func testDuplicateProductsDeduplicateAndConflictingCodesRejectBatch() async throws {
        guard case let .confirmation(route) = try await search([product(), product()]) else { return XCTFail() }
        XCTAssertEqual(route.matches.count, 1)
        do {
            _ = try await search([product(), product { $0["quantity"] = "400 g" }])
            XCTFail("Conflicting duplicate must reject the batch")
        } catch { XCTAssertEqual(error as? FoodSearchEnrichmentError, .invalidResponse) }
    }

    func testStatusShapeAndLimitsFailWithoutRetry() async throws {
        let cases: [(OFFProductResponse, FoodSearchEnrichmentError)] = [
            (.init(status: 429, body: Data()), .quotaExceeded), (.init(status: 503, body: Data()), .unavailable),
            (.init(status: 200, body: Data("{}".utf8)), .invalidResponse),
            (.init(status: 200, body: Data(repeating: 0, count: 500_001)), .invalidResponse),
            (.init(status: 200, body: try JSONSerialization.data(withJSONObject: ["products": Array(repeating: product(), count: 11)])), .invalidResponse)
        ]
        for (response, expected) in cases {
            let transport = SearchFixture(response: response)
            do {
                _ = try await OpenFoodFactsSearch(transport: transport, locale: LedgerText("en_GB"))
                    .enrich(FoodSearchRemoteQuery(foodTerms: "Greek yoghurt"))
                XCTFail()
            } catch { XCTAssertEqual(error as? FoodSearchEnrichmentError, expected) }
            let terms = await transport.terms
            XCTAssertEqual(terms, ["greek yoghurt"])
        }
    }

    func testModernPackagingSetWinsWithoutLegacyBackfill() async throws {
        let modern = product {
            $0["nutrition"] = ["input_sets": [["source": "packaging", "per": "100g", "preparation": "as_sold",
                "nutrients": ["proteins": ["value": 6, "unit": "g", "modifier": "<"]]]]]
        }
        guard case let .confirmation(route) = try await search([modern]) else { return XCTFail() }
        let values = route.matches[0].candidate.candidate.nutrients.entries
        XCTAssertEqual(values.first { $0.key == .energyConsumed }?.value, .unknown(.notDeclared))
        guard case let .bounded(protein) = values.first(where: { $0.key == .protein })?.value else { return XCTFail() }
        XCTAssertEqual(protein.upper, 6)
        XCTAssertFalse(protein.upperClosed)
    }

    func testOutboundSearchRemovesOnlyIntakeQuantityAndRetainsDescriptors() async throws {
        let examples = [
            ("180g boiled brown rice", "brown rice boiled"),
            ("½ kg raw chicken breast", "chicken breast raw"),
            ("220ml whole cow's milk", "cow's milk whole"),
            ("140g Kolios Greek yoghurt 10% fat", "kolios greek yoghurt 10% fat"),
            ("100g Olympus Greek yoghurt 10% fat", "olympus greek yoghurt 10% fat"),
            ("3 boiled eggs", "egg boiled"),
            ("180ml Alpro unsweetened soya drink", "alpro soya drink unsweetened"),
            ("100g lactose-free yoghurt", "yoghurt lactose-free"),
            ("250g cooked weight sirloin", "sirloin cooked")
        ]
        for (original, expected) in examples {
            let transport = SearchFixture(response: OFFProductResponse(status: 200, body: Data("{\"products\":[]}".utf8)))
            _ = try await OpenFoodFactsSearch(transport: transport, locale: LedgerText("en_GB"), clock: clock)
                .enrich(FoodSearchRemoteQuery(foodTerms: original))
            let sent = await transport.terms
            XCTAssertEqual(sent, [expected], original)
        }
    }

    func testQuantityFreeRetrievalKeepsOriginalEvidenceAndFatVariantReview() async throws {
        let original = "140g Greek yoghurt 10% fat"
        guard case let .confirmation(route) = try await search([product()], terms: original) else { return XCTFail() }
        XCTAssertEqual(route.confirmation.evidence[0].originalPayload, .text(try LedgerText(original)))
        XCTAssertEqual(route.confirmation.evidence[0].captureMethodVersion.value, "off-search-candidates-v6")
        let candidate = route.matches[0].candidate
        let parsed = FoodQueryParser.parse(original)
        XCTAssertFalse(FoodQueryCandidateAssessment.matchesFat(query: parsed, candidate: candidate))
        XCTAssertTrue(FoodQueryCandidateAssessment.note(query: parsed, candidate: candidate)?.contains("you requested 10% fat") == true)
        XCTAssertEqual(candidate.candidate.identity.preparation.kind, .unknown)
        XCTAssertEqual(FoodConfirmationState(input: route.confirmation).decision, .undecided)
        XCTAssertFalse(FoodConfirmationPolicy.unresolvedIdentity(candidate.candidate.identity, allowingEstimate: false).isEmpty)
    }

    func testRecognisedBrandCannotBeDroppedWhenFilteringReturnedProducts() async throws {
        guard case .noResult = try await search([product()], terms: "100g Olympus Greek yoghurt") else {
            return XCTFail("A different brand must not become the requested product")
        }
        guard case .confirmation = try await search([product { $0["brands"] = "Olympus" }], terms: "100g Olympus Greek yoghurt") else {
            return XCTFail("Matching brand should remain a reviewable candidate")
        }
    }

    func testInvalidQuantityNeverReachesOFF() async throws {
        for original in ["0g rice", "-50g rice", "raw cooked rice"] {
            let transport = SearchFixture(response: OFFProductResponse(status: 200, body: Data("{\"products\":[]}".utf8)))
            do {
                _ = try await OpenFoodFactsSearch(transport: transport, locale: LedgerText("en_GB"), clock: clock)
                    .enrich(FoodSearchRemoteQuery(foodTerms: original))
                XCTFail("Should stop before networking: \(original)")
            } catch { XCTAssertEqual(error as? FoodSearchEnrichmentError, .invalidQuery) }
            let sent = await transport.terms
            XCTAssertTrue(sent.isEmpty)
        }
    }

    func testDescriptionsReachOFFWithoutMakingIntakeAmounts() async throws {
        for original in ["Scallion pancake with eggs and american chese", "100g rice and 200g chicken", "bowl of rice", "half scallion pancake"] {
            let transport = SearchFixture(response: .init(status: 200, body: Data("{\"products\":[]}".utf8)))
            _ = try await OpenFoodFactsSearch(transport: transport, locale: LedgerText("en_GB"), clock: clock)
                .enrich(FoodSearchRemoteQuery(foodTerms: original))
            let sent = await transport.terms
            XCTAssertEqual(sent.count, 1)
            XCTAssertNil(FoodQueryInterpretation(original).parsedQuery.quantity)
            if original == "half scallion pancake" { XCTAssertEqual(sent, ["scallion pancake"]) }
        }
    }

    func testCancellationIgnoringTransportCannotReturnCandidates() async throws {
        let started = expectation(description: "started")
        let transport = HeldSearchFixture(started: started)
        let source = try OpenFoodFactsSearch(transport: transport, locale: LedgerText("en_GB"))
        let task = Task { try await source.enrich(FoodSearchRemoteQuery(foodTerms: "yoghurt")) }
        await fulfillment(of: [started], timeout: 2)
        task.cancel()
        await transport.release(OFFProductResponse(status: 200, body: try JSONSerialization.data(withJSONObject: ["products": [product()]])))
        do { _ = try await task.value; XCTFail() } catch { XCTAssertTrue(error is CancellationError) }
    }
}

private struct SearchFixedClock: LedgerClock { func now() -> Date { Date(timeIntervalSince1970: 1_700_000_000) } }
private struct SearchProductFixture: OFFProductTransport {
    let response: OFFProductResponse
    func product(code: String) async throws -> OFFProductResponse { response }
}
private actor SearchFixture: OFFSearchTransport {
    let response: OFFProductResponse
    var terms: [String] = []
    init(response: OFFProductResponse) { self.response = response }
    func search(foodTerms: String) async throws -> OFFProductResponse { terms.append(foodTerms); return response }
}
private actor HeldSearchFixture: OFFSearchTransport {
    let started: XCTestExpectation
    var continuation: CheckedContinuation<OFFProductResponse, Never>?
    init(started: XCTestExpectation) { self.started = started }
    func search(foodTerms: String) async throws -> OFFProductResponse {
        await withCheckedContinuation { continuation = $0; started.fulfill() }
    }
    func release(_ response: OFFProductResponse) { continuation?.resume(returning: response); continuation = nil }
}
