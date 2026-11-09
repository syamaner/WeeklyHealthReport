import FoodGenericSearch
import FoodLedgerApplication
import FoodLedgerDomain
import FoodLedgerTestSupport
import XCTest

final class CoFIDGenericFoodSearchTests: XCTestCase {
    /// #196 tap-through: the list route compared a later choice with the first candidate's identity
    /// and asked about skin for "grilled without skin". Both routes now snapshot the chosen candidate,
    /// so the same food and choice yield identical differences and requirements.
    func testListAndSearchRoutesGiveIdenticalRequirementsForTheSameChoice() throws {
        let ids = SequenceIDs()
        let importer = FoodListImportService(searcher: try CoFIDGenericFoodSearch(ids: ids), ids: ids)
        let line = try XCTUnwrap(FoodListParser.parse("150g grilled chicken breast").first)
        let draft = FoodListLineDraft(parsed: line, operationID: try ids.makeID(OperationTag.self),
            evidenceID: try ids.makeID(EvidenceTag.self))
        guard case let .candidates(route) = try importer.search(draft, at: FixedClock().now(), locale: LedgerText("en_GB")) else {
            return XCTFail("Expected list candidates")
        }
        XCTAssertGreaterThan(route.matches.count, 1)
        var sawSkinless = false
        for index in route.matches.indices {
            let list = try importer.confirmation(for: draft, route: route, candidateIndex: index)
            var search = FoodConfirmationState(input: try XCTUnwrap(route.choosing(index)), prefillSourceQuantity: false)
            search.quantity = list.quantity
            XCTAssertEqual(list.selectedCandidate, search.selectedCandidate, "\(index)")
            XCTAssertEqual(list.materialDifferences, search.materialDifferences, "\(index)")
            XCTAssertEqual(FoodLogPolicy.requirements(list, now: FixedClock().now(), calendar: .current),
                           FoodLogPolicy.requirements(search, now: FixedClock().now(), calendar: .current), "\(index)")
            if list.selectedCandidate.name.value.lowercased().contains("without skin") {
                sawSkinless = true
                XCTAssertFalse(list.materialDifferences.contains(.skin), list.selectedCandidate.name.value)
            }
        }
        XCTAssertTrue(sawSkinless, "Fixture should include the grilled skinless breast")
    }

    func testListSearchEvidenceAllowsExplicitGenericEstimateSaveAndReopen() throws {
        for method in [FoodListInputMethod.pastedOrTyped, .reviewedSpeechText] {
            let ids = SequenceIDs()
            let importer = FoodListImportService(searcher: try CoFIDGenericFoodSearch(ids: ids), ids: ids)
            let line = try XCTUnwrap(FoodListParser.parse(" 100g raw apples ").first)
            let draft = FoodListLineDraft(parsed: line, operationID: try ids.makeID(OperationTag.self),
                evidenceID: try ids.makeID(EvidenceTag.self), inputMethod: method)
            guard case let .candidates(route) = try importer.search(draft, at: FixedClock().now(), locale: LedgerText("en_GB")) else {
                return XCTFail("Expected list candidates")
            }
            var state = try importer.confirmation(for: draft, route: route, candidateIndex: 0)
            let manual = try XCTUnwrap(state.input.evidence.first)
            XCTAssertEqual(manual.evidenceID, draft.evidenceID)
            XCTAssertEqual(manual.kind, .manual)
            XCTAssertEqual(manual.captureMethod.value, method.rawValue)
            let search = try XCTUnwrap(state.input.evidence.first(where: { $0.kind == .genericSearch }))
            XCTAssertNotEqual(search.evidenceID, manual.evidenceID)
            XCTAssertEqual(search.originalPayload, .text(try LedgerText(draft.query)))
            let store = InMemoryFoodLedgerStore()
            let service = FoodConfirmationService(
                ledger: FoodLedgerService(actorID: try ids.makeID(ActorTag.self), committer: store,
                    clock: FixedClock(), encoder: FoundationCanonicalJSONEncoder(), digester: SHA256Digester()),
                reader: store, clock: FixedClock(), ids: ids, digester: SHA256Digester())
            XCTAssertThrowsError(try service.save(state, operationID: draft.operationID)) { error in
                XCTAssertEqual(error as? FoodConfirmationSaveError, .noAcceptedCandidate)
            }
            XCTAssertEqual(try store.counts().operations, 0)
            FoodConfirmationReducer.reduce(state: &state, action: .accept)
            let saved = try service.save(state, operationID: draft.operationID)
            XCTAssertEqual(saved.logItemVersion.edibleQuantity.value, 100)
            XCTAssertTrue(saved.evidence.contains(manual))
            XCTAssertTrue(saved.evidence.contains(search))
            XCTAssertTrue(saved.candidateDecision.candidate.evidenceIDs.contains(manual.evidenceID))
            XCTAssertTrue(saved.candidateDecision.candidate.evidenceIDs.contains(search.evidenceID))
            XCTAssertEqual(saved.resolutionVersion.nutrients, state.selectedCandidate.candidate.nutrients)
            let reopened = try XCTUnwrap(service.reopen(logItemID: saved.logItem.logItemID))
            XCTAssertTrue(reopened.input.evidence.contains(manual))
            XCTAssertTrue(reopened.input.evidence.contains(search))
        }
    }

