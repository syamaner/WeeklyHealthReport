import CryptoKit
@testable import FoodLedgerDomain
import Foundation
import XCTest

/// Import v2 (docs/personal-food-catalogue-import-v2.md): the shared synthetic v2 fixtures in
/// `docs/fixtures/personal-food-database-v2`, which the skill's `test_export_check.py` also reads, so
/// both checkers give the same verdict and rule code for every file. Synthetic data only.
final class PersonalFoodDatabaseCodecV2Tests: XCTestCase {
    static let fixtures = PersonalFoodDatabaseCodecTests.repoRoot.appendingPathComponent("docs/fixtures/personal-food-database-v2")
    /// `shasum -a 256` of the committed v2 golden.json.
    static let goldenSHA256 = "014a1ee60e810ad08f90d581e76e3ebf56e55b71612e86118bebf15af21b65e9"

    struct Manifest: Decodable {
        let schema: String
        let golden: String
        let reject: [String: String]
        let accept: [String]
        let rule_codes: [String]
        let v2_only_rule_codes: [String]
        let canonical_units: [String: String]
    }

    func manifest() throws -> Manifest {
        try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: Self.fixtures.appendingPathComponent("manifest.json")))
    }

    func fixture(_ name: String) throws -> Data { try Data(contentsOf: Self.fixtures.appendingPathComponent(name)) }

    func codes(_ data: Data) -> Set<String> {
        switch PersonalFoodDatabaseCodec.decode(data) {
        case .success: []
        case let .failure(rejection): Set(rejection.codes.map(\.rawValue))
        }
    }

    func golden() throws -> PersonalFoodDatabaseFile {
        try PersonalFoodDatabaseCodec.decode(try fixture(try manifest().golden)).get()
    }

    func testEveryRejectFixtureGivesItsRuleCode() throws {
        let m = try manifest()
        XCTAssertEqual(m.schema, PersonalFoodDatabaseSchema.v2.rawValue)
        XCTAssertGreaterThanOrEqual(m.reject.count, 28)
        for (file, code) in m.reject.sorted(by: { $0.key < $1.key }) {
            let got = codes(try fixture(file))
            XCTAssertTrue(got.contains(code), "\(file): expected \(code), got \(got.sorted())")
        }
    }

    func testGoldenAndAcceptFixturesAreAccepted() throws {
        let m = try manifest()
        XCTAssertFalse(m.accept.isEmpty)
        for file in [m.golden] + m.accept {
            XCTAssertEqual(codes(try fixture(file)), [], file)
        }
    }

    func testRuleCodesEqualThePythonChecker() throws {
        let m = try manifest()
        XCTAssertEqual(Set(PersonalFoodDatabaseRuleCode.allCases.map(\.rawValue)), Set(m.rule_codes))
        XCTAssertEqual(Set(PersonalFoodDatabaseRuleCode.v2Only.map(\.rawValue)), Set(m.v2_only_rule_codes))
        XCTAssertEqual(Dictionary(uniqueKeysWithValues: NutrientKey.allCases.map { ($0.rawValue, $0.canonicalUnit.rawValue) }),
                       m.canonical_units)
    }

    func testServingRuleValuesArePinned() {
        // Mirrored by off_rules.PLAUSIBLE_MAXIMUM, export_v1.PLAUSIBLE_MAXIMUM and SERVING_TO_100.
        XCTAssertEqual(OpenFoodFactsServingRule.plausibleMaximum(.grams), 100)
        XCTAssertEqual(OpenFoodFactsServingRule.plausibleMaximum(.milligrams), 100_000)
        XCTAssertEqual(OpenFoodFactsServingRule.plausibleMaximum(.kilocalories), 900)
        XCTAssertNil(OpenFoodFactsServingRule.plausibleMaximum(.micrograms))
        XCTAssertEqual(OpenFoodFactsServingRule.transformID, "off-serving-to-100")
        XCTAssertEqual(OpenFoodFactsServingRule.transformVersion, "v1")
        XCTAssertFalse(NutrientDerivation.calculatedTransforms.contains(NutrientDerivation.CalculatedTransformPair(
            transformID: "off-serving-to-100", transformVersion: "v1")), "a scaled value exports calculated: false")
    }

    func testGoldenDecodesScaledValuesWithTheirServing() throws {
        let file = try golden()
        XCTAssertEqual(file.schema, .v2)
        let bar = try XCTUnwrap(file.entries.first { $0.title == "Synthetic Serving Bar" })
        let serving = try PositiveQuantity(value: 28, unit: .grams)
        let energy = try XCTUnwrap(bar.labelNutrients.first { $0.key == .energyConsumed }?.value)
        XCTAssertEqual(energy.value, 100 * (100 / 28.0), accuracy: 1e-9)
        XCTAssertEqual(energy.transform, PersonalFoodDatabaseTransform(
            steps: [PersonalFoodDatabaseTransformStep(transformID: "off-serving-to-100", version: "v1")],
            sourceValue: 100, sourceUnit: "kcal", serving: serving))
        let sodium = try XCTUnwrap(bar.labelNutrients.first { $0.key == .sodium }?.value)
        XCTAssertEqual(sodium.transform?.steps.map(\.transformID), ["mass-g-to-mg", "off-serving-to-100"])
        XCTAssertEqual(sodium.transform?.sourceValue, 0.112)
        XCTAssertEqual(sodium.transform?.sourceUnit, "g")
        XCTAssertEqual(sodium.transform?.serving, serving)
        let drink = try XCTUnwrap(file.entries.first { $0.title == "Synthetic Panel Drink" })
        XCTAssertEqual(drink.basis, .per100MillilitresAsLabelled)
        XCTAssertNil(drink.labelNutrients.first?.value.transform, "the panel wins: no scaling, no transform")
        XCTAssertEqual(Set(file.sources.map(\.pipelineVersion)), ["off-product-projection-v4", "off-product-projection-v6",
                                                                   "personal-food-catalogue-skill-v1"])
    }

    func testDatabaseReleaseNamesTheV2Schema() throws {
        let bytes = try fixture("golden.json")
        let hex = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        XCTAssertEqual(hex, Self.goldenSHA256, "v2 golden.json changed; regenerate it with the skill and update the pin")
        let file = try golden()
        let release = try PersonalFoodDatabaseRelease.sourceRelease(fileSHA256: SHA256Digest(hex), generated: file.generated,
                                                                     schema: file.schema)
        XCTAssertEqual(release.schemaVersion.value, "personal-food-catalogue-v2")
        XCTAssertEqual(release.sourceReleaseID.value, "pfc:sha256:\(hex)")
        XCTAssertEqual(release.pipelineVersion.value, "pfc-resolution-v1")
    }

    func testV1RulesAreUnchangedForTheSameContentUnderV1() throws {
        // The v1 golden's content is accepted under v2, and a v6 release or a serving under v1 is not.
        let m = try manifest()
        XCTAssertTrue(m.accept.contains("accept-v1-content-under-v2.json"))
        XCTAssertTrue(codes(try fixture("reject-v1-file-citing-v6.json")).contains("source-form"))
        XCTAssertEqual(codes(try fixture("reject-v1-file-with-serving-key.json")), ["source-value"])
    }
}
