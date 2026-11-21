import FoodLedgerApplication
import FoodLedgerDomain
import XCTest

/// Confirm enrichment's route classification (docs/confirm-enrichment-openrouter-v1.md section 2): Open
/// Food Facts, Your food database and the bundled tables are v1 routes; a Your foods row is not.
/// Synthetic records only.
final class ConfirmEnrichmentRouteTests: XCTestCase {
    static let now = Date(timeIntervalSince1970: 1_795_000_000)

    static func release(_ id: String, sourceID: String) throws -> SourceRelease {
        SourceRelease(sourceReleaseID: try ExternalIdentifier(id), sourceID: try ExternalIdentifier(sourceID), releasedAt: now,
                      artifactHash: try SHA256Digest(String(repeating: "a", count: 64)), schemaVersion: try LedgerText("synthetic"),
                      pipelineVersion: try LedgerText("synthetic"), licence: try LedgerText("synthetic"),
                      attribution: try LedgerText("synthetic"), manifestHash: try SHA256Digest(String(repeating: "b", count: 64)))
    }

    /// One candidate whose stated energy carries `kind` provenance from `sourceID`, with `recordID`.
    static func input(sourceID: String, releaseID: String, recordID: String, provenanceRecordID: String? = nil,
                      kind: ProvenanceSourceKind, evidenceKind: CaptureKind = .genericSearch,
                      payload: CapturePayload? = nil) throws -> PopulatedFoodConfirmation {
        let evidence = try CaptureEvidence(evidenceID: LedgerID("00000000-0000-4000-8000-000000000501"), kind: evidenceKind, capturedAt: now,
            locale: LedgerText("en_GB"), captureMethod: LedgerText("synthetic_search"), captureMethodVersion: LedgerText("synthetic-v1"),
            originalPayload: payload ?? .text(LedgerText("synthetic oats")))
        let provenance = NutrientProvenance(sourceKind: kind, sourceID: try ExternalIdentifier(sourceID),
                                            sourceReleaseID: try ExternalIdentifier(releaseID),
                                            recordID: try ExternalIdentifier(provenanceRecordID ?? recordID))
        let nutrients = try NutrientSet(entries: NutrientKey.allCases.map { key in
            guard key == .energyConsumed else { return try NutrientEntry(key: key, value: .unknown(.notDeclared)) }
            let exact = try ExactNutrientValue(amount: 380, unit: key.canonicalUnit,
                sourceValue: .exact(SourceExactNutrientValue(amount: 380, unit: LedgerText("kcal"), basis: .per100Grams)),
                provenance: [provenance])
            return try NutrientEntry(key: key, value: .augmented(exact))
        })
        let identity = try DecisiveIdentity(preparation: PreparationState(kind: .unknown), bone: .unknown, skin: .unknown,
                                            drained: .unknown, packingMedium: .unknown, fortification: .unknown, servingBasis: .per100Grams)
        let candidate = try PopulatedFoodCandidate(candidate: ProviderNeutralCandidate(
            sourceReleaseID: ExternalIdentifier(releaseID), recordID: ExternalIdentifier(recordID), identity: identity,
            edibleQuantity: .unknown, nutrients: nutrients, evidenceIDs: [evidence.evidenceID]),
            name: LedgerText("Synthetic rolled oats"), brand: LedgerText("Example"), variant: LedgerText("Synthetic variant"), itemClass: .food)
        return try PopulatedFoodConfirmation(evidence: [evidence], sourceReleases: [release(releaseID, sourceID: sourceID)],
                                             candidates: [candidate], expectedIdentity: identity, expectedEdibleQuantity: .unknown)
    }

    func route(_ input: PopulatedFoodConfirmation) -> ConfirmEnrichmentPolicy.SourceRoute? {
        ConfirmEnrichmentPolicy.sourceRoute(input, candidate: input.candidates[0])
    }

    func testAnOpenFoodFactsProductIsItsOwnRoute() throws {
        XCTAssertEqual(route(try Self.input(sourceID: "open-food-facts", releaseID: "off:snapshot:synthetic", recordID: "off:gtin:0000000000001",
                                            kind: .exactProductDataset)), .openFoodFacts)
        // A barcode capture is product evidence too.
        XCTAssertEqual(route(try Self.input(sourceID: "open-food-facts", releaseID: "off:snapshot:synthetic", recordID: "off:gtin:0000000000001",
                                            kind: .exactProductDataset, evidenceKind: .barcode,
                                            payload: .barcode(value: LedgerText("0000000000001"), symbology: LedgerText("ean13")))), .openFoodFacts)
    }

    func testAYourFoodDatabaseEntryIsItsOwnRoute() throws {
        XCTAssertEqual(route(try Self.input(sourceID: PersonalFoodDatabaseRelease.sourceID, releaseID: "pfd:release:synthetic",
                                            recordID: "pfc:000000000001", kind: .exactProductDataset)), .yourFoodDatabase)
    }

    func testCoFIDSendsItsVariantAndTheOtherTablesDoNot() throws {
        XCTAssertEqual(route(try Self.input(sourceID: "uk-cofid-2021", releaseID: "cofid:synthetic", recordID: "cofid:11-001",
                                            kind: .genericCompositionDataset)), .compositionTable(sendsVariant: true))
        XCTAssertEqual(route(try Self.input(sourceID: "usda-fdc-sr-legacy", releaseID: "usda:synthetic", recordID: "usda:1001",
                                            kind: .genericCompositionDataset)), .compositionTable(sendsVariant: false))
        XCTAssertEqual(route(try Self.input(sourceID: "tfda-taiwan", releaseID: "tfda:synthetic", recordID: "tfda:A001",
                                            kind: .genericCompositionDataset)), .compositionTable(sendsVariant: false))
        XCTAssertEqual(route(try Self.input(sourceID: "ciqual", releaseID: "ciqual:synthetic", recordID: "ciqual:1001",
                                            kind: .genericCompositionDataset)), .compositionTable(sendsVariant: false))
    }

    func testAYourFoodsRowIsNotARoute() throws {
        // A Your foods row from a rescan keeps the product's provenance but is never enriched in v1.
        XCTAssertNil(route(try Self.input(sourceID: "open-food-facts", releaseID: "off:snapshot:synthetic",
                                          recordID: "personal-library:00000000-0000-4000-8000-000000000009",
                                          provenanceRecordID: "off:gtin:0000000000001", kind: .exactProductDataset)))
        XCTAssertNil(route(try Self.input(sourceID: "uk-cofid-2021", releaseID: "cofid:synthetic",
                                          recordID: "personal-library:00000000-0000-4000-8000-000000000010",
                                          provenanceRecordID: "cofid:11-001", kind: .genericCompositionDataset)))
    }

    func testAnUnclassifiedSourceIsNotARoute() throws {
        XCTAssertNil(route(try Self.input(sourceID: "synthetic-other-source", releaseID: "other:synthetic",
                                          recordID: "other:1", kind: .exactProductDataset)))
    }
}
