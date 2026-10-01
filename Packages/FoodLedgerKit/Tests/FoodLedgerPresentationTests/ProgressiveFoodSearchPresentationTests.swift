import Foundation
import Combine
import FoodGenericSearch
import FoodLedgerApplication
import FoodLedgerDomain
import FoodLedgerPresentation
import XCTest

@MainActor
final class ProgressiveFoodSearchPresentationTests: XCTestCase {
    func testUnknownNamedDishPreparationStaysVisibleAndUnselectedThroughReview() throws {
        let local = try CompositeGenericFoodSearch(sources: [CoFIDGenericFoodSearch(ids: RandomLedgerIDGenerator()), USDAGenericFoodSearch(ids: RandomLedgerIDGenerator())], ids: RandomLedgerIDGenerator())
        let model = try GenericFoodSearchViewModel(searcher: local, locale: LedgerText("en_GB"))
        model.query = "200g cooked porridge made with water"; model.search()
        guard case let .results(route) = model.phase else { return XCTFail() }
        XCTAssertNil(model.parsedQuery?.quantity)
        XCTAssertTrue(route.matches.allSatisfy { $0.candidate.candidate.identity.preparation.kind == .unknown })
        let selected = try XCTUnwrap(model.confirmation(at: 0))
        XCTAssertEqual(selected.candidates[0].candidate.identity.preparation.kind, .unknown)
        XCTAssertEqual(FoodConfirmationState(input: selected).decision, .undecided)
        let note = FoodQueryCandidateAssessment.note(query: FoodQueryParser.parse("porridge made with water"), candidate: selected.candidates[0], requestedPreparation: .cooked)
        XCTAssertTrue(note?.contains("requested cooked") == true)
    }

    func testNamedDishDiscoveryReachesRealLocalSourcesButKeepsAmountAndRecipeUnconfirmed() throws {
        let local = try CompositeGenericFoodSearch(sources: [CoFIDGenericFoodSearch(ids: RandomLedgerIDGenerator()), USDAGenericFoodSearch(ids: RandomLedgerIDGenerator())], ids: RandomLedgerIDGenerator())
        let model = try GenericFoodSearchViewModel(searcher: local, locale: LedgerText("en_GB"))
        for query in ["200g cooked porridge made with water", "200g porridge made with milk", "275g homemade lentil and tomato soup", "180g Baxters lentil and tomato soup", "Taiwanese breakfast scallion n pancake with eggs and sliced cheese", "steak with noodles and fried egg", "500ml bubble tea with pearls"] {
            model.query = query; model.search()
            XCTAssertEqual(model.parsedQuery?.route, .clarify)
            XCTAssertNil(model.parsedQuery?.quantity)
            XCTAssertNotNil(model.parsedQuery?.discoveryReviewMessage)
            switch model.phase {
            case let .results(route):
                XCTAssertEqual(FoodConfirmationState(input: route.confirmation).decision, .undecided)
                XCTAssertTrue(route.confirmation.evidence.contains { $0.originalPayload == .text(try! LedgerText(query)) })
            case let .noResult(route):
                XCTAssertTrue(route.retainedEvidence.contains { $0.originalPayload == .text(try! LedgerText(query)) })
            default: XCTFail("Named dish should reach lookup: \(query)")
            }
        }
    }

