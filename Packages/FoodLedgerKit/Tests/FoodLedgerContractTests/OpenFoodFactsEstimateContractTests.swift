import Foundation
import FoodGenericSearch
import FoodLedgerApplication
import FoodLedgerDomain
import FoodLedgerGRDB
import FoodLedgerTestSupport
import GRDB
import XCTest

/// Open Food Facts plus generic estimate (off-label-estimate-v1, #464): the route predicate, save
/// and reopen with the stored candidate as the evidence of record, the edit recheck, the barcode
/// rescan, contract 9 and migration v9. Synthetic fixtures only: the candidates copy the Open Food
/// Facts projection's shape, with a resolved identity so the entry can be logged without a
/// correction.
final class OpenFoodFactsEstimateContractTests: XCTestCase {
    enum Route: CaseIterable { case search, barcode }

    // MARK: Fixtures

    static let releaseID = "off:snapshot:sha256:synthetic:projection:off-product-projection-v5:schema:synthetic:retrieved:1700000000"
    static let code = "4006381333931"

    static var gtin: LedgerText {
        get throws {
            guard case let .gtin(value) = try BarcodeClassifier.classify(code: LedgerText(code), symbology: .ean13) else {
                throw FoodLedgerValidationError.missingProvenance
            }
            return value
        }
    }

    static var recordID: String { get throws { "off:gtin:\(try gtin.value)" } }

    static func release() throws -> SourceRelease {
        SourceRelease(sourceReleaseID: try ExternalIdentifier(releaseID), sourceID: try ExternalIdentifier("open-food-facts"),
            releasedAt: LedgerFixtures.date, artifactHash: try SHA256Digest(String(repeating: "a", count: 64)),
            schemaVersion: try LedgerText("synthetic-off-schema"), pipelineVersion: try LedgerText("off-product-projection-v5"),
            licence: try LedgerText("ODbL 1.0 (synthetic)"), attribution: try LedgerText("Open Food Facts (synthetic)"),
            manifestHash: try SHA256Digest(String(repeating: "a", count: 64)))
    }

    static func scan() throws -> BarcodeScan {
        BarcodeScan(code: try LedgerText(code), symbology: .ean13, originalSymbology: try LedgerText("VNBarcodeSymbologyEAN13"),
                    capturedAt: LedgerFixtures.date, locale: try LedgerText("en_GB"), captureMethod: try LedgerText("visionkit"),
                    captureMethodVersion: try LedgerText("visionkit-barcode-v1"))
    }

    static func evidence(_ route: Route) throws -> CaptureEvidence {
        switch route {
        case .search:
            try CaptureEvidence(evidenceID: LedgerFixtures.id(9_400, EvidenceTag.self), kind: .genericSearch, capturedAt: LedgerFixtures.date,
                locale: LedgerText("en_GB"), captureMethod: LedgerText("off_text_search"),
                captureMethodVersion: LedgerText("off-search-candidates-v6"), originalPayload: .text(LedgerText("dark chocolate 90%")))
        case .barcode:
            try CaptureEvidence(evidenceID: LedgerFixtures.id(9_401, EvidenceTag.self), kind: .barcode, capturedAt: LedgerFixtures.date,
                locale: LedgerText("en_GB"), captureMethod: LedgerText("visionkit"), captureMethodVersion: LedgerText("visionkit-barcode-v1"),
                originalPayload: .barcode(value: LedgerText(code), symbology: LedgerText("VNBarcodeSymbologyEAN13")))
        }
    }

    static func provenance(sourceID: String = "open-food-facts", release: String = releaseID, record: String? = nil) throws -> [NutrientProvenance] {
        [NutrientProvenance(sourceKind: sourceID == "open-food-facts" ? .exactProductDataset : .genericCompositionDataset,
                            sourceID: try ExternalIdentifier(sourceID), sourceReleaseID: try ExternalIdentifier(release),
                            recordID: try ExternalIdentifier(record ?? recordID), manifestReference: try LedgerText("https://world.openfoodfacts.org/product/synthetic"))]
    }

    static func exact(_ key: NutrientKey, _ amount: Double, provenance: [NutrientProvenance]? = nil) throws -> NutrientValue {
        .augmented(try ExactNutrientValue(amount: amount, unit: key.canonicalUnit,
            sourceValue: .exact(SourceExactNutrientValue(amount: amount, unit: LedgerText(key.canonicalUnit.rawValue), basis: .per100Grams)),
            provenance: provenance ?? Self.provenance()))
    }

    /// Sodium "< 10 mg" per 100 g, as Open Food Facts states a modifier.
    static func sodiumBound() throws -> NutrientValue {
        .bounded(try NutrientBounds(lower: nil, upper: 10, lowerClosed: false, upperClosed: false, origin: .augmented, unit: .milligrams,
            sourceValue: .bounded(SourceBoundedNutrientValue(lower: nil, upper: 10, lowerClosed: false, upperClosed: false,
                                                             unit: LedgerText("mg"), basis: .per100Grams)),
            provenance: provenance()))
    }

    /// Energy, protein, fat, saturates and carbohydrate stated; sugars a stated zero; sodium a
    /// bound; fibre in a unit the reader cannot convert; every other key not declared.
    static func nutrients(fibre: NutrientValue = .unknown(.missingConversion), protein: NutrientValue? = nil) throws -> NutrientSet {
        let stated: [NutrientKey: Double] = [.energyConsumed: 598, .protein: 9, .fatTotal: 46, .fatSaturated: 28, .carbohydrates: 14, .sugar: 0]
        return try NutrientSet(entries: NutrientKey.allCases.map { key in
            if key == .fiber { return try NutrientEntry(key: key, value: fibre) }
            if key == .sodium { return try NutrientEntry(key: key, value: sodiumBound()) }
            if key == .protein, let protein { return try NutrientEntry(key: key, value: protein) }
            return try NutrientEntry(key: key, value: stated[key].map { try exact(key, $0) } ?? .unknown(.notDeclared))
        })
    }

