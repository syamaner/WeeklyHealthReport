@testable import FoodLedgerDomain
import Foundation
import XCTest

/// Estimates on catalogue v2 (docs/personal-food-catalogue-estimates-v2-proposal.md): the shared
/// synthetic fixtures in `docs/fixtures/personal-food-database-estimates-v2`, which the skill's
/// `test_export_check.py` also reads. Codec fixtures give exactly the manifest's codes, in order,
/// from both checkers; importer fixtures pass the codec. Synthetic data only.
final class PersonalFoodDatabaseCodecEstimatesTests: XCTestCase {
    static let fixtures = PersonalFoodDatabaseCodecTests.repoRoot
        .appendingPathComponent("docs/fixtures/personal-food-database-estimates-v2")

    struct Manifest: Decodable {
        struct Case: Decodable {
            let stage: String
            let codes: [String]
        }
        struct URLs: Decodable {
            let accept: [String]
            let reject: [String]
            let open_food_facts: [String]
        }
        let schema: String
        let golden: String
        let reject: [String: Case]
        let accept: [String: String]
        let rule_codes: [String]
        let estimates_only_rule_codes: [String]
        let importer_rule_codes: [String]
        let urls: URLs
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

    func testEveryCodecFixtureGivesExactlyItsCodesInOrder() throws {
        let m = try Self.manifest()
        XCTAssertEqual(m.schema, PersonalFoodDatabaseSchema.estimatesV2.rawValue)
        let codec = m.reject.filter { $0.value.stage == "codec" }
        XCTAssertGreaterThanOrEqual(codec.count, 60)
        for (file, expected) in codec.sorted(by: { $0.key < $1.key }) {
            XCTAssertEqual(codes(try Self.fixture(file)), expected.codes, file)
        }
    }

    func testImporterFixturesGoldenAndAcceptFilesPassTheCodec() throws {
        let m = try Self.manifest()
        let importer = m.reject.filter { $0.value.stage == "importer" }
        XCTAssertGreaterThanOrEqual(importer.count, 17)
        for file in [m.golden] + m.accept.keys.sorted() + importer.keys.sorted() {
            XCTAssertEqual(codes(try Self.fixture(file)), [], file)
        }
        // A codec rejection never carries an importer code.
        let importerCodes = Set(m.importer_rule_codes)
        for expected in m.reject.values where expected.stage == "codec" {
            XCTAssertTrue(importerCodes.isDisjoint(with: expected.codes))
        }
    }

    func testRuleCodeEnumEqualsTheManifestAndTheOlderListsAreSubsets() throws {
        let m = try Self.manifest()
        // The label photo codes belong to estimates v3 files alone (PersonalFoodDatabaseCodecV3Tests).
        let upToV2 = Set(PersonalFoodDatabaseRuleCode.allCases).subtracting(PersonalFoodDatabaseRuleCode.estimatesV3Only)
        XCTAssertEqual(Set(upToV2.map(\.rawValue)), Set(m.rule_codes))
        XCTAssertEqual(Set(PersonalFoodDatabaseRuleCode.estimatesOnly.map(\.rawValue)), Set(m.estimates_only_rule_codes))
        XCTAssertEqual(PersonalFoodDatabaseRuleCode.importerOnly.map(\.rawValue), m.importer_rule_codes)
        let v2 = try PersonalFoodDatabaseCodecV2Tests().manifest()
        XCTAssertEqual(Set(upToV2.map(\.rawValue)).subtracting(m.estimates_only_rule_codes), Set(v2.rule_codes))
    }

    func testAnEstimatesFileIsNeverReadUnderAnOlderSchemaAndTheReverse() throws {
        // Contract section 2: v1 and v2 goldens keep their verdicts, and gain exactly `top-keys`
        // when they carry `estimate_evidence`.
        for name in ["personal-food-database-v1", "personal-food-database-v2"] {
            let url = PersonalFoodDatabaseCodecTests.repoRoot.appendingPathComponent("docs/fixtures/\(name)/golden.json")
            let data = try Data(contentsOf: url)
            XCTAssertEqual(codes(data), [], name)
            var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            object["estimate_evidence"] = [Any]()
            XCTAssertEqual(codes(try JSONSerialization.data(withJSONObject: object)), ["top-keys"], name)
        }
    }