    func testCookingMethodsKeepSourceMethodAndNeverReturnKnownRawAsCooked() throws {
        let local = try CompositeGenericFoodSearch(sources: [CoFIDGenericFoodSearch(ids: RandomLedgerIDGenerator()), USDAGenericFoodSearch(ids: RandomLedgerIDGenerator())], ids: RandomLedgerIDGenerator())
        let model = try GenericFoodSearchViewModel(searcher: local, locale: LedgerText("en_GB"))
        for query in ["90g boiled broccoli", "180g boiled brown rice", "160g boiled red lentils"] {
            model.query = query; model.search()
            guard case let .results(route) = model.phase else { return XCTFail(query) }
            let method = try XCTUnwrap(model.parsedQuery?.attributes["preparation"])
            XCTAssertTrue(route.matches.allSatisfy { $0.candidate.name.value.lowercased().contains(method) }, query)
            XCTAssertTrue(route.matches.allSatisfy { $0.candidate.candidate.identity.preparation.kind != .raw }, query)
            XCTAssertEqual(FoodConfirmationState(input: route.confirmation).decision, .undecided)
            XCTAssertTrue(route.confirmation.evidence.contains { $0.originalPayload == .text(try! LedgerText(query)) })
        }
        for query in ["90g roasted broccoli", "160g roasted skinless chicken breast", "2 soft boiled eggs"] {
            model.query = query; model.search()
            guard case .noResult = model.phase else { return XCTFail("Do not silently broaden a missing method: \(query)") }
        }
        model.query = "90g boiled broccoli"; model.preparationFilter = .raw; model.search()
        guard case .failed = model.phase else { return XCTFail("Contradictory filter must stop") }
    }

    func testCowSpecificMilkRecoveryRequiresExplicitSearchAndRetainsOriginalEvidence() throws {
        let local = try CompositeGenericFoodSearch(sources: [CoFIDGenericFoodSearch(ids: RandomLedgerIDGenerator()), USDAGenericFoodSearch(ids: RandomLedgerIDGenerator())], ids: RandomLedgerIDGenerator())
        let model = try GenericFoodSearchViewModel(searcher: local, locale: LedgerText("en_GB"))
        for query in ["220ml whole cow's milk", "220ml whole cow’s milk", "220ml whole cows milk"] {
            model.query = query; model.search()
            guard case let .noResult(miss) = model.phase else { return XCTFail("Species must not be silently dropped") }
            XCTAssertEqual(miss.suggestedQueries, ["220ml whole milk"])
            XCTAssertTrue(miss.guidance.contains("broader"))
            XCTAssertEqual(model.query, query)
            model.searchSuggestion("220ml whole milk", from: miss)
            guard case let .results(route) = model.phase else { return XCTFail("Explicit recovery should find whole milk") }
            XCTAssertEqual(model.parsedQuery?.quantity?.value, 220)
            XCTAssertEqual(model.parsedQuery?.quantity?.unit, "ml")
            XCTAssertTrue(route.confirmation.evidence.contains { $0.originalPayload == .text(try! LedgerText(query)) })
            XCTAssertEqual(FoodConfirmationState(input: route.confirmation).decision, .undecided)
            XCTAssertEqual(route.matches.first?.candidate.name.value, "Milk, whole, pasteurised, average")
            XCTAssertEqual(route.matches.first?.candidate.candidate.identity.servingBasis, .per100Grams)
        }
        for query in ["220ml skimmed cow's milk", "220ml whole chocolate cow's milk", "220ml raw whole cow's milk"] {
            model.query = query; model.search()
            if case let .noResult(miss) = model.phase { XCTAssertFalse(miss.suggestedQueries.contains("220ml whole milk")) }
        }
    }

    func testConflictingPreparationStopsBeforeLocalOrEnabledProvidersEvenWithLiteralPercentage() async throws {
        let provider = PreparationGateEnrichment()
        let model = try GenericFoodSearchViewModel(searcher: RejectedPreparationLocalSearch(), locale: LedgerText("en_GB"),
            database: provider, gemini: provider, services: .init(onlineDatabase: .ready, gemini: .ready))
        for query in ["250g raw grilled beef sirloin steak", "160g uncooked steamed cod", "175g uncooked cooked quinoa",
                      "160g raw stewed pork", "160g broiled uncooked cod", "150g raw grilled FAGE Total 2% Greek yoghurt"] {
            model.query = query
            model.search()
            guard case .failed = model.phase else { return XCTFail("Conflicting preparation must ask for clarification") }
            XCTAssertEqual(model.parsedQuery?.route, .clarify)
            XCTAssertTrue(model.parsedQuery?.reasons.contains("conflicting_preparation") == true)
            XCTAssertFalse(model.parsedQuery?.allowsCandidateDiscovery ?? true)
            XCTAssertNil(model.parsedQuery?.quantity)
            XCTAssertNil(model.activeEnrichmentStage)
        }
        await Task.yield()
        let calls = await provider.calls
        XCTAssertEqual(calls, 0)
    }