    static func input(_ route: Route, name: String = "90% Cocoa Dark Chocolate", basis: ResolutionBasis = .per100Grams,
                      sourceID: String = "open-food-facts", nutrients: NutrientSet? = nil,
                      evidence: CaptureEvidence? = nil) throws -> PopulatedFoodConfirmation {
        let evidence = try evidence ?? Self.evidence(route)
        let identity = try DecisiveIdentity(preparation: PreparationState(kind: .asSold), bone: .notApplicable, skin: .notApplicable,
            drained: .notApplicable, packingMedium: .named(LedgerText("none")), fortification: .unfortified, servingBasis: basis)
        let quantity = try EdibleQuantityIdentity.known(PositiveQuantity(value: 100, unit: basis == .per100Millilitres ? .millilitres : .grams),
                                                        conversionVersionID: nil)
        let metadata = try CandidateMatchMetadata(methodVersion: LedgerText(route == .search ? "off-search-candidates-v5" : "off-product-candidates-v4"),
            score: 1, materialDifferences: [LedgerText("Community product data; check name, package and nutrition basis. Missing values remain unknown.")],
            libraryAliases: route == .barcode ? [try BarcodeIdentity.gtin(gtin).lookupAlias] : [])
        let candidate = try PopulatedFoodCandidate(candidate: ProviderNeutralCandidate(sourceReleaseID: ExternalIdentifier(releaseID),
            recordID: ExternalIdentifier(recordID), identity: identity, edibleQuantity: quantity, nutrients: nutrients ?? Self.nutrients(),
            evidenceIDs: [evidence.evidenceID], matchMetadata: metadata),
            name: LedgerText(name), brand: LedgerText("Synthetic Chocolatier"),
            variant: LedgerText("Open Food Facts · source estimate · 100 g · per 100 g; 85% cocoa in the source text"),
            barcode: gtin, itemClass: .food, packFacts: PackFacts())
        var release = try release()
        if sourceID != "open-food-facts" {
            release = SourceRelease(sourceReleaseID: release.sourceReleaseID, sourceID: try ExternalIdentifier(sourceID), releasedAt: release.releasedAt,
                artifactHash: release.artifactHash, schemaVersion: release.schemaVersion, pipelineVersion: release.pipelineVersion,
                licence: release.licence, attribution: release.attribution, manifestHash: release.manifestHash)
        }
        return try PopulatedFoodConfirmation(evidence: [evidence], sourceReleases: [release], candidates: [candidate],
                                             expectedIdentity: identity, expectedEdibleQuantity: quantity)
    }

    static let genericReleaseID = "usda-synthetic:2018-04-01"
    static let genericRecordID = "usda-synthetic:fdc:1"

    static func genericRelease(id: String = genericReleaseID) throws -> SourceRelease {
        SourceRelease(sourceReleaseID: try ExternalIdentifier(id), sourceID: try ExternalIdentifier("usda"),
            releasedAt: LedgerFixtures.date, artifactHash: try SHA256Digest(String(repeating: "e", count: 64)),
            schemaVersion: try LedgerText("synthetic-generic-v1"), pipelineVersion: try LedgerText("synthetic-projection-v1"),
            licence: try LedgerText("synthetic"), attribution: try LedgerText("synthetic fixture"),
            manifestHash: try SHA256Digest(String(repeating: "f", count: 64)))
    }

    static func genericEvidence() throws -> CaptureEvidence {
        try CaptureEvidence(evidenceID: LedgerFixtures.id(9_900, EvidenceTag.self), kind: .genericSearch,
            capturedAt: LedgerFixtures.date, locale: LedgerText("en_GB"), captureMethod: LedgerText(LabelEstimateCandidatePool.captureMethod),
            captureMethodVersion: LedgerText(LabelEstimateCandidatePool.version), originalPayload: .text(LedgerText("dark chocolate 90%")))
    }

    /// A bundled 70 to 85% row, the owner-approved estimate for 86 to 99% by its pinned record ID.
    static func generic(iron: Double = 11.9) throws -> PopulatedFoodCandidate {
        let record = LabelEstimateCompatibility.nearestBandRecordID
        let values: [NutrientKey: Double] = [.energyConsumed: 600, .protein: 7.8, .fatTotal: 43, .sugar: 24, .fiber: 10.9, .sodium: 20, .iron: iron, .magnesium: 228]
        let nutrients = try NutrientSet(entries: NutrientKey.allCases.map { key in
            try NutrientEntry(key: key, value: values[key].map {
                try exact(key, $0, provenance: provenance(sourceID: "usda", release: genericReleaseID, record: record))
            } ?? .unknown(.notDeclared))
        })
        return try PopulatedFoodCandidate(candidate: ProviderNeutralCandidate(sourceReleaseID: ExternalIdentifier(genericReleaseID),
            recordID: ExternalIdentifier(record), identity: LedgerFixtures.identity(), edibleQuantity: .unknown,
            nutrients: nutrients, evidenceIDs: [genericEvidence().evidenceID]), name: LedgerText("Chocolate, dark, 70-85% cacao solids"), itemClass: .food)
    }

    static func choice(percent: Double = 90, generic: PopulatedFoodCandidate? = nil) throws -> LabelEstimateChoice {
        LabelEstimateChoice(generic: try generic ?? Self.generic(), evidence: [try genericEvidence()],
                            sourceRelease: try genericRelease(), cocoaPercent: percent, origin: .name)
    }

    static func service(_ harness: TestHarness) throws -> FoodConfirmationService {
        try FoodConfirmationService(ledger: LedgerFixtures.service(harness.committer), reader: harness.reader,
            clock: LedgerFixtures.clock, ids: RandomLedgerIDGenerator(), digester: LedgerFixtures.digester)
    }

    static func state(_ input: PopulatedFoodConfirmation) -> FoodConfirmationState {
        var state = FoodConfirmationState(input: input, prefillSourceQuantity: false)
        FoodConfirmationReducer.reduce(state: &state, action: .setQuantity(25, .grams))
        state.answerPendingDifferences()
        FoodConfirmationReducer.reduce(state: &state, action: .accept)
        return state
    }

    static func value(_ set: NutrientSet, _ key: NutrientKey) -> NutrientValue {
        set.entries.first { $0.key == key }!.value
    }

    static func operationType(_ harness: TestHarness, _ number: Int) throws -> LedgerOperationType? {
        try harness.committer.operation(id: LedgerFixtures.operationID(number))?.operationType
    }

    // MARK: Rule 1: the predicate

