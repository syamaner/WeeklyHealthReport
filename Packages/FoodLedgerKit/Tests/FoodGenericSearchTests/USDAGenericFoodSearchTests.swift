import Foundation
import FoodGenericSearch
import FoodLedgerApplication
import FoodLedgerDomain
import FoodLedgerTestSupport
import XCTest

final class USDAGenericFoodSearchTests: XCTestCase {
    func testCookedQuinoaNeverIncludesUncookedSourceAndNutrientsRemainLiteral() throws {
        let search = try USDAGenericFoodSearch(ids: USDASequenceIDs())
        for (state, suffix, energy) in [(PreparationKind.cooked, ":fdc:168917", 120.0), (.raw, ":fdc:168874", 368.0)] {
            guard case let .confirmation(route) = try search.search(request("quinoa", identity: GenericFoodIdentityQuery(preparation: try PreparationState(kind: state)))) else {
                return XCTFail("Expected preparation-matched quinoa")
            }
            if state == .cooked {
                XCTAssertFalse(route.matches.contains { $0.candidate.name.value.lowercased().contains("uncooked") })
            }
            let candidate = try XCTUnwrap(route.matches.first { $0.candidate.candidate.recordID.value.hasSuffix(suffix) }?.candidate.candidate)
            XCTAssertEqual(candidate.identity.preparation.kind, state)
            guard case let .augmented(value) = candidate.nutrients.entries.first(where: { $0.key == .energyConsumed })?.value else {
                return XCTFail("Missing declared energy")
            }
            XCTAssertEqual(value.amount, energy)
            let release = try XCTUnwrap(route.confirmation.sourceReleases.first { $0.sourceReleaseID == candidate.sourceReleaseID })
            let archiveReleaseID = String(candidate.recordID.value.components(separatedBy: ":fdc:")[0])
            XCTAssertNotEqual(release.sourceReleaseID.value, archiveReleaseID)
            XCTAssertEqual(release.sourceReleaseID.value, "\(archiveReleaseID):projection:\(USDAGenericFoodSearch.corpusSHA256)")
            XCTAssertEqual(release.manifestHash.value, USDAGenericFoodSearch.corpusSHA256)
            XCTAssertTrue(value.provenance.allSatisfy { $0.sourceReleaseID == release.sourceReleaseID && $0.recordID == candidate.recordID })
            XCTAssertTrue(route.confirmation.sourceReleases.allSatisfy { $0.pipelineVersion.value == "usda-projection-v2" })
        }
    }

    func testBothAdaptersKeepPancakePluralIdentityAndExcludeUnrequestedSyrupOrMix() throws {
        for source in [try CoFIDGenericFoodSearch(ids: USDASequenceIDs()) as any GenericFoodSearching,
                       try USDAGenericFoodSearch(ids: USDASequenceIDs()) as any GenericFoodSearching] {
            guard case let .confirmation(singular) = try source.search(request("pancake")),
                  case let .confirmation(plural) = try source.search(request("pancakes")) else {
                return XCTFail("Both bundled sources contain pancake records")
            }
            XCTAssertEqual(singular.matches.map { $0.candidate.candidate.recordID }, plural.matches.map { $0.candidate.candidate.recordID })
            XCTAssertFalse(singular.matches.isEmpty)
            for match in singular.matches {
                let name = match.candidate.name.value.lowercased()
                XCTAssertTrue(name.contains("pancake"))
                XCTAssertFalse(name.contains("syrup") || name.contains("mix") || name.contains("batter"), name)
            }
            for text in ["蛋餅 cheese", "蔥油餅 pancake", "scallion pancake", "scallion pancakes"] {
                guard case let .noResult(miss) = try source.search(request(text)) else { return XCTFail("Do not drop unmatched identity: \(text)") }
                XCTAssertEqual(miss.evidence.originalPayload, .text(try LedgerText(text)))
            }
        }
        let usda = try USDAGenericFoodSearch(ids: USDASequenceIDs())
        guard case let .confirmation(syrup) = try usda.search(request("pancake syrups")) else { return XCTFail("Explicit syrup query remains supported") }
        XCTAssertTrue(syrup.matches.allSatisfy { $0.candidate.name.value.lowercased().contains("syrup") })
    }

