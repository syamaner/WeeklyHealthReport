import Foundation
@testable import FoodGenericSearch
import FoodLedgerApplication
import FoodLedgerDomain
import XCTest

/// Open Food Facts parity (personal-food-catalogue-import-v1 section 9; phase 1 plan 2.1 item 6, 5.1 item 11).
///
/// Reproduces every check in `.agents/skills/personal-food-catalogue/scripts/test_off_rules.py` (the Python port,
/// `off_rules.py`) against the app's own `OpenFoodFactsLookup.project`, using synthetic v3.6 product records only.
/// "Admitted" in the port means `.candidate` here; "refused" (None) means `.insufficientData`; "left out" (key absent)
/// means an `.unknown` entry.
///
/// Known, documented difference (contract section 4, last bullet): a "<" or ">" value becomes a bound in the app, while
/// the catalogue v1 format has no bounded state, so the skill leaves that nutrient out. The parity check for that case
/// asserts that the app gives a bounded value, never an exact one.
///
/// Second known difference: the skill's port stays on `off-product-projection-v5`, because the catalogue codec accepts
/// only v4 and v5 releases. The app's v6 (docs/off-barcode-candidate-plan-v1.md) only admits records v5 refuses (a per
/// serving panel, or a lone per 100 panel that contradicts the pack) and projects every v5 admission unchanged, so the
/// two cases where the port refuses and the app now admits assert the app's v6 result.
///
/// Skill-only checks with no app equivalent:
/// - "release fields are a function of its ID (retrieved date in both)": the `pfc-off:` release form and its
///   `released_at` string are defined by the catalogue contract, not by the app, whose release ID is
///   `off:snapshot:...:retrieved:<epoch seconds>`. The parts both share (pipeline version and the projection version
///   inside the release ID) are asserted in the v5 basis cases below.
/// The four `R.load` cache cases are mapped to the app's response `status` / `warnings` checks in `lookup`.
final class OpenFoodFactsSkillParityTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)
    private let gtin = "00000000000017"

    // MARK: Synthetic records, the same shapes as `legacy()` and `modern()` in test_off_rules.py

    private func legacy(_ over: [String: Any] = [:]) -> [String: Any] {
        var product: [String: Any] = ["code": "0000000000017", "product_name": "Synthetic oats", "quantity": "500 g",
            "nutrition_data_per": "100g",
            "nutriments": ["energy-kcal_100g": 370, "energy-kcal_unit": "kcal", "fat_100g": 7, "fat_unit": "g",
                           "sodium_100g": 0.4, "sodium_unit": "mg", "calcium_100g": 0.05, "calcium_unit": "mg"]]
        product.merge(over) { _, new in new }
        return product
    }

    private func modern(per: Any = "100g", quantity: Any? = "500 g", sodium: (Double, String) = (0.4, "g"),
                        modifier: String? = nil) -> [String: Any] {
        var nutrients: [String: Any] = ["energy-kcal": ["value": 370, "unit": "kcal"],
                                        "sodium": ["value": sodium.0, "unit": sodium.1]]
        if let modifier { nutrients["sugars"] = ["value": 0.5, "unit": "g", "modifier": modifier] }
        var product: [String: Any] = ["code": "00000017", "product_name": "Synthetic drink",
            "nutrition": ["input_sets": [["source": "packaging", "per": per, "preparation": "as_sold", "nutrients": nutrients]]]]
        if let quantity { product["quantity"] = quantity }
        return product
    }

    private func evidence() throws -> CaptureEvidence {
        let barcode = try LedgerText("0000000000017")
        return try CaptureEvidence(evidenceID: LedgerID("00000000-0000-0000-0000-000000000001"), kind: .barcode,
            capturedAt: now, locale: LedgerText("en_GB"), captureMethod: LedgerText("synthetic"),
            captureMethodVersion: LedgerText("v1"), originalPayload: .barcode(value: barcode, symbology: LedgerText("ean-13")))
    }

    /// Round-trips through JSON so numbers and booleans arrive as `NSNumber`, exactly as from `JSONSerialization`.
    private func run(_ product: [String: Any]) throws -> PackagedFoodLookupOutcome {
        let artifact = try JSONSerialization.data(withJSONObject: product, options: .sortedKeys)
        let decoded = try XCTUnwrap(JSONSerialization.jsonObject(with: artifact) as? [String: Any])
        return try OpenFoodFactsLookup.project(product: decoded, artifact: artifact, gtin: LedgerText(gtin),
            evidence: evidence(), retrievedAt: now)
    }

    private func admitted(_ product: [String: Any], file: StaticString = #filePath, line: UInt = #line) throws -> PopulatedFoodConfirmation {
        guard case let .candidate(input) = try run(product) else {
            XCTFail("Expected the record to be admitted", file: file, line: line)
            throw XCTSkip("not admitted")
        }
        return input
    }

    private func value(_ input: PopulatedFoodConfirmation, _ key: NutrientKey) -> NutrientValue? {
        input.candidates.first?.candidate.nutrients.entries.first(where: { $0.key == key })?.value
    }

    private func isUnknown(_ value: NutrientValue?) -> Bool {
        if case .unknown = value { return true }
        return false
    }

    private func exact(_ value: NutrientValue?) -> ExactNutrientValue? {
        switch value {
        case let .augmented(exact), let .measured(exact): exact
        default: nil
        }
    }

    private func basis(_ input: PopulatedFoodConfirmation) -> ResolutionBasis? {
        input.candidates.first?.candidate.identity.servingBasis
    }

    // MARK: Legacy records

    func testLegacyRecordAdmittedWithEnergyAndFat() throws {
        let input = try admitted(legacy())
        XCTAssertEqual(exact(value(input, .energyConsumed))?.amount, 370)
        XCTAssertEqual(exact(value(input, .energyConsumed))?.unit, .kilocalories)
        XCTAssertEqual(exact(value(input, .fatTotal))?.amount, 7)
        XCTAssertEqual(basis(input), .per100Grams)
    }

    func testLegacySodiumIsUnknownNeverPointFourMilligrams() throws {
        XCTAssertEqual(value(try admitted(legacy()), .sodium), .unknown(.notDeclared))
    }

    func testMicronutrientsAreNeverTaken() throws {
        XCTAssertTrue(isUnknown(value(try admitted(legacy()), .calcium)))
    }

    func testRecordIdentityIsOffGTIN14() async throws {
        // Identity in `project` comes from the caller's GTIN; `lookup` derives it from the scanned code, so both are checked.
        XCTAssertEqual(try admitted(legacy()).candidates.first?.candidate.recordID.value, "off:gtin:00000000000017")
        let outcome = try await lookup(document(status: "success", warnings: nil, product: legacy()))
        guard case let .candidate(input) = outcome else { return XCTFail("Expected candidate") }
        XCTAssertEqual(input.candidates.first?.candidate.recordID.value, "off:gtin:00000000000017")
        guard case let .augmented(energy) = value(input, .energyConsumed) else { return XCTFail("Expected exact energy") }
        XCTAssertEqual(energy.provenance.first?.recordID?.value, "off:gtin:00000000000017")
    }

    func testNonStringQuantityTreatedAsMissingWithoutCrashing() throws {
        // v3.6 can return `quantity` as a number; a legacy record then has no mass pack and is refused.
        XCTAssertEqual(try run(legacy(["quantity": 500])), .insufficientData)
    }

    func testNonStringProductNameIsRefused() throws {
        // v3.6 shape: a non-string product_name is treated as empty in the port (`name = ""`), so refused.
        XCTAssertEqual(try run(legacy(["product_name": 42])), .insufficientData)
        XCTAssertEqual(try run(modern().merging(["product_name": NSNull()]) { _, new in new }), .insufficientData)
    }

    func testNonDictionaryInputSetRefused() throws {
        var product = modern()
        product["nutrition"] = ["input_sets": [1]]
        XCTAssertEqual(try run(product), .insufficientData)
    }

    func testPerServingLegacyRecordRefused() throws {
        XCTAssertEqual(try run(legacy(["nutrition_data_per": "serving"])), .insufficientData)
    }

    func testSupplementRefused() throws {
        XCTAssertEqual(try run(legacy(["categories_tags": ["en:dietary-supplements"]])), .insufficientData)
    }

    func testCategoriesTagsAsStringOrNumberTreatedAsEmpty() throws {
        XCTAssertNotEqual(try run(legacy(["categories_tags": "en:dietary-supplements"])), .insufficientData)
        XCTAssertNotEqual(try run(legacy(["categories_tags": 7])), .insufficientData)
    }

    func testPackWithMassAndVolumeRefused() throws {
        XCTAssertEqual(try run(legacy(["quantity": "500 g / 500 ml"])), .insufficientData)
    }

    func testLegacyVolumeRecordRefused() throws {
        XCTAssertEqual(try run(legacy(["quantity": "1 l"])), .insufficientData)
    }

    // MARK: Modern input sets

    func testModernSodiumGramsToMilligramsWithTransformAndSourceValue() throws {
        guard case let .augmented(sodium) = value(try admitted(modern()), .sodium) else { return XCTFail("Expected exact sodium") }
        XCTAssertEqual(sodium.amount, 400)
        XCTAssertEqual(sodium.unit, .milligrams)
        XCTAssertEqual(sodium.provenance.first?.transforms.first?.transformID.value, "mass-g-to-mg")
        XCTAssertEqual(sodium.provenance.first?.transforms.first?.transformVersion.value, "v1")
        guard case let .exact(source) = sodium.sourceValue else { return XCTFail("Expected exact source value") }
        XCTAssertEqual(source.amount, 0.4)
        XCTAssertEqual(source.unit.value, "g")
    }

    func testVolumeProductUsesPer100MillilitreBasis() throws {
        XCTAssertEqual(basis(try admitted(modern(per: "100ml", quantity: "1 l"))), .per100Millilitres)
    }

    func testPer100GramPanelOnVolumeProductUsesThePanelInTheAppOnly() throws {
        // Known difference (off-product-projection-v6, "the panel wins"): the skill, still on v5, refuses a lone per
        // 100 g panel on a volume pack; the app admits it with the panel's own basis under a v6 release.
        try assertPanelWins(modern(per: "100g", quantity: "1 l"), basis: .per100Grams)
    }

    func testLessThanValueIsNeverExact() throws {
        // Known difference (contract section 4, last bullet): the skill leaves a "<" value out because catalogue v1
        // has no bounds; the app keeps it as an upper bound. Parity is "never exact", asserted as a bound here.
        let sugar = value(try admitted(modern(modifier: "<")), .sugar)
        XCTAssertNil(exact(sugar))
        guard case let .bounded(bound) = sugar else { return XCTFail("Expected a bounded sugar value in the app") }
        XCTAssertEqual(bound.upper, 0.5)
        XCTAssertNil(bound.lower)
        XCTAssertFalse(bound.upperClosed)
    }

    func testUnknownModifierLeftOut() throws {
        XCTAssertEqual(value(try admitted(modern(modifier: "~")), .sugar), .unknown(.noCompatibleSource))
    }

    func testNonCanonicalUnitLeftOut() throws {
        XCTAssertEqual(value(try admitted(modern(sodium: (400, "µg"))), .sodium), .unknown(.missingConversion))
    }

    func testBooleanValueRefused() throws {
        let outcome = try run(legacy(["nutriments": ["energy-kcal_100g": true, "energy-kcal_unit": "kcal"]]))
        if case let .candidate(input) = outcome {
            XCTAssertTrue(isUnknown(value(input, .energyConsumed)))
        } else {
            XCTAssertEqual(outcome, .insufficientData)
        }
    }

    // MARK: off-product-projection-v5 (#458): a panel may state its own basis when the pack does not

    func testNoRecognisedPackUsesThePanelsBasis() throws {
        let quantities: [String?] = [nil, "", "3 oz", "1 bar"]
        for quantity in quantities {
            for (per, expected) in [("100g", ResolutionBasis.per100Grams), ("100ml", .per100Millilitres)] {
                let input = try admitted(modern(per: per, quantity: quantity))
                XCTAssertEqual(basis(input), expected, "pack \(quantity ?? "absent"), panel \(per)")
                let release = try XCTUnwrap(input.sourceReleases.first)
                XCTAssertEqual(release.pipelineVersion.value, "off-product-projection-v5")
                XCTAssertTrue(release.sourceReleaseID.value.contains(":off-product-projection-v5:"))
            }
        }
    }

    func testTwoPanelsWithNoPackBasisRefused() throws {
        var product = modern(quantity: "3 oz")
        var nutrition = product["nutrition"] as! [String: Any]
        var sets = nutrition["input_sets"] as! [[String: Any]]
        var second = sets[0]; second["per"] = "100ml"
        sets.append(second); nutrition["input_sets"] = sets; product["nutrition"] = nutrition
        XCTAssertEqual(try run(product), .insufficientData)
    }

    func testLegacyRecordWithNoOrUnrecognisedPackRefused() throws {
        XCTAssertEqual(try run(legacy(["quantity": ""])), .insufficientData)
        XCTAssertEqual(try run(legacy(["quantity": "3 oz"])), .insufficientData)
    }

    func testMassPackWithALonePer100MillilitrePanelUsesThePanelInTheAppOnly() throws {
        // Known difference (off-product-projection-v6, "the panel wins"): the skill, still on v5, refuses this record.
        try assertPanelWins(modern(per: "100ml", quantity: "500 g"), basis: .per100Millilitres)
    }

    private func assertPanelWins(_ product: [String: Any], basis expected: ResolutionBasis,
                                 file: StaticString = #filePath, line: UInt = #line) throws {
        let input = try admitted(product, file: file, line: line)
        XCTAssertEqual(basis(input), expected, file: file, line: line)
        let release = try XCTUnwrap(input.sourceReleases.first, file: file, line: line)
        XCTAssertEqual(release.pipelineVersion.value, "off-product-projection-v6", file: file, line: line)
        XCTAssertTrue(release.sourceReleaseID.value.contains(":off-product-projection-v6:"), file: file, line: line)
    }

    func testMalformedPanelPerIsDeclinedNotRaised() throws {
        let malformed: [Any] = [[Any](), ["100g"], [String: Any](), ["per": "100g"], 100]
        for bad in malformed {
            XCTAssertEqual(try run(modern(per: bad, quantity: "")), .insufficientData, "per \(bad)")
        }
    }

    func testPanelUnitThatContradictsItsPerRefused() throws {
        var product = modern(quantity: "")
        var nutrition = product["nutrition"] as! [String: Any]
        var sets = nutrition["input_sets"] as! [[String: Any]]
        sets[0]["per_unit"] = "ml"; nutrition["input_sets"] = sets; product["nutrition"] = nutrition
        XCTAssertEqual(try run(product), .insufficientData)
    }

    // MARK: Cache loading (`R.load`) mapped to the app's response status and warnings checks in `lookup`
    // The port's cached product has no nutrients; here it carries the legacy fixture so that "loads" is visible as a
    // candidate and "refused" as `malformedResponse`, the error the app raises for these statuses.

    private func document(status: String, warnings: Any?, product: [String: Any]? = nil) -> [String: Any] {
        var document: [String: Any] = ["status": status, "product": product ?? legacy(["code": "00000017"])]
        if let warnings { document["warnings"] = warnings }
        return document
    }

    private func lookup(_ document: [String: Any]) async throws -> PackagedFoodLookupOutcome {
        let body = try JSONSerialization.data(withJSONObject: document, options: .sortedKeys)
        let code = try LedgerText("0000000000017")
        let request = try PackagedFoodLookupRequest(identity: BarcodeClassifier.classify(code: code, symbology: .ean13),
                                                    evidence: evidence())
        return try await OpenFoodFactsLookup(transport: ParityFixtureTransport(body: body), clock: ParityFixedClock()).lookup(request)
    }

    private func loads(status: String, warnings: Any?) async -> Bool {
        do {
            guard case .candidate = try await lookup(document(status: status, warnings: warnings)) else { return false }
            return true
        } catch {
            XCTAssertEqual(error as? OFFLookupError, .malformedResponse)
            return false
        }
    }

    func testSuccessRecordLoads() async {
        let accepted = await loads(status: "success", warnings: nil)
        XCTAssertTrue(accepted)
    }

    func testNormalisationOnlyWarningLoads() async {
        let accepted = await loads(status: "success_with_warnings",
            warnings: [["message": ["id": "different_normalized_product_code"], "impact": ["id": "none"]]])
        XCTAssertTrue(accepted)
    }

    func testAnyOtherWarningIsRefused() async {
        let accepted = await loads(status: "success_with_warnings", warnings: [["message": ["id": "x"], "impact": ["id": "warning"]]])
        XCTAssertFalse(accepted)
    }

    func testWarningsNotRecordedAreRefused() async {
        let accepted = await loads(status: "success_with_warnings", warnings: nil)
        XCTAssertFalse(accepted)
    }
}

private struct ParityFixedClock: LedgerClock { func now() -> Date { Date(timeIntervalSince1970: 1_700_000_000) } }

private struct ParityFixtureTransport: OFFProductTransport {
    let body: Data
    func product(code: String) async throws -> OFFProductResponse {
        XCTAssertEqual(code, "00000017")
        return OFFProductResponse(status: 200, body: body)
    }
}