    func testBundledCookedAndRawQuinoaSearchPreservesPreparationThroughRealComposition() throws {
        let local = try CompositeGenericFoodSearch(sources: [
            CoFIDGenericFoodSearch(ids: RandomLedgerIDGenerator()),
            USDAGenericFoodSearch(ids: RandomLedgerIDGenerator())
        ], ids: RandomLedgerIDGenerator())
        let model = try GenericFoodSearchViewModel(searcher: local, locale: LedgerText("en_GB"))
        for (word, state, record, energy) in [("cooked", PreparationKind.cooked, ":fdc:168917", 120.0),
                                            ("raw", .raw, ":fdc:168874", 368.0), ("uncooked", .raw, ":fdc:168874", 368.0)] {
            model.query = "175g \(word) quinoa"
            model.search()
            guard case let .results(route) = model.phase else { return XCTFail("Expected local results") }
            XCTAssertNil(model.enrichmentMessage)
            XCTAssertNil(model.activeEnrichmentStage)
            XCTAssertEqual(model.parsedQuery?.quantity?.value, 175)
            XCTAssertTrue(route.matches.allSatisfy { $0.candidate.candidate.identity.preparation.kind == state })
            if state == .cooked {
                XCTAssertFalse(route.matches.contains { $0.candidate.name.value.lowercased().contains("uncooked") })
            }
            let match = try XCTUnwrap(route.matches.first { $0.candidate.candidate.recordID.value.hasSuffix(record) })
            guard case let .augmented(value) = match.candidate.candidate.nutrients.entries.first(where: { $0.key == .energyConsumed })?.value else {
                return XCTFail("Expected literal source energy")
            }
            XCTAssertEqual(value.amount, energy)
            XCTAssertEqual(FoodConfirmationState(input: route.confirmation).decision, .undecided)
        }
    }

    func testQueryEditAndSettingsChangeCannotReviveOldResults() async throws {
        let started = expectation(description: "provider started")
        let returned = expectation(description: "provider returned")
        let remote = HeldFoodEnrichment(started: started, returned: returned)
        let model = try makeModel(remote)
        model.query = "200ml milk"
        model.search()
        await fulfillment(of: [started], timeout: 2)
        model.query = "100g rice"
        XCTAssertEqual(model.phase, .idle)
        XCTAssertNil(model.parsedQuery)
        model.setServices(.init(onlineDatabase: .disabled, gemini: .disabled))
        XCTAssertEqual(model.phase, .idle)
        model.search()
        let rice = model.phase
        await remote.release(try remoteMilk())
        await fulfillment(of: [returned], timeout: 2)
        await Task.yield()
        XCTAssertEqual(model.phase, rice)
        XCTAssertNil(model.activeEnrichmentStage)
        XCTAssertEqual(model.parsedQuery?.quantity?.value, 100)
    }

    func testChoosingCandidateFreezesConfirmationAndQuantityBeforeRemoteReturns() async throws {
        let started = expectation(description: "provider started")
        let returned = expectation(description: "provider returned")
        let remote = HeldFoodEnrichment(started: started, returned: returned)
        let model = try makeModel(remote)
        model.query = "200ml milk"
        model.search()
        await fulfillment(of: [started], timeout: 2)
        guard case let .results(route) = model.phase else { return XCTFail() }
        let index = min(1, route.matches.count - 1)
        let selected = try XCTUnwrap(model.confirmation(id: route.matches[index].searchID))
        let confirmation = FoodConfirmationState(input: selected, queryQuantity: model.parsedQuery?.quantity)
        XCTAssertEqual(confirmation.quantity.value, 200)
        XCTAssertEqual(confirmation.quantity.unit, .millilitres)
        XCTAssertNil(confirmation.quantity.conversion)
        XCTAssertEqual(confirmation.decision, .undecided)
        XCTAssertNil(model.activeEnrichmentStage)
        let phase = model.phase
        await remote.release(try remoteMilk())
        await fulfillment(of: [returned], timeout: 2)
        await Task.yield()
        XCTAssertEqual(model.phase, phase)
        XCTAssertEqual(selected.candidates[0], route.matches[index].candidate)
        XCTAssertEqual(confirmation.input, selected)
    }

