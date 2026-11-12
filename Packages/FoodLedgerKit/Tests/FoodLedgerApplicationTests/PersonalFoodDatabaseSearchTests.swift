@testable import FoodLedgerApplication
import FoodLedgerDomain
import FoodLedgerTestSupport
import Foundation
import XCTest

/// P1c contract (import v1 sections 5 to 7; phase 1 plan sections 5 and 5.1). Synthetic fixtures only.
final class PersonalFoodDatabaseSearchTests: XCTestCase {
    static let fixtures = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("docs/fixtures/personal-food-database-v1")

    static func golden(_ edit: (String) -> String = { $0 }) throws -> Data {
        let text = try String(decoding: Data(contentsOf: fixtures.appendingPathComponent("golden.json")), as: UTF8.self)
        return Data(edit(text).utf8)
    }

    final class IDs: LedgerIDGenerating, @unchecked Sendable {
        private var value = 1
        func makeID<Tag>(_ tag: Tag.Type) throws -> LedgerID<Tag> {
            defer { value += 1 }
            return try LedgerID(String(format: "00000000-0000-0000-0000-%012x", value))
        }
    }

    /// A synthetic generic record standing in for an adapter's own candidate.
    struct FakeResolver: GenericRecordResolving {
        var preparation: PreparationKind = .raw
        var basis: ResolutionBasis = .per100Grams
        var records: Set<String> = ["cofid:example", "tfda:X0001"]
        var energy: Double = 380

        static let release = SourceRelease(
            sourceReleaseID: try! ExternalIdentifier("cofid:synthetic"), sourceID: try! ExternalIdentifier("cofid"),
            releasedAt: Date(timeIntervalSince1970: 0), artifactHash: try! SHA256Digest(String(repeating: "d", count: 64)),
            schemaVersion: try! LedgerText("synthetic"), pipelineVersion: try! LedgerText("synthetic"),
            licence: try! LedgerText("synthetic"), attribution: try! LedgerText("synthetic"),
            manifestHash: try! SHA256Digest(String(repeating: "d", count: 64)))

        func contains(_ reference: GenericRecordReference) -> Bool { records.contains(reference.recordID) }

        func resolve(_ reference: GenericRecordReference, evidenceIDs: [EvidenceID], queryAlias: String) -> ResolvedGenericRecord? {
            guard contains(reference) else { return nil }
            return try? ResolvedGenericRecord(candidate: Self.candidate(reference.recordID, preparation: preparation,
                basis: basis, energy: energy, evidenceIDs: evidenceIDs), release: Self.release)
        }

        static func candidate(_ recordID: String, preparation: PreparationKind, basis: ResolutionBasis, energy: Double,
                              evidenceIDs: [EvidenceID]) throws -> PopulatedFoodCandidate {
            let record = try ExternalIdentifier(recordID)
            func value(_ amount: Double, _ key: NutrientKey) throws -> NutrientValue {
                .augmented(try ExactNutrientValue(amount: amount, unit: key.canonicalUnit,
                    sourceValue: .exact(SourceExactNutrientValue(amount: amount, unit: LedgerText(key.canonicalUnit.rawValue), basis: basis)),
                    provenance: [NutrientProvenance(sourceKind: .genericCompositionDataset, sourceID: release.sourceID,
                                                    sourceReleaseID: release.sourceReleaseID, recordID: record)]))
            }
            let nutrients = try NutrientSet(entries: NutrientKey.allCases.map { key in
                switch key {
                case .energyConsumed: try NutrientEntry(key: key, value: value(energy, key))
                case .protein: try NutrientEntry(key: key, value: value(11, key))
                case .sodium: try NutrientEntry(key: key, value: value(9, key))
                default: try NutrientEntry(key: key, value: .unknown(.notDeclared))
                }
            })
            let unit: QuantityUnit = basis == .per100Grams ? .grams : .millilitres
            return try PopulatedFoodCandidate(candidate: ProviderNeutralCandidate(
                sourceReleaseID: release.sourceReleaseID, recordID: record,
                identity: DecisiveIdentity(preparation: PreparationState(kind: preparation), bone: .unknown, skin: .unknown,
                    drained: .unknown, packingMedium: .unknown, fortification: .unknown, servingBasis: basis),
                edibleQuantity: .known(PositiveQuantity(value: 100, unit: unit), conversionVersionID: nil),
                nutrients: nutrients, evidenceIDs: evidenceIDs,
                matchMetadata: CandidateMatchMetadata(methodVersion: LedgerText(PersonalFoodDatabaseCandidateBuilder.methodVersion),
                    score: 1, materialDifferences: [])),
                name: LedgerText("Synthetic generic " + recordID), itemClass: .food)
        }
    }

