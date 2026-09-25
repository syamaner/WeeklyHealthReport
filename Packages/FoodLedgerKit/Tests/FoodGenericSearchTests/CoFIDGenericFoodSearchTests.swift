import FoodGenericSearch
import FoodLedgerApplication
import FoodLedgerDomain
import FoodLedgerTestSupport
import XCTest

final class CoFIDGenericFoodSearchTests: XCTestCase {
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
            "Beef braising steak raw lean",
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
            ids: ids
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
        XCTAssertEqual(evidence.captureMethodVersion.value, FoodListParser.version)
        guard case let .descriptor(payload) = evidence.originalPayload else { return XCTFail("Missing input evidence") }
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(payload.value.utf8)) as? [String: Any])
        XCTAssertEqual(json["original"] as? String, " 60 gr Ackee canned drained ")
        XCTAssertEqual(json["lineNumber"] as? Int, 1)
        draft.quantityText = ""
        let missing = try service.confirmation(for: draft, route: route, candidateIndex: 0)
        XCTAssertNil(missing.quantity.value)
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
