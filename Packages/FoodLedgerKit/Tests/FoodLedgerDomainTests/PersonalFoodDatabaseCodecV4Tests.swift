@testable import FoodLedgerDomain
import Foundation
import XCTest

/// Food details from the catalogue (docs/personal-food-catalogue-identity-facts-v1-amendment.md section 5,
/// contract test 1): the shared synthetic fixtures in `docs/fixtures/personal-food-database-estimates-v4`,
/// which the skill's `test_identity_facts.py --verify` also reads. Synthetic data only.
final class PersonalFoodDatabaseCodecV4Tests: XCTestCase {
    static let fixtures = PersonalFoodDatabaseCodecTests.repoRoot
        .appendingPathComponent("docs/fixtures/personal-food-database-estimates-v4")

    struct MergeCase: Decodable {
        let name: String
        let facts: [String: String]?
        let record: [String: String]
        let eligible: Bool
        let filled: [String]
    }

    struct Manifest: Decodable {
        let schema: String
        let golden: String
        let facts_rule_codes: [String]
        let reject: [String: [String]]
        let accept: [String]
        let merge_cases: [MergeCase]
    }

    static func manifest() throws -> Manifest {
        try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: fixtures.appendingPathComponent("manifest.json")))
    }

    static func fixture(_ name: String) throws -> Data { try Data(contentsOf: fixtures.appendingPathComponent(name)) }

    static func decoded(_ name: String) throws -> PersonalFoodDatabaseFile {
        guard case let .success(file) = PersonalFoodDatabaseCodec.decode(try fixture(name)) else {
            throw FoodLedgerValidationError.invalidBasis
        }
        return file
    }

    func codes(_ data: Data) -> [String] {
        switch PersonalFoodDatabaseCodec.decode(data) {
        case .success: []
        case let .failure(rejection): rejection.codes.map(\.rawValue)
        }
    }

    func testEveryRejectFixtureGivesExactlyItsCodesInOrder() throws {
        let m = try Self.manifest()
        XCTAssertEqual(m.schema, PersonalFoodDatabaseSchema.estimatesV4.rawValue)
        XCTAssertGreaterThanOrEqual(m.reject.count, 13)
        for (file, expected) in m.reject.sorted(by: { $0.key < $1.key }) {
            XCTAssertEqual(codes(try Self.fixture(file)), expected, file)
        }
        // One failing fixture per new code; an identity_facts key in v2 or v3 is item-keys only.
        for code in PersonalFoodDatabaseRuleCode.estimatesV4Only {
            XCTAssertTrue(m.reject.values.contains([code.rawValue]), code.rawValue)
        }
        XCTAssertEqual(m.reject["reject-facts-in-v3-file.json"], ["item-keys"])
        XCTAssertEqual(m.reject["reject-facts-in-v2-estimates-file.json"], ["item-keys"])
    }

    func testTheGoldenAndAcceptFilesDecodeWithTheirFacts() throws {
        let m = try Self.manifest()
        for file in [m.golden] + m.accept { XCTAssertEqual(codes(try Self.fixture(file)), [], file) }
        let file = try Self.decoded(m.golden)
        XCTAssertEqual(file.schema, .estimatesV4)
        // A v4 file needs no photo estimate.
        XCTAssertFalse(file.entries.flatMap(\.estimatedNutrients).contains { $0.evidence.sourceType == .productDatasetPhoto })
        let stated = file.entries.compactMap(\.identityFacts)
        XCTAssertEqual(stated.count, 3)
        XCTAssertTrue(stated.contains(PersonalFoodDatabaseIdentityFacts(
            preparation: .asSold, bone: .notApplicable, skin: .notApplicable, drained: .notApplicable,
            packingMedium: .notApplicable, fortification: .unfortified)))
        XCTAssertEqual(stated.first { $0.preparation == .asSold }?.packingMediumState, .named(try LedgerText("not applicable")))
    }

    func testTheFactsCodesAreV4OnlyAndMatchTheManifest() throws {
        let m = try Self.manifest()
        XCTAssertEqual(PersonalFoodDatabaseRuleCode.estimatesV4Only.map(\.rawValue).sorted(), m.facts_rule_codes.sorted())
        XCTAssertTrue(PersonalFoodDatabaseRuleCode.estimatesV4Only.isDisjoint(with: PersonalFoodDatabaseRuleCode.estimatesOnly))
        XCTAssertTrue(PersonalFoodDatabaseRuleCode.estimatesV4Only.isDisjoint(with: PersonalFoodDatabaseRuleCode.estimatesV3Only))
        let v3 = try PersonalFoodDatabaseCodecV3Tests.manifest()
        for expected in v3.reject.values { XCTAssertTrue(Set(expected).isDisjoint(with: m.facts_rule_codes)) }
    }

    func testSchemaTablesNameV4() {
        XCTAssertTrue(PersonalFoodDatabaseSchema.estimatesV4.carriesEstimates)
        XCTAssertTrue(PersonalFoodDatabaseSchema.estimatesV4.carriesIdentityFacts)
        XCTAssertFalse(PersonalFoodDatabaseSchema.estimatesV3.carriesIdentityFacts)
        XCTAssertTrue(PersonalFoodDatabaseEstimateSourceType.allowed(catalogue: .estimatesV4).contains(.productDatasetPhoto))
        XCTAssertEqual(PersonalFoodDatabaseRelease.pipelineVersion(for: .estimatesV4), "pfc-resolution-v2")
        for schema in [PersonalFoodDatabaseSchema.v1, .v2, .estimatesV2, .estimatesV3] {
            XCTAssertEqual(PersonalFoodDatabaseRelease.pipelineVersion(for: schema), "pfc-resolution-v1")
        }
    }

    /// Section 4: an all-null v4 file equals its v3 twin field by field, apart from the schema.
    func testAnAllNullV4FileEqualsItsV3Twin() throws {
        let v4 = try Self.decoded("accept-all-null-with-photo.json")
        guard case let .success(v3) = PersonalFoodDatabaseCodec.decode(try PersonalFoodDatabaseCodecV3Tests.fixture("golden.json")) else {
            return XCTFail("v3 golden rejected")
        }
        XCTAssertEqual(v4.schema, .estimatesV4)
        XCTAssertEqual(v4.entries, v3.entries)
        XCTAssertEqual(v4.sources, v3.sources)
        XCTAssertEqual(v4.genericCorpora, v3.genericCorpora)
        XCTAssertEqual(v4.generated, v3.generated)
    }

    func testTheReleaseOfAV4FileCarriesTheV2Pipeline() throws {
        let file = try Self.decoded(try Self.manifest().golden)
        let release = try PersonalFoodDatabaseRelease.sourceRelease(fileSHA256: SHA256Digest(String(repeating: "a", count: 64)),
                                                                     generated: file.generated, schema: file.schema)
        XCTAssertEqual(release.schemaVersion.value, "personal-food-catalogue-estimates-v4")
        XCTAssertEqual(release.pipelineVersion.value, "pfc-resolution-v2")
    }

    func testV3AndV4FilesRoundTripThroughTheStoredSchemaRead() throws {
        for (data, schema) in [(try Self.fixture("golden.json"), PersonalFoodDatabaseSchema.estimatesV4),
                               (try PersonalFoodDatabaseCodecV3Tests.fixture("golden.json"), .estimatesV3)] {
            XCTAssertEqual(PersonalFoodDatabaseCodec.declaredSchema(data), schema)
            guard case let .success(file) = PersonalFoodDatabaseCodec.decode(data) else { return XCTFail("rejected") }
            XCTAssertEqual(file.schema, schema)
        }
    }
}