    func snapshot(_ bytes: Data, resolver: some GenericRecordResolving = FakeResolver()) throws -> PersonalFoodDatabaseIndex.Snapshot {
        let store = InMemoryPersonalFoodDatabaseStore()
        try store.install(bytes: bytes, manifest: manifest(bytes))
        let index = PersonalFoodDatabaseIndex(store: store, resolver: resolver)
        index.warm()
        return try XCTUnwrap(index.snapshot())
    }

    func manifest(_ bytes: Data) throws -> PersonalFoodDatabaseManifest {
        let digest = try SHA256Digester().sha256(bytes)
        guard case let .success(file) = PersonalFoodDatabaseCodec.decode(bytes) else { throw FoodLedgerValidationError.invalidBasis }
        return PersonalFoodDatabaseManifest(schema: PersonalFoodDatabaseFile.schema,
            releaseID: PersonalFoodDatabaseRelease.releaseID(fileSHA256: digest), fileSHA256: digest,
            generated: file.generated, importedAt: Date(timeIntervalSince1970: 1_794_000_000), entryCount: file.entries.count)
    }

    func build(_ snapshot: PersonalFoodDatabaseIndex.Snapshot, id: String, resolver: FakeResolver = FakeResolver())
        throws -> PersonalFoodDatabaseCandidateBuilder.Built? {
        let entry = try XCTUnwrap(snapshot.file.entries.first { $0.id == id })
        let evidence = [try EvidenceID("00000000-0000-0000-0000-0000000000aa")]
        let record = entry.genericReference.flatMap {
            resolver.resolve(GenericRecordReference($0), evidenceIDs: evidence, queryAlias: entry.title)
        }
        return try PersonalFoodDatabaseCandidateBuilder.build(entry: entry, file: snapshot.file,
            databaseRelease: snapshot.release, record: record, evidenceIDs: evidence, score: 1)
    }

    func value(_ built: PersonalFoodDatabaseCandidateBuilder.Built, _ key: NutrientKey) -> NutrientValue? {
        built.candidate.candidate.nutrients.entries.first { $0.key == key }?.value
    }

    static let oats = "pfc:65799635db4d"
    static let tofu = "pfc:7955aa2f6d66"
    static let spread = "pfc:bb273a5023cb"

    // MARK: A1 merge

    func testMergeTakesOwnerThenProductThenGenericAndStatesFollowDecision11() throws {
        let built = try XCTUnwrap(build(try snapshot(Self.golden()), id: Self.oats))
        XCTAssertTrue(built.merged)
        guard case let .measured(energy)? = value(built, .energyConsumed) else { return XCTFail("owner value is measured") }
        XCTAssertEqual(energy.amount, 370)
        XCTAssertEqual(energy.provenance.first?.sourceKind, .manualDeclaration)
        XCTAssertEqual(energy.provenance.first?.sourceID.value, "owner")
        XCTAssertNil(energy.provenance.first?.recordID)
        guard case let .augmented(sodium)? = value(built, .sodium) else { return XCTFail("product value is augmented") }
        XCTAssertEqual(sodium.amount, 5)
        XCTAssertEqual(sodium.provenance.first?.sourceKind, .exactProductDataset)
        XCTAssertEqual(sodium.provenance.first?.recordID?.value, "off:gtin:00000000000017")
        XCTAssertFalse(NutrientDerivation.isCalculated(.augmented(sodium)), "a unit conversion is not a calculation")
        guard case let .augmented(protein)? = value(built, .protein) else { return XCTFail("generic fills the rest") }
        XCTAssertEqual(protein.provenance.first?.sourceKind, .genericCompositionDataset)
        XCTAssertEqual(protein.provenance.first?.sourceReleaseID, FakeResolver.release.sourceReleaseID)
        XCTAssertEqual(built.candidate.candidate.matchMetadata?.methodVersion.value, "pfc-resolution-v1")
    }