    func testProgressiveArrivalPreservesEveryExistingRowAndSelectableIdentity() async throws {
        let started = expectation(description: "provider started")
        let returned = expectation(description: "provider returned")
        let finished = expectation(description: "enrichment displayed")
        let remote = HeldFoodEnrichment(started: started, returned: returned)
        let model = try makeModel(remote)
        model.query = "200ml milk"
        model.search()
        guard case let .results(before) = model.phase else { return XCTFail() }
        let oldIDs = before.matches.map(\.searchID)
        let subscription = model.$activeEnrichmentStage.dropFirst().sink { if $0 == nil { finished.fulfill() } }
        await fulfillment(of: [started], timeout: 2)
        await remote.release(try remoteMilk())
        await fulfillment(of: [returned, finished], timeout: 2)
        subscription.cancel()
        guard case let .results(after) = model.phase else { return XCTFail() }
        XCTAssertEqual(Array(after.matches.prefix(oldIDs.count)).map(\.searchID), oldIDs)
        XCTAssertGreaterThan(after.matches.count, before.matches.count)
        XCTAssertEqual(model.confirmation(id: oldIDs.last!)?.candidates.first, before.matches.last?.candidate)
        XCTAssertEqual(model.parsedQuery?.quantity?.value, 200)
        XCTAssertEqual(after.confirmation.evidence.first?.originalPayload, .text(try LedgerText("200ml milk")))
    }

    func testDeclinePreparationEditAndNavigationCancelOutstandingResults() async throws {
        for action in ["decline", "preparation", "leave"] {
            let started = expectation(description: "provider started")
            let returned = expectation(description: "provider returned")
            let remote = HeldFoodEnrichment(started: started, returned: returned)
            let model = try makeModel(remote)
            model.query = "milk"
            model.search()
            await fulfillment(of: [started], timeout: 2)
            switch action {
            case "decline": model.decline()
            case "preparation": model.preparationFilter = .raw
            default: model.stopEnrichment()
            }
            let expected = model.phase
            await remote.release(try remoteMilk())
            await fulfillment(of: [returned], timeout: 2)
            await Task.yield()
            XCTAssertEqual(model.phase, expected, action)
            XCTAssertNil(model.activeEnrichmentStage)
        }
    }

    func testDatabasePreferenceDefaultsOffPersistsAndDoesNotReuseDebugOptIn() throws {
        let suite = "food-search-test-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "foodSearchDeveloperToolsEnabled")
        let preferences = FoodSearchUserDefaultsPreferences(defaults: defaults)
        XCTAssertFalse(preferences.onlineDatabaseEnabled)
        XCTAssertFalse(preferences.geminiEnabled)
        preferences.geminiEnabled = true
        XCTAssertTrue(FoodSearchUserDefaultsPreferences(defaults: defaults).geminiEnabled)
        XCTAssertFalse(preferences.onlineDatabaseEnabled)
        preferences.geminiEnabled = false
        XCTAssertFalse(FoodSearchUserDefaultsPreferences(defaults: defaults).geminiEnabled)
        preferences.onlineDatabaseEnabled = true
        XCTAssertTrue(FoodSearchUserDefaultsPreferences(defaults: defaults).onlineDatabaseEnabled)
        preferences.onlineDatabaseEnabled = false
        XCTAssertFalse(FoodSearchUserDefaultsPreferences(defaults: defaults).onlineDatabaseEnabled)
    }