    func testPageURLGrammarMatchesTheSharedList() throws {
        let urls = try Self.manifest().urls
        func host(_ s: String) -> [UInt8]? { PersonalFoodDatabaseEstimateChecker.pageHost(PFDText(bytes: Array(s.utf8))) }
        XCTAssertGreaterThanOrEqual(urls.reject.count, 20)
        for url in urls.accept {
            let h = try XCTUnwrap(host(url), url)
            XCTAssertFalse(PersonalFoodDatabaseEstimateChecker.isOpenFoodFactsHost(h), url)
        }
        for url in urls.reject { XCTAssertNil(host(url), url) }
        for url in urls.open_food_facts {
            XCTAssertTrue(PersonalFoodDatabaseEstimateChecker.isOpenFoodFactsHost(try XCTUnwrap(host(url), url)), url)
        }
    }

    func testGoldenDecodesToTypedEstimatesBoundToTheirEvidence() throws {
        let file = try PersonalFoodDatabaseCodec.decode(try Self.fixture("golden.json")).get()
        XCTAssertEqual(file.schema, .estimatesV2)
        let estimates = file.entries.flatMap { entry in entry.estimatedNutrients.map { (entry, $0) } }
        XCTAssertEqual(estimates.count, 11)
        for (entry, estimate) in estimates {
            XCTAssertEqual(estimate.evidence.entryID, entry.id)
            XCTAssertEqual(estimate.evidence.nutrient, estimate.key)
            XCTAssertEqual(estimate.unit, estimate.key.canonicalUnit)
            XCTAssertFalse(entry.labelNutrients.contains { $0.key == estimate.key })
            XCTAssertEqual(estimate.evidence.sourceType == .nationalComposition, estimate.evidence.compositionSource != nil)
            XCTAssertEqual(estimate.evidence.sourceType == .nationalComposition, estimate.evidence.pageAccess == nil)
        }
        let fish = try XCTUnwrap(file.entries.first { $0.title == "Synthetic Tinned Fish" })
        let protein = try XCTUnwrap(fish.estimatedNutrients.first { $0.key == .protein })
        XCTAssertTrue(fish.isOwnRecord(protein.evidence))
        XCTAssertEqual(protein.evidence.quality, .high)
        XCTAssertEqual(protein.evidence.method, .carriedFromSameFood)
        // A quantified zero stays a zero; an entry with no estimate has none.
        XCTAssertEqual(fish.estimatedNutrients.first { $0.key == .sugar }?.value, 0)
        XCTAssertEqual(file.entries.first { $0.title == "Synthetic Example Oats" }?.estimatedNutrients, [])
        let crisps = try XCTUnwrap(file.entries.first { $0.title == "Synthetic Crisps" })
        let sodium = try XCTUnwrap(crisps.estimatedNutrients.first { $0.key == .sodium })
        XCTAssertEqual(sodium.evidence.derivation, PersonalFoodDatabaseEstimateDerivation(
            transformID: "salt_to_sodium_v1", version: "pasted-label-conversions-v1", sourceValue: 1.25, sourceUnit: "g"))
        XCTAssertEqual(sodium.evidence.pageAccess, .indexedCopy)
        XCTAssertFalse(crisps.isOwnRecord(sodium.evidence))
    }

    func testNoSimilarFoodEstimateCanBeHighAndTheCeilingsAreOneRule() {
        typealias C = PersonalFoodDatabaseEstimateChecker
        func ceiling(_ method: String, _ basis: String, access: String? = nil, national: Bool = true, own: Bool = true)
            -> PersonalFoodDatabaseEstimateQuality {
            C.ceiling(method: PFDText(bytes: Array(method.utf8)), stateBasis: PFDText(bytes: Array(basis.utf8)),
                      pageAccess: access.map { PFDText(bytes: Array($0.utf8)) }, national: national, own: own)
        }
        XCTAssertEqual(ceiling("carried_from_same_food", "source_states_it"), .high)
        XCTAssertEqual(ceiling("direct", "source_states_it", access: "direct_read", national: false, own: false), .high)
        for basis in ["source_states_it", "stated_assumption"] {
            XCTAssertEqual(ceiling("carried_from_similar_food", basis), .medium)
            XCTAssertEqual(ceiling("derived", basis, access: "direct_read", national: false, own: false), .medium)
        }
        XCTAssertEqual(ceiling("carried_from_same_food", "stated_assumption"), .medium)
        XCTAssertEqual(ceiling("carried_from_same_food", "source_states_it", own: false), .medium)
        XCTAssertEqual(ceiling("direct", "source_states_it", access: "indexed_copy", national: false, own: false), .medium)
        for method in PersonalFoodDatabaseEstimateMethod.allCases {
            XCTAssertEqual(ceiling(method.rawValue, "unknown"), .low)
        }
        // Own merge amendment G4: an own merge record the app does not merge is at most `medium`, and
        // `unknown` still gives `low`.
        func ownMerge(_ basis: String) -> PersonalFoodDatabaseEstimateQuality {
            C.ceiling(method: PFDText(bytes: Array("carried_from_same_food".utf8)), stateBasis: PFDText(bytes: Array(basis.utf8)),
                      pageAccess: nil, national: true, own: true, ownMerge: true)
        }
        XCTAssertEqual(ownMerge("source_states_it"), .medium)
        XCTAssertEqual(ownMerge("stated_assumption"), .medium)
        XCTAssertEqual(ownMerge("unknown"), .low)
        // Composite web amendment G5: a national record (any method, G1) or a web page carried from a
        // similar food is at most `low` on a composite dish; a page about this product and a label photo
        // keep their ceilings.
        func composite(_ method: String, national: Bool = false, photo: Bool = false, webSimilar: Bool = false)
            -> PersonalFoodDatabaseEstimateQuality {
            C.ceiling(method: PFDText(bytes: Array(method.utf8)), stateBasis: PFDText(bytes: Array("source_states_it".utf8)),
                      pageAccess: national ? nil : PFDText(bytes: Array("direct_read".utf8)), national: national,
                      own: national, photo: photo, composite: true, webSimilar: webSimilar)
        }
        for method in PersonalFoodDatabaseEstimateMethod.allCases {
            XCTAssertEqual(composite(method.rawValue, national: true), .low)
        }
        XCTAssertEqual(composite("carried_from_similar_food", webSimilar: true), .low)
        XCTAssertEqual(composite("direct"), .high)
        XCTAssertEqual(composite("carried_from_same_food"), .high)
        XCTAssertEqual(composite("derived"), .medium)
        XCTAssertEqual(composite("carried_from_similar_food", photo: true), .medium)
    }