    func testThePredicateAdmitsOpenFoodFactsSearchAndBarcodeCandidatesOnly() throws {
        for route in Route.allCases {
            let input = try Self.input(route)
            XCTAssertTrue(OpenFoodFactsEstimateSource.applies(input, candidate: input.candidates[0]), "\(route)")
            XCTAssertEqual(LabelEstimateOffer.route(FoodConfirmationState(input: input)), .openFoodFacts, "\(route)")
        }
        let refused: [(String, PopulatedFoodConfirmation)] = [
            ("per 100 ml", try Self.input(.search, basis: .per100Millilitres)),
            ("milk chocolate", try Self.input(.search, name: "Milk Chocolate 40% Cocoa")),
            ("white chocolate", try Self.input(.search, name: "White Chocolate")),
            ("ruby chocolate", try Self.input(.search, name: "Ruby Chocolate")),
            ("not a chocolate", try Self.input(.search, name: "Roasted Almonds")),
            ("another source", try Self.input(.search, sourceID: "openfoodfacts")),
            ("mixed provenance", try Self.input(.search, nutrients: Self.nutrients(protein: Self.exact(.protein, 9,
                provenance: Self.provenance(sourceID: "usda", release: Self.genericReleaseID, record: Self.genericRecordID))))),
            ("another record", try Self.input(.search, nutrients: Self.nutrients(protein: Self.exact(.protein, 9,
                provenance: Self.provenance(record: "off:gtin:00000000000000"))))),
            ("label evidence", try Self.input(.search, evidence: CaptureEvidence(evidenceID: LedgerFixtures.id(9_402, EvidenceTag.self),
                kind: .labelText, capturedAt: LedgerFixtures.date, locale: LedgerText("en_GB"), captureMethod: LedgerText("synthetic"),
                captureMethodVersion: LedgerText("v1"), originalPayload: .text(LedgerText("synthetic")))))
        ]
        for (name, input) in refused {
            XCTAssertFalse(OpenFoodFactsEstimateSource.applies(input, candidate: input.candidates[0]), name)
            XCTAssertFalse(LabelEstimateOffer.applies(FoodConfirmationState(input: input)), name)
        }
        // A corrected entry offers no choice.
        var corrected = Self.state(try Self.input(.search))
        let source = corrected.input.candidates[0]
        FoodConfirmationReducer.reduce(state: &corrected, action: .applyCorrection(try FoodCorrection(name: LedgerText("Renamed bar"),
            brand: nil, variant: nil, identity: source.candidate.identity, itemClass: .food, nutrients: source.candidate.nutrients,
            reason: LedgerText("Synthetic rename"))))
        XCTAssertFalse(LabelEstimateOffer.admitsChoice(corrected))
        XCTAssertThrowsError(try FoodConfirmationService(ledger: LedgerFixtures.service(InMemoryFoodLedgerStore()), reader: InMemoryFoodLedgerStore(),
            clock: LedgerFixtures.clock, ids: RandomLedgerIDGenerator(), digester: LedgerFixtures.digester)
            .save(corrected, operationID: LedgerFixtures.operationID(9_499), estimate: Self.choice())) {
            XCTAssertEqual($0 as? FoodConfirmationSaveError, .invalidLabelEstimate)
        }
    }

    func testAPer100MillilitreProductOffersNoEstimateAndTheSaveRefusesOne() throws {
        for harness in try LedgerFixtures.harnesses() {
            defer { harness.cleanup() }
            let state = Self.state(try Self.input(.search, basis: .per100Millilitres))
            XCTAssertFalse(LabelEstimateOffer.applies(state), harness.name)
            XCTAssertNil(LabelEstimateOffer.prefill(state), harness.name)
            XCTAssertThrowsError(try Self.service(harness).save(state, operationID: LedgerFixtures.operationID(9_498), estimate: Self.choice())) {
                XCTAssertEqual($0 as? FoodConfirmationSaveError, .invalidLabelEstimate, harness.name)
            }
        }
    }

    // MARK: Rule 3: the merge fills every unknown reason

    func testTheMergeFillsEveryUnknownReasonAndKeepsEveryProductValue() throws {
        let stated: [NutrientKey: Double] = [.energyConsumed: 598, .protein: 9, .sugar: 0]
        let product = try NutrientSet(entries: NutrientKey.allCases.map { key in
            switch key {
            case .fiber: try NutrientEntry(key: key, value: .unknown(.missingConversion))
            case .iron: try NutrientEntry(key: key, value: .unknown(.noCompatibleSource))
            // Legacy sodium _100g is never read; it is unknown as not declared.
            case .sodium: try NutrientEntry(key: key, value: .unknown(.notDeclared))
            case .fatTotal: try NutrientEntry(key: key, value: Self.sodiumBound().reboundedForTest(key))
            default: try NutrientEntry(key: key, value: stated[key].map { try Self.exact(key, $0) } ?? .unknown(.notDeclared))
            }
        })
        let generic = try Self.generic().candidate.nutrients
        let result = try XCTUnwrap(LabelEstimateMerge.merge(label: product, labelBasis: .per100Grams, generic: generic, genericBasis: .per100Grams))
        XCTAssertEqual(result.filledKeys, [.fiber, .sodium, .iron, .magnesium].sorted { a, b in
            NutrientKey.allCases.firstIndex(of: a)! < NutrientKey.allCases.firstIndex(of: b)! })
        for key in result.filledKeys {
            XCTAssertEqual(Self.value(result.nutrients, key), Self.value(generic, key), "\(key) is the generic value, marked augmented")
        }
        for key in [NutrientKey.energyConsumed, .protein, .sugar, .fatTotal] {
            XCTAssertEqual(Self.value(result.nutrients, key), Self.value(product, key), "\(key): a product value, a zero or a bound, is kept")
        }
        XCTAssertEqual(Self.value(result.nutrients, .zinc), .unknown(.notDeclared), "unknown in both stays unknown")
    }

    // MARK: Rule 4: pre-fill from the product name only

    func testThePrefillReadsTheProductNameOnlyAndThePastedLabelPrefillIsUnchanged() throws {
        func prefill(_ name: String) throws -> (value: Double, origin: CocoaPercentOrigin)? {
            LabelEstimateOffer.prefill(FoodConfirmationState(input: try Self.input(.search, name: name)))
        }
        XCTAssertEqual(try prefill("90% Cocoa Dark Chocolate")?.value, 90)
        XCTAssertEqual(try prefill("90% Cocoa Dark Chocolate")?.origin, .name)
        XCTAssertEqual(try prefill("95% Dark Chocolate")?.value, 95)
        XCTAssertEqual(try prefill("95% Dark Chocolate")?.origin, .name)
        XCTAssertNil(try prefill("Dark chocolate with almonds"), "the variant's 85% source text is never read")
        XCTAssertNil(LabelEstimateOffer.prefill(FoodConfirmationState(input: try Self.input(.search, basis: .per100Millilitres))))
        // The shared label pre-fill (pasted labels and photos) keeps its readings.
        XCTAssertEqual(LabelEstimateCompatibility.prefill(name: "90% Cocoa Dark Chocolate", pastedText: nil)?.value, 90)
        XCTAssertNil(LabelEstimateCompatibility.prefill(name: "95% Dark Chocolate", pastedText: nil))
        XCTAssertNil(LabelEstimateCompatibility.prefill(name: "Dark chocolate with almonds", pastedText: nil))
        XCTAssertEqual(LabelEstimateCompatibility.prefill(name: "Synthetic dark chocolate", pastedText: "Cocoa solids: 72% minimum")?.origin, .pastedText)
    }