    func testDatabaseOptInWaitsForNextSearchAndDisableRejectsLateCompletion() async throws {
        let started = expectation(description: "provider started after opt-in")
        let returned = expectation(description: "provider returned after disable")
        let remote = HeldFoodEnrichment(started: started, returned: returned)
        let preferences = InMemorySearchPreferences()
        let model = try GenericFoodSearchViewModel(searcher: CoFIDGenericFoodSearch(ids: RandomLedgerIDGenerator()),
            locale: LedgerText("en_GB"), database: remote, preferences: preferences)
        model.query = "milk"
        model.search()
        XCTAssertNil(model.activeEnrichmentStage)
        let before = model.phase
        model.setOnlineDatabaseEnabled(true)
        XCTAssertTrue(preferences.onlineDatabaseEnabled)
        XCTAssertNil(model.activeEnrichmentStage)
        XCTAssertEqual(model.phase, before)
        model.search()
        await fulfillment(of: [started], timeout: 2)
        model.setOnlineDatabaseEnabled(false)
        XCTAssertFalse(preferences.onlineDatabaseEnabled)
        XCTAssertNil(model.activeEnrichmentStage)
        let disabled = model.phase
        await remote.release(try remoteMilk())
        await fulfillment(of: [returned], timeout: 2)
        await Task.yield()
        XCTAssertEqual(model.phase, disabled)
        let calls = await remote.calls
        XCTAssertEqual(calls, 1)
    }

    func testPersistedOptInCannotEnableAnAbsentProvider() throws {
        let preferences = InMemorySearchPreferences()
        preferences.onlineDatabaseEnabled = true
        let model = try GenericFoodSearchViewModel(searcher: CoFIDGenericFoodSearch(ids: RandomLedgerIDGenerator()),
            locale: LedgerText("en_GB"), preferences: preferences)
        XCTAssertFalse(model.onlineDatabaseAvailable)
        model.query = "milk"
        model.search()
        XCTAssertNil(model.activeEnrichmentStage)
        guard case .results = model.phase else { return XCTFail("Local results remain available") }
    }

    func testLiteralPercentageTravelsThroughUIAndCoordinatorWithoutQuantityPrefill() async throws {
        let finished = expectation(description: "OFF discovery finished")
        let body = try JSONSerialization.data(withJSONObject: ["products": [["code": "3274080005003",
            "product_name": "Acme Total 2%", "brands": "Acme", "quantity": "170 g",
            "categories_tags": ["en:greek-style-yogurts"], "nutrition_data_per": "100g",
            "nutriments": ["proteins_100g": 8, "proteins_unit": "g"]]]])
        let transport = PercentageSearchTransport(body: body)
        let database = try OpenFoodFactsSearch(transport: transport, locale: LedgerText("en_GB"))
        let model = try GenericFoodSearchViewModel(searcher: CoFIDGenericFoodSearch(ids: RandomLedgerIDGenerator()), locale: LedgerText("en_GB"),
            database: database, services: .init(onlineDatabase: .ready, gemini: .disabled))
        model.query = "150g Acme Total 2% Greek yoghurt"
        model.search()
        let subscription = model.$activeEnrichmentStage.dropFirst().sink { if $0 == nil { finished.fulfill() } }
        await fulfillment(of: [finished], timeout: 3)
        subscription.cancel()
        guard case let .results(route) = model.phase else { return XCTFail("Discovery should reach OFF through the real coordinator") }
        XCTAssertEqual(route.matches.count, 1)
        let terms = await transport.terms
        XCTAssertEqual(terms, ["acme total greek yoghurt 2%"])
        XCTAssertEqual(model.parsedQuery?.route, .clarify); XCTAssertNil(model.parsedQuery?.quantity)
        let chosen = try XCTUnwrap(model.confirmation(id: route.matches[0].searchID))
        XCTAssertEqual(chosen.candidates[0].name.value, "Acme Total 2%")
        XCTAssertFalse(FoodConfirmationState(input: chosen).unresolvedIdentity.isEmpty)
    }