    func testEveryProvenanceReleaseIsCarriedAndReferencesAreOpaque() throws {
        let snapshot = try snapshot(Self.golden())
        for id in [Self.oats, Self.spread] {
            let built = try XCTUnwrap(build(snapshot, id: id))
            let carried = Set(built.releases.map(\.sourceReleaseID))
            for entry in built.candidate.candidate.nutrients.entries {
                for provenance in entry.value.provenance {
                    XCTAssertTrue(carried.contains(provenance.sourceReleaseID), "\(id) \(entry.key)")
                    if provenance.sourceKind != .genericCompositionDataset {
                        XCTAssertEqual(provenance.manifestReference?.value, "\(snapshot.release.sourceReleaseID.value)#\(id)")
                    }
                }
            }
            XCTAssertEqual(built.releases.first, snapshot.release)
        }
    }

    func testSaltDerivedOwnerValueIsCalculated() throws {
        let built = try XCTUnwrap(build(try snapshot(Self.golden()), id: Self.spread))
        guard case let .measured(sodium)? = value(built, .sodium) else { return XCTFail() }
        XCTAssertEqual(sodium.amount, 200)
        XCTAssertTrue(NutrientDerivation.isCalculated(.measured(sodium)))
        XCTAssertFalse(built.merged)
        XCTAssertEqual(built.candidate.candidate.identity.preparation.kind, .raw)
        XCTAssertEqual(built.candidate.itemClass, .food)
        XCTAssertNil(built.candidate.variant, "the source name is never put in an identity field")
    }

    func testMergeIsRefusedForUnknownPreparationOtherKindOrPer100Millilitres() throws {
        let snapshot = try snapshot(Self.golden())
        for resolver in [FakeResolver(preparation: .unknown), FakeResolver(preparation: .cooked),
                         FakeResolver(basis: .per100Millilitres)] {
            let built = try XCTUnwrap(build(snapshot, id: Self.oats, resolver: resolver))
            XCTAssertFalse(built.merged)
            XCTAssertEqual(value(built, .protein), .unknown(.notDeclared))
            XCTAssertFalse(built.releases.contains(FakeResolver.release))
        }
    }

    func testFreshWholeOrderPutsGenericBeforeTheProductRecord() throws {
        let bytes = try Self.golden {
            $0.replacingOccurrences(of: "\"grain_cereal\",\n   \"product_type\": \"packaged_single_ingredient\"",
                                    with: "\"grain_cereal\",\n   \"product_type\": \"fresh_whole\"")
        }
        let built = try XCTUnwrap(build(try snapshot(bytes), id: Self.oats))
        guard case let .augmented(sodium)? = value(built, .sodium) else { return XCTFail() }
        XCTAssertEqual(sodium.amount, 9, "generic before exact_product_dataset for fresh_whole")
        guard case .measured? = value(built, .energyConsumed) else { return XCTFail("owner value still first") }
    }

