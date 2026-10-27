import Foundation
import FoodGenericSearch
import FoodLedgerApplication
import FoodLedgerDomain
import FoodLedgerPresentation
import FoodLedgerTestSupport
import XCTest

/// Phase 3 (#196) presentation: result-row formatting (separate from the application's structure
/// tests), recent-row text, search view-model orchestration and egress (contract test 13).
@MainActor
final class AddFoodSearchPresentationTests: XCTestCase {
    // MARK: Formatter golden strings

    func testResultRowFormatterGoldenStrings() throws {
        let rows: [(FoodSearchResultSummary, String)] = [
            (.init(family: .ukReference, preparation: .cooked, energy: .forAmount(kcal: 248, quantity: try PositiveQuantity(value: 150, unit: .grams))),
             "UK reference · cooked · 248 kcal for 150 g"),
            (.init(family: .packagedProduct, preparation: .unknown, energy: .basisOnly(.per100Grams)),
             "Packaged product · per 100 g on label"),
            (.init(family: .usReference, preparation: .raw, energy: .basisOnly(.per100Grams)), "US reference · raw · per 100 g"),
            (.init(family: .taiwanReference, preparation: .named, energy: .forAmount(kcal: 300, quantity: try PositiveQuantity(value: 200, unit: .millilitres))),
             "Taiwan reference · 300 kcal for 200 mL"),
            (.init(family: .yourFoods, preparation: .asSold, energy: .basisOnly(.named(try LedgerText("bowl"), try PositiveQuantity(value: 1, unit: .count)))),
             "Your foods · as sold · per bowl"),
            (.init(family: .webSource, preparation: .unknown, energy: .basisOnly(.unknown)), "Web source · basis not specified"),
            (.init(family: .otherSource, preparation: .unknown, energy: .basisOnly(.per100Grams)), "Other source · per 100 g")
        ]
        for (summary, expected) in rows { XCTAssertEqual(FoodSearchResultText.summaryLine(summary), expected) }
        XCTAssertEqual(FoodSearchResultText.amount(.init(value: 150, unit: "g")), "150 g")
        XCTAssertEqual(FoodSearchResultText.amount(.init(value: 250, unit: "ml")), "250 mL")
        XCTAssertEqual(FoodSearchResultText.amount(.init(value: 1, unit: "count")), "1 piece")
        XCTAssertEqual(FoodSearchResultText.amount(.init(value: 2, unit: "count")), "2 pieces")
    }

    /// #308: a row without an amount states the source's energy per 100 g or per 100 mL; an
    /// unknown energy shows the basis alone and never 0.
    func testRowsStateEnergyPerBasisAndNeverZeroForUnknown() throws {
        XCTAssertEqual(FoodSearchResultText.summaryLine(.init(family: .usReference, preparation: .raw,
            energy: .basisOnly(.per100Grams), basisEnergyKcal: 89)), "US reference · raw · 89 kcal per 100 g")
        XCTAssertEqual(FoodSearchResultText.summaryLine(.init(family: .packagedProduct, preparation: .unknown,
            energy: .basisOnly(.per100Millilitres), basisEnergyKcal: 42)), "Packaged product · 42 kcal per 100 mL on label")
        XCTAssertEqual(FoodSearchResultText.summaryLine(.init(family: .ukReference, preparation: .unknown,
            energy: .basisOnly(.per100Millilitres), basisEnergyKcal: 0)), "UK reference · 0 kcal per 100 mL", "a stated zero stays zero")
        XCTAssertEqual(FoodSearchResultText.summaryLine(.init(family: .ukReference, preparation: .unknown,
            energy: .basisOnly(.per100Grams), basisEnergyKcal: nil)), "UK reference · per 100 g", "unknown energy shows no figure")
        let model = try GenericFoodSearchViewModel(searcher: CoFIDGenericFoodSearch(ids: RandomLedgerIDGenerator()), locale: LedgerText("en_GB"))
        model.query = "banana"; model.search()
        let rows = try model.bestMatches.map { FoodSearchResultText.summaryLine(try XCTUnwrap(model.summary(for: $0))) }
        XCTAssertFalse(rows.isEmpty)
        XCTAssertTrue(rows.contains { $0.contains(" kcal per 100 g") }, "\(rows)")
        XCTAssertFalse(rows.contains { $0.contains(" 0 kcal") }, "\(rows)")
    }