    func testListSearchEvidenceDoesNotBypassConsumedQuantityRequirements() throws {
        for (text, count) in [("2 boiled eggs", true), ("raw apples", false)] {
            let ids = SequenceIDs()
            let importer = FoodListImportService(searcher: try CoFIDGenericFoodSearch(ids: ids), ids: ids)
            let draft = FoodListLineDraft(parsed: try XCTUnwrap(FoodListParser.parse(text).first),
                operationID: try ids.makeID(OperationTag.self), evidenceID: try ids.makeID(EvidenceTag.self))
            guard case let .candidates(route) = try importer.search(draft, at: FixedClock().now(), locale: LedgerText("en_GB")) else {
                return XCTFail("Expected list candidates")
            }
            var state = try importer.confirmation(for: draft, route: route, candidateIndex: 0)
            FoodConfirmationReducer.reduce(state: &state, action: .accept)
            let store = InMemoryFoodLedgerStore()
            let service = FoodConfirmationService(
                ledger: FoodLedgerService(actorID: try ids.makeID(ActorTag.self), committer: store,
                    clock: FixedClock(), encoder: FoundationCanonicalJSONEncoder(), digester: SHA256Digester()),
                reader: store, clock: FixedClock(), ids: ids, digester: SHA256Digester())
            XCTAssertThrowsError(try service.save(state, operationID: draft.operationID)) { error in
                if count { XCTAssertEqual(error as? FoodConfirmationSaveError, .unmetRequirements([.countNeedsMeasuredAmount])) }
                else { XCTAssertEqual(error as? FoodConfirmationSaveError, .unmetRequirements([.amountMissing])) }
            }
            XCTAssertEqual(try store.counts().operations, 0)
        }
    }

    func testHalfItemQueryAndListConfirmationsKeepCountsAndEvidence() throws {
        let ids = SequenceIDs()
        let search = try CoFIDGenericFoodSearch(ids: ids)
        let list = FoodListImportService(searcher: search)
        for text in ["half a green pepper", "½ yellow pepper", "1/2 green pepper"] {
            let parsed = FoodQueryParser.parse(text)
            guard case let .confirmation(route) = try search.search(request(text)) else { return XCTFail("Expected whole-food candidates") }
            let state = FoodConfirmationState(input: route.confirmation, queryQuantity: parsed.quantity)
            XCTAssertEqual(state.quantity.value, 0.5)
            XCTAssertEqual(state.quantity.unit, .count)
            XCTAssertNil(state.quantity.conversion)
            XCTAssertEqual(state.decision, .undecided)
            XCTAssertEqual(state.input.evidence.first?.originalPayload, .text(try LedgerText(text)))
            XCTAssertThrowsError(try state.quantity.calculatedEdibleQuantity()) { error in
                XCTAssertEqual(error as? FoodQuantityValidationError, .missingConversion)
            }
            let line = try XCTUnwrap(FoodListParser.parse(text).first)
            let draft = FoodListLineDraft(parsed: line, operationID: try ids.makeID(OperationTag.self), evidenceID: try ids.makeID(EvidenceTag.self))
            guard case let .candidates(listRoute) = try list.search(draft, at: FixedClock().now(), locale: LedgerText("en_GB")) else { return XCTFail("Expected list candidate") }
            let listState = try list.confirmation(for: draft, route: listRoute, candidateIndex: 0)
            XCTAssertEqual(listState.quantity.value, 0.5)
            XCTAssertEqual(listState.quantity.unit, .count)
            XCTAssertNil(listState.quantity.conversion)
            XCTAssertEqual(listState.decision, .undecided)
        }
    }

    func testCookedEggCountsStayBasisOnlyWithoutInventedEnergy() throws {
        let ids = SequenceIDs()
        // CoFID has no poached egg record, so the two-source composite is used.
        let search = CompositeGenericFoodSearch(sources: [try CoFIDGenericFoodSearch(ids: ids), try USDAGenericFoodSearch(ids: ids)], ids: ids)
        for text in ["2 scrambled eggs", "two fried eggs", "3 poached eggs"] {
            let parsed = FoodQueryParser.parse(text)
            XCTAssertEqual(parsed.quantity?.unit, "count", text)
            guard case let .confirmation(route) = try search.search(request(text)) else { return XCTFail("Expected egg candidates: " + text) }
            var state = FoodConfirmationState(input: route.confirmation, queryQuantity: parsed.quantity)
            XCTAssertEqual(state.quantity.unit, .count, text)
            XCTAssertEqual(state.quantity.value, parsed.quantity?.value, text)
            XCTAssertNil(state.quantity.conversion, text)
            XCTAssertThrowsError(try state.quantity.calculatedEdibleQuantity()) { error in
                XCTAssertEqual(error as? FoodQuantityValidationError, .missingConversion)
            }
            XCTAssertEqual(state.input.evidence.first?.originalPayload, .text(try LedgerText(text)))
            FoodConfirmationReducer.reduce(state: &state, action: .accept)
            let store = InMemoryFoodLedgerStore()
            let service = FoodConfirmationService(
                ledger: FoodLedgerService(actorID: try ids.makeID(ActorTag.self), committer: store,
                    clock: FixedClock(), encoder: FoundationCanonicalJSONEncoder(), digester: SHA256Digester()),
                reader: store, clock: FixedClock(), ids: ids, digester: SHA256Digester())
            XCTAssertThrowsError(try service.save(state, operationID: try ids.makeID(OperationTag.self))) { error in
                XCTAssertEqual(error as? FoodConfirmationSaveError, .unmetRequirements([.countNeedsMeasuredAmount]), text)
            }
            XCTAssertEqual(try store.counts().operations, 0)
        }
    }