    // MARK: Rules 2 and 3: save and reopen

    func testALayeredOpenFoodFactsEntrySavesV4KeepsEveryProductValueAndReopens() throws {
        for harness in try LedgerFixtures.harnesses() {
            defer { harness.cleanup() }
            for (offset, route) in Route.allCases.enumerated() {
                let input = try Self.input(route)
                let product = input.candidates[0].candidate
                let service = try Self.service(harness)
                let saved = try service.save(Self.state(input), operationID: LedgerFixtures.operationID(9_410 + offset), estimate: Self.choice())
                XCTAssertEqual(try Self.operationType(harness, 9_410 + offset), .confirmFoodV4, "\(route) \(harness.name)")
                let layer = try XCTUnwrap(saved.estimate)
                XCTAssertEqual(saved.candidateDecision.candidate, product, "the product candidate is stored verbatim")
                let generic = try Self.generic().candidate.nutrients
                // Every Open Food Facts value stays, including a stated zero and a bound.
                for key in [NutrientKey.energyConsumed, .protein, .fatTotal, .fatSaturated, .carbohydrates, .sugar, .sodium] {
                    XCTAssertEqual(Self.value(saved.resolutionVersion.nutrients, key), Self.value(product.nutrients, key), "\(key) \(route)")
                }
                // Unknown keys are filled whatever the reason; keys neither source has stay unknown.
                XCTAssertEqual(Self.value(saved.resolutionVersion.nutrients, .fiber), Self.value(generic, .fiber), "missing conversion filled")
                XCTAssertEqual(Self.value(saved.resolutionVersion.nutrients, .iron), Self.value(generic, .iron), "not declared filled")
                XCTAssertEqual(Self.value(saved.resolutionVersion.nutrients, .zinc), .unknown(.notDeclared))
                XCTAssertEqual(try harness.reader.foodConfirmation(logItemID: saved.logItem.logItemID), saved, "\(route) \(harness.name)")
                let reopened = try XCTUnwrap(service.reopen(logItemID: saved.logItem.logItemID), "\(route) \(harness.name)")
                XCTAssertEqual(reopened.reopened?.estimate, layer)
                XCTAssertEqual(reopened.input.candidates[0].candidate, product)
                XCTAssertTrue(FoodEntryEstimateStatus.isPartlyEstimated(saved))
                XCTAssertEqual(try service.isEstimate(saved), false, "a product source is not a generic estimate")
                let detail = try XCTUnwrap(SavedFoodEntryDetail(stored: saved, isEstimate: false, history: []).labelEstimate)
                XCTAssertEqual(detail.route, .openFoodFacts)
                XCTAssertEqual(detail.estimatedKeys, [.fiber, .iron, .magnesium])
                XCTAssertEqual(detail.originalReasons, [.fiber: .missingConversion, .iron: .notDeclared, .magnesium: .notDeclared])
            }
        }
    }

    func testAnOpenFoodFactsEntryWithoutALayerSavesAndReopensAsBefore() throws {
        for harness in try LedgerFixtures.harnesses() {
            defer { harness.cleanup() }
            for (offset, route) in Route.allCases.enumerated() {
                let input = try Self.input(route)
                let service = try Self.service(harness)
                let saved = try service.save(Self.state(input), operationID: LedgerFixtures.operationID(9_420 + offset))
                XCTAssertEqual(try Self.operationType(harness, 9_420 + offset), .confirmFood, "\(route) \(harness.name)")
                XCTAssertNil(saved.estimate)
                XCTAssertEqual(saved.assertions, [])
                XCTAssertEqual(saved.resolutionVersion.decisionIDs, [saved.candidateDecision.candidateDecisionID])
                XCTAssertEqual(saved.resolutionVersion.sourceReleaseIDs.map(\.value), [Self.releaseID])
                XCTAssertEqual(saved.resolutionVersion.nutrients, input.candidates[0].candidate.nutrients)
                XCTAssertNotNil(try service.reopen(logItemID: saved.logItem.logItemID))
                XCTAssertNil(SavedFoodEntryDetail(stored: saved, isEstimate: false, history: []).labelEstimate)
            }
        }
    }

    func testATamperedResolutionGenericRowOrCocoaPercentageFailsReopen() throws {
        for harness in try LedgerFixtures.harnesses() {
            defer { harness.cleanup() }
            let saved = try Self.service(harness).save(Self.state(Self.input(.search)), operationID: LedgerFixtures.operationID(9_430),
                                                       estimate: Self.choice())
            let layer = try XCTUnwrap(saved.estimate)
            let product = try Self.input(.search).candidates[0].candidate
            let altered = try Self.generic(iron: 12.5)
            let alteredDecision = try CandidateDecision(candidateDecisionID: layer.candidateDecision.candidateDecisionID, candidate: altered.candidate,
                expectedIdentity: layer.candidateDecision.expectedIdentity, expectedEdibleQuantity: layer.candidateDecision.expectedEdibleQuantity,
                requestedOutcome: .selectedForEstimate, assertionID: layer.candidateDecision.assertionID, createdAt: layer.candidateDecision.createdAt)
            let asserted = try XCTUnwrap(saved.assertions.first?.labelEstimate)
            let merged = try XCTUnwrap(LabelEstimateMerge.merge(label: product.nutrients, labelBasis: .per100Grams,
                                                                generic: altered.candidate.nutrients, genericBasis: .per100Grams)).nutrients
            let tampered: [(String, StoredFoodConfirmation)] = [
                ("altered resolution", try Self.rebuilt(saved, nutrients: merged)),
                ("resolution equal to the product only", try Self.rebuilt(saved, nutrients: product.nutrients)),
                ("altered generic row", try Self.rebuilt(saved, estimate: StoredLabelEstimate(candidateDecision: alteredDecision,
                    evidence: layer.evidence, sourceRelease: layer.sourceRelease))),
                ("cocoa percentage outside every admitted band", try Self.rebuilt(saved, assertions: [Self.reasserted(saved.assertions[0],
                    LabelEstimateAssertion(cocoaPercent: 60, cocoaPercentOrigin: asserted.cocoaPercentOrigin,
                        compatibilityVersion: asserted.compatibilityVersion, mergeVersion: asserted.mergeVersion,
                        genericName: asserted.genericName, genericVariant: asserted.genericVariant))])),
                ("cocoa assertion removed", try Self.rebuilt(saved, assertions: [])),
                ("layer removed, assertion kept", try Self.rebuilt(saved, estimate: .some(nil)))
            ]
            for (name, stored) in tampered {
                XCTAssertThrowsError(try Self.service(harness, stored).reopen(logItemID: saved.logItem.logItemID), "\(name) (\(harness.name))") {
                    guard case .integrityFailure = $0 as? FoodLedgerStoreError else { return XCTFail("\(name): \($0)") }
                }
            }
            XCTAssertNotNil(try Self.service(harness, saved).reopen(logItemID: saved.logItem.logItemID), "control (\(harness.name))")
        }
    }