    func testSameLevelDisagreementIsAConflictAndUnknown() throws {
        let release = FakeResolver.release
        func label(_ amount: Double) throws -> NutrientValue {
            .measured(try ExactNutrientValue(amount: amount, unit: .milligrams,
                sourceValue: .exact(SourceExactNutrientValue(amount: amount, unit: LedgerText("mg"), basis: .per100Grams)),
                provenance: [NutrientProvenance(sourceKind: .manualDeclaration, sourceID: ExternalIdentifier("owner"),
                                                sourceReleaseID: release.sourceReleaseID)]))
        }
        let conflict = try PersonalFoodDatabaseCandidateBuilder.resolve(key: .sodium, level: [label(1), label(2)])
        XCTAssertEqual(conflict.value, .unknown(.conflictingEvidence))
        XCTAssertEqual(conflict.status, .conflict)
        XCTAssertEqual(conflict.conflictCandidates.count, 2)
        XCTAssertEqual(try PersonalFoodDatabaseCandidateBuilder.resolve(key: .sodium, level: [label(1), label(1)]).value, try label(1))
        // In v1 the codec keeps one label value per nutrient, so the conflict cannot come from a file.
        for entry in try snapshot(Self.golden()).file.entries {
            XCTAssertEqual(Set(entry.labelNutrients.map(\.key)).count, entry.labelNutrients.count)
        }
    }

    func testPer100MillilitreEntryKeepsItsBasisAndNeverMerges() throws {
        let bytes = try Self.golden {
            $0.replacingOccurrences(of: "\"category\": \"other\",\n   \"product_type\": \"packaged_single_ingredient\",\n   \"state\": \"raw\",\n   \"basis\": \"per_100_g\"",
                                    with: "\"category\": \"beverage\",\n   \"product_type\": \"packaged_single_ingredient\",\n   \"state\": \"raw\",\n   \"basis\": \"per_100_ml_as_labelled\"")
        }
        let built = try XCTUnwrap(build(try snapshot(bytes), id: Self.spread))
        XCTAssertEqual(built.candidate.candidate.identity.servingBasis, .per100Millilitres)
        XCTAssertEqual(built.candidate.candidate.edibleQuantity, .known(try PositiveQuantity(value: 100, unit: .millilitres), conversionVersionID: nil))
        XCTAssertEqual(built.candidate.itemClass, .drink)
    }

    func testEntryWithNoKnownNutrientIsLeftOut() throws {
        XCTAssertNil(try build(try snapshot(Self.golden()), id: Self.tofu), "no label values and a candidate role")
    }

    // MARK: Search route

    func makeSearch(_ bytes: Data, resolver: FakeResolver = FakeResolver(), store: InMemoryPersonalFoodDatabaseStore? = nil)
        throws -> (PersonalFoodDatabaseFoodSearch, PersonalFoodDatabaseIndex, InMemoryPersonalFoodDatabaseStore) {
        let store = store ?? InMemoryPersonalFoodDatabaseStore()
        try store.install(bytes: bytes, manifest: manifest(bytes))
        let index = PersonalFoodDatabaseIndex(store: store, resolver: resolver)
        index.warm()
        return (PersonalFoodDatabaseFoodSearch(index: index, resolver: resolver, ids: IDs()), index, store)
    }

    func request(_ text: String) throws -> GenericFoodSearchRequest {
        GenericFoodSearchRequest(text: try LedgerText(text), capturedAt: Date(timeIntervalSince1970: 1_794_000_000),
                                 locale: try LedgerText("en-GB"))
    }

    func matches(_ outcome: GenericFoodSearchOutcome) -> [GenericFoodMatch] {
        if case let .confirmation(route) = outcome { return route.matches }
        return []
    }

    func testStepsExactNameAndGenericRow() throws {
        let (search, _, _) = try makeSearch(Self.golden())
        let exact = matches(try search.search(request("synthetic example oats")))
        XCTAssertEqual(exact.map(\.candidate.candidate.recordID.value), [Self.oats])
        XCTAssertEqual(exact.first?.isExactName, true)
        XCTAssertEqual(exact.first?.personalDatabase, PersonalFoodDatabaseMatchContext(step: .titleOrAlias, isGenericReference: false))
        XCTAssertNil(exact.first?.candidate.candidate.nutrients.entries.first { $0.key == .energyConsumed }.flatMap {
            if case .unknown = $0.value { $0 } else { nil } })
        let concept = matches(try search.search(request("tofu")))
        XCTAssertEqual(concept.map(\.candidate.candidate.recordID.value), ["tfda:X0001"], "entry left out, record offered")
        XCTAssertEqual(concept.first?.personalDatabase, PersonalFoodDatabaseMatchContext(step: .concept, isGenericReference: true))
        let chinese = matches(try search.search(request("合成豆腐")))
        XCTAssertEqual(chinese.first?.personalDatabase?.step, .titleOrAlias)
        XCTAssertNil(chinese.first?.candidate.candidate.recordID.value.hasPrefix("pfc:") == true ? "entry" : nil)
        XCTAssertTrue(matches(try search.search(request("lentils"))).isEmpty)
    }