    func testGeminiConsentAndValidatedKeyAreBothRequiredAndDisableRejectsLateResult() async throws {
        let started = expectation(description: "Gemini starts only after submitted consent and key")
        let returned = expectation(description: "late Gemini returns")
        let remote = HeldFoodEnrichment(started: started, returned: returned)
        let preferences = InMemorySearchPreferences()
        let model = try GenericFoodSearchViewModel(searcher: CoFIDGenericFoodSearch(ids: RandomLedgerIDGenerator()),
            locale: LedgerText("en_GB"), gemini: remote, preferences: preferences)
        model.query = "milk"
        model.search()
        XCTAssertNil(model.activeEnrichmentStage)
        model.setGeminiEnabled(true)
        model.search()
        XCTAssertNil(model.activeEnrichmentStage)
        model.setGeminiEnabled(false)
        model.setGeminiCredentialReady(true)
        model.search()
        XCTAssertNil(model.activeEnrichmentStage)
        model.setGeminiEnabled(true)
        XCTAssertNil(model.activeEnrichmentStage)
        let before = await remote.calls
        XCTAssertEqual(before, 0)
        model.search()
        await fulfillment(of: [started], timeout: 2)
        model.setGeminiEnabled(false)
        let disabled = model.phase
        await remote.release(try remoteMilk())
        await fulfillment(of: [returned], timeout: 2)
        await Task.yield()
        XCTAssertEqual(model.phase, disabled)
        XCTAssertNil(model.activeEnrichmentStage)
        let calls = await remote.calls
        XCTAssertEqual(calls, 1)
    }

    func testSourceCheckFailureIsVisibleBesidePreservedLocalResultsAndLinks() async throws {
        let started = expectation(description: "source check starts")
        let returned = expectation(description: "source check returned")
        let finished = expectation(description: "partial discovery displayed")
        let remote = HeldFoodEnrichment(started: started, returned: returned)
        let model = try GenericFoodSearchViewModel(searcher: CoFIDGenericFoodSearch(ids: RandomLedgerIDGenerator()),
            locale: LedgerText("en_GB"), gemini: remote, services: .init(onlineDatabase: .disabled, gemini: .ready))
        model.query = "milk"; model.search()
        guard case let .results(before) = model.phase else { return XCTFail() }
        let subscription = model.$activeEnrichmentStage.dropFirst().sink { if $0 == nil { finished.fulfill() } }
        await fulfillment(of: [started], timeout: 2)
        guard case let .confirmation(other) = try remoteMilk() else { return XCTFail() }
        let discovery = FoodWebDiscoveryResult(leads: [.init(title: "Source", url: URL(string: "https://source.example.com/food")!)], searchSuggestionsHTML: "<a>Suggestion</a>")
        await remote.release(.noResult(GenericFoodNoResultRoute(evidence: other.confirmation.evidence[0],
            sourceDiscovery: discovery, sourceReviewFailure: .unsupportedSource)))
        await fulfillment(of: [returned, finished], timeout: 2); subscription.cancel()
        guard case let .results(after) = model.phase else { return XCTFail() }
        XCTAssertEqual(after.matches, before.matches)
        XCTAssertEqual(model.sourceDiscovery, discovery)
        XCTAssertTrue(model.sourceReviewMessage?.contains("not supported") == true)
    }