    func testAnEditRechecksTheLayerAndACorrectionDropsIt() throws {
        for harness in try LedgerFixtures.harnesses() {
            defer { harness.cleanup() }
            let service = try Self.service(harness)
            let saved = try service.save(Self.state(Self.input(.barcode)), operationID: LedgerFixtures.operationID(9_440), estimate: Self.choice())
            var edit = try XCTUnwrap(service.reopen(logItemID: saved.logItem.logItemID))
            FoodConfirmationReducer.reduce(state: &edit, action: .setQuantity(40, .grams))
            let edited = try service.save(edit, operationID: LedgerFixtures.operationID(9_441))
            XCTAssertEqual(try Self.operationType(harness, 9_441), .confirmFoodV4, harness.name)
            XCTAssertEqual(edited.estimate, saved.estimate, harness.name)
            // An edit whose stored resolution no longer matches the layer is refused before saving.
            let product = try Self.input(.barcode).candidates[0].candidate
            var stale = FoodConfirmationState(input: edit.input, reopened: try Self.rebuilt(edited, nutrients: product.nutrients))
            stale.decision = .accepted
            FoodConfirmationReducer.reduce(state: &stale, action: .setQuantity(50, .grams))
            XCTAssertThrowsError(try service.save(stale, operationID: LedgerFixtures.operationID(9_442)), harness.name) {
                XCTAssertEqual($0 as? FoodConfirmationSaveError, .invalidLabelEstimate, harness.name)
            }
            XCTAssertNil(try Self.operationType(harness, 9_442), "nothing is written (\(harness.name))")
            var corrected = try XCTUnwrap(service.reopen(logItemID: saved.logItem.logItemID))
            let source = corrected.input.candidates[0]
            FoodConfirmationReducer.reduce(state: &corrected, action: .applyCorrection(try FoodCorrection(name: LedgerText("Renamed bar"),
                brand: nil, variant: nil, identity: source.candidate.identity, itemClass: .food, nutrients: source.candidate.nutrients,
                reason: LedgerText("Synthetic rename; the product values are unchanged."))))
            let dropped = try service.save(corrected, operationID: LedgerFixtures.operationID(9_443))
            XCTAssertEqual(try Self.operationType(harness, 9_443), .confirmFood, harness.name)
            XCTAssertNil(dropped.estimate, harness.name)
            XCTAssertEqual(dropped.resolutionVersion.nutrients, source.candidate.nutrients, harness.name)
            XCTAssertNotNil(try service.reopen(logItemID: saved.logItem.logItemID), harness.name)
        }
    }

    // MARK: Decision 6: food details on an Open Food Facts product

    /// A product exactly as `OpenFoodFactsLookup` projects it: every food detail unknown, so Log
    /// needs a food details correction. Fibre is listed in a unit the reader cannot convert.
    static func lookedUp() async throws -> PopulatedFoodConfirmation {
        let product: [String: Any] = ["code": code, "product_name": "90% Cocoa Dark Chocolate", "brands": "Synthetic Chocolatier",
            "quantity": "100 g", "nutrition_data_per": "100g", "nutriments": [
                "energy-kcal_100g": 598, "energy-kcal_unit": "kcal", "proteins_100g": 9, "proteins_unit": "g", "fat_100g": 46, "fat_unit": "g",
                "saturated-fat_100g": 28, "saturated-fat_unit": "g", "carbohydrates_100g": 14, "carbohydrates_unit": "g",
                "sugars_100g": 7, "sugars_unit": "g", "fiber_100g": 1, "fiber_unit": "oz"]]
        let body = try JSONSerialization.data(withJSONObject: ["status": "success", "product": product], options: .sortedKeys)
        let request = PackagedFoodLookupRequest(identity: try BarcodeClassifier.classify(code: LedgerText(code), symbology: .ean13),
                                                evidence: try evidence(.barcode))
        guard case let .candidate(input) = try await OpenFoodFactsLookup(transport: FixedOFFTransport(body: body), clock: LedgerFixtures.clock)
            .lookup(request) else { throw OFFLookupError.malformedResponse }
        return input
    }

    /// The food details sheet's correction for the selected product: the source's nutrients, the
    /// given name and brand, and filled-in details.
    static func correction(_ state: FoodConfirmationState, name: String? = nil, nutrients: NutrientSet? = nil) throws -> FoodCorrection {
        let selected = state.selectedCandidate
        let identity = try DecisiveIdentity(preparation: PreparationState(kind: .asSold), bone: .notApplicable, skin: .notApplicable,
            drained: .notApplicable, packingMedium: .named(LedgerText("none")), fortification: .unfortified,
            servingBasis: selected.candidate.identity.servingBasis)
        return try FoodCorrection(name: name.map { try LedgerText($0) } ?? selected.name, brand: selected.brand, variant: selected.variant,
            identity: identity, itemClass: selected.itemClass, nutrients: nutrients ?? selected.candidate.nutrients,
            reason: LedgerText("Filled in the food details from the pack"))
    }