    /// #308: "Best matches" holds close name matches; the rest keep their order under "Other matches".
    func testBestMatchesKeepCloseNameMatchesAndTheRestFollowInOrder() throws {
        func match(_ name: String, exact: Bool = false) throws -> GenericFoodMatch {
            let base = try XCTUnwrap(try { () -> GenericFoodMatch? in
                let model = try GenericFoodSearchViewModel(searcher: CoFIDGenericFoodSearch(ids: RandomLedgerIDGenerator()), locale: LedgerText("en_GB"))
                model.query = "banana"; model.search()
                return model.bestMatches.first
            }())
            let candidate = try PopulatedFoodCandidate(candidate: base.candidate.candidate, name: LedgerText(name), brand: nil, variant: nil,
                                                       barcode: nil, itemClass: base.candidate.itemClass)
            return GenericFoodMatch(candidate: candidate, isExactName: exact)
        }
        typealias M = GenericFoodSearchViewModel
        XCTAssertTrue(M.isCloseNameMatch(try match("Bananas, raw"), food: "banana"))
        XCTAssertTrue(M.isCloseNameMatch(try match("Bananas, dehydrated, or banana powder"), food: "banana"))
        XCTAssertTrue(M.isCloseNameMatch(try match("Heinz Baked Beans"), food: "baked beans"))
        XCTAssertTrue(M.isCloseNameMatch(try match("Yogurt, Greek, plain"), food: "greek yoghurt"))
        XCTAssertTrue(M.isCloseNameMatch(try match("Plantain chips", exact: true), food: "banana"), "an exact name is always close")
        XCTAssertFalse(M.isCloseNameMatch(try match("Babyfood, cereal, oatmeal, with bananas"), food: "banana"))
        XCTAssertFalse(M.isCloseNameMatch(try match("Bread, banana"), food: "banana"))

        let model = try GenericFoodSearchViewModel(searcher: CoFIDGenericFoodSearch(ids: RandomLedgerIDGenerator()), locale: LedgerText("en_GB"))
        model.query = "banana"; model.search()
        let food = model.parsedQuery?.food ?? model.query
        XCTAssertFalse(model.closeMatches.isEmpty)
        XCTAssertTrue(model.closeMatches.allSatisfy { M.isCloseNameMatch($0, food: food) })
        XCTAssertTrue(model.otherMatches.allSatisfy { !M.isCloseNameMatch($0, food: food) })
        XCTAssertEqual(Set((model.closeMatches + model.otherMatches).map(\.searchID)), Set(model.bestMatches.map(\.searchID)))
        let order = model.bestMatches.map(\.searchID)
        XCTAssertEqual(model.closeMatches.map(\.searchID), order.filter { id in model.closeMatches.contains { $0.searchID == id } },
                       "grouping keeps the ranked order")
    }

    /// #308: Confirm names a generic estimate's source with the search row's words.
    func testConfirmSourceNameMatchesTheSearchRow() {
        XCTAssertEqual(FoodSearchResultText.confirmSourceName(family: .usReference, isGenericEstimate: true), "US reference · estimate")
        XCTAssertEqual(FoodSearchResultText.confirmSourceName(family: .ukReference, isGenericEstimate: true), "UK reference · estimate")
        XCTAssertEqual(FoodSearchResultText.confirmSourceName(family: .otherSource, isGenericEstimate: true), "Generic food estimate")
        XCTAssertNil(FoodSearchResultText.confirmSourceName(family: .usReference, isGenericEstimate: false))
        XCTAssertTrue(FoodSearchResultText.confirmSourceName(family: .usReference, isGenericEstimate: true)!
            .hasPrefix(FoodSearchResultText.family(.usReference)))
    }