    func testWholeMilkVolumeEstimateIsRecordBoundAndSurvivesSaveReopen() throws {
        let ids = SequenceIDs()
        let search = try CoFIDGenericFoodSearch(ids: ids)
        let policy = try CoFIDWholeMilkVolumeConversion()
        guard case let .confirmation(route) = try search.search(request("Milk, whole, pasteurised, average")),
              let milk = route.matches.map(\.candidate).first(where: policy.applies(to:)) else {
            return XCTFail("Expected exact CoFID whole pasteurised milk")
        }
        let volume = try PositiveQuantity(value: 200, unit: .millilitres)
        let offer = try XCTUnwrap(policy.offer(for: milk, original: volume))
        XCTAssertEqual(offer.convertedQuantity, try PositiveQuantity(value: 206, unit: .grams))
        XCTAssertEqual(offer.sourceReleaseID, policy.sourceRelease.sourceReleaseID)
        XCTAssertNil(try policy.offer(for: milk, original: PositiveQuantity(value: 200, unit: .grams)))
        guard case let .confirmation(uhtRoute) = try search.search(request("Milk, whole, UHT")) else {
            return XCTFail("Expected UHT control")
        }
        XCTAssertNil(try policy.offer(for: uhtRoute.matches[0].candidate, original: volume))

        let input = try PopulatedFoodConfirmation(
            evidence: route.confirmation.evidence,
            sourceReleases: route.confirmation.sourceReleases + [policy.sourceRelease],
            candidates: [milk],
            expectedIdentity: milk.candidate.identity,
            expectedEdibleQuantity: milk.candidate.edibleQuantity
        )
        var state = FoodConfirmationState(input: input)
        FoodConfirmationReducer.reduce(state: &state, action: .setQuantity(200, .millilitres))
        FoodConfirmationReducer.reduce(state: &state, action: .setConversion(offer))
        FoodConfirmationReducer.reduce(state: &state, action: .accept)
        let store = InMemoryFoodLedgerStore()
        let service = FoodConfirmationService(
            ledger: FoodLedgerService(actorID: try id(919, ActorTag.self), committer: store,
                clock: FixedClock(), encoder: FoundationCanonicalJSONEncoder(), digester: SHA256Digester()),
            reader: store, clock: FixedClock(), ids: ids,
            digester: SHA256Digester()
        )
        let saved = try service.save(state, operationID: id(920, OperationTag.self))
        XCTAssertEqual(saved.logItemVersion.edibleQuantity.value, 206)
        XCTAssertEqual(saved.quantityConversion?.sourceQuantity, volume)
        XCTAssertEqual(saved.quantityConversion?.sourceReleaseID, policy.sourceRelease.sourceReleaseID)
        let reopened = try XCTUnwrap(service.reopen(logItemID: saved.logItem.logItemID))
        XCTAssertEqual(reopened.quantity.conversion, offer)
        XCTAssertTrue(reopened.input.sourceReleases.contains(policy.sourceRelease))
        var changed = reopened
        FoodConfirmationReducer.reduce(state: &changed, action: .setQuantity(250, .millilitres))
        XCTAssertNil(changed.quantity.conversion)
    }

    func testBundledCorpusIsHashVerifiedCompleteAndExactSearchRequiresSelection() throws {
        let search = try CoFIDGenericFoodSearch(ids: SequenceIDs())
        XCTAssertEqual(search.recordCount, 2_887)
        XCTAssertEqual(
            search.sourceRelease.manifestHash.value,
            CoFIDGenericFoodSearch.corpusCanonicalSHA256
        )

        let outcome = try search.search(request("Ackee, canned, drained"))
        guard case let .confirmation(route) = outcome else { return XCTFail("Expected matches") }
        XCTAssertTrue(route.matches[0].isExactName)
        XCTAssertEqual(route.matches[0].candidate.name.value, "Ackee, canned, drained")
        XCTAssertEqual(route.confirmation.evidence[0].kind, .genericSearch)
        XCTAssertEqual(route.matches[0].candidate.candidate.nutrients.entries.count, 39)
        XCTAssertEqual(
            route.matches[0].candidate.candidate.matchMetadata?.selectionPolicy.value,
            "explicit_user_selection_v1"
        )
        let water = try XCTUnwrap(route.matches[0].candidate.candidate.nutrients.entries.first {
            $0.key == .water
        })
        XCTAssertEqual(water.value, .unknown(.missingConversion))
    }

    func testKnownPreparationHardRuleRunsBeforeRanking() throws {
        let search = try CoFIDGenericFoodSearch(ids: SequenceIDs())
        let outcome = try search.search(request(
            "Beef braising steak lean",
            identity: GenericFoodIdentityQuery(preparation: try PreparationState(kind: .cooked))
        ))
        guard case let .confirmation(route) = outcome else { return XCTFail("Expected cooked candidates") }
        XCTAssertFalse(route.matches.isEmpty)
        XCTAssertTrue(route.matches.allSatisfy {
            $0.candidate.candidate.identity.preparation.kind == .cooked
        })
    }

    func testSaltStateHardRuleAndNoResultDeclineAreDeterministic() throws {
        let search = try CoFIDGenericFoodSearch(ids: SequenceIDs())
        let salted = try search.search(request(
            "Beef silverside raw",
            identity: GenericFoodIdentityQuery(saltState: try LedgerText("salted"))
        ))
        guard case let .confirmation(route) = salted else { return XCTFail("Expected salted candidates") }
        XCTAssertTrue(route.matches.allSatisfy { $0.candidate.name.value.contains("salted") })

        let missing = try search.search(request("zzzxqv no compatible food"))
        guard case let .noResult(fallback) = missing else { return XCTFail("Expected explicit no result") }
        XCTAssertTrue(fallback.guidance.contains("Nothing has been selected or saved"))
    }

    func testNormalizationMatchesFrozenAliasesAndPunctuation() {
        XCTAssertEqual(
            CoFIDGenericFoodSearch.normalized("Yogurt, AUBERGINES"),
            "yoghurt aubergine"
        )
    }