    func testBothAdaptersPreserveSeedIdentityAndRejectDerivativeOnlyMatches() throws {
        let sources: [any GenericFoodSearching] = [try CoFIDGenericFoodSearch(ids: USDASequenceIDs()), try USDAGenericFoodSearch(ids: USDASequenceIDs())]
        for source in sources {
            var records: [[String]] = []
            for query in ["pumpkin seed", "pumpkin seeds"] {
                guard case let .confirmation(route) = try source.search(request(query)) else { return XCTFail("Expected seed records") }
                XCTAssertEqual(route.confirmation.evidence.first?.originalPayload, .text(try LedgerText(query)))
                records.append(route.matches.map { $0.candidate.candidate.recordID.value })
                XCTAssertTrue(route.matches.allSatisfy { $0.candidate.candidate.matchMetadata?.selectionPolicy.value == "explicit_user_selection_v1" })
            }
            XCTAssertEqual(records[0], records[1])
            guard case let .noResult(miss) = try source.search(request("hot dog")) else { return XCTFail("Derivative foods cannot stand in for the requested food") }
            XCTAssertEqual(miss.evidence.originalPayload, .text(try LedgerText("hot dog")))
        }
        let usda = try USDAGenericFoodSearch(ids: USDASequenceIDs())
        guard case let .confirmation(relish) = try usda.search(request("hot dog relish")) else { return XCTFail("Explicitly requested relish must remain searchable") }
        XCTAssertTrue(relish.matches.allSatisfy { $0.candidate.name.value.lowercased().contains("relish") })
        guard case let .confirmation(seeds) = try usda.search(request("chia seed")) else { return XCTFail("Expected literal chia seed source") }
        XCTAssertTrue(seeds.matches.allSatisfy { $0.candidate.name.value.lowercased().contains("chia") })
        guard case .noResult = try usda.search(request("chia seed", identity: GenericFoodIdentityQuery(preparation: try PreparationState(kind: .cooked)))) else { return XCTFail("Lexical equivalence cannot override preparation") }
    }

    func testSlicedSourceRetrievalKeepsUnknownPreparationAndOriginalEvidence() throws {
        let source = try USDAGenericFoodSearch(ids: USDASequenceIDs())
        for text in ["roast beef slice", "roast beef slices"] {
            guard case let .confirmation(route) = try source.search(request(text)) else { return XCTFail("Expected sliced source record") }
            let target = try XCTUnwrap(route.matches.first { $0.candidate.candidate.recordID.value.hasSuffix(":fdc:174570") })
            XCTAssertEqual(target.candidate.candidate.identity.preparation.kind, .unknown)
            XCTAssertEqual(route.confirmation.evidence.first?.originalPayload, .text(try LedgerText(text)))
            XCTAssertEqual(target.candidate.candidate.matchMetadata?.selectionPolicy.value, "explicit_user_selection_v1")
            for preparation in [PreparationKind.raw, .cooked] {
                guard case .noResult = try source.search(request(text, identity: GenericFoodIdentityQuery(preparation: try PreparationState(kind: preparation)))) else { return XCTFail("Unknown preparation cannot satisfy a requested state") }
            }
        }
        let parsed = try XCTUnwrap(FoodListParser.parse("75 g roast beef slices").first)
        let ids = USDASequenceIDs()
        let draft = FoodListLineDraft(parsed: parsed, operationID: try ids.makeID(OperationTag.self), evidenceID: try ids.makeID(EvidenceTag.self))
        let service = FoodListImportService(searcher: source)
        guard case .unresolved = try service.search(draft, at: Date(timeIntervalSince1970: 1_700_000_000), locale: LedgerText("en_GB")) else { return XCTFail("List preparation cannot bypass unknown source metadata") }
    }