    /// #308: at accessibility sizes the search field keeps a prompt that scales, the chips stack
    /// so words wrap whole, and screen titles move inline instead of truncating.
    func testAccessibilitySizesKeepPromptChipsAndTitlesWhole() {
        XCTAssertEqual(FoodSearchFieldText.prompt(example: "2 scrambled eggs", at: .large), "Food and amount, e.g. 2 scrambled eggs")
        XCTAssertEqual(FoodSearchFieldText.prompt(example: "2 scrambled eggs", at: .accessibility5), "Food and amount")
        XCTAssertEqual(FoodSearchFieldText.prompt(example: "x", at: .accessibility1), FoodSearchFieldText.shortPrompt)
        XCTAssertFalse(FoodSearchFieldText.stacksChips(at: .xxxLarge))
        XCTAssertTrue(FoodSearchFieldText.stacksChips(at: .accessibility1))
        XCTAssertFalse(AccessibleNavigationTitle.usesInlineTitle(at: .xxxLarge))
        XCTAssertTrue(AccessibleNavigationTitle.usesInlineTitle(at: .accessibility5))
        XCTAssertGreaterThan(AccessibleNavigationTitle.inlineLineLimit, 1)
    }

    /// #315: at accessibility sizes the query wraps instead of truncating, route rows put the
    /// icon above the title and favourite rows give the name the full width.
    func testAccessibilitySizesWrapTheQueryAndKeepRowTitlesWhole() {
        XCTAssertFalse(FoodSearchFieldText.wrapsQuery(at: .xxxLarge), "standard sizes keep the one-line field")
        XCTAssertTrue(FoodSearchFieldText.wrapsQuery(at: .accessibility5))
        XCTAssertGreaterThan(FoodSearchFieldText.wrappedQueryLineLimit.upperBound, 1)
        XCTAssertFalse(RouteRowLabel.stacks(at: .xxxLarge))
        XCTAssertTrue(RouteRowLabel.stacks(at: .accessibility1))
        XCTAssertFalse(FavouritesView.rowHidesChevron(at: .large))
        XCTAssertTrue(FavouritesView.rowHidesChevron(at: .accessibility5))
        XCTAssertTrue(AddFoodRecentRowText.stacks(at: .accessibility5), "quick-add favourites stack like Recent")
    }

    /// #315: a wrapping field takes Return as a line break; the one-line query submits instead.
    func testALineBreakInTheQuerySubmitsTheOneLineText() {
        XCTAssertNil(FoodSearchFieldText.submittedQuery("3 pieces banana"), "no line break, no submission")
        XCTAssertEqual(FoodSearchFieldText.submittedQuery("3 pieces banana\n"), "3 pieces banana")
        XCTAssertEqual(FoodSearchFieldText.submittedQuery("3 pieces\nbanana"), "3 pieces banana", "pasted lines join with a space")
        XCTAssertEqual(FoodSearchFieldText.submittedQuery("  2 eggs \r\n\n toast "), "2 eggs toast")
        XCTAssertEqual(FoodSearchFieldText.submittedQuery("\n"), "", "an empty query stays empty; Search rejects it")
    }

    func testConfirmAmountTextHasNoTrailingZeroAndRoundTrips() {
        XCTAssertEqual(FoodAmountTextParser.editableText(150), "150")
        XCTAssertEqual(FoodAmountTextParser.editableText(1500), "1500")
        XCTAssertEqual(FoodAmountTextParser.editableText(0.5), "0.5")
        XCTAssertEqual(FoodAmountTextParser.editableText(150.25), "150.25")
        for value in [150.0, 1500, 0.5, 150.25, 12_345.5] {
            XCTAssertEqual(FoodAmountTextParser.parse(FoodAmountTextParser.editableText(value)), value)
        }
        XCTAssertEqual(FoodSearchResultText.preparationChip(.cooked), "Cooked")
        XCTAssertEqual(FoodSearchResultText.preparationChip(.raw), "Raw")
        XCTAssertEqual(FoodSearchResultText.preparationChip(nil), "Any preparation")
    }