    func testRouteNeverSetsReuseAndConfirmationCarriesEveryRelease() throws {
        let (search, _, _) = try makeSearch(Self.golden())
        guard case let .confirmation(route) = try search.search(request("synthetic")) else { return XCTFail() }
        XCTAssertNil(route.reuse)
        let carried = Set(route.confirmation.sourceReleases.map(\.sourceReleaseID))
        for candidate in route.confirmation.candidates {
            XCTAssertTrue(carried.contains(candidate.candidate.sourceReleaseID))
            for entry in candidate.candidate.nutrients.entries {
                for provenance in entry.value.provenance { XCTAssertTrue(carried.contains(provenance.sourceReleaseID)) }
            }
        }
        XCTAssertEqual(route.matches.map(\.candidate.candidate.recordID.value).filter { $0.hasPrefix("pfc:") }.count, 2)
    }

    func testOrderIsDeterministicByStepPreferenceThenID() throws {
        let (search, _, _) = try makeSearch(Self.golden())
        let first = matches(try search.search(request("synthetic"))).map(\.candidate.candidate.recordID.value)
        let second = matches(try search.search(request("synthetic"))).map(\.candidate.candidate.recordID.value)
        XCTAssertEqual(first, second)
        XCTAssertEqual(first, first.sorted(), "same step and preference fall back to entry ID")
    }

    // MARK: Index

    func testLockedLoadIsRetriedAndDamagedGivesNoRows() throws {
        let bytes = try Self.golden()
        let store = InMemoryPersonalFoodDatabaseStore()
        try store.install(bytes: bytes, manifest: manifest(bytes))
        store.locked = true
        let index = PersonalFoodDatabaseIndex(store: store, resolver: FakeResolver())
        index.warm()
        XCTAssertNil(index.snapshot())
        store.locked = false
        index.warm()
        XCTAssertNotNil(index.snapshot(), "a locked result is never cached")
        store.damaged = true
        index.invalidate()
        index.warm()
        XCTAssertNil(index.snapshot())
        let search = PersonalFoodDatabaseFoodSearch(index: index, resolver: FakeResolver(), ids: IDs())
        guard case let .noResult(route) = try search.search(request("oats")) else { return XCTFail() }
        XCTAssertTrue(route.suggestedQueries.isEmpty)
    }

    func testUnresolvedReferenceCount() throws {
        XCTAssertEqual(try snapshot(Self.golden()).unresolvedReferenceCount, 0)
        XCTAssertEqual(try snapshot(Self.golden(), resolver: FakeResolver(records: [])).unresolvedReferenceCount, 2)
    }

    func testInvalidateDuringALoadNeverInstallsAStaleRelease() throws {
        let bytes = try Self.golden()
        let store = GatedStore(InMemoryPersonalFoodDatabaseStore())
        try store.inner.install(bytes: bytes, manifest: manifest(bytes))
        let index = PersonalFoodDatabaseIndex(store: store, resolver: FakeResolver())
        let loading = expectation(description: "load")
        DispatchQueue.global().async { index.warm(); loading.fulfill() }
        store.started.wait()
        XCTAssertNil(index.snapshot(), "search never waits for a load")
        index.invalidate()
        store.proceed.signal()
        wait(for: [loading], timeout: 5)
        XCTAssertNil(index.snapshot(), "the load began before invalidate()")
        index.warm()
        XCTAssertNotNil(index.snapshot())
    }