    func testAnIdentityOnlyCorrectionOfALookedUpProductKeepsTheEstimateThroughLogAndReopen() async throws {
        let input = try await Self.lookedUp()
        for harness in try LedgerFixtures.harnesses() {
            defer { harness.cleanup() }
            var state = Self.state(input)
            XCTAssertFalse(state.unresolvedIdentity.isEmpty, "the projection leaves every food detail unknown")
            XCTAssertTrue(FoodLogPolicy.requirements(state, now: LedgerFixtures.date, calendar: .current)
                .contains { if case .sourceIdentityMissing = $0 { true } else { false } }, "Log needs the food details")
            XCTAssertEqual(LabelEstimateOffer.prefill(state)?.value, 90)
            let correction = try Self.correction(state)
            XCTAssertTrue(OpenFoodFactsEstimateSource.isIdentityOnlyCorrection(correction, of: state.selectedCandidate))
            FoodConfirmationReducer.reduce(state: &state, action: .applyCorrection(correction))
            XCTAssertTrue(state.unresolvedIdentity.isEmpty)
            XCTAssertTrue(LabelEstimateOffer.admitsChoice(state), "the section stays available (\(harness.name))")
            XCTAssertEqual(LabelEstimateOffer.prefill(state)?.value, 90)
            let service = try Self.service(harness)
            let saved = try service.save(state, operationID: LedgerFixtures.operationID(9_480), estimate: Self.choice())
            XCTAssertEqual(try Self.operationType(harness, 9_480), .confirmFoodV4, harness.name)
            let layer = try XCTUnwrap(saved.estimate, harness.name)
            XCTAssertEqual(saved.productVersion.identity, correction.identity, "the corrected food details are saved")
            XCTAssertEqual(saved.candidateDecision.candidate, input.candidates[0].candidate, "the merge input is the stored candidate")
            XCTAssertEqual(saved.assertions.count, 1)
            XCTAssertNotNil(saved.assertions[0].labelEstimate, "one assertion carries the correction and the cocoa percentage")
            let product = input.candidates[0].candidate.nutrients
            XCTAssertEqual(Self.value(saved.resolutionVersion.nutrients, .protein), Self.value(product, .protein))
            XCTAssertEqual(Self.value(saved.resolutionVersion.nutrients, .fiber), Self.value(try Self.generic().candidate.nutrients, .fiber),
                           "fibre in an unconverted unit is estimated")
            XCTAssertEqual(try harness.reader.foodConfirmation(logItemID: saved.logItem.logItemID), saved, harness.name)
            var edit = try XCTUnwrap(service.reopen(logItemID: saved.logItem.logItemID), harness.name)
            XCTAssertEqual(edit.reopened?.estimate, layer)
            FoodConfirmationReducer.reduce(state: &edit, action: .setQuantity(40, .grams))
            let edited = try service.save(edit, operationID: LedgerFixtures.operationID(9_481))
            XCTAssertEqual(try Self.operationType(harness, 9_481), .confirmFoodV4, harness.name)
            XCTAssertEqual(edited.estimate, layer, harness.name)
            // A stored resolution that no longer matches still fails reopen with the corrected details.
            XCTAssertThrowsError(try Self.service(harness, Self.rebuilt(saved, nutrients: product)).reopen(logItemID: saved.logItem.logItemID)) {
                guard case .integrityFailure = $0 as? FoodLedgerStoreError else { return XCTFail("\($0)") }
            }
        }
    }

    func testACorrectionThatChangesTheNameBrandOrAValueDropsTheEstimate() async throws {
        let input = try await Self.lookedUp()
        let base = Self.state(input)
        // The same product provenance with another amount.
        guard case let .augmented(stated) = Self.value(base.selectedCandidate.candidate.nutrients, .protein) else { return XCTFail("protein") }
        let protein = NutrientValue.augmented(try ExactNutrientValue(amount: 12, unit: stated.unit, sourceValue: stated.sourceValue,
                                                                     provenance: stated.provenance))
        let other = try NutrientSet(entries: base.selectedCandidate.candidate.nutrients.entries.map {
            $0.key == .protein ? try NutrientEntry(key: .protein, value: protein) : $0
        })
        let selected = base.selectedCandidate
        let renamed = try Self.correction(base, name: "90% Cocoa Dark Chocolate Bar")
        let revalued = try Self.correction(base, nutrients: other)
        let rebranded = try FoodCorrection(name: selected.name, brand: LedgerText("Another Maker"), variant: selected.variant,
            identity: renamed.identity, itemClass: selected.itemClass, nutrients: selected.candidate.nutrients, reason: renamed.reason)
        for harness in try LedgerFixtures.harnesses() {
            defer { harness.cleanup() }
            for (offset, (name, correction)) in [("name", renamed), ("value", revalued), ("brand", rebranded)].enumerated() {
                var state = base
                XCTAssertFalse(OpenFoodFactsEstimateSource.isIdentityOnlyCorrection(correction, of: selected), name)
                FoodConfirmationReducer.reduce(state: &state, action: .applyCorrection(correction))
                XCTAssertFalse(LabelEstimateOffer.admitsChoice(state), name)
                XCTAssertThrowsError(try Self.service(harness).save(state, operationID: LedgerFixtures.operationID(9_485 + 2 * offset),
                                                                     estimate: Self.choice()), "\(name) (\(harness.name))") {
                    XCTAssertEqual($0 as? FoodConfirmationSaveError, .invalidLabelEstimate)
                }
                let plain = try Self.service(harness).save(state, operationID: LedgerFixtures.operationID(9_486 + 2 * offset))
                XCTAssertNil(plain.estimate, name)
                XCTAssertEqual(try Self.operationType(harness, 9_486 + 2 * offset), .confirmFood, "\(name) (\(harness.name))")
            }
        }
    }

    func testFortifiedOrAnotherItemClassDropsTheEstimateAndOtherFoodDetailsKeepIt() async throws {
        let base = Self.state(try await Self.lookedUp())
        let selected = base.selectedCandidate
        let basis = selected.candidate.identity.servingBasis
        func correction(preparation: PreparationKind = .asSold, bone: BoneState = .notApplicable, skin: SkinState = .notApplicable,
                        drained: DrainedState = .notApplicable, packing: PackingMediumState? = nil,
                        fortification: FortificationState = .unfortified, itemClass: ItemClass? = nil) throws -> FoodCorrection {
            try FoodCorrection(name: selected.name, brand: selected.brand, variant: LedgerText("A changed description"),
                identity: DecisiveIdentity(preparation: PreparationState(kind: preparation), bone: bone, skin: skin, drained: drained,
                    packingMedium: packing ?? .named(LedgerText("none")), fortification: fortification, servingBasis: basis),
                itemClass: itemClass ?? selected.itemClass, nutrients: selected.candidate.nutrients, reason: LedgerText("Food details"))
        }
        let kept: [(String, FoodCorrection)] = [
            ("preparation raw", try correction(preparation: .raw)), ("bone", try correction(bone: .boneless)),
            ("skin", try correction(skin: .skinless)), ("drained", try correction(drained: .undrained)),
            ("packing medium", try correction(packing: .named(LedgerText("foil")))), ("unfortified", try correction()),
            ("fortification not stated", try correction(fortification: .unknown))
        ]
        for (name, value) in kept {
            XCTAssertTrue(OpenFoodFactsEstimateSource.isIdentityOnlyCorrection(value, of: selected), name)
            var state = base
            FoodConfirmationReducer.reduce(state: &state, action: .applyCorrection(value))
            XCTAssertTrue(LabelEstimateOffer.admitsChoice(state), name)
        }
        let dropped: [(String, FoodCorrection)] = [
            ("fortified", try correction(fortification: .fortified)),
            ("supplement", try correction(itemClass: .supplement)),
            ("fortified food class", try correction(itemClass: .fortifiedFood))
        ]
        for harness in try LedgerFixtures.harnesses() {
            defer { harness.cleanup() }
            for (offset, (name, value)) in dropped.enumerated() {
                XCTAssertFalse(OpenFoodFactsEstimateSource.isIdentityOnlyCorrection(value, of: selected), name)
                var state = base
                FoodConfirmationReducer.reduce(state: &state, action: .applyCorrection(value))
                XCTAssertFalse(LabelEstimateOffer.admitsChoice(state), name)
                XCTAssertThrowsError(try Self.service(harness).save(state, operationID: LedgerFixtures.operationID(9_490 + offset),
                                                                     estimate: Self.choice()), "\(name) (\(harness.name))") {
                    XCTAssertEqual($0 as? FoodConfirmationSaveError, .invalidLabelEstimate)
                }
            }
        }
    }

