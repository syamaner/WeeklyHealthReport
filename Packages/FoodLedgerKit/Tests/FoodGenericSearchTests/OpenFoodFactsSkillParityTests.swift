import CryptoKit
import Foundation
@testable import FoodGenericSearch
import FoodLedgerApplication
import FoodLedgerDomain
import XCTest

/// Open Food Facts parity (personal-food-catalogue-import-v1 section 9, import v2 section 5; phase 1 plan 2.1 item 6,
/// 5.1 item 11).
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
/// Since import v2 (docs/personal-food-catalogue-import-v2.md) the port follows `off-product-projection-v6` too: the
/// panel wins over a contradicting pack, and a single per-serving panel is scaled to per 100, so those cases are ordinary
/// parity cases, mirrored one for one in `test_off_rules.py`. The plausibility check covers bound ends as well, so the
/// port refuses exactly the records the app declines, although it leaves the bounds themselves out.
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

    func testPer100GramPanelOnVolumeProductUsesThePanel() throws {
        // off-product-projection-v6, "the panel wins": a lone per 100 g panel on a volume pack keeps its own basis.
        let input = try assertPanelWins(modern(per: "100g", quantity: "1 l"), basis: .per100Grams)
        guard case let .augmented(sodium) = value(input, .sodium) else { return XCTFail("Expected exact sodium") }
        XCTAssertEqual(sodium.provenance.first?.transforms.map(\.transformID.value), ["mass-g-to-mg"], "no scaling")
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

    func testMassPackWithALonePer100MillilitrePanelUsesThePanel() throws {
        try assertPanelWins(modern(per: "100ml", quantity: "500 g"), basis: .per100Millilitres)
    }

    @discardableResult
    private func assertPanelWins(_ product: [String: Any], basis expected: ResolutionBasis,
                                 file: StaticString = #filePath, line: UInt = #line) throws -> PopulatedFoodConfirmation {
        let input = try admitted(product, file: file, line: line)
        XCTAssertEqual(basis(input), expected, file: file, line: line)
        assertProjection(input, "off-product-projection-v6", file: file, line: line)
        return input
    }

    private func assertProjection(_ input: PopulatedFoodConfirmation, _ version: String,
                                  file: StaticString = #filePath, line: UInt = #line) {
        guard let release = input.sourceReleases.first else { return XCTFail("Expected a release", file: file, line: line) }
        XCTAssertEqual(release.pipelineVersion.value, version, file: file, line: line)
        XCTAssertTrue(release.sourceReleaseID.value.contains(":\(version):"), file: file, line: line)
    }

    // MARK: off-product-projection-v6 per-serving panels, the same cases as `serving()` in test_off_rules.py

    private func serving(quantity: String? = "500 g", perQuantity: Any? = 28, perUnit: Any? = "g",
                         sodium: (Double, String) = (0.4, "g"), extra: [[String: Any]] = [],
                         modifier: (String, Double)? = nil, energy: Double = 100) -> [String: Any] {
        var nutrients: [String: Any] = ["energy-kcal": ["value": energy, "unit": "kcal"],
                                        "sodium": ["value": sodium.0, "unit": sodium.1]]
        if let modifier { nutrients["sugars"] = ["value": modifier.1, "unit": "g", "modifier": modifier.0] }
        var panel: [String: Any] = ["source": "packaging", "per": "serving", "preparation": "as_sold", "nutrients": nutrients]
        if let perQuantity { panel["per_quantity"] = perQuantity }
        if let perUnit { panel["per_unit"] = perUnit }
        var product: [String: Any] = ["code": "00000017", "product_name": "Synthetic bar", "nutrition": ["input_sets": [panel] + extra]]
        if let quantity { product["quantity"] = quantity }
        return product
    }

    private func perServing(_ value: Double, _ unit: QuantityUnit) throws -> ResolutionBasis {
        .perServing(try PositiveQuantity(value: value, unit: unit))
    }

    func testNumericServingScaledWithTransformAndPerServingSource() throws {
        let input = try admitted(serving(sodium: (0.112, "mg")))
        XCTAssertEqual(basis(input), .per100Grams)
        assertProjection(input, "off-product-projection-v6")
        guard case let .augmented(energy) = value(input, .energyConsumed) else { return XCTFail("Expected exact energy") }
        XCTAssertEqual(energy.amount, 100 * 100 / 28, accuracy: 1e-9)
        XCTAssertEqual(energy.provenance.first?.transforms.map(\.transformID.value), ["off-serving-to-100"])
        XCTAssertEqual(energy.sourceValue, .exact(try SourceExactNutrientValue(amount: 100, unit: LedgerText("kcal"),
                                                                                basis: perServing(28, .grams))))
    }

    func testTextServingScaled() throws {
        let input = try admitted(serving(perQuantity: "12.5", sodium: (0.112, "mg")))
        XCTAssertEqual(exact(value(input, .energyConsumed))?.amount ?? 0, 100 * 8, accuracy: 1e-9)
        XCTAssertEqual(exact(value(input, .energyConsumed))?.sourceValue,
                       .exact(try SourceExactNutrientValue(amount: 100, unit: LedgerText("kcal"), basis: perServing(12.5, .grams))))
    }

    func testServingOfExactly100StillCarriesTheTransform() throws {
        let energy = exact(value(try admitted(serving(perQuantity: 100, sodium: (0.112, "mg"))), .energyConsumed))
        XCTAssertEqual(energy?.amount, 100)
        XCTAssertEqual(energy?.provenance.first?.transforms.map(\.transformID.value), ["off-serving-to-100"])
    }

    func testMillilitreServingOnAMassPackGivesPer100Millilitres() throws {
        let input = try admitted(serving(perQuantity: 250, perUnit: "ml", sodium: (0.112, "mg")))
        XCTAssertEqual(basis(input), .per100Millilitres)
        XCTAssertEqual(exact(value(input, .energyConsumed))?.sourceValue,
                       .exact(try SourceExactNutrientValue(amount: 100, unit: LedgerText("kcal"), basis: perServing(250, .millilitres))))
        XCTAssertTrue(input.candidates.first?.variant?.value.contains("scaled from a 250 ml serving") == true)
    }

    func testSodiumInGramsGivesTheTwoTransformChainInOrder() throws {
        guard case let .augmented(sodium) = value(try admitted(serving(sodium: (0.112, "g"))), .sodium) else {
            return XCTFail("Expected exact sodium")
        }
        XCTAssertEqual(sodium.provenance.first?.transforms.map(\.transformID.value), ["mass-g-to-mg", "off-serving-to-100"])
        XCTAssertEqual(sodium.amount, 0.112 * 1000 * (100 / 28), accuracy: 1e-9)
        XCTAssertEqual(sodium.sourceValue, .exact(try SourceExactNutrientValue(amount: 0.112, unit: LedgerText("g"),
                                                                                basis: perServing(28, .grams))))
    }

    func testTwoServingPanelsRefused() throws {
        var product = serving()
        var nutrition = product["nutrition"] as! [String: Any]
        var sets = nutrition["input_sets"] as! [[String: Any]]
        var second = sets[0]; second["per_quantity"] = 30
        sets.append(second); nutrition["input_sets"] = sets; product["nutrition"] = nutrition
        XCTAssertEqual(try run(product), .insufficientData)
    }

    func testServingPanelBesideAPer100PanelIsIgnored() throws {
        let input = try admitted(serving(extra: [["source": "packaging", "per": "100g", "preparation": "as_sold",
                                                  "nutrients": ["energy-kcal": ["value": 400, "unit": "kcal"]]]]))
        XCTAssertEqual(exact(value(input, .energyConsumed))?.amount, 400)
        XCTAssertEqual(exact(value(input, .energyConsumed))?.provenance.first?.transforms, [])
        assertProjection(input, "off-product-projection-v5")
    }

    func testMalformedServingQuantitiesRefused() throws {
        let bad: [Any] = [0, -5, true, "1e2", "+5", "112\n", "1234567", "12.5000", "", [28]]
        for quantity in bad {
            XCTAssertEqual(try run(serving(perQuantity: quantity)), .insufficientData, "per_quantity \(quantity)")
        }
        XCTAssertEqual(try run(serving(perQuantity: nil)), .insufficientData, "per_quantity absent")
    }

    func testServingUnitsOtherThanGramsOrMillilitresRefused() throws {
        for unit: Any? in ["oz", nil, "G", 1] {
            XCTAssertEqual(try run(serving(perUnit: unit)), .insufficientData, "per_unit \(String(describing: unit))")
        }
    }

    func testImplausibleScaledExactValueRefused() throws {
        XCTAssertEqual(try run(serving(perQuantity: 1, energy: 10)), .insufficientData)
    }

    func testImplausibleScaledBoundEndRefused() throws {
        XCTAssertEqual(try run(serving(perQuantity: 1, modifier: ("<", 101), energy: 5)), .insufficientData)
    }

    func testPlausibleScaledBoundIsABoundNeverExact() throws {
        // The port leaves it out (no bounds in the catalogue); the app keeps a scaled bound.
        let sugar = value(try admitted(serving(sodium: (0.112, "mg"), modifier: ("<", 0.5))), .sugar)
        XCTAssertNil(exact(sugar))
        guard case let .bounded(bound) = sugar else { return XCTFail("Expected a bounded sugar value in the app") }
        XCTAssertEqual(bound.upper ?? 0, 0.5 * 100 / 28, accuracy: 1e-9)
    }

    func testScaleOverflowRefused() throws {
        XCTAssertEqual(try run(serving(perQuantity: 1e-300, energy: 1e300)), .insufficientData)
    }

    /// Mirrors the port's large-number cases (Qodo local review): a value that overflows only when
    /// scaled declines the record; one that overflows before scaling is unknown and the rest stays.
    func testLargeValuesFollowTheAppsDoubleArithmetic() throws {
        XCTAssertEqual(try run(serving(perQuantity: 1e-10, energy: 1e300)), .insufficientData)
        let plain = try admitted(modern(sodium: (1e306, "g")))
        XCTAssertEqual(value(plain, .sodium), .unknown(.missingConversion))
        XCTAssertEqual(exact(value(plain, .energyConsumed))?.amount, 370)
        XCTAssertEqual(value(try admitted(serving(sodium: (1e306, "g"))), .sodium), .unknown(.missingConversion))
    }

    func testTwoPer100PanelsContradictingThePackRefused() throws {
        var product = modern(per: "100g", quantity: "1 l")
        var nutrition = product["nutrition"] as! [String: Any]
        var sets = nutrition["input_sets"] as! [[String: Any]]
        sets.append(sets[0]); nutrition["input_sets"] = sets; product["nutrition"] = nutrition
        XCTAssertEqual(try run(product), .insufficientData)
    }

    func testLegacyRecordNeverScaled() throws {
        XCTAssertEqual(try run(legacy(["nutrition_data_per": "serving", "serving_quantity": 28])), .insufficientData)
    }

    func testV5AdmissionKeepsV5AndNoServing() throws {
        let input = try admitted(modern())
        assertProjection(input, "off-product-projection-v5")
        guard case let .augmented(sodium) = value(input, .sodium), case let .exact(source) = sodium.sourceValue else {
            return XCTFail("Expected exact sodium")
        }
        XCTAssertEqual(source.basis, .per100Grams)
    }

    // MARK: Cross-route: a catalogue v2 entry gives the barcode route's own provenance

    /// The v2 golden's "Synthetic Serving Bar" is what the skill writes for this record (export
    /// `build_round_trip` in test_export_check.py). Through the database candidate builder its values,
    /// source values, per-serving basis and transforms equal the app's barcode projection of the record.
    func testCatalogueV2EntryMatchesTheBarcodeRouteProvenance() throws {
        let product: [String: Any] = ["code": "00000017", "product_name": "Synthetic bar", "quantity": "84 g",
            "nutrition": ["input_sets": [["source": "packaging", "per": "serving", "preparation": "as_sold",
                "per_quantity": "28", "per_unit": "g", "nutrients": [
                    "energy-kcal": ["value": 100, "unit": "kcal"], "proteins": ["value": 2.8, "unit": "g"],
                    "sodium": ["value": 0.112, "unit": "g"]]]]]]
        let barcode = try admitted(product)
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("docs/fixtures/personal-food-database-v2/golden.json")
        let bytes = try Data(contentsOf: url)
        let file = try PersonalFoodDatabaseCodec.decode(bytes).get()
        let entry = try XCTUnwrap(file.entries.first { $0.title == "Synthetic Serving Bar" })
        let digest = try SHA256Digest(SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined())
        let release = try PersonalFoodDatabaseRelease.sourceRelease(fileSHA256: digest, generated: file.generated, schema: file.schema)
        let built = try XCTUnwrap(PersonalFoodDatabaseCandidateBuilder.build(entry: entry, file: file, databaseRelease: release,
                                                                            record: nil, evidenceIDs: [], score: 1))
        for key in [NutrientKey.energyConsumed, .protein, .sodium] {
            let app = try XCTUnwrap(exact(value(barcode, key)), "\(key)")
            let database = try XCTUnwrap(exact(built.candidate.candidate.nutrients.entries.first { $0.key == key }?.value), "\(key)")
            XCTAssertEqual(database.amount, app.amount, "\(key)")
            XCTAssertEqual(database.unit, app.unit, "\(key)")
            XCTAssertEqual(database.sourceValue, app.sourceValue, "\(key)")
            XCTAssertEqual(database.provenance.first?.transforms, app.provenance.first?.transforms, "\(key)")
            XCTAssertEqual(database.provenance.first?.sourceKind, app.provenance.first?.sourceKind, "\(key)")
        }
        XCTAssertTrue(barcode.candidates.first?.variant?.value.contains("scaled from a 28 g serving") == true)
        XCTAssertTrue(built.candidate.candidate.matchMetadata?.materialDifferences.map(\.value)
            .contains("Some values scaled from a 28 g serving") == true)
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
