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
        let first = try search.search(request("Ackee canned drained"))
        guard case let .confirmation(route) = first else { return XCTFail("Expected CoFID candidate") }
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
        _ = try FoodConfirmationService(
            ledger: ledger,
            reader: store,
            clock: FixedClock(),
            ids: ids
        ).save(state, operationID: try id(901, OperationTag.self))

        let reused = try search.search(request("Ackee canned drained"))
        guard case let .confirmation(savedRoute) = reused else { return XCTFail("Expected saved reuse") }
        XCTAssertNotNil(savedRoute.reuse)
        XCTAssertEqual(
            savedRoute.matches[0].candidate.candidate.matchMetadata?.methodVersion.value,
            "personal-library-exact-v1"
        )
        XCTAssertEqual(savedRoute.matches[0].candidate.candidate.identity, resolvedIdentity)
    }

    private func request(
        _ text: String,
        identity: GenericFoodIdentityQuery = GenericFoodIdentityQuery()
    ) throws -> GenericFoodSearchRequest {
        GenericFoodSearchRequest(
            text: try LedgerText(text),
            identity: identity,
            capturedAt: Date(timeIntervalSince1970: 1_700_000_000),
            locale: try LedgerText("en_GB")
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