    // MARK: Rule 5: barcode rescan

    func testARescanAfterAnEstimatedLogReturnsTheProductValuesAndOffersTheEstimateAgain() throws {
        for harness in try LedgerFixtures.harnesses() {
            defer { harness.cleanup() }
            let input = try Self.input(.barcode)
            let service = try Self.service(harness)
            _ = try service.save(Self.state(input), operationID: LedgerFixtures.operationID(9_450), estimate: Self.choice())
            let coordinator = BarcodeCaptureCoordinator(search: PersonalLibraryBarcodeSearch(reader: harness.reader), ids: RandomLedgerIDGenerator())
            guard case let .confirmation(route) = try coordinator.route(scan: Self.scan()) else { return XCTFail("rescan (\(harness.name))") }
            let row = route.confirmation.candidates[0].candidate
            XCTAssertEqual(row.nutrients, input.candidates[0].candidate.nutrients, "the product values only (\(harness.name))")
            XCTAssertFalse(row.nutrients.entries.flatMap(\.value.provenance).contains { $0.sourceReleaseID.value == Self.genericReleaseID },
                           "no estimated value (\(harness.name))")
            XCTAssertEqual(route.confirmation.sourceReleases.map(\.sourceReleaseID.value), [Self.releaseID], "no generic release (\(harness.name))")
            XCTAssertTrue(OpenFoodFactsEstimateSource.applies(route.confirmation, candidate: route.confirmation.candidates[0]), harness.name)
            let rescan = Self.state(route.confirmation)
            XCTAssertEqual(LabelEstimateOffer.route(rescan), .openFoodFacts, harness.name)
            let again = try service.save(rescan, operationID: LedgerFixtures.operationID(9_451), estimate: Self.choice())
            XCTAssertNotNil(again.estimate, harness.name)
            XCTAssertNotNil(try service.reopen(logItemID: again.logItem.logItemID), harness.name)
        }
    }

    // MARK: Decision 5: contract 9 and migration v9

    func testContractNineOnlyWithALayerOnAnOpenFoodFactsEntry() throws {
        for harness in try LedgerFixtures.harnesses() {
            defer { harness.cleanup() }
            let archive = try XCTUnwrap(harness.committer as? any FoodArchiveLedgerAccess)
            func generate() throws -> FoodArchiveBundle {
                try FoodArchiveGenerator().generate(state: archive.archiveState(), ledgerID: LedgerText("off-estimate"),
                    createdAt: LedgerFixtures.date, creatingActorID: LedgerFixtures.id(900, ActorTag.self))
            }
            let service = try Self.service(harness)
            _ = try service.save(Self.state(Self.input(.search)), operationID: LedgerFixtures.operationID(9_460))
            XCTAssertEqual(try FoodArchiveVerifier().verify(generate()).manifest.foodContractVersion, 6, "no layer: the floor (\(harness.name))")
            let saved = try service.save(Self.state(Self.input(.barcode)), operationID: LedgerFixtures.operationID(9_461), estimate: Self.choice())
            let bundle = try generate()
            let verified = try FoodArchiveVerifier().verify(bundle)
            XCTAssertEqual(verified.manifest.foodContractVersion, 9, harness.name)
            XCTAssertEqual(verified.manifest.migrationIdentifiers.map(\.value).last, "food-ledger-v9", harness.name)
            XCTAssertThrowsError(try CanonicalFoodProjection(records: archive.archiveState().records, foodContractVersion: 8)) {
                XCTAssertEqual($0 as? FoodArchiveError, .unsupportedFoodContract(8))
            }
            for destination in try LedgerFixtures.harnesses() {
                defer { destination.cleanup() }
                let live = try XCTUnwrap(destination.committer as? any FoodArchiveLedgerAccess)
                let importer = FoodArchiveImportService(live: live, staging: InMemoryFoodArchiveStaging())
                _ = try importer.apply(importer.dryRun(bundle))
                let again = try FoodArchiveGenerator().generate(state: live.archiveState(), ledgerID: LedgerText("off-estimate"),
                    createdAt: LedgerFixtures.date, creatingActorID: LedgerFixtures.id(900, ActorTag.self))
                XCTAssertEqual(again, bundle, "\(harness.name)->\(destination.name)")
                XCTAssertEqual(try Self.service(destination).reopen(logItemID: saved.logItem.logItemID)?.reopened?.estimate, saved.estimate,
                               "\(harness.name)->\(destination.name)")
            }
        }
        // Read from the first decision's own provenance: a transaction whose product release was
        // stored earlier still needs contract 9; a label layer stays at 8.
        for harness in try LedgerFixtures.harnesses() {
            defer { harness.cleanup() }
            let saved = try Self.service(harness).save(Self.state(Self.input(.search)), operationID: LedgerFixtures.operationID(9_465),
                                                       estimate: Self.choice())
            var mutation = LedgerMutation()
            mutation.resolutionVersions = [saved.resolutionVersion]
            mutation.candidateDecisions = [saved.candidateDecision, try XCTUnwrap(saved.estimate).candidateDecision]
            XCTAssertEqual(CanonicalFoodProjection.minimumContractVersion(for: mutation), 9, harness.name)
            mutation.candidateDecisions = [try XCTUnwrap(saved.estimate).candidateDecision]
            XCTAssertEqual(CanonicalFoodProjection.minimumContractVersion(for: mutation), 8, "first decision unknown: a layer only (\(harness.name))")
        }
    }