    func testSourceFamilyIsAClosedListWithANeutralFallback() {
        XCTAssertEqual(FoodSearchResultSummary.family("physical_package"), .yourFoods)
        XCTAssertEqual(FoodSearchResultSummary.family("cofid-2021", recordID: "personal-library:abc"), .yourFoods)
        XCTAssertEqual(FoodSearchResultSummary.family("phe-npm-2018-annex-a"), .otherSource)
        XCTAssertEqual(FoodSearchResultSummary.family(""), .otherSource)
        XCTAssertEqual(FoodSearchResultSummary.family("cofid-2021"), .ukReference)
        XCTAssertEqual(FoodSearchResultSummary.family("open-food-facts"), .packagedProduct)
    }

    /// Opening and closing the amount editor must not change the amount (no grouping separators,
    /// one locale-aware style for display and parsing).
    func testAmountEditorTextRoundTripsInEnglishAndGermanLocales() {
        for identifier in ["en_GB", "de_DE"] {
            let locale = Locale(identifier: identifier)
            for value in [1500.0, 12_345.0, 0.5, 150.25] {
                let text = FoodSearchAmountText.text(value, locale: locale)
                XCTAssertFalse(text.contains(identifier == "en_GB" ? "," : "."), "\(identifier) \(text)")
                XCTAssertEqual(FoodSearchAmountText.parse(text, locale: locale), value, "\(identifier) \(text)")
            }
        }
        XCTAssertEqual(FoodSearchAmountText.text(1500, locale: Locale(identifier: "en_GB")), "1500")
        XCTAssertEqual(FoodSearchAmountText.parse("1,5", locale: Locale(identifier: "de_DE")), 1.5)
        XCTAssertNil(FoodSearchAmountText.parse("0", locale: Locale(identifier: "en_GB")))
        XCTAssertNil(FoodSearchAmountText.parse("", locale: Locale(identifier: "en_GB")))
    }

    func testRecentRowTextUsesLastAmountDayEstimateAndRoundedEnergy() throws {
        var london = Calendar(identifier: .gregorian); london.timeZone = try XCTUnwrap(TimeZone(identifier: "Europe/London"))
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-10-11T12:00:00Z"))
        func item(_ at: String, amount: PositiveQuantity, energy: Double?, estimate: Bool) throws -> FoodRecentRelogItem {
            FoodRecentRelogItem(item: FoodRecentItem(logItemID: try LogItemID(UUID().uuidString.lowercased()),
                sourceReleaseID: try ExternalIdentifier("cofid-2021"), recordID: try ExternalIdentifier("rec"),
                occurredAt: try XCTUnwrap(ISO8601DateFormatter().date(from: at)), lastAmount: amount, energyKcal: energy),
                name: "Chicken breast, grilled", isEstimate: estimate)
        }
        let yesterday = AddFoodRecentRowText(try item("2026-10-10T18:00:00Z", amount: try PositiveQuantity(value: 150, unit: .grams), energy: 247.5, estimate: false), now: now, calendar: london)
        XCTAssertEqual(yesterday.title, "Chicken breast, grilled")
        XCTAssertEqual(yesterday.detail, "Last: 150 g · yesterday")
        XCTAssertEqual(yesterday.energy, "248 kcal")
        let today = AddFoodRecentRowText(try item("2026-10-11T07:00:00Z", amount: try PositiveQuantity(value: 1, unit: .count), energy: nil, estimate: true), now: now, calendar: london)
        XCTAssertEqual(today.detail, "Estimate · Last: 1 piece · today")
        XCTAssertNil(today.energy, "Unknown energy shows no figure")
        let older = AddFoodRecentRowText(try item("2026-10-09T07:00:00Z", amount: try PositiveQuantity(value: 300, unit: .millilitres), energy: 105, estimate: false), now: now, calendar: london)
        XCTAssertTrue(older.detail.hasPrefix("Last: 300 mL · "))
        XCTAssertTrue(older.detail.contains("9"))
        // One kcal format everywhere: grouped, no decimals, as the Food Log row shows it.
        let large = AddFoodRecentRowText(try item("2026-10-10T18:00:00Z", amount: try PositiveQuantity(value: 2250.5, unit: .grams), energy: 2633.4, estimate: false), now: now, calendar: london)
        XCTAssertEqual(large.energy, "\(FoodDisplayNumber.kcal(2633.4)) kcal")
        XCTAssertEqual(large.energy, "\(FoodLogText.kcal(2633.4)) kcal")
        // A positive amount is never shown as 0.
        let crumb = AddFoodRecentRowText(try item("2026-10-10T18:00:00Z", amount: try PositiveQuantity(value: 0.004, unit: .grams), energy: 0.1, estimate: false), now: now, calendar: london)
        XCTAssertTrue(crumb.detail.hasPrefix("Last: less than \(FoodDisplayNumber.amount(0.1)) g · "), crumb.detail)
    }

