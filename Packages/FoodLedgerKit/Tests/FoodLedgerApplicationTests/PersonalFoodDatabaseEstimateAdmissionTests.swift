import FoodLedgerApplication
import FoodLedgerDomain
import FoodLedgerTestSupport
import Foundation
import XCTest

/// The importer stage of estimates on catalogue v2 (contract section 3.1): every importer fixture of
/// `docs/fixtures/personal-food-database-estimates-v2` passes the codec and is rejected by the
/// importer with exactly its codes, against the stub lookup the manifest describes. Synthetic only.
final class PersonalFoodDatabaseEstimateAdmissionTests: XCTestCase {
    static let fixtures = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("docs/fixtures/personal-food-database-estimates-v2")

    struct Manifest: Decodable {
        struct Case: Decodable {
            let stage: String
            let codes: [String]
        }
        struct Record: Decodable {
            let source: String
            let record_id: String
            let nutrients: [String: Double?]
            let preparation: String
            let preparation_method: String?
            let fortification: String
            /// A known 100-unit edible quantity on the record's basis (100 g, or 100 mL when `basis` is
            /// `per_100_ml`); false gives 30 units.
            let per_100_g_edible: Bool
            /// `per_100_g` or `per_100_ml` (gap estimates amendment G2).
            let basis: String
            /// The entry states (`raw`, `cooked`) the skill's `merges` says this record merges into
            /// (own merge amendment G4).
            let merges_into: [String]
        }
        struct Stub: Decodable {
            let pins: [String: String]
            let records: [Record]
        }
        let golden: String
        let reject: [String: Case]
        let accept: [String: String]
        let stub_lookup: Stub
    }