    func testMigrationFromAPopulatedV8StoreChangesOnlyLedgerMetadata() throws {
        XCTAssertEqual(FoodLedgerGRDBStore.schemaVersion, 9)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("off-estimate-v9-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let database = directory.appendingPathComponent("food-ledger-v1.sqlite")
        do {
            let store = try FoodLedgerGRDBStore.temporary(directory: directory)
            _ = try Self.service(TestHarness(name: "grdb", committer: store, reader: store, cleanup: {}))
                .save(Self.state(Self.input(.barcode)), operationID: LedgerFixtures.operationID(9_470))
        }
        let queue = try DatabaseQueue(path: database.path)
        try queue.write { db in
            try db.execute(sql: "DELETE FROM grdb_migrations WHERE identifier = 'v9_off_label_estimate'")
            try db.execute(sql: "UPDATE ledger_metadata SET value = 'food-ledger-v8' WHERE key = 'schema_identity'")
            try db.execute(sql: "PRAGMA user_version = 8")
        }
        let before = try Self.tableRows(queue)
        let schemaBefore = try queue.read { try String.fetchAll($0, sql: "SELECT sql FROM sqlite_master WHERE sql IS NOT NULL ORDER BY name") }
        try queue.close()
        let migrated = try FoodLedgerGRDBStore.temporary(directory: directory)
        try migrated.verifyIntegrity()
        let check = try DatabaseQueue(path: database.path)
        let after = try Self.tableRows(check)
        XCTAssertEqual(Set(before.keys.filter { before[$0] != after[$0] }), ["ledger_metadata"], "Only ledger_metadata may change")
        XCTAssertEqual(try check.read { try String.fetchAll($0, sql: "SELECT sql FROM sqlite_master WHERE sql IS NOT NULL ORDER BY name") },
                       schemaBefore, "No table, index or trigger definition changes")
        try check.read { db in
            XCTAssertEqual(try Int.fetchOne(db, sql: "PRAGMA user_version"), 9)
            XCTAssertEqual(try String.fetchOne(db, sql: "SELECT value FROM ledger_metadata WHERE key = 'schema_identity'"), "food-ledger-v9")
            XCTAssertEqual(try String.fetchAll(db, sql: "SELECT identifier FROM grdb_migrations ORDER BY rowid").last, "v9_off_label_estimate")
        }
        // A schema-8 binary declines this store before migrating (user_version above its schema).
        try check.write { db in try db.execute(sql: "PRAGMA user_version = 10") }
        XCTAssertThrowsError(try FoodLedgerGRDBStore.temporary(directory: directory)) {
            XCTAssertEqual($0 as? FoodLedgerStoreError, .unknownSchema(10))
        }
    }

    // MARK: Helpers

    static func service(_ harness: TestHarness, _ stored: StoredFoodConfirmation) throws -> FoodConfirmationService {
        try FoodConfirmationService(ledger: LedgerFixtures.service(harness.committer), reader: OneStoredReader(saved: stored),
            clock: LedgerFixtures.clock, ids: RandomLedgerIDGenerator(), digester: LedgerFixtures.digester)
    }

    static func rebuilt(_ saved: StoredFoodConfirmation, nutrients: NutrientSet? = nil, assertions: [UserAssertion]? = nil,
                        estimate: StoredLabelEstimate?? = .none) throws -> StoredFoodConfirmation {
        let version = saved.resolutionVersion
        let resolutionVersion = try NutritionResolutionVersion(resolutionVersionID: version.resolutionVersionID, resolutionID: version.resolutionID,
            ordinal: version.ordinal, methodVersion: version.methodVersion, sourceReleaseIDs: version.sourceReleaseIDs,
            nutrients: nutrients ?? version.nutrients, decisionIDs: version.decisionIDs, assertionIDs: version.assertionIDs, createdAt: version.createdAt)
        return StoredFoodConfirmation(evidence: saved.evidence, sourceReleases: saved.sourceReleases, product: saved.product,
            productVersion: saved.productVersion, resolution: saved.resolution, resolutionVersion: resolutionVersion, logItem: saved.logItem,
            logItemVersion: saved.logItemVersion, quantityConversion: saved.quantityConversion, plate: saved.plate,
            plateWeightVersion: saved.plateWeightVersion, candidateDecision: saved.candidateDecision,
            assertions: assertions ?? saved.assertions, estimate: estimate ?? saved.estimate)
    }

    static func reasserted(_ assertion: UserAssertion, _ estimate: LabelEstimateAssertion) -> UserAssertion {
        UserAssertion(assertionID: assertion.assertionID, evidenceID: assertion.evidenceID, supersedesAssertionID: assertion.supersedesAssertionID,
            author: assertion.author, createdAt: assertion.createdAt, reason: assertion.reason, claim: assertion.claim,
            confirmation: assertion.confirmation, labelEstimate: estimate)
    }

    static func tableRows(_ queue: DatabaseQueue) throws -> [String: [String]] {
        try queue.read { db in
            var result: [String: [String]] = [:]
            for table in try String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%' AND name != 'grdb_migrations'") {
                result[table] = try Row.fetchAll(db, sql: "SELECT * FROM \"\(table)\"").map { row in
                    row.columnNames.map { "\($0)=\(row[$0] as DatabaseValue)" }.joined(separator: "|")
                }.sorted()
            }
            return result
        }
    }
}

private extension NutrientValue {
    /// The fixture's "< 10" bound restated in another key's unit.
    func reboundedForTest(_ key: NutrientKey) throws -> NutrientValue {
        guard case let .bounded(bound) = self else { return self }
        return .bounded(try NutrientBounds(lower: nil, upper: 0.5, lowerClosed: false, upperClosed: false, origin: .augmented, unit: key.canonicalUnit,
            sourceValue: .bounded(SourceBoundedNutrientValue(lower: nil, upper: 0.5, lowerClosed: false, upperClosed: false,
                                                             unit: LedgerText(key.canonicalUnit.rawValue), basis: .per100Grams)),
            provenance: bound.provenance))
    }
}

/// Returns one product document, as the Open Food Facts product endpoint would.
private struct FixedOFFTransport: OFFProductTransport {
    let body: Data
    func product(code: String) async throws -> OFFProductResponse { OFFProductResponse(status: 200, body: body) }
}

/// Serves one stored aggregate, with its estimate release.
private struct OneStoredReader: FoodConfirmationReading {
    let saved: StoredFoodConfirmation
    func sourceRelease(id: ExternalIdentifier) throws -> SourceRelease? {
        (saved.sourceReleases + (saved.estimate.map { [$0.sourceRelease] } ?? [])).first { $0.sourceReleaseID == id }
    }
    func foodConfirmation(logItemID: LogItemID) throws -> StoredFoodConfirmation? { logItemID == saved.logItem.logItemID ? saved : nil }
    func foodConfirmation(logItemVersionID: LogItemVersionID) throws -> StoredFoodConfirmation? {
        logItemVersionID == saved.logItemVersion.logItemVersionID ? saved : nil
    }
    func evidence(id: EvidenceID) throws -> CaptureEvidence? { saved.evidence.first { $0.evidenceID == id } }
}