    func testBothAdaptersKeepExplicitSliceAndContradictoryMethodConstraints() throws {
        let sources: [any GenericFoodSearching] = [try CoFIDGenericFoodSearch(ids: USDASequenceIDs()), try USDAGenericFoodSearch(ids: USDASequenceIDs())]
        for source in sources {
            guard case .noResult = try source.search(request("roast turkey slices")) else { return XCTFail("A whole roast source does not declare a sliced form") }
            if case let .confirmation(route) = try source.search(request("roast turkey", identity: GenericFoodIdentityQuery(preparation: try PreparationState(kind: .raw)))) {
                // A raw turkey roast is a named cut, not an asserted cooked record.
                XCTAssertTrue(route.matches.allSatisfy { $0.candidate.candidate.identity.preparation.kind == .raw })
                XCTAssertFalse(route.matches.contains { $0.candidate.name.value.lowercased().contains("roasted") })
            }
        }
    }

    private func request(_ text: String, identity: GenericFoodIdentityQuery = GenericFoodIdentityQuery()) throws -> GenericFoodSearchRequest {
        GenericFoodSearchRequest(text: try LedgerText(text), identity: identity, capturedAt: Date(timeIntervalSince1970: 1_700_000_000), locale: try LedgerText("en_GB"))
    }

    func testBothAdaptersSatisfyEvidenceUnknownAndIdentityContract() throws {
        let sources: [any GenericFoodSearching] = [try CoFIDGenericFoodSearch(ids: USDASequenceIDs()), try USDAGenericFoodSearch(ids: USDASequenceIDs())]
        for source in sources {
            guard case let .confirmation(route) = try source.search(request("Beef", identity: GenericFoodIdentityQuery(preparation: try PreparationState(kind: .cooked)))) else {
                return XCTFail("Expected explicitly cooked candidates")
            }
            XCTAssertFalse(route.matches.isEmpty)
            for match in route.matches {
                let c = match.candidate.candidate
                XCTAssertEqual(c.identity.preparation.kind, .cooked)
                XCTAssertEqual(c.nutrients.entries.count, NutrientKey.allCases.count)
                XCTAssertEqual(c.matchMetadata?.selectionPolicy.value, "explicit_user_selection_v1")
                XCTAssertEqual(c.evidenceIDs, route.confirmation.evidence.map(\.evidenceID))
                XCTAssertTrue(route.confirmation.sourceReleases.contains { $0.sourceReleaseID == c.sourceReleaseID })
            }
            for query in ["zzzzqqqq", "and with the"] {
                guard case let .noResult(miss) = try source.search(request(query)) else { return XCTFail("Expected explicit miss") }
                XCTAssertEqual(miss.evidence.originalPayload, .text(try LedgerText(query)))
            }
            guard case .noResult = try source.search(request("Beef", identity: GenericFoodIdentityQuery(servingBasis: .per100Millilitres))) else {
                return XCTFail("Cannot substitute mass for volume basis")
            }
        }
    }

    func testRibeyeSpellingsRetrieveWholeUSRecordsWithoutChangingOriginalEvidence() throws {
        let search = try USDAGenericFoodSearch(ids: USDASequenceIDs())
        XCTAssertEqual(search.recordCount, 8_156)
        for text in ["Ribeye", "rib eye", "rib-eye"] {
            guard case let .confirmation(route) = try search.search(request(text, identity: GenericFoodIdentityQuery(preparation: try PreparationState(kind: .raw)))) else {
                return XCTFail("Expected source-backed cut")
            }
            XCTAssertEqual(route.confirmation.evidence.first?.originalPayload, .text(try LedgerText(text)))
            XCTAssertTrue(route.matches.allSatisfy { $0.candidate.variant?.value.contains("US composition estimate") == true })
            for match in route.matches {
                let c = match.candidate.candidate
                XCTAssertEqual(c.identity.preparation.kind, .raw)
                XCTAssertTrue(c.recordID.value.contains(":fdc:"))
                XCTAssertEqual(c.nutrients.entries.first { $0.key == .water }?.value, .unknown(.missingConversion))
                XCTAssertEqual(c.nutrients.entries.first { $0.key == .vitaminA }?.value, .unknown(.notDeclared))
            }
        }
    }