    func testBothIdentityComparisonsCoverTheSameFacets() throws {
        // Every decisive facet `IdentityCompatibility` reports, apart from serving basis and edible
        // quantity (separate estimate rules), is one this comparison can report.
        func identity(_ kind: PreparationKind, bone: BoneState, skin: SkinState, drained: DrainedState, packing: String,
                      fortification: FortificationState) throws -> DecisiveIdentity {
            try DecisiveIdentity(preparation: PreparationState(kind: kind), bone: bone, skin: skin, drained: drained,
                                 packingMedium: .named(LedgerText(packing)), fortification: fortification, servingBasis: .per100Grams)
        }
        let a = try identity(.cooked, bone: .boneless, skin: .skinless, drained: .drained, packing: "brine", fortification: .unfortified)
        let b = try identity(.raw, bone: .withBone, skin: .skinOn, drained: .undrained, packing: "oil", fortification: .fortified)
        let quantity = EdibleQuantityIdentity.known(try PositiveQuantity(value: 100, unit: .grams), conversionVersionID: nil)
        let strict = IdentityCompatibility.contradictions(between: a, and: b, expectedEdibleQuantity: quantity,
                                                          candidateEdibleQuantity: quantity)
        XCTAssertEqual(EstimateIdentityComparison.contradictions(record: a, confirmed: b), strict)
        XCTAssertEqual(strict, EstimateIdentityComparison.facets)
        XCTAssertEqual(Set(IdentityContradiction.allCases).subtracting(EstimateIdentityComparison.facets), [.servingBasis, .edibleQuantity])
        XCTAssertEqual(EstimateIdentityComparison.contradictions(record: a, confirmed: a), [])
    }

    func testUnknownNeverContradictsAndAsSoldAgreesWithRawBothWays() throws {
        func state(_ kind: PreparationKind, _ method: String? = nil) throws -> PreparationState {
            try PreparationState(kind: kind, method: method.map { try LedgerText($0) })
        }
        typealias C = EstimateIdentityComparison
        for kind in [PreparationKind.asSold, .raw, .cooked, .reheated, .unknown] {
            XCTAssertFalse(C.preparationContradicts(try state(.unknown), try state(kind)))
            XCTAssertFalse(C.preparationContradicts(try state(kind), try state(.unknown)))
        }
        XCTAssertFalse(C.preparationContradicts(try state(.asSold), try state(.raw)))
        XCTAssertFalse(C.preparationContradicts(try state(.raw), try state(.asSold)))
        XCTAssertTrue(C.preparationContradicts(try state(.asSold), try state(.cooked)))
        XCTAssertTrue(C.preparationContradicts(try state(.raw), try state(.cooked)))
        XCTAssertTrue(C.preparationContradicts(try state(.cooked), try state(.reheated)))
        XCTAssertTrue(C.preparationContradicts(try state(.named, "grilled"), try state(.named, "fried")))
        XCTAssertFalse(C.preparationContradicts(try state(.named, "grilled"), try state(.named, "grilled")))
        XCTAssertTrue(C.preparationContradicts(try state(.named, "grilled"), try state(.cooked)))
    }
}
