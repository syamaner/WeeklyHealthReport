@testable import FoodLedgerApplication
import FoodLedgerDomain
import FoodLedgerPresentation
import FoodLedgerTestSupport
import Foundation
import XCTest

/// Food details from the catalogue (docs/personal-food-catalogue-identity-facts-v1-amendment.md section 5,
/// contract tests 2 to 6 and 8): candidate identity, the facts-aware merge, the importer's estimate check,
/// Confirm's difference questions, the composite-generic-ranking-v12 database filter, the method version
/// split and re-resolution. Synthetic fixtures only (`docs/fixtures/personal-food-database-estimates-v4`).
final class IdentityFactsAmendmentContractTests: XCTestCase {
    static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
    static let crisps = "Synthetic Crisps", rice = "Synthetic Cooked Rice", oats = "Synthetic Example Oats"
    static let fish = "Synthetic Tinned Fish", spread = "Synthetic Crème Spread"
    static let allStated: [String: String] = ["preparation": "raw", "bone": "not_applicable", "skin": "not_applicable",
        "drained": "not_applicable", "packing_medium": "not applicable", "fortification": "unfortified"]

    static func fixture(_ path: String) throws -> Data { try Data(contentsOf: root.appendingPathComponent("docs/fixtures/" + path)) }

    /// The v4 golden with `edit` applied to its JSON object.
    static func v4(_ edit: (inout [String: Any]) -> Void = { _ in }) throws -> Data {
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: fixture("personal-food-database-estimates-v4/golden.json"))
            as? [String: Any])
        edit(&object)
        return try JSONSerialization.data(withJSONObject: object)
    }

    static func item(_ object: inout [String: Any], _ title: String, _ edit: (inout [String: Any]) -> Void) {
        var items = object["items"] as! [[String: Any]]
        let index = items.firstIndex { $0["title"] as? String == title }!
        edit(&items[index])
        object["items"] = items
    }

    final class IDs: LedgerIDGenerating, @unchecked Sendable {
        private var value = 1
        func makeID<Tag>(_ tag: Tag.Type) throws -> LedgerID<Tag> {
            defer { value += 1 }
            return try LedgerID(String(format: "00000000-0000-0000-0000-%012x", value))
        }
    }

    static let recordRelease = SourceRelease(
        sourceReleaseID: try! ExternalIdentifier("cofid:synthetic"), sourceID: try! ExternalIdentifier("cofid"),
        releasedAt: Date(timeIntervalSince1970: 0), artifactHash: try! SHA256Digest(String(repeating: "d", count: 64)),
        schemaVersion: try! LedgerText("synthetic"), pipelineVersion: try! LedgerText("synthetic"),
        licence: try! LedgerText("synthetic"), attribution: try! LedgerText("synthetic"),
        manifestHash: try! SHA256Digest(String(repeating: "d", count: 64)))

    /// Generic records with a stated identity: energy, protein and sodium known, per 100 g edible.
    struct Resolver: GenericRecordResolving {
        var identities: [String: DecisiveIdentity]

        func contains(_ reference: GenericRecordReference) -> Bool { identities[reference.recordID] != nil }

        func resolve(_ reference: GenericRecordReference, evidenceIDs: [EvidenceID], queryAlias: String) -> ResolvedGenericRecord? {
            guard let identity = identities[reference.recordID] else { return nil }
            return try? ResolvedGenericRecord(candidate: IdentityFactsAmendmentContractTests.record(reference.recordID,
                identity: identity, evidenceIDs: evidenceIDs), release: recordRelease)
        }
    }

    static func identity(_ preparation: PreparationKind, bone: BoneState = .unknown, packing: String? = nil,
                         fortification: FortificationState = .unknown) throws -> DecisiveIdentity {
        try DecisiveIdentity(preparation: PreparationState(kind: preparation), bone: bone, skin: .unknown, drained: .unknown,
            packingMedium: packing.map { .named(try LedgerText($0)) } ?? .unknown, fortification: fortification,
            servingBasis: .per100Grams)
    }

    static func record(_ recordID: String, identity: DecisiveIdentity, evidenceIDs: [EvidenceID]) throws -> PopulatedFoodCandidate {
        let id = try ExternalIdentifier(recordID)
        let nutrients = try NutrientSet(entries: NutrientKey.allCases.map { key in
            guard [.energyConsumed, .protein, .sodium].contains(key) else { return try NutrientEntry(key: key, value: .unknown(.notDeclared)) }
            return try NutrientEntry(key: key, value: .augmented(ExactNutrientValue(amount: 11, unit: key.canonicalUnit,
                sourceValue: .exact(SourceExactNutrientValue(amount: 11, unit: LedgerText(key.canonicalUnit.rawValue), basis: .per100Grams)),
                provenance: [NutrientProvenance(sourceKind: .genericCompositionDataset, sourceID: recordRelease.sourceID,
                                                sourceReleaseID: recordRelease.sourceReleaseID, recordID: id)])))
        })
        return try PopulatedFoodCandidate(candidate: ProviderNeutralCandidate(
            sourceReleaseID: recordRelease.sourceReleaseID, recordID: id, identity: identity,
            edibleQuantity: .known(PositiveQuantity(value: 100, unit: .grams), conversionVersionID: nil),
            nutrients: nutrients, evidenceIDs: evidenceIDs,
            matchMetadata: CandidateMatchMetadata(methodVersion: LedgerText(PersonalFoodDatabaseCandidateBuilder.methodVersion),
                                                  score: 1, materialDifferences: [])),
            name: LedgerText("Synthetic generic " + recordID), itemClass: .food)
    }

    static func defaultResolver() throws -> Resolver {
        Resolver(identities: ["cofid:example": try identity(.raw), "cofid:fish": try identity(.unknown),
                              "cofid:cheese": try identity(.unknown), "cofid:greens": try identity(.raw)])
    }

    static func manifest(_ bytes: Data) throws -> PersonalFoodDatabaseManifest {
        let digest = try SHA256Digester().sha256(bytes)
        let file = try PersonalFoodDatabaseCodec.decode(bytes).get()
        return PersonalFoodDatabaseManifest(schema: file.schema.rawValue,
            releaseID: PersonalFoodDatabaseRelease.releaseID(fileSHA256: digest), fileSHA256: digest,
            generated: file.generated, importedAt: Date(timeIntervalSince1970: 1_794_000_000), entryCount: file.entries.count)
    }

    static func index(_ bytes: Data, resolver: some GenericRecordResolving, store: InMemoryPersonalFoodDatabaseStore = .init())
        throws -> PersonalFoodDatabaseIndex {
        try store.install(bytes: bytes, manifest: manifest(bytes))
        let index = PersonalFoodDatabaseIndex(store: store, resolver: resolver)
        index.warm()
        return index
    }

    static func search(_ bytes: Data, resolver: Resolver? = nil) throws -> PersonalFoodDatabaseFoodSearch {
        let resolver = try resolver ?? defaultResolver()
        let ids = IDs()
        return PersonalFoodDatabaseFoodSearch(index: try index(bytes, resolver: resolver), resolver: resolver, ids: ids,
            estimates: ApprovedEstimateManifestBuilder(ids: ids, digester: SHA256Digester()))
    }

    static func request(_ text: String) throws -> GenericFoodSearchRequest {
        GenericFoodSearchRequest(text: try LedgerText(text), capturedAt: Date(timeIntervalSince1970: 1_794_000_000),
                                 locale: try LedgerText("en-GB"))
    }

    static func route(_ search: PersonalFoodDatabaseFoodSearch, _ text: String) throws -> GenericFoodConfirmationRoute? {
        if case let .confirmation(route) = try search.search(request(text)) { return route }
        return nil
    }

    static func note(_ candidate: PopulatedFoodCandidate) -> String? {
        candidate.candidate.matchMetadata?.materialDifferences.map(\.value)
            .first { $0.hasPrefix(PersonalFoodDatabaseCandidateBuilder.factsNotePrefix) }
    }

    // MARK: Test 2, candidates

    func testNoMergeWithEveryFactStatedNeedsOnlyAnAmount() throws {
        let route = try XCTUnwrap(Self.route(try Self.search(try Self.v4()), "synthetic crisps"))
        let state = FoodConfirmationState(input: try XCTUnwrap(route.choosing(0)))
        XCTAssertTrue(state.unresolvedIdentity.isEmpty)
        XCTAssertTrue(state.materialDifferences.isEmpty, "the tapped row's identity is the expected one")
        let identity = state.selectedCandidate.candidate.identity
        XCTAssertEqual(identity.preparation.kind, .asSold)
        XCTAssertEqual(identity.packingMedium, .named(try LedgerText(FoodDetailsFillPolicy.packingNotApplicable)))
        XCTAssertEqual(Self.note(state.selectedCandidate),
                       "Food details from your food database: as sold, no bone, no skin, nothing to drain, no packing liquid, not fortified")
        var logged = state
        logged.quantity.value = 30
        logged.decision = .accepted
        let requirements = FoodLogPolicy.requirements(logged, now: Date(timeIntervalSince1970: 1_794_000_000), calendar: .current)
        XCTAssertFalse(requirements.contains { if case .sourceIdentityMissing = $0 { true } else { false } })
        XCTAssertFalse(requirements.contains { if case .decideDifference = $0 { true } else { false } })
    }

    func testPartialFactsAskOnlyTheUnknownOnes() throws {
        let route = try XCTUnwrap(Self.route(try Self.search(try Self.v4()), "synthetic cooked rice"))
        let state = FoodConfirmationState(input: try XCTUnwrap(route.choosing(0)))
        XCTAssertEqual(Set(state.unresolvedIdentity), [.bone, .skin, .drained, .fortification])
        XCTAssertEqual(Self.note(state.selectedCandidate), "Food details from your food database: cooked, no packing liquid")
    }

    func testAMergeTakesOnlyTheRecordUnknownFactsFromTheFile() throws {
        let route = try XCTUnwrap(Self.route(try Self.search(try Self.v4()), "synthetic example oats"))
        XCTAssertEqual(route.matches.count, 1, "the record merges, so no Generic row")
        let candidate = route.matches[0].candidate
        XCTAssertEqual(candidate.candidate.identity.preparation.kind, .raw)
        XCTAssertEqual(candidate.candidate.identity.bone, .notApplicable)
        XCTAssertEqual(candidate.candidate.identity.fortification, .unfortified)
        // The record states raw, so the preparation is not listed as the catalogue's.
        XCTAssertEqual(Self.note(candidate), "Food details from your food database: no bone, no skin, not fortified")
    }

    func testAConflictingKnownFactDropsTheMergeAndOffersTheRecordAsItsOwnRow() throws {
        var resolver = try Self.defaultResolver()
        resolver.identities["cofid:example"] = try Self.identity(.raw, bone: .withBone)
        let route = try XCTUnwrap(Self.route(try Self.search(try Self.v4(), resolver: resolver), "synthetic example oats"))
        XCTAssertEqual(route.matches.map { $0.personalDatabase?.isGenericReference }, [false, true])
        XCTAssertEqual(route.matches[0].candidate.candidate.identity.bone, .notApplicable)
        // The same record merges in a file without facts (A1 today).
        let file = try PersonalFoodDatabaseCodec.decode(try Self.v4()).get()
        let entry = try XCTUnwrap(file.entries.first { $0.title == Self.oats })
        let record = try Self.record("cofid:example", identity: Self.identity(.raw, bone: .withBone), evidenceIDs: [])
        XCTAssertFalse(PersonalFoodDatabaseCandidateBuilder.mergeEligible(entry, record: record))
        XCTAssertTrue(PersonalFoodDatabaseCandidateBuilder.mergeEligible(PersonalFoodDatabaseEntry(
            id: entry.id, brand: entry.brand, title: entry.title, titles: entry.titles, aliases: entry.aliases, concept: entry.concept,
            variety: entry.variety, fallbackChain: entry.fallbackChain, category: entry.category, productType: entry.productType,
            state: entry.state, basis: entry.basis, labelNutrients: entry.labelNutrients, genericReference: entry.genericReference),
            record: record))
    }

    func testAMergeOnlyEntryWhoseFactBreaksTheMergeGivesNoEntryRow() throws {
        var resolver = try Self.defaultResolver()
        resolver.identities["cofid:example"] = try Self.identity(.raw, bone: .withBone)
        let bytes = try Self.v4 { Self.item(&$0, Self.oats) { $0["label_nutrients"] = [String: Any]() } }
        let route = try XCTUnwrap(Self.route(try Self.search(bytes, resolver: resolver), "synthetic example oats"))
        XCTAssertEqual(route.matches.map { $0.personalDatabase?.isGenericReference }, [true], "only its Generic row remains")
    }

    /// The shared merge cases of the fixture manifest agree with the skill's checker (I1.5 step 5).
    func testTheSharedMergeCasesAgreeWithTheSkill() throws {
        struct Case: Decodable { let name: String; let facts: [String: String]?; let record: [String: String]; let eligible: Bool; let filled: [String] }
        struct Manifest: Decodable { let merge_cases: [Case] }
        let manifest = try JSONDecoder().decode(Manifest.self, from: Self.fixture("personal-food-database-estimates-v4/manifest.json"))
        XCTAssertGreaterThanOrEqual(manifest.merge_cases.count, 3)
        for c in manifest.merge_cases {
            let bytes = try Self.v4 { Self.item(&$0, Self.oats) { $0["identity_facts"] = c.facts ?? NSNull() } }
            let file = try PersonalFoodDatabaseCodec.decode(bytes).get()
            let entry = try XCTUnwrap(file.entries.first { $0.title == Self.oats })
            let r = c.record
            let identity = try DecisiveIdentity(preparation: PreparationState(kind: PreparationKind(rawValue: r["preparation"]!)!),
                bone: BoneState(rawValue: r["bone"]!)!, skin: SkinState(rawValue: r["skin"]!)!,
                drained: DrainedState(rawValue: r["drained"]!)!,
                packingMedium: r["packing_medium"] == "unknown" ? .unknown : .named(try LedgerText(r["packing_medium"]!)),
                fortification: FortificationState(rawValue: r["fortification"]!)!, servingBasis: .per100Grams)
            let record = try Self.record("cofid:example", identity: identity, evidenceIDs: [])
            let eligible = PersonalFoodDatabaseCandidateBuilder.mergeEligible(entry, record: record)
            XCTAssertEqual(eligible, c.eligible, c.name)
            let filled = eligible ? try PersonalFoodDatabaseCandidateBuilder.identity(entry, merged: identity).fromFile : []
            XCTAssertEqual(filled.map(\.rawValue), c.filled, c.name)
        }
    }

    func testMethodVersionFollowsTheSchemaAndDedupeAcceptsBoth() throws {
        let v4 = try XCTUnwrap(Self.route(try Self.search(try Self.v4()), "synthetic crème spread"))
        XCTAssertEqual(v4.matches[0].candidate.candidate.matchMetadata?.methodVersion.value, "pfc-resolution-v2")
        XCTAssertEqual(v4.confirmation.evidence.first?.captureMethodVersion.value, "pfc-resolution-v2")
        let v3 = try XCTUnwrap(Self.route(try Self.search(try Self.fixture("personal-food-database-estimates-v3/golden.json")),
                                          "synthetic crème spread"))
        XCTAssertEqual(v3.matches[0].candidate.candidate.matchMetadata?.methodVersion.value, "pfc-resolution-v1")
        XCTAssertEqual(v3.confirmation.evidence.first?.captureMethodVersion.value, "pfc-resolution-v1")
        XCTAssertEqual(try CompositeGenericFoodSearch.dedupeDatabaseRows(v4.matches + v3.matches).count, 2)
    }

    /// Section 4: an all-null v4 file gives the candidates of its v3 twin apart from the release and
    /// method version.
    func testAnAllNullV4FileGivesItsV3TwinsCandidates() throws {
        let v4 = try XCTUnwrap(Self.route(try Self.search(try Self.fixture("personal-food-database-estimates-v4/accept-all-null-with-photo.json")),
                                          "synthetic serving bar"))
        let v3 = try XCTUnwrap(Self.route(try Self.search(try Self.fixture("personal-food-database-estimates-v3/golden.json")),
                                          "synthetic serving bar"))
        XCTAssertEqual(v4.matches.count, v3.matches.count)
        for (a, b) in zip(v4.matches, v3.matches) {
            XCTAssertEqual(a.candidate.candidate.identity, b.candidate.candidate.identity)
            XCTAssertEqual(a.candidate.candidate.matchMetadata?.materialDifferences, b.candidate.candidate.matchMetadata?.materialDifferences)
            XCTAssertEqual(a.candidate.candidate.recordID, b.candidate.candidate.recordID)
            XCTAssertEqual(a.candidate.candidate.nutrients.entries.map(\.key), b.candidate.candidate.nutrients.entries.map(\.key))
        }
    }

    // MARK: Test 3, estimates

    /// Each record's identity; values are left unknown, so only the contradiction code is compared.
    struct Lookup: GenericRecordNutrientLookup {
        var identities: [String: DecisiveIdentity]

        func record(source: PersonalFoodDatabaseGenericSource, corpusSHA256: String, recordID: String)
            -> Result<GenericRecordFacts, GenericRecordLookupFailure> {
            guard let identity = identities[recordID],
                  let nutrients = try? NutrientSet(entries: NutrientKey.allCases.map { try NutrientEntry(key: $0, value: .unknown(.notDeclared)) }),
                  let quantity = try? PositiveQuantity(value: 100, unit: .grams) else { return .failure(.recordMissing) }
            return .success(GenericRecordFacts(nutrients: nutrients, identity: identity, edibleQuantity: .known(quantity, conversionVersionID: nil)))
        }
    }

    static func lookup(fish: DecisiveIdentity) throws -> Lookup {
        Lookup(identities: ["cofid:fish": fish, "cofid:cheese": try identity(.unknown), "cofid:other-cheese": try identity(.unknown),
                            "cofid:greens": try identity(.raw), "cofid:cooked-rice": try identity(.cooked),
                            "cofid:example": try identity(.raw)])
    }

    func contradictions(_ bytes: Data, lookup: Lookup) throws -> Int {
        let file = try PersonalFoodDatabaseCodec.decode(bytes).get()
        return PersonalFoodDatabaseEstimateAdmission.codes(file: file, lookup: lookup).filter { $0 == .estimateContradiction }.count
    }

    func testAFactContradictingEstimateIsRejectedInV4AndTodaysConditionsStillFire() throws {
        let brine = try Self.lookup(fish: Self.identity(.unknown, packing: "brine"))
        let oil = try Self.v4 { Self.item(&$0, Self.fish) { $0["identity_facts"] = ["preparation": "unknown", "bone": "unknown",
            "skin": "unknown", "drained": "unknown", "packing_medium": "oil", "fortification": "unknown"] } }
        XCTAssertEqual(try contradictions(oil, lookup: brine), 3, "three fish estimates from the brine record")
        XCTAssertEqual(try contradictions(try Self.v4(), lookup: brine), 0, "no fish facts, no contradiction")
        // The v3 twin keeps exactly today's codes with the same records.
        let v2 = try Self.fixture("personal-food-database-estimates-v2/golden.json")
        XCTAssertEqual(try contradictions(v2, lookup: brine), 0)
        // A fortified record still contradicts, in v4 as before.
        let fortified = try Self.lookup(fish: Self.identity(.unknown, fortification: .fortified))
        XCTAssertEqual(try contradictions(try Self.v4(), lookup: fortified), 3)
        XCTAssertEqual(try contradictions(v2, lookup: fortified), 3)
    }

    func testConfirmsWithholdingAgreesWithTheImporter() throws {
        let brine = try Self.identity(.unknown, packing: "brine")
        let file = try PersonalFoodDatabaseCodec.decode(try Self.v4 { Self.item(&$0, Self.fish) { $0["identity_facts"] = [
            "preparation": "unknown", "bone": "unknown", "skin": "unknown", "drained": "unknown", "packing_medium": "oil",
            "fortification": "unknown"] } }).get()
        let entry = try XCTUnwrap(file.entries.first { $0.title == Self.fish })
        let lookup = try Self.lookup(fish: brine)
        // The importer rejects the three fish estimates from the brine record...
        XCTAssertEqual(PersonalFoodDatabaseEstimateAdmission.codes(file: file, lookup: lookup)
            .filter { $0 == .estimateContradiction }.count, 3)
        // ...and Confirm, given the same candidate and record, withholds each of them on that facet.
        let bytes = try Self.v4 { Self.item(&$0, Self.fish) { $0["identity_facts"] = [
            "preparation": "unknown", "bone": "unknown", "skin": "unknown", "drained": "unknown", "packing_medium": "oil",
            "fortification": "unknown"] } }
        let route = try XCTUnwrap(Self.route(try Self.search(bytes), "synthetic tinned fish"))
        let candidate = try XCTUnwrap(route.matches.first { $0.personalDatabase?.isGenericReference == false }).candidate.candidate
        XCTAssertEqual(PersonalFoodDatabaseEstimateAdmission.entryIdentity(entry, file: file, lookup: lookup), candidate.identity)
        let verified = try XCTUnwrap(ApprovedEstimateSource.verifiedManifest(candidate, evidence: route.confirmation.evidence,
                                                                              digester: SHA256Digester()))
        var records: [ApprovedEstimateRecordKey: ApprovedEstimateRecordState] = [:]
        for estimate in verified.manifest.estimates {
            if let key = ApprovedEstimateRecordKey(estimate) { records[key] = .identity(brine) }
        }
        let withheld = ApprovedEstimateEligibility.withheld(manifest: verified.manifest, records: records,
            confirmed: candidate.identity, candidateBasis: candidate.identity.servingBasis)
        XCTAssertEqual(withheld, [.protein: .facet(.packingMedium), .fatTotal: .facet(.packingMedium),
                                  .sugar: .facet(.packingMedium)])
    }

    /// Review fix: the v4 comparison applies only to an entry with stated facts, so a merged null-facts
    /// entry with another record's estimate that differs from the merged record imports as in v3.
    func testANullFactsEntryKeepsTodaysEstimateCheckInV4() throws {
        let bytes = try Self.fixture("personal-food-database-estimates-v4/accept-null-facts-merge-other-record-estimate.json")
        var lookup = try Self.lookup(fish: Self.identity(.unknown))
        lookup.identities["cofid:example"] = try DecisiveIdentity(preparation: PreparationState(kind: .raw), bone: .unknown,
            skin: .skinOn, drained: .unknown, packingMedium: .unknown, fortification: .unknown, servingBasis: .per100Grams)
        lookup.identities["cofid:other-skin"] = try DecisiveIdentity(preparation: PreparationState(kind: .raw), bone: .unknown,
            skin: .skinless, drained: .unknown, packingMedium: .unknown, fortification: .unknown, servingBasis: .per100Grams)
        XCTAssertEqual(try contradictions(bytes, lookup: lookup), 0)
        let file = try PersonalFoodDatabaseCodec.decode(bytes).get()
        let oats = try XCTUnwrap(file.entries.first { $0.title == Self.oats })
        XCTAssertNil(oats.identityFacts)
        XCTAssertNil(PersonalFoodDatabaseEstimateAdmission.entryIdentity(oats, file: file, lookup: lookup))
    }

    /// G4 with facts: the facts-aware merge decides `estimate-own-merge`. A fact that makes the merge
    /// ineligible is by definition one that contradicts the record, so the same record's estimate is then
    /// `estimate-contradiction` instead (see the phase report).
    func testOwnMergeUsesTheFactsAwareMerge() throws {
        let data = try Self.fixture("personal-food-database-estimates-v2/accept-own-merge-unstated-preparation-raw.json")
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let raw = try Self.identity(.raw, bone: .withBone)
        let lookup = Lookup(identities: ["cofid:unstated-greens": raw])
        let v2File = try PersonalFoodDatabaseCodec.decode(data).get()
        XCTAssertTrue(PersonalFoodDatabaseEstimateAdmission.codes(file: v2File, lookup: lookup).contains(.estimateOwnMerge))
        object["schema"] = PersonalFoodDatabaseSchema.estimatesV4.rawValue
        var items = object["items"] as! [[String: Any]]
        for i in items.indices {
            items[i]["identity_facts"] = items[i]["title"] as? String == "Synthetic Raw Greens"
                ? ["preparation": "raw", "bone": "boneless", "skin": "unknown", "drained": "unknown", "packing_medium": "unknown",
                   "fortification": "unknown"] as [String: Any] : NSNull()
        }
        object["items"] = items
        let v4File = try PersonalFoodDatabaseCodec.decode(try JSONSerialization.data(withJSONObject: object)).get()
        let codes = PersonalFoodDatabaseEstimateAdmission.codes(file: v4File, lookup: lookup)
        XCTAssertFalse(codes.contains(.estimateOwnMerge))
        XCTAssertTrue(codes.contains(.estimateContradiction))
    }

    // MARK: Test 4, Confirm differences

    func testATappedRowRaisesNoDifferenceAndSwitchingAsksTheListedQuestions() throws {
        var resolver = try Self.defaultResolver()
        resolver.identities["cofid:example"] = try Self.identity(.raw, bone: .withBone)
        let route = try XCTUnwrap(Self.route(try Self.search(try Self.v4(), resolver: resolver), "synthetic example oats"))
        // Tapping the entry, then switching to its Generic row: the record states bone differently.
        var state = FoodConfirmationState(input: try XCTUnwrap(route.choosing(0)))
        // Facts still unknown are missing details, not differences to decide.
        XCTAssertTrue(FoodLogPolicy.pendingDifferences(state).isEmpty)
        state.selectedCandidateIndex = 1
        XCTAssertTrue(state.materialDifferences.contains(.bone))
        // Tapping the Generic row (ranked second), then switching to the entry: for a non-generic row
        // unknown on either side is a difference, and the bone is one.
        var reverse = FoodConfirmationState(input: try XCTUnwrap(route.choosing(1)))
        XCTAssertTrue(FoodLogPolicy.pendingDifferences(reverse).isEmpty)
        reverse.selectedCandidateIndex = 1
        XCTAssertTrue(reverse.materialDifferences.contains(.bone))
    }

    // MARK: Test 5, search (composite-generic-ranking-v12)

    func testNoDatabaseRowHardContradictsTheRequest() throws {
        let search = try Self.search(try Self.v4())
        for text in ["raw synthetic crisps", "cooked synthetic crème spread", "synthetic crisps", "raw synthetic example oats",
                     "cooked synthetic example oats", "raw synthetic cooked rice"] {
            let request = try Self.request(text)
            for match in try Self.route(search, text)?.matches ?? [] {
                XCTAssertFalse(ConservativeFoodSearchCoverageAssessment.hasHardContradiction(match.candidate.candidate, request: request), text)
            }
        }
        // An as_sold entry is absent for "raw ..." and present without it.
        XCTAssertNil(try Self.route(search, "raw synthetic crisps"))
        XCTAssertNotNil(try Self.route(search, "synthetic crisps"))
        // The same fix for a v1 to v3 entry whose state is raw, against a "cooked" query.
        let v3 = try Self.search(try Self.fixture("personal-food-database-estimates-v3/golden.json"))
        XCTAssertNil(try Self.route(v3, "cooked synthetic crème spread"))
        XCTAssertNotNil(try Self.route(v3, "synthetic crème spread"))
    }

    func testAGenericRowIsLeftOutOnlyWhenItContradicts() throws {
        var resolver = try Self.defaultResolver()
        resolver.identities["cofid:fish"] = try Self.identity(.cooked)
        let cooked = try XCTUnwrap(Self.route(try Self.search(try Self.v4(), resolver: resolver), "raw synthetic tinned fish"))
        XCTAssertEqual(cooked.matches.map { $0.personalDatabase?.isGenericReference }, [false], "the cooked record is absent")
        XCTAssertFalse(cooked.confirmation.sourceReleases.contains { $0.sourceReleaseID == Self.recordRelease.sourceReleaseID })
        resolver.identities["cofid:fish"] = try Self.identity(.raw)
        let raw = try XCTUnwrap(Self.route(try Self.search(try Self.v4(), resolver: resolver), "raw synthetic tinned fish"))
        XCTAssertEqual(raw.matches.map { $0.personalDatabase?.isGenericReference }, [false, true])
    }

    func testTheCapCountsOnlyOfferedEntriesAndDroppedOnesAddNoRelease() throws {
        let dropped = "owner:sha256:" + String(repeating: "f", count: 64)
        let bytes = try Self.v4 { object in
            var sources = object["sources"] as! [[String: Any]]
            var owner = sources.first { $0["source_id"] as? String == "owner" }!
            owner["source_release_id"] = dropped
            owner["artifact_sha256"] = String(repeating: "f", count: 64)
            owner["manifest_sha256"] = String(repeating: "f", count: 64)
            sources.append(owner)
            object["sources"] = sources
            var items = object["items"] as! [[String: Any]]
            let spread = items.first { $0["title"] as? String == Self.spread }!
            for n in 1...16 {
                var copy = spread
                copy["id"] = String(format: "pfc:ff00000000%02x", n)
                copy["title"] = String(format: "Synthetic Test Spread %02d", n)
                copy["titles"] = [copy["title"]!]
                copy["state"] = n <= 5 ? "cooked" : "raw"
                if n <= 5 {
                    var labels = copy["label_nutrients"] as! [String: [String: Any]]
                    labels["sodium"]!["source_release"] = dropped
                    copy["label_nutrients"] = labels
                }
                items.append(copy)
            }
            object["items"] = items
        }
        let route = try XCTUnwrap(Self.route(try Self.search(bytes), "raw synthetic test spread"))
        XCTAssertEqual(route.matches.count, PersonalFoodDatabaseFoodSearch.maximumEntries)
        XCTAssertTrue(route.matches.allSatisfy { $0.candidate.candidate.identity.preparation.kind == .raw })
        XCTAssertFalse(route.confirmation.sourceReleases.contains { $0.sourceReleaseID.value == dropped })
        let offered = Set(route.matches.flatMap(\.candidate.candidate.evidenceIDs))
        XCTAssertTrue(route.confirmation.evidence.filter(ApprovedEstimateSource.isManifest).allSatisfy { offered.contains($0.evidenceID) })
        // A dropped entry with estimates adds no capture manifest: the fish stated as sold is left out
        // of "raw ..." while its raw record's Generic row stays.
        var resolver = try Self.defaultResolver()
        resolver.identities["cofid:fish"] = try Self.identity(.raw)
        let asSold = try Self.v4 { Self.item(&$0, Self.fish) { $0["identity_facts"] = ["preparation": "as_sold", "bone": "unknown",
            "skin": "unknown", "drained": "unknown", "packing_medium": "unknown", "fortification": "unknown"] } }
        let fish = try XCTUnwrap(Self.route(try Self.search(asSold, resolver: resolver), "raw synthetic tinned fish"))
        XCTAssertEqual(fish.matches.map { $0.personalDatabase?.isGenericReference }, [true])
        XCTAssertFalse(fish.confirmation.evidence.contains(where: ApprovedEstimateSource.isManifest))
        XCTAssertNotNil(try Self.route(try Self.search(asSold, resolver: resolver), "synthetic tinned fish")?
            .confirmation.evidence.first(where: ApprovedEstimateSource.isManifest), "offered, it carries its manifest")
    }

    func testWhenEveryDatabaseRowIsDroppedTheCompositeIsV11WithoutTheDatabase() throws {
        let ids = IDs(), other = IDs()
        let database = try Self.search(try Self.v4())
        let with = CompositeGenericFoodSearch(sources: [], databaseSource: database, ids: ids)
        let without = CompositeGenericFoodSearch(sources: [], ids: other)
        let request = try Self.request("raw synthetic crisps")
        guard case let .noResult(a) = try with.search(request), case let .noResult(b) = try without.search(request) else {
            return XCTFail("no database row survives, so the composite has no result")
        }
        XCTAssertEqual(a.guidance, b.guidance)
        XCTAssertEqual(a.suggestedQueries, b.suggestedQueries)
        XCTAssertEqual(a.title, b.title)
        XCTAssertEqual(CompositeGenericFoodSearch.version, "composite-generic-ranking-v12")
    }

    // MARK: Test 6, re-resolution

    func testReresolutionTargetsFollowTheSchemaAndAStatedMismatchGivesNoProposal() throws {
        for harness in try LedgerFixtures.harnesses() {
            defer { harness.cleanup() }
            let resolver = try Self.defaultResolver()
            let store = InMemoryPersonalFoodDatabaseStore()
            let v3 = try Self.fixture("personal-food-database-estimates-v3/golden.json")
            let index = try Self.index(v3, resolver: resolver, store: store)
            let search = PersonalFoodDatabaseFoodSearch(index: index, resolver: resolver, ids: RandomLedgerIDGenerator())
            let route = try XCTUnwrap(Self.route(search, "synthetic example oats"))
            let input = try XCTUnwrap(route.choosing(0))
            let candidate = input.candidates[0]
            var state = FoodConfirmationState(input: input)
            state.correction = FoodCorrection(name: candidate.name, brand: candidate.brand, variant: candidate.variant,
                identity: try DecisiveIdentity(preparation: PreparationState(kind: .raw), bone: .withBone, skin: .notApplicable,
                    drained: .notApplicable, packingMedium: .named(LedgerText("not applicable")), fortification: .unfortified,
                    servingBasis: .per100Grams),
                itemClass: candidate.itemClass, nutrients: candidate.candidate.nutrients, reason: try LedgerText("Synthetic reason"))
            state.decision = .accepted
            state.quantity.value = 30
            let ledger = try LedgerFixtures.service(harness.committer)
            let archive = try XCTUnwrap(harness.committer as? any FoodArchiveLedgerAccess)
            let saved = try FoodConfirmationService(ledger: ledger, reader: harness.reader, clock: LedgerFixtures.clock,
                ids: RandomLedgerIDGenerator(), digester: SHA256Digester()).save(state, operationID: LedgerFixtures.operationID(901))
            let provider = PersonalFoodDatabaseReresolutionProvider(index: index, resolver: resolver, ids: RandomLedgerIDGenerator())
            let service = FoodReresolutionService(ledger: ledger,
                reader: FoodReresolutionHistory(archive: archive, confirmations: harness.reader),
                provider: FoodReresolutionProviderSet([provider]), clock: LedgerFixtures.clock, ids: RandomLedgerIDGenerator())
            XCTAssertEqual(try service.targets().map(\.methodVersion.value), ["pfc-resolution-v1"])

            // A v4 release whose oats state boneless: no proposal, and a direct one throws.
            try store.install(bytes: try Self.v4 { Self.item(&$0, Self.oats) { $0["identity_facts"] = [
                "preparation": "raw", "bone": "boneless", "skin": "unknown", "drained": "unknown", "packing_medium": "unknown",
                "fortification": "unknown"] } }, manifest: Self.manifest(try Self.v4 { Self.item(&$0, Self.oats) { $0["identity_facts"] = [
                "preparation": "raw", "bone": "boneless", "skin": "unknown", "drained": "unknown", "packing_medium": "unknown",
                "fortification": "unknown"] } }))
            index.invalidate(); index.warm()
            let mismatch = try XCTUnwrap(service.targets().first)
            XCTAssertEqual(mismatch.methodVersion.value, "pfc-resolution-v2")
            XCTAssertTrue(try service.proposals(logItemID: saved.logItem.logItemID, target: mismatch).isEmpty)
            guard case let .confirmation(fresh) = try provider.candidates(for: saved, target: mismatch, at: LedgerFixtures.clock.now())
            else { return XCTFail("the entry is still there") }
            XCTAssertThrowsError(try FoodReresolutionProposal(before: saved, target: mismatch, input: fresh.confirmation,
                                                               candidate: fresh.confirmation.candidates[0])) {
                XCTAssertEqual($0 as? FoodReresolutionError, .incompatibleIdentity)
            }

            // Matching details update; target and candidate both carry pfc-resolution-v2.
            let matching = try Self.v4 { Self.item(&$0, Self.oats) { $0["identity_facts"] = [
                "preparation": "raw", "bone": "with_bone", "skin": "unknown", "drained": "unknown", "packing_medium": "unknown",
                "fortification": "unknown"] } }
            try store.install(bytes: matching, manifest: Self.manifest(matching))
            index.invalidate(); index.warm()
            let target = try XCTUnwrap(service.targets().first)
            let proposals = try service.proposals(logItemID: saved.logItem.logItemID, target: target)
            XCTAssertFalse(proposals.isEmpty)
            XCTAssertEqual(target.methodVersion.value, "pfc-resolution-v2")
            XCTAssertEqual(proposals[0].candidate.candidate.matchMetadata?.methodVersion.value, "pfc-resolution-v2")
            // Resolver-built Generic rows keep pfc-resolution-v1.
            XCTAssertEqual(try Self.record("cofid:x", identity: Self.identity(.raw), evidenceIDs: [])
                .candidate.matchMetadata?.methodVersion.value, "pfc-resolution-v1")
        }
    }

    // MARK: Test 7, Confirm line and decision I1-D1 on a merged entry

    /// Review fix: on a merged entry only the facts the note lists change without a typed reason; a
    /// fact the merged record states (skin) or the preparation from `state` still needs one.
    @MainActor
    func testOnAMergedEntryOnlyTheFileFactsChangeWithoutAReason() throws {
        var resolver = try Self.defaultResolver()
        resolver.identities["cofid:example"] = try DecisiveIdentity(preparation: PreparationState(kind: .raw), bone: .unknown,
            skin: .skinOn, drained: .unknown, packingMedium: .unknown, fortification: .unknown, servingBasis: .per100Grams)
        let bytes = try Self.v4 { Self.item(&$0, Self.oats) { $0["identity_facts"] = ["preparation": "unknown",
            "bone": "not_applicable", "skin": "unknown", "drained": "unknown", "packing_medium": "unknown",
            "fortification": "unknown"] } }
        let route = try XCTUnwrap(Self.route(try Self.search(bytes, resolver: resolver), "synthetic example oats"))
        XCTAssertEqual(route.matches.count, 1, "merged")
        let state = FoodConfirmationState(input: try XCTUnwrap(route.choosing(0)))
        XCTAssertEqual(Self.note(state.selectedCandidate), "Food details from your food database: no bone")
        let model = FoodConfirmationViewModel(state: state) { _ in throw FoodConfirmationSaveError.noAcceptedCandidate }
        var bone = FoodDetailsDraft(model: model)
        bone.bone = BoneState.withBone.rawValue
        XCTAssertTrue(bone.canApply(in: state))
        XCTAssertEqual(bone.correction(in: state)?.reason.value, FoodDetailsFillPolicy.databaseFactChangedReason)
        var skin = FoodDetailsDraft(model: model)
        skin.skin = SkinState.skinless.rawValue
        XCTAssertFalse(skin.changesDatabaseFactsOnly(in: state))
        XCTAssertFalse(skin.canApply(in: state), "the record's skin needs a typed reason")
        var preparation = FoodDetailsDraft(model: model)
        preparation.preparation = PreparationKind.cooked.rawValue
        XCTAssertFalse(preparation.canApply(in: state), "the preparation from state needs a typed reason")
        var both = bone
        both.skin = SkinState.skinless.rawValue
        XCTAssertFalse(both.canApply(in: state), "one record fact among the changes still needs a reason")
    }

    // MARK: Test 8, saving, re-log and quick add

    func testAV4LogSavedWithoutACorrectionIsQuickAddEligibleAndKeepsItsFacts() throws {
        for harness in try LedgerFixtures.harnesses() {
            defer { harness.cleanup() }
            let bytes = try Self.v4 { Self.item(&$0, Self.oats) { $0["identity_facts"] = Self.allStated } }
            let resolver = try Self.defaultResolver()
            let index = try Self.index(bytes, resolver: resolver)
            let search = PersonalFoodDatabaseFoodSearch(index: index, resolver: resolver, ids: RandomLedgerIDGenerator())
            let input = try XCTUnwrap(try Self.route(search, "synthetic example oats")?.choosing(0))
            var state = FoodConfirmationState(input: input)
            XCTAssertTrue(state.unresolvedIdentity.isEmpty)
            state.decision = .accepted
            state.quantity.value = 40
            let saved = try FoodConfirmationService(ledger: LedgerFixtures.service(harness.committer), reader: harness.reader,
                clock: LedgerFixtures.clock, ids: RandomLedgerIDGenerator(), digester: SHA256Digester())
                .save(state, operationID: LedgerFixtures.operationID(902))
            let restored = try PopulatedFoodCandidate(candidate: saved.candidateDecision.candidate, name: saved.productVersion.name,
                brand: saved.productVersion.brand, itemClass: saved.productVersion.itemClass)
            XCTAssertNotNil(Self.note(restored), "the note is saved with the candidate")
            XCTAssertTrue(QuickAddPolicy.pinnedIsUncorrected(saved))
            // Re-log rebuilds from the saved candidate, whatever a later import says.
            let relog = FoodConfirmationState(input: try PopulatedFoodConfirmation(evidence: input.evidence,
                sourceReleases: input.sourceReleases, candidates: [restored],
                expectedIdentity: saved.candidateDecision.candidate.identity,
                expectedEdibleQuantity: saved.candidateDecision.candidate.edibleQuantity))
            XCTAssertEqual(relog.selectedCandidate.candidate.identity, saved.productVersion.identity)
            var ready = relog
            ready.quantity.value = 40
            XCTAssertEqual(QuickAddPolicy.eligibility(pinned: saved, pinnedIsEstimate: false, rebuilt: ready,
                now: LedgerFixtures.clock.now(), calendar: ApprovedEstimateConfirmContractTests.utc), .sheet)
            // Review fixes: with every fact stated the line shows and the sheet can still be opened to
            // change one; on the reopened entry the line is hidden.
            let reopenedState = try XCTUnwrap(try FoodConfirmationService(ledger: LedgerFixtures.service(harness.committer),
                reader: harness.reader, clock: LedgerFixtures.clock, ids: RandomLedgerIDGenerator(), digester: SHA256Digester())
                .reopen(logItemID: saved.logItem.logItemID))
            XCTAssertNotNil(reopenedState.reopened)
            let fresh = state
            MainActor.assumeIsolated {
                let model = FoodConfirmationViewModel(state: fresh) { _ in throw FoodConfirmationSaveError.noAcceptedCandidate }
                XCTAssertEqual(model.databaseFactsLine,
                    "Food details from your food database: no bone, no skin, nothing to drain, no packing liquid, not fortified")
                XCTAssertEqual(model.foodDetailsActionTitle, FoodConfirmationViewModel.correctFoodDetailsTitle)
                let reopened = FoodConfirmationViewModel(state: reopenedState) { _ in throw FoodConfirmationSaveError.noAcceptedCandidate }
                XCTAssertNil(reopened.databaseFactsLine)
            }
        }
    }
}