    func testFrozenWeightsThresholdLimitAndDuplicateTieBreakMatchEvaluation() throws {
        XCTAssertEqual(CoFIDGenericFoodSearch.candidateLimit, 10)
        XCTAssertEqual(CoFIDGenericFoodSearch.minimumScore, 0.25)
        XCTAssertEqual(CoFIDGenericFoodSearch.weights.exactName, 0.55)
        XCTAssertEqual(CoFIDGenericFoodSearch.weights.queryCoverage, 0.20)
        XCTAssertEqual(CoFIDGenericFoodSearch.weights.candidateCoverage, 0.15)
        XCTAssertEqual(CoFIDGenericFoodSearch.weights.jaccard, 0.10)

        let outcome = try CoFIDGenericFoodSearch(ids: SequenceIDs()).search(request("Beef, mince, stewed"))
        guard case let .confirmation(route) = outcome else { return XCTFail("Expected duplicate candidates") }
        let exactIDs = route.matches.filter(\.isExactName).map { $0.candidate.candidate.recordID.value }
        XCTAssertGreaterThanOrEqual(exactIDs.count, 2)
        XCTAssertEqual(exactIDs, exactIDs.sorted())
    }

    func testEveryFrozenHardRuleFamilyBlocksAnExactLexicalConflict() throws {
        let quantity = try PositiveQuantity(value: 100, unit: .grams)
        let constraints = [
            GenericFoodIdentityQuery(preparation: try PreparationState(kind: .raw)),
            GenericFoodIdentityQuery(bone: .withBone),
            GenericFoodIdentityQuery(skin: .skinOn),
            GenericFoodIdentityQuery(drained: .undrained),
            GenericFoodIdentityQuery(packingMedium: .named(try LedgerText("brine"))),
            GenericFoodIdentityQuery(fortification: .fortified),
            GenericFoodIdentityQuery(servingBasis: .per100Millilitres),
            GenericFoodIdentityQuery(edibleQuantity: .known(quantity, conversionVersionID: nil)),
            GenericFoodIdentityQuery(saltState: try LedgerText("salted")),
            GenericFoodIdentityQuery(formulation: try LedgerText("v2"))
        ]
        let search = try CoFIDGenericFoodSearch(ids: SequenceIDs())
        for constraint in constraints {
            let outcome = try search.search(request("Ackee, canned, drained", identity: constraint))
            guard case .noResult = outcome else {
                return XCTFail("A frozen hard-rule family admitted the exact conflict")
            }
        }
    }

    func testUnknownGenericEstimateSearchesAgainWithoutClaimingExactLibraryIdentity() throws {
        let store = InMemoryFoodLedgerStore()
        let ids = SequenceIDs()
        let search = try CoFIDGenericFoodSearch(library: PersonalLibraryGenericFoodSearch(reader: store), ids: ids)
        guard case let .confirmation(route) = try search.search(request("rice")) else { return XCTFail("rice") }
        var state = FoodConfirmationState(input: route.confirmation)
        FoodConfirmationReducer.reduce(state: &state, action: .setQuantity(100, .grams))
        FoodConfirmationReducer.reduce(state: &state, action: .accept)
        let ledger = FoodLedgerService(actorID: try id(999, ActorTag.self), committer: store,
            clock: FixedClock(), encoder: FoundationCanonicalJSONEncoder(), digester: SHA256Digester())
        let service = FoodConfirmationService(ledger: ledger, reader: store, clock: FixedClock(), ids: ids, digester: SHA256Digester())
        let saved = try service.save(state, operationID: id(905, OperationTag.self))
        // D6 (food_confirmation_v5): an estimate creates no exact library alias; the bundled source is rediscovered.
        XCTAssertTrue(try store.exactLibraryEntries(alias: LedgerText("food:name:rice")).isEmpty)
        guard case let .confirmation(nextRoute) = try search.search(request("rice")) else { return XCTFail("rice") }
        XCTAssertNil(nextRoute.reuse)
        XCTAssertEqual(nextRoute.matches[0].candidate.candidate.recordID, saved.candidateDecision.candidate.recordID)
        var next = FoodConfirmationState(input: nextRoute.confirmation)
        XCTAssertTrue(next.isGenericEstimate)
        FoodConfirmationReducer.reduce(state: &next, action: .setQuantity(150, .grams))
        FoodConfirmationReducer.reduce(state: &next, action: .accept)
        XCTAssertNoThrow(try service.save(next, operationID: id(906, OperationTag.self)))
    }

    func testNamedDishUnknownPreparationSurvivesExplicitSaveAndDoesNotBecomeExactReuse() throws {
        let store = InMemoryFoodLedgerStore()
        let ids = SequenceIDs()
        let search = try CoFIDGenericFoodSearch(library: PersonalLibraryGenericFoodSearch(reader: store), ids: ids)
        guard case let .confirmation(route) = try search.search(request("200g cooked porridge made with water")) else { return XCTFail("200g cooked porridge made with water") }
        var state = FoodConfirmationState(input: route.confirmation)
        FoodConfirmationReducer.reduce(state: &state, action: .setQuantity(100, .grams))
        FoodConfirmationReducer.reduce(state: &state, action: .accept)
        let ledger = FoodLedgerService(actorID: try id(999, ActorTag.self), committer: store,
            clock: FixedClock(), encoder: FoundationCanonicalJSONEncoder(), digester: SHA256Digester())
        let service = FoodConfirmationService(ledger: ledger, reader: store, clock: FixedClock(), ids: ids, digester: SHA256Digester())
        let saved = try service.save(state, operationID: id(905, OperationTag.self))
        // D6 (food_confirmation_v5): an estimate creates no exact library alias; the bundled source is rediscovered.
        XCTAssertTrue(try store.exactLibraryEntries(alias: LedgerText("food:name:200g cooked porridge made with water")).isEmpty)
        guard case let .confirmation(nextRoute) = try search.search(request("200g cooked porridge made with water")) else { return XCTFail("200g cooked porridge made with water") }
        XCTAssertEqual(saved.candidateDecision.candidate.identity.preparation.kind, .unknown)
        XCTAssertEqual(nextRoute.matches[0].candidate.candidate.identity.preparation.kind, .unknown)
        XCTAssertEqual(nextRoute.matches[0].candidate.candidate.nutrients, saved.candidateDecision.candidate.nutrients)
        XCTAssertNil(nextRoute.reuse)
        XCTAssertEqual(nextRoute.matches[0].candidate.candidate.recordID, saved.candidateDecision.candidate.recordID)
        var next = FoodConfirmationState(input: nextRoute.confirmation)
        XCTAssertTrue(next.isGenericEstimate)
        FoodConfirmationReducer.reduce(state: &next, action: .setQuantity(150, .grams))
        FoodConfirmationReducer.reduce(state: &next, action: .accept)
        XCTAssertNoThrow(try service.save(next, operationID: id(906, OperationTag.self)))
    }

