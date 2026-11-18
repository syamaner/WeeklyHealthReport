@testable import FoodLedgerDomain
import Foundation
import XCTest

/// Label photo estimates (docs/personal-food-catalogue-off-estimates-v1-phase.md section 6, tests 1
/// to 5 and 10): the shared synthetic fixtures in `docs/fixtures/personal-food-database-estimates-v3`,
/// which the skill's `test_photo_estimates.py --verify` also reads. Each reject fixture gives exactly
/// the manifest's codes, in order, from both checkers. Synthetic data only.
final class PersonalFoodDatabaseCodecV3Tests: XCTestCase {
    static let fixtures = PersonalFoodDatabaseCodecTests.repoRoot
        .appendingPathComponent("docs/fixtures/personal-food-database-estimates-v3")

    struct Manifest: Decodable {
        let schema: String
        let golden: String
        let photo_rule_codes: [String]
        let reject: [String: [String]]
        let accept: [String]
    }

    static func manifest() throws -> Manifest {
        try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: fixtures.appendingPathComponent("manifest.json")))
    }

    static func fixture(_ name: String) throws -> Data { try Data(contentsOf: fixtures.appendingPathComponent(name)) }

    func codes(_ data: Data) -> [String] {
        switch PersonalFoodDatabaseCodec.decode(data) {
        case .success: []
        case let .failure(rejection): rejection.codes.map(\.rawValue)
        }
    }

    func testEveryRejectFixtureGivesExactlyItsCodesInOrder() throws {
        let m = try Self.manifest()
        XCTAssertEqual(m.schema, PersonalFoodDatabaseSchema.estimatesV3.rawValue)
        XCTAssertGreaterThanOrEqual(m.reject.count, 23)
        for (file, expected) in m.reject.sorted(by: { $0.key < $1.key }) {
            XCTAssertEqual(codes(try Self.fixture(file)), expected, file)
        }
    }

    func testTheGoldenAndAcceptFilesDecodeAndCarryThePhotoEstimates() throws {
        let m = try Self.manifest()
        for file in [m.golden] + m.accept {
            XCTAssertEqual(codes(try Self.fixture(file)), [], file)
        }
        guard case let .success(file) = PersonalFoodDatabaseCodec.decode(try Self.fixture(m.golden)) else {
            return XCTFail("golden rejected")
        }
        XCTAssertEqual(file.schema, .estimatesV3)
        let photos = file.entries.flatMap(\.estimatedNutrients).filter { $0.evidence.sourceType == .productDatasetPhoto }
        XCTAssertEqual(photos.count, 2)
        XCTAssertTrue(photos.allSatisfy { $0.evidence.quality != .high && $0.evidence.pageAccess == .directRead })
    }

    func testThePhotoCodesAreV3OnlyAndMatchTheManifest() throws {
        let m = try Self.manifest()
        XCTAssertEqual(Set(PersonalFoodDatabaseRuleCode.estimatesV3Only.map(\.rawValue)), Set(m.photo_rule_codes))
        XCTAssertTrue(PersonalFoodDatabaseRuleCode.estimatesV3Only.isDisjoint(with: PersonalFoodDatabaseRuleCode.estimatesOnly))
        // The estimates v2 fixtures never get a photo code.
        let v2 = try PersonalFoodDatabaseCodecEstimatesTests.manifest()
        for expected in v2.reject.values {
            XCTAssertTrue(Set(expected.codes).isDisjoint(with: m.photo_rule_codes))
        }
    }

    func testOneTokenListPerCatalogueSchema() {
        XCTAssertFalse(PersonalFoodDatabaseEstimateSourceType.allowed(catalogue: .estimatesV2).contains(.productDatasetPhoto))
        XCTAssertTrue(PersonalFoodDatabaseEstimateSourceType.allowed(catalogue: .estimatesV3).contains(.productDatasetPhoto))
        XCTAssertEqual(PersonalFoodDatabaseEstimateSourceType.estimatesV2List.count, 3)
        XCTAssertTrue(PersonalFoodDatabaseSchema.estimatesV3.carriesEstimates)
    }

    func testThePhotoAddressForm() {
        let ok = "https://images.openfoodfacts.org/images/products/000/000/000/0024/nutrition_en.1.400.jpg"
        XCTAssertTrue(PersonalFoodDatabasePhotoAddress.isPhoto(ok))
        XCTAssertTrue(PersonalFoodDatabasePhotoAddress.isPhoto("https://images.openfoodfacts.org/images/products/29308750/n.jpg"))
        for bad in [ok + "?a=1", ok + "#b", ok.replacingOccurrences(of: "images.open", with: "static.open"),
                    ok.replacingOccurrences(of: ".org/", with: ".org:443/"),
                    "https://images.openfoodfacts.org/images/products/n.jpg",
                    "https://images.openfoodfacts.org/images/products/12/",
                    "https://images.openfoodfacts.org/images/products/1a/n.jpg"] {
            XCTAssertFalse(PersonalFoodDatabasePhotoAddress.isPhoto(bad), bad)
        }
    }

    /// Test 10: a stored manifest record keeps the photo rules.
    func testAStoredPhotoRecordKeepsItsRules() throws {
        let m = try Self.manifest()
        guard case let .success(file) = PersonalFoodDatabaseCodec.decode(try Self.fixture(m.golden)),
              let photo = file.entries.flatMap(\.estimatedNutrients).first(where: { $0.evidence.sourceType == .productDatasetPhoto })
        else { return XCTFail("no photo estimate") }
        let wire = ApprovedEstimateCaptureManifest.Evidence(photo.evidence)
        XCTAssertNotNil(wire.typed)
        func altered(_ change: (inout [String: Any]) -> Void) throws -> ApprovedEstimateCaptureManifest.Evidence {
            var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(wire)) as? [String: Any])
            change(&object)
            return try JSONDecoder().decode(ApprovedEstimateCaptureManifest.Evidence.self,
                                            from: JSONSerialization.data(withJSONObject: object))
        }
        XCTAssertNil(try altered { $0["source_digest"] = NSNull() }.typed)
        XCTAssertNil(try altered { $0["source_reference"] = "https://example.com/label.jpg" }.typed)
        XCTAssertNil(try altered { $0["quality"] = "high" }.typed)
        XCTAssertNil(try altered { $0["method"] = "carried_from_same_food" }.typed)
    }
}