    func testSharedDisplayNumberGroupsKcalAndRoundsAmounts() throws {
        let gb = Locale(identifier: "en_GB")
        XCTAssertEqual(FoodDisplayNumber.kcal(2633.4, locale: gb), "2,633")
        XCTAssertEqual(FoodDisplayNumber.kcal(259.5, locale: gb), "260")
        XCTAssertEqual(FoodDisplayNumber.kcal(3.04, locale: gb), "3")
        XCTAssertEqual(FoodDisplayNumber.amount(6.44, locale: gb), "6.4")
        XCTAssertEqual(FoodDisplayNumber.amount(60.95, locale: gb), "61")
        XCTAssertEqual(FoodDisplayNumber.amount(2250.5, locale: gb), "2,250.5")
        XCTAssertEqual(FoodLogText.kcal(2633.4, locale: gb), FoodDisplayNumber.kcal(2633.4, locale: gb))
        XCTAssertEqual(FoodDisplayNumber.energy(0.4, locale: gb), "less than 1 kcal")
        XCTAssertEqual(FoodDisplayNumber.energy(0, locale: gb), "0 kcal", "a real zero stays zero")
        XCTAssertEqual(FoodDisplayNumber.quantity(0.04, unit: "g", locale: gb), "less than 0.1 g")
        XCTAssertEqual(FoodDisplayNumber.quantity(1.25, unit: "mL", locale: gb), "1.2 mL")
        let tinySearch = FoodSearchResultSummary(family: .ukReference, preparation: .unknown,
            energy: .forAmount(kcal: 0, quantity: try PositiveQuantity(value: 0.004, unit: .grams)))
        XCTAssertEqual(FoodSearchResultText.summaryLine(tinySearch),
                       "UK reference · 0 kcal for less than \(FoodDisplayNumber.amount(0.1)) g")
        let summary = FoodSearchResultSummary(family: .ukReference, preparation: .cooked,
            energy: .forAmount(kcal: 2633, quantity: try PositiveQuantity(value: 1200, unit: .grams)))
        XCTAssertEqual(FoodSearchResultText.summaryLine(summary),
                       "UK reference · cooked · \(FoodDisplayNumber.kcal(2633)) kcal for \(FoodDisplayNumber.amount(1200)) g")
    }

    // MARK: Search view model