    func testConfirmedGenericMatchCreatesOfflineExactLibraryReuse() throws {
        let store = InMemoryFoodLedgerStore()
        let ids = SequenceIDs()
        let search = try CoFIDGenericFoodSearch(
            library: PersonalLibraryGenericFoodSearch(reader: store),
            ids: ids
        )
        let scan = try barcodeEvidence()
        let first = try search.search(request("Ackee canned drained", additionalEvidence: [scan]))
        guard case let .confirmation(route) = first else { return XCTFail("Expected CoFID candidate") }
        XCTAssertEqual(route.confirmation.evidence.count, 2)
        XCTAssertTrue(route.matches[0].candidate.candidate.evidenceIDs.contains(scan.evidenceID))
        XCTAssertNil(route.matches[0].candidate.barcode)
        var state = FoodConfirmationState(input: route.confirmation)
        let selected = state.selectedCandidate
        let resolvedIdentity = try DecisiveIdentity(
            preparation: PreparationState(kind: .asSold),
            bone: .notApplicable,
            skin: .notApplicable,
            drained: .drained,
            packingMedium: .named(LedgerText("none")),
            fortification: .unfortified,
            servingBasis: .per100Grams
        )
        FoodConfirmationReducer.reduce(state: &state, action: .applyCorrection(FoodCorrection(
            name: selected.name,
            brand: nil,
            variant: nil,
            identity: resolvedIdentity,
            nutrients: selected.candidate.nutrients,
            reason: try LedgerText("User resolved identity before explicit selection")
        )))
        let ledger = FoodLedgerService(
            actorID: try id(900, ActorTag.self),
            committer: store,
            clock: FixedClock(),
            encoder: FoundationCanonicalJSONEncoder(),
            digester: SHA256Digester()
        )
        let saved = try FoodConfirmationService(
            ledger: ledger,
            reader: store,
            clock: FixedClock(),
            ids: ids,
            digester: SHA256Digester()
        ).save(state, operationID: try id(901, OperationTag.self))
        XCTAssertEqual(try store.foodConfirmation(logItemID: saved.logItem.logItemID)?.evidence.last, scan)
        XCTAssertTrue(try store.exactLibraryEntries(alias: LedgerText("barcode:gtin:04006381333931")).isEmpty)

        let provider = try CoFIDReresolutionProvider(ids: ids)
        let target = try XCTUnwrap(provider.targets().first)
        let reresolution = FoodReresolutionService(
            ledger: ledger, reader: FoodReresolutionHistory(archive: store, confirmations: store),
            provider: provider, clock: FixedClock(), ids: ids
        )
        let proposals = try reresolution.proposals(logItemID: saved.logItem.logItemID, target: target)
        let sameRecord = try XCTUnwrap(proposals.first { $0.candidate.candidate.recordID == saved.candidateDecision.candidate.recordID })
        XCTAssertTrue(sameRecord.isNoOp)
        XCTAssertFalse(sameRecord.identityGaps.isEmpty)
        XCTAssertEqual(sameRecord.candidate.candidate.matchMetadata?.methodVersion.value, CoFIDGenericFoodSearch.matcherVersion)
        XCTAssertThrowsError(try provider.candidates(for: saved, target: FoodReresolutionTarget(sourceRelease: target.sourceRelease, methodVersion: LedgerText("not-an-accepted-model")), at: FixedClock().now()))

        let reused = try search.search(request("Ackee canned drained", additionalEvidence: [scan]))
        guard case let .confirmation(savedRoute) = reused else { return XCTFail("Expected saved reuse") }
        XCTAssertNotNil(savedRoute.reuse)
        XCTAssertEqual(
            savedRoute.matches[0].candidate.candidate.matchMetadata?.methodVersion.value,
            "personal-library-exact-v1"
        )
        XCTAssertEqual(savedRoute.matches[0].candidate.candidate.identity, resolvedIdentity)
        XCTAssertEqual(savedRoute.confirmation.evidence.last, scan)
        XCTAssertTrue(savedRoute.matches[0].candidate.candidate.evidenceIDs.contains(scan.evidenceID))

        let incompatible = try search.search(request(
            "Ackee canned drained", identity: GenericFoodIdentityQuery(preparation: try PreparationState(kind: .raw))
        ))
        if case let .confirmation(other) = incompatible {
            XCTAssertNil(other.reuse)
            XCTAssertTrue(other.matches.allSatisfy { $0.candidate.candidate.identity.preparation.kind == .raw })
        }
    }