    func testFoundationRibeyeEnergyConventionAndBonelessStateArePreserved() throws {
        let search = try USDAGenericFoodSearch(ids: USDASequenceIDs())
        guard case let .confirmation(route) = try search.search(request("ribeye")) else { return XCTFail("Missing ribeye") }
        let candidate = try XCTUnwrap(route.matches.first { $0.candidate.candidate.recordID.value.hasSuffix(":fdc:2646172") }?.candidate.candidate)
        XCTAssertEqual(candidate.identity.bone, .boneless)
        guard case let .augmented(value) = candidate.nutrients.entries.first(where: { $0.key == .energyConsumed })?.value else {
            return XCTFail("Expected source-backed energy estimate")
        }
        XCTAssertEqual(value.amount, 260)
        XCTAssertTrue(value.provenance[0].manifestReference?.value.contains("2048") == true)
        XCTAssertTrue(candidate.sourceReleaseID.value.hasPrefix("usda-foundation:"))
    }

    func testCompositeRetainsBothSourcesAndNeverTreatsComponentAsCombinedMeal() throws {
        let ids = USDASequenceIDs()
        let search = try CompositeGenericFoodSearch(sources: [CoFIDGenericFoodSearch(ids: ids), USDAGenericFoodSearch(ids: ids)], ids: ids)
        guard case let .confirmation(route) = try search.search(request("Beef")) else { return XCTFail("Expected sources") }
        XCTAssertTrue(route.confirmation.sourceReleases.contains { $0.sourceID.value == "cofid" })
        XCTAssertTrue(route.confirmation.sourceReleases.contains { $0.sourceID.value.hasPrefix("usda-") })
        XCTAssertEqual(route.confirmation.evidence.count, 1)
        XCTAssertTrue(route.matches.allSatisfy { $0.candidate.candidate.evidenceIDs == route.confirmation.evidence.map(\.evidenceID) })
        guard case let .noResult(miss) = try search.search(request("Fish & Chips")) else { return XCTFail("No whole meal record exists") }
        XCTAssertEqual(miss.suggestedQueries, ["Cod in batter", "Potato chips"])
    }

    func testEverydayFoodsAndPluralEquivalentsRetainRelevantCandidates() throws {
        let ids = USDASequenceIDs()
        let search = try CompositeGenericFoodSearch(sources: [CoFIDGenericFoodSearch(ids: ids), USDAGenericFoodSearch(ids: ids)], ids: ids)
        for text in ["chicken breast", "salmon", "olive oil", "brown rice", "oats", "milk", "yoghurt", "lentils"] {
            guard case let .confirmation(route) = try search.search(request(text)) else {
                return XCTFail("Expected an everyday source-backed food: \(text)")
            }
            XCTAssertFalse(route.matches.isEmpty)
            XCTAssertEqual(route.confirmation.evidence.first?.originalPayload, .text(try LedgerText(text)))
        }
        for (singular, plural) in [("apple", "apples"), ("banana", "bananas"), ("egg", "eggs"), ("potato", "potatoes")] {
            guard case let .confirmation(a) = try search.search(request(singular)),
                  case let .confirmation(b) = try search.search(request(plural)) else { return XCTFail("Missing plural pair") }
            XCTAssertEqual(a.matches.map { $0.candidate.candidate.recordID }, b.matches.map { $0.candidate.candidate.recordID })
        }
        for text in ["chicken zzqx", "salmon chocolate", "Fiash and Chips"] {
            guard case .noResult = try search.search(request(text)) else { return XCTFail("An unrelated partial match must not stand in for \(text)") }
        }
    }

    func testTamperedCorpusFailsClosed() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        try Data("{}".utf8).write(to: file)
        XCTAssertThrowsError(try USDAGenericFoodSearch(corpusURL: file, ids: USDASequenceIDs())) {
            XCTAssertEqual($0 as? USDASearchError, .hashMismatch)
        }
    }
}

private final class USDASequenceIDs: LedgerIDGenerating, @unchecked Sendable {
    private var value = 1
    func makeID<Tag>(_ tag: Tag.Type) throws -> LedgerID<Tag> {
        defer { value += 1 }
        return try LedgerID(String(format: "00000000-0000-0000-0000-%012x", value))
    }
}