    func testAmountChipOverridesEnergyAndHandoffAndQueryEditClearsIt() throws {
        let model = try GenericFoodSearchViewModel(searcher: CoFIDGenericFoodSearch(ids: RandomLedgerIDGenerator()), locale: LedgerText("en_GB"))
        model.query = "100 g rice"; model.search()
        let match = try XCTUnwrap(model.bestMatches.first)
        XCTAssertEqual(model.effectiveAmount, .init(value: 100, unit: "g"))
        guard case let .forAmount(_, quantity) = try XCTUnwrap(model.summary(for: match)).energy else { return XCTFail("energy for 100 g") }
        XCTAssertEqual(quantity.value, 100)
        model.amountOverride = .init(value: 250, unit: "g")
        XCTAssertEqual(model.effectiveAmount, .init(value: 250, unit: "g"))
        guard case let .forAmount(_, edited) = try XCTUnwrap(model.summary(for: match)).energy else { return XCTFail("energy for 250 g") }
        XCTAssertEqual(edited.value, 250)
        XCTAssertNotEqual(model.phase, .idle, "Editing the amount does not re-run or discard the search")
        model.query = "rice"
        XCTAssertNil(model.amountOverride)
        XCTAssertEqual(model.phase, .idle)
    }

    func testPreparationChipConstrainsBeforeRankingAndRowsCarryNoIdentifiers() throws {
        let local = try CompositeGenericFoodSearch(sources: [
            CoFIDGenericFoodSearch(ids: RandomLedgerIDGenerator()), USDAGenericFoodSearch(ids: RandomLedgerIDGenerator())
        ], ids: RandomLedgerIDGenerator())
        let model = try GenericFoodSearchViewModel(searcher: local, locale: LedgerText("en_GB"))
        model.query = "175g quinoa"
        model.preparationFilter = .cooked; model.search()
        XCTAssertEqual(model.effectivePreparation, .cooked)
        XCTAssertFalse(model.bestMatches.isEmpty)
        for match in model.bestMatches {
            XCTAssertNotEqual(match.candidate.candidate.identity.preparation.kind, .raw)
            let line = FoodSearchResultText.summaryLine(try XCTUnwrap(model.summary(for: match)))
            XCTAssertFalse(line.contains(match.candidate.candidate.recordID.value))
            XCTAssertFalse(line.lowercased().contains("score"))
        }
        let usda = try XCTUnwrap(model.bestMatches.first { $0.candidate.candidate.recordID.value.hasSuffix(":fdc:168917") })
        XCTAssertEqual(FoodSearchResultText.summaryLine(try XCTUnwrap(model.summary(for: usda))), "US reference · cooked · 210 kcal for 175 g")
        XCTAssertTrue(model.diagnosticLines.contains { $0.hasPrefix("Lexical score") } || model.diagnosticLines.contains { $0.hasPrefix("Source: ") },
                      "Scores and identifiers live in Developer tools only")
        XCTAssertTrue(model.diagnosticLines.contains { $0.hasPrefix("Record: ") })
    }

    func testSearchSelectionUsesTheSharedChosenCandidateSnapshot() throws {
        let model = try GenericFoodSearchViewModel(searcher: CoFIDGenericFoodSearch(ids: RandomLedgerIDGenerator()), locale: LedgerText("en_GB"))
        model.query = "150g grilled chicken breast"; model.search()
        guard case let .results(route) = model.phase else { return XCTFail("results") }
        for index in route.matches.indices.prefix(4) {
            XCTAssertEqual(model.confirmation(at: index), route.choosing(index))
        }
    }

    // MARK: 13. Egress