    final class GatedStore: PersonalFoodDatabaseStoring, @unchecked Sendable {
        let inner: InMemoryPersonalFoodDatabaseStore
        let started = DispatchSemaphore(value: 0)
        let proceed = DispatchSemaphore(value: 0)
        private var first = true
        init(_ inner: InMemoryPersonalFoodDatabaseStore) { self.inner = inner }
        func activeRelease() throws -> PersonalFoodDatabaseInstalledRelease? {
            if first { first = false; started.signal(); proceed.wait() }
            return try inner.activeRelease()
        }
        func install(bytes: Data, manifest: PersonalFoodDatabaseManifest) throws { try inner.install(bytes: bytes, manifest: manifest) }
        func remove() throws -> Bool { try inner.remove() }
    }

    // MARK: Composite

    struct Fixed: GenericFoodSearching {
        let outcome: @Sendable (GenericFoodSearchRequest) throws -> GenericFoodSearchOutcome
        func search(_ request: GenericFoodSearchRequest) throws -> GenericFoodSearchOutcome { try outcome(request) }
    }

    /// A source answering with the synthetic record as its own candidate (as CoFID would).
    func recordSource(energy: Double = 380, guidance: String? = nil) -> Fixed {
        Fixed { request in
            let evidence = try XCTUnwrap(request.captureEvidence)
            let candidate = try FakeResolver.candidate("tfda:X0001", preparation: .raw, basis: .per100Grams, energy: energy,
                                                      evidenceIDs: [evidence.evidenceID] + request.additionalEvidence.map(\.evidenceID))
            return .confirmation(GenericFoodConfirmationRoute(confirmation: try PopulatedFoodConfirmation(
                evidence: [evidence] + request.additionalEvidence, sourceReleases: [FakeResolver.release], candidates: [candidate],
                expectedIdentity: candidate.candidate.identity, expectedEdibleQuantity: candidate.candidate.edibleQuantity),
                matches: [GenericFoodMatch(candidate: candidate, isExactName: true)]))
        }
    }

    func testCompositeWithEmptyDatabaseIsUnchangedAndNeverTakesItsGuidance() throws {
        let empty = PersonalFoodDatabaseFoodSearch(index: PersonalFoodDatabaseIndex(store: InMemoryPersonalFoodDatabaseStore(),
            resolver: FakeResolver()), resolver: FakeResolver(), ids: IDs())
        let miss = Fixed { request in .noResult(GenericFoodNoResultRoute(evidence: try XCTUnwrap(request.captureEvidence),
                                                                          guidance: "Source guidance", suggestedQueries: ["oat"])) }
        for sources in [[recordSource()], [miss]] {
            let plain = try CompositeGenericFoodSearch(sources: sources, ids: IDs()).search(request("tofu"))
            let withDatabase = try CompositeGenericFoodSearch(sources: sources, databaseSource: empty, ids: IDs()).search(request("tofu"))
            XCTAssertEqual(plain, withDatabase)
        }
        guard case let .noResult(route) = try CompositeGenericFoodSearch(sources: [], regionalSources: [miss],
            databaseSource: empty, ids: IDs()).search(request("tofu")) else { return XCTFail() }
        XCTAssertEqual(route.guidance, "Source guidance", "the database no-result is never the fallback")
    }

    func testCompositeKeepsTheDatabaseCopyOfTheSameRecordAndThrowsOnDifferingFacts() throws {
        let (database, _, _) = try makeSearch(Self.golden())
        for deferred in [true, false] {
            guard case let .confirmation(route) = try CompositeGenericFoodSearch(sources: [recordSource()], regionalSources: [],
                databaseSource: database, promotesRegional: { _ in !deferred }, ids: IDs()).search(request("tofu")) else { return XCTFail() }
            XCTAssertEqual(route.matches.count, 1)
            XCTAssertEqual(route.matches[0].personalDatabase?.isGenericReference, true)
            XCTAssertEqual(route.matches[0].candidate.candidate.matchMetadata?.methodVersion.value, "pfc-resolution-v1")
        }
        XCTAssertThrowsError(try CompositeGenericFoodSearch(sources: [recordSource(energy: 1)], databaseSource: database,
                                                            ids: IDs()).search(request("tofu")))
    }