    func testNoResultRetainsBarcodeAndDuplicateEvidenceIsRejected() throws {
        let search = try CoFIDGenericFoodSearch(ids: SequenceIDs())
        let evidence = try barcodeEvidence()
        guard case let .noResult(route) = try search.search(request("zzzxxxx", additionalEvidence: [evidence])) else {
            return XCTFail("Expected no result")
        }
        XCTAssertEqual(route.retainedEvidence.last, evidence)
        XCTAssertThrowsError(try search.search(request("rice", additionalEvidence: [evidence, evidence])))
    }

    func testListToRealCatalogueConfirmationPreservesMeasuredDescriptorsAndEvidence() throws {
        let ids = SequenceIDs()
        let search = try CoFIDGenericFoodSearch(ids: ids)
        let service = FoodListImportService(searcher: search)
        for (text, amount) in [("73g cheese processed slices", 73.0), ("81g bread white sliced", 81.0)] {
            let parsed = try XCTUnwrap(FoodListParser.parse(text).first)
            var draft = FoodListLineDraft(parsed: parsed, operationID: try ids.makeID(OperationTag.self), evidenceID: try ids.makeID(EvidenceTag.self))
            guard case let .candidates(route) = try service.search(draft, at: FixedClock().now(), locale: LedgerText("en_GB")) else {
                return XCTFail("Expected real catalogue candidates: \(text)")
            }
            let state = try service.confirmation(for: draft, route: route, candidateIndex: 0)
            XCTAssertEqual(state.quantity.value, amount)
            XCTAssertEqual(state.quantity.unit, .grams)
            XCTAssertEqual(state.decision, .undecided)
            XCTAssertFalse(state.input.sourceReleases.isEmpty)
            let evidence = try XCTUnwrap(state.input.evidence.first)
            XCTAssertEqual(evidence.evidenceID, draft.evidenceID)
            guard case let .descriptor(payload) = evidence.originalPayload else { return XCTFail("Missing source") }
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(payload.value.utf8)) as? [String: Any])
            XCTAssertEqual(json["original"] as? String, text)
            draft.quantityText = ""
            XCTAssertNil(try service.confirmation(for: draft, route: route, candidateIndex: 0).quantity.value)
            XCTAssertThrowsError(try service.confirmation(for: draft, route: route, candidateIndex: route.matches.count))
        }
        let parsed = try XCTUnwrap(FoodListParser.parse("2 slices processed cheese").first)
        let draft = FoodListLineDraft(parsed: parsed, operationID: try ids.makeID(OperationTag.self), evidenceID: try ids.makeID(EvidenceTag.self))
        guard case let .candidates(route) = try service.search(draft, at: FixedClock().now(), locale: LedgerText("en_GB")) else {
            return XCTFail("Expected editable household query candidates")
        }
        XCTAssertNil(try service.confirmation(for: draft, route: route, candidateIndex: 0).quantity.value)
        for text in ["73g ham slices", "81g wholemeal and rye bread"] {
            let parsed = try XCTUnwrap(FoodListParser.parse(text).first)
            let unmatched = FoodListLineDraft(parsed: parsed, operationID: try ids.makeID(OperationTag.self), evidenceID: try ids.makeID(EvidenceTag.self))
            guard case .unresolved = try service.search(unmatched, at: FixedClock().now(), locale: LedgerText("en_GB")) else {
                return XCTFail("A missing catalogue description must not silently drop terms: \(text)")
            }
            XCTAssertNotNil(FoodListParser.number(unmatched.quantityText))
        }
    }

    private func barcodeEvidence() throws -> CaptureEvidence {
        try CaptureEvidence(
            evidenceID: id(800, EvidenceTag.self), kind: .barcode, capturedAt: FixedClock().now(),
            locale: LedgerText("en_GB"), captureMethod: LedgerText("synthetic"), captureMethodVersion: LedgerText("1"),
            originalPayload: .barcode(value: LedgerText("4006381333931"), symbology: LedgerText("ean13"))
        )
    }

    func testFoodListSearchPreservesSourceAndNeverUsesDatasetServingAsConsumedAmount() throws {
        let ids = SequenceIDs()
        let service = FoodListImportService(searcher: try CoFIDGenericFoodSearch(ids: ids))
        let parsed = try XCTUnwrap(FoodListParser.parse(" 60 gr Ackee canned drained ").first)
        var draft = FoodListLineDraft(parsed: parsed, operationID: try ids.makeID(OperationTag.self), evidenceID: try ids.makeID(EvidenceTag.self))
        guard case let .candidates(route) = try service.search(draft, at: FixedClock().now(), locale: LedgerText("en_GB")) else {
            return XCTFail("Expected candidates")
        }
        let state = try service.confirmation(for: draft, route: route, candidateIndex: 0)
        XCTAssertEqual(state.quantity.value, 60)
        XCTAssertEqual(state.decision, .undecided)
        let evidence = try XCTUnwrap(state.input.evidence.first)
        XCTAssertEqual(evidence.evidenceID, draft.evidenceID)
        XCTAssertEqual(evidence.captureMethodVersion.value, FoodListParser.legacyVersion, "a v3 line keeps its v3 label")
        guard case let .descriptor(payload) = evidence.originalPayload else { return XCTFail("Missing input evidence") }
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(payload.value.utf8)) as? [String: Any])
        XCTAssertEqual(json["original"] as? String, " 60 gr Ackee canned drained ")
        XCTAssertEqual(json["lineNumber"] as? Int, 1)
        draft.quantityText = ""
        let missing = try service.confirmation(for: draft, route: route, candidateIndex: 0)
        XCTAssertNil(missing.quantity.value)
    }

    /// food-list-lexical-v4 (#222): evidence carries each line's own grammar and convention with
    /// canonical amount text; a restored v3 line keeps its v3 label and descriptor bytes; Confirm
    /// opens with the untouched parse, or with typed text that presentation made canonical with
    /// the field's locale, read by the canonical amount parser (Q6).
    func testListEvidenceRecordsEachLinesGrammarAndConfirmReadsAmountsByItsConvention() throws {
        let ids = SequenceIDs()
        let service = FoodListImportService(searcher: try CoFIDGenericFoodSearch(ids: ids))
        func draft(_ line: ParsedFoodListLine) throws -> FoodListLineDraft {
            FoodListLineDraft(parsed: line, operationID: try ids.makeID(OperationTag.self), evidenceID: try ids.makeID(EvidenceTag.self))
        }
        func route(_ draft: FoodListLineDraft) throws -> GenericFoodConfirmationRoute {
            guard case let .candidates(route) = try service.search(draft, at: FixedClock().now(), locale: LedgerText("en_GB")) else {
                throw FoodLedgerValidationError.empty("candidates")
            }
            return route
        }
        func evidence(_ draft: FoodListLineDraft) throws -> (version: String, descriptor: String) {
            let route = try route(draft)
            let state = try service.confirmation(for: draft, route: route, candidateIndex: 0)
            let evidence = try XCTUnwrap(state.input.evidence.first { $0.evidenceID == draft.evidenceID })
            guard case let .descriptor(payload) = evidence.originalPayload else { throw FoodLedgerValidationError.empty("descriptor") }
            return (evidence.captureMethodVersion.value, payload.value)
        }
        func amount(_ draft: FoodListLineDraft) throws -> Double? {
            try service.confirmation(for: draft, route: try route(draft), candidateIndex: 0).quantity.value
        }

        // A stored v4 line, full-stop-decimal: "1,500" is 1500 (Q1); evidence records the convention (Q4).
        var english = try draft(try XCTUnwrap(FoodListParser.parseV4("1,500 gr Ackee canned drained", convention: .fullStopDecimal).first))
        XCTAssertEqual(try amount(english), 1500)
        let englishEvidence = try evidence(english)
        XCTAssertEqual(englishEvidence.version, "food-list-lexical-v4")
        XCTAssertEqual(englishEvidence.descriptor,
                       #"{"lineNumber":1,"notices":[],"numeralConvention":"full_stop_decimal","original":"1,500 gr Ackee canned drained","quantity":"1500","query":"Ackee canned drained","unit":"g"}"#)
        english.quantityText = "1,250" // canonical text for an en_GB field keeps comma grouping
        XCTAssertEqual(try amount(english), 1250, "typed canonical text is read by the canonical parser (Q6)")
        XCTAssertTrue(try evidence(english).descriptor.contains(#""quantity":"1250""#), "typed text is recorded canonically")
        english.quantityText = "0.75"
        XCTAssertEqual(try amount(english), 0.75)

        // v4, comma-decimal: "1,5" is 1.5 and "1.500" is never guessed.
        var german = try draft(try XCTUnwrap(FoodListParser.parseV4("1,5 gr Ackee canned drained", convention: .commaDecimal).first))
        XCTAssertEqual(try amount(german), 1.5)
        XCTAssertTrue(try evidence(german).descriptor.contains(#""numeralConvention":"comma_decimal""#))
        XCTAssertTrue(try evidence(german).descriptor.contains(#""quantity":"1.5""#))
        german.quantityText = "2.25" // a German field's "2,25", made canonical by presentation
        XCTAssertEqual(try amount(german), 2.25, "the line's comma convention never reinterprets canonical text")
        german.quantityText = "1250"
        XCTAssertEqual(try amount(german), 1250)
        let ambiguous = try draft(try XCTUnwrap(FoodListParser.parseV4("1.500 gr Ackee canned drained", convention: .commaDecimal).first))
        XCTAssertNil(ambiguous.parsed.quantity)
        XCTAssertNil(try amount(ambiguous))

        // A v3 line (restored from an older checkpoint) keeps its label, bytes and frozen reading.
        var legacy = try draft(try XCTUnwrap(FoodListParser.parse("60 gr Ackee canned drained").first))
        let legacyEvidence = try evidence(legacy)
        XCTAssertEqual(legacyEvidence.version, "food-list-lexical-v3")
        XCTAssertEqual(legacyEvidence.descriptor,
                       #"{"lineNumber":1,"notices":[],"original":"60 gr Ackee canned drained","quantity":"60.0","query":"Ackee canned drained","unit":"g"}"#)
        XCTAssertEqual(try amount(legacy), 60)
        legacy.quantityText = "1,500"
        XCTAssertNil(try amount(legacy), "v3 lines keep the frozen v3 rule")
        XCTAssertTrue(try evidence(legacy).descriptor.contains(#""quantity":"1,500""#), "v3 text is recorded as typed")

        // food-list-lexical-v5 and v6: a new line reads amounts exactly as v4 and is stamped v6.
        var current = try draft(try XCTUnwrap(FoodListParser.parse("1,500 gr Ackee canned drained", convention: .fullStopDecimal).first))
        XCTAssertEqual(try amount(current), 1500)
        let currentEvidence = try evidence(current)
        XCTAssertEqual(currentEvidence.version, "food-list-lexical-v7")
        XCTAssertEqual(currentEvidence.descriptor, englishEvidence.descriptor, "the v6 descriptor has the v4 form")
        current.quantityText = "1,250"
        XCTAssertEqual(try amount(current), 1250)
    }

    /// food-list-lexical-v5 (#140, B3): a vague portion reaches Confirm with no amount, so the
    /// needs-amount rule blocks Log; its evidence is stamped with the line's version (v6) and the household-measure notice.
    func testVaguePortionListLineReachesConfirmWithoutAnAmount() throws {
        let ids = SequenceIDs()
        let service = FoodListImportService(searcher: try CoFIDGenericFoodSearch(ids: ids), ids: ids)
        // food-list-lexical-v6 (#353) and v7 (#359): household containers and measures behave the same way.
        for text in ["a handful of Ackee canned drained", "2 pinches Ackee canned drained", "a few Ackee canned drained",
                     "2 mugs of Ackee canned drained", "a pot of Ackee canned drained", "250 ml mug of Ackee canned drained",
                     "a tin of Ackee canned drained", "2 slices of Ackee canned drained", "400 g tin of Ackee canned drained"] {
            let parsed = try XCTUnwrap(FoodListParser.parse(text, convention: .fullStopDecimal).first)
            let draft = FoodListLineDraft(parsed: parsed, operationID: try ids.makeID(OperationTag.self), evidenceID: try ids.makeID(EvidenceTag.self))
            XCTAssertEqual(draft.quantityText, "", text)
            XCTAssertNil(draft.amountValue, text)
            guard case let .candidates(route) = try service.search(draft, at: FixedClock().now(), locale: LedgerText("en_GB")) else {
                return XCTFail("Expected candidates: \(text)")
            }
            var state = try service.confirmation(for: draft, route: route, candidateIndex: 0)
            XCTAssertNil(state.quantity.value, text)
            XCTAssertEqual(state.quantity.unit, .grams, text)
            let evidence = try XCTUnwrap(state.input.evidence.first { $0.evidenceID == draft.evidenceID })
            XCTAssertEqual(evidence.captureMethodVersion.value, "food-list-lexical-v7", text)
            guard case let .descriptor(payload) = evidence.originalPayload else { return XCTFail("Missing descriptor") }
            XCTAssertTrue(payload.value.contains(#""notices":["householdMeasure"]"#), text)
            XCTAssertTrue(payload.value.contains(#""quantity":"""#), text)
            FoodConfirmationReducer.reduce(state: &state, action: .accept)
            XCTAssertTrue(FoodLogPolicy.requirements(state, now: FixedClock().now(), calendar: Calendar(identifier: .gregorian))
                .contains(.amountMissing), text)
        }
    }

    func testSupplementRecipeAndUnknownFoodStayUnresolved() throws {
        let ids = SequenceIDs()
        let service = FoodListImportService(searcher: try CoFIDGenericFoodSearch(ids: ids))
        for text in ["1 vitamin milk tablet", "80 g homemade rice", "5 g zzzzxxxx"] {
            let parsed = try XCTUnwrap(FoodListParser.parse(text).first)
            let draft = FoodListLineDraft(parsed: parsed, operationID: try ids.makeID(OperationTag.self), evidenceID: try ids.makeID(EvidenceTag.self))
            guard case .unresolved = try service.search(draft, at: FixedClock().now(), locale: LedgerText("en_GB")) else {
                return XCTFail("Must remain unresolved: \(text)")
            }
        }
    }

    func testReportedMealAndCutFailuresOfferHonestNextSearches() throws {
        let search = try CoFIDGenericFoodSearch(ids: SequenceIDs())
        for query in ["Fish & Chips", "Fish and Chips", "Fiash and Chips"] {
            guard case let .noResult(route) = try search.search(request(query)) else {
                return XCTFail("A component or shop description is not the whole meal: \(query)")
            }
            XCTAssertEqual(route.suggestedQueries, ["Cod in batter", "Potato chips"])
            XCTAssertTrue(route.guidance.contains("separately"))
            for suggestion in route.suggestedQueries {
                guard case .confirmation = try search.search(request(suggestion)) else {
                    return XCTFail("Suggested search must retrieve candidates")
                }
            }
        }
        for query in ["Ribeye", "rib eye", "rib-eye"] {
            guard case let .noResult(route) = try search.search(request(query)) else {
                return XCTFail("Do not invent an exact cut match")
            }
            XCTAssertEqual(route.suggestedQueries, ["Beef steak"])
            XCTAssertTrue(route.guidance.contains("different cut"))
        }
    }

    func testConnectingWordsAloneCannotRetrieveCandidates() throws {
        let search = try CoFIDGenericFoodSearch(ids: SequenceIDs())
        for query in ["and with the", "zzzz and", "in from"] {
            guard case .noResult = try search.search(request(query)) else {
                return XCTFail("A conjunction is not a food match: \(query)")
            }
        }
    }

    private func request(
        _ text: String,
        identity: GenericFoodIdentityQuery = GenericFoodIdentityQuery(),
        additionalEvidence: [CaptureEvidence] = []
    ) throws -> GenericFoodSearchRequest {
        GenericFoodSearchRequest(
            text: try LedgerText(text),
            identity: identity,
            capturedAt: Date(timeIntervalSince1970: 1_700_000_000),
            locale: try LedgerText("en_GB"), additionalEvidence: additionalEvidence
        )
    }
}

private struct FixedClock: LedgerClock {
    func now() -> Date { Date(timeIntervalSince1970: 1_700_000_000) }
}

private func id<Tag>(_ value: Int, _ tag: Tag.Type) throws -> LedgerID<Tag> {
    try LedgerID(String(format: "00000000-0000-0000-0000-%012x", value))
}

private final class SequenceIDs: LedgerIDGenerating, @unchecked Sendable {
    private var value = 1

    func makeID<Tag>(_ tag: Tag.Type) throws -> LedgerID<Tag> {
        defer { value += 1 }
        return try LedgerID(String(format: "00000000-0000-0000-0000-%012x", value))
    }
}