    static func manifest() throws -> Manifest {
        try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: fixtures.appendingPathComponent("manifest.json")))
    }

    static func fixture(_ name: String) throws -> Data { try Data(contentsOf: fixtures.appendingPathComponent(name)) }

    /// The manifest's stub: pinned corpora and synthetic records.
    struct StubLookup: GenericRecordNutrientLookup {
        let pins: [String: String]
        let records: [String: GenericRecordFacts]

        init(_ stub: Manifest.Stub) throws {
            pins = stub.pins
            var built: [String: GenericRecordFacts] = [:]
            for record in stub.records {
                let release = try ExternalIdentifier("stub-release"), source = try ExternalIdentifier(record.source)
                let perMillilitre = record.basis == "per_100_ml"
                let entries = try NutrientKey.allCases.map { key -> NutrientEntry in
                    guard case let .some(.some(amount)) = record.nutrients[key.rawValue] else {
                        return try NutrientEntry(key: key, value: .unknown(.notDeclared))
                    }
                    let provenance = NutrientProvenance(sourceKind: .genericCompositionDataset, sourceID: source,
                        sourceReleaseID: release, recordID: try ExternalIdentifier(record.record_id))
                    return try NutrientEntry(key: key, value: .augmented(ExactNutrientValue(
                        amount: amount, unit: key.canonicalUnit,
                        sourceValue: .exact(SourceExactNutrientValue(amount: amount, unit: LedgerText(key.canonicalUnit.rawValue),
                                                                     basis: perMillilitre ? .per100Millilitres : .per100Grams)),
                        provenance: [provenance])))
                }
                let kind = try XCTUnwrap(PreparationKind(rawValue: record.preparation))
                let identity = try DecisiveIdentity(
                    preparation: PreparationState(kind: kind, method: record.preparation_method.map { try LedgerText($0) }),
                    bone: .unknown, skin: .unknown, drained: .unknown, packingMedium: .unknown,
                    fortification: try XCTUnwrap(FortificationState(rawValue: record.fortification)),
                    servingBasis: perMillilitre ? .per100Millilitres : .per100Grams)
                let quantity = try PositiveQuantity(value: record.per_100_g_edible ? 100 : 30,
                                                    unit: perMillilitre ? .millilitres : .grams)
                built["\(record.source)|\(record.record_id)"] = GenericRecordFacts(
                    nutrients: try NutrientSet(entries: entries), identity: identity,
                    edibleQuantity: .known(quantity, conversionVersionID: nil))
            }
            records = built
        }

        func record(source: PersonalFoodDatabaseGenericSource, corpusSHA256: String, recordID: String)
            -> Result<GenericRecordFacts, GenericRecordLookupFailure> {
            guard pins[source.rawValue] == corpusSHA256 else { return .failure(.corpusMismatch) }
            guard let facts = records["\(source.rawValue)|\(recordID)"] else { return .failure(.recordMissing) }
            return .success(facts)
        }
    }

    func codes(_ name: String, lookup: any GenericRecordNutrientLookup) throws -> [String] {
        let file = try PersonalFoodDatabaseCodec.decode(try Self.fixture(name)).get()
        return PersonalFoodDatabaseEstimateAdmission.codes(file: file, lookup: lookup).map(\.rawValue)
    }

    func testEveryImporterFixtureIsRejectedWithExactlyItsCodes() throws {
        let m = try Self.manifest()
        let lookup = try StubLookup(m.stub_lookup)
        let importer = m.reject.filter { $0.value.stage == "importer" }
        XCTAssertGreaterThanOrEqual(importer.count, 17)
        for (name, expected) in importer.sorted(by: { $0.key < $1.key }) {
            XCTAssertEqual(try codes(name, lookup: lookup), expected.codes, name)
        }
        XCTAssertEqual(Set(importer.values.flatMap(\.codes)), Set(PersonalFoodDatabaseRuleCode.importerOnly.map(\.rawValue)),
                       "every importer code has a fixture")
    }

    /// Own merge amendment G4: the importer's merge predicate (shared with the candidate builder) and the
    /// skill's `merges` agree on every stub record, for a raw and a cooked entry.
    func testTheMergePredicateAgreesWithTheSkillOnEveryStubRecord() throws {
        let m = try Self.manifest()
        let lookup = try StubLookup(m.stub_lookup)
        var entries: [String: PersonalFoodDatabaseEntry] = [:]
        for (state, name, title) in [("raw", "accept-own-merge-unstated-preparation-raw.json", "Synthetic Raw Greens"),
                                     ("cooked", "accept-own-merge-unstated-preparation-cooked.json", "Synthetic Cooked Rice")] {
            let file = try PersonalFoodDatabaseCodec.decode(try Self.fixture(name)).get()
            let entry = try XCTUnwrap(file.entries.first { $0.title == title })
            XCTAssertEqual(entry.genericReference?.role, .merge)
            entries[state] = entry
        }
        for record in m.stub_lookup.records {
            let facts = try XCTUnwrap(lookup.records["\(record.source)|\(record.record_id)"])
            for (state, entry) in entries {
                XCTAssertEqual(PersonalFoodDatabaseCandidateBuilder.mergeEligible(entry, facts: facts),
                               record.merges_into.contains(state), "\(record.record_id) into \(state)")
            }
        }
        XCTAssertTrue(m.stub_lookup.records.contains { !$0.merges_into.isEmpty })
    }

    func testGoldenAndAcceptFixturesPassTheImporterRules() throws {
        let m = try Self.manifest()
        let lookup = try StubLookup(m.stub_lookup)
        for name in [m.golden] + m.accept.keys.sorted() {
            XCTAssertEqual(try codes(name, lookup: lookup), [], name)
        }
    }

    func testAtZeroOnlyExactEqualityPassesAndOtherwiseHalfAPerCent() {
        typealias A = PersonalFoodDatabaseEstimateAdmission
        XCTAssertTrue(A.valueMatches(file: 0, record: 0))
        XCTAssertFalse(A.valueMatches(file: 1e-9, record: 0))
        XCTAssertFalse(A.valueMatches(file: 0, record: 1e-9))
        XCTAssertTrue(A.valueMatches(file: 18.09, record: 18))
        XCTAssertFalse(A.valueMatches(file: 18.091, record: 18))
        XCTAssertTrue(A.valueMatches(file: 17.91, record: 18))
        XCTAssertFalse(A.valueMatches(file: 17.9, record: 18))
    }

    func testWithNoLookupACompositionEstimateRejectsAndAPageOnlyFileDoesNot() throws {
        // Closed by default: no pinned corpus, so every composition estimate is `corpus-mismatch`.
        let none = GenericRecordLookupSet([:])
        let golden = try codes("golden.json", lookup: none)
        XCTAssertEqual(golden, Array(repeating: "corpus-mismatch", count: 7))
        XCTAssertEqual(try codes("accept-v2-relabelled-with-empty-estimates.json", lookup: none), [])
    }

    func testTheImporterRejectsWithImporterCodesAndKeepsTheActiveRelease() async throws {
        struct FixedClock: LedgerClock { func now() -> Date { Date(timeIntervalSince1970: 1_794_000_000) } }
        let m = try Self.manifest()
        let store = InMemoryPersonalFoodDatabaseStore()
        let importer = PersonalFoodDatabaseImporter(store: store, digester: SHA256Digester(), clock: FixedClock(),
            releases: PersonalFoodDatabaseImporterTests.Releases(), lookup: try StubLookup(m.stub_lookup))
        guard case let .added(first) = await importer.importFile(try Self.fixture("golden.json")) else {
            return XCTFail("the golden estimates file should install")
        }
        XCTAssertEqual(try store.activeRelease()?.manifest.schema, PersonalFoodDatabaseSchema.estimatesV2.rawValue)
        // Settings counts the estimated values, from the file, also on a cold start.
        XCTAssertEqual(first.estimatedValueCount, 11)
        let cold = PersonalFoodDatabaseImporter(store: store, digester: SHA256Digester(), clock: FixedClock(),
            releases: PersonalFoodDatabaseImporterTests.Releases(), lookup: try StubLookup(m.stub_lookup))
        guard case let .installed(summary) = await cold.status() else { return XCTFail("installed") }
        XCTAssertEqual(summary.estimatedValueCount, 11)
        let outcome = await importer.importFile(try Self.fixture("reject-importer-value-outside-tolerance.json"))
        XCTAssertEqual(outcome, .rejected([.valueMismatch]))
        let codec = await importer.importFile(try Self.fixture("reject-own-held-raw.json"))
        XCTAssertEqual(codec, .rejected([.estimateOwnHeld, .estimateOwnHeld, .estimateOwnHeld]))
        let ownMerge = await importer.importFile(try Self.fixture("reject-own-merge.json"))
        XCTAssertEqual(ownMerge, .rejected([.estimateOwnMerge]))
        XCTAssertEqual(try store.activeRelease()?.manifest.releaseID, first.releaseID)
        guard case .installed = await importer.status() else { return XCTFail("still installed") }

        // An importer wired without a lookup refuses the same golden file.
        let bare = PersonalFoodDatabaseImporter(store: InMemoryPersonalFoodDatabaseStore(), digester: SHA256Digester(),
            clock: FixedClock(), releases: PersonalFoodDatabaseImporterTests.Releases())
        guard case let .rejected(codes) = await bare.importFile(try Self.fixture("golden.json")) else { return XCTFail("rejected") }
        XCTAssertEqual(Set(codes), [.corpusMismatch])
    }
}