    func testCompositeNeverDedupesRowsFromOtherSources() throws {
        let rows = try CompositeGenericFoodSearch(sources: [recordSource(), recordSource()], ids: IDs()).search(request("tofu"))
        XCTAssertEqual(matches(rows).count, 2, "existing behaviour: duplicates from two other sources are untouched")
    }

    func testDatabaseRowsJoinGroupZeroAheadOfDeferredRegionalRows() throws {
        let (database, _, _) = try makeSearch(Self.golden())
        let regional = Fixed { request in
            let evidence = try XCTUnwrap(request.captureEvidence)
            let candidate = try FakeResolver.candidate("regional:1", preparation: .raw, basis: .per100Grams, energy: 1,
                                                      evidenceIDs: [evidence.evidenceID])
            return .confirmation(GenericFoodConfirmationRoute(confirmation: try PopulatedFoodConfirmation(
                evidence: [evidence], sourceReleases: [FakeResolver.release], candidates: [candidate],
                expectedIdentity: candidate.candidate.identity, expectedEdibleQuantity: candidate.candidate.edibleQuantity),
                matches: [GenericFoodMatch(candidate: candidate, isExactName: true)]))
        }
        let rows = matches(try CompositeGenericFoodSearch(sources: [], regionalSources: [regional], databaseSource: database,
                                                         ids: IDs()).search(request("synthetic example oats")))
        XCTAssertEqual(rows.first?.candidate.candidate.recordID.value, Self.oats)
        XCTAssertEqual(rows.last?.candidate.candidate.recordID.value, "regional:1")
    }

    // MARK: Invariant review fixes

    /// Two entries naming the same record give one Generic row (unique search IDs).
    func testTwoEntriesNamingOneRecordGiveOneGenericRow() throws {
        let bytes = try Self.golden {
            $0.replacingOccurrences(of: "\"match\": \"same_food_same_state\",\n    \"role\": \"merge\"",
                                    with: "\"match\": \"close\",\n    \"role\": \"candidate\"")
              .replacingOccurrences(of: "\"generic_reference\": null",
                                    with: "\"generic_reference\": {\n    \"source\": \"cofid\",\n    \"corpus_sha256\": \"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\n    \"record_id\": \"cofid:example\",\n    \"match\": \"close\",\n    \"role\": \"candidate\"\n   }")
        }
        let (search, _, _) = try makeSearch(bytes)
        let rows = matches(try search.search(request("synthetic")))
        XCTAssertEqual(rows.filter { $0.candidate.candidate.recordID.value == "cofid:example" }.count, 1)
        XCTAssertEqual(Set(rows.map(\.searchID)).count, rows.count)
        XCTAssertEqual(rows.filter { $0.candidate.candidate.recordID.value.hasPrefix("pfc:") }.count, 2)
    }

    /// A merged record's own unknown reason is kept when nothing else declares the nutrient.
    func testMergedRecordUnknownReasonIsKept() throws {
        struct MissingConversion: GenericRecordResolving {
            func contains(_ reference: GenericRecordReference) -> Bool { true }
            func resolve(_ reference: GenericRecordReference, evidenceIDs: [EvidenceID], queryAlias: String) -> ResolvedGenericRecord? {
                guard let base = FakeResolver().resolve(reference, evidenceIDs: evidenceIDs, queryAlias: queryAlias),
                      let nutrients = try? NutrientSet(entries: base.candidate.candidate.nutrients.entries.map {
                          $0.key == .fiber ? try NutrientEntry(key: .fiber, value: .unknown(.missingConversion)) : $0 }),
                      let candidate = try? PopulatedFoodCandidate(candidate: ProviderNeutralCandidate(
                          sourceReleaseID: base.candidate.candidate.sourceReleaseID, recordID: base.candidate.candidate.recordID,
                          identity: base.candidate.candidate.identity, edibleQuantity: base.candidate.candidate.edibleQuantity,
                          nutrients: nutrients, evidenceIDs: base.candidate.candidate.evidenceIDs,
                          matchMetadata: base.candidate.candidate.matchMetadata),
                          name: base.candidate.name, itemClass: base.candidate.itemClass) else { return nil }
                return ResolvedGenericRecord(candidate: candidate, release: base.release)
            }
        }
        let snapshot = try snapshot(Self.golden())
        let entry = try XCTUnwrap(snapshot.file.entries.first { $0.id == Self.oats })
        let evidence = [try EvidenceID("00000000-0000-0000-0000-0000000000aa")]
        let record = MissingConversion().resolve(GenericRecordReference(try XCTUnwrap(entry.genericReference)),
                                                 evidenceIDs: evidence, queryAlias: entry.title)
        let built = try XCTUnwrap(PersonalFoodDatabaseCandidateBuilder.build(entry: entry, file: snapshot.file,
            databaseRelease: snapshot.release, record: record, evidenceIDs: evidence, score: 1))
        XCTAssertTrue(built.merged)
        XCTAssertEqual(value(built, .fiber), .unknown(.missingConversion))
        XCTAssertEqual(value(built, .calcium), .unknown(.notDeclared))
    }