    func testSearchStatusTracksActualStagesAndUniqueAdditionsThroughCompletion() async throws {
        let dbStarted = expectation(description: "online starts")
        let dbReturned = expectation(description: "online returns")
        let webStarted = expectation(description: "web starts")
        let webReturned = expectation(description: "web returns")
        let db = HeldFoodEnrichment(started: dbStarted, returned: dbReturned)
        let web = HeldFoodEnrichment(started: webStarted, returned: webReturned)
        let model = try GenericFoodSearchViewModel(searcher: CoFIDGenericFoodSearch(ids: RandomLedgerIDGenerator()),
            locale: LedgerText("en_GB"), database: db, gemini: web,
            services: .init(onlineDatabase: .ready, gemini: .ready), assessment: UXNeedsMoreEvidence())
        model.query = "milk"; model.search()
        await fulfillment(of: [dbStarted], timeout: 2)
        XCTAssertEqual(model.searchStatus?.title, "Searching Open Food Facts…")
        XCTAssertEqual(model.stageReports.map(\.stage), [.local])
        let localIDs = model.stageReports[0].addedCandidateIDs
        XCTAssertFalse(localIDs.isEmpty)
        let online = try remoteMilk()
        await db.release(online)
        await fulfillment(of: [dbReturned, webStarted], timeout: 2)
        XCTAssertEqual(model.searchStatus?.title, "Checking web nutrition with Gemini…")
        XCTAssertFalse(model.onlineAddedIDs.isEmpty)
        let added = model.onlineAddedIDs
        await web.release(online)
        await fulfillment(of: [webReturned], timeout: 2)
        for _ in 0..<20 where model.activeEnrichmentStage != nil { await Task.yield() }
        XCTAssertNil(model.activeEnrichmentStage)
        XCTAssertEqual(model.stageReports.map(\.stage), [.local, .onlineDatabase, .gemini])
        XCTAssertEqual(model.stageReports[2].addedCandidateIDs, [])
        XCTAssertEqual(model.onlineAddedIDs, added, "Duplicate source rows are not new matches")
        XCTAssertEqual(model.searchStatus?.title, "Search finished")
        XCTAssertTrue(model.searchStatus?.summary.contains("No extra matches from Gemini") == true)
        guard case let .results(route) = model.phase else { return XCTFail() }
        XCTAssertEqual(Array(route.matches.prefix(localIDs.count)).map(\.searchID), localIDs)
    }

    func testLocalOnlyStatusDoesNotClaimAnOnlineSearchAndEditClearsHistory() throws {
        let model = try GenericFoodSearchViewModel(searcher: CoFIDGenericFoodSearch(ids: RandomLedgerIDGenerator()), locale: LedgerText("en_GB"))
        model.query = "milk"; model.search()
        XCTAssertEqual(model.stageReports.map(\.stage), [.local])
        XCTAssertEqual(model.searchStatus?.title, "Search finished")
        XCTAssertTrue(model.searchStatus?.details.contains("Open Food Facts: Off") == true)
        XCTAssertTrue(model.searchStatus?.details.contains("Gemini: Off") == true)
        XCTAssertEqual(model.onlineAddedIDs, [])
        model.query = "rice"
        XCTAssertNil(model.searchStatus)
        XCTAssertEqual(model.stageReports, [])
        XCTAssertEqual(model.phase, .idle)
    }

    func testStopRetainsRealSearchHistoryAndRejectsLateStatusAndRows() async throws {
        let started = expectation(description: "source starts")
        let returned = expectation(description: "source returns")
        let remote = HeldFoodEnrichment(started: started, returned: returned)
        let model = try makeModel(remote)
        model.query = "milk"; model.search()
        await fulfillment(of: [started], timeout: 2)
        let rows = model.phase
        model.stopEnrichment()
        XCTAssertEqual(model.searchStatus?.title, "Search stopped")
        XCTAssertTrue(model.searchStatus?.details.contains("Open Food Facts: Stopped") == true)
        let status = model.searchStatus
        await remote.release(try remoteMilk())
        await fulfillment(of: [returned], timeout: 2); await Task.yield()
        XCTAssertEqual(model.phase, rows)
        XCTAssertEqual(model.searchStatus, status)
        XCTAssertEqual(model.onlineAddedIDs, [])
    }