    func test13NoCallsWhileEditingRestoringPreparingSavingOrRelogging() async throws {
        let remote = CountingEnrichment()
        let search = try GenericFoodSearchViewModel(searcher: CoFIDGenericFoodSearch(ids: RandomLedgerIDGenerator()),
            locale: LedgerText("en_GB"), database: remote, services: .init(onlineDatabase: .ready, gemini: .disabled))
        for text in ["r", "ri", "ric", "rice", "150 g rice"] { search.query = text }
        search.preparationFilter = .cooked
        search.amountOverride = .init(value: 200, unit: "g")
        // A restored Search results screen starts with an empty field and no search.
        let restored = try GenericFoodSearchViewModel(searcher: CoFIDGenericFoodSearch(ids: RandomLedgerIDGenerator()),
            locale: LedgerText("en_GB"), database: remote, services: .init(onlineDatabase: .ready, gemini: .disabled))
        XCTAssertEqual(restored.phase, .idle)
        await Task.yield()
        let searchCalls = await remote.calls
        XCTAssertEqual(searchCalls, 0)

        let reviewer = CountingProposalReview()
        let review = GenericFoodProposalReviewViewModel(reviewer: reviewer, credentials: CountingCredentials(),
            confirmation: ReviewedFoodProposalConfirmation(ids: RandomLedgerIDGenerator(), clock: SystemLedgerClock(),
                encoder: FoundationCanonicalJSONEncoder(), digester: SHA256Digester()), locale: try LedgerText("en_GB"))
        for text in ["c", "chicken", "chicken caesar wrap"] { review.foodTerms = text }
        review.market = .unitedKingdom
        review.sourceAddress = "https://example.com/wrap"
        let reviewCalls = await reviewer.calls
        XCTAssertEqual(reviewCalls, 0)

        // Preparing, saving and re-logging have no transport at all; with the fakes above idle,
        // a complete save and re-log on the in-memory store must leave every counter at zero.
        let store = InMemoryFoodLedgerStore(encoder: FoundationCanonicalJSONEncoder(), digester: SHA256Digester())
        let ledger = FoodLedgerService(actorID: try ActorID("00000000-0000-0000-0000-000000000900"), committer: store,
            clock: SystemLedgerClock(), encoder: FoundationCanonicalJSONEncoder(), digester: SHA256Digester())
        let confirmations = FoodConfirmationService(ledger: ledger, reader: store, clock: SystemLedgerClock(),
            ids: RandomLedgerIDGenerator(), digester: SHA256Digester())
        search.query = "rice"; search.search()
        for _ in 0..<5 { await Task.yield() }
        let afterExplicitSearch = await remote.calls
        XCTAssertLessThanOrEqual(afterExplicitSearch, 1, "At most the one explicit search reaches the online database")
        let input = try XCTUnwrap(search.confirmation(at: 0))
        var state = FoodConfirmationState(input: input, prefillSourceQuantity: false)
        FoodConfirmationReducer.reduce(state: &state, action: .setQuantity(100, .grams))
        state.answerPendingDifferences(); FoodConfirmationReducer.reduce(state: &state, action: .accept)
        let saved = try confirmations.save(state, operationID: try OperationID(UUID().uuidString.lowercased()))
        var relog = try XCTUnwrap(confirmations.relogState(logItemID: saved.logItem.logItemID))
        relog.answerPendingDifferences(); FoodConfirmationReducer.reduce(state: &relog, action: .accept)
        _ = try confirmations.save(relog, operationID: try OperationID(UUID().uuidString.lowercased()))
        await Task.yield()
        let finalSearchCalls = await remote.calls, finalReviewCalls = await reviewer.calls
        XCTAssertEqual(finalSearchCalls, afterExplicitSearch, "Saving and re-logging make no request")
        XCTAssertEqual(finalReviewCalls, 0)
    }
}

private actor CountingEnrichment: FoodSearchEnriching {
    var calls = 0
    func enrich(_ query: FoodSearchRemoteQuery) async throws -> GenericFoodSearchOutcome {
        calls += 1
        throw FoodSearchEnrichmentError.unavailable
    }
}

private actor CountingProposalReview: GenericFoodProposalReviewing {
    var calls = 0
    func review(foodTerms: String, sourceURL: URL?, key: String) async throws -> GenericFoodProposalReview {
        calls += 1
        throw FoodWebDiscoveryError.requestRejected
    }
}

@MainActor
private final class CountingCredentials: FoodWebCredentialAuthorizing {
    var reads = 0
    func credentialForRequest() throws -> FoodWebRequestCredential { reads += 1; return .init(key: "synthetic-key-never-sent", generation: 0) }
    func isCurrent(_ credential: FoodWebRequestCredential) -> Bool { true }
    func reject(_ credential: FoodWebRequestCredential) {}
}