    /// Qodo (local review): a Generic row exactly naming its record ranks as exact, and the kept
    /// database copy keeps the source route's exact status.
    func testGenericRowExactNameAndDedupeKeepsExactStatus() throws {
        let (database, _, _) = try makeSearch(Self.golden())
        let generic = matches(try database.search(request("tofu"))).first { $0.personalDatabase?.isGenericReference == true }
        XCTAssertEqual(generic?.isExactName, false, "the record's own name is not the query")
        let kept = try CompositeGenericFoodSearch.dedupeDatabaseRows([
            GenericFoodMatch(candidate: try FakeResolver.candidate("tfda:X0001", preparation: .raw, basis: .per100Grams, energy: 380, evidenceIDs: []),
                             isExactName: true),
            GenericFoodMatch(candidate: try FakeResolver.candidate("tfda:X0001", preparation: .raw, basis: .per100Grams, energy: 380, evidenceIDs: []),
                             isExactName: false, personalDatabase: PersonalFoodDatabaseMatchContext(step: .concept, isGenericReference: true))])
        XCTAssertEqual(kept.count, 1)
        XCTAssertTrue(kept[0].isExactName)
        XCTAssertEqual(kept[0].personalDatabase?.isGenericReference, true)
    }

    /// Qodo (PR #478): a reordered name is not exact, as the CoFID and USDA routes judge it.
    func testReorderedGenericNameIsNotExact() {
        XCTAssertFalse(PersonalFoodDatabaseFoodSearch.isExactName("Beans, baked", query: "baked beans"))
        XCTAssertTrue(PersonalFoodDatabaseFoodSearch.isExactName("Baked beans", query: "baked beans"))
        XCTAssertFalse(PersonalFoodDatabaseFoodSearch.isExactName("", query: ""))
    }

    /// Qodo (PR #478): a cold index read off the main thread is warmed, so Nutrition updates sees
    /// the installed database; a target from another release is refused against the same snapshot.
    func testReresolutionWarmsAColdIndexOffTheMainThreadAndChecksOneSnapshot() throws {
        let bytes = try Self.golden()
        let store = InMemoryPersonalFoodDatabaseStore()
        try store.install(bytes: bytes, manifest: manifest(bytes))
        let index = PersonalFoodDatabaseIndex(store: store, resolver: FakeResolver())
        let provider = PersonalFoodDatabaseReresolutionProvider(index: index, resolver: FakeResolver(), ids: IDs())
        let done = expectation(description: "background read")
        var targets: [FoodReresolutionTarget] = []
        DispatchQueue.global().async { targets = (try? provider.targets()) ?? []; done.fulfill() }
        wait(for: [done], timeout: 5)
        XCTAssertEqual(targets.count, 1, "the cold index was warmed off the main thread")
        let stale = FoodReresolutionTarget(sourceRelease: FakeResolver.release,
                                           methodVersion: try LedgerText(PersonalFoodDatabaseCandidateBuilder.methodVersion))
        XCTAssertFalse(try provider.targets().contains(stale))
    }
}