    func testUnavailableDatabaseAndUnsupportedWebNutritionStayDistinct() async throws {
        let started = expectation(description: "web starts after unavailable online database")
        let returned = expectation(description: "unsupported source returns")
        let web = HeldFoodEnrichment(started: started, returned: returned)
        let model = try GenericFoodSearchViewModel(searcher: CoFIDGenericFoodSearch(ids: RandomLedgerIDGenerator()),
            locale: LedgerText("en_GB"), database: UXUnavailableSource(), gemini: web,
            services: .init(onlineDatabase: .ready, gemini: .ready), assessment: UXNeedsMoreEvidence())
        model.query = "milk"; model.search()
        await fulfillment(of: [started], timeout: 2)
        XCTAssertEqual(model.searchStatus?.title, "Checking web nutrition with Gemini…")
        guard case let .confirmation(other) = try remoteMilk() else { return XCTFail() }
        let discovery = FoodWebDiscoveryResult(leads: [.init(title: "Nutrition source", url: URL(string: "https://source.example.com/milk")!)], searchSuggestionsHTML: nil)
        await web.release(.noResult(GenericFoodNoResultRoute(evidence: other.confirmation.evidence[0],
            sourceDiscovery: discovery, sourceReviewFailure: .unsupportedSource)))
        await fulfillment(of: [returned], timeout: 2)
        for _ in 0..<20 where model.activeEnrichmentStage != nil { await Task.yield() }
        XCTAssertEqual(model.searchStatus?.title, "Search finished")
        XCTAssertTrue(model.searchStatus?.summary.contains("Open Food Facts unavailable") == true)
        XCTAssertTrue(model.searchStatus?.details.contains("Gemini: Source found; nutrition format unsupported") == true)
        XCTAssertEqual(model.sourceDiscovery, discovery)
        XCTAssertEqual(model.onlineAddedIDs, [])
    }

    private func makeModel(_ remote: HeldFoodEnrichment) throws -> GenericFoodSearchViewModel {
        try GenericFoodSearchViewModel(searcher: CoFIDGenericFoodSearch(ids: RandomLedgerIDGenerator()), locale: LedgerText("en_GB"),
            database: remote, services: .init(onlineDatabase: .ready, gemini: .disabled))
    }
    private func remoteMilk() throws -> GenericFoodSearchOutcome {
        try USDAGenericFoodSearch(ids: RandomLedgerIDGenerator()).search(GenericFoodSearchRequest(text: LedgerText("200ml milk"),
            capturedAt: Date(timeIntervalSince1970: 1_700_000_000), locale: LedgerText("en_GB")))
    }
}

private actor HeldFoodEnrichment: FoodSearchEnriching {
    var calls = 0
    let started: XCTestExpectation
    let returned: XCTestExpectation
    private var continuation: CheckedContinuation<GenericFoodSearchOutcome, Never>?
    init(started: XCTestExpectation, returned: XCTestExpectation) { self.started = started; self.returned = returned }
    func enrich(_ query: FoodSearchRemoteQuery) async throws -> GenericFoodSearchOutcome {
        calls += 1
        defer { returned.fulfill() }
        return await withCheckedContinuation { continuation = $0; started.fulfill() }
    }
    func release(_ outcome: GenericFoodSearchOutcome) { continuation?.resume(returning: outcome); continuation = nil }
}

@MainActor
private final class InMemorySearchPreferences: FoodSearchPreferences {
    var onlineDatabaseEnabled = false
    var geminiEnabled = false
}

private actor PercentageSearchTransport: OFFSearchTransport {
    let body: Data
    var terms: [String] = []
    init(body: Data) { self.body = body }
    func search(foodTerms: String) async throws -> OFFProductResponse {
        terms.append(foodTerms); return .init(status: 200, body: body)
    }
}

private struct RejectedPreparationLocalSearch: GenericFoodSearching {
    func search(_ request: GenericFoodSearchRequest) throws -> GenericFoodSearchOutcome {
        XCTFail("Conflicting preparation must stop before local search")
        throw FoodSearchEnrichmentError.invalidQuery
    }
}
private actor PreparationGateEnrichment: FoodSearchEnriching {
    var calls = 0
    func enrich(_ query: FoodSearchRemoteQuery) throws -> GenericFoodSearchOutcome {
        calls += 1
        throw FoodSearchEnrichmentError.unavailable
    }
}


private struct UXNeedsMoreEvidence: FoodSearchCoverageAssessing {
    func assess(_ outcome: GenericFoodSearchOutcome, for request: GenericFoodSearchRequest) -> [FoodSearchCandidateCoverage] { [] }
}

private struct UXUnavailableSource: FoodSearchEnriching {
    func enrich(_ query: FoodSearchRemoteQuery) async throws -> GenericFoodSearchOutcome { throw FoodSearchEnrichmentError.unavailable }
}
